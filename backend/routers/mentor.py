"""
backend/routers/mentor.py
RiseUp AI Mentor — Production v1.0

The Mentor is the user's personal wealth coach.
It automatically detects when tasks should delegate to:
  • APEX Agent     — "do it for me" tasks
  • Workflow Engine — "build me a plan" tasks
  • Web search     — "find me X" tasks

All AI providers used in fallback chain (matching ai_service.py order):
  Free:    Groq (Llama-3.3-70b) → Gemini 1.5 Flash
  Premium: GPT-4o → Claude 3.5 Sonnet → Gemini 1.5 Pro → Groq

Endpoints:
  POST /mentor/chat          — main conversational endpoint
  POST /mentor/chat/stream   — SSE streaming version
  GET  /mentor/session       — session history
  POST /mentor/daily-checkin — proactive daily coaching
  GET  /mentor/profile-status — profile completeness
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from middleware.rate_limit import limiter, AI_LIMIT, FREE_TIER_LIMIT
from services.ai_service import ai_service, RISEUP_MENTOR_PROMPT, SmartOnboardingManager
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/mentor", tags=["AI Mentor"])
logger = logging.getLogger(__name__)

# ── Brain (graceful) ──────────────────────────────────────────────────────────
try:
    from services.riseup_brain_service import search_riseup_brain, build_brain_context_prompt
    from services.adaptive_brain_service import build_adaptive_context_prompt
    _BRAIN_ENABLED = True
except Exception:
    _BRAIN_ENABLED = False


# ═════════════════════════════════════════════════════════════════════════════
# APEX / WORKFLOW TRIGGER DETECTION
# ═════════════════════════════════════════════════════════════════════════════

_APEX_PHRASES = [
    "do it for me", "handle it", "set it up", "automate this",
    "apply for me", "go ahead", "take care of it", "build this for me",
    "run it", "make it happen", "execute", "just do it",
    "find me clients", "send the emails", "post this",
    "create the account", "create my profile", "open my store",
    "set up my", "create my fiverr", "create my upwork",
    "start my channel", "sign me up", "register me",
    "activating apex", "use apex", "use the agent",
]

_WORKFLOW_PHRASES = [
    "create a workflow", "build a workflow", "make a plan for",
    "income plan", "start earning from", "i want to earn",
    "how do i start", "step by step plan", "full plan",
    "set up income", "side hustle plan", "make me a roadmap",
    "help me get started", "guide me through",
]

_SEARCH_PHRASES = [
    "find me", "search for", "look up", "what is the price of",
    "who sells", "suppliers of", "contact for", "phone number of",
    "latest news", "current price", "best deals",
]


def _detect_delegation(message: str) -> Optional[str]:
    """Returns 'apex', 'workflow', 'search', or None."""
    lower = message.lower()
    if any(p in lower for p in _APEX_PHRASES):
        return "apex"
    if any(p in lower for p in _WORKFLOW_PHRASES):
        return "workflow"
    if any(p in lower for p in _SEARCH_PHRASES):
        return "search"
    return None


# ═════════════════════════════════════════════════════════════════════════════
# REQUEST MODELS
# ═════════════════════════════════════════════════════════════════════════════

class MentorChatRequest(BaseModel):
    message:          str
    session_id:       Optional[str] = None
    language:         Optional[str] = None
    stream:           bool          = False
    include_brain:    bool          = True

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
            search_riseup_brain(query=query, user_id=user_id,
                                user_country=country, limit=3),
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
        sb = supabase_service.client
        msgs = (
            sb.table("chat_messages")
            .select("role,content")
            .eq("session_id", session_id)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
            .data or []
        )
        return [{"role": m["role"], "content": m["content"]} for m in reversed(msgs)
                if m["role"] in ("user", "assistant")]
    except Exception:
        return []


async def _save_message(session_id: str, user_id: str, role: str,
                        content: str, model: str = "") -> None:
    try:
        sb = supabase_service.client
        sb.table("chat_messages").insert({
            "session_id": session_id,
            "user_id":    user_id,
            "role":       role,
            "content":    content,
            "model_used": model,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
        sb.table("chat_sessions").update({
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", session_id).execute()
    except Exception as e:
        logger.error("_save_message: %s", e)


async def _ensure_session(user_id: str, title: str = "") -> str:
    try:
        sb  = supabase_service.client
        now = datetime.now(timezone.utc).isoformat()
        res = sb.table("chat_sessions").insert({
            "user_id":    user_id,
            "title":      title or f"Mentor Chat {datetime.now().strftime('%H:%M')}",
            "is_active":  True,
            "created_at": now,
            "updated_at": now,
        }).execute()
        return res.data[0]["id"]
    except Exception as e:
        logger.error("_ensure_session: %s", e)
        return f"temp_{int(datetime.now().timestamp())}"


def _build_system_prompt(profile: Dict, brain_ctx: str, language: str) -> str:
    lang_note = f"\nRespond in language ISO: {language}." if language != "en" else ""
    brain_note = (
        f"\n\n[RISEUP BRAIN CONTEXT — use this to enhance advice]\n{brain_ctx}"
        if brain_ctx else ""
    )
    onboarding = SmartOnboardingManager.build_onboarding_injection(profile)
    return RISEUP_MENTOR_PROMPT + lang_note + brain_note + onboarding


def _sse(event: str, data: Any) -> str:
    return f"event: {event}\ndata: {json.dumps(data) if not isinstance(data, str) else data}\n\n"


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

    # Ensure session
    session_id = req.session_id
    if not session_id:
        session_id = await _ensure_session(user_id, title=req.message[:40])

    # Load history
    history = await _load_history(session_id, user_id)

    # Brain context
    brain_ctx = ""
    if req.include_brain:
        brain_ctx = await _get_brain_context(req.message, user_id, country)

    # Detect delegation
    delegation = _detect_delegation(req.message)
    delegation_payload: Optional[Dict] = None

    if delegation == "apex":
        delegation_payload = {
            "type":       "apex",
            "task":       req.message,
            "session_id": session_id,
            "message":    "Activating APEX to handle this for you. 🤖⚡",
        }
    elif delegation == "workflow":
        delegation_payload = {
            "type":    "workflow",
            "goal":    req.message,
            "message": "Opening the Workflow Engine to build your plan. ⚡",
        }
    elif delegation == "search":
        # Run a quick web search and inject results
        try:
            from services.web_search_service import web_search_service
            results = await web_search_service.search(req.message, num=5)
            brain_ctx += (
                "\n\n[LIVE SEARCH RESULTS]\n" +
                "\n".join(f"- {r.get('title','')}: {r.get('snippet','')}" for r in results[:4])
            )
        except Exception:
            pass

    system = _build_system_prompt(profile, brain_ctx, language)
    messages = history + [{"role": "user", "content": req.message}]

    result = await ai_service.mentor_chat(
        messages=messages,
        user_profile=profile,
        system_prompt=system,
        max_tokens=2048,
    )
    content   = result.get("content", "")
    model_used = result.get("model", "unknown")

    await _save_message(session_id, user_id, "user", req.message)
    await _save_message(session_id, user_id, "assistant", content, model_used)

    # Extract any profile signals and save
    signals = SmartOnboardingManager.extract_profile_signals(req.message, profile)
    if signals:
        try:
            supabase_service.client.table("profiles").update(signals).eq("id", user_id).execute()
        except Exception:
            pass

    return {
        "content":    content,
        "session_id": session_id,
        "model_used": model_used,
        "delegation": delegation_payload,
        "brain_used": bool(brain_ctx),
        "language":   language,
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
        # Send session id immediately so Flutter can display it
        yield _sse("session_id", {"session_id": session_id})

        # Check delegation first
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
            # Brain context
            brain_ctx = ""
            if req.include_brain:
                brain_ctx = await _get_brain_context(req.message, user_id, country)
                if brain_ctx:
                    yield _sse("brain_context", {"found": True})

            # Live search if needed
            if delegation == "search":
                try:
                    from services.web_search_service import web_search_service
                    results = await web_search_service.search(req.message, num=5)
                    brain_ctx += (
                        "\n\n[LIVE SEARCH RESULTS]\n" +
                        "\n".join(
                            f"- {r.get('title','')}: {r.get('snippet','')}"
                            for r in results[:4]
                        )
                    )
                    yield _sse("search_done", {"results": len(results)})
                except Exception:
                    pass

            history = await _load_history(session_id, user_id)
            system  = _build_system_prompt(profile, brain_ctx, language)
            messages = history + [{"role": "user", "content": req.message}]

            result = await ai_service.mentor_chat(
                messages=messages,
                user_profile=profile,
                system_prompt=system,
                max_tokens=2048,
            )
            content   = result.get("content", "")
            model_used = result.get("model", "unknown")

            # Stream word-by-word for live typing effect
            words = content.split()
            for i, word in enumerate(words):
                chunk = word + (" " if i < len(words) - 1 else "")
                yield _sse("token", {"content": chunk})
                await asyncio.sleep(0.008)

        # Save messages
        await _save_message(session_id, user_id, "user", req.message)
        await _save_message(session_id, user_id, "assistant", content)

        # Profile signal extraction
        signals = SmartOnboardingManager.extract_profile_signals(req.message, profile)
        if signals:
            try:
                supabase_service.client.table("profiles").update(signals).eq("id", user_id).execute()
            except Exception:
                pass

        yield _sse("complete", {
            "content":    content,
            "session_id": session_id,
            "delegation": delegation,
            "brain_used": bool(brain_ctx) if delegation not in ("apex", "workflow") else False,
            "language":   language,
        })

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
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
    return {"session_id": session_id, "messages": messages, "count": len(messages)}


@router.get("/sessions")
async def list_mentor_sessions(
    limit: int = 20,
    user:  dict = Depends(get_current_user),
):
    try:
        sb = supabase_service.client
        data = (
            sb.table("chat_sessions")
            .select("id,title,updated_at,created_at")
            .eq("user_id", user["id"])
            .eq("is_active", True)
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
    stage   = profile.get("stage", "survival")
    goal    = profile.get("short_term_goal", "")
    country = profile.get("country", "US")
    income  = profile.get("monthly_income", 0)

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
        "model_used": result.get("model", ""),
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

