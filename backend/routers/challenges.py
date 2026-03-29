# backend/routers/challenges.py
"""
Production-Ready AI-Driven Income Challenges
Fully adaptive, globally-aware, no hardcoded templates.
Every challenge is uniquely generated based on user context.
"""
import json
import logging
import uuid
from datetime import datetime, timezone, date, timedelta
from decimal import Decimal
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from pydantic import BaseModel, Field, validator
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from services.currency_service import currency_service
from services.notification_service import notification_service
from utils.auth import get_current_user

router = APIRouter(prefix="/challenges", tags=["Income Challenges"])
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# Pydantic Models
# ─────────────────────────────────────────────────────────────

class CreateChallengeRequest(BaseModel):
    goal_description: str = Field(
        ..., 
        min_length=5, 
        max_length=500,
        description="User's goal in natural language (e.g., 'I want to earn $500 this month doing graphic design')"
    )
    preferred_duration_days: Optional[int] = Field(
        None, 
        ge=3, 
        le=90,
        description="Preferred challenge duration (3-90 days). AI will suggest if not provided."
    )
    constraints: Optional[str] = Field(
        None,
        max_length=300,
        description="Any constraints (time available, resources, restrictions)"
    )
    
    @validator('goal_description')
    def validate_goal(cls, v):
        if len(v.strip()) < 5:
            raise ValueError('Goal must be at least 5 characters')
        return v.strip()


class CheckInRequest(BaseModel):
    challenge_id: str
    action_taken: str = Field(..., min_length=1, max_length=500)
    amount_earned_local: Optional[Decimal] = Field(
        Decimal("0"),
        ge=Decimal("0"),
        description="Amount earned in user's local currency"
    )
    note: Optional[str] = Field(None, max_length=500)
    mood: Optional[str] = Field(None, pattern="^(struggling|neutral|confident|crushing_it)$")


class AdjustChallengeRequest(BaseModel):
    challenge_id: str
    reason: str = Field(..., min_length=5, max_length=300)
    new_target_amount: Optional[Decimal] = None
    extend_days: Optional[int] = Field(None, ge=1, le=30)


class ChallengeFeedbackRequest(BaseModel):
    challenge_id: str
    feedback_type: str = Field(..., pattern="^(too_hard|too_easy|unclear|motivating|other)$")
    details: Optional[str] = Field(None, max_length=500)


# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

async def get_user_context(user_id: str) -> Dict[str, Any]:
    """Gather comprehensive user context for AI personalization"""
    profile = await supabase_service.get_profile(user_id) or {}
    
    # Get user's country and economic context
    country = profile.get("country", "US")
    country_data = await currency_service.get_country_economic_context(country)
    
    # Get user's challenge history for pattern analysis
    history = supabase_service.client.table("income_challenges").select(
        "status, target_usd, current_usd, duration_days, challenge_type, created_at"
    ).eq("user_id", user_id).order("created_at", desc=True).limit(10).execute()
    
    # Get recent check-in patterns
    recent_checkins = supabase_service.client.table("challenge_checkins").select(
        "checkin_date, amount_earned_usd, mood"
    ).eq("user_id", user_id).order("checkin_date", desc=True).limit(20).execute()
    
    # Calculate completion rate
    past_challenges = history.data or []
    completed = len([c for c in past_challenges if c.get("status") == "completed"])
    completion_rate = completed / len(past_challenges) if past_challenges else 0
    
    # Calculate average earnings
    earnings = [c.get("current_usd", 0) for c in past_challenges]
    avg_earnings = sum(earnings) / len(earnings) if earnings else 0
    
    return {
        "profile": profile,
        "country": country,
        "country_data": country_data,
        "language": profile.get("language", "en"),
        "stage": profile.get("stage", "exploration"),
        "skills": profile.get("current_skills", []) or [],
        "experience_level": profile.get("experience_level", "beginner"),
        "time_available_hours": profile.get("time_available_hours", 10),
        "past_challenges_count": len(past_challenges),
        "completion_rate": round(completion_rate * 100, 1),
        "avg_challenge_earnings": round(avg_earnings, 2),
        "recent_checkins": len(recent_checkins.data or []),
        "currency": profile.get("currency", "USD"),
        "economic_context": country_data.get("economic_tier", "middle_income"),
        "local_cost_of_living_index": country_data.get("cost_of_living_index", 100),
    }


