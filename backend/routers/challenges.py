"""
30-Day Income Challenges
Agent-driven. Adaptive. Intervenes when you fall behind.
Every challenge is custom-built for the user's skill, stage, and country.
No other wealth app has this.
"""
import json, logging
from datetime import datetime, timezone, date, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/challenges", tags=["Income Challenges"])
logger = logging.getLogger(__name__)


class CreateChallengeRequest(BaseModel):
    challenge_type: str  # first_client | first_100 | first_500_month | skill_30day | custom
    custom_goal: Optional[str] = None
    custom_target_usd: Optional[float] = None


class CheckInRequest(BaseModel):
    challenge_id: str
    action_taken: str
    amount_earned_usd: Optional[float] = 0
    note: Optional[str] = None


CHALLENGE_TEMPLATES = {
    "first_client": {
        "title": "Land Your First Paying Client in 7 Days",
        "target_usd": 50,
        "duration_days": 7,
        "emoji": "🎯",
        "daily_target": "One concrete action toward landing a client",
    },
    "first_100": {
        "title": "Earn Your First $100 in 14 Days",
        "target_usd": 100,
        "duration_days": 14,
        "emoji": "💯",
        "daily_target": "Progress toward $100 total",
    },
    "first_500_month": {
        "title": "Reach $500/Month in 30 Days",
        "target_usd": 500,
        "duration_days": 30,
        "emoji": "🚀",
        "daily_target": "Daily income actions",
    },
    "skill_30day": {
        "title": "Master a Skill and Get Paid in 30 Days",
        "target_usd": 200,
        "duration_days": 30,
        "emoji": "🎓",
        "daily_target": "Learn + apply",
    },
}


@router.post("/create")
@limiter.limit(AI_LIMIT)
async def create_challenge(req: CreateChallengeRequest, request: Request, user: dict = Depends(get_current_user)):
    """Create a personalized income challenge with AI-generated daily plan"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}

    template = CHALLENGE_TEMPLATES.get(req.challenge_type, CHALLENGE_TEMPLATES["first_100"])
    title = req.custom_goal or template["title"]
    target = req.custom_target_usd or template["target_usd"]
    duration = template["duration_days"]
    country = profile.get("country", "NG")
    skills = ", ".join(profile.get("current_skills", []) or ["no skills listed"])

    # AI generates the daily plan
    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Challenge: {title}\nTarget: ${target}\nDuration: {duration} days\nUser: {profile.get('full_name','User')} in {country}\nSkills: {skills}\nStage: {profile.get('stage','survival')}"}],
        system="""Create a detailed income challenge daily plan.
