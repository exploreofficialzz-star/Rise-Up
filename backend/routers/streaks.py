"""Streaks Router — Daily check-ins, streak tracking, XP & level system"""
import logging
from datetime import datetime, timezone, date

from fastapi import APIRouter, Depends, HTTPException, Request
from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/streaks", tags=["Streaks"])
logger = logging.getLogger(__name__)


@router.post("/check-in")
@limiter.limit("5/minute")
async def daily_check_in(request: Request, user: dict = Depends(get_current_user)):
    """Process daily check-in — updates streak, awards XP, triggers achievement checks"""
    user_id = user["id"]

    # Call the RPC function which handles all streak logic atomically
    result = supabase_service.db.rpc("process_daily_checkin", {"uid": user_id}).execute()
    data = result.data

    if not data:
        raise HTTPException(500, "Check-in failed")

    current_streak = data.get("current_streak", 0)
    already_done   = data.get("already_checked_in", False)

    # Check and unlock streak-based achievements
    achievements_unlocked = []
    if not already_done:
        streak_milestones = {3: "streak_3", 7: "streak_7", 14: "streak_14", 30: "streak_30", 100: "streak_100"}
        for threshold, key in streak_milestones.items():
            if current_streak == threshold:
                ach = supabase_service.db.rpc("unlock_achievement", {
                    "uid": user_id, "ach_key": key
                }).execute()
                if ach.data and ach.data.get("success"):
                    achievements_unlocked.append(ach.data.get("achievement"))

    return {
        "already_checked_in": already_done,
        "current_streak": current_streak,
        "longest_streak": data.get("longest_streak", 0),
        "is_new_record": data.get("is_new_record", False),
        "xp_earned": 0 if already_done else data.get("xp_earned", 10),
        "achievements_unlocked": achievements_unlocked,
        "message": (
            "Already checked in today! Come back tomorrow 💪" if already_done
            else f"🔥 Day {current_streak} streak! Keep going!"
        ),
    }


@router.get("/")
async def get_streak(user: dict = Depends(get_current_user)):
    """Get current streak info for the user"""
    user_id = user["id"]

    # Get or create streak record
    supabase_service.db.table("user_streaks").upsert(
        {"user_id": user_id}, on_conflict="user_id"
    ).execute()

    res = supabase_service.db.table("user_streaks").select("*").eq("user_id", user_id).single().execute()
    streak = res.data or {}

    # Get profile for XP and level
    profile = await supabase_service.get_profile(user_id)

    today = date.today()
    last_ci = streak.get("last_check_in")
    checked_in_today = last_ci == str(today) if last_ci else False

    return {
        "current_streak":    streak.get("current_streak", 0),
        "longest_streak":    streak.get("longest_streak", 0),
        "total_check_ins":   streak.get("total_check_ins", 0),
        "last_check_in":     last_ci,
        "checked_in_today":  checked_in_today,
        "xp_points":         profile.get("xp_points", 0) if profile else 0,
        "level":             profile.get("level", 1) if profile else 1,
        "xp_to_next_level":  500 - ((profile.get("xp_points", 0) if profile else 0) % 500),
        "recent_dates":      streak.get("check_in_dates", [])[-30:],  # last 30 days
    }
