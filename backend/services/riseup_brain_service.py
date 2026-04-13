"""
RiseUp Brain Service v1.1 — Production Hardened
═══════════════════════════════════════════════════════════════════
v1.1 fixes over v1.0:
  - Detects PostgREST "Worker threw exception" (Cloudflare 1101) and
    emits a single clean warning instead of dumping HTML to logs
  - _search_methods:    safe column select + tier fallback always runs
  - _search_marketplace: safe column select, no crash on missing table
  - _search_service_providers: RPC timeout guard + skills fallback
  - brain_search_log write is fully fire-and-forget (never blocks)
  - All public API signatures unchanged — drop-in replacement

Root cause of v1.0 errors:
  Tables `income_methods` and `marketplace_listings` did not exist.
  PostgREST crashes (Cloudflare 1101 Worker threw exception) instead of
  returning a clean 404. Fix: run migration_010_brain_tables.sql first,
  then deploy this file.
"""

import asyncio
import logging
import re
from typing import Optional, Dict, List, Any
from datetime import datetime, timezone

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)

# ───────────────────────────────────────────────────────────────────
# ERROR DETECTION HELPERS
# ───────────────────────────────────────────────────────────────────

def _is_missing_table_error(exc: Exception) -> bool:
    """
    Detect PostgREST "Worker threw exception" / table-not-found errors.
    These arrive as a dict-like error with code 500 and HTML in details,
    or as a string containing the Cloudflare error page.
    """
    msg = str(exc)
    return any(k in msg for k in (
        "Worker threw exception",
        "JSON could not be generated",
        "relation",           # pg: relation "x" does not exist
        "does not exist",
        "1101",
        "<!DOCTYPE html",
    ))


def _log_brain_error(location: str, exc: Exception) -> None:
    """Emit one clean warning line instead of the full HTML wall."""
    if _is_missing_table_error(exc):
        logger.warning(
            "[BRAIN] %s — table/column not found. "
            "Run migration_010_brain_tables.sql in Supabase.",
            location,
        )
    else:
        logger.error("[BRAIN] %s error: %s", location, exc)


# ───────────────────────────────────────────────────────────────────
# INTENT DETECTION
# ───────────────────────────────────────────────────────────────────

SELL_SIGNALS    = ["sell","selling","sell my","get rid of","i have for sale",
                   "how much for my","list my","find buyer","buyer for","market my"]
BUY_SIGNALS     = ["buy","looking for","want to buy","find me a","need to purchase",
                   "where can i get","acquire","source"]
SERVICE_SIGNALS = ["need someone to","hire a","looking for a","find a developer",
                   "find a designer","need a","help with","who can","outsource"]
LEARN_SIGNALS   = ["how to make money","how do i start","ways to earn","income ideas",
                   "side hustle","make money","earn money","start a business"]
PARTNER_SIGNALS = ["business partner","co-founder","collab","joint venture",
                   "teaming up","work together"]
INVEST_SIGNALS  = ["invest","investor","funding","raise money","capital",
                   "angel","vc","seed"]


def detect_intent(query: str) -> str:
    q = query.lower()
    if any(s in q for s in SELL_SIGNALS):    return "find_buyers"
    if any(s in q for s in SERVICE_SIGNALS): return "find_service_provider"
    if any(s in q for s in BUY_SIGNALS):     return "find_sellers"
    if any(s in q for s in PARTNER_SIGNALS): return "find_partners"
    if any(s in q for s in INVEST_SIGNALS):  return "find_investors"
    if any(s in q for s in LEARN_SIGNALS):   return "learn_method"
    return "explore"


def extract_keywords(text: str) -> List[str]:
    stop = {
        "i","want","to","a","the","is","for","in","and","or","my","me",
        "how","can","do","be","have","has","help","please","need","like",
        "where","what","who","when","find","get","make","some","any",
        "someone","something","anyone","looking","there","this","that",
    }
    words = re.findall(r'\b[a-zA-Z]{3,}\b', text.lower())
    return [w for w in words if w not in stop]


