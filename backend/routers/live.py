"""Live Router — Live sessions, go live, join, coins"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/live", tags=["Live"])
db = supabase_service.db


class LiveCreate(BaseModel):
    title: str
    topic: str = "💰 Wealth"
    is_premium: bool = False


class SendCoins(BaseModel):
    amount: int


# ── Get live sessions ──────────────────────────────────
@router.get("/sessions")
async def get_sessions(user: dict = Depends(get_current_user)):
    try:
        res = db.table("live_sessions") \
            .select("*, profiles!live_sessions_host_id_fkey(id, full_name, avatar_url, is_verified, subscription_tier)") \
            .eq("is_active", True) \
            .order("viewers_count", desc=True) \
            .execute()
        sessions = res.data or []

        # Check subscription tier
        profile = db.table("profiles").select("subscription_tier").eq("id", user["id"]).single().execute().data
        is_premium = profile and profile.get("subscription_tier") == "premium"

        for s in sessions:
            s["can_join"] = not s.get("is_premium") or is_premium

        return {"sessions": sessions, "is_premium": is_premium}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Start live session ─────────────────────────────────
@router.post("/start")
async def start_live(req: LiveCreate, user: dict = Depends(get_current_user)):
    try:
        # Check user stage — only earners/growing/wealth can go live
        profile = db.table("profiles") \
            .select("stage, subscription_tier") \
            .eq("id", user["id"]).single().execute().data

        allowed_stages = ["earning", "growing", "wealth"]
        if profile and profile.get("stage") not in allowed_stages:
            raise HTTPException(403, "You need to reach the Earning stage to go live. Keep hustling! 💪")

        # End any existing session
        db.table("live_sessions") \
            .update({"is_active": False, "ended_at": "now()"}) \
            .eq("host_id", user["id"]) \
            .eq("is_active", True) \
            .execute()

        # Create new session
        session = db.table("live_sessions").insert({
            "host_id": user["id"],
            "title": req.title,
            "topic": req.topic,
            "is_premium": req.is_premium,
            "is_active": True,
            "viewers_count": 0,
            "coins_earned": 0,
        }).execute().data[0]

        return {"session": session, "message": "You're live! 🔴"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── End live session ───────────────────────────────────
@router.post("/end")
async def end_live(user: dict = Depends(get_current_user)):
    try:
        db.table("live_sessions") \
            .update({"is_active": False, "ended_at": "now()"}) \
            .eq("host_id", user["id"]) \
            .eq("is_active", True) \
            .execute()
        return {"message": "Live ended"}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Join / Leave session ───────────────────────────────
@router.post("/sessions/{session_id}/join")
async def join_session(session_id: str, user: dict = Depends(get_current_user)):
    try:
        session = db.table("live_sessions").select("is_premium, host_id").eq("id", session_id).single().execute().data
        if not session:
            raise HTTPException(404, "Session not found")

        if session.get("is_premium"):
            profile = db.table("profiles").select("subscription_tier").eq("id", user["id"]).single().execute().data
            if not profile or profile.get("subscription_tier") != "premium":
                raise HTTPException(403, "Premium required to join this live")

        db.table("live_viewers").upsert({
            "session_id": session_id, "user_id": user["id"], "joined_at": "now()"
        }).execute()

        db.rpc("increment_live_viewers", {"sid": session_id}).execute()

        return {"joined": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/sessions/{session_id}/leave")
async def leave_session(session_id: str, user: dict = Depends(get_current_user)):
    try:
        db.table("live_viewers").delete() \
            .eq("session_id", session_id).eq("user_id", user["id"]).execute()
        db.rpc("decrement_live_viewers", {"sid": session_id}).execute()
        return {"left": True}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Send coins ─────────────────────────────────────────
@router.post("/sessions/{session_id}/coins")
async def send_coins(
    session_id: str,
    req: SendCoins,
    user: dict = Depends(get_current_user),
):
    try:
        if req.amount < 1:
            raise HTTPException(400, "Invalid coin amount")

        session = db.table("live_sessions").select("host_id, is_active").eq("id", session_id).single().execute().data
        if not session or not session["is_active"]:
            raise HTTPException(404, "Session not found or ended")

        # Log coin gift
        db.table("coin_gifts").insert({
            "session_id": session_id,
            "sender_id": user["id"],
            "host_id": session["host_id"],
            "amount": req.amount,
        }).execute()

        # Add to host coins
        db.rpc("add_live_coins", {"sid": session_id, "amount": req.amount}).execute()

        profile = db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data

        # Notify host
        db.table("notifications").insert({
            "user_id": session["host_id"],
            "type": "coins",
            "title": "Coins received 🪙",
            "message": f"{profile.get('full_name', 'Someone')} sent you {req.amount} coins!",
            "data": {"session_id": session_id},
        }).execute()

        return {"message": f"Sent {req.amount} coins! 🪙"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))
