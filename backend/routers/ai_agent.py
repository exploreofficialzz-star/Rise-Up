"""
RiseUp AI Agent Router — v3.0 Brain-Aware Global (Production)
═══════════════════════════════════════════════════════════════════
v3.0 Changes:
  - /ai/chat now runs brain search + adaptive profile BEFORE responding
  - Brain context injected into system prompt
  - Post/status signals collected passively
  - Complementary user matching integrated
  - Escalation flow: internal → workflow → agentic
  - All original endpoints preserved
"""

import logging
from datetime import datetime, timezone, timedelta
from typing import Optional
import pytz

from fastapi import APIRouter, Depends, HTTPException, Request
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT

from models.schemas import ChatRequest, ChatResponse, GenerateTasksRequest
from services.ai_service import (
    ai_service,
    RISEUP_SYSTEM_PROMPT,
    ONBOARDING_PROMPT,
    global_db,
)
from services.supabase_service import supabase_service
from services.riseup_brain_service import (
    search_riseup_brain,
    build_brain_context_prompt,
    get_user_brain_context,
    detect_intent,
)
from services.adaptive_brain_service import (
    build_adaptive_context_prompt,
    process_mentor_chat_signal,
    find_complementary_users,
    get_adaptive_profile,
)
from utils.auth import get_current_user

router = APIRouter(prefix="/ai", tags=["AI Agent"])
logger = logging.getLogger(__name__)


# ════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════

def _local_time_str(timezone_name: str) -> str:
    try:
        tz  = pytz.timezone(timezone_name)
        now = datetime.now(tz)
        return now.strftime("%I:%M %p, %A %B %d")
    except Exception:
        return datetime.now(timezone.utc).strftime("%I:%M %p UTC")


def _build_system_prompt(mode: str, profile: dict, language: str = "en") -> str:
    if mode == "onboarding":
        base = ONBOARDING_PROMPT
        if language != "en":
            base += f"\n\nIMPORTANT: Conduct this onboarding in the user's language (ISO: {language}). Translate all questions."
        return base

    base = RISEUP_SYSTEM_PROMPT

    if not profile:
        if language != "en":
            base += f"\n\nIMPORTANT: Respond in the user's language (ISO: {language})."
        return base

    country_code = profile.get("country", "NG")
    country_data = global_db.get_country(country_code)
    tz_name      = country_data.timezone or "UTC"
    local_time   = _local_time_str(tz_name)

    lang_note = ""
    if language != "en":
        lang_note = f"\n\nIMPORTANT: Respond ONLY in the user's language (ISO: {language}). Do not switch to English."

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
🎓 Registration Cost:    {sym}{country_data.business_registration_cost:,.0f}

INSTRUCTION: Always give SPECIFIC advice using {country_data.name} platforms, {sym} amounts, and local 2025/2026 opportunities.
{lang_note}"""

    return base + context


# ════════════════════════════════════════════════════════════════════
# BRAIN-AWARE CHAT ENDPOINT
# ════════════════════════════════════════════════════════════════════

@router.post("/chat", response_model=ChatResponse)
@limiter.limit(AI_LIMIT)
async def chat(
    req:     ChatRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """
    Brain-aware AI mentor chat.

    Enhanced flow v3.0:
    1. Record user message as signal (adaptive learning)
    2. Run brain search (methods + marketplace + profiles)
    3. Load adaptive profile (what user has been doing/saying)
    4. Inject ALL context into system prompt
    5. AI responds with full awareness
    6. Return response + escalation metadata for Flutter
    """
    user_id = user["id"]

    # ── Conversation management ────────────────────────────────────
    if req.conversation_id:
        conv_id = req.conversation_id
    else:
        conv    = await supabase_service.create_conversation(user_id)
        conv_id = conv["id"]

    history  = await supabase_service.get_messages(conv_id, limit=20)
    messages = [
        {"role": m["role"], "content": m["content"]}
        for m in history
        if m["role"] in ("user", "assistant")
    ]
    messages.append({"role": "user", "content": req.message})

    # ── Save user message ─────────────────────────────────────────
    await supabase_service.save_message(conv_id, user_id, "user", req.message)

    # ── Profile + language ────────────────────────────────────────
    profile  = await supabase_service.get_profile(user_id) or {}
    language = profile.get("language", "en")
    country  = profile.get("country", "")

    # ════════════════════════════════════════════════════════════════
    # v3.0: PARALLEL BRAIN ENRICHMENT
    # ════════════════════════════════════════════════════════════════

    # Record signal asynchronously (don't block response)
    import asyncio
    signal_task = asyncio.create_task(
        process_mentor_chat_signal(
            user_id=user_id,
            message=req.message,
            session_id=conv_id,
        )
    )

    # Run brain search + adaptive profile load in parallel
    brain_result, adaptive_context, brain_user_ctx = await asyncio.gather(
        search_riseup_brain(
            query=req.message,
            user_id=user_id,
            user_country=country,
            limit=5,
        ),
        build_adaptive_context_prompt(user_id),
        get_user_brain_context(user_id),
        return_exceptions=True,
    )

    # Handle exceptions gracefully
    if isinstance(brain_result, Exception):
        brain_result = {"found": False, "needs_external": False, "methods": [], "marketplace": [], "service_providers": [], "intent": "explore", "total_found": 0}
    if isinstance(adaptive_context, Exception):
        adaptive_context = ""
    if isinstance(brain_user_ctx, Exception):
        brain_user_ctx = {}

    # ── Build enriched system prompt ──────────────────────────────
    base_system    = _build_system_prompt(req.mode, profile, language)
    brain_block    = build_brain_context_prompt(brain_result) if not isinstance(brain_result, dict) or brain_result.get("total_found", 0) > 0 else ""
    active_methods = ", ".join(brain_user_ctx.get("active_methods", [])) if isinstance(brain_user_ctx, dict) else ""

    # Compose the full system prompt
    system_parts = [base_system]
    if adaptive_context:
        system_parts.append(adaptive_context)
    if brain_block:
        system_parts.append(brain_block)
    if active_methods:
        system_parts.append(f"\nUSER'S ACTIVE METHODS: {active_methods}")

    # ── Escalation instructions ───────────────────────────────────
    brain_dict = brain_result if isinstance(brain_result, dict) else {}
    if brain_dict.get("needs_external"):
        system_parts.append("""