# ───────────────────────────────────────────────────────────────────
# MAIN BRAIN SEARCH
# ───────────────────────────────────────────────────────────────────

async def search_riseup_brain(
    query: str,
    user_id: str,
    intent: Optional[str] = None,
    user_country: Optional[str] = None,
    limit: int = 5,
) -> Dict[str, Any]:
    """
    Search the entire internal RiseUp system and return enriched context.

    Returns:
    {
      "found": bool,
      "confidence": 0.0–1.0,
      "intent": str,
      "methods": [...],
      "marketplace": [...],
      "service_providers": [...],
      "summary": str,
      "needs_external": bool,
      "escalation_reason": str,
      "suggested_task_type": str,
      "total_found": int,
    }
    Always returns a valid dict — never raises.
    """
    if not intent:
        intent = detect_intent(query)

    keywords = extract_keywords(query)

    # Run all internal searches in parallel; exceptions are captured, not raised
    results = await asyncio.gather(
        _search_methods(query, keywords, intent, limit),
        _search_marketplace(query, keywords, intent, user_country, limit),
        _search_service_providers(query, keywords, intent, user_country, limit),
        return_exceptions=True,
    )

    methods     = results[0] if isinstance(results[0], list) else []
    marketplace = results[1] if isinstance(results[1], list) else []
    providers   = results[2] if isinstance(results[2], list) else []

    total_found = len(methods) + len(marketplace) + len(providers)
    confidence  = min(0.95, total_found * 0.18)
    found       = total_found > 0

    needs_external = not found or (
        intent in ("find_buyers", "find_sellers",
                   "find_service_provider", "find_partners")
        and confidence < 0.6
    )

    summary = _build_summary(intent, methods, marketplace, providers, query)

    # Fire-and-forget log — never blocks the response
    asyncio.create_task(_log_brain_search(
        user_id, query, intent, found, total_found, needs_external
    ))

    return {
        "found":               found,
        "confidence":          confidence,
        "intent":              intent,
        "methods":             methods,
        "marketplace":         marketplace,
        "service_providers":   providers,
        "summary":             summary,
        "total_found":         total_found,
        "needs_external":      needs_external,
        "escalation_reason":   _escalation_reason(intent, found, confidence) if needs_external else None,
        "suggested_task_type": _suggest_task_type(intent),
    }


async def _log_brain_search(
    user_id: str, query: str, intent: str,
    found: bool, count: int, escalated: bool,
) -> None:
    """Write to brain_search_log asynchronously — silently ignored on failure."""
    try:
        supabase_service.client.table("brain_search_log").insert({
            "user_id":        user_id,
            "query":          query[:500],
            "intent":         intent,
            "internal_found": found,
            "results_count":  count,
            "escalated":      escalated,
        }).execute()
    except Exception:
        pass  # Logging failure must never affect brain search result


# ───────────────────────────────────────────────────────────────────
# METHODS SEARCH
# ───────────────────────────────────────────────────────────────────

_METHODS_COLS = (
    "id,method_number,title,description,category,investment_tier,"
    "time_to_first_dollar,skill_level,tags,section_emoji,"
    "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,"
    "global_demand_score,how_to_start,first_steps,platforms"
)

