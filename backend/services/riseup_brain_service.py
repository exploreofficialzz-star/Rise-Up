"""
RiseUp Brain Service v1.0
═══════════════════════════════════════════════════════════════════
The intelligence layer that makes the AI Mentor aware of:
  1. All 10,000 income methods
  2. RiseUp marketplace listings (buyers/sellers/services)
  3. RiseUp user profiles (service providers, skill holders)
  4. Community posts relevant to the query

Search Priority:
  Internal first → Found? Return with confidence.
  Not found / low confidence? → Signal escalation to workflow.

Used by: ai_agent.py (/ai/chat), agent.py (/agent/chat & /agent/run-stream)
"""

import asyncio
import logging
import json
import re
from typing import Optional, Dict, List, Any
from datetime import datetime

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)

# ───────────────────────────────────────────────────────────────────
# INTENT DETECTION
# ───────────────────────────────────────────────────────────────────

SELL_SIGNALS    = ["sell","selling","sell my","get rid of","i have for sale","how much for my","list my","find buyer","buyer for","market my"]
BUY_SIGNALS     = ["buy","looking for","want to buy","find me a","need to purchase","where can i get","acquire","source"]
SERVICE_SIGNALS = ["need someone to","hire a","looking for a","find a developer","find a designer","need a","help with","who can","outsource"]
LEARN_SIGNALS   = ["how to make money","how do i start","ways to earn","income ideas","side hustle","make money","earn money","start a business"]
PARTNER_SIGNALS = ["business partner","co-founder","collab","joint venture","teaming up","work together"]
INVEST_SIGNALS  = ["invest","investor","funding","raise money","capital","angel","vc","seed"]

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
      "methods": [...],          # matching income methods
      "marketplace": [...],      # matching listings
      "service_providers": [...],# RiseUp users offering related services
      "community": [...],        # relevant posts
      "summary": str,            # human-readable summary for AI mentor
      "needs_external": bool,
      "escalation_reason": str,
      "suggested_task_type": str,
    }
    """
    if not intent:
        intent = detect_intent(query)

    keywords = extract_keywords(query)

    # Run all internal searches in parallel
    methods_res, marketplace_res, profiles_res = await asyncio.gather(
        _search_methods(query, keywords, intent, limit),
        _search_marketplace(query, keywords, intent, user_country, limit),
        _search_service_providers(query, keywords, intent, user_country, limit),
        return_exceptions=True,
    )

    methods     = methods_res     if isinstance(methods_res, list)     else []
    marketplace = marketplace_res if isinstance(marketplace_res, list) else []
    providers   = profiles_res    if isinstance(profiles_res, list)    else []

    # Calculate confidence
    total_found = len(methods) + len(marketplace) + len(providers)
    confidence  = min(0.95, total_found * 0.18)
    found       = total_found > 0

    # Decide if external search is needed
    needs_external = not found or (
        intent in ("find_buyers", "find_sellers", "find_service_provider", "find_partners") and
        confidence < 0.6
    )

    # Build human-readable summary for AI mentor injection
    summary = _build_summary(intent, methods, marketplace, providers, query)

    # Log search for analytics
    try:
        sb = supabase_service.client
        sb.table("brain_search_log").insert({
            "user_id":       user_id,
            "query":         query[:500],
            "intent":        intent,
            "internal_found": found,
            "results_count": total_found,
            "escalated":     needs_external,
        }).execute()
    except Exception:
        pass

    return {
        "found":              found,
        "confidence":         confidence,
        "intent":             intent,
        "methods":            methods,
        "marketplace":        marketplace,
        "service_providers":  providers,
        "summary":            summary,
        "total_found":        total_found,
        "needs_external":     needs_external,
        "escalation_reason":  _escalation_reason(intent, found, confidence) if needs_external else None,
        "suggested_task_type": _suggest_task_type(intent),
    }


# ───────────────────────────────────────────────────────────────────
# METHODS SEARCH
# ───────────────────────────────────────────────────────────────────

async def _search_methods(
    query: str,
    keywords: List[str],
    intent: str,
    limit: int,
) -> List[Dict]:
    """Search the 10,000 income methods database."""
    if intent not in ("learn_method", "explore") and not any(
        w in query.lower() for w in ["method","way","how","earn","make money","income","hustle","business"]
    ):
        return []

    try:
        sb     = supabase_service.client
        result = None

        # Full-text search if keywords exist
        if keywords:
            result = sb.table("income_methods").select(
                "id,method_number,title,description,category,investment_tier,"
                "time_to_first_dollar,skill_level,tags,section_emoji,"
                "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,"
                "global_demand_score,how_to_start,first_steps,platforms"
            ).eq("is_active", True)\
             .ilike("title", f"%{keywords[0]}%")\
             .order("global_demand_score", desc=True)\
             .limit(limit).execute()

        # Fallback: investment tier detection
        if not (result and result.data):
            tier = _detect_investment_tier(query)
            if tier:
                result = sb.table("income_methods").select(
                    "id,method_number,title,description,category,investment_tier,"
                    "time_to_first_dollar,skill_level,tags,section_emoji,"
                    "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,"
                    "global_demand_score,how_to_start,first_steps,platforms"
                ).eq("is_active", True)\
                 .eq("investment_tier", tier)\
                 .eq("is_featured", True)\
                 .order("global_demand_score", desc=True)\
                 .limit(limit).execute()

        return result.data if result and result.data else []
    except Exception as e:
        logger.error(f"[BRAIN] Methods search error: {e}")
        return []


# ───────────────────────────────────────────────────────────────────
# MARKETPLACE SEARCH
# ───────────────────────────────────────────────────────────────────

async def _search_marketplace(
    query: str,
    keywords: List[str],
    intent: str,
    country: Optional[str],
    limit: int,
) -> List[Dict]:
    """Search active marketplace listings."""
    try:
        sb = supabase_service.client

        # Map intent to listing type we want to show
        listing_type_map = {
            "find_buyers":          "buying",          # user wants to sell → show buyers
            "find_sellers":         "selling",         # user wants to buy  → show sellers
            "find_service_provider":"service_offer",   # user needs help    → show services
            "find_partners":        "partnership",
            "find_investors":       "investment",
        }
        target_type = listing_type_map.get(intent)

        q = sb.table("marketplace_listings").select(
            "id,listing_type,title,description,price_usd,currency,"
            "location,country,is_global,contact_info,tags,user_id,created_at"
        ).eq("status", "active")

        if target_type:
            q = q.eq("listing_type", target_type)

        if keywords:
            q = q.ilike("title", f"%{keywords[0]}%")

        result = q.order("created_at", desc=True).limit(limit).execute()
        return result.data or []
    except Exception as e:
        logger.error(f"[BRAIN] Marketplace search error: {e}")
        return []


# ───────────────────────────────────────────────────────────────────
# PROFILE / SERVICE PROVIDER SEARCH
# ───────────────────────────────────────────────────────────────────

async def _search_service_providers(
    query: str,
    keywords: List[str],
    intent: str,
    country: Optional[str],
    limit: int,
) -> List[Dict]:
    """Search RiseUp user profiles for relevant service providers."""
    if intent not in ("find_service_provider", "find_partners", "find_buyers", "find_sellers"):
        return []

    try:
        sb = supabase_service.client

        if keywords:
            result = sb.rpc("search_service_providers", {
                "p_query":  " ".join(keywords[:3]),
                "p_limit":  limit,
                "p_offset": 0,
            }).execute()
            if result.data:
                return result.data

        # Fallback: search by skills array
        if keywords:
            result = sb.table("profiles").select(
                "id,full_name,bio,avatar_url,country,current_skills,"
                "service_tags,service_description,hourly_rate_usd"
            ).contains("current_skills", [keywords[0]])\
             .limit(limit).execute()
            return result.data or []

        return []
    except Exception as e:
        logger.error(f"[BRAIN] Profile search error: {e}")
        return []


# ───────────────────────────────────────────────────────────────────
# SUMMARY BUILDER — for injection into AI mentor system prompt
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
            earnings = ""
            if m.get("avg_earning_monthly_usd_low"):
                earnings = f" | Earns: ${m['avg_earning_monthly_usd_low']:,.0f}–${m.get('avg_earning_monthly_usd_high',0):,.0f}/mo"
            parts.append(
                f"  {m.get('section_emoji','💡')} {m['title']} "
                f"[{m['investment_tier'].upper()}, {m.get('time_to_first_dollar','weeks')} to first $]{earnings}"
            )
            if m.get("how_to_start"):
                parts.append(f"     How to start: {m['how_to_start'][:120]}...")

    if marketplace:
        parts.append(f"\n🛒 RISEUP MARKETPLACE ({len(marketplace)} listings found):")
        for l in marketplace[:3]:
            price = f"${l['price_usd']:,.0f}" if l.get("price_usd") else "Negotiable"
            location = "Global" if l.get("is_global") else l.get("location","Unknown")
            parts.append(
                f"  [{l.get('listing_type','').upper()}] {l['title']} "
                f"| {price} | {location}"
            )

    if providers:
        parts.append(f"\n👤 RISEUP USERS OFFERING RELATED SERVICES ({len(providers)} found):")
        for p in providers[:3]:
            skills = ", ".join((p.get("current_skills") or [])[:3])
            rate = f" | ${p['hourly_rate_usd']}/hr" if p.get("hourly_rate_usd") else ""
            country = f" | {p.get('country','')}" if p.get("country") else ""
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
    This is called BEFORE the AI responds, giving it real-time RiseUp data.
    """
    lines = [
        "═══════════════════════════════════════════════",
        "RISEUP INTERNAL KNOWLEDGE (search results just run):",
        "═══════════════════════════════════════════════",
    ]

    if brain_result.get("summary"):
        lines.append(brain_result["summary"])

    if brain_result["needs_external"]:
        lines.extend([
            "",
            "⚠️  ESCALATION NEEDED:",
            f"   Reason: {brain_result.get('escalation_reason', 'Insufficient internal results')}",
            f"   Suggested action: Tell user I found limited internal results and offer to",
            f"   search the internet via the Workflow Engine.",
            f"   Task type if escalated: {brain_result.get('suggested_task_type', 'custom')}",
        ])
    else:
        lines.append("\n✅ Internal results are sufficient. Present them directly.")

    lines.extend([
        "═══════════════════════════════════════════════",
        "INSTRUCTIONS FOR THIS RESPONSE:",
        f"  Intent detected: {brain_result.get('intent', 'explore')}",
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
    mapping = {
        "find_buyers":           "find_buyers",
        "find_sellers":          "find_sellers",
        "find_service_provider": "find_service_provider",
        "find_partners":         "find_partners",
        "find_investors":        "find_investors",
        "learn_method":          "market_research",
        "explore":               "market_research",
    }
    return mapping.get(intent, "custom")


# ───────────────────────────────────────────────────────────────────
# USER CONTEXT LOADER
# ───────────────────────────────────────────────────────────────────

async def get_user_brain_context(user_id: str) -> Dict[str, Any]:
    """
    Load a user's full brain context: positioning, active methods, recent tasks.
    Used to personalise the AI mentor system prompt.
    """
    try:
        sb = supabase_service.client

        positioning = sb.table("user_positioning")\
            .select("goal_type,available_capital_usd,risk_tolerance,"
                    "location_city,location_country,current_skills")\
            .eq("user_id", user_id).execute()

        tracked = sb.table("user_income_methods")\
            .select("status,income_methods(title,investment_tier)")\
            .eq("user_id", user_id)\
            .in_("status", ["active","mastered"])\
            .limit(5).execute()

        recent_tasks = sb.table("agentic_tasks")\
            .select("task_type,title,status,created_at")\
            .eq("user_id", user_id)\
            .order("created_at", desc=True)\
            .limit(3).execute()

        return {
            "positioning":    positioning.data[0] if positioning.data else None,
            "active_methods": [
                m.get("income_methods",{}).get("title","")
                for m in (tracked.data or []) if m.get("income_methods")
            ],
            "recent_tasks":   recent_tasks.data or [],
        }
    except Exception as e:
        logger.error(f"[BRAIN] Context load error: {e}")
        return {}

