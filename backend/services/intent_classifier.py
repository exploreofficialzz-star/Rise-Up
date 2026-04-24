"""
backend/services/intent_classifier.py
RiseUp Intent Classification Engine — v1.0

Classifies any user message into the right handler:
  mentor_chat   — conversational advice, questions, planning, learning
  apex          — "do it for me" execution tasks (browser agent)
  workflow      — build an income plan / multi-step roadmap
  market_pulse  — real-time opportunity scanning, trends, leads
  code_sandbox  — build/run code, create web pages, scripts
  search        — find contacts, prices, live information

Each classification returns:
  {
    "intent":      str,           # one of the above
    "confidence":  float,         # 0.0–1.0
    "sub_intent":  str | None,    # e.g. "upwork_setup", "youtube_channel"
    "platform":    str | None,    # detected platform
    "urgency":     str,           # "now" | "plan" | "explore"
    "apex_task":   str | None,    # cleaned task string for APEX if intent==apex
    "reason":      str,           # human-readable why
  }
"""

import re
from typing import Any, Dict, List, Optional, Tuple


# ─────────────────────────────────────────────────────────────────────────────
# SIGNAL LIBRARIES
# ─────────────────────────────────────────────────────────────────────────────

# APEX — user wants the system to DO something on a browser
_APEX_STRONG = [
    "do it for me", "handle it", "set it up for me", "automate this",
    "apply for me", "go ahead", "take care of it", "build this for me",
    "run it", "make it happen", "execute", "just do it", "i'm ready",
    "find me clients", "send the emails", "post this for me",
    "create the account", "create my profile", "open my store",
    "sign me up", "register me", "use apex", "use the agent",
    "start my channel", "create my upwork", "create my fiverr",
    "create my etsy", "create my shopify", "fill the form",
    "complete my profile", "submit my proposal", "send my cv",
    "upload my portfolio", "set up my paypal", "connect my bank",
    "list my product", "publish my gig", "open the website",
    "book the meeting", "send the message", "post the job",
    "start the trade", "place the order", "open the account",
    "submit the application",
]

_APEX_WEAK = [
    "can you do", "can apex", "i want you to", "please do",
    "open upwork", "open fiverr", "open youtube", "open shopify",
    "set up", "help me create", "help me open", "help me start",
    "do this automatically", "automate", "browse", "navigate to",
]

# WORKFLOW — user wants a strategic plan / roadmap
_WORKFLOW_STRONG = [
    "create a workflow", "build a workflow", "make a plan",
    "income plan", "build me a plan", "step by step plan",
    "full plan", "set up income", "side hustle plan",
    "make me a roadmap", "guide me through this",
    "complete guide", "full guide", "full strategy",
    "how do i start earning", "i want to start earning from",
    "how do i start with", "create an income strategy",
    "plan for me", "build my strategy",
]

_WORKFLOW_WEAK = [
    "how do i start", "where do i begin", "first steps",
    "getting started", "what should i do first", "begin",
    "want to earn", "want to make money from",
    "looking to start", "thinking about starting",
]

# MARKET PULSE — real-time data, trends, prices, opportunities
_MARKET_STRONG = [
    "market pulse", "scan for opportunities", "what's trending",
    "find opportunities", "latest opportunities", "current trends",
    "hot niches", "find leads", "find clients now",
    "what's selling", "find suppliers", "find buyers",
    "best selling products", "trending products",
    "market analysis", "competition analysis",
    "what platforms are hot", "where is the money right now",
    "scan jobs", "find freelance jobs", "find gigs",
    "live opportunities", "real time", "right now market",
]

_MARKET_WEAK = [
    "find me", "search for", "look up", "latest news",
    "current price", "who sells", "contact for",
    "phone number", "best deals", "compare prices",
    "cheapest", "most expensive", "find a supplier",
]

