"""
RiseUp AI Agent Router — v2.1 Global (Production)
═══════════════════════════════════════════════════════════════════════════
Main conversational intelligence router for the RiseUp app.

v2.1 Bug Fixes:
- Import RISEUP_SYSTEM_PROMPT / ONBOARDING_PROMPT  ← now exported from ai_service
- ai_service.chat()               ← wrapper method now exists on engine
- ai_service.analyze_onboarding() ← method now exists on engine
- ai_service.generate_roadmap()   ← alias method now exists on engine

v2.1 Global Enhancements:
- Language-aware system prompts (responds in user's language)
- Timezone-aware context (shows local time in prompts)
- Multi-currency income formatting
- Region-specific platform recommendations
- Localized onboarding flow
- Better error messages for all locales
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
    RISEUP_SYSTEM_PROMPT,  # ← fixed: was RISEUP_MENTOR_PROMPT in old ai_service
    ONBOARDING_PROMPT,     # ← fixed: was ONBOARDING_ARCHITECT_PROMPT in old ai_service
    global_db,
)
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/ai", tags=["AI Agent"])
logger = logging.getLogger(__name__)


# ════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════

def _local_time_str(timezone_name: str) -> str:
    """Return current local time string for the user's timezone."""
    try:
        tz  = pytz.timezone(timezone_name)
        now = datetime.now(tz)
        return now.strftime("%I:%M %p, %A %B %d")
    except Exception:
        return datetime.now(timezone.utc).strftime("%I:%M %p UTC")


def _build_system_prompt(mode: str, profile: dict, language: str = "en") -> str:
    """
    Build a fully localized, context-aware system prompt.

    Global enhancements:
    - Injects user's local time so the AI can give time-aware advice
    - Injects country database context (platforms, currency, opportunities)
    - Language instruction so the AI replies in the user's language
    """
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

    # ── Country context from global database ──────────────────────
    country_code = profile.get("country", "NG")
    country_data = global_db.get_country(country_code)
    tz_name      = country_data.timezone or "UTC"
    local_time   = _local_time_str(tz_name)

    # ── Language instruction ──────────────────────────────────────
    lang_note = ""
    if language != "en":
        lang_note = f"\n\nIMPORTANT: Respond ONLY in the user's language (ISO: {language}). Do not switch to English."

    # ── Format currency amounts with local symbol ─────────────────
    sym        = country_data.currency_symbol
    income     = profile.get("monthly_income", 0)
    earned     = profile.get("total_earned", 0)

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
# CHAT ENDPOINT
# ════════════════════════════════════════════════════════════════════

