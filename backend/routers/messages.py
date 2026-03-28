"""
routers/messages.py  — RiseUp Messaging System (Production v2)
Handles:
  • Direct messages between users
  • AI mentor messages inside DM conversations
  • User search for new DMs
  • AI message quota enforcement (free: 3/4-hr window, 5 unlocks/day)
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone, timedelta

from services.supabase_service import supabase_service
from services.ai_service import ai_service
from utils.auth import get_current_user

router = APIRouter(prefix="/messages", tags=["Messages"])
db = supabase_service.db

# ── Freemium constants ────────────────────────────────────────────────
FREE_MSGS_PER_WINDOW  = 3      # free AI messages per 4-hour window
WINDOW_HOURS          = 4      # hours per unlock window
MAX_AD_UNLOCKS_PER_DAY = 5     # rewarded-ad unlocks per calendar day
# ─────────────────────────────────────────────────────────────────────


# ── Request models ────────────────────────────────────────────────────
class MessageSend(BaseModel):
    content: str
    media_url: Optional[str] = None


class AiMessageRequest(BaseModel):
    content: str                    # user's message text
    ad_unlocked: bool = False       # True after user watched a rewarded ad


# ═══════════════════════════════════════════════════════════════════════
# CONVERSATIONS
# ═══════════════════════════════════════════════════════════════════════

@router.get("/conversations")
async def get_conversations(user: dict = Depends(get_current_user)):
    """Return all DM conversations for the current user, sorted by latest."""
    try:
        res = (
            db.table("conversations")
            .select(
                "*, "
                "conversation_members!inner(user_id, profiles(id, full_name, avatar_url, is_online)), "
                "messages(content, created_at, is_read, sender_id)"
            )
            .eq("conversation_members.user_id", user["id"])
            .order("updated_at", desc=True)
            .execute()
        )

        convos = res.data or []
        enriched = []
        for c in convos:
            members  = c.get("conversation_members") or []
            other    = next((m for m in members if m["user_id"] != user["id"]), None)
            msgs     = c.get("messages") or []
            last_msg = msgs[-1] if msgs else None
            unread   = sum(
                1 for m in msgs
                if not m.get("is_read") and m.get("sender_id") != user["id"]
            )
            enriched.append({
                "id":         c["id"],
                "other_user": other["profiles"] if other else None,
                "last_message": last_msg,
                "unread_count": unread,
                "updated_at":   c["updated_at"],
            })

        return {"conversations": enriched}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Get or create a conversation with another user ───────────────────
@router.post("/conversations/with/{other_user_id}")
async def get_or_create_conversation(
    other_user_id: str,
    user: dict = Depends(get_current_user),
):
    try:
        existing = (
            db.rpc("get_conversation_between", {
                "user1": user["id"], "user2": other_user_id
            })
            .execute()
            .data
        )
        if existing:
            return {"conversation_id": existing[0]["id"]}

        # Create new conversation
        convo = db.table("conversations").insert({
            "type": "direct", "created_by": user["id"],
        }).execute().data[0]

        db.table("conversation_members").insert([
            {"conversation_id": convo["id"], "user_id": user["id"]},
            {"conversation_id": convo["id"], "user_id": other_user_id},
        ]).execute()

        return {"conversation_id": convo["id"]}
    except Exception as e:
        raise HTTPException(500, str(e))


# ═══════════════════════════════════════════════════════════════════════
# MESSAGES
# ═══════════════════════════════════════════════════════════════════════

@router.get("/conversations/{conversation_id}/messages")
async def get_messages(
    conversation_id: str,
    limit: int = 50,
    since: Optional[str] = None,          # ISO timestamp for polling
    user: dict = Depends(get_current_user),
):
    """Return messages in a conversation.  `since` enables incremental polling."""
    try:
        _assert_member(conversation_id, user["id"])

        q = (
            db.table("messages")
            .select("*, profiles!messages_sender_id_fkey(id, full_name, avatar_url)")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=False)
            .limit(limit)
        )
        if since:
            q = q.gt("created_at", since)

        msgs = q.execute().data or []

        # Mark incoming messages as read
        db.table("messages") \
            .update({"is_read": True}) \
            .eq("conversation_id", conversation_id) \
            .neq("sender_id", user["id"]) \
            .eq("is_read", False) \
            .execute()

        return {"messages": msgs}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/conversations/{conversation_id}/send")
async def send_message(
    conversation_id: str,
    req: MessageSend,
    user: dict = Depends(get_current_user),
):
    """Send a DM from one user to another."""
    try:
        _assert_member(conversation_id, user["id"])

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

        # Bump conversation updated_at (triggers unread badge on other side)
        db.table("conversations").update({"updated_at": "now()"}).eq("id", conversation_id).execute()

        # Push notification to the other member
        members = (
            db.table("conversation_members")
            .select("user_id")
            .eq("conversation_id", conversation_id)
            .neq("user_id", user["id"])
            .execute()
            .data or []
        )
        profile = (
            db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
        )
        sender_name = profile.get("full_name", "Someone") if profile else "Someone"

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
                pass  # Notification failure must not fail the message send

        return {"message": msg}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ═══════════════════════════════════════════════════════════════════════
# AI MENTOR INSIDE A DM CONVERSATION
# ═══════════════════════════════════════════════════════════════════════

@router.post("/conversations/{conversation_id}/ai-message")
async def send_ai_message(
    conversation_id: str,
    req: AiMessageRequest,
    user: dict = Depends(get_current_user),
):
    """
    Invoke RiseUp AI inside a DM conversation.
    Quota rules enforced server-side:
      • Premium users → unlimited
      • Free users → 3 free per 4-hour window, then rewarded-ad gate
      • After ad watched (ad_unlocked=True) → window reset server-side
    """
    try:
        _assert_member(conversation_id, user["id"])

        # ── Quota check ──────────────────────────────────────────────
        quota = _get_or_create_quota(user["id"])
        is_premium = _is_premium(user["id"])

        if not is_premium:
            now = datetime.now(timezone.utc)

            # Handle ad unlock: reset window
            if req.ad_unlocked:
                quota = _reset_window(user["id"], quota, now)
            else:
                # Check if in a valid unlocked window
                window_exp = quota.get("window_expires")
                if window_exp:
                    exp_dt = datetime.fromisoformat(window_exp)
                    if exp_dt < now:
                        # Window expired — fall through to free count
                        quota["window_expires"] = None
                        _save_quota(user["id"], quota)

                if not quota.get("window_expires"):
                    # Free messages check
                    if quota.get("free_used", 0) >= FREE_MSGS_PER_WINDOW:
                        ads_today = _get_ads_today(quota, now)
                        if ads_today >= MAX_AD_UNLOCKS_PER_DAY:
                            # Compute seconds until midnight UTC
                            midnight = (now + timedelta(days=1)).replace(
                                hour=0, minute=0, second=0, microsecond=0
                            )
                            wait_seconds = int((midnight - now).total_seconds())
                            raise HTTPException(
                                429,
                                detail={
                                    "code":         "daily_limit",
                                    "message":      "Daily AI message limit reached. Resets at midnight.",
                                    "retry_after":  wait_seconds,
                                    "upgrade_url":  "/premium",
                                }
                            )
                        # Not at daily limit — client should show ad gate
                        raise HTTPException(
                            402,
                            detail={
                                "code":    "quota_exceeded",
                                "message": "Free AI messages used. Watch an ad to continue.",
                                "free_used":    quota.get("free_used", 0),
                                "ads_today":    ads_today,
                                "max_ads_day":  MAX_AD_UNLOCKS_PER_DAY,
                            }
                        )

        # ── Fetch recent conversation context ──────────────────────
        history_res = (
            db.table("messages")
            .select("sender_type, content")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=True)
            .limit(20)
            .execute()
        )
        raw_history = list(reversed(history_res.data or []))
        ai_messages = []
        for h in raw_history:
            role = "user" if h.get("sender_type") == "user" else "assistant"
            ai_messages.append({"role": role, "content": h["content"]})

        # Add current user message
        ai_messages.append({"role": "user", "content": req.content})

        # Fetch user profile for localisation
        profile_res = (
            db.table("profiles")
            .select("*")
            .eq("id", user["id"])
            .single()
            .execute()
        )
        user_profile = profile_res.data

        # ── Call AI ─────────────────────────────────────────────────
        result = await ai_service.mentor_chat(
            messages=ai_messages,
            user_profile=user_profile,
        )
        ai_content = result.get("content", "I'm here to help! Ask me anything. 💡")

        # ── Save both messages ───────────────────────────────────────
        db.table("messages").insert({
            "conversation_id": conversation_id,
            "sender_id":       user["id"],
            "content":         req.content,
            "sender_type":     "user",
            "is_read":         True,
        }).execute()

        ai_msg = db.table("messages").insert({
            "conversation_id": conversation_id,
            "sender_id":       None,
            "content":         ai_content,
            "sender_type":     "ai",
            "is_read":         True,
        }).execute().data[0]

        db.table("conversations").update({"updated_at": "now()"}).eq("id", conversation_id).execute()

        # ── Update quota ─────────────────────────────────────────────
        if not is_premium:
            if not quota.get("window_expires"):
                quota["free_used"] = quota.get("free_used", 0) + 1
                _save_quota(user["id"], quota)

        return {
            "message":    ai_msg,
            "content":    ai_content,
            "model":      result.get("model", "ai"),
            "quota": {
                "free_used":       quota.get("free_used", 0),
                "free_remaining":  max(0, FREE_MSGS_PER_WINDOW - quota.get("free_used", 0)),
                "window_expires":  quota.get("window_expires"),
                "is_premium":      is_premium,
            },
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ═══════════════════════════════════════════════════════════════════════
# USER SEARCH (for new DM sheet)
# ═══════════════════════════════════════════════════════════════════════

@router.get("/users/search")
async def search_users(
    q: str = "",
    limit: int = 20,
    user: dict = Depends(get_current_user),
):
    """Search for users to start a new DM. Excludes the current user."""
    try:
        if len(q.strip()) < 2:
            return {"users": []}

        res = (
            db.table("profiles")
            .select("id, full_name, username, avatar_url, stage, is_online")
            .ilike("full_name", f"%{q}%")
            .neq("id", user["id"])
            .limit(limit)
            .execute()
        )
        return {"users": res.data or []}
    except Exception as e:
        raise HTTPException(500, str(e))


# ═══════════════════════════════════════════════════════════════════════
# QUOTA — READ STATUS (so client can sync on launch)
# ═══════════════════════════════════════════════════════════════════════

@router.get("/ai-quota")
async def get_ai_quota(user: dict = Depends(get_current_user)):
    """Return current AI message quota for this user."""
    quota      = _get_or_create_quota(user["id"])
    is_premium = _is_premium(user["id"])
    now        = datetime.now(timezone.utc)
    ads_today  = _get_ads_today(quota, now)
    window_exp = quota.get("window_expires")
    in_window  = False
    if window_exp:
        exp_dt    = datetime.fromisoformat(window_exp)
        in_window = exp_dt > now

    return {
        "is_premium":       is_premium,
        "free_used":        quota.get("free_used", 0),
        "free_total":       FREE_MSGS_PER_WINDOW,
        "free_remaining":   max(0, FREE_MSGS_PER_WINDOW - quota.get("free_used", 0)) if not in_window else 999,
        "in_unlocked_window": in_window,
        "window_expires":   window_exp,
        "ads_today":        ads_today,
        "max_ads_day":      MAX_AD_UNLOCKS_PER_DAY,
        "ads_remaining":    max(0, MAX_AD_UNLOCKS_PER_DAY - ads_today),
    }


# ═══════════════════════════════════════════════════════════════════════
# PRIVATE HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _assert_member(conversation_id: str, user_id: str):
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


def _is_premium(user_id: str) -> bool:
    try:
        sub = (
            db.table("subscriptions")
            .select("status, expires_at")
            .eq("user_id", user_id)
            .eq("status", "active")
            .limit(1)
            .execute()
            .data
        )
        return bool(sub)
    except Exception:
        return False


def _get_or_create_quota(user_id: str) -> dict:
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


def _save_quota(user_id: str, quota: dict):
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
        pass  # quota save failure must not block the message


def _reset_window(user_id: str, quota: dict, now: datetime) -> dict:
    today = now.date().isoformat()
    if quota.get("ads_date") != today:
        quota["ads_count"] = 0
        quota["ads_date"]  = today
    quota["ads_count"]      = quota.get("ads_count", 0) + 1
    quota["free_used"]      = 0
    quota["window_expires"] = (now + timedelta(hours=WINDOW_HOURS)).isoformat()
    _save_quota(user_id, quota)
    return quota


def _get_ads_today(quota: dict, now: datetime) -> int:
    today = now.date().isoformat()
    if quota.get("ads_date") != today:
        return 0
    return quota.get("ads_count", 0)
