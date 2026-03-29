"""
Notification Service — RiseUp Backend
Single source of truth for all push and in-app notifications.

Architecture:
  • send_push_to_user()  – stores in-app record + fires FCM multicast
  • Named helpers        – called by routers via BackgroundTasks
  • firebase_admin SDK   – optional; falls back gracefully if not configured
"""
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# Firebase initialisation (lazy, thread-safe singleton)
# ─────────────────────────────────────────────────────────────

_firebase_initialised = False


def _init_firebase(service_account_json: str) -> bool:
    """Initialise Firebase Admin SDK once. Returns True on success."""
    global _firebase_initialised
    if _firebase_initialised:
        return True
    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred = credentials.Certificate(json.loads(service_account_json))
            firebase_admin.initialize_app(cred)
        _firebase_initialised = True
        return True
    except Exception as exc:
        logger.error("Firebase init failed: %s", exc)
        return False


# ─────────────────────────────────────────────────────────────
# Core push sender (module-level so notifications.py can import it)
# ─────────────────────────────────────────────────────────────

async def send_push_to_user(
    user_id: str,
    title: str,
    body: str,
    notif_type: str = "system",
    data: Optional[dict] = None,
) -> bool:
    """
    Send a push notification to all active FCM tokens for a user AND
    persist an in-app notification record.

    Always stores the in-app record first.
    FCM delivery is skipped gracefully if FIREBASE_SERVICE_ACCOUNT_JSON
    is not configured.

    Returns True if at least one FCM message was delivered.
    """
    # ── 1. Persist in-app notification ──────────────────────
    try:
        supabase_service.client.table("notifications").insert({
            "id":         str(uuid.uuid4()),
            "user_id":    user_id,
            "title":      title,
            "body":       body,
            "type":       notif_type,
            "data":       data or {},
            "is_read":    False,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as exc:
        logger.warning("In-app notification store failed | user=%s | %s", user_id, exc)

    # ── 2. Fetch active FCM tokens ───────────────────────────
    try:
        tokens_res = (
            supabase_service.client.table("fcm_tokens")
            .select("token")
            .eq("user_id", user_id)
            .eq("is_active", True)
            .execute()
        )
        tokens = [t["token"] for t in (tokens_res.data or [])]
    except Exception as exc:
        logger.warning("FCM token fetch failed | user=%s | %s", user_id, exc)
        tokens = []

    if not tokens:
        return False

    # ── 3. Resolve Firebase credentials ─────────────────────
    try:
        from config import settings
        firebase_key = getattr(settings, "FIREBASE_SERVICE_ACCOUNT_JSON", None)
    except Exception:
        firebase_key = None

    if not firebase_key:
        logger.info("Firebase not configured — push skipped, in-app record stored")
        return False

    if not _init_firebase(firebase_key):
        return False

    # ── 4. Send multicast via Firebase Admin SDK ─────────────
    try:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default")
                )
            ),
        )
        response = messaging.send_each_for_multicast(message)
        logger.info(
            "FCM multicast | user=%s | %d/%d delivered",
            user_id,
            response.success_count,
            len(tokens),
        )

        # Deactivate stale / unregistered tokens
        failed_tokens = [
            tokens[i]
            for i, r in enumerate(response.responses)
            if not r.success
        ]
        if failed_tokens:
            try:
                supabase_service.client.table("fcm_tokens").update(
                    {"is_active": False}
                ).in_("token", failed_tokens).execute()
            except Exception as exc:
                logger.warning("Failed to deactivate bad tokens: %s", exc)

        return response.success_count > 0

    except Exception as exc:
        logger.error("FCM send error | user=%s | %s", user_id, exc)
        return False


# ─────────────────────────────────────────────────────────────
# Named notification helpers
# All methods are async and swallow exceptions so they are
# safe to call inside FastAPI BackgroundTasks.
# ─────────────────────────────────────────────────────────────