# CODE SANDBOX — build code, create web pages, scripts, apps
_CODE_STRONG = [
    "build a website", "create a website", "build a web page",
    "write code", "build an app", "create an app",
    "write a script", "build a bot", "create a tool",
    "build a landing page", "create a landing page",
    "python script", "javascript code", "html page",
    "build me a", "code this", "program this",
    "write me a python", "write me a javascript",
    "create a form", "build a form", "design a page",
    "build a calculator", "create a spreadsheet formula",
]

_CODE_WEAK = [
    "automate with code", "using python", "using javascript",
    "can you code", "need a script", "need code",
]

# PLATFORMS — detect which platform user is talking about
_PLATFORMS = {
    "upwork":       ["upwork", "upwork.com"],
    "fiverr":       ["fiverr", "fiverr.com"],
    "youtube":      ["youtube", "youtube channel", "yt"],
    "tiktok":       ["tiktok", "tik tok"],
    "shopify":      ["shopify"],
    "etsy":         ["etsy"],
    "amazon":       ["amazon", "amazon fba", "fba", "amazon kdp"],
    "toptal":       ["toptal"],
    "linkedin":     ["linkedin"],
    "facebook":     ["facebook marketplace", "fb marketplace", "facebook shop"],
    "instagram":    ["instagram", "ig"],
    "twitter":      ["twitter", "x.com"],
    "clickbank":    ["clickbank"],
    "jiji":         ["jiji"],
    "freelancer":   ["freelancer.com"],
    "99designs":    ["99designs"],
    "teachable":    ["teachable", "thinkific", "kajabi"],
    "gumroad":      ["gumroad"],
    "notion":       ["notion template"],
    "canva":        ["canva"],
    "chatgpt":      ["chatgpt", "openai", "claude"],
    "replit":       ["replit"],
    "github":       ["github", "github pages"],
}


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def _normalise(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower().strip())


def _score(text: str, phrases: List[str]) -> float:
    """Returns 0.0–1.0 match score based on how many phrases match."""
    hits = sum(1 for p in phrases if p in text)
    if not hits:
        return 0.0
    return min(1.0, hits / max(1, len(phrases) ** 0.4))


def _detect_platform(text: str) -> Optional[str]:
    for platform, aliases in _PLATFORMS.items():
        if any(alias in text for alias in aliases):
            return platform
    return None


def _detect_urgency(text: str) -> str:
    if any(w in text for w in ["now", "today", "asap", "immediately",
                                "right now", "i'm ready", "let's go",
                                "start now", "do it"]):
        return "now"
    if any(w in text for w in ["plan", "strategy", "roadmap", "eventually",
                                "thinking", "considering", "maybe", "someday",
                                "when", "eventually"]):
        return "explore"
    return "plan"


def _is_pure_question(text: str) -> bool:
    """Returns True if the message is clearly an informational question."""
    question_starters = [
        "what is", "what are", "how does", "how do i", "why does",
        "explain", "tell me about", "what's the difference",
        "can you explain", "what should i", "which is better",
        "is it worth", "should i", "do you think", "what do you think",
        "how much can i make", "how long does it take",
    ]
    t = text.strip()
    return t.endswith("?") or any(t.startswith(q) for q in question_starters)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN CLASSIFIER
# ─────────────────────────────────────────────────────────────────────────────