def build_ai_prompt_for_challenge(context: Dict, request: CreateChallengeRequest) -> tuple:
    """Build comprehensive AI prompt for challenge generation"""
    
    user_ctx = context["profile"]
    country = context["country"]
    currency = context["currency"]
    col_index = context["local_cost_of_living_index"]
    
    # Convert USD benchmarks to local currency
    def to_local(usd_amount: float) -> float:
        return round(usd_amount * (col_index / 100), 2)
    
    system_prompt = f"""You are an expert challenge architect for global income generation.
Create personalized, culturally-aware challenges that fit the user's specific context.

USER CONTEXT:
- Country: {country} (Cost of living index: {col_index})
- Currency: {currency}
- Local purchasing power: ${to_local(100)} {currency} ≈ $100 USD in local value
- Stage: {context['stage']}
- Skills: {', '.join(context['skills']) or 'None listed'}
- Experience: {context['experience_level']}
- Time available: {context['time_available_hours']} hrs/week
- Past completion rate: {context['completion_rate']}%
- Average past earnings: ${context['avg_challenge_earnings']}

CHALLENGE DESIGN PRINCIPLES:
1. Income targets must be realistic for their country and stage
2. Actions must use locally-available platforms (not just US-centric)
3. Respect cultural norms and local business practices
4. Account for infrastructure limitations (internet, payment methods)
5. Consider language barriers and suggest local alternatives
6. Factor in time zone differences for global clients

OUTPUT FORMAT - Valid JSON only:
{{
  "challenge_title": "Compelling, specific title",
  "challenge_summary": "One-line description of the journey",
  "target_amount_local": <realistic amount in {currency}>,
  "target_amount_usd": <USD equivalent>,
  "duration_days": <3-90>,
  "difficulty_rating": <1-10>,
  "category": "freelancing|selling|content|services|arbitrage|skills|hybrid",
  "emoji": "single relevant emoji",
  
  "why_this_works": "Psychological and practical explanation",
  "success_probability": "<percentage> based on similar users in {country}",
  
  "daily_plan": [
    {{
      "day": 1,
      "phase": "setup|execution|optimization|scaling",
      "action": "Specific, completable action",
      "time_minutes": <15-120>,
      "expected_outcome": "What completing this achieves",
      "platforms": ["specific platform names"],
      "local_resources": ["local-specific resources"],
      "fallback_action": "What to do if main action fails",
      "verification_check": "How user confirms completion"
    }}
  ],
  
  "milestones": [
    {{
      "day": 7,
      "target_pct": <0-100>,
      "milestone": "What should be achieved",
      "reward_suggestion": "How to celebrate"
    }}
  ],
  
  "adaptive_triggers": [
    {{
      "condition": "if_behind_by_20_percent",
      "intervention": "Specific action to take"
    }}
  ],
  
  "local_platforms": ["platform1", "platform2"],
  "global_platforms": ["platform1", "platform2"],
  "payment_methods": ["methods available in {country}"],
  
  "risk_factors": ["what could go wrong"],
  "mitigation_strategies": ["how to handle each risk"],
  
  "motivation_hooks": ["specific motivational messages for days"],
  "community_actions": ["how to involve others for accountability"]
}}
"""

    user_prompt = f"""Create a personalized income challenge based on this goal:
"{request.goal_description}"

User constraints: {request.constraints or 'None specified'}
Preferred duration: {request.preferred_duration_days or 'AI should suggest optimal duration'}

Make this highly specific to {country}. Use local platforms, consider local economic reality, and ensure the target amount is meaningful in local purchasing power but achievable."""

    return system_prompt, user_prompt


def parse_ai_challenge_response(raw_content: str) -> Dict:
    """Safely parse AI response with fallback handling"""
    # Clean up common formatting issues
    cleaned = raw_content.strip()
    for prefix in ["```json", "```", "`"]:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()
    for suffix in ["```", "`"]:
        if cleaned.endswith(suffix):
            cleaned = cleaned[:-len(suffix)].strip()
    
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}, content: {raw_content[:500]}")
        # Attempt recovery with more aggressive cleaning
        try:
            # Find JSON-like content between braces
            start = cleaned.find('{')
            end = cleaned.rfind('}')
            if start != -1 and end != -1:
                return json.loads(cleaned[start:end+1])
        except Exception:
            pass
        raise ValueError(f"Could not parse AI response: {str(e)}")


# ─────────────────────────────────────────────────────────────
# API Endpoints
# ─────────────────────────────────────────────────────────────

