"""Posts Router — Social feed, likes, comments, shares, follows, status"""
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timedelta
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/posts", tags=["Posts"])
db = supabase_service.db


# ── Models ─────────────────────────────────────────────
class PostCreate(BaseModel):
    content: str
    tag: str = "💰 Wealth"
    media_url: Optional[str] = None
    media_type: Optional[str] = None  # photo, video


class CommentCreate(BaseModel):
    content: str
    parent_id: Optional[str] = None


# ── Feed ───────────────────────────────────────────────
@router.get("/feed")
async def get_feed(
    tab: str = "for_you",   # for_you | following | trending
    limit: int = 20,
    offset: int = 0,
    user: dict = Depends(get_current_user),
):
    """Get social feed posts"""
    try:
        q = db.table("posts") \
            .select(
                "*, "
                "profiles!posts_user_id_fkey(id, full_name, stage, avatar_url, is_verified, subscription_tier), "
                "post_likes(user_id), "
                "post_comments(count), "
                "post_saves(user_id)"
            ) \
            .eq("is_visible", True) \
            .order("created_at", desc=True) \
            .range(offset, offset + limit - 1)

        if tab == "following":
            # Get IDs of users this user follows
            follows = db.table("follows") \
                .select("following_id") \
                .eq("follower_id", user["id"]) \
                .execute().data or []
            following_ids = [f["following_id"] for f in follows]
            if following_ids:
                q = q.in_("user_id", following_ids)
            else:
                return {"posts": [], "tab": tab}

        elif tab == "trending":
            q = db.table("posts") \
                .select(
                    "*, "
                    "profiles!posts_user_id_fkey(id, full_name, stage, avatar_url, is_verified, subscription_tier), "
                    "post_likes(user_id), "
                    "post_comments(count), "
                    "post_saves(user_id)"
                ) \
                .eq("is_visible", True) \
                .order("likes_count", desc=True) \
                .range(offset, offset + limit - 1)

        posts = q.execute().data or []

        # Enrich each post with user-specific flags
        enriched = []
        for p in posts:
            likes = p.get("post_likes") or []
            saves = p.get("post_saves") or []
            p["is_liked"] = any(l["user_id"] == user["id"] for l in likes)
            p["is_saved"] = any(s["user_id"] == user["id"] for s in saves)
            p["likes_count"] = len(likes)
            comments_data = p.get("post_comments") or []
            p["comments_count"] = comments_data[0].get("count", 0) if comments_data else 0
            enriched.append(p)

        return {"posts": enriched, "tab": tab, "offset": offset}
    except Exception as e:
        raise HTTPException(500, f"Failed to load feed: {str(e)}")


# ── Create Post ────────────────────────────────────────
@router.post("")
async def create_post(
    req: PostCreate,
    user: dict = Depends(get_current_user),
):
    try:
        data = {
            "user_id": user["id"],
            "content": req.content,
            "tag": req.tag,
            "is_visible": True,
            "likes_count": 0,
            "shares_count": 0,
        }
        if req.media_url:
            data["media_url"] = req.media_url
            data["media_type"] = req.media_type

        res = db.table("posts").insert(data).execute()
        return {"post": res.data[0] if res.data else {}, "message": "Post shared! 🚀"}
    except Exception as e:
        raise HTTPException(500, f"Failed to create post: {str(e)}")


# ── Get Single Post ────────────────────────────────────
@router.get("/{post_id}")
async def get_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        res = db.table("posts") \
            .select("*, profiles!posts_user_id_fkey(id, full_name, stage, avatar_url, is_verified), post_likes(user_id), post_saves(user_id)") \
            .eq("id", post_id) \
            .single() \
            .execute()
        p = res.data
        if not p:
            raise HTTPException(404, "Post not found")
        p["is_liked"] = any(l["user_id"] == user["id"] for l in (p.get("post_likes") or []))
        p["is_saved"] = any(s["user_id"] == user["id"] for s in (p.get("post_saves") or []))
        return {"post": p}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Like / Unlike ──────────────────────────────────────
