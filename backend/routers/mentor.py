"""
backend/routers/mentor.py
RiseUp AI Mentor — Production v1.1

v1.1 fix: removed `from __future__ import annotations`.
  Pydantic v2 cannot resolve forward-reference strings created by that import
  when the model classes are used as FastAPI endpoint parameters, raising
  "name 'MentorChatRequest' is not defined" at startup.

The Mentor is the user's personal wealth coach.
It automatically detects when tasks should delegate to:
  • APEX Agent     — "do it for me" tasks
  • Workflow Engine — "build me a plan" tasks
  • Web search     — "find me X" tasks

All AI providers used in fallback chain (matching ai_service.py order):
  Free:    Groq (Llama-3.3-70b) → Gemini 2.0 Flash
  Premium: GPT-4o-mini → Claude 3.5 Haiku → Gemini 1.5 Pro → Groq

Endpoints:
  POST /mentor/chat          — main conversational endpoint
  POST /mentor/chat/stream   — SSE streaming version
  GET  /mentor/session/{id}  — session message history
  GET  /mentor/sessions      — list user's sessions
  POST /mentor/daily-checkin — proactive daily coaching
  GET  /mentor/profile-status — profile completeness
  POST /mentor/feedback      — session rating
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from middleware.rate_limit import limiter, AI_LIMIT, FREE_TIER_LIMIT
from services.ai_service import ai_service, RISEUP_MENTOR_PROMPT, SmartOnboardingManager
from services.intent_classifier import classify_with_context, should_include_market_pulse
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/mentor", tags=["AI Mentor"])
logger = logging.getLogger(__name__)

# ── Brain (graceful optional import) ─────────────────────────────────────────
try:
    from services.riseup_brain_service import search_riseup_brain, build_brain_context_prompt
    from services.adaptive_brain_service import build_adaptive_context_prompt
    _BRAIN_ENABLED = True
except Exception:
    _BRAIN_ENABLED = False


# ═════════════════════════════════════════════════════════════════════════════
# INTENT ROUTING (powered by intent_classifier.py)
# ═════════════════════════════════════════════════════════════════════════════

def _detect_delegation(
    message: str,
    profile: Optional[Dict] = None,
    history: Optional[List[Dict]] = None,
) -> Optional[str]:
    """
    Uses the smart intent classifier to route messages.
    Returns: 'apex' | 'workflow' | 'market_pulse' | 'code_sandbox' | 'search' | None
    """
    result = classify_with_context(message, profile, history)
    intent     = result.get("intent", "mentor_chat")
    confidence = result.get("confidence", 0.0)

    if intent == "mentor_chat" or confidence < 0.15:
        return None

    # Map classifier intents to delegation keys
    mapping = {
        "apex":         "apex",
        "workflow":     "workflow",
        "market_pulse": "market_pulse",
        "code_sandbox": "code_sandbox",
    }
    return mapping.get(intent)


def _get_intent_details(
    message: str,
    profile: Optional[Dict] = None,
    history: Optional[List[Dict]] = None,
) -> Dict:
    """Returns full classification dict for rich routing decisions."""
    return classify_with_context(message, profile, history)


# ═════════════════════════════════════════════════════════════════════════════
# REQUEST / RESPONSE MODELS
# ═════════════════════════════════════════════════════════════════════════════

class MentorChatRequest(BaseModel):
    message:       str
    session_id:    Optional[str] = None
    language:      Optional[str] = None
    stream:        bool          = False
    include_brain: bool          = True


class MentorCheckInRequest(BaseModel):
    session_id: Optional[str] = None
    mood:       Optional[str] = None


class MentorFeedbackRequest(BaseModel):
    session_id: str
    rating:     int = Field(ge=1, le=5)
    comment:    Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════════════════════

async def _get_profile(user_id: str) -> Dict[str, Any]:
    try:
        return await supabase_service.get_profile(user_id) or {}
    except Exception:
        return {}


async def _get_brain_context(query: str, user_id: str, country: str) -> str:
    if not _BRAIN_ENABLED:
        return ""
    try:
        brain_result, adaptive = await asyncio.gather(
            search_riseup_brain(
                query=query, user_id=user_id,
                user_country=country, limit=3,
            ),
            build_adaptive_context_prompt(user_id),
            return_exceptions=True,
        )
        parts = []
        if isinstance(brain_result, dict) and brain_result.get("total_found", 0) > 0:
            parts.append(build_brain_context_prompt(brain_result))
        if isinstance(adaptive, str) and adaptive:
            parts.append(adaptive)
        return "\n\n".join(parts)
    except Exception:
        return ""


async def _load_history(session_id: str, user_id: str, limit: int = 20) -> List[Dict]:
    try:
        sb   = supabase_service.client
        msgs = (
            sb.table("mentor_messages")
            .select("role,content")
            .eq("session_id", session_id)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
            .data or []
        )
        return [
            {"role": m["role"], "content": m["content"]}
            for m in reversed(msgs)
            if m["role"] in ("user", "assistant")
        ]
    except Exception:
        return []


async def _save_message(
    session_id: str,
    user_id: str,
    role: str,
    content: str,
    model: str = "",
) -> None:
    try:
        sb = supabase_service.client
        sb.table("mentor_messages").insert({
            "session_id": session_id,
            "user_id":    user_id,
            "role":       role,
            "content":    content,
            "metadata":   {"model_used": model},
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
        sb.table("mentor_sessions").update({
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", session_id).execute()
    except Exception as e:
        logger.error("_save_message: %s", e)


def _make_title(message: str) -> str:
    """Generate a short mission title from the user's first message."""
    import re
    msg   = re.sub(r"[#*_`>]", "", message).strip()
    words = msg.split()
    if len(words) <= 6:
        return msg.capitalize()
    # Take first 6 meaningful words
    return " ".join(words[:6]).capitalize() + "..."