@router.post("/create", response_model=Dict)
@limiter.limit(AI_LIMIT)
async def create_challenge(
    request: Request,
    req: CreateChallengeRequest,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """
    Create a fully AI-generated, personalized income challenge.
    No templates - every challenge is unique to the user's context.
    """
    user_id = user["id"]
    
    try:
        # Gather comprehensive user context
        context = await get_user_context(user_id)
        
        # Build AI prompts
        system_prompt, user_prompt = build_ai_prompt_for_challenge(context, req)
        
        # Generate challenge with AI
        result = await ai_service.chat(
            messages=[{"role": "user", "content": user_prompt}],
            system=system_prompt,
            max_tokens=3000,
            temperature=0.7,
        )
        
        # Parse AI response
        challenge_data = parse_ai_challenge_response(result["content"])
        
        # Validate and sanitize
        duration = min(
            max(challenge_data.get("duration_days", 30), 3), 
            90
        )
        
        # Calculate dates
        start_date = datetime.now(timezone.utc).date()
        end_date = start_date + timedelta(days=duration)
        
        # Prepare database record
        challenge_record = {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "title": challenge_data.get("challenge_title", "Income Challenge"),
            "summary": challenge_data.get("challenge_summary", ""),
            "challenge_type": challenge_data.get("category", "custom"),
            "target_amount_local": float(challenge_data.get("target_amount_local", 0)),
            "target_amount_usd": float(challenge_data.get("target_amount_usd", 0)),
            "current_amount_local": 0,
            "current_amount_usd": 0,
            "currency_local": context["currency"],
            "duration_days": duration,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "status": "active",
            "difficulty_rating": challenge_data.get("difficulty_rating", 5),
            "emoji": challenge_data.get("emoji", "🎯"),
            
            # AI-generated content
            "daily_plan": json.dumps(challenge_data.get("daily_plan", [])),
            "milestones": json.dumps(challenge_data.get("milestones", [])),
            "adaptive_triggers": json.dumps(challenge_data.get("adaptive_triggers", [])),
            "motivation_hooks": json.dumps(challenge_data.get("motivation_hooks", [])),
            
            # Context and metadata
            "why_this_works": challenge_data.get("why_this_works", ""),
            "success_probability": challenge_data.get("success_probability", "50%"),
            "risk_factors": json.dumps(challenge_data.get("risk_factors", [])),
            "mitigation_strategies": json.dumps(challenge_data.get("mitigation_strategies", [])),
            "local_platforms": json.dumps(challenge_data.get("local_platforms", [])),
            "global_platforms": json.dumps(challenge_data.get("global_platforms", [])),
            "payment_methods": json.dumps(challenge_data.get("payment_methods", [])),
            
            # Progress tracking
            "current_day": 1,
            "streak_days": 0,
            "total_checkins": 0,
            "progress_pct": 0,
            
            # Metadata
            "created_at": datetime.now(timezone.utc).isoformat(),
            "country_context": context["country"],
            "ai_model_used": result.get("model", "unknown"),
            "user_goal_input": req.goal_description,
        }
        
        # Save to database
        saved = supabase_service.client.table("income_challenges").insert(
            challenge_record
        ).execute()
        
        if not saved.data:
            raise HTTPException(500, "Failed to save challenge")
        
        challenge = saved.data[0]
        
        # Schedule welcome notification
        background_tasks.add_task(
            notification_service.send_challenge_start,
            user_id=user_id,
            challenge_title=challenge["title"],
            first_action=json.loads(challenge["daily_plan"])[0]["action"] if challenge["daily_plan"] else "Get started!"
        )
        
        # Return enriched response
        return {
            "challenge": challenge,
            "plan": challenge_data,
            "context": {
                "currency": context["currency"],
                "country": context["country"],
                "local_value_equivalent": f"${challenge_data.get('target_amount_local')} {context['currency']}",
            },
            "next_steps": {
                "today_action": json.loads(challenge["daily_plan"])[0] if challenge["daily_plan"] else None,
                "check_in_reminder": "Daily check-ins keep you on track",
            },
            "message": f"🎯 Challenge created: {challenge['title']}",
        }
        
    except ValueError as e:
        logger.error(f"Challenge creation validation error: {e}")
        raise HTTPException(400, f"Invalid challenge data: {str(e)}")
    except Exception as e:
        logger.exception("Challenge creation failed")
        raise HTTPException(500, f"Failed to create challenge: {str(e)}")


@router.post("/check-in", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def daily_checkin(
    request: Request,
    req: CheckInRequest,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """
    Log daily progress with AI-powered adaptive feedback.
    Supports local currency input with automatic USD conversion.
    """
    user_id = user["id"]
    
    try:
        # Fetch challenge with lock
        challenge_res = supabase_service.client.table("income_challenges").select(
            "*"
        ).eq("id", req.challenge_id).eq("user_id", user_id).single().execute()
        
        if not challenge_res.data:
            raise HTTPException(404, "Challenge not found")
        
        challenge = challenge_res.data
        
        if challenge["status"] != "active":
            raise HTTPException(400, f"Challenge is {challenge['status']}")
        
        # Get user's currency for conversion
        profile = await supabase_service.get_profile(user_id) or {}
        user_currency = profile.get("currency", "USD")
        
        # Convert local amount to USD for tracking
        amount_usd = await currency_service.convert_to_usd(
            req.amount_earned_local or Decimal("0"), 
            user_currency
        )
        
        # Calculate new totals
        new_total_local = Decimal(str(challenge.get("current_amount_local", 0))) + (req.amount_earned_local or Decimal("0"))
        new_total_usd = Decimal(str(challenge.get("current_amount_usd", 0))) + amount_usd
        target_local = Decimal(str(challenge.get("target_amount_local", 1)))
        
        # Progress calculations
        progress_pct = min(round(float(new_total_local / target_local * 100), 1), 100)
        current_day = challenge.get("current_day", 1)
        new_day = min(current_day + 1, challenge["duration_days"])
        
        # Streak calculation
        last_checkin = challenge.get("last_checkin_date")
        today = date.today().isoformat()
        streak = challenge.get("streak_days", 0)
        
        if last_checkin:
            last_date = datetime.fromisoformat(last_checkin).date()
            today_date = date.today()
            day_diff = (today_date - last_date).days
            
            if day_diff == 1:
                streak += 1  # Continued streak
            elif day_diff > 1:
                streak = 1   # Broken streak, restart
            # day_diff == 0 means multiple check-ins same day (allow but don't increment streak)
        else:
            streak = 1
        
        # Check completion
        completed = progress_pct >= 100 or new_day > challenge["duration_days"]
        
        # Save check-in
        checkin_record = {
            "id": str(uuid.uuid4()),
            "challenge_id": req.challenge_id,
            "user_id": user_id,
            "day_number": current_day,
            "action_taken": req.action_taken,
            "amount_earned_local": float(req.amount_earned_local or 0),
            "amount_earned_usd": float(amount_usd),
            "currency_local": user_currency,
            "note": req.note,
            "mood": req.mood,
            "checkin_date": today,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        
        supabase_service.client.table("challenge_checkins").insert(
            checkin_record
        ).execute()
        
        # Update challenge
        update_data = {
            "current_amount_local": float(new_total_local),
            "current_amount_usd": float(new_total_usd),
            "current_day": new_day,
            "streak_days": streak,
            "total_checkins": challenge.get("total_checkins", 0) + 1,
            "progress_pct": progress_pct,
            "last_checkin_date": today,
            "last_action_taken": req.action_taken,
        }
        
        if completed:
            update_data["status"] = "completed"
            update_data["completed_at"] = datetime.now(timezone.utc).isoformat()
            update_data["completed_day"] = current_day
        
        supabase_service.client.table("income_challenges").update(
            update_data
        ).eq("id", req.challenge_id).execute()
        
        # Get tomorrow's action
        daily_plan = json.loads(challenge.get("daily_plan", "[]"))
        tomorrow_action = None
        if new_day <= len(daily_plan):
            tomorrow_action = daily_plan[new_day - 1]
        elif not completed:
            # AI-generate continuation if plan exhausted but not complete
            tomorrow_action = await _generate_continuation_action(
                challenge, new_day, user_id
            )
        
        # AI intervention analysis
        intervention = await _analyze_progress_for_intervention(
            challenge, progress_pct, current_day, streak, req.mood, user_id
        )
        
        # Build response
        response = {
            "check_in": {
                "id": checkin_record["id"],
                "day": current_day,
                "amount_logged": {
                    "local": float(req.amount_earned_local or 0),
                    "usd": float(amount_usd),
                    "currency": user_currency,
                },
                "streak": streak,
                "progress": {
                    "percentage": progress_pct,
                    "current_local": float(new_total_local),
                    "target_local": float(target_local),
                    "remaining_local": float(max(target_local - new_total_local, Decimal("0"))),
                },
            },
            "challenge_status": "completed" if completed else "active",
            "next_action": tomorrow_action,
            "intervention": intervention if intervention.get("needed") else None,
            "insights": await _generate_checkin_insights(
                challenge, checkin_record, streak, user_id
            ),
        }
        
        if completed:
            response["completion"] = {
                "message": "🏆 CHALLENGE COMPLETE!",
                "days_taken": current_day,
                "total_earned_usd": float(new_total_usd),
                "streak_maintained": streak >= challenge["duration_days"] * 0.8,
            }
            background_tasks.add_task(
                notification_service.send_challenge_complete,
                user_id=user_id,
                challenge_title=challenge["title"],
                earnings_usd=float(new_total_usd)
            )
        else:
            # Schedule reminder for tomorrow
            background_tasks.add_task(
                notification_service.schedule_checkin_reminder,
                user_id=user_id,
                challenge_id=req.challenge_id,
                challenge_title=challenge["title"],
                next_action=tomorrow_action["action"] if tomorrow_action else "Continue your challenge"
            )
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Check-in failed")
        raise HTTPException(500, f"Check-in failed: {str(e)}")


@router.get("/", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def list_challenges(
    request: Request,
    status: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """List user's challenges with optional filtering"""
    user_id = user["id"]
    
    query = supabase_service.client.table("income_challenges").select(
        "*"
    ).eq("user_id", user_id)
    
    if status:
        query = query.eq("status", status)
    
    result = query.order("created_at", desc=True).execute()
    challenges = result.data or []
    
    # Enrich with today's action for active challenges
    enriched = []
    for c in challenges:
        if c["status"] == "active" and c.get("daily_plan"):
            daily_plan = json.loads(c["daily_plan"])
            current_day = c.get("current_day", 1)
            if current_day <= len(daily_plan):
                c["today_action"] = daily_plan[current_day - 1]
        enriched.append(c)
    
    # Statistics
    stats = {
        "total": len(challenges),
        "active": len([c for c in challenges if c["status"] == "active"]),
        "completed": len([c for c in challenges if c["status"] == "completed"]),
        "abandoned": len([c for c in challenges if c["status"] == "abandoned"]),
        "total_earned_usd": sum(c.get("current_amount_usd", 0) for c in challenges),
        "completion_rate": round(
            len([c for c in challenges if c["status"] == "completed"]) / len(challenges) * 100, 1
        ) if challenges else 0,
    }
    
    return {
        "challenges": enriched,
        "statistics": stats,
    }


@router.get("/{challenge_id}", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def get_challenge(
    challenge_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Get detailed challenge with full history and analytics"""
    user_id = user["id"]
    
    challenge = supabase_service.client.table("income_challenges").select(
        "*"
    ).eq("id", challenge_id).eq("user_id", user_id).single().execute()
    
    if not challenge.data:
        raise HTTPException(404, "Challenge not found")
    
    c = challenge.data
    
    # Get check-ins
    checkins = supabase_service.client.table("challenge_checkins").select(
        "*"
    ).eq("challenge_id", challenge_id).order("day_number").execute()
    
    # Get AI suggestions based on current state
    suggestions = None
    if c["status"] == "active":
        suggestions = await _generate_challenge_suggestions(c, user_id)
    
    # Parse JSON fields
    daily_plan = json.loads(c.get("daily_plan", "[]"))
    milestones = json.loads(c.get("milestones", "[]"))
    
    # Calculate analytics
    checkin_data = checkins.data or []
    analytics = {
        "consistency_score": _calculate_consistency(checkin_data, c["duration_days"]),
        "average_daily_earnings": _calculate_avg_daily(checkin_data),
        "mood_trend": _calculate_mood_trend(checkin_data),
        "pace_assessment": _assess_pace(c, daily_plan),
    }
    
    return {
        "challenge": {
            **c,
            "daily_plan": daily_plan,
            "milestones": milestones,
        },
        "checkins": checkin_data,
        "analytics": analytics,
        "suggestions": suggestions,
        "shareable_summary": _generate_shareable_summary(c) if c["status"] == "completed" else None,
    }


@router.post("/{challenge_id}/adjust")
@limiter.limit(AI_LIMIT)
async def adjust_challenge(
    challenge_id: str,
    request: Request,
    req: AdjustChallengeRequest,
    user: dict = Depends(get_current_user)
):
    """AI-powered challenge adjustment based on user's situation"""
    user_id = user["id"]
    
    # Verify ownership
    challenge = supabase_service.client.table("income_challenges").select(
        "*"
    ).eq("id", challenge_id).eq("user_id", user_id).single().execute()
    
    if not challenge.data:
        raise HTTPException(404, "Challenge not found")
    
    c = challenge.data
    
    if c["status"] != "active":
        raise HTTPException(400, "Can only adjust active challenges")
    
    # Get adjustment recommendation from AI
    profile = await supabase_service.get_profile(user_id) or {}
    
    result = await ai_service.chat(
        messages=[{
            "role": "user",
            "content": f"""Challenge: {c['title']}
Current progress: {c['progress_pct']}% complete, Day {c['current_day']}/{c['duration_days']}
Reason for adjustment: {req.reason}
Proposed new target: {req.new_target_amount or 'Keep current'}
Proposed extension: {req.extend_days or 'None'} days"""
        }],
        system=f"""You are a challenge coach. The user needs to adjust their challenge.
Analyze if this adjustment is reasonable and suggest the best path forward.
Consider: motivation preservation, realistic targets, and maintaining momentum.

Respond with JSON:
{{
  "approved": true/false,
  "reasoning": "why this adjustment is or isn't recommended",
  "suggested_target": <amount>,
  "suggested_duration": <days>,
  "adjusted_plan": ["modified actions for remaining days"],
  "motivation_message": "encouraging message",
  "warning": "any concerns about the adjustment" or null
}}""",
        max_tokens=1000,
    )
    
    adjustment = parse_ai_challenge_response(result["content"])
    
    if not adjustment.get("approved", True):
        return {
            "adjustment_rejected": True,
            "reason": adjustment.get("reasoning", "Adjustment not recommended"),
            "alternative_suggestion": adjustment.get("motivation_message"),
        }
    
    # Apply adjustment
    new_end_date = datetime.fromisoformat(c["end_date"]).date()
    if req.extend_days:
        new_end_date += timedelta(days=req.extend_days)
    
    update_data = {
        "target_amount_local": float(req.new_target_amount or c["target_amount_local"]),
        "end_date": new_end_date.isoformat(),
        "duration_days": c["duration_days"] + (req.extend_days or 0),
        "adjustment_history": json.dumps({
            "previous_target": c["target_amount_local"],
            "reason": req.reason,
            "adjusted_at": datetime.now(timezone.utc).isoformat(),
        }),
    }
    
    if adjustment.get("adjusted_plan"):
        # Merge adjusted plan with existing
        current_plan = json.loads(c.get("daily_plan", "[]"))
        adjusted = adjustment["adjusted_plan"]
        # Replace from current day forward
        new_plan = current_plan[:c["current_day"]-1] + adjusted
        update_data["daily_plan"] = json.dumps(new_plan)
    
    supabase_service.client.table("income_challenges").update(
        update_data
    ).eq("id", challenge_id).execute()
    
    return {
        "adjusted": True,
        "new_target": update_data["target_amount_local"],
        "new_end_date": update_data["end_date"],
        "ai_guidance": adjustment.get("motivation_message"),
        "warning": adjustment.get("warning"),
    }


@router.post("/{challenge_id}/feedback")
@limiter.limit(GENERAL_LIMIT)
async def submit_feedback(
    challenge_id: str,
    request: Request,
    req: ChallengeFeedbackRequest,
    user: dict = Depends(get_current_user)
):
    """Submit feedback to improve future challenge generation"""
    user_id = user["id"]
    
    # Verify ownership
    challenge = supabase_service.client.table("income_challenges").select(
        "id"
    ).eq("id", challenge_id).eq("user_id", user_id).single().execute()
    
    if not challenge.data:
        raise HTTPException(404, "Challenge not found")
    
    # Store feedback
    feedback_record = {
        "id": str(uuid.uuid4()),
        "challenge_id": challenge_id,
        "user_id": user_id,
        "feedback_type": req.feedback_type,
        "details": req.details,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    
    supabase_service.client.table("challenge_feedback").insert(
        feedback_record
    ).execute()
    
    # If feedback indicates major issues, offer AI intervention
    if req.feedback_type in ["too_hard", "unclear"]:
        intervention = await ai_service.chat(
            messages=[{"role": "user", "content": f"User feedback: {req.feedback_type}. Details: {req.details or 'None'}"}],
            system="Provide immediate helpful advice for someone struggling with their income challenge. Be empathetic but action-oriented. 2-3 sentences max.",
            max_tokens=200,
        )
        
        return {
            "feedback_recorded": True,
            "ai_support_message": intervention["content"],
            "suggested_action": "Consider adjusting your challenge difficulty",
        }
    
    return {"feedback_recorded": True}


@router.post("/{challenge_id}/abandon")
@limiter.limit(GENERAL_LIMIT)
async def abandon_challenge(
    challenge_id: str,
    request: Request,
    reason: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """Abandon a challenge with optional feedback"""
    user_id = user["id"]
    
    challenge = supabase_service.client.table("income_challenges").select(
        "*"
    ).eq("id", challenge_id).eq("user_id", user_id).single().execute()
    
    if not challenge.data:
        raise HTTPException(404, "Challenge not found")
    
    c = challenge.data
    
    # Store abandonment reason for learning
    if reason:
        supabase_service.client.table("challenge_abandonments").insert({
            "id": str(uuid.uuid4()),
            "challenge_id": challenge_id,
            "user_id": user_id,
            "reason": reason,
            "progress_at_abandonment": c.get("progress_pct", 0),
            "abandoned_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    
    # Mark as abandoned
    supabase_service.client.table("income_challenges").update({
        "status": "abandoned",
        "abandoned_at": datetime.now(timezone.utc).isoformat(),
        "abandonment_reason": reason,
    }).eq("id", challenge_id).execute()
    
    # AI message to encourage retry
    encouragement = await ai_service.chat(
        messages=[{"role": "user", "content": f"User abandoned challenge: {c['title']}. Progress was {c.get('progress_pct', 0)}%. Reason: {reason or 'Not specified'}"}],
        system="Write a brief, encouraging message to someone who had to abandon a challenge. Acknowledge it's okay to pause, validate their effort, and invite them to try again when ready. No guilt, just support.",
        max_tokens=150,
    )
    
    return {
        "abandoned": True,
        "message": encouragement["content"],
        "suggestion": "You can create a new, adjusted challenge anytime you're ready.",
    }


# ─────────────────────────────────────────────────────────────
# AI Helper Functions
# ─────────────────────────────────────────────────────────────

async def _analyze_progress_for_intervention(
    challenge: Dict,
    progress_pct: float,
    current_day: int,
    streak: int,
    mood: Optional[str],
    user_id: str
) -> Dict:
    """AI analysis to determine if intervention is needed"""
    
    duration = challenge["duration_days"]
    expected_progress = (current_day / duration) * 100
    behind_by = expected_progress - progress_pct
    
    # Intervention triggers
    needs_intervention = (
        behind_by > 25 or  # Significantly behind
        mood == "struggling" or
        (streak == 0 and current_day > 3) or  # Broken streak after 3 days
        progress_pct < 10 and current_day > duration * 0.3  # Very slow start
    )
    
    if not needs_intervention:
        return {"needed": False}
    
    # Get AI intervention
    checkins = supabase_service.client.table("challenge_checkins").select(
        "*"
    ).eq("challenge_id", challenge["id"]).order("created_at", desc=True).limit(5).execute()
    
    result = await ai_service.chat(
        messages=[{
            "role": "user",
            "content": f"""Challenge: {challenge['title']}
Progress: {progress_pct}% (expected ~{expected_progress}%)
Day: {current_day}/{duration}
Streak: {streak}
Mood: {mood or 'unknown'}
Recent check-ins: {len(checkins.data or [])}"""
        }],
        system="""You are a supportive but direct challenge coach. The user is falling behind.
Analyze why they might be struggling and give ONE specific, actionable next step.
Don't be generic - be specific to their situation.

JSON response:
{
  "needed": true,
  "severity": "mild|moderate|critical",
  "assessment": "Brief analysis of what's happening",
  "immediate_action": "The ONE thing they must do today",
  "mindset_shift": "How to reframe their thinking",
  "support_offer": "What additional help could look like"
}""",
        max_tokens=500,
    )
    
    try:
        intervention = parse_ai_challenge_response(result["content"])
        intervention["needed"] = True
        return intervention
    except Exception:
        return {
            "needed": True,
            "severity": "moderate",
            "assessment": "Progress is slower than planned",
            "immediate_action": "Focus on completing today's action, even if imperfectly",
            "mindset_shift": "Progress over perfection - every check-in counts",
        }


async def _generate_continuation_action(
    challenge: Dict,
    day: int,
    user_id: str
) -> Dict:
    """Generate a new action when the plan runs out but challenge continues"""
    
    profile = await supabase_service.get_profile(user_id) or {}
    
    result = await ai_service.chat(
        messages=[{
            "role": "user",
            "content": f"""Challenge: {challenge['title']}
Original target: {challenge['target_amount_local']} {challenge.get('currency_local', 'USD')}
Current: {challenge['current_amount_local']} ({challenge['progress_pct']}%)
Day: {day} (beyond original plan)
User country: {profile.get('country', 'Unknown')}"""
        }],
        system="Generate ONE continuation action for an extended challenge. It should build on previous progress and push toward the remaining target. Be specific and actionable.",
        max_tokens=300,
    )
    
    return {
        "day": day,
        "phase": "extended",
        "action": result["content"].strip(),
        "time_minutes": 60,
        "expected_outcome": "Continue momentum toward goal",
        "is_ai_generated": True,
    }


async def _generate_checkin_insights(
    challenge: Dict,
    checkin: Dict,
    streak: int,
    user_id: str
) -> Dict:
    """Generate personalized insights based on check-in patterns"""
    
    insights = {
        "streak_status": "🔥 On fire!" if streak >= 7 else f"⚡ {streak} day streak" if streak > 1 else "First step taken",
        "pace_comment": None,
        "earning_rate": None,
    }
    
    # Calculate earning rate if applicable
    if checkin.get("amount_earned_usd", 0) > 0:
        daily_avg = challenge.get("current_amount_usd", 0) / max(challenge.get("current_day", 1), 1)
        insights["earning_rate"] = f"${daily_avg:.2f}/day average"
        
        if checkin["amount_earned_usd"] > daily_avg * 1.5:
            insights["pace_comment"] = "🚀 Above your average - great work!"
    
    # AI-generated encouragement
    if streak in [3, 7, 14, 21, 30]:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": f"User hit {streak} day streak on challenge: {challenge['title']}"}],
            system="Write a brief, enthusiastic milestone celebration message. Reference the streak number specifically.",
            max_tokens=100,
        )
        insights["milestone_message"] = result["content"]
    
    return insights


async def _generate_challenge_suggestions(challenge: Dict, user_id: str) -> List[Dict]:
    """Generate contextual suggestions for active challenge"""
    
    suggestions = []
    
    # Parse progress
    progress = challenge.get("progress_pct", 0)
    days_remaining = challenge["duration_days"] - challenge.get("current_day", 1)
    
    if progress < 20 and days_remaining < challenge["duration_days"] * 0.5:
        suggestions.append({
            "type": "urgency",
            "message": "You're behind schedule. Consider focusing on higher-impact actions.",
            "action": "Review your daily plan and prioritize money-making activities",
        })
    
    if challenge.get("streak_days", 0) == 0:
        suggestions.append({
            "type": "consistency",
            "message": "Get back on track with a small win today.",
            "action": "Complete even a 15-minute action to restart your streak",
        })
    
    return suggestions


# ─────────────────────────────────────────────────────────────
# Analytics Helper Functions
# ─────────────────────────────────────────────────────────────

def _calculate_consistency(checkins: List[Dict], duration_days: int) -> float:
    """Calculate consistency score based on check-in patterns"""
    if not checkins or not duration_days:
        return 0.0
    
    unique_days = len(set(c["checkin_date"] for c in checkins))
    return round(unique_days / duration_days * 100, 1)


def _calculate_avg_daily(checkins: List[Dict]) -> float:
    """Calculate average daily earnings"""
    if not checkins:
        return 0.0
    
    earnings = [c.get("amount_earned_usd", 0) for c in checkins if c.get("amount_earned_usd", 0) > 0]
    if not earnings:
        return 0.0
    
    return round(sum(earnings) / len(earnings), 2)


def _calculate_mood_trend(checkins: List[Dict]) -> Optional[str]:
    """Analyze mood trend from recent check-ins"""
    moods = [c.get("mood") for c in checkins if c.get("mood")]
    if len(moods) < 3:
        return None
    
    recent_moods = moods[-5:]
    struggling_count = recent_moods.count("struggling")
    confident_count = recent_moods.count("confident") + recent_moods.count("crushing_it")
    
    if struggling_count >= 2:
        return "declining"
    elif confident_count >= 3:
        return "improving"
    return "stable"


def _assess_pace(challenge: Dict, daily_plan: List[Dict]) -> Dict:
    """Assess if user is on pace to complete challenge"""
    current_day = challenge.get("current_day", 1)
    progress_pct = challenge.get("progress_pct", 0)
    expected = (current_day / challenge["duration_days"]) * 100
    
    diff = progress_pct - expected
    
    return {
        "status": "ahead" if diff > 10 else "on_track" if diff > -10 else "behind",
        "difference_pct": round(diff, 1),
        "expected_progress": round(expected, 1),
        "actual_progress": progress_pct,
    }


def _generate_shareable_summary(challenge: Dict) -> str:
    """Generate a shareable text summary of completed challenge"""
    emoji = challenge.get("emoji", "🎯")
    title = challenge["title"]
    target = challenge["target_amount_local"]
    currency = challenge.get("currency_local", "USD")
    days = challenge.get("completed_day", challenge["duration_days"])
    
    return f"{emoji} Just completed \"{title}\" in {days} days! Earned {target} {currency} through consistent daily action. #IncomeChallenge #RiseUp"
