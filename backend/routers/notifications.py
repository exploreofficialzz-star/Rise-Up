"""Notifications Router — FCM token registration, push notifications, in-app notification feed"""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from config import settings
from utils.auth import get_current_user

router = APIRouter(prefix="/notifications", tags=["Notifications"])
logger = logging.getLogger(__name__)


class FCMTokenRequest(BaseModel):
    token: str
    platform: str = "android"   # android | ios | web


class SendNotificationRequest(BaseModel):
    user_id:     str
    title:       str
    body:        str
    notif_type:  str = "system"
    data:        Optional[dict] = None


class MarkReadRequest(BaseModel):
    notification_ids: Optional[list] = None  # None = mark all


# ── FCM Token Management ─────────────────────────────────────

@router.post("/register-token")
@limiter.limit(GENERAL_LIMIT)
async def register_fcm_token(
    req: FCMTokenRequest, request: Request, user: dict = Depends(get_current_user)
):
    """Register or update a device FCM push token"""
    supabase_service.db.table("fcm_tokens").upsert({
        "user_id":   user["id"],
        "token":     req.token,
        "platform":  req.platform,
        "is_active": True,
    }, on_conflict="user_id,token").execute()

    return {"success": True, "message": "Push notifications enabled"}


@router.delete("/unregister-token")
async def unregister_fcm_token(token: str, user: dict = Depends(get_current_user)):
    """Deactivate a FCM token (logout or unsubscribe)"""
    supabase_service.db.table("fcm_tokens").update({"is_active": False}).eq(
        "user_id", user["id"]
    ).eq("token", token).execute()
    return {"success": True}


# ── In-App Notifications ─────────────────────────────────────

@router.get("/")
async def list_notifications(limit: int = 30, user: dict = Depends(get_current_user)):
    """Get user's in-app notification history"""
    res = (
        supabase_service.db.table("notifications")
        .select("*")
        .eq("user_id", user["id"])
        .order("sent_at", desc=True)
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
async def mark_notifications_read(req: MarkReadRequest, user: dict = Depends(get_current_user)):
    """Mark notifications as read"""
    q = supabase_service.db.table("notifications").update({"is_read": True}).eq("user_id", user["id"])
    if req.notification_ids:
        q = q.in_("id", req.notification_ids)
    q.execute()
    return {"success": True}


# ── Server-Side Push Sending ─────────────────────────────────

async def send_push_to_user(
    user_id: str,
    title: str,
    body: str,
    notif_type: str = "system",
    data: Optional[dict] = None,
) -> bool:
    """
    Internal helper — send a FCM push notification to all active tokens for a user.
    Uses Firebase Admin SDK (requires FIREBASE_SERVICE_ACCOUNT_JSON env var).
    Falls back gracefully if Firebase not configured.
    """
    # Store in-app notification regardless of FCM
    try:
        supabase_service.db.table("notifications").insert({
            "user_id": user_id,
            "title":   title,
            "body":    body,
            "type":    notif_type,
            "data":    data or {},
        }).execute()
    except Exception as e:
        logger.warning(f"In-app notification store failed: {e}")

    # Get active FCM tokens
    tokens_res = (
        supabase_service.db.table("fcm_tokens")
        .select("token, platform")
        .eq("user_id", user_id)
        .eq("is_active", True)
        .execute()
    )
    tokens = [t["token"] for t in (tokens_res.data or [])]
    if not tokens:
        return False

    # Send via Firebase Admin SDK
    firebase_key = getattr(settings, "FIREBASE_SERVICE_ACCOUNT_JSON", None)
    if not firebase_key:
        logger.info("Firebase not configured — push skipped, in-app notification stored")
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            import json
            cred = credentials.Certificate(json.loads(firebase_key))
            firebase_admin.initialize_app(cred)

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(aps=messaging.Aps(sound="default"))
            ),
        )
        response = messaging.send_each_for_multicast(message)
        logger.info(f"Push sent: {response.success_count}/{len(tokens)} delivered")

        # Deactivate failed tokens
        failed_tokens = [
            tokens[i] for i, r in enumerate(response.responses) if not r.success
        ]
        if failed_tokens:
            supabase_service.db.table("fcm_tokens").update({"is_active": False}).in_(
                "token", failed_tokens
            ).execute()

        return response.success_count > 0
    except Exception as e:
        logger.error(f"Push notification error: {e}")
        return False


# ── Trigger endpoints (called by Supabase Edge Functions / cron) ─

@router.post("/send-streak-reminder")
@limiter.limit("10/minute")
async def send_streak_reminder(request: Request, user: dict = Depends(get_current_user)):
    """Trigger a streak reminder for the calling user (for testing/manual trigger)"""
    profile = await supabase_service.get_profile(user["id"])
    name = (profile.get("full_name") or "Champion").split()[0] if profile else "Champion"
    streak = profile.get("current_streak", 0) if profile else 0

    success = await send_push_to_user(
        user["id"],
        "🔥 Keep your streak alive!",
        f"Hey {name}! Your {streak}-day streak is at risk. Check in now!",
        "streak_reminder",
    )
    return {"sent": success}


@router.post("/send-task-reminder")
@limiter.limit("10/minute")
async def send_task_reminder(request: Request, user: dict = Depends(get_current_user)):
    """Trigger a task reminder for the calling user"""
    profile = await supabase_service.get_profile(user["id"])
    name = (profile.get("full_name") or "Champion").split()[0] if profile else "Champion"

    success = await send_push_to_user(
        user["id"],
        "💰 New income waiting!",
        f"Hey {name}! You have income tasks ready. Take 10 minutes and make some money today!",
        "task_reminder",
    )
    return {"sent": success}
