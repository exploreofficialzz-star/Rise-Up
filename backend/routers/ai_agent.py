"""
RiseUp AI Agent Router — v3.2 Production (Critical Fix)

v3.2 Root-cause fixes:
  - riseup_brain_service and adaptive_brain_service imports are now wrapped
    in try/except with async stubs. A missing or broken brain module no longer
    crashes the ENTIRE router — /ai/chat works even if brain is unavailable.
  - Rate limiter wrapped with no-op fallback.
  - supabase_service calls hardened; save_message failure is non-fatal.
  - /ai/chat endpoint catches every exception individually so one bad service
    never silences the AI response.
  - Added PATCH/DELETE endpoints for AI conversation messages (edit/delete).
"""

import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional

logger = logging.getLogger(__name__)

# ── Rate limiter (optional — no-op stub if middleware not deployed) ──────────
try:
    from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
except Exception as _rl_err:
    logger.warning(f"Rate limiter unavailable (running without): {_rl_err}")

    class _NoOpLimiter:
        def limit(self, *args, **kwargs):
            return lambda func: func

    limiter       = _NoOpLimiter()
    AI_LIMIT      = "1000/hour"
    GENERAL_LIMIT = "2000/hour"

# ── Brain service (optional) ─────────────────────────────────────────────────
try:
    from services.riseup_brain_service import (
        search_riseup_brain,
        build_brain_context_prompt,
        get_user_brain_context,
        detect_intent,
    )
    _BRAIN_AVAILABLE = True
    logger.info("Brain service loaded OK")
except Exception as _brain_err:
    logger.warning(
        f"Brain service unavailable — AI will respond without brain context: {_brain_err}"
    )
    _BRAIN_AVAILABLE = False

    async def search_riseup_brain(*a, **kw):
        return {
            "found": False, "needs_external": False,
            "methods": [], "marketplace": [],
            "service_providers": [], "intent": "explore", "total_found": 0,
        }

    def build_brain_context_prompt(*a, **kw):
        return ""

    async def get_user_brain_context(*a, **kw):
        return {}

    def detect_intent(*a, **kw):
        return "explore"


# ── Adaptive brain service (optional) ────────────────────────────────────────
try:
    from services.adaptive_brain_service import (
        build_adaptive_context_prompt,
        process_mentor_chat_signal,
        find_complementary_users,
        get_adaptive_profile,
    )
    _ADAPTIVE_AVAILABLE = True
    logger.info("Adaptive brain service loaded OK")
except Exception as _adaptive_err:
    logger.warning(f"Adaptive brain unavailable: {_adaptive_err}")
    _ADAPTIVE_AVAILABLE = False

    async def build_adaptive_context_prompt(*a, **kw):
        return ""

    async def process_mentor_chat_signal(*a, **kw):
        pass

    async def find_complementary_users(*a, **kw):
        return []

    async def get_adaptive_profile(*a, **kw):
        return {}


# ── Core imports (always required) ───────────────────────────────────────────
try:
    import pytz
    _PYTZ_OK = True
except ImportError:
    _PYTZ_OK = False

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from models.schemas import ChatRequest, ChatResponse, GenerateTasksRequest
from services.ai_service import (
    ai_service,
    RISEUP_SYSTEM_PROMPT,
    ONBOARDING_PROMPT,
    global_db,
)
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/ai", tags=["AI Agent"])


# ── Pydantic helpers ──────────────────────────────────────────────────────────

class MessageEditRequest(BaseModel):
    content: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def _local_time_str(timezone_name: str) -> str:
    try:
        if _PYTZ_OK:
            tz  = pytz.timezone(timezone_name)
            now = datetime.now(tz)
            return now.strftime("%I:%M %p, %A %B %d")
    except Exception:
        pass
    return datetime.now(timezone.utc).strftime("%I:%M %p UTC")