Each day has ONE specific action that moves toward the goal.
Actions must be completable in 30-60 minutes.
Real platforms, real steps, no vagueness.
JSON:
{
  "challenge_description": "Why this challenge will work",
  "daily_plan": [{"day": 1, "action": "exact specific action", "expected_outcome": "...", "time_minutes": 30, "platform": "..."}],
  "milestones": [{"day": 7, "target_usd": 0, "milestone": "..."}],
  "success_formula": "The key to completing this challenge",
  "common_failure_point": "Where most people quit and how to avoid it"
}
Return valid JSON only.""",
        max_tokens=2000,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan_data = json.loads(raw)
    except Exception:
        plan_data = {"daily_plan": [], "challenge_description": result["content"]}

    start_date = datetime.now(timezone.utc).date()
    end_date = start_date + timedelta(days=duration)

    saved = supabase_service.client.table("income_challenges").insert({
        "user_id": user_id,
        "title": title,
        "challenge_type": req.challenge_type,
        "target_usd": target,
        "current_usd": 0,
        "duration_days": duration,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "status": "active",
        "daily_plan": json.dumps(plan_data.get("daily_plan", [])),
        "milestones": json.dumps(plan_data.get("milestones", [])),
        "plan_data": json.dumps(plan_data),
        "current_day": 1,
        "streak": 0,
        "emoji": template.get("emoji", "🎯"),
    }).execute()

    challenge = saved.data[0] if saved.data else {}
    return {**challenge, "plan": plan_data, "message": f"Challenge started! Day 1 action: {plan_data.get('daily_plan',[{}])[0].get('action','Get started!')}"}


@router.post("/check-in")
@limiter.limit(GENERAL_LIMIT)
async def daily_checkin(req: CheckInRequest, request: Request, user: dict = Depends(get_current_user)):
    """Log daily progress on a challenge"""
    user_id = user["id"]
    sb = supabase_service.client

    challenge = sb.table("income_challenges").select("*").eq(
        "id", req.challenge_id).eq("user_id", user_id).single().execute()

    if not challenge.data:
        raise HTTPException(404, "Challenge not found")

    c = challenge.data
    today = date.today().isoformat()
    new_total = (c.get("current_usd") or 0) + (req.amount_earned_usd or 0)
    new_day = min((c.get("current_day") or 1) + 1, c["duration_days"])
    new_streak = (c.get("streak") or 0) + 1
    progress_pct = round(new_total / c["target_usd"] * 100, 1)
    completed = new_total >= c["target_usd"]

    # Save check-in
    sb.table("challenge_checkins").insert({
        "challenge_id": req.challenge_id,
        "user_id": user_id,
        "day_number": c.get("current_day", 1),
        "action_taken": req.action_taken,
        "amount_earned_usd": req.amount_earned_usd or 0,
        "note": req.note,
        "checkin_date": today,
    }).execute()

    # Update challenge
    update_data = {
        "current_usd": new_total,
        "current_day": new_day,
        "streak": new_streak,
        "progress_pct": progress_pct,
        "last_checkin": today,
    }
    if completed:
        update_data["status"] = "completed"
        update_data["completed_at"] = datetime.now(timezone.utc).isoformat()

    sb.table("income_challenges").update(update_data).eq("id", req.challenge_id).execute()

    # Get tomorrow's action
    plan = json.loads(c.get("daily_plan", "[]"))
    tomorrow_action = plan[new_day - 1]["action"] if new_day <= len(plan) else "Keep going — you're in the zone!"

    response = {
        "checked_in": True,
        "day": new_day,
        "streak": new_streak,
        "total_earned_usd": round(new_total, 2),
        "progress_pct": progress_pct,
        "target_usd": c["target_usd"],
        "completed": completed,
        "tomorrow_action": tomorrow_action,
        "message": "🏆 CHALLENGE COMPLETE! You did it!" if completed else f"Day {new_day - 1} done. Streak: {new_streak} days 🔥",
    }

    # AI intervention if falling behind
    days_elapsed = new_day - 1
    expected_progress = (days_elapsed / c["duration_days"]) * 100
    if progress_pct < expected_progress - 20:
        response["intervention_needed"] = True
        response["intervention_message"] = f"You're {round(expected_progress - progress_pct)}% behind pace. Tomorrow needs to count — focus on {tomorrow_action[:50]}."

    return response


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_challenges(request: Request, user: dict = Depends(get_current_user)):
    result = supabase_service.client.table("income_challenges").select("*").eq(
        "user_id", user["id"]).order("created_at", desc=True).execute()
    challenges = result.data or []
    active = [c for c in challenges if c["status"] == "active"]
    completed = [c for c in challenges if c["status"] == "completed"]
    return {
        "challenges": challenges,
        "active_count": len(active),
        "completed_count": len(completed),
        "active_challenges": active,
    }


@router.get("/{challenge_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_challenge(challenge_id: str, request: Request, user: dict = Depends(get_current_user)):
    c = supabase_service.client.table("income_challenges").select("*").eq(
        "id", challenge_id).eq("user_id", user["id"]).single().execute()
    if not c.data:
        raise HTTPException(404, "Challenge not found")

    checkins = supabase_service.client.table("challenge_checkins").select("*").eq(
        "challenge_id", challenge_id).order("day_number").execute()

    return {"challenge": c.data, "checkins": checkins.data or []}


@router.post("/{challenge_id}/ai-intervention")
@limiter.limit(AI_LIMIT)
async def ai_intervention(challenge_id: str, request: Request, user: dict = Depends(get_current_user)):
    """AI analyzes progress and gives specific recovery plan"""
    user_id = user["id"]
    c_res = supabase_service.client.table("income_challenges").select("*").eq(
        "id", challenge_id).eq("user_id", user_id).single().execute()
    if not c_res.data:
        raise HTTPException(404)

    c = c_res.data
    checkins = supabase_service.client.table("challenge_checkins").select("*").eq("challenge_id", challenge_id).execute()
    profile = await supabase_service.get_profile(user_id) or {}

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Challenge: {c['title']}\nTarget: ${c['target_usd']}\nEarned: ${c['current_usd']}\nDay: {c['current_day']}/{c['duration_days']}\nStreak: {c['streak']}\nCheckins: {len(checkins.data or [])}\nUser stage: {profile.get('stage','survival')}"}],
        system="""You are a challenge coach. This user is behind. Help them recover.
Be direct, specific, encouraging. Not generic.
JSON: {"situation_assessment":"...", "recovery_plan":["specific action 1","specific action 2","specific action 3"], "daily_minimum":"the minimum they must do each remaining day", "you_can_do_this":"personal message of belief", "adjusted_target_if_needed":"..."}""",
        max_tokens=600,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan = json.loads(raw)
    except Exception:
        plan = {"recovery_plan": [result["content"]]}

    return {"intervention": plan, "challenge_id": challenge_id}