async def _ensure_session(
    user_id: str,
    title: str = "",
    session_id: str = "",
) -> str:
    """
    Creates or validates a mentor session.
    Uses upsert so Flutter-generated UUIDs become valid DB rows.
    The session title is set ONCE on creation and never overwritten.
    """
    import uuid as _uuid
    sb  = supabase_service.client
    now = datetime.now(timezone.utc).isoformat()
    sid = session_id or str(_uuid.uuid4())
    final_title = title or f"Mission {datetime.now().strftime('%d %b, %H:%M')}"

    try:
        # Check existence first
        try:
            existing = (
                sb.table("mentor_sessions")
                .select("id, title")
                .eq("id", sid)
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )
            row = (existing.data if existing is not None else None) or {}
            if row:
                return sid  # already exists — never touch its title
        except Exception:
            pass

        # Insert new session — use upsert so duplicate IDs don't error
        sb.table("mentor_sessions").upsert(
            {
                "id":         sid,
                "user_id":    user_id,
                "title":      final_title,
                "emoji":      "🎯",
                "status":     "active",
                "created_at": now,
                "updated_at": now,
            },
            on_conflict="id",
            ignore_duplicates=True,       # keep existing row if already present
        ).execute()
        return sid

    except Exception as e:
        logger.error("_ensure_session: %s", e)
        return sid  # still return the sid so chat can proceed


def _build_system_prompt(
    profile: Dict[str, Any],
    brain_ctx: str,
    language: str,
    is_first_message: bool = False,
) -> str:
    lang_note  = f"\nRespond in language ISO: {language}." if language != "en" else ""
    brain_note = (
        f"\n\n[RISEUP BRAIN CONTEXT — use this to enhance advice]\n{brain_ctx}"
        if brain_ctx else ""
    )
    onboarding = SmartOnboardingManager.build_onboarding_injection(profile)

    first_msg_note = ""
    if is_first_message:
        name = profile.get("full_name") or profile.get("username") or "there"
        first_msg_note = (
            f"\n\n[FIRST MESSAGE INSTRUCTION] This is the user's very first message. "
            f"In 1-2 short natural sentences, introduce yourself as RiseUp — an AI AGENT "
            f"that doesn't just advise but actually executes tasks (sets up accounts, sends "
            f"proposals, builds pages, finds clients) using APEX and other tools. "
            f"Use the user's name ({name}) if known. Sound like a smart friend who shows up "
            f"and actually does the work. Then immediately respond to what they said."
        )

    # Always inject agent-identity reminder so AI never slips back to advisor mode
    agent_reminder = (
        "\n\n[AGENT IDENTITY REMINDER] You are an execution agent, not just an advisor. "
        "Every response should move the user closer to action. "
        "If a task is executable → offer APEX. "
        "If a plan is needed → trigger the Workflow Engine. "
        "If live data is needed → use Market Pulse. "
        "If code/pages are needed → use Code Sandbox. "
        "NEVER just give advice when you can take action."
    )

    return RISEUP_MENTOR_PROMPT + lang_note + brain_note + onboarding + first_msg_note + agent_reminder


def _sse(event: str, data: Any) -> str:
    payload = data if isinstance(data, str) else json.dumps(data)
    return f"event: {event}\ndata: {payload}\n\n"