def _build_system_prompt(mode: str, profile: dict, language: str = "en") -> str:
    if mode == "onboarding":
        base = ONBOARDING_PROMPT
        if language != "en":
            base += f"\n\nIMPORTANT: Conduct this onboarding in the user's language (ISO: {language})."
        return base

    base = RISEUP_SYSTEM_PROMPT

    if not profile:
        if language != "en":
            base += f"\n\nIMPORTANT: Respond in the user's language (ISO: {language})."
        return base

    country_code = profile.get("country", "NG")
    country_data = global_db.get_country(country_code)
    tz_name      = getattr(country_data, "timezone", None) or "UTC"
    local_time   = _local_time_str(tz_name)

    lang_note = ""
    if language != "en":
        lang_note = f"\n\nIMPORTANT: Respond ONLY in the user's language (ISO: {language})."

    sym    = country_data.currency_symbol
    income = profile.get("monthly_income", 0)
    earned = profile.get("total_earned", 0)

    context = f"""

CURRENT USER CONTEXT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👤 Name:           {profile.get('full_name', 'User')}
🌍 Country:        {country_data.name} ({country_data.region})
🕐 Local Time:     {local_time}
💰 Currency:       {country_data.currency} ({sym})
📊 Stage:          {profile.get('stage', 'survival').upper()}
💵 Monthly Income: {sym}{income:,.0f}
🏆 Earned via App: {sym}{earned:,.0f}
🛠️ Skills:         {', '.join(profile.get('current_skills', []) or ['none listed'])}
🎯 Goals:          {profile.get('short_term_goal', 'not set')}
⭐ Subscription:   {profile.get('subscription_tier', 'free').upper()}

COUNTRY INTELLIGENCE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 Top Local Platforms:  {', '.join([p['name'] for p in country_data.popular_platforms[:4]])}
📈 Trending Skills:      {', '.join(country_data.trending_skills[:4])}
🏠 Avg Country Income:   {sym}{country_data.avg_monthly_income:,.0f}/month
💼 Middle Class Target:  {sym}{country_data.middle_class_monthly:,.0f}/month

INSTRUCTION: Always give SPECIFIC advice using {country_data.name} platforms, {sym} amounts.
{lang_note}"""

    return base + context


# ═══════════════════════════════════════════════════════════════════
# BRAIN-AWARE CHAT — v3.2 (hardened)
# ═══════════════════════════════════════════════════════════════════