def classify_intent(
    message: str,
    profile: Optional[Dict[str, Any]] = None,
    conversation_history: Optional[List[Dict]] = None,
) -> Dict[str, Any]:
    """
    Classify a user message and return routing decision.

    Args:
        message:              The user's raw message
        profile:              User profile dict (optional, improves accuracy)
        conversation_history: Prior messages in this session (optional)

    Returns:
        Classification dict with intent, confidence, platform, urgency, etc.
    """
    t = _normalise(message)

    # ── Scores for each intent ────────────────────────────────────────────────
    apex_score     = _score(t, _APEX_STRONG) * 1.0 + _score(t, _APEX_WEAK) * 0.4
    workflow_score = _score(t, _WORKFLOW_STRONG) * 1.0 + _score(t, _WORKFLOW_WEAK) * 0.35
    market_score   = _score(t, _MARKET_STRONG) * 1.0 + _score(t, _MARKET_WEAK) * 0.3
    code_score     = _score(t, _CODE_STRONG) * 1.0 + _score(t, _CODE_WEAK) * 0.35

    # ── Boost rules ───────────────────────────────────────────────────────────

    # Platform + action verb → APEX boost
    platform = _detect_platform(t)
    if platform and apex_score > 0.05:
        apex_score = min(1.0, apex_score * 1.6)

    # Platform alone (no action verb) → weak workflow/mentor signal
    if platform and apex_score < 0.05:
        workflow_score = min(1.0, workflow_score + 0.15)

    # Pure question → mentor chat
    if _is_pure_question(t):
        return _result("mentor_chat", 0.9, platform, message, t, "Pure question — conversational advice")

    # Very short messages (≤ 4 words) that aren't commands → mentor chat
    word_count = len(t.split())
    if word_count <= 4 and apex_score < 0.3:
        return _result("mentor_chat", 0.8, platform, message, t, "Short conversational message")

    # Greeting / intro → mentor chat
    greetings = ["hi", "hello", "hey", "good morning", "good evening", "what's up",
                 "sup", "hola", "how are you", "i just signed up", "i'm new", "just joined"]
    if any(g in t for g in greetings) and word_count < 10:
        return _result("mentor_chat", 0.95, platform, message, t, "Greeting / intro message")

    # ── Winner selection ──────────────────────────────────────────────────────
    scores = {
        "apex":        apex_score,
        "workflow":    workflow_score,
        "market_pulse": market_score,
        "code_sandbox": code_score,
    }

    best_intent, best_score = max(scores.items(), key=lambda x: x[1])

    # If nothing scored high enough → mentor chat
    if best_score < 0.12:
        return _result("mentor_chat", 0.85, platform, message, t,
                       "No strong signal — default to mentor conversation")

    # Multiple intents tied → pick apex if urgency is "now"
    urgency = _detect_urgency(t)
    if urgency == "now" and apex_score > 0.1:
        best_intent = "apex"
        best_score  = max(best_score, apex_score)

    # Sub-intent detection
    sub_intent = _detect_sub_intent(t, best_intent, platform)

    reason = {
        "apex":        f"User wants something executed{' on ' + platform if platform else ''}",
        "workflow":    f"User wants a plan/strategy{' for ' + platform if platform else ''}",
        "market_pulse": "User wants real-time opportunities or market data",
        "code_sandbox": "User wants code built or a web page created",
    }.get(best_intent, "Conversational advice")

    return _result(best_intent, min(1.0, best_score), platform, message, t,
                   reason, sub_intent, urgency)


def _detect_sub_intent(t: str, intent: str, platform: Optional[str]) -> Optional[str]:
    if intent == "apex":
        if platform:
            return f"{platform}_setup"
        if any(w in t for w in ["profile", "bio", "description"]):
            return "profile_setup"
        if any(w in t for w in ["proposal", "apply", "application"]):
            return "proposal_submission"
        if any(w in t for w in ["email", "outreach", "message"]):
            return "outreach"
        if any(w in t for w in ["post", "publish", "upload", "content"]):
            return "content_publishing"

    elif intent == "workflow":
        if platform:
            return f"{platform}_income_plan"
        if any(w in t for w in ["freelance", "freelancing"]):
            return "freelance_plan"
        if any(w in t for w in ["youtube", "content", "video"]):
            return "content_plan"
        if any(w in t for w in ["ecommerce", "store", "shop", "sell"]):
            return "ecommerce_plan"
        if any(w in t for w in ["trade", "trading", "forex", "crypto"]):
            return "trading_plan"

    elif intent == "market_pulse":
        if any(w in t for w in ["job", "jobs", "gig", "freelance"]):
            return "job_scan"
        if any(w in t for w in ["supplier", "wholesale", "bulk"]):
            return "supplier_search"
        if any(w in t for w in ["trend", "trending", "hot"]):
            return "trend_analysis"
        if any(w in t for w in ["client", "customer", "lead"]):
            return "lead_generation"

    elif intent == "code_sandbox":
        if any(w in t for w in ["website", "landing", "page", "html"]):
            return "web_page"
        if any(w in t for w in ["bot", "automation", "script"]):
            return "automation_script"
        if any(w in t for w in ["app", "tool", "calculator"]):
            return "mini_app"

    return None