@router.post("/{post_id}/like")
async def toggle_like(post_id: str, user: dict = Depends(get_current_user)):
    try:
        # Check if already liked
        existing = db.table("post_likes") \
            .select("id") \
            .eq("post_id", post_id) \
            .eq("user_id", user["id"]) \
            .execute().data

        if existing:
            # Unlike
            db.table("post_likes").delete() \
                .eq("post_id", post_id).eq("user_id", user["id"]).execute()
            db.rpc("decrement_post_likes", {"pid": post_id}).execute()
            return {"liked": False, "message": "Unliked"}
        else:
            # Like
            db.table("post_likes").insert({
                "post_id": post_id, "user_id": user["id"]
            }).execute()
            db.rpc("increment_post_likes", {"pid": post_id}).execute()

            # Notify post owner
            post = db.table("posts").select("user_id").eq("id", post_id).single().execute().data
            if post and post["user_id"] != user["id"]:
                profile = db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
                db.table("notifications").insert({
                    "user_id": post["user_id"],
                    "type": "like",
                    "title": "New like",
                    "message": f"{profile.get('full_name', 'Someone')} liked your post",
                    "data": {"post_id": post_id},
                }).execute()

            return {"liked": True, "message": "Liked! ❤️"}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Save / Unsave ──────────────────────────────────────
@router.post("/{post_id}/save")
async def toggle_save(post_id: str, user: dict = Depends(get_current_user)):
    try:
        existing = db.table("post_saves") \
            .select("id").eq("post_id", post_id).eq("user_id", user["id"]).execute().data
        if existing:
            db.table("post_saves").delete() \
                .eq("post_id", post_id).eq("user_id", user["id"]).execute()
            return {"saved": False}
        else:
            db.table("post_saves").insert({"post_id": post_id, "user_id": user["id"]}).execute()
            return {"saved": True}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Comments ───────────────────────────────────────────
@router.get("/{post_id}/comments")
async def get_comments(
    post_id: str,
    limit: int = 30,
    user: dict = Depends(get_current_user),
):
    try:
        res = db.table("post_comments") \
            .select("*, profiles!post_comments_user_id_fkey(id, full_name, avatar_url, is_verified), comment_likes(user_id)") \
            .eq("post_id", post_id) \
            .is_("parent_id", None) \
            .order("created_at", desc=False) \
            .limit(limit) \
            .execute()
        comments = res.data or []
        for c in comments:
            likes = c.get("comment_likes") or []
            c["is_liked"] = any(l["user_id"] == user["id"] for l in likes)
            c["likes_count"] = len(likes)
        return {"comments": comments}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/{post_id}/comments")
async def add_comment(
    post_id: str,
    req: CommentCreate,
    user: dict = Depends(get_current_user),
):
    try:
        data = {
            "post_id": post_id,
            "user_id": user["id"],
            "content": req.content,
        }
        if req.parent_id:
            data["parent_id"] = req.parent_id

        res = db.table("post_comments").insert(data).execute()

        # Notify post owner
        post = db.table("posts").select("user_id").eq("id", post_id).single().execute().data
        if post and post["user_id"] != user["id"]:
            profile = db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
            db.table("notifications").insert({
                "user_id": post["user_id"],
                "type": "comment",
                "title": "New comment",
                "message": f"{profile.get('full_name', 'Someone')} commented on your post",
                "data": {"post_id": post_id},
            }).execute()

        return {"comment": res.data[0] if res.data else {}}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/comments/{comment_id}/like")
async def like_comment(comment_id: str, user: dict = Depends(get_current_user)):
    try:
        existing = db.table("comment_likes") \
            .select("id").eq("comment_id", comment_id).eq("user_id", user["id"]).execute().data
        if existing:
            db.table("comment_likes").delete() \
                .eq("comment_id", comment_id).eq("user_id", user["id"]).execute()
            return {"liked": False}
        else:
            db.table("comment_likes").insert({"comment_id": comment_id, "user_id": user["id"]}).execute()
            return {"liked": True}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Share ──────────────────────────────────────────────
@router.post("/{post_id}/share")
async def share_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db.rpc("increment_post_shares", {"pid": post_id}).execute()
        return {"message": "Shared! 📤"}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Delete Post ────────────────────────────────────────
