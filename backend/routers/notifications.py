# backend/routers/notifications.py
"""
Notifications Router v2.0 — FCM token management, push notifications,
in-app notification feed, unread count badge.

v2.0 additions:
  • GET  /notifications/unread-count  — badge count for app bar bell icon
  • POST /notifications/mark-read     — accepts both notification_ids + ids fields
  • All endpoints return proper data for RiseUp frontend
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
    # Accept both field names for forward + backward compat
    notification_ids: Optional[list] = None
    ids:              Optional[list] = None   # v2.0 alias


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
    try:
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
    except Exception as e:
        logger.warning("register_fcm_token failed: user=%s | %s", user.get("id"), e)
        # Non-fatal — still return 200 so client doesn't retry-loop
        return {"success": False, "message": str(e)}


@router.delete("/unregister-token")
async def unregister_fcm_token(
    token: str,
    user: dict = Depends(get_current_user),
):
    """Deactivate a FCM token on logout or unsubscribe."""
    try:
        supabase_service.client.table("fcm_tokens").update(
            {"is_active": False}
        ).eq("user_id", user["id"]).eq("token", token).execute()
        return {"success": True}
    except Exception as e:
        logger.warning("unregister_fcm_token failed: user=%s | %s", user.get("id"), e)
        return {"success": False}


# ─────────────────────────────────────────────────────────────
# In-App Notification Feed
# ─────────────────────────────────────────────────────────────

@router.get("/")
async def list_notifications(
    limit: int = 30,
    user: dict = Depends(get_current_user),
):
    """Get user's in-app notification history."""
    try:
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
    except Exception as e:
        logger.exception("list_notifications failed: user=%s", user.get("id"))
        raise HTTPException(500, str(e))


# v2.0: Dedicated unread count endpoint (used by AppBar bell badge)
@router.get("/unread-count")
async def get_unread_count(user: dict = Depends(get_current_user)):
    """
    Lightweight endpoint — just returns the unread notification count.
    Called every 30 seconds by HomeScreen for the bell badge.
    """
    try:
        res = (
            supabase_service.client.table("notifications")
            .select("id", count="exact")
            .eq("user_id", user["id"])
            .eq("is_read", False)
            .execute()
        )
        count = res.count or 0
        return {"count": count}
    except Exception as e:
        logger.warning("get_unread_count failed: user=%s | %s", user.get("id"), e)
        return {"count": 0}   # always 200 — don't break the badge


@router.post("/mark-read")
async def mark_notifications_read(
    req: MarkReadRequest,
    user: dict = Depends(get_current_user),
):
    """
    Mark one, many, or all notifications as read.
    Accepts notification_ids (legacy) or ids (v2.0 alias).
    If neither provided → mark ALL as read.
    """
    try:
        # Merge both field names
        ids_to_mark = req.notification_ids or req.ids or None

        q = (
            supabase_service.client.table("notifications")
            .update({"is_read": True})
            .eq("user_id", user["id"])
        )
        if ids_to_mark:
            q = q.in_("id", ids_to_mark)
        q.execute()
        return {"success": True}
    except Exception as e:
        logger.warning("mark_notifications_read failed: user=%s | %s", user.get("id"), e)
        return {"success": False}


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
    try:
        profile = await supabase_service.get_profile(user["id"])
        name    = ((profile.get("full_name") or "Champion").split()[0] if profile else "Champion")
        streak  = profile.get("current_streak", 0) if profile else 0
        await notification_service.send_streak_reminder(user_id=user["id"], name=name, streak=streak)
        return {"sent": True}
    except Exception as e:
        logger.warning("send_streak_reminder failed: user=%s | %s", user.get("id"), e)
        return {"sent": False}


@router.post("/send-task-reminder")
@limiter.limit("10/minute")
async def send_task_reminder(
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Trigger a task reminder for the calling user."""
    try:
        profile = await supabase_service.get_profile(user["id"])
        name    = ((profile.get("full_name") or "Champion").split()[0] if profile else "Champion")
        await notification_service.send_task_reminder(user_id=user["id"], name=name)
        return {"sent": True}
    except Exception as e:
        logger.warning("send_task_reminder failed: user=%s | %s", user.get("id"), e)
        return {"sent": False}


# ─────────────────────────────────────────────────────────────
# Admin Send Endpoint
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
    """
    try:
        delivered = await send_push_to_user(
            user_id    = req.user_id,
            title      = req.title,
            body       = req.body,
            notif_type = req.notif_type,
            data       = req.data,
        )
        return {"success": True, "fcm_delivered": delivered}
    except Exception as e:
        logger.exception("send_notification failed: user=%s | %s", user.get("id"), e)
        raise HTTPException(500, str(e))