def _result(
    intent: str,
    confidence: float,
    platform: Optional[str],
    raw_message: str,
    normalised: str,
    reason: str,
    sub_intent: Optional[str] = None,
    urgency: Optional[str] = None,
) -> Dict[str, Any]:
    return {
        "intent":     intent,
        "confidence": round(confidence, 2),
        "sub_intent": sub_intent,
        "platform":   platform,
        "urgency":    urgency or _detect_urgency(normalised),
        "apex_task":  raw_message if intent == "apex" else None,
        "reason":     reason,
    }


# ─────────────────────────────────────────────────────────────────────────────
# CONTEXT-AWARE CLASSIFIER
# Uses conversation history to improve accuracy
# ─────────────────────────────────────────────────────────────────────────────

def classify_with_context(
    message: str,
    profile: Optional[Dict[str, Any]] = None,
    history: Optional[List[Dict]] = None,
) -> Dict[str, Any]:
    """
    Enhanced classifier that uses prior conversation to resolve ambiguity.

    If the user said "go ahead" or "do it" after a workflow suggestion,
    that's clearly an APEX trigger even though "go ahead" alone is weak.
    """
    base = classify_intent(message, profile, history)

    if not history:
        return base

    # Check what the last assistant message discussed
    last_assistant = next(
        (m["content"] for m in reversed(history) if m.get("role") == "assistant"),
        ""
    )
    last_lower = last_assistant.lower()

    # If last message mentioned a specific task/platform and user says "ok", "yes", "go", "do it"
    short_confirmations = ["ok", "yes", "yeah", "yep", "sure", "go", "do it",
                           "sounds good", "let's go", "great", "perfect", "ok go",
                           "alright", "let's do it", "go ahead", "start"]

    msg_lower = _normalise(message)
    is_confirmation = msg_lower in short_confirmations or len(message.split()) <= 3

    if is_confirmation:
        # Was the last message offering APEX execution?
        if any(w in last_lower for w in ["apex", "automate", "handle this", "do it for you",
                                          "set it up", "execute"]):
            base["intent"]     = "apex"
            base["confidence"] = 0.9
            base["reason"]     = "User confirmed APEX execution from prior message"

        # Was the last message offering a workflow plan?
        elif any(w in last_lower for w in ["workflow", "plan", "roadmap", "step-by-step",
                                            "strategy"]):
            base["intent"]     = "workflow"
            base["confidence"] = 0.85
            base["reason"]     = "User confirmed workflow plan from prior message"

        # Was the last message discussing a platform?
        for platform, aliases in _PLATFORMS.items():
            if any(a in last_lower for a in aliases):
                base["platform"] = platform
                break

    return base


# ─────────────────────────────────────────────────────────────────────────────
# MARKET PULSE DAILY SUMMARY
# Called by scheduler to inject into first message of the day
# ─────────────────────────────────────────────────────────────────────────────

def should_include_market_pulse(
    profile: Dict[str, Any],
    last_market_check: Optional[str] = None,
) -> bool:
    """Returns True if the user should receive a market pulse alert today."""
    from datetime import datetime, timezone, timedelta

    if not last_market_check:
        return True

    try:
        last = datetime.fromisoformat(last_market_check)
        now  = datetime.now(timezone.utc)
        return (now - last) >= timedelta(hours=20)
    except Exception:
        return True


intent_classifier = classify_with_context