@router.delete("/{post_id}")
async def delete_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        post = db.table("posts").select("user_id").eq("id", post_id).single().execute().data
        if not post or post["user_id"] != user["id"]:
            raise HTTPException(403, "Not your post")
        db.table("posts").delete().eq("id", post_id).execute()
        return {"message": "Post deleted"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Follow / Unfollow ──────────────────────────────────
@router.post("/users/{target_id}/follow")
async def toggle_follow(target_id: str, user: dict = Depends(get_current_user)):
    try:
        if target_id == user["id"]:
            raise HTTPException(400, "Cannot follow yourself")

        existing = db.table("follows") \
            .select("id").eq("follower_id", user["id"]).eq("following_id", target_id).execute().data

        if existing:
            db.table("follows").delete() \
                .eq("follower_id", user["id"]).eq("following_id", target_id).execute()
            return {"following": False}
        else:
            db.table("follows").insert({
                "follower_id": user["id"], "following_id": target_id
            }).execute()

            # Notify
            profile = db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
            db.table("notifications").insert({
                "user_id": target_id,
                "type": "follow",
                "title": "New follower",
                "message": f"{profile.get('full_name', 'Someone')} started following you",
                "data": {"user_id": user["id"]},
            }).execute()

            return {"following": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── User Profile ───────────────────────────────────────
@router.get("/users/{user_id}/profile")
async def get_user_profile(user_id: str, user: dict = Depends(get_current_user)):
    try:
        profile = db.table("profiles").select("*").eq("id", user_id).single().execute().data
        if not profile:
            raise HTTPException(404, "User not found")

        posts_count = db.table("posts").select("id", count="exact").eq("user_id", user_id).execute().count or 0
        followers = db.table("follows").select("id", count="exact").eq("following_id", user_id).execute().count or 0
        following = db.table("follows").select("id", count="exact").eq("follower_id", user_id).execute().count or 0
        is_following = bool(db.table("follows").select("id").eq("follower_id", user["id"]).eq("following_id", user_id).execute().data)

        return {
            "profile": profile,
            "stats": {"posts": posts_count, "followers": followers, "following": following},
            "is_following": is_following,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/users/{user_id}/posts")
async def get_user_posts(user_id: str, limit: int = 20, user: dict = Depends(get_current_user)):
    try:
        res = db.table("posts") \
            .select("*, post_likes(user_id), post_comments(count)") \
            .eq("user_id", user_id) \
            .eq("is_visible", True) \
            .order("created_at", desc=True) \
            .limit(limit) \
            .execute()
        posts = res.data or []
        for p in posts:
            likes = p.get("post_likes") or []
            p["is_liked"] = any(l["user_id"] == user["id"] for l in likes)
            p["likes_count"] = len(likes)
        return {"posts": posts}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/users/{user_id}/liked")
async def get_user_liked_posts(user_id: str, limit: int = 20, user: dict = Depends(get_current_user)):
    """Get posts liked by a specific user"""
    try:
        liked = db.table("post_likes") \
            .select("post_id") \
            .eq("user_id", user_id) \
            .order("created_at", desc=True) \
            .limit(limit) \
            .execute()
        post_ids = [l["post_id"] for l in (liked.data or [])]
        if not post_ids:
            return {"posts": []}
        posts_res = db.table("posts") \
            .select("*, profiles(full_name, stage, is_verified, subscription_tier), post_likes(user_id), post_saves(user_id), post_comments(count)") \
            .in_("id", post_ids) \
            .eq("is_visible", True) \
            .execute()
        posts = posts_res.data or []
        for p in posts:
            likes = p.get("post_likes") or []
            saves = p.get("post_saves") or []
            p["is_liked"] = True
            p["likes_count"] = len(likes)
            p["is_saved"] = any(s["user_id"] == user["id"] for s in saves)
        return {"posts": posts}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── User Status / Stories ────────────────────────────────────────
class StatusCreate(BaseModel):
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_type: Optional[str] = "text"   # text | image | video | link
    link_url: Optional[str] = None
    link_title: Optional[str] = None
    background_color: Optional[str] = None
    duration_hours: int = 24


@router.post("/status")
async def create_status(req: StatusCreate, user: dict = Depends(get_current_user)):
    """Create a status update (story) — max 15 active per user"""
    user_id = user["id"]
    try:
        active = db.table("user_status").select("id", count="exact") \
            .eq("user_id", user_id).eq("is_active", True).execute()
        if (active.count or 0) >= 15:
            raise HTTPException(400, "Maximum 15 active status updates allowed")

        from datetime import timezone as tz
        expires = (datetime.now(tz.utc) + timedelta(hours=req.duration_hours)).isoformat()
        saved = db.table("user_status").insert({
            "user_id": user_id,
            "content": req.content,
            "media_url": req.media_url,
            "media_type": req.media_type or "text",
            "link_url": req.link_url,
            "link_title": req.link_title,
            "background_color": req.background_color or "#6C5CE7",
            "expires_at": expires,
            "is_active": True,
            "views_count": 0,
        }).execute()
        return {"status": saved.data[0] if saved.data else {}, "message": "Status posted!"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/status/feed")
async def get_status_feed(user: dict = Depends(get_current_user)):
    """Get status updates from people user follows + own status"""
    user_id = user["id"]
    try:
        from datetime import timezone as tz
        now = datetime.now(tz.utc).isoformat()

        # Get followed user IDs
        follows = db.table("follows").select("following_id") \
            .eq("follower_id", user_id).execute().data or []
        followed_ids = [f["following_id"] for f in follows] + [user_id]

        # Get active statuses
        res = db.table("user_status") \
            .select("*, profiles(id, full_name, avatar_url, is_online)") \
            .in_("user_id", followed_ids) \
            .eq("is_active", True) \
            .gte("expires_at", now) \
            .order("created_at", desc=True) \
            .limit(50).execute()

        statuses = res.data or []

        # Group by user
        grouped: dict = {}
        for s in statuses:
            uid = s["user_id"]
            if uid not in grouped:
                grouped[uid] = {
                    "user_id": uid,
                    "profile": s.get("profiles") or {},
                    "is_own": uid == user_id,
                    "items": [],
                    "has_unseen": False,
                }
            viewed = db.table("status_views").select("id") \
                .eq("status_id", s["id"]).eq("viewer_id", user_id).execute().data
            s["is_viewed"] = bool(viewed)
            if not s["is_viewed"] and uid != user_id:
                grouped[uid]["has_unseen"] = True
            grouped[uid]["items"].append(s)

        result = sorted(grouped.values(), key=lambda x: (not x["is_own"], not x["has_unseen"]))
        return {"users": result, "total": len(result)}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/status/{status_id}/view")
async def view_status(status_id: str, user: dict = Depends(get_current_user)):
    """Mark status as viewed"""
    try:
        db.table("status_views").upsert({
            "status_id": status_id, "viewer_id": user["id"]
        }, on_conflict="status_id,viewer_id").execute()
        db.table("user_status").update({"views_count": db.table("user_status").select("views_count").eq("id", status_id).single().execute().data.get("views_count", 0) + 1}) \
            .eq("id", status_id).execute()
        return {"viewed": True}
    except Exception:
        return {"viewed": True}


@router.delete("/status/{status_id}")
async def delete_status(status_id: str, user: dict = Depends(get_current_user)):
    db.table("user_status").update({"is_active": False}) \
        .eq("id", status_id).eq("user_id", user["id"]).execute()
    return {"deleted": True}


@router.post("/status/upload-media")
async def upload_status_media(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user)
):
    """Upload image/video for status to Supabase Storage"""
    from services.supabase_service import supabase_service
    import uuid as _uuid

    allowed = {"image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/quicktime"}
    ct = file.content_type or "image/jpeg"
    if ct not in allowed:
        raise HTTPException(400, "Only images (JPEG/PNG/WebP/GIF) and videos (MP4/MOV) allowed")

    contents = await file.read()
    if len(contents) > 50 * 1024 * 1024:
        raise HTTPException(400, "File must be under 50MB")

    try:
        sb = supabase_service.client
        ext = ct.split("/")[-1].replace("jpeg", "jpg").replace("quicktime", "mov")
        is_video = ct.startswith("video/")
        bucket = "status-media"
        filename = f"{user['id']}/{_uuid.uuid4()}.{ext}"

        try:
            sb.storage.from_(bucket).upload(
                path=filename, file=contents,
                file_options={"content-type": ct, "upsert": True}
            )
        except Exception:
            sb.storage.from_(bucket).upload(
                path=filename, file=contents,
                file_options={"content-type": ct}
            )

        url = sb.storage.from_(bucket).get_public_url(filename)
        return {
            "url": url if isinstance(url, str) else url.get("publicUrl", ""),
            "media_type": "video" if is_video else "image",
            "content_type": ct,
        }
    except Exception as e:
        raise HTTPException(500, str(e))
