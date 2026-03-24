"""Messages Router — Direct messages between users"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/messages", tags=["Messages"])
db = supabase_service.db


class MessageSend(BaseModel):
    content: str
    media_url: Optional[str] = None


# ── Get all conversations ──────────────────────────────
@router.get("/conversations")
async def get_conversations(user: dict = Depends(get_current_user)):
    try:
        res = db.table("conversations") \
            .select(
                "*, "
                "conversation_members!inner(user_id, profiles(id, full_name, avatar_url, is_online)), "
                "messages(content, created_at, is_read, sender_id)"
            ) \
            .eq("conversation_members.user_id", user["id"]) \
            .order("updated_at", desc=True) \
            .execute()

        convos = res.data or []
        enriched = []
        for c in convos:
            members = c.get("conversation_members") or []
            # Get the other person (not current user)
            other = next((m for m in members if m["user_id"] != user["id"]), None)
            msgs = c.get("messages") or []
            last_msg = msgs[-1] if msgs else None
            unread = sum(1 for m in msgs if not m.get("is_read") and m.get("sender_id") != user["id"])

            enriched.append({
                "id": c["id"],
                "other_user": other["profiles"] if other else None,
                "last_message": last_msg,
                "unread_count": unread,
                "updated_at": c["updated_at"],
            })

        return {"conversations": enriched}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Get or create conversation ─────────────────────────
@router.post("/conversations/with/{other_user_id}")
async def get_or_create_conversation(
    other_user_id: str,
    user: dict = Depends(get_current_user),
):
    try:
        # Check if conversation exists
        existing = db.rpc("get_conversation_between", {
            "user1": user["id"], "user2": other_user_id
        }).execute().data

        if existing:
            return {"conversation_id": existing[0]["id"]}

        # Create new
        convo = db.table("conversations").insert({
            "type": "direct",
            "created_by": user["id"],
        }).execute().data[0]

        # Add members
        db.table("conversation_members").insert([
            {"conversation_id": convo["id"], "user_id": user["id"]},
            {"conversation_id": convo["id"], "user_id": other_user_id},
        ]).execute()

        return {"conversation_id": convo["id"]}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Get messages in conversation ───────────────────────
@router.get("/conversations/{conversation_id}/messages")
async def get_messages(
    conversation_id: str,
    limit: int = 50,
    before: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    try:
        # Verify member
        member = db.table("conversation_members") \
            .select("id").eq("conversation_id", conversation_id).eq("user_id", user["id"]).execute().data
        if not member:
            raise HTTPException(403, "Not a member of this conversation")

        q = db.table("messages") \
            .select("*, profiles!messages_sender_id_fkey(id, full_name, avatar_url)") \
            .eq("conversation_id", conversation_id) \
            .order("created_at", desc=False) \
            .limit(limit)

        if before:
            q = q.lt("created_at", before)

        msgs = q.execute().data or []

        # Mark as read
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


# ── Send message ───────────────────────────────────────
@router.post("/conversations/{conversation_id}/send")
async def send_message(
    conversation_id: str,
    req: MessageSend,
    user: dict = Depends(get_current_user),
):
    try:
        # Verify member
        member = db.table("conversation_members") \
            .select("id").eq("conversation_id", conversation_id).eq("user_id", user["id"]).execute().data
        if not member:
            raise HTTPException(403, "Not a member")

        data = {
            "conversation_id": conversation_id,
            "sender_id": user["id"],
            "content": req.content,
            "is_read": False,
        }
        if req.media_url:
            data["media_url"] = req.media_url

        msg = db.table("messages").insert(data).execute().data[0]

        # Update conversation timestamp
        db.table("conversations").update({"updated_at": "now()"}).eq("id", conversation_id).execute()

        # Notify other members
        members = db.table("conversation_members") \
            .select("user_id").eq("conversation_id", conversation_id).neq("user_id", user["id"]).execute().data or []
        profile = db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data

        for m in members:
            db.table("notifications").insert({
                "user_id": m["user_id"],
                "type": "message",
                "title": "New message",
                "message": f"{profile.get('full_name', 'Someone')}: {req.content[:50]}",
                "data": {"conversation_id": conversation_id},
            }).execute()

        return {"message": msg}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Groups messaging ───────────────────────────────────
@router.get("/groups")
async def get_groups(user: dict = Depends(get_current_user)):
    try:
        res = db.table("groups") \
            .select("*, group_members(user_id, count)") \
            .eq("is_active", True) \
            .order("members_count", desc=True) \
            .execute()
        groups = res.data or []

        # Check which ones user joined
        joined = db.table("group_members") \
            .select("group_id").eq("user_id", user["id"]).execute().data or []
        joined_ids = {j["group_id"] for j in joined}

        for g in groups:
            g["is_joined"] = g["id"] in joined_ids

        return {"groups": groups}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Join/Leave group ───────────────────────────────────
@router.post("/groups/{group_id}/join")
async def toggle_group(group_id: str, user: dict = Depends(get_current_user)):
    try:
        existing = db.table("group_members") \
            .select("id").eq("group_id", group_id).eq("user_id", user["id"]).execute().data

        if existing:
            db.table("group_members").delete() \
                .eq("group_id", group_id).eq("user_id", user["id"]).execute()
            db.rpc("decrement_group_members", {"gid": group_id}).execute()
            return {"joined": False}
        else:
            db.table("group_members").insert({
                "group_id": group_id, "user_id": user["id"]
            }).execute()
            db.rpc("increment_group_members", {"gid": group_id}).execute()
            return {"joined": True}
    except Exception as e:
        raise HTTPException(500, str(e))
