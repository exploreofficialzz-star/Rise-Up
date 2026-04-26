"""
backend/services/dispatcher.py
RiseUp Central Dispatcher v1.0

Single source of truth for all intent → endpoint routing.
Every feature (APEX, Workflow, Market Pulse, Mentor, Code) is mapped here.

Usage in mentor.py chat endpoint:
    from services.dispatcher import dispatcher
    result = await dispatcher.dispatch(message, profile, history, session_id, user_id)
"""

import logging
import re
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# FULL ENDPOINT MAP
# ─────────────────────────────────────────────────────────────────────────────

ENDPOINT_MAP = {
    # ── APEX Agent ────────────────────────────────────────────────────────────
    "apex_run":             "POST /api/v1/agent/browser/run",
    "apex_stream":          "POST /api/v1/agent/run-stream",
    "apex_stop":            "POST /api/v1/agent/browser/stop",
    "apex_status":          "GET  /api/v1/agent/browser/status/{session_id}",
    "apex_answer":          "POST /api/v1/agent/browser/answer",
    "apex_handoff":         "POST /api/v1/agent/handoff",
    "apex_classify":        "POST /api/v1/agent/classify",
    "apex_execute_tool":    "POST /api/v1/agent/execute-tool",
    "apex_tokens":          "GET  /api/v1/agent/tokens",
    "apex_record_ad":       "POST /api/v1/agent/tokens/record-ad",
    "apex_claim_reward":    "POST /api/v1/agent/tokens/claim-redemption",

    # ── Workflow Engine ────────────────────────────────────────────────────────
    "workflow_create":      "POST /api/v1/workflow/create",
    "workflow_research":    "POST /api/v1/workflow/research",
    "workflow_list":        "GET  /api/v1/workflow/",
    "workflow_get":         "GET  /api/v1/workflow/{workflow_id}",
    "workflow_step":        "PATCH /api/v1/workflow/{workflow_id}/step/{step_id}",
    "workflow_revenue":     "POST /api/v1/workflow/{workflow_id}/log-revenue",
    "workflow_analytics":   "GET  /api/v1/workflow/{workflow_id}/analytics",
    "workflow_ai_assist":   "POST /api/v1/workflow/{workflow_id}/ai-assist",
    "workflow_currencies":  "GET  /api/v1/workflow/global/currencies",
    "workflow_regions":     "GET  /api/v1/workflow/global/regions",
    "workflow_payments":    "GET  /api/v1/workflow/global/payment-methods/{region}",

    # ── Market Pulse ──────────────────────────────────────────────────────────
    "market_today":         "GET  /api/v1/pulse/today",
    "market_international": "GET  /api/v1/pulse/international",
    "market_local":         "GET  /api/v1/pulse/local",
    "market_forecast":      "GET  /api/v1/pulse/career-forecast",
    "market_entrepreneur":  "GET  /api/v1/pulse/entrepreneurial-opportunities",
    "market_wealth":        "GET  /api/v1/pulse/wealth-strategies",
    "market_growth":        "GET  /api/v1/pulse/personal-growth",
    "market_scan":          "GET  /api/v1/pulse/opportunity-scan",
    "market_arbitrage":     "GET  /api/v1/pulse/arbitrage",
    "market_comprehensive": "GET  /api/v1/pulse/comprehensive",

    # ── AI Mentor ─────────────────────────────────────────────────────────────
    "mentor_chat":          "POST /api/v1/mentor/chat",
    "mentor_stream":        "POST /api/v1/mentor/chat/stream",
    "mentor_sessions":      "GET  /api/v1/mentor/sessions",
    "mentor_session":       "GET  /api/v1/mentor/session/{session_id}",
    "mentor_checkin":       "POST /api/v1/mentor/daily-checkin",
    "mentor_feedback":      "POST /api/v1/mentor/feedback",
    "mentor_rename":        "POST /api/v1/mentor/sessions/{session_id}/rename",
    "mentor_delete":        "POST /api/v1/mentor/sessions/{session_id}/delete",

    # ── Methods Brain ─────────────────────────────────────────────────────────
    "methods_list":         "GET  /api/v1/brain/methods",
    "methods_search":       "GET  /api/v1/brain/methods/search",
    "methods_featured":     "GET  /api/v1/brain/methods/featured",
    "methods_tiers":        "GET  /api/v1/brain/methods/tiers",
    "methods_detail":       "GET  /api/v1/brain/methods/{method_id}",
    "methods_track":        "POST /api/v1/brain/methods/{method_id}/track",
    "methods_chat":         "POST /api/v1/brain/mentor/chat",
    "marketplace_list":     "GET  /api/v1/brain/marketplace",
    "marketplace_create":   "POST /api/v1/brain/marketplace",
    "marketplace_mine":     "GET  /api/v1/brain/marketplace/my",

    # ── Code Sandbox ──────────────────────────────────────────────────────────
    "code_run":             "POST /api/v1/agent/run",
    "code_stream":          "POST /api/v1/agent/run-stream",

    # ── Supporting ────────────────────────────────────────────────────────────
    "goals_list":           "GET  /api/v1/goals",
    "goals_create":         "POST /api/v1/goals",
    "tasks_list":           "GET  /api/v1/tasks",
    "tasks_create":         "POST /api/v1/tasks",
    "earnings_log":         "POST /api/v1/income_memory/log",
    "earnings_summary":     "GET  /api/v1/income_memory/summary",
    "profile_get":          "GET  /api/v1/auth/me",
    "profile_update":       "PATCH /api/v1/auth/me",
    "notifications":        "GET  /api/v1/notifications",
}


