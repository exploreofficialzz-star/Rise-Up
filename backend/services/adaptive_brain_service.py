"""
RiseUp Adaptive Brain — Learning & Signal Collection Service v1.0
═══════════════════════════════════════════════════════════════════
Collects signals from EVERYWHERE:
  • Posts (what user creates, likes, saves, shares)
  • Status updates (what user shares publicly)
  • AI Mentor chat (intent, queries, goals declared)
  • Marketplace interactions (what user buys/sells/inquires)
  • Workflow searches (what user researches)
  • Agentic tasks (what user wants executed)

Builds adaptive user economic profile that gets smarter every session.
Enables the AI to:
  • Detect unmet needs ("selling a used laptop" → find buyers)
  • Suggest methods based on actual behaviour, not just quiz answers
  • Proactively surface opportunities user hasn't asked for
  • Connect users whose needs complement each other
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional, Dict, List, Any

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)

# ───────────────────────────────────────────────────────────────────
# SIGNAL TYPES
# ───────────────────────────────────────────────────────────────────

class SignalType:
    POST_CREATED         = "post_created"
    POST_LIKED           = "post_liked"
    POST_SAVED           = "post_saved"
    POST_SHARED          = "post_shared"
    STATUS_CREATED       = "status_created"
    MENTOR_QUERY         = "mentor_query"
    MENTOR_INTENT        = "mentor_intent"
    MARKETPLACE_POSTED   = "marketplace_posted"
    MARKETPLACE_INQUIRED = "marketplace_inquired"
    METHOD_TRACKED       = "method_tracked"
    WORKFLOW_CREATED     = "workflow_created"
    AGENT_TASK_CREATED   = "agent_task_created"
    SEARCH_PERFORMED     = "search_performed"
    OPPORTUNITY_FOUND    = "opportunity_found"


# ───────────────────────────────────────────────────────────────────
# NEED DETECTOR — reads text and finds economic intents
# ───────────────────────────────────────────────────────────────────

# Patterns that indicate the user has something to SELL
SELL_ASSET_PATTERNS = [
    r"selling\s+(?:my\s+)?(.+?)(?:\s+for|\s+cheap|\s+urgently|\.|\,|$)",
    r"want(?:s)?\s+to\s+sell\s+(.+?)(?:\.|,|\s+but|\s+and|$)",
    r"(?:have|got)\s+(?:a\s+)?(.+?)\s+(?:for sale|to sell|i want to sell)",
    r"(?:my|a)\s+(?:used|old|second.?hand)\s+(.+?)\s+(?:for sale|to sell|selling)",
    r"(?:trying|need)\s+to\s+(?:sell|get rid of)\s+(.+?)(?:\.|,|$)",
    r"how\s+(?:do|can)\s+i\s+sell\s+(?:my\s+)?(.+?)(?:\?|$)",
]

# Patterns indicating user NEEDS to buy something
BUY_NEED_PATTERNS = [
    r"(?:looking for|need|want to buy|searching for)\s+(?:a\s+)?(.+?)(?:\s+cheap|\s+affordable|\.|,|$)",
    r"(?:where\s+can\s+i|how\s+do\s+i)\s+(?:buy|get|find)\s+(?:a\s+)?(.+?)(?:\?|$)",
    r"(?:need|require)\s+(?:a\s+)?(.+?)\s+(?:for\s+my|to\s+start|urgently)",
]

# Patterns indicating user needs a SERVICE
SERVICE_NEED_PATTERNS = [
    r"(?:need|looking for)\s+(?:someone|a person|a developer|a designer|a writer)\s+(?:to|who\s+can)\s+(.+?)(?:\.|,|$)",
    r"(?:hire|outsource)\s+(.+?)(?:\s+work|\s+task|\s+job|\.|,|$)",
    r"(?:can\s+someone|anyone\s+here|who\s+can)\s+help\s+(?:me\s+with\s+)?(.+?)(?:\?|$)",
    r"(?:do you|does anyone)\s+(?:know\s+)?(?:someone\s+who\s+)?(?:does|builds|creates|writes|designs)\s+(.+?)(?:\?|$)",
]

# Patterns indicating user declares a business/income GOAL
GOAL_PATTERNS = [
    r"(?:want|trying|planning|going)\s+to\s+(?:start|build|create|launch)\s+(?:a\s+|my\s+)?(.+?)(?:\s+business|\s+company|\s+service|\s+store|\.|,|$)",
    r"(?:i\s+want|my goal is|i'm going)\s+to\s+(?:make|earn)\s+(.+?)(?:\s+per\s+month|\s+a\s+month|\s+monthly|\s+a\s+day)",
    r"(?:started|starting|launching)\s+(?:a\s+|my\s+)?(.+?)(?:\s+business|\s+company|\.|,|$)",
]

# CASH PROBLEM patterns
CASH_PROBLEM_PATTERNS = [
    r"(?:broke|no money|out of cash|no capital|zero budget|can't afford|don't have money)",
    r"(?:need money|need cash|struggling financially|financial difficulty)",
    r"(?:looking for)\s+(?:ways|how)\s+to\s+(?:make money|earn money|get cash)",
]

def extract_economic_signals(text: str) -> Dict[str, Any]:
    """
    Parse any text (post, status, chat message) and extract economic signals.
    Returns structured signals the brain can act on.
    """
    t = text.lower()
    signals = {
        "has_sell_intent":    False,
        "has_buy_intent":     False,
        "has_service_need":   False,
        "has_cash_problem":   False,
        "sell_items":         [],
        "buy_items":          [],
        "service_needs":      [],
        "income_goals":       [],
        "keywords":           [],
        "raw_text":           text[:300],
    }

    # Detect sell intent
    for pattern in SELL_ASSET_PATTERNS:
        for m in re.finditer(pattern, t, re.IGNORECASE):
            item = m.group(1).strip()[:80] if m.lastindex else ""
            if item and len(item) > 2:
                signals["has_sell_intent"] = True
                signals["sell_items"].append(item)

    # Detect buy intent
    for pattern in BUY_NEED_PATTERNS:
        for m in re.finditer(pattern, t, re.IGNORECASE):
            item = m.group(1).strip()[:80] if m.lastindex else ""
            if item and len(item) > 2:
                signals["has_buy_intent"] = True
                signals["buy_items"].append(item)

    # Detect service needs
    for pattern in SERVICE_NEED_PATTERNS:
        for m in re.finditer(pattern, t, re.IGNORECASE):
            item = m.group(1).strip()[:80] if m.lastindex else ""
            if item and len(item) > 2:
                signals["has_service_need"] = True
                signals["service_needs"].append(item)

    # Detect goals
    for pattern in GOAL_PATTERNS:
        for m in re.finditer(pattern, t, re.IGNORECASE):
            item = m.group(1).strip()[:100] if m.lastindex else ""
            if item and len(item) > 2:
                signals["income_goals"].append(item)

    # Detect cash problem
    for pattern in CASH_PROBLEM_PATTERNS:
        if re.search(pattern, t, re.IGNORECASE):
            signals["has_cash_problem"] = True
            break

    # Extract keywords
    stop = {"i","the","a","to","and","or","my","me","but","for","have","want","that","this"}
    words = re.findall(r'\b[a-zA-Z]{4,}\b', t)
    signals["keywords"] = list({w for w in words if w not in stop})[:15]

    return signals


# ───────────────────────────────────────────────────────────────────
# USER ADAPTIVE PROFILE TABLE (brain_user_signals)
# ───────────────────────────────────────────────────────────────────

async def record_signal(
    user_id: str,
    signal_type: str,
    content: str,
    metadata: Optional[Dict] = None,
):
    """
    Record a single user signal into brain_user_signals table.
    This is the raw event stream the brain learns from.
    """
    try:
        sb = supabase_service.client
        economic = extract_economic_signals(content)

        sb.table("brain_user_signals").insert({
            "user_id":     user_id,
            "signal_type": signal_type,
            "content":     content[:500],
            "metadata":    metadata or {},
            "economic_signals": economic,
            "has_sell_intent":  economic["has_sell_intent"],
            "has_buy_intent":   economic["has_buy_intent"],
            "has_service_need": economic["has_service_need"],
            "has_cash_problem": economic["has_cash_problem"],
            "created_at":  datetime.now(timezone.utc).isoformat(),
        }).execute()

        # If strong economic signal → update adaptive profile immediately
        if any([
            economic["has_sell_intent"],
            economic["has_buy_intent"],
            economic["has_service_need"],
            economic["income_goals"],
        ]):
            await _update_adaptive_profile(user_id, economic, signal_type)

    except Exception as e:
        logger.error(f"[BRAIN SIGNAL] record error: {e}")


async def _update_adaptive_profile(
    user_id: str,
    economic: Dict,
    signal_type: str,
):
    """
    Update the user's adaptive economic profile based on new signals.
    This is the rolling picture of what the user needs.
    """
    try:
        sb = supabase_service.client

        # Load existing profile
        existing = sb.table("brain_adaptive_profiles")\
            .select("*").eq("user_id", user_id).execute()

        profile = existing.data[0] if existing.data else {}

        # Merge sell items
        sell_items = list(set(
            (profile.get("detected_sell_items") or []) +
            economic.get("sell_items", [])
        ))[:20]

        # Merge buy items
        buy_items = list(set(
            (profile.get("detected_buy_items") or []) +
            economic.get("buy_items", [])
        ))[:20]

        # Merge service needs
        service_needs = list(set(
            (profile.get("detected_service_needs") or []) +
            economic.get("service_needs", [])
        ))[:20]

        # Merge goals
        income_goals = list(set(
            (profile.get("detected_income_goals") or []) +
            economic.get("income_goals", [])
        ))[:10]

        # Merge keywords
        all_keywords = list(set(
            (profile.get("interest_keywords") or []) +
            economic.get("keywords", [])
        ))[:50]

        upsert_data = {
            "user_id":                   user_id,
            "detected_sell_items":       sell_items,
            "detected_buy_items":        buy_items,
            "detected_service_needs":    service_needs,
            "detected_income_goals":     income_goals,
            "interest_keywords":         all_keywords,
            "has_active_sell_intent":    len(sell_items) > 0,
            "has_active_buy_intent":     len(buy_items) > 0,
            "has_active_service_need":   len(service_needs) > 0,
            "signal_count":              (profile.get("signal_count") or 0) + 1,
            "last_signal_type":          signal_type,
            "last_signal_at":            datetime.now(timezone.utc).isoformat(),
            "updated_at":                datetime.now(timezone.utc).isoformat(),
        }

        sb.table("brain_adaptive_profiles").upsert(
            upsert_data, on_conflict="user_id"
        ).execute()

    except Exception as e:
        logger.error(f"[BRAIN ADAPTIVE] profile update error: {e}")


# ───────────────────────────────────────────────────────────────────
# ADAPTIVE PROFILE READER
# ───────────────────────────────────────────────────────────────────

async def get_adaptive_profile(user_id: str) -> Dict[str, Any]:
    """
    Get the user's full adaptive economic profile.
    Used to enrich the AI mentor system prompt.
    """
    try:
        sb = supabase_service.client
        result = sb.table("brain_adaptive_profiles")\
            .select("*").eq("user_id", user_id).execute()
        return result.data[0] if result.data else {}
    except Exception as e:
        logger.error(f"[BRAIN ADAPTIVE] get profile error: {e}")
        return {}


async def build_adaptive_context_prompt(user_id: str) -> str:
    """
    Build the adaptive brain context block to inject into AI mentor prompts.
    This makes the AI aware of everything the user has said/done.
    """
    profile = await get_adaptive_profile(user_id)
    if not profile:
        return ""

    lines = [
        "═══════════════════════════════════════════════",
        "ADAPTIVE USER ECONOMIC PROFILE (learned from behavior):",
        "═══════════════════════════════════════════════",
    ]

    sell_items = profile.get("detected_sell_items") or []
    buy_items  = profile.get("detected_buy_items") or []
    svc_needs  = profile.get("detected_service_needs") or []
    goals      = profile.get("detected_income_goals") or []
    keywords   = profile.get("interest_keywords") or []

    if sell_items:
        lines.append(f"💰 USER WANTS TO SELL: {', '.join(sell_items[:5])}")
        lines.append("   → OPPORTUNITY: Search for buyers of these items within RiseUp first!")
        lines.append("   → If no RiseUp buyers found: offer to post on marketplace + find external buyers")

    if buy_items:
        lines.append(f"🛒 USER WANTS TO BUY: {', '.join(buy_items[:5])}")
        lines.append("   → OPPORTUNITY: Search RiseUp marketplace for sellers of these items")

    if svc_needs:
        lines.append(f"🔧 USER NEEDS SERVICES: {', '.join(svc_needs[:5])}")
        lines.append("   → OPPORTUNITY: Search RiseUp for service providers who can help")

    if goals:
        lines.append(f"🎯 USER'S INCOME GOALS: {', '.join(goals[:3])}")
        lines.append("   → OPPORTUNITY: Match goals to relevant income methods from the 10,000 brain")

    if profile.get("has_active_sell_intent"):
        lines.append("\n🔔 ACTIVE SIGNAL: This user WANTS TO SELL SOMETHING.")
        lines.append("   Your response should proactively offer to help find buyers.")

    if profile.get("has_active_buy_intent"):
        lines.append("\n🔔 ACTIVE SIGNAL: This user is LOOKING TO BUY something.")
        lines.append("   Check marketplace listings for what they want.")

    if profile.get("has_active_service_need"):
        lines.append("\n🔔 ACTIVE SIGNAL: This user NEEDS SOMEONE TO HELP THEM.")
        lines.append("   Search service providers on RiseUp who match their needs.")

    if keywords:
        lines.append(f"\n📊 USER INTEREST KEYWORDS: {', '.join(keywords[:10])}")

    lines.append(f"\n📈 Brain learning signals: {profile.get('signal_count',0)}")
    lines.append("═══════════════════════════════════════════════")
    lines.append("ADAPTIVE RESPONSE RULES:")
    lines.append("1. If user has sell_items: ALWAYS offer to find buyers (internal first)")
    lines.append("2. If user has buy_items: ALWAYS show relevant marketplace listings")
    lines.append("3. If user has service_needs: ALWAYS show matching RiseUp service providers")
    lines.append("4. Connect users whose needs complement each other when possible")
    lines.append("5. Remember past conversations — user said they want to sell X, act on it")
    lines.append("═══════════════════════════════════════════════")

    return "\n".join(lines)


# ───────────────────────────────────────────────────────────────────
# POST SIGNAL COLLECTOR (called from posts router)
# ───────────────────────────────────────────────────────────────────

async def process_post_signal(
    user_id: str,
    post_id: str,
    content: str,
    tag: Optional[str] = None,
    media_url: Optional[str] = None,
):
    """
    Called when a user creates a post.
    Extracts economic signals and potentially surfaces a suggestion.
    """
    await record_signal(
        user_id=user_id,
        signal_type=SignalType.POST_CREATED,
        content=content,
        metadata={"post_id": post_id, "tag": tag},
    )

    # Check for strong sell/buy signals → auto-suggest marketplace action
    economic = extract_economic_signals(content)

    suggestions = []
    if economic["has_sell_intent"] and economic["sell_items"]:
        suggestions.append({
            "type": "marketplace_sell",
            "items": economic["sell_items"],
            "message": (
                f"I noticed you mentioned selling: {', '.join(economic['sell_items'][:2])}. "
                "Want me to help you find buyers on RiseUp or list it on the marketplace?"
            ),
            "action_url": "/marketplace",
        })

    if economic["has_buy_intent"] and economic["buy_items"]:
        suggestions.append({
            "type": "marketplace_buy",
            "items": economic["buy_items"],
            "message": (
                f"Looking for: {', '.join(economic['buy_items'][:2])}. "
                "Let me check if anyone on RiseUp has this available."
            ),
            "action_url": "/marketplace",
        })

    return {
        "economic_signals": economic,
        "suggestions":      suggestions,
    }


async def process_status_signal(
    user_id: str,
    status_id: str,
    content: str,
):
    """Called when a user creates a status update."""
    await record_signal(
        user_id=user_id,
        signal_type=SignalType.STATUS_CREATED,
        content=content,
        metadata={"status_id": status_id},
    )


async def process_mentor_chat_signal(
    user_id: str,
    message: str,
    intent: Optional[str] = None,
    session_id: Optional[str] = None,
):
    """Called on every AI mentor chat message."""
    await record_signal(
        user_id=user_id,
        signal_type=SignalType.MENTOR_QUERY,
        content=message,
        metadata={"intent": intent, "session_id": session_id},
    )


async def process_interaction_signal(
    user_id: str,
    signal_type: str,
    post_content: str,
    post_id: str,
):
    """Called when user likes/saves/shares a post."""
    await record_signal(
        user_id=user_id,
        signal_type=signal_type,
        content=post_content,
        metadata={"post_id": post_id},
    )


# ───────────────────────────────────────────────────────────────────
# COMPLEMENTARY USER MATCHER
# ───────────────────────────────────────────────────────────────────

async def find_complementary_users(
    user_id: str,
    limit: int = 5,
) -> List[Dict]:
    """
    Find RiseUp users whose economic needs COMPLEMENT this user.

    E.g.:
    - User A wants to SELL laptop → find users who want to BUY laptop
    - User B needs a developer → find users who OFFER development services
    - User C has cash → find users with investment opportunities
    """
    try:
        sb = supabase_service.client

        # Get this user's profile
        my_profile = sb.table("brain_adaptive_profiles")\
            .select("*").eq("user_id", user_id).execute()

        if not my_profile.data:
            return []

        my = my_profile.data[0]
        my_sell = my.get("detected_sell_items") or []
        my_buy  = my.get("detected_buy_items")  or []
        my_svc  = my.get("detected_service_needs") or []

        matches = []

        # Find buyers for what I'm selling
        if my_sell:
            buyers = sb.table("brain_adaptive_profiles")\
                .select("user_id,detected_buy_items")\
                .eq("has_active_buy_intent", True)\
                .neq("user_id", user_id)\
                .limit(20).execute()

            for b in (buyers.data or []):
                their_buy = b.get("detected_buy_items") or []
                overlap   = set(my_sell) & set(their_buy)
                # Also check partial keyword overlap
                if not overlap:
                    for s in my_sell:
                        for t in their_buy:
                            if len(s) > 3 and (s[:4] in t or t[:4] in s):
                                overlap.add(s)
                if overlap:
                    matches.append({
                        "user_id":     b["user_id"],
                        "match_type":  "buyer",
                        "overlap":     list(overlap)[:3],
                        "score":       len(overlap) * 20 + 50,
                    })

        # Find service providers for what I need
        if my_svc:
            providers = sb.table("profiles")\
                .select("id,full_name,service_tags,current_skills,hourly_rate_usd,avatar_url")\
                .eq("is_service_provider", True)\
                .limit(20).execute()

            for p in (providers.data or []):
                their_skills = list(p.get("service_tags") or []) + \
                               list(p.get("current_skills") or [])
                their_lower  = [s.lower() for s in their_skills]
                for need in my_svc:
                    if any(n in s or s in need.lower() for s in their_lower for n in need.lower().split()):
                        matches.append({
                            "user_id":    p["id"],
                            "full_name":  p.get("full_name","User"),
                            "avatar_url": p.get("avatar_url"),
                            "match_type": "service_provider",
                            "service":    need,
                            "rate":       p.get("hourly_rate_usd"),
                            "score":      75,
                        })
                        break

        # Sort by score
        matches.sort(key=lambda x: x.get("score", 0), reverse=True)
        return matches[:limit]

    except Exception as e:
        logger.error(f"[BRAIN MATCH] complementary users error: {e}")
        return []


# ───────────────────────────────────────────────────────────────────
# BRAIN MIGRATION SQL (add to run alongside migration_009)
# ───────────────────────────────────────────────────────────────────

BRAIN_LEARNING_MIGRATION_SQL = """
-- brain_user_signals: raw event stream
CREATE TABLE IF NOT EXISTS public.brain_user_signals (
    id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id             UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_type         TEXT        NOT NULL,
    content             TEXT,
    metadata            JSONB       DEFAULT '{}',
    economic_signals    JSONB       DEFAULT '{}',
    has_sell_intent     BOOLEAN     DEFAULT FALSE,
    has_buy_intent      BOOLEAN     DEFAULT FALSE,
    has_service_need    BOOLEAN     DEFAULT FALSE,
    has_cash_problem    BOOLEAN     DEFAULT FALSE,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bus_user    ON public.brain_user_signals(user_id);
CREATE INDEX IF NOT EXISTS idx_bus_type    ON public.brain_user_signals(signal_type);
CREATE INDEX IF NOT EXISTS idx_bus_sell    ON public.brain_user_signals(has_sell_intent) WHERE has_sell_intent = TRUE;
CREATE INDEX IF NOT EXISTS idx_bus_buy     ON public.brain_user_signals(has_buy_intent) WHERE has_buy_intent = TRUE;
CREATE INDEX IF NOT EXISTS idx_bus_date    ON public.brain_user_signals(created_at DESC);
ALTER TABLE public.brain_user_signals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bus_own" ON public.brain_user_signals FOR ALL USING (auth.uid() = user_id);

-- brain_adaptive_profiles: rolling economic snapshot
CREATE TABLE IF NOT EXISTS public.brain_adaptive_profiles (
    id                          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id                     UUID        REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    detected_sell_items         TEXT[]      DEFAULT '{}',
    detected_buy_items          TEXT[]      DEFAULT '{}',
    detected_service_needs      TEXT[]      DEFAULT '{}',
    detected_income_goals       TEXT[]      DEFAULT '{}',
    interest_keywords           TEXT[]      DEFAULT '{}',
    has_active_sell_intent      BOOLEAN     DEFAULT FALSE,
    has_active_buy_intent       BOOLEAN     DEFAULT FALSE,
    has_active_service_need     BOOLEAN     DEFAULT FALSE,
    signal_count                INTEGER     DEFAULT 0,
    last_signal_type            TEXT,
    last_signal_at              TIMESTAMPTZ,
    updated_at                  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bap_user      ON public.brain_adaptive_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_bap_sell      ON public.brain_adaptive_profiles(has_active_sell_intent) WHERE has_active_sell_intent = TRUE;
CREATE INDEX IF NOT EXISTS idx_bap_buy       ON public.brain_adaptive_profiles(has_active_buy_intent) WHERE has_active_buy_intent = TRUE;
CREATE INDEX IF NOT EXISTS idx_bap_svc       ON public.brain_adaptive_profiles(has_active_service_need) WHERE has_active_service_need = TRUE;
ALTER TABLE public.brain_adaptive_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bap_own" ON public.brain_adaptive_profiles FOR ALL USING (auth.uid() = user_id);
"""