@router.post("/chat", response_model=ChatResponse)
@limiter.limit(AI_LIMIT)
async def chat(
    req:     ChatRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """
    Main AI chat endpoint — handles all conversation modes.

    Modes:
    - onboarding : guided profile-building flow
    - mentor     : general wealth coaching
    - tasks      : income-task generation
    - roadmap    : 90-day plan building
    """
    user_id = user["id"]

    # ── Get or create conversation ─────────────────────────────────
    if req.conversation_id:
        conv_id = req.conversation_id
    else:
        conv    = await supabase_service.create_conversation(user_id)
        conv_id = conv["id"]

    # ── Load conversation history ──────────────────────────────────
    history  = await supabase_service.get_messages(conv_id, limit=20)
    messages = [
        {"role": m["role"], "content": m["content"]}
        for m in history
        if m["role"] in ("user", "assistant")
    ]
    messages.append({"role": "user", "content": req.message})

    # ── Save user message ──────────────────────────────────────────
    await supabase_service.save_message(conv_id, user_id, "user", req.message)

    # ── Load user profile for localization ────────────────────────
    profile  = await supabase_service.get_profile(user_id) or {}
    language = profile.get("language", "en")

    # ── Build localized system prompt ─────────────────────────────
    system = _build_system_prompt(req.mode, profile, language)

    # ── Call AI engine (fixed: uses .chat() wrapper) ──────────────
    result = await ai_service.chat(
        messages,
        system=system,
        max_tokens=1_200,
        preferred_model=getattr(req, "preferred_model", None),
    )

    ai_content = result["content"]
    ai_model   = result["model"]

    # ── Save AI response ───────────────────────────────────────────
    ai_msg = await supabase_service.save_message(
        conv_id, user_id, "assistant", ai_content, ai_model=ai_model
    )

    # ── Onboarding completion handling ────────────────────────────
    onboarding_complete = False
    extracted_profile   = None
    suggested_tasks     = None

    if req.mode == "onboarding" and "PROFILE_COMPLETE" in ai_content:
        try:
            all_messages = messages + [{"role": "assistant", "content": ai_content}]

            # Fixed: .analyze_onboarding() now exists on the engine
            extracted_profile = await ai_service.analyze_onboarding(all_messages)

            if extracted_profile:
                await supabase_service.update_profile(user_id, {
                    **extracted_profile,
                    "onboarding_completed": True,
                })
                onboarding_complete = True

                # Auto-generate initial income tasks in user's local context
                tasks_data = await ai_service.generate_income_tasks(
                    extracted_profile, count=5
                )
                if tasks_data:
                    for t in tasks_data:
                        # Normalize earnings field name for the DB schema
                        t["estimated_earnings"] = t.pop("estimated_earnings_max", 0)
                    saved_tasks     = await supabase_service.create_tasks_bulk(user_id, tasks_data)
                    suggested_tasks = saved_tasks[:5]

            # Replace raw AI JSON with friendly completion message
            country_name = (extracted_profile or {}).get("country", "")
            country_data = global_db.get_country(country_name) if country_name else None
            currency_sym = country_data.currency_symbol if country_data else ""

            ai_content = (
                "🎉 Amazing! I've got everything I need to build your "
                "personalised wealth roadmap.\n\n"
                "Your profile is complete and your first income tasks are "
                f"ready{' in ' + country_data.name if country_data else ''}. "
                "Let's start your journey to financial freedom! 💪"
            )

        except Exception as e:
            logger.error(f"Onboarding processing error: {e}")
            ai_content = "✅ Profile complete! Preparing your personalised roadmap now..."

    return ChatResponse(
        content             = ai_content,
        conversation_id     = conv_id,
        message_id          = ai_msg.get("id", ""),
        ai_model            = ai_model,
        onboarding_complete = onboarding_complete,
        extracted_profile   = extracted_profile,
        suggested_tasks     = suggested_tasks,
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
    """
    Generate fresh AI-powered income tasks localized to user's country.
    Returns tasks with earnings in user's local currency.
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(
            400,
            detail={
                "error":   "Profile not found",
                "action":  "Complete onboarding first",
                "endpoint": "/ai/chat with mode=onboarding",
            },
        )

    tasks_data = await ai_service.generate_income_tasks(
        profile,
        count=req.count or 5,
    )
    if not tasks_data:
        raise HTTPException(500, detail="Failed to generate tasks — all AI models unavailable")

    # Normalize field names for DB schema
    for t in tasks_data:
        t["estimated_earnings"] = t.pop("estimated_earnings_max", t.get("estimated_earnings", 0))
        t.pop("estimated_earnings_min", None)

    saved = await supabase_service.create_tasks_bulk(user_id, tasks_data)

    # Include country context in response so Flutter can show local currency
    country_code = profile.get("country", "DEFAULT")
    country_data = global_db.get_country(country_code)

    return {
        "tasks":    saved,
        "count":    len(saved),
        "country":  country_data.name,
        "currency": country_data.currency,
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
    """
    Generate a personalized 3-stage wealth roadmap.
    Localized to user's country, currency, and language.
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(
            400,
            detail={
                "error":  "Profile not found",
                "action": "Complete onboarding first",
            },
        )

    # Fixed: .generate_roadmap() alias now exists on the engine
    roadmap_data = await ai_service.generate_roadmap(profile)
    if not roadmap_data:
        raise HTTPException(500, detail="Failed to generate roadmap")

    # Save to database
    db_roadmap = {
        "current_stage":     roadmap_data.get("current_stage", "immediate_income"),
        "stage_1_milestones":roadmap_data.get("immediate_90_day_plan", {}).get("key_actions", []),
        "stage_2_milestones":roadmap_data.get("income_stacking_strategy", {}).get("immediate_income", []),
        "stage_3_milestones":roadmap_data.get("financial_milestones", []),
        "ai_notes":          roadmap_data.get("user_summary", ""),
        "next_review_at":    (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
    }
    saved = await supabase_service.upsert_roadmap(user_id, db_roadmap)

    # Include localization metadata for Flutter UI
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
# UTILITY ENDPOINTS
# ════════════════════════════════════════════════════════════════════

@router.get("/models")
async def get_available_models(user: dict = Depends(get_current_user)):
    """Return list of available AI models in priority order."""
    return {"models": ai_service.get_available_models()}


@router.get("/conversations")
@limiter.limit(GENERAL_LIMIT)
async def get_conversations(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """Return all conversations for the current user."""
    convs = await supabase_service.get_conversations(user["id"])
    return {"conversations": convs, "total": len(convs)}


@router.get("/conversations/{conversation_id}/messages")
@limiter.limit(GENERAL_LIMIT)
async def get_messages(
    conversation_id: str,
    request:         Request,
    user:            dict = Depends(get_current_user),
):
    """Return all messages in a conversation."""
    messages = await supabase_service.get_messages(conversation_id)
    return {"messages": messages, "total": len(messages), "conversation_id": conversation_id}


@router.get("/country-info")
async def get_country_info(
    country_code: str = "NG",
    user:         dict = Depends(get_current_user),
):
    """
    Return country-specific financial intelligence.
    Useful for Flutter to display localized content before profile load.
    """
    info = ai_service.get_country_info(country_code)
    return info


@router.get("/trending")
@limiter.limit(GENERAL_LIMIT)
async def get_trending_opportunities(
    request:      Request,
    country_code: Optional[str] = None,
    user:         dict = Depends(get_current_user),
):
    """
    Return trending global and local income opportunities.
    Localizes to user's country if no country_code provided.
    """
    if not country_code:
        profile      = await supabase_service.get_profile(user["id"]) or {}
        country_code = profile.get("country", "NG")

    data = await ai_service.get_trending_opportunities(country_code)
    return data