class NotificationService:

    # ── Skills ───────────────────────────────────────────────

    async def send_skill_start(
        self,
        user_id: str,
        skill_name: str,
        first_lesson: str,
    ) -> None:
        """Fired when a user enrolls in a skill path."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title=f"🎓 Learning started: {skill_name}",
                body=f"Your first lesson: {first_lesson}. Let's go!",
                notif_type="skill_started",
                data={"skill_name": skill_name, "first_lesson": first_lesson},
            )
        except Exception as exc:
            logger.error("send_skill_start failed | user=%s | %s", user_id, exc)

    async def send_skill_complete(
        self,
        user_id: str,
        skill_name: str,
    ) -> None:
        """Fired when a user completes a skill path."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title=f"🏆 Skill complete: {skill_name}",
                body="You've mastered a new skill! Add it to your portfolio.",
                notif_type="skill_completed",
                data={"skill_name": skill_name},
            )
        except Exception as exc:
            logger.error("send_skill_complete failed | user=%s | %s", user_id, exc)

    async def send_first_earning_congrats(
        self,
        user_id: str,
        skill_name: str,
        amount_usd: float,
    ) -> None:
        """Fired when a user logs their first earning from a skill."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title="💸 First skill earning logged!",
                body=(
                    f"You earned ${amount_usd:.2f} using {skill_name}. "
                    "Keep stacking those wins!"
                ),
                notif_type="first_skill_earning",
                data={"skill_name": skill_name, "amount_usd": str(amount_usd)},
            )
        except Exception as exc:
            logger.error(
                "send_first_earning_congrats failed | user=%s | %s", user_id, exc
            )

    # ── Challenges ───────────────────────────────────────────

    async def send_challenge_start(
        self,
        user_id: str,
        challenge_title: str,
        first_action: str,
    ) -> None:
        """Fired when a user creates a new income challenge."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title=f"🎯 Challenge started: {challenge_title}",
                body=f"Today's action: {first_action}",
                notif_type="challenge_started",
                data={
                    "challenge_title": challenge_title,
                    "first_action": first_action,
                },
            )
        except Exception as exc:
            logger.error(
                "send_challenge_start failed | user=%s | %s", user_id, exc
            )

    async def send_challenge_complete(
        self,
        user_id: str,
        challenge_title: str,
        earnings_usd: float,
    ) -> None:
        """Fired when a user completes an income challenge."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title=f"🏆 Challenge complete: {challenge_title}",
                body=(
                    f"You earned ${earnings_usd:.2f}. "
                    "Incredible work — share your win!"
                ),
                notif_type="challenge_completed",
                data={
                    "challenge_title": challenge_title,
                    "earnings_usd": str(earnings_usd),
                },
            )
        except Exception as exc:
            logger.error(
                "send_challenge_complete failed | user=%s | %s", user_id, exc
            )

    async def schedule_checkin_reminder(
        self,
        user_id: str,
        challenge_id: str,
        challenge_title: str,
        next_action: str,
    ) -> None:
        """Stores a check-in reminder surfaced as a push/in-app nudge."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title=f"⏰ Daily check-in: {challenge_title}",
                body=f"Tomorrow's action: {next_action}",
                notif_type="checkin_reminder",
                data={
                    "challenge_id": challenge_id,
                    "challenge_title": challenge_title,
                    "next_action": next_action,
                },
            )
        except Exception as exc:
            logger.error(
                "schedule_checkin_reminder failed | user=%s | %s", user_id, exc
            )

    # ── Streak & Task reminders ──────────────────────────────

    async def send_streak_reminder(
        self,
        user_id: str,
        name: str,
        streak: int,
    ) -> None:
        """Fired by cron / Supabase Edge Function for streak preservation."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title="🔥 Keep your streak alive!",
                body=f"Hey {name}! Your {streak}-day streak is at risk. Check in now!",
                notif_type="streak_reminder",
                data={"streak": str(streak)},
            )
        except Exception as exc:
            logger.error(
                "send_streak_reminder failed | user=%s | %s", user_id, exc
            )

    async def send_task_reminder(
        self,
        user_id: str,
        name: str,
    ) -> None:
        """Fired by cron / Supabase Edge Function for task nudges."""
        try:
            await send_push_to_user(
                user_id=user_id,
                title="💰 New income waiting!",
                body=(
                    f"Hey {name}! You have income tasks ready. "
                    "Take 10 minutes and make some money today!"
                ),
                notif_type="task_reminder",
            )
        except Exception as exc:
            logger.error(
                "send_task_reminder failed | user=%s | %s", user_id, exc
            )


# Singleton — import this everywhere
notification_service = NotificationService()