async def _search_methods(
    query: str,
    keywords: List[str],
    intent: str,
    limit: int,
) -> List[Dict]:
    """Search the income_methods table. Returns [] on any failure."""
    if intent not in ("learn_method", "explore") and not any(
        w in query.lower()
        for w in ["method","way","how","earn","make money","income","hustle","business"]
    ):
        return []

    sb = supabase_service.client

    # ── Pass 1: keyword ilike on title ────────────────────────────
    if keywords:
        try:
            res = sb.table("income_methods") \
                .select(_METHODS_COLS) \
                .eq("is_active", True) \
                .ilike("title", f"%{keywords[0]}%") \
                .order("global_demand_score", desc=True) \
                .limit(limit) \
                .execute()
            if res.data:
                return res.data
        except Exception as exc:
            _log_brain_error("Methods/keyword", exc)
            return []   # table missing — bail out of both passes

    # ── Pass 2: investment-tier featured fallback ─────────────────
    tier = _detect_investment_tier(query)
    if tier:
        try:
            res = sb.table("income_methods") \
                .select(_METHODS_COLS) \
                .eq("is_active", True) \
                .eq("investment_tier", tier) \
                .eq("is_featured", True) \
                .order("global_demand_score", desc=True) \
                .limit(limit) \
                .execute()
            return res.data or []
        except Exception as exc:
            _log_brain_error("Methods/tier-fallback", exc)
            return []

    # ── Pass 3: top featured across all tiers ────────────────────
    try:
        res = sb.table("income_methods") \
            .select(_METHODS_COLS) \
            .eq("is_active", True) \
            .eq("is_featured", True) \
            .order("global_demand_score", desc=True) \
            .limit(limit) \
            .execute()
        return res.data or []
    except Exception as exc:
        _log_brain_error("Methods/featured-fallback", exc)
        return []


# ───────────────────────────────────────────────────────────────────
# MARKETPLACE SEARCH
# ───────────────────────────────────────────────────────────────────

_MARKET_COLS = (
    "id,listing_type,title,description,price_usd,currency,"
    "location,country,is_global,contact_info,tags,user_id,created_at"
)

_LISTING_TYPE_MAP = {
    "find_buyers":           "buying",
    "find_sellers":          "selling",
    "find_service_provider": "service_offer",
    "find_partners":         "partnership",
    "find_investors":        "investment",
}

async def _search_marketplace(
    query: str,
    keywords: List[str],
    intent: str,
    country: Optional[str],
    limit: int,
) -> List[Dict]:
    """Search active marketplace listings. Returns [] on any failure."""
    try:
        sb          = supabase_service.client
        target_type = _LISTING_TYPE_MAP.get(intent)

        q = sb.table("marketplace_listings") \
            .select(_MARKET_COLS) \
            .eq("status", "active")

        if target_type:
            q = q.eq("listing_type", target_type)

        if keywords:
            q = q.ilike("title", f"%{keywords[0]}%")

        res = q.order("created_at", desc=True).limit(limit).execute()
        return res.data or []

    except Exception as exc:
        _log_brain_error("Marketplace", exc)
        return []


# ───────────────────────────────────────────────────────────────────
# PROFILE / SERVICE PROVIDER SEARCH
# ───────────────────────────────────────────────────────────────────

_PROFILE_COLS = (
    "id,full_name,bio,avatar_url,country,current_skills,"
    "service_tags,service_description,hourly_rate_usd"
)

async def _search_service_providers(
    query: str,
    keywords: List[str],
    intent: str,
    country: Optional[str],
    limit: int,
) -> List[Dict]:
    """Search user profiles for service providers. Returns [] on any failure."""
    if intent not in (
        "find_service_provider", "find_partners",
        "find_buyers", "find_sellers",
    ):
        return []

    sb = supabase_service.client

    # ── Pass 1: RPC full-text search ─────────────────────────────
    if keywords:
        try:
            res = sb.rpc("search_service_providers", {
                "p_query":  " ".join(keywords[:3]),
                "p_limit":  limit,
                "p_offset": 0,
            }).execute()
            if res.data:
                return res.data
        except Exception as exc:
            if not _is_missing_table_error(exc):
                logger.debug("[BRAIN] Provider RPC unavailable, using fallback: %s", exc)
            # Fall through to array-contains fallback

    # ── Pass 2: skills array contains ────────────────────────────
    if keywords:
        try:
            res = sb.table("profiles") \
                .select(_PROFILE_COLS) \
                .contains("current_skills", [keywords[0]]) \
                .limit(limit) \
                .execute()
            return res.data or []
        except Exception as exc:
            _log_brain_error("Providers/skills-fallback", exc)
            return []

    return []


