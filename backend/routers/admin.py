"""Admin Router — Protected dashboard for ChAs Tech Group internal use only"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from config import settings
from services.supabase_service import supabase_service

router = APIRouter(prefix="/admin", tags=["Admin"])
logger = logging.getLogger(__name__)


def require_admin(x_admin_key: Optional[str] = Header(None)):
    """Simple API-key-based admin auth — not exposed to public clients"""
    admin_key = getattr(settings, "ADMIN_SECRET_KEY", None)
    if not admin_key or x_admin_key != admin_key:
        raise HTTPException(403, "Admin access denied")
    return True


@router.get("/stats")
async def get_admin_stats(_: bool = Depends(require_admin)):
    """Overall platform statistics"""
    db = supabase_service.db

    # User counts
    total_users     = db.table("profiles").select("id", count="exact").execute().count or 0
    premium_users   = db.table("profiles").select("id", count="exact").eq("subscription_tier", "premium").execute().count or 0
    onboarded       = db.table("profiles").select("id", count="exact").eq("onboarding_completed", True).execute().count or 0

    # Last 7 days signups
    week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
    new_this_week = db.table("profiles").select("id", count="exact").gte("created_at", week_ago).execute().count or 0

    # Revenue
    payments = db.table("payments").select("amount, currency, status, created_at").eq("status", "successful").execute().data or []
    total_revenue_ngn = sum(float(p["amount"]) for p in payments if p.get("currency") == "NGN")
    total_revenue_usd = sum(float(p["amount"]) for p in payments if p.get("currency") == "USD")

    # AI usage
    total_messages = db.table("messages").select("id", count="exact").execute().count or 0
    ai_models_used = db.table("messages").select("ai_model").not_.is_("ai_model", "null").execute().data or []
    from collections import Counter
    model_counts = dict(Counter(m["ai_model"] for m in ai_models_used if m.get("ai_model")))

    # Tasks
    total_tasks     = db.table("tasks").select("id", count="exact").execute().count or 0
    completed_tasks = db.table("tasks").select("id", count="exact").eq("status", "completed").execute().count or 0

    # Earnings
    earnings_res = db.table("earnings").select("amount").execute().data or []
    total_logged_earnings = sum(float(e["amount"]) for e in earnings_res)

    # Referrals
    total_referrals = db.table("referrals").select("id", count="exact").execute().count or 0

    # Streaks
    active_streaks = db.table("user_streaks").select("id", count="exact").gte("current_streak", 3).execute().count or 0

    return {
        "users": {
            "total":         total_users,
            "premium":       premium_users,
            "onboarded":     onboarded,
            "new_this_week": new_this_week,
            "conversion_rate": f"{round(premium_users / max(total_users,1) * 100, 1)}%",
        },
        "revenue": {
            "total_payments":     len(payments),
            "total_ngn":          total_revenue_ngn,
            "total_usd":          total_revenue_usd,
        },
        "ai": {
            "total_messages": total_messages,
            "model_usage":    model_counts,
        },
        "tasks": {
            "total":     total_tasks,
            "completed": completed_tasks,
            "completion_rate": f"{round(completed_tasks / max(total_tasks,1) * 100, 1)}%",
        },
        "earnings_logged": total_logged_earnings,
        "referrals":       total_referrals,
        "active_streaks":  active_streaks,
        "generated_at":    datetime.now(timezone.utc).isoformat(),
    }


@router.get("/users")
async def list_users(
    limit: int = 50,
    offset: int = 0,
    stage: Optional[str] = None,
    tier: Optional[str] = None,
    _: bool = Depends(require_admin),
):
    """List users with filters"""
    q = supabase_service.db.table("profiles").select(
        "id, email, full_name, country, stage, subscription_tier, onboarding_completed, "
        "total_earned, current_streak, created_at"
    )
    if stage:
        q = q.eq("stage", stage)
    if tier:
        q = q.eq("subscription_tier", tier)

    res = q.order("created_at", desc=True).range(offset, offset + limit - 1).execute()
    return {"users": res.data or [], "limit": limit, "offset": offset}


@router.get("/users/{user_id}")
async def get_user_detail(user_id: str, _: bool = Depends(require_admin)):
    """Get full user profile + stats for admin review"""
    profile = await supabase_service.get_profile(user_id)
    if not profile:
        raise HTTPException(404, "User not found")

    stats = await supabase_service.get_user_stats(user_id)
    earnings = await supabase_service.get_earnings_summary(user_id)

    return {
        "profile":  profile,
        "stats":    stats,
        "earnings": earnings,
    }


@router.post("/users/{user_id}/grant-premium")
async def grant_premium(
    user_id: str, days: int = 30, _: bool = Depends(require_admin)
):
    """Manually grant premium to a user"""
    from datetime import datetime, timezone, timedelta
    expires = (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()
    await supabase_service.update_profile(user_id, {
        "subscription_tier":       "premium",
        "subscription_expires_at": expires,
    })
    logger.info(f"Admin granted {days}d premium to user {user_id}")
    return {"success": True, "expires_at": expires, "days_granted": days}


@router.delete("/users/{user_id}")
async def delete_user(user_id: str, _: bool = Depends(require_admin)):
    """Delete a user account (GDPR compliance)"""
    # Supabase cascades delete to all child tables via FK constraints
    supabase_service.db.table("profiles").delete().eq("id", user_id).execute()
    logger.warning(f"Admin deleted user {user_id}")
    return {"success": True, "message": f"User {user_id} deleted"}


@router.get("/payments")
async def list_payments(
    status: Optional[str] = "successful",
    limit: int = 50,
    _: bool = Depends(require_admin),
):
    """List payment records"""
    q = supabase_service.db.table("payments").select(
        "*, profiles(full_name, email, country)"
    )
    if status:
        q = q.eq("status", status)
    res = q.order("created_at", desc=True).limit(limit).execute()
    return {"payments": res.data or []}


@router.post("/broadcast")
async def broadcast_notification(
    title: str,
    body: str,
    stage: Optional[str] = None,
    _: bool = Depends(require_admin),
):
    """Broadcast a push notification to all users or a stage segment"""
    from routers.notifications import send_push_to_user

    q = supabase_service.db.table("profiles").select("id")
    if stage:
        q = q.eq("stage", stage)
    users = q.execute().data or []

    sent = 0
    for u in users:
        success = await send_push_to_user(u["id"], title, body, "system")
        if success:
            sent += 1

    logger.info(f"Admin broadcast sent to {sent}/{len(users)} users")
    return {"sent": sent, "total": len(users)}
