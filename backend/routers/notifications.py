"""
Notifications Router — FCM token registration, push notifications, in-app notification feed.
send_push_to_user lives in notification_service so all routers share one implementation.
"""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from services.notification_service import notification_service, send_push_to_user
from utils.auth import get_current_user

router = APIRouter(prefix="/notifications", tags=["Notifications"])
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# Pydantic Models
# ─────────────────────────────────────────────────────────────

class FCMTokenRequest(BaseModel):
    token: str
    platform: str = "android"   # android | ios | web


class SendNotificationRequest(BaseModel):
    user_id:    str
    title:      str
    body:       str
    notif_type: str = "system"
    data:       Optional[dict] = None


class MarkReadRequest(BaseModel):
    notification_ids: Optional[list] = None   # None = mark all


# ─────────────────────────────────────────────────────────────
# FCM Token Management
# ─────────────────────────────────────────────────────────────

@router.post("/register-token")
@limiter.limit(GENERAL_LIMIT)
async def register_fcm_token(
    req: FCMTokenRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Register or update a device FCM push token."""
    supabase_service.client.table("fcm_tokens").upsert(
        {
            "user_id":   user["id"],
            "token":     req.token,
            "platform":  req.platform,
            "is_active": True,
        },
        on_conflict="user_id,token",
    ).execute()
    return {"success": True, "message": "Push notifications enabled"}


@router.delete("/unregister-token")
async def unregister_fcm_token(
    token: str,
    user: dict = Depends(get_current_user),
):
    """Deactivate a FCM token on logout or unsubscribe."""
    supabase_service.client.table("fcm_tokens").update(
        {"is_active": False}
    ).eq("user_id", user["id"]).eq("token", token).execute()
    return {"success": True}


# ─────────────────────────────────────────────────────────────
# In-App Notification Feed
# ─────────────────────────────────────────────────────────────

@router.get("/")
async def list_notifications(
    limit: int = 30,
    user: dict = Depends(get_current_user),
):
    """Get user's in-app notification history."""
    res = (
        supabase_service.client.table("notifications")
        .select("*")
        .eq("user_id", user["id"])
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    notifications = res.data or []
    unread_count = sum(1 for n in notifications if not n.get("is_read"))

    return {
        "notifications": notifications,
        "unread_count":  unread_count,
    }


@router.post("/mark-read")
async def mark_notifications_read(
    req: MarkReadRequest,
    user: dict = Depends(get_current_user),
):
    """Mark one, many, or all notifications as read."""
    q = (
        supabase_service.client.table("notifications")
        .update({"is_read": True})
        .eq("user_id", user["id"])
    )
    if req.notification_ids:
        q = q.in_("id", req.notification_ids)
    q.execute()
    return {"success": True}


# ─────────────────────────────────────────────────────────────
# Manual / Cron Trigger Endpoints
# ─────────────────────────────────────────────────────────────

@router.post("/send-streak-reminder")
@limiter.limit("10/minute")
async def send_streak_reminder(
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Trigger a streak reminder for the calling user."""
    profile = await supabase_service.get_profile(user["id"])
    name = (
        (profile.get("full_name") or "Champion").split()[0]
        if profile
        else "Champion"
    )
    streak = profile.get("current_streak", 0) if profile else 0

    await notification_service.send_streak_reminder(
        user_id=user["id"],
        name=name,
        streak=streak,
    )
    return {"sent": True}


@router.post("/send-task-reminder")
@limiter.limit("10/minute")
async def send_task_reminder(
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Trigger a task reminder for the calling user."""
    profile = await supabase_service.get_profile(user["id"])
    name = (
        (profile.get("full_name") or "Champion").split()[0]
        if profile
        else "Champion"
    )

    await notification_service.send_task_reminder(
        user_id=user["id"],
        name=name,
    )
    return {"sent": True}


# ─────────────────────────────────────────────────────────────
# Admin Send Endpoint (internal use)
# ─────────────────────────────────────────────────────────────

@router.post("/send")
@limiter.limit("20/minute")
async def send_notification(
    req: SendNotificationRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Admin / server-side endpoint to push a notification to any user.
    Requires the caller to be authenticated (add admin guard if needed).
    """
    delivered = await send_push_to_user(
        user_id=req.user_id,
        title=req.title,
        body=req.body,
        notif_type=req.notif_type,
        data=req.data,
    )
    return {"success": True, "fcm_delivered": delivered}
