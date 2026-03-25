"""Goals Router — Financial goal setting, tracking & AI-powered suggestions
All monetary amounts are stored and calculated in USD by default.
The user's preferred display currency is read from profile.currency.
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, field_validator
from middleware.rate_limit import limiter, GENERAL_LIMIT, AI_LIMIT
from services.supabase_service import supabase_service
from services.ai_service import ai_service
from utils.auth import get_current_user

router = APIRouter(prefix="/goals", tags=["Goals"])
logger = logging.getLogger(__name__)


class GoalCreate(BaseModel):
    title: str
    description: Optional[str] = None
    goal_type: str = "savings"
    target_amount: Optional[float] = None
    currency: str = "USD"       # defaults to USD; user may pass their local currency
    target_date: Optional[str] = None   # ISO date string
    priority: str = "medium"
    icon: str = "🎯"

    @field_validator("title")
    @classmethod
    def validate_title(cls, v):
        if not v or not v.strip():
            raise ValueError("Title cannot be empty")
        if len(v) > 120:
            raise ValueError("Title too long")
        return v.strip()


class GoalUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    target_amount: Optional[float] = None
    current_amount: Optional[float] = None
    target_date: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    icon: Optional[str] = None


class GoalContribute(BaseModel):
    amount: float
    description: Optional[str] = None


@router.get("/")
async def list_goals(status: str = None, user: dict = Depends(get_current_user)):
    """Get all goals for the user"""
    q = supabase_service.db.table("goals").select("*").eq("user_id", user["id"])
    if status:
        q = q.eq("status", status)
    res = q.order("created_at", desc=False).execute()
    goals = res.data or []

    # Calculate progress % for each goal
    for g in goals:
        if g.get("target_amount") and float(g["target_amount"]) > 0:
            g["progress_percent"] = min(100, round(
                float(g.get("current_amount") or 0) / float(g["target_amount"]) * 100, 1
            ))
        else:
            g["progress_percent"] = 0

    return {"goals": goals, "count": len(goals)}


@router.post("/")
@limiter.limit(GENERAL_LIMIT)
async def create_goal(req: GoalCreate, request: Request, user: dict = Depends(get_current_user)):
    """Create a new financial goal"""
    user_id = user["id"]

    # Build milestone checkpoints automatically
    milestones = []
    if req.target_amount:
        milestones = [
            {"percent": 25,  "label": "Quarter way there! 🎉",      "reached_at": None},
            {"percent": 50,  "label": "Halfway! You're doing it! 💪","reached_at": None},
            {"percent": 75,  "label": "75% done! Almost there! 🔥",  "reached_at": None},
            {"percent": 100, "label": "Goal Achieved! 🏆",           "reached_at": None},
        ]

    data = {
        "user_id":       user_id,
        "title":         req.title,
        "description":   req.description,
        "goal_type":     req.goal_type,
        "target_amount": req.target_amount,
        "currency":      req.currency,
        "target_date":   req.target_date,
        "priority":      req.priority,
        "icon":          req.icon,
        "milestones":    milestones,
    }

    res = supabase_service.db.table("goals").insert(data).execute()
    goal = res.data[0] if res.data else {}

    # Unlock "first goal" achievement
    supabase_service.db.rpc("unlock_achievement", {
        "uid": user_id, "ach_key": "first_goal"
    }).execute()

    return {"goal": goal, "message": "🎯 Goal created! Let's crush it!"}


@router.patch("/{goal_id}")
async def update_goal(goal_id: str, req: GoalUpdate, user: dict = Depends(get_current_user)):
    """Update a goal"""
    data = {k: v for k, v in req.dict().items() if v is not None}
    if not data:
        raise HTTPException(400, "No fields to update")

    res = supabase_service.db.table("goals").update(data).eq("id", goal_id).eq("user_id", user["id"]).execute()
    if not res.data:
        raise HTTPException(404, "Goal not found")
    return {"goal": res.data[0]}


@router.post("/{goal_id}/contribute")
async def contribute_to_goal(
    goal_id: str, req: GoalContribute, user: dict = Depends(get_current_user)
):
    """Add money toward a goal and check milestone triggers"""
    user_id = user["id"]

    # Get goal
    res = supabase_service.db.table("goals").select("*").eq("id", goal_id).eq("user_id", user_id).single().execute()
    if not res.data:
        raise HTTPException(404, "Goal not found")
    goal = res.data

    new_amount = float(goal.get("current_amount") or 0) + req.amount
    target = float(goal.get("target_amount") or 0)
    progress = (new_amount / target * 100) if target > 0 else 0

    # Check milestone triggers
    milestones = goal.get("milestones") or []
    newly_reached = []
    for m in milestones:
        if not m.get("reached_at") and progress >= m["percent"]:
            m["reached_at"] = datetime.now(timezone.utc).isoformat()
            newly_reached.append(m["label"])

    update_data: dict = {"current_amount": new_amount, "milestones": milestones}
    achievements_unlocked = []

    # Mark complete if 100%
    if progress >= 100:
        update_data["status"] = "completed"
        update_data["completed_at"] = datetime.now(timezone.utc).isoformat()
        ach = supabase_service.db.rpc("unlock_achievement", {
            "uid": user_id, "ach_key": "goal_complete"
        }).execute()
        if ach.data and ach.data.get("success"):
            achievements_unlocked.append(ach.data["achievement"])

    supabase_service.db.table("goals").update(update_data).eq("id", goal_id).execute()

    goal_currency = goal.get("currency", "USD")
    return {
        "current_amount":        new_amount,
        "progress_percent":      round(progress, 1),
        "milestones_reached":    newly_reached,
        "achievements_unlocked": achievements_unlocked,
        "completed":             progress >= 100,
        "message":               f"💰 +{goal_currency} {req.amount:,.2f} added to goal!" + (
            " 🏆 GOAL ACHIEVED!" if progress >= 100 else ""
        ),
    }


@router.delete("/{goal_id}")
async def delete_goal(goal_id: str, user: dict = Depends(get_current_user)):
    """Delete a goal"""
    supabase_service.db.table("goals").delete().eq("id", goal_id).eq("user_id", user["id"]).execute()
    return {"message": "Goal deleted"}


@router.post("/ai-suggest")
@limiter.limit(AI_LIMIT)
async def suggest_goals(request: Request, user: dict = Depends(get_current_user)):
    """Get AI-suggested goals based on user profile"""
    profile = await supabase_service.get_profile(user["id"])
    if not profile:
        raise HTTPException(400, "Complete onboarding first")

    # Use display currency for AI context, also show local currency if different
    display_currency = profile.get("currency", "USD")
    local_currency   = profile.get("local_currency", display_currency)
    country          = profile.get("country", "your country")

    currency_context = (
        f"USD (show local equivalent in {local_currency} too)"
        if local_currency != "USD"
        else "USD"
    )

    prompt = f"""Based on this user profile, suggest 3 specific, achievable financial goals.

Profile:
- Stage: {profile.get('stage', 'survival')}
- Monthly Income: ${profile.get('monthly_income', 0):,.0f} USD
- Monthly Expenses: ${profile.get('monthly_expenses', 0):,.0f} USD
- Short-term goal: {profile.get('short_term_goal', 'not set')}
- Country: {country}
- Display Currency: {display_currency}

Return ONLY a JSON array of 3 goals:
[
  {{
    "title": "Goal title",
    "description": "Why this goal matters for them",
    "goal_type": "savings|income|skill|debt_payoff|emergency_fund",
    "target_amount": 500,
    "currency": "{display_currency}",
    "target_date": "2026-06-30",
    "priority": "high",
    "icon": "🎯",
    "ai_notes": "Specific advice for achieving this goal"
  }}
]

IMPORTANT: All target_amount values must be in {currency_context}.
Be realistic for someone in {country}."""

    result = await ai_service.chat(
        [{"role": "user", "content": "Suggest goals for me"}],
        prompt, max_tokens=800
    )
    try:
        import json
        content = result["content"].strip().strip("```json").strip("```").strip()
        goals = json.loads(content)
        return {"suggestions": goals}
    except Exception:
        raise HTTPException(500, "Could not generate goal suggestions")