ESCALATION INSTRUCTION:
The brain search found limited results internally.
Tell the user you searched RiseUp and found limited results.
Offer to search the internet using this EXACT phrasing:
"Want me to search the internet for more options? I can use the Workflow Engine to find [buyers/sellers/service providers] globally."

If user says yes: tell them "Opening the Workflow Engine for you now."
If user says "handle everything" or "do it all" or "take care of it":
  Tell them "Activating your Agentic assistant to handle this end-to-end."
""")

    full_system = "\n\n".join(filter(bool, system_parts))

    # ── Call AI ───────────────────────────────────────────────────
    result     = await ai_service.chat(messages, system=full_system, max_tokens=1_400)
    ai_content = result["content"]
    ai_model   = result["model"]

    # ── Save AI response ──────────────────────────────────────────
    ai_msg = await supabase_service.save_message(
        conv_id, user_id, "assistant", ai_content, ai_model=ai_model
    )

    # ── Complementary user suggestions ───────────────────────────
    complementary = []
    adaptive_prof = await get_adaptive_profile(user_id)
    if isinstance(adaptive_prof, dict) and (
        adaptive_prof.get("has_active_sell_intent") or
        adaptive_prof.get("has_active_buy_intent") or
        adaptive_prof.get("has_active_service_need")
    ):
        complementary = await find_complementary_users(user_id, limit=3)

    # ── Onboarding handling ───────────────────────────────────────
    onboarding_complete = False
    extracted_profile   = None
    suggested_tasks     = None

    if req.mode == "onboarding" and "PROFILE_COMPLETE" in ai_content:
        try:
            all_messages = messages + [{"role": "assistant", "content": ai_content}]
            extracted_profile = await ai_service.analyze_onboarding(all_messages)

            if extracted_profile:
                await supabase_service.update_profile(user_id, {
                    **extracted_profile,
                    "onboarding_completed": True,
                })
                onboarding_complete = True

                tasks_data = await ai_service.generate_income_tasks(
                    extracted_profile, count=5
                )
                if tasks_data:
                    for t in tasks_data:
                        t["estimated_earnings"] = t.pop("estimated_earnings_max", 0)
                    saved_tasks     = await supabase_service.create_tasks_bulk(user_id, tasks_data)
                    suggested_tasks = saved_tasks[:5]

            country_data = global_db.get_country(
                (extracted_profile or {}).get("country", "DEFAULT"))
            ai_content = (
                "🎉 Amazing! I've got everything I need to build your "
                f"personalised wealth roadmap in {country_data.name}.\n\n"
                "Your profile is complete and your first income tasks are ready. "
                "Let's start your journey to financial freedom! 💪"
            )
        except Exception as e:
            logger.error(f"Onboarding processing error: {e}")
            ai_content = "✅ Profile complete! Preparing your personalised roadmap now..."

    # Cancel signal task if still running (fire and forget)
    try:
        if not signal_task.done():
            pass  # Let it complete in background
    except Exception:
        pass

    return ChatResponse(
        content             = ai_content,
        conversation_id     = conv_id,
        message_id          = ai_msg.get("id", ""),
        ai_model            = ai_model,
        onboarding_complete = onboarding_complete,
        extracted_profile   = extracted_profile,
        suggested_tasks     = suggested_tasks,
        # v3.0 extras — Flutter reads these to decide escalation UI
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


# ════════════════════════════════════════════════════════════════════
# TASK GENERATION
# ════════════════════════════════════════════════════════════════════

@router.post("/generate-tasks")
@limiter.limit(AI_LIMIT)
async def generate_tasks(
    req:     GenerateTasksRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, detail={"error": "Profile not found", "action": "Complete onboarding first"})

    tasks_data = await ai_service.generate_income_tasks(profile, count=req.count or 5)
    if not tasks_data:
        raise HTTPException(500, detail="Failed to generate tasks")

    for t in tasks_data:
        t["estimated_earnings"] = t.pop("estimated_earnings_max", t.get("estimated_earnings", 0))
        t.pop("estimated_earnings_min", None)

    saved = await supabase_service.create_tasks_bulk(user_id, tasks_data)

    country_code = profile.get("country", "DEFAULT")
    country_data = global_db.get_country(country_code)

    return {
        "tasks":           saved,
        "count":           len(saved),
        "country":         country_data.name,
        "currency":        country_data.currency,
        "currency_symbol": country_data.currency_symbol,
    }


# ════════════════════════════════════════════════════════════════════
# ROADMAP GENERATION
# ════════════════════════════════════════════════════════════════════

@router.post("/generate-roadmap")
@limiter.limit(AI_LIMIT)
async def generate_roadmap(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, detail={"error": "Profile not found"})

    roadmap_data = await ai_service.generate_roadmap(profile)
    if not roadmap_data:
        raise HTTPException(500, detail="Failed to generate roadmap")

    db_roadmap = {
        "current_stage":      roadmap_data.get("current_stage", "immediate_income"),
        "stage_1_milestones": roadmap_data.get("immediate_90_day_plan", {}).get("key_actions", []),
        "stage_2_milestones": roadmap_data.get("income_stacking_strategy", {}).get("immediate_income", []),
        "stage_3_milestones": roadmap_data.get("financial_milestones", []),
        "ai_notes":           roadmap_data.get("user_summary", ""),
        "next_review_at":     (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
    }
    saved = await supabase_service.upsert_roadmap(user_id, db_roadmap)

    country_code = profile.get("country", "DEFAULT")
    country_data = global_db.get_country(country_code)

    return {
        "roadmap":         roadmap_data,
        "saved":           saved,
        "country":         country_data.name,
        "currency":        country_data.currency,
        "currency_symbol": country_data.currency_symbol,
        "region":          country_data.region,
    }


# ════════════════════════════════════════════════════════════════════
# POST SIGNAL ENDPOINT (called by posts router when user creates post)
# ════════════════════════════════════════════════════════════════════

@router.post("/signal/post")
async def record_post_signal(
    data: dict,
    user: dict = Depends(get_current_user),
):
    """
    Record a post creation signal into the brain.
    Called by the posts router when user creates a new post.
    Returns economic signals + suggestions for the Flutter UI.
    """
    from services.adaptive_brain_service import process_post_signal
    result = await process_post_signal(
        user_id   = user["id"],
        post_id   = data.get("post_id", ""),
        content   = data.get("content", ""),
        tag       = data.get("tag"),
    )
    return result


@router.post("/signal/interaction")
async def record_interaction_signal(
    data: dict,
    user: dict = Depends(get_current_user),
):
    """
    Record a like/save/share interaction signal.
    Called when user interacts with a post.
    """
    from services.adaptive_brain_service import process_interaction_signal, SignalType
    type_map = {
        "like":  SignalType.POST_LIKED,
        "save":  SignalType.POST_SAVED,
        "share": SignalType.POST_SHARED,
    }
    signal_type = type_map.get(data.get("action", ""), SignalType.POST_LIKED)
    await process_interaction_signal(
        user_id      = user["id"],
        signal_type  = signal_type,
        post_content = data.get("post_content", ""),
        post_id      = data.get("post_id", ""),
    )
    return {"recorded": True}


@router.get("/adaptive-profile")
async def get_my_adaptive_profile(user: dict = Depends(get_current_user)):
    """Get the user's adaptive economic profile as learned by the brain."""
    profile = await get_adaptive_profile(user["id"])
    return {"profile": profile}


