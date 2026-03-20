"""Community Router — Posts, leaderboard, challenges"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional

from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/community", tags=["Community"])


class PostCreate(BaseModel):
    content: str
    post_type: str = "win"
    tags: Optional[list] = []


@router.get("/posts")
async def get_posts(limit: int = 20, post_type: str = None):
    """Get community posts (public)"""
    q = supabase_service.db.table("community_posts") \
        .select("*, profiles(full_name, stage, country)") \
        .eq("is_visible", True) \
        .order("created_at", desc=True) \
        .limit(limit)
    if post_type:
        q = q.eq("post_type", post_type)
    return {"posts": q.execute().data or []}


@router.post("/posts")
async def create_post(req: PostCreate, user: dict = Depends(get_current_user)):
    res = supabase_service.db.table("community_posts").insert({
        "user_id": user["id"],
        "content": req.content,
        "post_type": req.post_type,
        "tags": req.tags,
    }).execute()
    return {"post": res.data[0] if res.data else {}, "message": "🌟 Posted to the community!"}


@router.post("/posts/{post_id}/like")
async def like_post(post_id: str, user: dict = Depends(get_current_user)):
    supabase_service.db.rpc("increment_post_likes", {"pid": post_id}).execute()
    return {"message": "👍 Liked!"}


@router.get("/leaderboard")
async def get_leaderboard(period: str = "monthly", limit: int = 10):
    """Get top earners leaderboard"""
    res = supabase_service.db.table("profiles") \
        .select("full_name, stage, country, total_earned, currency") \
        .order("total_earned", desc=True) \
        .limit(limit) \
        .execute()
    return {"leaderboard": res.data or [], "period": period}


class ShareLog(BaseModel):
    share_type: str
    platform: str


@router.post("/share")
async def log_share(req: ShareLog, user: dict = Depends(get_current_user)):
    """Log a social share event + unlock share achievement"""
    supabase_service.db.table("share_logs").insert({
        "user_id":    user["id"],
        "share_type": req.share_type,
        "platform":   req.platform,
    }).execute()
    # Unlock achievement
    supabase_service.db.rpc("unlock_achievement", {
        "uid": user["id"], "ach_key": "shared_win"
    }).execute()
    return {"success": True}