# ─────────────────────────────────────────────────────────────────────────────
# INTENT PATTERNS — compiled once at startup
# ─────────────────────────────────────────────────────────────────────────────

_INTENT_PATTERNS: List[Tuple[re.Pattern, str, float]] = []


def _p(pattern: str, intent: str, weight: float = 1.0):
    _INTENT_PATTERNS.append((re.compile(pattern, re.IGNORECASE), intent, weight))


# APEX — user wants the system to DO something right now
_p(r'\b(do it|just do it|go ahead|handle it|take care of it)\b', "apex", 1.0)
_p(r'\b(set (it|this|that) up (for me)?|execute (this|it|now))\b', "apex", 1.0)
_p(r'\b(run it|make it happen|automate (this|it|that))\b', "apex", 1.0)
_p(r'\b(apply for me|sign me up|register me|create (my|the) account)\b', "apex", 1.0)
_p(r'\b(create my (profile|account|store|gig|channel|page|shop))\b', "apex", 1.0)
_p(r'\b(open (upwork|fiverr|youtube|shopify|etsy|amazon|tiktok|linkedin))\b', "apex", 1.0)
_p(r'\b(send (the )?(email|proposal|message|application|cv|resume) (for me|now))\b', "apex", 1.0)
_p(r'\b(post (it|this|the content|for me)|publish (it|this|now))\b', "apex", 1.0)
_p(r'\b(fill (in |out )?(the |this )?(form|details|profile))\b', "apex", 1.0)
_p(r'\b(submit (the |this )?(proposal|application|form))\b', "apex", 1.0)
_p(r'\b(use apex|activate apex|launch apex)\b', "apex", 1.0)
_p(r'\b(build (it|this) for me|deploy (this|it))\b', "apex", 0.9)
_p(r'\b(find me clients? (now|today|automatically))\b', "apex", 0.9)
_p(r'\b(connect (my |the )?(bank|paypal|stripe|payment))\b', "apex", 0.9)
_p(r'\b(upload (my |the )?(portfolio|cv|resume|photo|image))\b', "apex", 0.85)
_p(r'\b(start my (channel|store|business|shop|gig|profile|account))\b', "apex", 0.85)