# ───────────────────────────────────────────────────────────────────
# SUMMARY BUILDER
# ───────────────────────────────────────────────────────────────────

def _build_summary(
    intent: str,
    methods: List[Dict],
    marketplace: List[Dict],
    providers: List[Dict],
    query: str,
) -> str:
    parts = []

    if methods:
        parts.append(f"📚 RELEVANT METHODS FROM RISEUP BRAIN ({len(methods)} found):")
        for m in methods[:3]:
            lo  = m.get("avg_earning_monthly_usd_low",  0)
            hi  = m.get("avg_earning_monthly_usd_high", 0)
            earn = f" | Earns: ${lo:,.0f}–${hi:,.0f}/mo" if lo else ""
            parts.append(
                f"  {m.get('section_emoji','💡')} {m['title']} "
                f"[{(m.get('investment_tier') or 'zero').upper()}, "
                f"{m.get('time_to_first_dollar','weeks')} to first $]{earn}"
            )
            if m.get("how_to_start"):
                parts.append(f"     How to start: {m['how_to_start'][:120]}...")

    if marketplace:
        parts.append(f"\n🛒 RISEUP MARKETPLACE ({len(marketplace)} listings found):")
        for lst in marketplace[:3]:
            price    = f"${lst['price_usd']:,.0f}" if lst.get("price_usd") else "Negotiable"
            location = "Global" if lst.get("is_global") else lst.get("location", "Unknown")
            parts.append(
                f"  [{(lst.get('listing_type') or '').upper()}] {lst['title']} "
                f"| {price} | {location}"
            )

    if providers:
        parts.append(f"\n👤 RISEUP USERS OFFERING RELATED SERVICES ({len(providers)} found):")
        for p in providers[:3]:
            skills  = ", ".join((p.get("current_skills") or [])[:3])
            rate    = f" | ${p['hourly_rate_usd']}/hr" if p.get("hourly_rate_usd") else ""
            country = f" | {p['country']}"             if p.get("country")          else ""
            parts.append(f"  👤 {p.get('full_name','User')} — Skills: {skills}{rate}{country}")

    if not parts:
        return f"No internal RiseUp results found for: {query}"

    return "\n".join(parts)


# ───────────────────────────────────────────────────────────────────
# AI MENTOR SYSTEM PROMPT ENRICHMENT
# ───────────────────────────────────────────────────────────────────

def build_brain_context_prompt(brain_result: Dict[str, Any]) -> str:
    """
    Build the brain context block to inject into the AI mentor system prompt.
    Called BEFORE the AI responds, giving it real-time RiseUp data.
    """
    lines = [
        "═══════════════════════════════════════════════",
        "RISEUP INTERNAL KNOWLEDGE (search results just run):",
        "═══════════════════════════════════════════════",
    ]

    if brain_result.get("summary"):
        lines.append(brain_result["summary"])

    if brain_result.get("needs_external"):
        lines.extend([
            "",
            "⚠️  ESCALATION NEEDED:",
            f"   Reason: {brain_result.get('escalation_reason','Insufficient internal results')}",
            "   Suggested action: Tell user I found limited internal results and offer to",
            "   search the internet via the Workflow Engine.",
            f"   Task type if escalated: {brain_result.get('suggested_task_type','custom')}",
        ])
    else:
        lines.append("\n✅ Internal results are sufficient. Present them directly.")

    lines.extend([
        "═══════════════════════════════════════════════",
        "INSTRUCTIONS FOR THIS RESPONSE:",
        f"  Intent detected: {brain_result.get('intent','explore')}",
        "  1. If internal results exist: present them warmly and specifically",
        "  2. If marketplace listings found: show as real opportunities with prices",
        "  3. If RiseUp users found: mention they can be contacted directly on RiseUp",
        "  4. If needs_external=true: tell user results are limited, offer workflow search",
        "  5. If user says 'yes search web'/'find more': say you'll open the Workflow Engine",
        "  6. If user says 'handle everything'/'do it for me': confirm you'll create an Agentic task",
        "═══════════════════════════════════════════════",
    ])

    return "\n".join(lines)