# ═════════════════════════════════════════════════════════════════════════════
# MAIN CHAT ENDPOINT
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/chat")
@limiter.limit(AI_LIMIT)
async def mentor_chat(
    req:     MentorChatRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    user_id  = user["id"]
    profile  = await _get_profile(user_id)
    language = req.language or profile.get("language", "en")
    country  = profile.get("country", "US")

    # Ensure / reuse session
    # Always call _ensure_session — creates or validates the session row.
    # Title is set from first message and never overwritten after that.
    session_id = await _ensure_session(
        user_id,
        title=_make_title(req.message),
        session_id=req.session_id or "",
    )

    # Load prior history so the mentor has context
    history = await _load_history(session_id, user_id)

    # First message ever → inject intro instruction into system prompt
    is_first_message = len(history) == 0

    # Brain context (non-blocking failure)
    brain_ctx = ""
    if req.include_brain:
        brain_ctx = await _get_brain_context(req.message, user_id, country)

    # ── Smart intent routing ─────────────────────────────────────────────────
    intent_result  = _get_intent_details(req.message, profile, history)
    delegation     = _detect_delegation(req.message, profile, history)
    delegation_payload: Optional[Dict] = None
    platform       = intent_result.get("platform")
    sub_intent     = intent_result.get("sub_intent")

    if delegation == "apex":
        apex_msg = (
            f"🤖 **APEX activated.** I'll handle this end-to-end for you"
            + (f" on **{platform.title()}**" if platform else "")
            + f".\n\nHere's what I'm about to do:"
        )
        delegation_payload = {
            "type":       "apex",
            "task":       req.message,
            "platform":   platform,
            "sub_intent": sub_intent,
            "session_id": session_id,
            "message":    apex_msg,
            "escalate_to_apex": True,
            "apex_task":  req.message,
        }
        # Let AI describe what APEX will do, then signal Flutter to launch it
        brain_ctx += (
            f"\n\n[APEX INSTRUCTION] The user wants APEX to execute this task. "
            f"Platform detected: {platform or 'general'}. Sub-intent: {sub_intent or 'general_execution'}. "
            f"In your response: briefly describe what APEX will do step by step (3-5 bullet points). "
            f"End with: 'Activating APEX to handle this end-to-end for you. 🤖⚡' — this triggers the agent."
        )

    elif delegation == "workflow":
        delegation_payload = {
            "type":       "workflow",
            "goal":       req.message,
            "platform":   platform,
            "sub_intent": sub_intent,
            "message":    "Building your income workflow... ⚡",
        }
        # Enrich context so AI builds a proper workflow response
        brain_ctx += (
            f"\n\n[WORKFLOW INSTRUCTION] User wants a concrete income plan. "
            f"Platform: {platform or 'any'}. Sub-intent: {sub_intent or 'income_plan'}. "
            f"Build a structured step-by-step workflow. Use the 90-day sprint framework. "
            f"Include: daily actions, weekly milestones, first income estimate, tools needed. "
            f"Format with clear sections. End by offering APEX execution for the first step."
        )

    elif delegation == "market_pulse":
        # Trigger live market scan
        try:
            from services.market_pulse_service import market_pulse_service
            market_data = await market_pulse_service.scan_opportunities(
                user_id=user_id,
                country=country,
                skills=profile.get("skills", []),
                limit=5,
            )
            if market_data:
                brain_ctx += (
                    "\n\n[LIVE MARKET DATA]\n" +
                    "\n".join(f"• {o.get('title','')} — {o.get('ai_summary','')}"
                               for o in market_data[:4])
                )
        except Exception:
            # Fallback to web search
            try:
                from services.web_search_service import web_search_service
                results   = await web_search_service.search(
                    f"{req.message} opportunities {country}", num=5)
                brain_ctx += (
                    "\n\n[LIVE SEARCH]\n" +
                    "\n".join(f"- {r.get('title','')}: {r.get('snippet','')}"
                               for r in results[:4])
                )
            except Exception:
                pass
        brain_ctx += (
            "\n\n[MARKET PULSE INSTRUCTION] Use the live data above to give "
            "specific, actionable opportunities with real numbers and links. "
            "Always include: platform, niche, income potential, and first step."
        )

    elif delegation == "code_sandbox":
        brain_ctx += (
            "\n\n[CODE SANDBOX INSTRUCTION] User wants code built. "
            "Write complete, working code. No placeholders. "
            "For web pages: write full HTML/CSS/JS in one file. "
            "For Python: include all imports and a working main() function. "
            "After the code, offer APEX to deploy or run it automatically."
        )

    else:
        # Pure mentor chat — check if we should add a search enrichment
        search_triggers = ["find", "price", "contact", "supplier", "number",
                           "latest", "current", "news", "best", "compare"]
        if any(t in req.message.lower() for t in search_triggers):
            try:
                from services.web_search_service import web_search_service
                results   = await web_search_service.search(req.message, num=4)
                brain_ctx += (
                    "\n\n[WEB SEARCH]\n" +
                    "\n".join(f"- {r.get('title','')}: {r.get('snippet','')}"
                               for r in results[:3])
                )
            except Exception:
                pass

    system   = _build_system_prompt(profile, brain_ctx, language, is_first_message)
    messages = history + [{"role": "user", "content": req.message}]

    # Deduct tokens before calling AI
    try:
        from services.token_service import token_service
        tok = await token_service.deduct(
            user_id   = user_id,
            tool_name = "chat_message",
            is_premium= profile.get("is_premium", False) or
                        profile.get("subscription_tier", "free") != "free",
        )
        if not tok.get("allowed", True):
            return {
                "reply":      "⚡ You've used all your tokens for today. Watch an ad or upgrade to keep going!",
                "content":    "⚡ You've used all your tokens for today. Watch an ad or upgrade to keep going!",
                "session_id": session_id,
                "exhausted":  True,
                "can_redeem_ads": tok.get("can_redeem_ads", True),
            }
    except Exception as te:
        logger.warning("token deduct error: %s", te)

    result     = await ai_service.mentor_chat(
        messages=messages,
        user_profile=profile,
        system_prompt=system,
        max_tokens=2048,
    )
    content    = result.get("content", "")
    model_used = result.get("model", "unknown")

    await _save_message(session_id, user_id, "user",      req.message)
    await _save_message(session_id, user_id, "assistant", content, model_used)

    # Extract profile signals and persist them silently
    signals = SmartOnboardingManager.extract_profile_signals(req.message, profile)
    if signals:
        try:
            supabase_service.client.table("profiles").update(
                signals
            ).eq("id", user_id).execute()
        except Exception:
            pass

    return {
        "reply":            content,
        "content":          content,      # backwards compat
        "session_id":       session_id,
        "model_used":       model_used,
        "delegation":       delegation_payload,
        "escalate_to_apex": delegation_payload.get("escalate_to_apex", False) if delegation_payload else False,
        "apex_task":        delegation_payload.get("apex_task") if delegation_payload else None,
        "session_title":    _make_title(req.message) if is_first_message else None,
        "brain_used":       bool(brain_ctx),
        "language":         language,
        "intent":           intent_result.get("intent"),
        "platform":         intent_result.get("platform"),
    }


# ═════════════════════════════════════════════════════════════════════════════
# STREAMING CHAT
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/chat/stream")
@limiter.limit(AI_LIMIT)
async def mentor_chat_stream(
    req:     MentorChatRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    user_id  = user["id"]
    profile  = await _get_profile(user_id)
    language = req.language or profile.get("language", "en")
    country  = profile.get("country", "US")

    session_id = req.session_id
    if not session_id:
        session_id = await _ensure_session(user_id, title=req.message[:40])

    async def generate():
        yield _sse("session_id", {"session_id": session_id})

        delegation = _detect_delegation(req.message)

        if delegation == "apex":
            yield _sse("delegation", {
                "type":       "apex",
                "task":       req.message,
                "session_id": session_id,
                "message":    "Activating APEX to handle this for you. 🤖⚡",
            })
            content = (
                "Activating APEX to handle this for you. 🤖⚡\n\n"
                "I'm handing this task to APEX — your autonomous agent. "
                "It will open the browser, complete the task, and report back. "
                "Tap **Launch APEX** below to start."
            )

        elif delegation == "workflow":
            yield _sse("delegation", {
                "type":    "workflow",
                "goal":    req.message,
                "message": "Opening Workflow Engine to build your plan. ⚡",
            })
            content = (
                "Let me build you a full income plan for this. ⚡\n\n"
                "Tap **Build Workflow** below and I'll research opportunities, "
                "build a step-by-step execution plan, and track your progress."
            )

        else:
            brain_ctx = ""
            if req.include_brain:
                brain_ctx = await _get_brain_context(req.message, user_id, country)
                if brain_ctx:
                    yield _sse("brain_context", {"found": True})

            if delegation == "search":
                try:
                    from services.web_search_service import web_search_service
                    results   = await web_search_service.search(req.message, num=5)
                    brain_ctx += (
                        "\n\n[LIVE SEARCH RESULTS]\n" +
                        "\n".join(
                            f"- {r.get('title', '')}: {r.get('snippet', '')}"
                            for r in results[:4]
                        )
                    )
                    yield _sse("search_done", {"results": len(results)})
                except Exception:
                    pass

            history  = await _load_history(session_id, user_id)
            system   = _build_system_prompt(profile, brain_ctx, language)
            messages = history + [{"role": "user", "content": req.message}]

            result     = await ai_service.mentor_chat(
                messages=messages,
                user_profile=profile,
                system_prompt=system,
                max_tokens=2048,
            )
            content    = result.get("content", "")
            model_used = result.get("model", "unknown")

            # Stream word-by-word for live typing effect
            words = content.split()
            for i, word in enumerate(words):
                chunk = word + (" " if i < len(words) - 1 else "")
                yield _sse("token", {"content": chunk})
                await asyncio.sleep(0.008)

        await _save_message(session_id, user_id, "user",      req.message)
        await _save_message(session_id, user_id, "assistant", content)

        signals = SmartOnboardingManager.extract_profile_signals(req.message, profile)
        if signals:
            try:
                supabase_service.client.table("profiles").update(
                    signals
                ).eq("id", user_id).execute()
            except Exception:
                pass

        brain_used = bool(brain_ctx) if delegation not in ("apex", "workflow") else False
        yield _sse("complete", {
            "content":    content,
            "session_id": session_id,
            "delegation": delegation,
            "brain_used": brain_used,
            "language":   language,
        })

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":    "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ═════════════════════════════════════════════════════════════════════════════
# SESSION HISTORY
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/session/{session_id}")
async def get_session_history(
    session_id: str,
    limit:      int  = 50,
    user:       dict = Depends(get_current_user),
):
    messages = await _load_history(session_id, user["id"], limit=limit)
    return {
        "session_id": session_id,
        "messages":   messages,
        "count":      len(messages),
    }


@router.get("/sessions")
async def list_mentor_sessions(
    limit: int  = 20,
    user:  dict = Depends(get_current_user),
):
    try:
        sb   = supabase_service.client
        data = (
            sb.table("mentor_sessions")
            .select("id,title,updated_at,created_at")
            .eq("user_id", user["id"])
            .eq("status", "active")
            .order("updated_at", desc=True)
            .limit(limit)
            .execute()
            .data or []
        )
        return {"sessions": data}
    except Exception as e:
        raise HTTPException(500, f"Failed to list sessions: {e}")


# ═════════════════════════════════════════════════════════════════════════════
# DAILY CHECK-IN
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/daily-checkin")
@limiter.limit(FREE_TIER_LIMIT)
async def daily_checkin(
    req:     MentorCheckInRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    user_id = user["id"]
    profile = await _get_profile(user_id)
    name    = (profile.get("full_name") or "").split(" ")[0] or "there"
    stage   = profile.get("stage",            "survival")
    goal    = profile.get("short_term_goal",  "")
    country = profile.get("country",          "US")
    income  = profile.get("monthly_income",   0)

    mood_context = f" They said they're feeling: {req.mood}." if req.mood else ""

    prompt = (
        f"Give {name} a powerful, specific daily wealth check-in message. "
        f"Stage: {stage}. Goal: {goal}. Country: {country}. "
        f"Monthly income: {income}.{mood_context}\n\n"
        "Include:\n"
        "1. One energising observation about their progress\n"
        "2. Today's single most important income action (specific, with platform/URL)\n"
        "3. One mindset challenge\n"
        "Keep it under 150 words. Be direct and personal. No fluff."
    )
    result = await ai_service.mentor_chat(
        messages=[{"role": "user", "content": prompt}],
        user_profile=profile,
        system_prompt=RISEUP_MENTOR_PROMPT,
        max_tokens=300,
    )
    return {
        "checkin":    result.get("content", ""),
        "model_used": result.get("model",   ""),
        "date":       datetime.now(timezone.utc).strftime("%A, %B %d"),
    }


# ═════════════════════════════════════════════════════════════════════════════
# PROFILE STATUS
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/profile-status")
async def profile_status(user: dict = Depends(get_current_user)):
    profile = await _get_profile(user["id"])
    return ai_service.get_profile_completeness(profile)


# ═════════════════════════════════════════════════════════════════════════════
# FEEDBACK
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/feedback")
@limiter.limit(FREE_TIER_LIMIT)
async def submit_feedback(
    req:     MentorFeedbackRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    try:
        supabase_service.client.table("mentor_feedback").insert({
            "user_id":    user["id"],
            "session_id": req.session_id,
            "rating":     req.rating,
            "comment":    req.comment or "",
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
        return {"saved": True}
    except Exception as e:
        raise HTTPException(500, f"Failed to save feedback: {e}")