# WORKFLOW — user wants a strategic plan/roadmap
_p(r'\b(create (a |my )?(workflow|plan|strategy|roadmap|income plan))\b', "workflow", 1.0)
_p(r'\b(build (me )?(a |my )?(workflow|plan|strategy|roadmap))\b', "workflow", 1.0)
_p(r'\b(make (me )?(a |my )?(plan|strategy|roadmap|income plan))\b', "workflow", 1.0)
_p(r'\b(step.by.step (plan|guide|strategy))\b', "workflow", 1.0)
_p(r'\b(90.day (plan|strategy|sprint))\b', "workflow", 1.0)
_p(r'\b(how (do i|can i) (start|earn|make money) (from|with|on))\b', "workflow", 0.9)
_p(r'\b(want to (start|begin) (earning|making money|freelancing|selling))\b', "workflow", 0.9)
_p(r'\b(full (guide|strategy|plan|roadmap) (for|to|on))\b', "workflow", 0.9)
_p(r'\b(income (strategy|roadmap|plan|blueprint))\b', "workflow", 0.9)
_p(r'\b(guide me (through|to|on)|walk me through)\b', "workflow", 0.8)
_p(r'\b(getting started (with|on|in))\b', "workflow", 0.75)

# MARKET PULSE — live data, opportunities, trends
_p(r'\b(market pulse|scan (for )?(opportunities|jobs|gigs))\b', "market_pulse", 1.0)
_p(r'\b(what.?s (trending|hot|popular|selling) (now|today|right now))\b', "market_pulse", 1.0)
_p(r'\b(find (me )?(opportunities|jobs|gigs|clients|leads) (now|today|live))\b', "market_pulse", 1.0)
_p(r'\b(live (opportunities|jobs|market|data))\b', "market_pulse", 1.0)
_p(r'\b(latest (jobs|gigs|opportunities|trends|news))\b', "market_pulse", 0.9)
_p(r'\b(real.?time (data|market|opportunities))\b', "market_pulse", 0.9)
_p(r'\b(hot (niches?|platforms?|opportunities?))\b', "market_pulse", 0.9)
_p(r'\b(best (selling|performing|trending) (products?|niches?|skills?))\b', "market_pulse", 0.85)
_p(r'\b(where is (the money|demand) (right now|today|currently))\b', "market_pulse", 0.85)
_p(r'\b(arbitrage|price (difference|gap|arbitrage))\b', "market_pulse", 0.85)
_p(r'\b(find (a |me a? )?(supplier|buyer|wholesale|bulk))\b', "market_pulse", 0.8)
_p(r'\b(contact (number|email|phone) (of|for))\b', "market_pulse", 0.75)

# CODE SANDBOX — build code, websites, scripts, tools
_p(r'\b(build (me )?(a )?website|create (me )?(a )?website)\b', "code_sandbox", 1.0)
_p(r'\b(write (me )?(a |some )?(code|script|program|function))\b', "code_sandbox", 1.0)
_p(r'\b(build (me )?(a )?((web )?page|landing page|app|tool|bot))\b', "code_sandbox", 1.0)
_p(r'\b(create (me )?(a )?(web ?page|landing page|html|app))\b', "code_sandbox", 1.0)
_p(r'\b(python (script|code|program)|javascript (code|script))\b', "code_sandbox", 1.0)
_p(r'\b(code (this|it|for me)|program (this|it))\b', "code_sandbox", 0.9)
_p(r'\b(write (me )?(a )?bot|build (a )?bot|create (a )?bot)\b', "code_sandbox", 0.9)
_p(r'\b(automate (with|using) (python|javascript|code))\b', "code_sandbox", 0.9)
_p(r'\b(facebook.?styled|twitter.?styled|clone|like (facebook|instagram|twitter))\b', "code_sandbox", 0.85)

# MENTOR — conversational, educational, advisory
_p(r'\b(what is|what are|explain|tell me (about|how)|how does)\b', "mentor_chat", 0.8)
_p(r'\b(is it worth|should i|do you think|what do you think)\b', "mentor_chat", 0.8)
_p(r'\b(how (much|long|hard)|what.?s (the best|a good))\b', "mentor_chat", 0.75)


