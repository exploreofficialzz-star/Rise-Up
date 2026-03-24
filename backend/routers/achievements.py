"""Achievements Router — Badge system, XP, levels, automatic unlock checks"""
import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/achievements", tags=["Achievements"])
logger = logging.getLogger(__name__)


@router.get("/")
async def get_all_achievements(user: dict = Depends(get_current_user)):
    """Get all achievement definitions + user's unlocked ones"""
    user_id = user["id"]

    # All achievements
    all_ach = supabase_service.db.table("achievements").select("*").order("category").execute()
    achievements = all_ach.data or []

    # User's unlocked achievements
    unlocked_res = (
        supabase_service.db.table("user_achievements")
        .select("achievement_id, unlocked_at")
        .eq("user_id", user_id)
        .execute()
    )
    unlocked_ids = {u["achievement_id"]: u["unlocked_at"] for u in (unlocked_res.data or [])}

    # Merge
    for a in achievements:
        a["unlocked"] = a["id"] in unlocked_ids
        a["unlocked_at"] = unlocked_ids.get(a["id"])

    # Group by category
    categories = {}
    for a in achievements:
        cat = a["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(a)

    profile = await supabase_service.get_profile(user_id)

    return {
        "achievements": achievements,
        "by_category":  categories,
        "unlocked_count": len(unlocked_ids),
        "total_count":    len(achievements),
        "xp_points":      profile.get("xp_points", 0) if profile else 0,
        "level":          profile.get("level", 1) if profile else 1,
    }


@router.get("/my")
async def get_my_achievements(user: dict = Depends(get_current_user)):
    """Get user's unlocked achievements, sorted by most recent"""
    res = (
        supabase_service.db.table("user_achievements")
        .select("*, achievements(*)")
        .eq("user_id", user["id"])
        .order("unlocked_at", desc=True)
        .execute()
    )
    return {"achievements": res.data or []}


@router.post("/check")
@limiter.limit(GENERAL_LIMIT)
async def check_achievements(request: Request, user: dict = Depends(get_current_user)):
    """Run a full achievement check for the user based on current stats.
    Call this after major actions (task complete, earning logged, etc.)"""
    user_id = user["id"]
    newly_unlocked = []

    # Gather stats
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        return {"newly_unlocked": []}

    tasks = await supabase_service.get_tasks(user_id)
    enrollments = await supabase_service.get_enrollments(user_id)
    referrals_res = supabase_service.db.table("referrals").select("id").eq("referrer_id", user_id).eq("status", "rewarded").execute()
    posts_res = supabase_service.db.table("community_posts").select("id", count="exact").eq("user_id", user_id).execute()
    goals_res = supabase_service.db.table("goals").select("id", count="exact").eq("user_id", user_id).eq("status", "completed").execute()

    completed_tasks   = len([t for t in tasks if t.get("status") == "completed"])
    completed_skills  = len([e for e in enrollments if e.get("status") == "completed"])
    enrolled_skills   = len(enrollments)
    referral_count    = len(referrals_res.data or [])
    post_count        = posts_res.count or 0
    goals_completed   = goals_res.count or 0
    goals_count_res   = supabase_service.db.table("goals").select("id", count="exact").eq("user_id", user_id).execute()
    goals_count       = goals_count_res.count or 0
    total_earned      = float(profile.get("total_earned") or 0)
    current_streak    = profile.get("current_streak", 0)
    level             = profile.get("level", 1)
    is_premium        = profile.get("subscription_tier") == "premium"

    # Define checks: (achievement_key, condition)
    checks = [
        ("onboarding_done",  profile.get("onboarding_completed")),
        ("first_task",       completed_tasks >= 1),
        ("tasks_5",          completed_tasks >= 5),
        ("tasks_10",         completed_tasks >= 10),
        ("tasks_25",         completed_tasks >= 25),
        ("first_earning",    total_earned >= 1),
        ("earned_10k_ngn",   total_earned >= 10000),
        ("earned_50k_ngn",   total_earned >= 50000),
        ("earned_100k_ngn",  total_earned >= 100000),
        ("earned_500k_ngn",  total_earned >= 500000),
        ("streak_3",         current_streak >= 3),
        ("streak_7",         current_streak >= 7),
        ("streak_14",        current_streak >= 14),
        ("streak_30",        current_streak >= 30),
        ("streak_100",       current_streak >= 100),
        ("first_skill",      enrolled_skills >= 1),
        ("skill_complete",   completed_skills >= 1),
        ("skills_3",         completed_skills >= 3),
        ("first_post",       post_count >= 1),
        ("first_referral",   referral_count >= 1),
        ("referrals_5",      referral_count >= 5),
        ("went_premium",     is_premium),
        ("first_goal",       goals_count >= 1),
        ("goal_complete",    goals_completed >= 1),
        ("level_5",          level >= 5),
        ("level_10",         level >= 10),
    ]

    for key, condition in checks:
        if condition:
            try:
                result = supabase_service.db.rpc("unlock_achievement", {
                    "uid": user_id, "ach_key": key
                }).execute()
                if result.data and result.data.get("success"):
                    newly_unlocked.append(result.data.get("achievement"))
            except Exception as e:
                logger.warning(f"Achievement check error for {key}: {e}")

    return {
        "newly_unlocked": [a for a in newly_unlocked if a],
        "count": len([a for a in newly_unlocked if a]),
    }
