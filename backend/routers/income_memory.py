"""
backend/routers/income_memory.py
RiseUp Income Memory Engine — Production v1.1

v1.1 fixes:
  • Router prefix changed: /memory → /income_memory
    (Flutter calls /api/v1/income_memory/... — this aligns the backend)
  • Added GET /income_memory/summary endpoint (was 404)
  • Null guards on all .execute() calls
  • All existing endpoints preserved under the new prefix
"""
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

# ── IMPORTANT: prefix is now /income_memory to match Flutter calls ────────────
router = APIRouter(prefix="/income_memory", tags=["Income Memory"])
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def _safe_data(result: Any) -> list:
    """Null-safe accessor for Supabase execute() results."""
    if result is None:
        return []
    data = getattr(result, "data", None)
    return data if isinstance(data, list) else []


# ─────────────────────────────────────────────────────────────────────────────
# MODELS
# ─────────────────────────────────────────────────────────────────────────────

class MemoryEventRequest(BaseModel):
    event_type: str          # task_completed | task_abandoned | income_earned |
                             # client_won | client_lost | skill_learned | obstacle_hit
    title: str
    amount_usd:          Optional[float] = 0
    platform:            Optional[str]   = None
    skill_used:          Optional[str]   = None
    time_taken_minutes:  Optional[int]   = None
    note:                Optional[str]   = None
    outcome:             Optional[str]   = None   # success | failure | partial


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY — new endpoint that was returning 404
# GET /income_memory/summary
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/summary")
@limiter.limit(GENERAL_LIMIT)
async def get_income_summary(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """
    Returns a lightweight summary of the user's income memory:
    total earned, completion rate, best platform, best skill,
    and last 5 events — designed for quick home-screen display.
    """
    user_id = user["id"]
    sb      = supabase_service.client

    try:
        result = (
            sb.table("income_memory_events")
            .select("event_type,amount_usd,platform,skill_used,outcome,created_at,title")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(200)
            .execute()
        )
        all_events = _safe_data(result)
    except Exception as e:
        logger.error("get_income_summary fetch: %s", e)
        all_events = []

    if not all_events:
        return {
            "has_memory":          False,
            "total_earned_usd":    0,
            "tasks_completed":     0,
            "tasks_abandoned":     0,
            "completion_rate_pct": 0,
            "best_platform":       None,
            "best_skill":          None,
            "recent_events":       [],
            "message":             "No income events recorded yet.",
        }

    completed = [e for e in all_events if e.get("outcome") == "success"]
    abandoned = [e for e in all_events if e.get("outcome") == "failure"]
    earned    = [e for e in all_events if (e.get("amount_usd") or 0) > 0]

    total_usd = sum(e.get("amount_usd", 0) or 0 for e in earned)

    platforms: dict = {}
    skills:    dict = {}
    for e in completed:
        if e.get("platform"):
            platforms[e["platform"]] = platforms.get(e["platform"], 0) + 1
        if e.get("skill_used"):
            skills[e["skill_used"]] = skills.get(e["skill_used"], 0) + 1

    best_platform = max(platforms, key=platforms.get) if platforms else None
    best_skill    = max(skills,    key=skills.get)    if skills    else None
    completion_rate = (
        round(len(completed) / len(all_events) * 100) if all_events else 0
    )

    return {
        "has_memory":          True,
        "total_earned_usd":    round(total_usd, 2),
        "tasks_completed":     len(completed),
        "tasks_abandoned":     len(abandoned),
        "total_events":        len(all_events),
        "completion_rate_pct": completion_rate,
        "best_platform":       best_platform,
        "best_skill":          best_skill,
        "recent_events":       all_events[:5],
    }


# ─────────────────────────────────────────────────────────────────────────────
# RECORD EVENT
# POST /income_memory/event
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/event")
@limiter.limit(GENERAL_LIMIT)
async def record_event(
    req:     MemoryEventRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """Record any income-related event to memory."""
    user_id = user["id"]
    try:
        supabase_service.client.table("income_memory_events").insert({
            "user_id":              user_id,
            "event_type":           req.event_type,
            "title":                req.title,
            "amount_usd":           req.amount_usd or 0,
            "platform":             req.platform,
            "skill_used":           req.skill_used,
            "time_taken_minutes":   req.time_taken_minutes,
            "note":                 req.note,
            "outcome":              req.outcome or "success",
        }).execute()
        return {"recorded": True, "event": req.event_type}
    except Exception as e:
        raise HTTPException(500, str(e))


# ─────────────────────────────────────────────────────────────────────────────
# FULL PROFILE
# GET /income_memory/profile
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/profile")
@limiter.limit(GENERAL_LIMIT)
async def get_memory_profile(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """Full income DNA profile derived from memory."""
    user_id = user["id"]
    sb      = supabase_service.client

    try:
        result     = (
            sb.table("income_memory_events")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(200)
            .execute()
        )
        all_events = _safe_data(result)
    except Exception as e:
        logger.error("get_memory_profile: %s", e)
        all_events = []

    if not all_events:
        return {
            "has_memory": False,
            "message":    "No income events recorded yet. Complete tasks to build your memory profile.",
        }

    completed     = [e for e in all_events if e.get("outcome") == "success"]
    abandoned     = [e for e in all_events if e.get("outcome") == "failure"]
    earned_events = [e for e in all_events if (e.get("amount_usd") or 0) > 0]

    total_usd = sum(e.get("amount_usd", 0) or 0 for e in earned_events)

    platforms: dict = {}
    skills:    dict = {}
    for e in completed:
        if e.get("platform"):
            platforms[e["platform"]] = platforms.get(e["platform"], 0) + 1
        if e.get("skill_used"):
            skills[e["skill_used"]] = skills.get(e["skill_used"], 0) + 1

    best_platform   = max(platforms, key=platforms.get) if platforms else None
    best_skill      = max(skills,    key=skills.get)    if skills    else None
    completion_rate = round(len(completed) / len(all_events) * 100) if all_events else 0

    hours = [
        datetime.fromisoformat(e["created_at"].replace("Z", "+00:00")).hour
        for e in completed
        if e.get("created_at")
    ]
    best_hour = max(set(hours), key=hours.count) if hours else None

    return {
        "has_memory":               True,
        "total_events":             len(all_events),
        "total_earned_usd":         round(total_usd, 2),
        "completion_rate_pct":      completion_rate,
        "best_platform":            best_platform,
        "best_skill":               best_skill,
        "platform_breakdown":       dict(sorted(platforms.items(), key=lambda x: x[1], reverse=True)[:5]),
        "skill_breakdown":          dict(sorted(skills.items(),    key=lambda x: x[1], reverse=True)[:5]),
        "peak_productivity_hour":   best_hour,
        "tasks_completed":          len(completed),
        "tasks_abandoned":          len(abandoned),
        "recent_events":            all_events[:10],
    }


# ─────────────────────────────────────────────────────────────────────────────
# AI INSIGHTS
# GET /income_memory/insights
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/insights")
@limiter.limit(AI_LIMIT)
async def get_ai_insights(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """AI analyses memory and gives personalised income intelligence."""
    user_id = user["id"]
    sb      = supabase_service.client

    try:
        result     = (
            sb.table("income_memory_events")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(100)
            .execute()
        )
        all_events = _safe_data(result)
    except Exception as e:
        logger.error("get_ai_insights: %s", e)
        all_events = []

    profile = await supabase_service.get_profile(user_id) or {}

    if len(all_events) < 3:
        return {
            "insights": "Complete at least 3 income tasks to unlock your personalised insights.",
            "ready":    False,
        }

    summary = (
        f"User income history ({len(all_events)} events):\n"
        f"Total earned: ${sum(e.get('amount_usd', 0) or 0 for e in all_events):.2f}\n"
        f"Completed: {len([e for e in all_events if e.get('outcome') == 'success'])}\n"
        f"Abandoned: {len([e for e in all_events if e.get('outcome') == 'failure'])}\n"
        f"Top platforms: {list(set(e.get('platform', '') for e in all_events if e.get('platform')))[:5]}\n"
        f"Top skills: {list(set(e.get('skill_used', '') for e in all_events if e.get('skill_used')))[:5]}\n"
        f"Recent: {[e.get('title', '') for e in all_events[:5]]}\n"
        f"Country: {profile.get('country', 'NG')} | Stage: {profile.get('stage', 'survival')}"
    )

    result = await ai_service.chat(
        messages=[{"role": "user", "content": summary}],
        system="""You are RiseUp's Income Memory AI. Analyse the user's income history and give deeply personal insights.

Return ONLY valid JSON — no preamble, no markdown fences:
{
  "personality_type": "Income personality in 3 words",
  "superpower": "Single biggest proven strength",
  "blind_spot": "What they're avoiding that could unlock growth",
  "pattern_alert": "A pattern they may not see",
  "next_unlock": "Single action that would most improve income",
  "past_wins_to_repeat": "What worked that they should do more of",
  "encouragement": "Specific data-backed belief in their potential",
  "weekly_focus": "ONE thing to focus on this week"
}""",
        max_tokens=800,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        insights = json.loads(raw)
    except Exception:
        insights = {"encouragement": result["content"]}

    return {"insights": insights, "ready": True, "events_analyzed": len(all_events)}


# ─────────────────────────────────────────────────────────────────────────────
# STREAK PATTERNS
# GET /income_memory/streak-patterns
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/streak-patterns")
@limiter.limit(GENERAL_LIMIT)
async def streak_patterns(
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """Analyse when the user is most productive and earns most."""
    user_id = user["id"]

    try:
        result = (
            supabase_service.client
            .table("income_memory_events")
            .select("created_at,amount_usd,outcome")
            .eq("user_id", user_id)
            .execute()
        )
        all_events = _safe_data(result)
    except Exception as e:
        logger.error("streak_patterns: %s", e)
        all_events = []

    if not all_events:
        return {"patterns": []}

    by_day: dict = {}
    for e in all_events:
        try:
            dt  = datetime.fromisoformat(e["created_at"].replace("Z", "+00:00"))
            day = dt.strftime("%A")
        except Exception:
            continue

        if day not in by_day:
            by_day[day] = {"count": 0, "earned": 0, "completed": 0}
        by_day[day]["count"]  += 1
        by_day[day]["earned"] += e.get("amount_usd", 0) or 0
        if e.get("outcome") == "success":
            by_day[day]["completed"] += 1

    patterns = [{"day": d, **stats} for d, stats in by_day.items()]
    best_day = max(patterns, key=lambda x: x["earned"]) if patterns else None

    return {
        "patterns":          patterns,
        "best_earning_day":  best_day["day"] if best_day else None,
        "recommendation": (
            f"You earn most on {best_day['day']}s — schedule your best income tasks then."
            if best_day else None
        ),
    }