def _classify_message(
    message: str,
    history: Optional[List[Dict]] = None,
) -> Dict[str, Any]:
    """
    Classify a message into an intent.
    Returns {intent, confidence, platform, sub_intent, urgency}
    """
    t     = message.lower().strip()
    words = t.split()

    # ── Score each intent ──────────────────────────────────────────────────
    scores: Dict[str, float] = {
        "apex": 0.0, "workflow": 0.0,
        "market_pulse": 0.0, "code_sandbox": 0.0, "mentor_chat": 0.0,
    }

    for pattern, intent, weight in _INTENT_PATTERNS:
        if pattern.search(t):
            scores[intent] = max(scores[intent], weight)

    # ── Greeting / very short → mentor ─────────────────────────────────────
    greetings = {"hi", "hello", "hey", "sup", "yo", "howdy", "hola",
                 "good morning", "good evening", "good afternoon",
                 "what's up", "how are you"}
    if t in greetings or (len(words) <= 2 and scores["apex"] < 0.5):
        return _result("mentor_chat", 0.95, None, t, "Greeting")

    # ── Pure question → mentor ──────────────────────────────────────────────
    q_starts = ("what ", "how ", "why ", "when ", "where ", "who ", "is ",
                 "can ", "does ", "do ", "which ", "explain ")
    if t.endswith("?") or any(t.startswith(q) for q in q_starts):
        if scores["apex"] < 0.7 and scores["code_sandbox"] < 0.7:
            scores["mentor_chat"] = max(scores["mentor_chat"], 0.75)

    # ── Platform detection ──────────────────────────────────────────────────
    platform = _detect_platform(t)
    if platform and scores["apex"] > 0.0:
        scores["apex"] = min(1.0, scores["apex"] * 1.3)

    # ── Context from last assistant message ─────────────────────────────────
    if history:
        last_ai = next(
            (m["content"].lower() for m in reversed(history)
             if m.get("role") == "assistant"), "")
        confirmations = {"ok", "yes", "yeah", "sure", "go", "do it",
                         "sounds good", "let's go", "perfect", "alright",
                         "go ahead", "start", "proceed", "great"}
        if t in confirmations or len(words) <= 3:
            if any(w in last_ai for w in
                   ["apex", "automate", "handle this", "set it up",
                    "execute", "do it for you", "activating"]):
                return _result("apex", 0.95, platform, t,
                               "Confirmed APEX from prior message")
            if any(w in last_ai for w in
                   ["workflow", "plan", "roadmap", "strategy", "step-by-step"]):
                return _result("workflow", 0.90, platform, t,
                               "Confirmed workflow from prior message")

    # ── Pick winner ─────────────────────────────────────────────────────────
    best  = max(scores, key=lambda k: scores[k])
    score = scores[best]

    if score < 0.1:
        return _result("mentor_chat", 0.85, platform, t,
                       "No strong signal — default to mentor")

    sub = _detect_sub_intent(t, best, platform)
    return _result(best, min(1.0, score), platform, t,
                   f"Matched intent={best}", sub)


def _detect_platform(t: str) -> Optional[str]:
    platforms = {
        "upwork": ["upwork"], "fiverr": ["fiverr"],
        "youtube": ["youtube", " yt "], "tiktok": ["tiktok", "tik tok"],
        "shopify": ["shopify"], "etsy": ["etsy"],
        "amazon": ["amazon", "amazon fba", " fba "],
        "facebook": ["facebook marketplace", "fb marketplace", "facebook shop"],
        "instagram": ["instagram", " ig "], "linkedin": ["linkedin"],
        "twitter": ["twitter", "x.com"], "clickbank": ["clickbank"],
        "jiji": ["jiji"], "freelancer": ["freelancer.com"],
        "toptal": ["toptal"], "gumroad": ["gumroad"],
        "replit": ["replit"], "github": ["github"],
        "ebay": ["ebay"], "paypal": ["paypal"], "stripe": ["stripe"],
    }
    for plat, aliases in platforms.items():
        if any(a in t for a in aliases):
            return plat
    return None