@router.get("/complementary-users")
async def get_complementary_users(
    limit: int = 5,
    user:  dict = Depends(get_current_user),
):
    """
    Find RiseUp users whose economic needs complement this user.
    E.g. if user wants to sell a laptop, returns users looking to buy laptops.
    """
    matches = await find_complementary_users(user["id"], limit=limit)
    return {"matches": matches, "count": len(matches)}


# ════════════════════════════════════════════════════════════════════
# UTILITY ENDPOINTS (preserved from v2.1)
# ════════════════════════════════════════════════════════════════════

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
    conversation_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
):
    messages = await supabase_service.get_messages(conversation_id)
    return {"messages": messages, "total": len(messages), "conversation_id": conversation_id}


@router.get("/country-info")
async def get_country_info(
    country_code: str = "NG",
    user: dict = Depends(get_current_user),
):
    return ai_service.get_country_info(country_code)


@router.get("/trending")
@limiter.limit(GENERAL_LIMIT)
async def get_trending_opportunities(
    request:      Request,
    country_code: Optional[str] = None,
    user:         dict = Depends(get_current_user),
):
    if not country_code:
        profile      = await supabase_service.get_profile(user["id"]) or {}
        country_code = profile.get("country", "NG")
    return await ai_service.get_trending_opportunities(country_code)