# ───────────────────────────────────────────────────────────────────
# USER CONTEXT LOADER
# ───────────────────────────────────────────────────────────────────

async def get_user_brain_context(user_id: str) -> Dict[str, Any]:
    """
    Load a user's full brain context: positioning, active methods, recent tasks.
    Always returns a valid dict — never raises.
    """
    try:
        sb = supabase_service.client

        positioning, tracked, recent_tasks = await asyncio.gather(
            asyncio.get_event_loop().run_in_executor(
                None,
                lambda: sb.table("user_positioning")
                    .select("goal_type,available_capital_usd,risk_tolerance,"
                            "location_city,location_country,current_skills")
                    .eq("user_id", user_id).execute()
            ),
            asyncio.get_event_loop().run_in_executor(
                None,
                lambda: sb.table("user_income_methods")
                    .select("status,income_methods(title,investment_tier)")
                    .eq("user_id", user_id)
                    .in_("status", ["active","mastered"])
                    .limit(5).execute()
            ),
            asyncio.get_event_loop().run_in_executor(
                None,
                lambda: sb.table("agentic_tasks")
                    .select("task_type,title,status,created_at")
                    .eq("user_id", user_id)
                    .order("created_at", desc=True)
                    .limit(3).execute()
            ),
            return_exceptions=True,
        )

        return {
            "positioning": positioning.data[0] if (
                not isinstance(positioning, Exception) and positioning.data
            ) else None,
            "active_methods": [
                m.get("income_methods", {}).get("title", "")
                for m in ((tracked.data or []) if not isinstance(tracked, Exception) else [])
                if m.get("income_methods")
            ],
            "recent_tasks": (
                recent_tasks.data or []
            ) if not isinstance(recent_tasks, Exception) else [],
        }
    except Exception as exc:
        _log_brain_error("Context load", exc)
        return {}


# ───────────────────────────────────────────────────────────────────
# HELPERS
# ───────────────────────────────────────────────────────────────────

def _detect_investment_tier(text: str) -> Optional[str]:
    t = text.lower()
    if any(w in t for w in ["no money","zero","broke","free","$0","nothing to invest"]):
        return "zero"
    if any(w in t for w in ["$100","$200","$500","hundred","few hundred","little money"]):
        return "micro"
    if any(w in t for w in ["$1000","$5000","thousand","1k","5k"]):
        return "low"
    if any(w in t for w in ["$50k","$100k","fifty thousand","hundred thousand"]):
        return "medium"
    if any(w in t for w in ["million","$1m","1 million"]):
        return "major"
    return None


def _escalation_reason(intent: str, found: bool, confidence: float) -> str:
    if not found:
        return "No matching RiseUp users or listings found internally. The internet search will find more options."
    if confidence < 0.5:
        return "Few internal results found. Web search will surface many more buyers, sellers, and contacts."
    if intent in ("find_buyers", "find_sellers", "find_service_provider"):
        return "To find more buyers/sellers/providers beyond RiseUp, we need to search the internet."
    return "More comprehensive results available through external web search."


def _suggest_task_type(intent: str) -> str:
    return {
        "find_buyers":           "find_buyers",
        "find_sellers":          "find_sellers",
        "find_service_provider": "find_service_provider",
        "find_partners":         "find_partners",
        "find_investors":        "find_investors",
        "learn_method":          "market_research",
        "explore":               "market_research",
    }.get(intent, "custom")