def _detect_sub_intent(t: str, intent: str, platform: Optional[str]) -> Optional[str]:
    if intent == "apex":
        if platform: return f"{platform}_setup"
        if any(w in t for w in ["profile", "bio", "description"]): return "profile_setup"
        if any(w in t for w in ["proposal", "apply", "bid"]): return "proposal_submission"
        if any(w in t for w in ["email", "outreach", "cold"]): return "outreach"
        if any(w in t for w in ["post", "publish", "upload"]): return "content_publishing"
        if any(w in t for w in ["form", "register", "sign up"]): return "account_creation"
    elif intent == "workflow":
        if platform: return f"{platform}_income_plan"
        if any(w in t for w in ["freelance"]): return "freelance_plan"
        if any(w in t for w in ["youtube", "content", "video"]): return "content_plan"
        if any(w in t for w in ["ecommerce", "store", "sell"]): return "ecommerce_plan"
        if any(w in t for w in ["trade", "forex", "crypto"]): return "trading_plan"
        if any(w in t for w in ["affiliate", "commission"]): return "affiliate_plan"
    elif intent == "market_pulse":
        if any(w in t for w in ["job", "gig", "work"]): return "job_scan"
        if any(w in t for w in ["supplier", "wholesale"]): return "supplier_search"
        if any(w in t for w in ["trend"]): return "trend_analysis"
        if any(w in t for w in ["client", "customer", "lead"]): return "lead_generation"
    elif intent == "code_sandbox":
        if any(w in t for w in ["website", "page", "html"]): return "web_page"
        if any(w in t for w in ["bot", "automation", "script"]): return "automation_script"
        if any(w in t for w in ["app", "tool"]): return "mini_app"
    return None


def _result(intent, confidence, platform, t, reason, sub_intent=None):
    urgency = "now"
    if any(w in t for w in ["plan", "strategy", "eventually", "thinking", "maybe"]):
        urgency = "explore"
    elif any(w in t for w in ["step", "guide", "how to", "roadmap"]):
        urgency = "plan"
    return {
        "intent":     intent,
        "confidence": round(confidence, 2),
        "sub_intent": sub_intent,
        "platform":   platform,
        "urgency":    urgency,
        "reason":     reason,
    }


# ─────────────────────────────────────────────────────────────────────────────
# DISPATCHER CLASS
# ─────────────────────────────────────────────────────────────────────────────