@router.post("/chat", response_model=ChatResponse)
@limiter.limit(AI_LIMIT)
async def chat(
    req:     ChatRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """
    Brain-aware AI mentor chat.
    v3.2: Every optional-service call is individually try/except guarded.
    The AI response is ALWAYS returned even if brain/adaptive/supabase fails.
    """
    user_id = user["id"]

    # ── Conversation management ──────────────────────────────────────
    conv_id = req.conversation_id
    if not conv_id:
        try:
            conv    = await supabase_service.create_conversation(user_id)
            conv_id = conv.get("id", "")
        except Exception as e:
            logger.warning(f"create_conversation failed: {e}")
            import uuid
            conv_id = str(uuid.uuid4())

    # ── Load history ─────────────────────────────────────────────────
    history  = []
    try:
        history = await supabase_service.get_messages(conv_id, limit=20)
    except Exception as e:
        logger.warning(f"get_messages failed: {e}")

    messages = [
        {"role": m["role"], "content": m["content"]}
        for m in history
        if m.get("role") in ("user", "assistant")
    ]
    messages.append({"role": "user", "content": req.message})

    # ── Save user message ────────────────────────────────────────────
    try:
        await supabase_service.save_message(conv_id, user_id, "user", req.message)
    except Exception as e:
        logger.warning(f"save user message failed (non-fatal): {e}")

    # ── Profile + language ────────────────────────────────────────────
    profile  = {}
    try:
        profile = await supabase_service.get_profile(user_id) or {}
    except Exception as e:
        logger.warning(f"get_profile failed: {e}")

    language = profile.get("language", "en")
    country  = profile.get("country", "")

    # ── Record adaptive signal (fire-and-forget) ─────────────────────
    signal_task = None
    try:
        signal_task = asyncio.create_task(
            process_mentor_chat_signal(
                user_id=user_id, message=req.message, session_id=conv_id,
            )
        )
    except Exception:
        pass

    # ── Parallel brain enrichment (all failures are silenced) ────────
    brain_result      = {"found": False, "needs_external": False, "methods": [], "marketplace": [], "service_providers": [], "intent": "explore", "total_found": 0}
    adaptive_context  = ""
    brain_user_ctx    = {}

    try:
        results = await asyncio.gather(
            search_riseup_brain(query=req.message, user_id=user_id, user_country=country, limit=5),
            build_adaptive_context_prompt(user_id),
            get_user_brain_context(user_id),
            return_exceptions=True,
        )
        if not isinstance(results[0], Exception): brain_result     = results[0]
        if not isinstance(results[1], Exception): adaptive_context = results[1] or ""
        if not isinstance(results[2], Exception): brain_user_ctx   = results[2] or {}
    except Exception as e:
        logger.warning(f"Brain enrichment gather failed: {e}")

    # ── Build system prompt ───────────────────────────────────────────
    base_system = _build_system_prompt(req.mode, profile, language)
    brain_block = ""
    try:
        if isinstance(brain_result, dict) and brain_result.get("total_found", 0) > 0:
            brain_block = build_brain_context_prompt(brain_result)
    except Exception:
        pass

    active_methods = ""
    if isinstance(brain_user_ctx, dict):
        active_methods = ", ".join(brain_user_ctx.get("active_methods", []))

    system_parts = [base_system]
    if adaptive_context:
        system_parts.append(adaptive_context)
    if brain_block:
        system_parts.append(brain_block)
    if active_methods:
        system_parts.append(f"\nUSER'S ACTIVE METHODS: {active_methods}")

    brain_dict = brain_result if isinstance(brain_result, dict) else {}
    if brain_dict.get("needs_external"):
        system_parts.append(
            "\nESCALATION: Brain search returned limited results. "
            "Offer the Workflow Engine to search the internet for more options."
        )

    full_system = "\n\n".join(filter(bool, system_parts))

    # ── Call AI ───────────────────────────────────────────────────────
    result     = await ai_service.chat(messages, system=full_system, max_tokens=1_400)
    ai_content = result["content"]
    ai_model   = result["model"]

    # ── Save AI response ──────────────────────────────────────────────
    ai_msg = {}
    try:
        ai_msg = await supabase_service.save_message(
            conv_id, user_id, "assistant", ai_content, ai_model=ai_model
        )
    except Exception as e:
        logger.warning(f"save AI message failed (non-fatal): {e}")

    # ── Complementary users ───────────────────────────────────────────
    complementary = []
    try:
        adaptive_prof = await get_adaptive_profile(user_id)
        if isinstance(adaptive_prof, dict) and any(
            adaptive_prof.get(k)
            for k in ("has_active_sell_intent", "has_active_buy_intent", "has_active_service_need")
        ):
            complementary = await find_complementary_users(user_id, limit=3)
    except Exception:
        pass

    # ── Onboarding completion handling ────────────────────────────────
    onboarding_complete = False
    extracted_profile   = None
    suggested_tasks     = None

    if req.mode == "onboarding" and "PROFILE_COMPLETE" in ai_content:
        try:
            all_messages = messages + [{"role": "assistant", "content": ai_content}]
            extracted_profile = await ai_service.analyze_onboarding(all_messages)
            if extracted_profile:
                await supabase_service.update_profile(user_id, {
                    **extracted_profile, "onboarding_completed": True,
                })
                onboarding_complete = True
                tasks_data = await ai_service.generate_income_tasks(extracted_profile, count=5)
                if tasks_data:
                    for t in tasks_data:
                        t["estimated_earnings"] = t.pop("estimated_earnings_max", 0)
                    saved_tasks     = await supabase_service.create_tasks_bulk(user_id, tasks_data)
                    suggested_tasks = saved_tasks[:5]
            country_data = global_db.get_country((extracted_profile or {}).get("country", "DEFAULT"))
            ai_content   = (
                f"🎉 I've built your personalised wealth roadmap for {country_data.name}. "
                "Your first income tasks are ready. Let's start! 💪"
            )
        except Exception as e:
            logger.error(f"Onboarding processing error: {e}")

    # Cancel signal task (fire-and-forget)
    try:
        if signal_task and not signal_task.done():
            pass  # runs in background
    except Exception:
        pass

    return ChatResponse(
        content              = ai_content,
        conversation_id      = conv_id,
        message_id           = ai_msg.get("id", ""),
        ai_model             = ai_model,
        onboarding_complete  = onboarding_complete,
        extracted_profile    = extracted_profile,
        suggested_tasks      = suggested_tasks,
        brain_intent             = brain_dict.get("intent"),
        brain_internal_found     = brain_dict.get("found", False),
        brain_methods            = brain_dict.get("methods", [])[:3],
        brain_marketplace        = brain_dict.get("marketplace", [])[:3],
        brain_service_providers  = brain_dict.get("service_providers", [])[:3],
        brain_needs_external     = brain_dict.get("needs_external", False),
        brain_escalation_reason  = brain_dict.get("escalation_reason"),
        brain_suggested_task_type= brain_dict.get("suggested_task_type"),
        complementary_users      = complementary[:3],
    )


# ═══════════════════════════════════════════════════════════════════
# EDIT / DELETE messages in AI conversations
# ═══════════════════════════════════════════════════════════════════

@router.patch("/conversations/{conversation_id}/messages/{message_id}")
async def edit_ai_message(
    conversation_id: str,
    message_id: str,
    req: MessageEditRequest,
    user: dict = Depends(get_current_user),
):
    """Edit a user message in an AI conversation."""
    try:
        db = supabase_service.db
        msg = (
            db.table("messages")
            .select("id, sender_id, user_id, role, sender_type, conversation_id")
            .eq("id", message_id)
            .execute()
            .data
        )
        if not msg:
            raise HTTPException(404, "Message not found")
        m = msg[0]
        if m.get("conversation_id") != conversation_id:
            raise HTTPException(400, "Message not in this conversation")
        if m.get("role") == "assistant" or m.get("sender_type") in ("ai", "system"):
            raise HTTPException(403, "Cannot edit AI messages")
        # Check ownership via sender_id or user_id
        owner = m.get("sender_id") or m.get("user_id")
        if owner != user["id"]:
            raise HTTPException(403, "Can only edit your own messages")

        update = {
            "content":    req.content.strip(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            db.table("messages").update({**update, "is_edited": True}).eq("id", message_id).execute()
        except Exception:
            db.table("messages").update(update).eq("id", message_id).execute()

        updated = db.table("messages").select("*").eq("id", message_id).execute().data
        return {"message": updated[0] if updated else {}, "edited": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"edit_ai_message {message_id}: {e}")
        raise HTTPException(500, str(e))


@router.delete("/conversations/{conversation_id}/messages/{message_id}")
async def delete_ai_message(
    conversation_id: str,
    message_id: str,
    user: dict = Depends(get_current_user),
):
    """Soft-delete a user message in an AI conversation."""
    try:
        db = supabase_service.db
        msg = (
            db.table("messages")
            .select("id, sender_id, user_id, role, sender_type, conversation_id")
            .eq("id", message_id)
            .execute()
            .data
        )
        if not msg:
            raise HTTPException(404, "Message not found")
        m = msg[0]
        if m.get("conversation_id") != conversation_id:
            raise HTTPException(400, "Message not in this conversation")
        if m.get("role") == "assistant" or m.get("sender_type") in ("ai", "system"):
            raise HTTPException(403, "Cannot delete AI messages")
        owner = m.get("sender_id") or m.get("user_id")
        if owner != user["id"]:
            raise HTTPException(403, "Can only delete your own messages")

        update = {
            "content":    "This message was deleted.",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            db.table("messages").update({**update, "is_deleted": True}).eq("id", message_id).execute()
        except Exception:
            db.table("messages").update(update).eq("id", message_id).execute()

        return {"deleted": True, "message_id": message_id}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"delete_ai_message {message_id}: {e}")
        raise HTTPException(500, str(e))


# ═══════════════════════════════════════════════════════════════════
# TASK GENERATION
# ═══════════════════════════════════════════════════════════════════

@router.post("/generate-tasks")
@limiter.limit(AI_LIMIT)
async def generate_tasks(
    req: GenerateTasksRequest, request: Request, user: dict = Depends(get_current_user),
):
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, detail={"error": "Profile not found"})
    tasks_data = await ai_service.generate_income_tasks(profile, count=req.count or 5)
    if not tasks_data:
        raise HTTPException(500, "Failed to generate tasks")
    for t in tasks_data:
        t["estimated_earnings"] = t.pop("estimated_earnings_max", t.get("estimated_earnings", 0))
        t.pop("estimated_earnings_min", None)
    saved = await supabase_service.create_tasks_bulk(user_id, tasks_data)
    country_data = global_db.get_country(profile.get("country", "DEFAULT"))
    return {
        "tasks": saved, "count": len(saved),
        "country": country_data.name, "currency": country_data.currency,
        "currency_symbol": country_data.currency_symbol,
    }


# ═══════════════════════════════════════════════════════════════════
# ROADMAP
# ═══════════════════════════════════════════════════════════════════

@router.post("/generate-roadmap")
@limiter.limit(AI_LIMIT)
async def generate_roadmap(request: Request, user: dict = Depends(get_current_user)):
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, detail={"error": "Profile not found"})
    roadmap_data = await ai_service.generate_roadmap(profile)
    if not roadmap_data:
        raise HTTPException(500, "Failed to generate roadmap")
    db_roadmap = {
        "current_stage":      roadmap_data.get("current_stage", "immediate_income"),
        "stage_1_milestones": roadmap_data.get("immediate_90_day_plan", {}).get("key_actions", []),
        "stage_2_milestones": roadmap_data.get("income_stacking_strategy", {}).get("immediate_income", []),
        "stage_3_milestones": roadmap_data.get("financial_milestones", []),
        "ai_notes":           roadmap_data.get("user_summary", ""),
        "next_review_at":     (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
    }
    saved        = await supabase_service.upsert_roadmap(user_id, db_roadmap)
    country_data = global_db.get_country(profile.get("country", "DEFAULT"))
    return {
        "roadmap": roadmap_data, "saved": saved,
        "country": country_data.name, "currency": country_data.currency,
        "currency_symbol": country_data.currency_symbol, "region": country_data.region,
    }


# ═══════════════════════════════════════════════════════════════════
# SIGNAL ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.post("/signal/post")
async def record_post_signal(data: dict, user: dict = Depends(get_current_user)):
    try:
        from services.adaptive_brain_service import process_post_signal
        result = await process_post_signal(
            user_id=user["id"], post_id=data.get("post_id", ""),
            content=data.get("content", ""), tag=data.get("tag"),
        )
        return result
    except Exception as e:
        return {"recorded": False, "error": str(e)}


@router.post("/signal/interaction")
async def record_interaction_signal(data: dict, user: dict = Depends(get_current_user)):
    try:
        from services.adaptive_brain_service import process_interaction_signal, SignalType
        type_map = {
            "like":  SignalType.POST_LIKED,
            "save":  SignalType.POST_SAVED,
            "share": SignalType.POST_SHARED,
        }
        signal_type = type_map.get(data.get("action", ""), SignalType.POST_LIKED)
        await process_interaction_signal(
            user_id=user["id"], signal_type=signal_type,
            post_content=data.get("post_content", ""), post_id=data.get("post_id", ""),
        )
    except Exception:
        pass
    return {"recorded": True}


@router.get("/adaptive-profile")
async def get_my_adaptive_profile(user: dict = Depends(get_current_user)):
    profile = await get_adaptive_profile(user["id"])
    return {"profile": profile}


@router.get("/complementary-users")
async def get_complementary_users(limit: int = 5, user: dict = Depends(get_current_user)):
    matches = await find_complementary_users(user["id"], limit=limit)
    return {"matches": matches, "count": len(matches)}


# ═══════════════════════════════════════════════════════════════════
# UTILITY ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.get("/models")
async def get_available_models(user: dict = Depends(get_current_user)):
    return {"models": ai_service.get_available_models()}


@router.get("/conversations")
@limiter.limit(GENERAL_LIMIT)
async def get_conversations(request: Request, user: dict = Depends(get_current_user)):
    convs = await supabase_service.get_conversations(user["id"])
    return {"conversations": convs, "total": len(convs)}


@router.get("/conversations/{conversation_id}/messages")
@limiter.limit(GENERAL_LIMIT)
async def get_messages(
    conversation_id: str, request: Request, user: dict = Depends(get_current_user),
):
    messages = await supabase_service.get_messages(conversation_id)
    return {"messages": messages, "total": len(messages), "conversation_id": conversation_id}


@router.get("/country-info")
async def get_country_info(country_code: str = "NG", user: dict = Depends(get_current_user)):
    return ai_service.get_country_info(country_code)


@router.get("/trending")
@limiter.limit(GENERAL_LIMIT)
async def get_trending_opportunities(
    request: Request, country_code: Optional[str] = None, user: dict = Depends(get_current_user),
):
    if not country_code:
        profile      = await supabase_service.get_profile(user["id"]) or {}
        country_code = profile.get("country", "NG")
    return await ai_service.get_trending_opportunities(country_code)
