"""AI Agent Router — Main conversational intelligence
Currency: USD is the global default. User's local_currency is shown alongside for context.
"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT

from models.schemas import ChatRequest, ChatResponse, GenerateTasksRequest
from services.ai_service import ai_service, RISEUP_SYSTEM_PROMPT, ONBOARDING_PROMPT
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/ai", tags=["AI Agent"])
logger = logging.getLogger(__name__)


@router.post("/chat", response_model=ChatResponse)
@limiter.limit(AI_LIMIT)
async def chat(req: ChatRequest, request: Request, user: dict = Depends(get_current_user)):
    """Main AI chat endpoint — handles all conversation modes"""
    user_id = user["id"]

    if req.conversation_id:
        conv_id = req.conversation_id
    else:
        conv = await supabase_service.create_conversation(user_id)
        conv_id = conv["id"]

    history  = await supabase_service.get_messages(conv_id, limit=20)
    messages = [{"role": m["role"], "content": m["content"]} for m in history if m["role"] in ("user", "assistant")]
    messages.append({"role": "user", "content": req.message})

    await supabase_service.save_message(conv_id, user_id, "user", req.message)

    profile = await supabase_service.get_profile(user_id)
    system  = _build_system_prompt(req.mode, profile)

    result     = await ai_service.chat(messages, system=system, max_tokens=1200, preferred_model=req.preferred_model)
    ai_content = result["content"]
    ai_model   = result["model"]

    ai_msg = await supabase_service.save_message(conv_id, user_id, "assistant", ai_content, ai_model=ai_model)

    onboarding_complete = False
    extracted_profile   = None
    suggested_tasks     = None

    if req.mode == "onboarding" and "PROFILE_COMPLETE" in ai_content:
        try:
            all_messages = messages + [{"role": "assistant", "content": ai_content}]
            extracted_profile = await ai_service.analyze_onboarding(all_messages)
            if extracted_profile:
                # Auto-detect local currency from country
                country_code = extracted_profile.get("country", "")
                if country_code:
                    try:
                        cur_res = supabase_service.db.rpc(
                            "set_local_currency_from_country",
                            {"uid": user_id, "country_code": country_code}
                        ).execute()
                    except Exception:
                        pass  # non-critical

                await supabase_service.update_profile(user_id, {
                    **extracted_profile,
                    "onboarding_completed": True
                })
                onboarding_complete = True

                tasks_data = await ai_service.generate_income_tasks(extracted_profile, count=5)
                if tasks_data:
                    for t in tasks_data:
                        t["estimated_earnings"] = t.pop("estimated_earnings_max", 0)
                    saved_tasks    = await supabase_service.create_tasks_bulk(user_id, tasks_data)
                    suggested_tasks = saved_tasks[:5]

            ai_content = (
                "🎉 Amazing! I've got everything I need to build your "
                "personalised wealth roadmap.\n\n"
                "Your profile is complete and your first income tasks are "
                "ready. Let's start your journey to financial freedom! 💪"
            )

        except Exception as e:
            logger.error(f"Onboarding processing error: {e}")
            ai_content = "✅ Profile complete! Preparing your personalised roadmap now..."

    return ChatResponse(
        content=ai_content,
        conversation_id=conv_id,
        message_id=ai_msg.get("id", ""),
        ai_model=ai_model,
        onboarding_complete=onboarding_complete,
        extracted_profile=extracted_profile,
        suggested_tasks=suggested_tasks
    )


@router.post("/generate-tasks")
@limiter.limit(AI_LIMIT)
async def generate_tasks(req: GenerateTasksRequest, request: Request, user: dict = Depends(get_current_user)):
    """Generate fresh AI-powered income tasks"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, "Complete onboarding first")

    tasks_data = await ai_service.generate_income_tasks(profile, count=req.count or 5)
    if not tasks_data:
        raise HTTPException(500, "Failed to generate tasks")

    for t in tasks_data:
        t["estimated_earnings"] = t.pop("estimated_earnings_max", t.get("estimated_earnings", 0))
        t.pop("estimated_earnings_min", None)

    saved = await supabase_service.create_tasks_bulk(user_id, tasks_data)
    return {"tasks": saved, "count": len(saved)}


@router.post("/generate-roadmap")
@limiter.limit(AI_LIMIT)
async def generate_roadmap(request: Request, user: dict = Depends(get_current_user)):
    """Generate personalized 3-stage wealth roadmap"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(400, "Complete onboarding first")

    roadmap_data = await ai_service.generate_roadmap(profile)
    if not roadmap_data:
        raise HTTPException(500, "Failed to generate roadmap")

    db_roadmap = {
        "current_stage":       roadmap_data.get("current_stage", "immediate_income"),
        "stage_1_milestones":  roadmap_data.get("stage_1", {}).get("milestones", []),
        "stage_2_milestones":  roadmap_data.get("stage_2", {}).get("milestones", []),
        "stage_3_milestones":  roadmap_data.get("stage_3", {}).get("milestones", []),
        "ai_notes":            roadmap_data.get("summary", ""),
        "next_review_at":      (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
    }
    saved = await supabase_service.upsert_roadmap(user_id, db_roadmap)
    return {"roadmap": roadmap_data, "saved": saved}


@router.get("/models")
async def get_available_models(user: dict = Depends(get_current_user)):
    return {"models": ai_service.get_available_models()}


@router.get("/conversations")
async def get_conversations(user: dict = Depends(get_current_user)):
    convs = await supabase_service.get_conversations(user["id"])
    return {"conversations": convs}


@router.get("/conversations/{conversation_id}/messages")
async def get_messages(conversation_id: str, user: dict = Depends(get_current_user)):
    messages = await supabase_service.get_messages(conversation_id)
    return {"messages": messages}


def _build_system_prompt(mode: str, profile: dict) -> str:
    """Build context-aware system prompt with dual-currency awareness."""
    if mode == "onboarding":
        return ONBOARDING_PROMPT

    base = RISEUP_SYSTEM_PROMPT
    if not profile:
        return base

    display_currency = profile.get("currency", "USD")
    local_currency   = profile.get("local_currency", display_currency)

    # Build a dual-currency label for the AI
    if local_currency and local_currency != "USD":
        currency_line = f"USD (global) / {local_currency} (local) — currently showing {display_currency}"
    else:
        currency_line = "USD"

    context = f"""

CURRENT USER CONTEXT:
- Name: {profile.get('full_name', 'User')}
- Country: {profile.get('country', 'not set')}
- Stage: {profile.get('stage', 'survival').upper()}
- Monthly Income: ${profile.get('monthly_income', 0):,.0f} USD
- Total Earned via RiseUp: ${profile.get('total_earned', 0):,.0f} USD
- Skills: {', '.join(profile.get('current_skills', []) or ['none listed'])}
- Goals: {profile.get('short_term_goal', 'not set')}
- Subscription: {profile.get('subscription_tier', 'free').upper()}
- Currency: {currency_line}

IMPORTANT: Always give income/earnings figures in USD first.
If the user has a local currency ({local_currency}), you may add the local equivalent in parentheses.
Example: "$200 USD (≈ ₦320,000 NGN)"
"""
    return base + context