class RiseUpDispatcher:
    """
    Classifies a message and returns a routing decision with
    the exact endpoint to call, payload shape, and context enrichments.
    """

    def route(
        self,
        message: str,
        profile: Optional[Dict] = None,
        history: Optional[List[Dict]] = None,
    ) -> Dict[str, Any]:
        classification = _classify_message(message, history)
        intent     = classification["intent"]
        platform   = classification["platform"]
        sub_intent = classification["sub_intent"]
        confidence = classification["confidence"]

        routing = {
            "intent":     intent,
            "confidence": confidence,
            "platform":   platform,
            "sub_intent": sub_intent,

            # Which feature to activate
            "activate_apex":        intent == "apex",
            "activate_workflow":    intent == "workflow",
            "activate_market":      intent == "market_pulse",
            "activate_code":        intent == "code_sandbox",
            "use_mentor_chat":      intent == "mentor_chat",

            # Which endpoints to call
            "primary_endpoint":    self._primary_endpoint(intent),
            "secondary_endpoints": self._secondary_endpoints(intent, sub_intent),

            # Context instructions for the AI
            "ai_instruction":      self._ai_instruction(intent, platform, sub_intent, profile),

            # Delegation payload for Flutter
            "delegation": self._delegation_payload(intent, message, platform, sub_intent),

            # Whether to escalate after AI response
            "escalate_to_apex": intent == "apex",
            "apex_task":        message if intent == "apex" else None,
        }
        return routing

    def _primary_endpoint(self, intent: str) -> str:
        return {
            "apex":        ENDPOINT_MAP["apex_run"],
            "workflow":    ENDPOINT_MAP["workflow_create"],
            "market_pulse": ENDPOINT_MAP["market_scan"],
            "code_sandbox": ENDPOINT_MAP["code_run"],
            "mentor_chat": ENDPOINT_MAP["mentor_chat"],
        }.get(intent, ENDPOINT_MAP["mentor_chat"])

    def _secondary_endpoints(self, intent: str, sub_intent: Optional[str]) -> List[str]:
        extras = {
            "apex": [
                ENDPOINT_MAP["apex_classify"],
                ENDPOINT_MAP["apex_tokens"],
            ],
            "workflow": [
                ENDPOINT_MAP["workflow_research"],
                ENDPOINT_MAP["methods_search"],
            ],
            "market_pulse": [
                ENDPOINT_MAP["market_today"],
                ENDPOINT_MAP["market_scan"],
                ENDPOINT_MAP["market_comprehensive"],
            ],
            "code_sandbox": [
                ENDPOINT_MAP["code_stream"],
            ],
            "mentor_chat": [
                ENDPOINT_MAP["methods_search"],
            ],
        }
        return extras.get(intent, [])

    def _ai_instruction(
        self,
        intent: str,
        platform: Optional[str],
        sub_intent: Optional[str],
        profile: Optional[Dict],
    ) -> str:
        country = (profile or {}).get("country", "")

        if intent == "apex":
            plat_str = f" on **{platform.title()}**" if platform else ""
            return (
                f"[APEX INSTRUCTION] The user wants APEX to execute this task{plat_str}. "
                f"Sub-intent: {sub_intent or 'general_execution'}. "
                "In your response: (1) Confirm you're activating APEX, "
                "(2) List 3-5 specific steps APEX will take in bullet points, "
                "(3) End EXACTLY with: 'Activating APEX to handle this end-to-end for you. 🤖⚡' "
                "— this phrase triggers the agent in Flutter."
            )

        if intent == "workflow":
            plat_str = f" for {platform.title()}" if platform else ""
            return (
                f"[WORKFLOW INSTRUCTION] Build a concrete income plan{plat_str}. "
                f"Country: {country}. Sub-intent: {sub_intent or 'income_plan'}. "
                "Use the 90-day sprint framework. Include: "
                "daily actions, weekly milestones, realistic first income timeline, "
                "exact tools and platforms with URLs, income potential in local currency. "
                "Format with clear sections. End by offering: "
                "'Want me to activate APEX to execute step 1 right now? Just say go ahead.'"
            )

        if intent == "market_pulse":
            return (
                f"[MARKET PULSE INSTRUCTION] User wants live opportunities. "
                f"Country: {country}. "
                "Give 3-5 REAL, specific opportunities available RIGHT NOW. "
                "For each: platform name, niche, income potential, time to first money, "
                "and exact first step with a real URL. "
                "Use the live data provided above if available."
            )

        if intent == "code_sandbox":
            return (
                "[CODE SANDBOX INSTRUCTION] User wants working code. "
                "Write COMPLETE, copy-paste-ready code. NO placeholders. NO '...' gaps. "
                "For websites: full HTML + CSS + JS in a single file. "
                "For Python: all imports + working main() + example usage. "
                "After the code, offer: "
                "'Want APEX to deploy this for you? Just say go ahead.'"
            )

        # mentor_chat
        return (
            "[MENTOR INSTRUCTION] Give specific, direct advice. "
            f"Country: {country}. "
            "Use real numbers, real platforms, real timelines. "
            "End with ONE concrete next action they can take in the next 24 hours."
        )

    def _delegation_payload(
        self,
        intent: str,
        message: str,
        platform: Optional[str],
        sub_intent: Optional[str],
    ) -> Optional[Dict]:
        if intent == "apex":
            return {
                "type":             "apex",
                "task":             message,
                "platform":         platform,
                "sub_intent":       sub_intent,
                "escalate_to_apex": True,
                "apex_task":        message,
                "endpoint":         ENDPOINT_MAP["apex_run"],
            }
        if intent == "workflow":
            return {
                "type":       "workflow",
                "goal":       message,
                "platform":   platform,
                "sub_intent": sub_intent,
                "endpoint":   ENDPOINT_MAP["workflow_create"],
            }
        if intent == "market_pulse":
            return {
                "type":     "market_pulse",
                "query":    message,
                "endpoint": ENDPOINT_MAP["market_scan"],
            }
        if intent == "code_sandbox":
            return {
                "type":     "code_sandbox",
                "task":     message,
                "endpoint": ENDPOINT_MAP["code_run"],
            }
        return None


# ── Singleton ─────────────────────────────────────────────────────────────────
dispatcher = RiseUpDispatcher()

