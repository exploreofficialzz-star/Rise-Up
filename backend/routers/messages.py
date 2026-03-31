"""
routers/messages.py — RiseUp Messaging System (Production v5)

v5 fixes:
  • send_ai_message: ai_service.mentor_chat() wrapped in try/except with
    automatic fallback to ai_service.chat() — eliminates "Connection issue"
    when mentor_chat is unavailable or throws.
  • get_conversations: is_online computed dynamically from last_seen.
  • All original v4 improvements retained.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone, timedelta
import logging

from services.supabase_service import supabase_service
from services.ai_service import ai_service
from utils.auth import get_current_user

router = APIRouter(prefix="/messages", tags=["Messages"])
logger = logging.getLogger(__name__)

FREE_MSGS_PER_WINDOW   = 3
WINDOW_HOURS           = 4
MAX_AD_UNLOCKS_PER_DAY = 5
ONLINE_THRESHOLD_SECS  = 120


class MessageSend(BaseModel):
    content: str
    media_url: Optional[str] = None


class AiMessageRequest(BaseModel):
    content: str
    ad_unlocked: bool = False


def _db():
    return supabase_service.db


def _is_online_from_last_seen(last_seen_str: Optional[str], now: datetime) -> bool:
    if not last_seen_str:
        return False
    try:
        ls = last_seen_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(ls)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return (now - dt).total_seconds() < ONLINE_THRESHOLD_SECS
    except Exception:
        return False


# ── PRESENCE ─────────────────────────────────────────────────────────────────

@router.post("/presence")
async def update_presence(user: dict = Depends(get_current_user)):
    try:
        _db().table("profiles").update({
            "is_online": True,
            "last_seen": datetime.now(timezone.utc).isoformat(),
        }).eq("id", user["id"]).execute()
    except Exception as e:
        logger.warning(f"presence update failed for {user['id']}: {e}")
    return {"online": True}


@router.delete("/presence")
async def clear_presence(user: dict = Depends(get_current_user)):
    try:
        _db().table("profiles").update({
            "is_online": False,
            "last_seen": datetime.now(timezone.utc).isoformat(),
        }).eq("id", user["id"]).execute()
    except Exception as e:
        logger.warning(f"presence clear failed for {user['id']}: {e}")
    return {"online": False}


# ── CONVERSATIONS ─────────────────────────────────────────────────────────────

@router.get("/conversations")
async def get_conversations(user: dict = Depends(get_current_user)):
    try:
        db  = _db()
        now = datetime.now(timezone.utc)

        try:
            member_res  = (
                db.table("conversation_members")
                .select("conversation_id")
                .eq("user_id", user["id"])
                .execute()
            )
            member_rows = member_res.data or []
        except Exception as e:
            logger.error(f"get_conversations member lookup failed: {e}")
            return {"conversations": []}

        if not member_rows:
            return {"conversations": []}

        conv_ids = [r["conversation_id"] for r in member_rows]

        try:
            convos_res = (
                db.table("conversations")
                .select(
                    "id, type, updated_at, created_at, "
                    "conversation_members(user_id, "
                    "profiles(id, full_name, avatar_url, last_seen, is_online))"
                )
                .in_("id", conv_ids)
                .order("updated_at", desc=True)
                .execute()
            )
            convos = convos_res.data or []
        except Exception as e:
            logger.error(f"get_conversations fetch failed: {e}")
            return {"conversations": []}

        enriched = []
        for c in convos:
            members       = c.get("conversation_members") or []
            other         = next(
                (m for m in members if m.get("user_id") != user["id"]), None
            )
            other_profile = None
            if other and other.get("profiles"):
                other_profile               = dict(other["profiles"])
                other_profile["is_online"]  = _is_online_from_last_seen(
                    other_profile.get("last_seen"), now
                )

            try:
                msgs_res = (
                    db.table("messages")
                    .select("content, created_at, is_read, sender_id, sender_type")
                    .eq("conversation_id", c["id"])
                    .order("created_at", desc=True)
                    .limit(1)
                    .execute()
                )
                last_msg = (msgs_res.data or [None])[0]
            except Exception:
                last_msg = None

            try:
                unread_res = (
                    db.table("messages")
                    .select("id", count="exact")
                    .eq("conversation_id", c["id"])
                    .neq("sender_id", user["id"])
                    .eq("is_read", False)
                    .execute()
                )
                unread = unread_res.count or 0
            except Exception:
                unread = 0

            enriched.append({
                "id":              c["id"],
                "conversation_id": c["id"],
                "other_user":      other_profile,
                "last_message":    last_msg,
                "unread_count":    unread,
                "updated_at":      c["updated_at"],
            })

        return {"conversations": enriched}

    except Exception as e:
        logger.error(f"get_conversations unhandled: {e}")
        raise HTTPException(500, str(e))


@router.post("/conversations/with/{other_user_id}")
async def get_or_create_conversation(
    other_user_id: str,
    user: dict = Depends(get_current_user),
):
    try:
        db       = _db()
        my_res   = (
            db.table("conversation_members")
            .select("conversation_id")
            .eq("user_id", user["id"])
            .execute()
        )
        my_ids   = [r["conversation_id"] for r in (my_res.data or [])]

        if my_ids:
            their_res  = (
                db.table("conversation_members")
                .select("conversation_id")
                .eq("user_id", other_user_id)
                .in_("conversation_id", my_ids)
                .execute()
            )
            shared_ids = [r["conversation_id"] for r in (their_res.data or [])]

            if shared_ids:
                existing_res = (
                    db.table("conversations")
                    .select("id")
                    .in_("id", shared_ids)
                    .eq("type", "direct")
                    .limit(1)
                    .execute()
                )
                if existing_res.data:
                    return {"conversation_id": existing_res.data[0]["id"]}

        convo_res = db.table("conversations").insert({
            "type":       "direct",
            "user_id":    user["id"],
            "created_by": user["id"],
        }).execute()

        if not convo_res.data:
            raise HTTPException(500, "Failed to create conversation")

        convo_id = convo_res.data[0]["id"]

        db.table("conversation_members").insert([
            {"conversation_id": convo_id, "user_id": user["id"]},
            {"conversation_id": convo_id, "user_id": other_user_id},
        ]).execute()

        return {"conversation_id": convo_id}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"get_or_create_conversation [{user['id']} → {other_user_id}]: {e}")
        raise HTTPException(500, f"Could not open conversation: {e}")


# ── MESSAGES ──────────────────────────────────────────────────────────────────

@router.get("/conversations/{conversation_id}/messages")
async def get_messages(
    conversation_id: str,
    limit: int = 50,
    since: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
        _assert_member(db, conversation_id, user["id"])

        q = (
            db.table("messages")
            .select(
                "id, conversation_id, sender_id, content, media_url, "
                "sender_type, is_read, created_at, "
                "profiles:sender_id(id, full_name, avatar_url)"
            )
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=False)
            .limit(limit)
        )
        if since:
            q = q.gt("created_at", since)

        msgs_raw = q.execute().data or []

        msgs = []
        for m in msgs_raw:
            row = dict(m)
            if row.get("sender_type") == "ai" and not row.get("profiles"):
                row["profiles"] = {
                    "id":         None,
                    "full_name":  "RiseUp AI",
                    "avatar_url": None,
                    "is_ai":      True,
                }
            msgs.append(row)

        try:
            db.table("messages") \
                .update({"is_read": True}) \
                .eq("conversation_id", conversation_id) \
                .neq("sender_id", user["id"]) \
                .eq("is_read", False) \
                .execute()
        except Exception:
            pass

        return {"messages": msgs}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"get_messages {conversation_id}: {e}")
        raise HTTPException(500, str(e))


@router.post("/conversations/{conversation_id}/send")
async def send_message(
    conversation_id: str,
    req: MessageSend,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
        _assert_member(db, conversation_id, user["id"])

        data: dict = {
            "conversation_id": conversation_id,
            "sender_id":       user["id"],
            "content":         req.content,
            "is_read":         False,
            "sender_type":     "user",
        }
        if req.media_url:
            data["media_url"] = req.media_url

        msg = db.table("messages").insert(data).execute().data[0]

        try:
            db.table("conversations") \
                .update({"updated_at": datetime.now(timezone.utc).isoformat()}) \
                .eq("id", conversation_id) \
                .execute()
        except Exception:
            pass

        try:
            members      = (
                db.table("conversation_members")
                .select("user_id")
                .eq("conversation_id", conversation_id)
                .neq("user_id", user["id"])
                .execute()
                .data or []
            )
            profile_row  = (
                db.table("profiles")
                .select("full_name")
                .eq("id", user["id"])
                .single()
                .execute()
                .data
            )
            sender_name  = (profile_row or {}).get("full_name") or "Someone"
            for m in members:
                try:
                    db.table("notifications").insert({
                        "user_id": m["user_id"],
                        "type":    "message",
                        "title":   f"New message from {sender_name}",
                        "message": req.content[:80],
                        "data":    {"conversation_id": conversation_id},
                    }).execute()
                except Exception:
                    pass
        except Exception:
            pass

        return {"message": msg}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"send_message {conversation_id}: {e}")
        raise HTTPException(500, str(e))


# ── AI MENTOR IN DM ───────────────────────────────────────────────────────────

@router.post("/conversations/{conversation_id}/ai-message")
async def send_ai_message(
    conversation_id: str,
    req: AiMessageRequest,
    user: dict = Depends(get_current_user),
):
    try:
        db         = _db()
        _assert_member(db, conversation_id, user["id"])

        quota      = _get_or_create_quota(db, user["id"])
        is_premium = _is_premium(db, user["id"])

        if not is_premium:
            now = datetime.now(timezone.utc)

            if req.ad_unlocked:
                quota = _reset_window(db, user["id"], quota, now)
            else:
                window_exp = quota.get("window_expires")
                if window_exp:
                    exp_dt = datetime.fromisoformat(window_exp.replace("Z", "+00:00"))
                    if exp_dt.tzinfo is None:
                        exp_dt = exp_dt.replace(tzinfo=timezone.utc)
                    if exp_dt < now:
                        quota["window_expires"] = None
                        _save_quota(db, user["id"], quota)

                if not quota.get("window_expires"):
                    if quota.get("free_used", 0) >= FREE_MSGS_PER_WINDOW:
                        ads_today = _get_ads_today(quota, now)
                        if ads_today >= MAX_AD_UNLOCKS_PER_DAY:
                            midnight     = (now + timedelta(days=1)).replace(
                                hour=0, minute=0, second=0, microsecond=0)
                            wait_seconds = int((midnight - now).total_seconds())
                            raise HTTPException(429, detail={
                                "code":        "daily_limit",
                                "message":     "Daily AI message limit reached. Resets at midnight.",
                                "retry_after": wait_seconds,
                                "upgrade_url": "/premium",
                            })
                        raise HTTPException(402, detail={
                            "code":       "quota_exceeded",
                            "message":    "Free AI messages used. Watch an ad to continue.",
                            "free_used":  quota.get("free_used", 0),
                            "ads_today":  _get_ads_today(quota, now),
                            "max_ads_day": MAX_AD_UNLOCKS_PER_DAY,
                        })

        # Build message history
        history_res = (
            db.table("messages")
            .select("sender_type, content")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=True)
            .limit(20)
            .execute()
        )
        raw_history = list(reversed(history_res.data or []))
        ai_messages = [
            {
                "role":    "user" if h.get("sender_type") == "user" else "assistant",
                "content": h["content"],
            }
            for h in raw_history
        ]
        ai_messages.append({"role": "user", "content": req.content})

        # User profile for context
        try:
            profile_res  = (
                db.table("profiles").select("*").eq("id", user["id"]).single().execute()
            )
            user_profile = profile_res.data
        except Exception:
            user_profile = {}

        # FIX: Call ai_service.mentor_chat() with a robust fallback chain.
        # If mentor_chat is unavailable or throws, fall back to ai_service.chat().
        # If chat also fails, return a graceful canned response so the endpoint
        # never returns a 500 to the client.
        ai_content = None
        model_used = "ai"

        try:
            result     = await ai_service.mentor_chat(
                messages=ai_messages, user_profile=user_profile
            )
            ai_content = result.get("content")
            model_used = result.get("model", "ai")
        except Exception as mentor_err:
            logger.warning(
                f"mentor_chat failed for conv {conversation_id}: {mentor_err}. "
                "Falling back to ai_service.chat()"
            )
            try:
                result     = await ai_service.chat(
                    ai_messages, system=None, max_tokens=800
                )
                ai_content = result.get("content")
                model_used = result.get("model", "ai")
            except Exception as chat_err:
                logger.error(
                    f"chat fallback also failed for conv {conversation_id}: {chat_err}"
                )

        if not ai_content:
            ai_content = (
                "I'm your RiseUp AI wealth mentor! I'm experiencing a brief "
                "connectivity issue. Please try again in a moment. 🔄"
            )

        # Persist user message
        db.table("messages").insert({
            "conversation_id": conversation_id,
            "sender_id":       user["id"],
            "content":         req.content,
            "sender_type":     "user",
            "is_read":         True,
        }).execute()

        # Persist AI message
        ai_msg = db.table("messages").insert({
            "conversation_id": conversation_id,
            "sender_id":       None,
            "content":         ai_content,
            "sender_type":     "ai",
            "is_read":         True,
        }).execute().data[0]

        try:
            db.table("conversations") \
                .update({"updated_at": datetime.now(timezone.utc).isoformat()}) \
                .eq("id", conversation_id) \
                .execute()
        except Exception:
            pass

        # Quota bookkeeping
        if not is_premium and not quota.get("window_expires"):
            quota["free_used"] = quota.get("free_used", 0) + 1
            _save_quota(db, user["id"], quota)

        return {
            "message":  ai_msg,
            "content":  ai_content,
            "model":    model_used,
            "quota": {
                "free_used":      quota.get("free_used", 0),
                "free_remaining": max(0, FREE_MSGS_PER_WINDOW - quota.get("free_used", 0)),
                "window_expires": quota.get("window_expires"),
                "is_premium":     is_premium,
            },
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"send_ai_message {conversation_id}: {e}")
        raise HTTPException(500, str(e))


# ── USER SEARCH ───────────────────────────────────────────────────────────────

@router.get("/users/search")
async def search_users(
    q: str = "",
    limit: int = 20,
    user: dict = Depends(get_current_user),
):
    try:
        if len(q.strip()) < 2:
            return {"users": []}
        db  = _db()
        now = datetime.now(timezone.utc)

        res = (
            db.table("profiles")
            .select("id, full_name, username, avatar_url, stage, last_seen, is_online")
            .ilike("full_name", f"%{q}%")
            .neq("id", user["id"])
            .limit(limit)
            .execute()
        )
        users = []
        for u in (res.data or []):
            row              = dict(u)
            row["is_online"] = _is_online_from_last_seen(row.get("last_seen"), now)
            users.append(row)

        return {"users": users}

    except Exception as e:
        raise HTTPException(500, str(e))


# ── QUOTA ─────────────────────────────────────────────────────────────────────

@router.get("/ai-quota")
async def get_ai_quota(user: dict = Depends(get_current_user)):
    db         = _db()
    quota      = _get_or_create_quota(db, user["id"])
    is_premium = _is_premium(db, user["id"])
    now        = datetime.now(timezone.utc)
    ads_today  = _get_ads_today(quota, now)

    window_exp = quota.get("window_expires")
    in_window  = False
    if window_exp:
        try:
            exp_dt    = datetime.fromisoformat(window_exp.replace("Z", "+00:00"))
            in_window = exp_dt > now
        except Exception:
            pass

    return {
        "is_premium":         is_premium,
        "free_used":          quota.get("free_used", 0),
        "free_total":         FREE_MSGS_PER_WINDOW,
        "free_remaining":     (
            max(0, FREE_MSGS_PER_WINDOW - quota.get("free_used", 0))
            if not in_window else 999
        ),
        "in_unlocked_window": in_window,
        "window_expires":     window_exp,
        "ads_today":          ads_today,
        "max_ads_day":        MAX_AD_UNLOCKS_PER_DAY,
        "ads_remaining":      max(0, MAX_AD_UNLOCKS_PER_DAY - ads_today),
    }


# ── HELPERS ───────────────────────────────────────────────────────────────────

def _assert_member(db, conversation_id: str, user_id: str):
    member = (
        db.table("conversation_members")
        .select("id")
        .eq("conversation_id", conversation_id)
        .eq("user_id", user_id)
        .execute()
        .data
    )
    if not member:
        raise HTTPException(403, "Not a member of this conversation")


def _is_premium(db, user_id: str) -> bool:
    try:
        sub = (
            db.table("subscriptions")
            .select("status")
            .eq("user_id", user_id)
            .eq("status", "active")
            .limit(1)
            .execute()
            .data
        )
        return bool(sub)
    except Exception:
        return False


def _get_or_create_quota(db, user_id: str) -> dict:
    try:
        row = (
            db.table("ai_message_quotas")
            .select("*")
            .eq("user_id", user_id)
            .single()
            .execute()
            .data
        )
        return row or _default_quota()
    except Exception:
        return _default_quota()


def _default_quota() -> dict:
    return {"free_used": 0, "window_expires": None, "ads_count": 0, "ads_date": None}


def _save_quota(db, user_id: str, quota: dict):
    try:
        db.table("ai_message_quotas").upsert({
            "user_id":        user_id,
            "free_used":      quota.get("free_used", 0),
            "window_expires": quota.get("window_expires"),
            "ads_count":      quota.get("ads_count", 0),
            "ads_date":       quota.get("ads_date"),
            "updated_at":     datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception:
        pass


def _reset_window(db, user_id: str, quota: dict, now: datetime) -> dict:
    today = now.date().isoformat()
    if quota.get("ads_date") != today:
        quota["ads_count"] = 0
        quota["ads_date"]  = today
    quota["ads_count"]      = quota.get("ads_count", 0) + 1
    quota["free_used"]      = 0
    quota["window_expires"] = (now + timedelta(hours=WINDOW_HOURS)).isoformat()
    _save_quota(db, user_id, quota)
    return quota


def _get_ads_today(quota: dict, now: datetime) -> int:
    if quota.get("ads_date") != now.date().isoformat():
        return 0
    return quota.get("ads_count", 0)
