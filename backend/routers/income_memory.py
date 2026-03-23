"""
Income Memory Engine — RiseUp's rarest feature.
Builds a personal income DNA profile that learns over time.
Remembers every task, every dollar, every pattern, every failure.
No other app does this.
"""
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/memory", tags=["Income Memory"])
logger = logging.getLogger(__name__)


class MemoryEventRequest(BaseModel):
    event_type: str        # task_completed | task_abandoned | income_earned | client_won | client_lost | skill_learned | obstacle_hit
    title: str
    amount_usd: Optional[float] = 0
    platform: Optional[str] = None
    skill_used: Optional[str] = None
    time_taken_minutes: Optional[int] = None
    note: Optional[str] = None
    outcome: Optional[str] = None   # success | failure | partial


@router.post("/event")
@limiter.limit(GENERAL_LIMIT)
async def record_event(req: MemoryEventRequest, request: Request, user: dict = Depends(get_current_user)):
    """Record any income-related event to memory"""
    user_id = user["id"]
    try:
        supabase_service.client.table("income_memory_events").insert({
            "user_id": user_id,
            "event_type": req.event_type,
            "title": req.title,
            "amount_usd": req.amount_usd or 0,
            "platform": req.platform,
            "skill_used": req.skill_used,
            "time_taken_minutes": req.time_taken_minutes,
            "note": req.note,
            "outcome": req.outcome or "success",
        }).execute()
        return {"recorded": True, "event": req.event_type}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/profile")
@limiter.limit(GENERAL_LIMIT)
async def get_memory_profile(request: Request, user: dict = Depends(get_current_user)):
    """Get the user's full income DNA profile derived from memory"""
    user_id = user["id"]
    sb = supabase_service.client

    events = sb.table("income_memory_events").select("*").eq(
        "user_id", user_id).order("created_at", desc=True).limit(200).execute()
    all_events = events.data or []

    if not all_events:
        return {"has_memory": False, "message": "No income events recorded yet. Complete tasks to build your memory profile."}

    # Calculate DNA stats
    completed = [e for e in all_events if e["outcome"] == "success"]
    abandoned = [e for e in all_events if e["outcome"] == "failure"]
    earned_events = [e for e in all_events if e["amount_usd"] and e["amount_usd"] > 0]

    total_usd = sum(e["amount_usd"] for e in earned_events)
    platforms = {}
    skills = {}
    for e in completed:
        if e.get("platform"):
            platforms[e["platform"]] = platforms.get(e["platform"], 0) + 1
        if e.get("skill_used"):
            skills[e["skill_used"]] = skills.get(e["skill_used"], 0) + 1

    best_platform = max(platforms, key=platforms.get) if platforms else None
    best_skill = max(skills, key=skills.get) if skills else None
    completion_rate = round(len(completed) / len(all_events) * 100) if all_events else 0

    # Time patterns
    hours = [datetime.fromisoformat(e["created_at"].replace("Z","+00:00")).hour for e in completed]
    best_hour = max(set(hours), key=hours.count) if hours else None

    dna = {
        "has_memory": True,
        "total_events": len(all_events),
        "total_earned_usd": round(total_usd, 2),
        "completion_rate_pct": completion_rate,
        "best_platform": best_platform,
        "best_skill": best_skill,
        "platform_breakdown": dict(sorted(platforms.items(), key=lambda x: x[1], reverse=True)[:5]),
        "skill_breakdown": dict(sorted(skills.items(), key=lambda x: x[1], reverse=True)[:5]),
        "peak_productivity_hour": best_hour,
        "tasks_completed": len(completed),
        "tasks_abandoned": len(abandoned),
        "recent_events": all_events[:10],
    }
    return dna


@router.get("/insights")
@limiter.limit(AI_LIMIT)
async def get_ai_insights(request: Request, user: dict = Depends(get_current_user)):
    """AI analyzes memory and gives personalized income intelligence"""
    user_id = user["id"]
    sb = supabase_service.client

    events = sb.table("income_memory_events").select("*").eq(
        "user_id", user_id).order("created_at", desc=True).limit(100).execute()
    all_events = events.data or []

    profile = await supabase_service.get_profile(user_id) or {}

    if len(all_events) < 3:
        return {"insights": "Complete at least 3 income tasks to unlock your personalized insights.", "ready": False}

    summary = f"""User income history ({len(all_events)} events):
Total earned: ${sum(e.get('amount_usd',0) for e in all_events):.2f}
Completed: {len([e for e in all_events if e.get('outcome')=='success'])}
Abandoned: {len([e for e in all_events if e.get('outcome')=='failure'])}
Top platforms: {list(set(e.get('platform','') for e in all_events if e.get('platform')))[:5]}
Top skills used: {list(set(e.get('skill_used','') for e in all_events if e.get('skill_used')))[:5]}
Recent: {[e.get('title','') for e in all_events[:5]]}
Country: {profile.get('country','NG')} | Stage: {profile.get('stage','survival')}"""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": summary}],
        system="""You are RiseUp's Income Memory AI. You analyze a user's income history and give deeply personal insights.

You see patterns others miss:
- What they're best at vs what they avoid
- When they earn most vs when they quit
- Which platforms work for them vs drain them
- The gap between their potential and their output

Give insights in JSON:
{
  "personality_type": "The user's income personality in 3 words",
  "superpower": "Their single biggest proven strength",
  "blind_spot": "What they're avoiding that could unlock growth",
  "pattern_alert": "A pattern in their history they may not see",
  "next_unlock": "The single action that would most improve their income",
  "past_wins_to_repeat": "What worked that they should do more of",
  "encouragement": "Specific, data-backed belief in their potential",
  "weekly_focus": "The ONE thing to focus on this week based on their data"
}
Return ONLY valid JSON.""",
        max_tokens=800,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        insights = json.loads(raw)
    except Exception:
        insights = {"encouragement": result["content"]}

    return {"insights": insights, "ready": True, "events_analyzed": len(all_events)}


@router.get("/streak-patterns")
@limiter.limit(GENERAL_LIMIT)
async def streak_patterns(request: Request, user: dict = Depends(get_current_user)):
    """Analyze when the user is most productive and earns most"""
    user_id = user["id"]
    events = supabase_service.client.table("income_memory_events").select(
        "created_at,amount_usd,outcome"
    ).eq("user_id", user_id).execute()

    all_events = events.data or []
    if not all_events:
        return {"patterns": []}

    by_day = {}
    for e in all_events:
        dt = datetime.fromisoformat(e["created_at"].replace("Z", "+00:00"))
        day = dt.strftime("%A")
        if day not in by_day:
            by_day[day] = {"count": 0, "earned": 0, "completed": 0}
        by_day[day]["count"] += 1
        by_day[day]["earned"] += e.get("amount_usd", 0) or 0
        if e.get("outcome") == "success":
            by_day[day]["completed"] += 1

    patterns = [{"day": d, **stats} for d, stats in by_day.items()]
    best_day = max(patterns, key=lambda x: x["earned"]) if patterns else None

    return {
        "patterns": patterns,
        "best_earning_day": best_day["day"] if best_day else None,
        "recommendation": f"You earn most on {best_day['day']}s — schedule your best income tasks then." if best_day else None
    }
