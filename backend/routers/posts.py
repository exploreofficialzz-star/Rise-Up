# backend/routers/posts.py
"""Posts Router — Social feed, likes, comments, shares, follows, status

Fix log:
  v2.1 — get_status_feed: added explicit FK hint for profiles join;
          removed 'is_online' from user_status→profiles select (column
          may not exist on that table, causing 42703 crash);
          all endpoints now use _db() helper instead of module-level capture.
"""
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import Optional
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/posts", tags=["Posts"])


# ── DB helper (always fresh client, never captured at import time) ────
def _db():
    return supabase_service.db


# ── Models ─────────────────────────────────────────────
class PostCreate(BaseModel):
    content: str
    tag: str = "💰 Wealth"
    media_url: Optional[str] = None
    media_type: Optional[str] = None


class CommentCreate(BaseModel):
    content: str
    parent_id: Optional[str] = None


class StatusCreate(BaseModel):
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_type: Optional[str] = "text"
    link_url: Optional[str] = None
    link_title: Optional[str] = None
    background_color: Optional[str] = None
    duration_hours: int = 24


# ── Feed ───────────────────────────────────────────────
@router.get("/feed")
async def get_feed(
    tab: str = "for_you",
    limit: int = 20,
    offset: int = 0,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
        base_select = (
            "*, "
            "profiles!posts_user_id_fkey("
            "id, full_name, stage, avatar_url, is_verified, subscription_tier"
            "), "
            "post_likes(user_id), "
            "post_comments(count), "
            "post_saves(user_id)"
        )

        if tab == "following":
            follows = (
                db.table("follows")
                .select("following_id")
                .eq("follower_id", user["id"])
                .execute()
                .data or []
            )
            following_ids = [f["following_id"] for f in follows]
            if not following_ids:
                return {"posts": [], "tab": tab, "offset": offset}
            posts = (
                db.table("posts")
                .select(base_select)
                .eq("is_visible", True)
                .in_("user_id", following_ids)
                .order("created_at", desc=True)
                .range(offset, offset + limit - 1)
                .execute()
                .data or []
            )

        elif tab == "trending":
            posts = (
                db.table("posts")
                .select(base_select)
                .eq("is_visible", True)
                .order("likes_count", desc=True)
                .range(offset, offset + limit - 1)
                .execute()
                .data or []
            )

        else:  # for_you
            posts = (
                db.table("posts")
                .select(base_select)
                .eq("is_visible", True)
                .order("created_at", desc=True)
                .range(offset, offset + limit - 1)
                .execute()
                .data or []
            )

        enriched = []
        for p in posts:
            likes = p.get("post_likes") or []
            saves = p.get("post_saves") or []
            comments_data = p.get("post_comments") or []
            p["is_liked"] = any(l["user_id"] == user["id"] for l in likes)
            p["is_saved"] = any(s["user_id"] == user["id"] for s in saves)
            p["likes_count"] = len(likes)
            p["comments_count"] = (
                comments_data[0].get("count", 0) if comments_data else 0
            )
            enriched.append(p)

        return {"posts": enriched, "tab": tab, "offset": offset}

    except Exception as e:
        raise HTTPException(500, f"Failed to load feed: {e}")


# ── Create Post ────────────────────────────────────────
@router.post("")
async def create_post(
    req: PostCreate,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
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
        return {
            "post": res.data[0] if res.data else {},
            "message": "Post shared! 🚀",
        }
    except Exception as e:
        raise HTTPException(500, f"Failed to create post: {e}")


# ── Get Single Post ────────────────────────────────────
@router.get("/{post_id}")
async def get_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        res = (
            db.table("posts")
            .select(
                "*, "
                "profiles!posts_user_id_fkey("
                "id, full_name, stage, avatar_url, is_verified"
                "), "
                "post_likes(user_id), "
                "post_saves(user_id)"
            )
            .eq("id", post_id)
            .single()
            .execute()
        )
        p = res.data
        if not p:
            raise HTTPException(404, "Post not found")
        p["is_liked"] = any(
            l["user_id"] == user["id"] for l in (p.get("post_likes") or [])
        )
        p["is_saved"] = any(
            s["user_id"] == user["id"] for s in (p.get("post_saves") or [])
        )
        return {"post": p}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Like / Unlike ──────────────────────────────────────
@router.post("/{post_id}/like")
async def toggle_like(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        existing = (
            db.table("post_likes")
            .select("id")
            .eq("post_id", post_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("post_likes").delete().eq("post_id", post_id).eq("user_id", user["id"]).execute()
            try:
                db.rpc("decrement_post_likes", {"pid": post_id}).execute()
            except Exception:
                pass
            return {"liked": False, "message": "Unliked"}
        else:
            db.table("post_likes").insert({"post_id": post_id, "user_id": user["id"]}).execute()
            try:
                db.rpc("increment_post_likes", {"pid": post_id}).execute()
            except Exception:
                pass

            try:
                post = (
                    db.table("posts").select("user_id").eq("id", post_id).single().execute().data
                )
                if post and post["user_id"] != user["id"]:
                    profile = (
                        db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
                    )
                    db.table("notifications").insert({
                        "user_id": post["user_id"],
                        "type": "like",
                        "title": "New like",
                        "message": f"{profile.get('full_name', 'Someone')} liked your post",
                        "data": {"post_id": post_id},
                    }).execute()
            except Exception:
                pass

            return {"liked": True, "message": "Liked! ❤️"}

    except Exception as e:
        raise HTTPException(500, str(e))


# ── Save / Unsave ──────────────────────────────────────
@router.post("/{post_id}/save")
async def toggle_save(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        existing = (
            db.table("post_saves")
            .select("id")
            .eq("post_id", post_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("post_saves").delete().eq("post_id", post_id).eq("user_id", user["id"]).execute()
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
        db = _db()
        res = (
            db.table("post_comments")
            .select(
                "*, "
                "profiles!post_comments_user_id_fkey("
                "id, full_name, avatar_url, is_verified"
                "), "
                "comment_likes(user_id)"
            )
            .eq("post_id", post_id)
            .is_("parent_id", None)
            .order("created_at", desc=False)
            .limit(limit)
            .execute()
        )
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
        db = _db()
        data: dict = {
            "post_id": post_id,
            "user_id": user["id"],
            "content": req.content,
        }
        if req.parent_id:
            data["parent_id"] = req.parent_id

        res = db.table("post_comments").insert(data).execute()

        try:
            post = (
                db.table("posts").select("user_id").eq("id", post_id).single().execute().data
            )
            if post and post["user_id"] != user["id"]:
                profile = (
                    db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
                )
                db.table("notifications").insert({
                    "user_id": post["user_id"],
                    "type": "comment",
                    "title": "New comment",
                    "message": f"{profile.get('full_name', 'Someone')} commented on your post",
                    "data": {"post_id": post_id},
                }).execute()
        except Exception:
            pass

        return {"comment": res.data[0] if res.data else {}}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/comments/{comment_id}/like")
async def like_comment(comment_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        existing = (
            db.table("comment_likes")
            .select("id")
            .eq("comment_id", comment_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("comment_likes").delete().eq("comment_id", comment_id).eq("user_id", user["id"]).execute()
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
        db = _db()
        try:
            db.rpc("increment_post_shares", {"pid": post_id}).execute()
        except Exception:
            pass
        return {"message": "Shared! 📤"}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Delete Post ────────────────────────────────────────
@router.delete("/{post_id}")
async def delete_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        post = (
            db.table("posts").select("user_id").eq("id", post_id).single().execute().data
        )
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
        db = _db()
        if target_id == user["id"]:
            raise HTTPException(400, "Cannot follow yourself")

        existing = (
            db.table("follows")
            .select("id")
            .eq("follower_id", user["id"])
            .eq("following_id", target_id)
            .execute()
            .data
        )
        if existing:
            db.table("follows").delete().eq("follower_id", user["id"]).eq("following_id", target_id).execute()
            return {"following": False}
        else:
            db.table("follows").insert({
                "follower_id": user["id"],
                "following_id": target_id,
            }).execute()

            try:
                profile = (
                    db.table("profiles").select("full_name").eq("id", user["id"]).single().execute().data
                )
                db.table("notifications").insert({
                    "user_id": target_id,
                    "type": "follow",
                    "title": "New follower",
                    "message": f"{profile.get('full_name', 'Someone')} started following you",
                    "data": {"user_id": user["id"]},
                }).execute()
            except Exception:
                pass

            return {"following": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


# ── User Profile ───────────────────────────────────────
@router.get("/users/{user_id}/profile")
async def get_user_profile(user_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        profile = (
            db.table("profiles").select("*").eq("id", user_id).single().execute().data
        )
        if not profile:
            raise HTTPException(404, "User not found")

        posts_count = (
            db.table("posts").select("id", count="exact").eq("user_id", user_id).execute().count or 0
        )
        followers = (
            db.table("follows").select("id", count="exact").eq("following_id", user_id).execute().count or 0
        )
        following = (
            db.table("follows").select("id", count="exact").eq("follower_id", user_id).execute().count or 0
        )
        is_following = bool(
            db.table("follows")
            .select("id")
            .eq("follower_id", user["id"])
            .eq("following_id", user_id)
            .execute()
            .data
        )

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
async def get_user_posts(
    user_id: str,
    limit: int = 20,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
        res = (
            db.table("posts")
            .select("*, post_likes(user_id), post_comments(count)")
            .eq("user_id", user_id)
            .eq("is_visible", True)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        posts = res.data or []
        for p in posts:
            likes = p.get("post_likes") or []
            p["is_liked"] = any(l["user_id"] == user["id"] for l in likes)
            p["likes_count"] = len(likes)
        return {"posts": posts}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/users/{user_id}/liked")
async def get_user_liked_posts(
    user_id: str,
    limit: int = 20,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()
        liked = (
            db.table("post_likes")
            .select("post_id")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        post_ids = [l["post_id"] for l in (liked.data or [])]
        if not post_ids:
            return {"posts": []}

        posts_res = (
            db.table("posts")
            .select(
                "*, "
                "profiles(full_name, stage, is_verified, subscription_tier), "
                "post_likes(user_id), "
                "post_saves(user_id), "
                "post_comments(count)"
            )
            .in_("id", post_ids)
            .eq("is_visible", True)
            .execute()
        )
        posts = posts_res.data or []
        for p in posts:
            saves = p.get("post_saves") or []
            likes = p.get("post_likes") or []
            p["is_liked"]    = True
            p["likes_count"] = len(likes)
            p["is_saved"]    = any(s["user_id"] == user["id"] for s in saves)
        return {"posts": posts}
    except Exception as e:
        raise HTTPException(500, str(e))


# ── Status / Stories ───────────────────────────────────
@router.post("/status")
async def create_status(req: StatusCreate, user: dict = Depends(get_current_user)):
    user_id = user["id"]
    try:
        db = _db()
        active = (
            db.table("user_status")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .eq("is_active", True)
            .execute()
        )
        if (active.count or 0) >= 15:
            raise HTTPException(400, "Maximum 15 active statuses allowed")

        expires = (
            datetime.now(timezone.utc) + timedelta(hours=req.duration_hours)
        ).isoformat()

        saved = db.table("user_status").insert({
            "user_id":          user_id,
            "content":          req.content,
            "media_url":        req.media_url,
            "media_type":       req.media_type or "text",
            "link_url":         req.link_url,
            "link_title":       req.link_title,
            "background_color": req.background_color or "#6C5CE7",
            "expires_at":       expires,
            "is_active":        True,
            "views_count":      0,
        }).execute()

        return {
            "status": saved.data[0] if saved.data else {},
            "message": "Status posted!",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))


@router.get("/status/feed")
async def get_status_feed(user: dict = Depends(get_current_user)):
    """
    v2.1 fix: use explicit FK hint for profiles join and removed 'is_online'
    from user_status select — that column belongs to profiles, not user_status,
    and caused a 42703 crash when PostgREST tried to resolve the join.
    """
    user_id = user["id"]
    try:
        db = _db()
        now = datetime.now(timezone.utc).isoformat()

        follows = (
            db.table("follows")
            .select("following_id")
            .eq("follower_id", user_id)
            .execute()
            .data or []
        )
        followed_ids = [f["following_id"] for f in follows] + [user_id]

        # ── Explicit FK hint + safe profile columns ──────────────────
        # 'is_online' is NOT a column on user_status; removed from join select
        # profiles!user_status_user_id_fkey resolves the FK unambiguously
        res = (
            db.table("user_status")
            .select(
                "*, "
                "profiles!user_status_user_id_fkey(id, full_name, avatar_url)"
            )
            .in_("user_id", followed_ids)
            .eq("is_active", True)
            .gte("expires_at", now)
            .order("created_at", desc=True)
            .limit(50)
            .execute()
        )
        statuses = res.data or []

        if not statuses:
            return {"users": [], "total": 0}

        # Bulk fetch views — eliminates N+1 DB query
        all_status_ids = [s["id"] for s in statuses]
        views_res = (
            db.table("status_views")
            .select("status_id")
            .eq("viewer_id", user_id)
            .in_("status_id", all_status_ids)
            .execute()
        )
        viewed_ids = {v["status_id"] for v in (views_res.data or [])}

        grouped: dict = {}
        for s in statuses:
            uid = s["user_id"]
            if uid not in grouped:
                grouped[uid] = {
                    "user_id":    uid,
                    "profile":    s.get("profiles") or {},
                    "is_own":     uid == user_id,
                    "items":      [],
                    "has_unseen": False,
                }
            s["is_viewed"] = s["id"] in viewed_ids
            if not s["is_viewed"] and uid != user_id:
                grouped[uid]["has_unseen"] = True
            grouped[uid]["items"].append(s)

        result = sorted(
            grouped.values(),
            key=lambda x: (not x["is_own"], not x["has_unseen"]),
        )
        return {"users": result, "total": len(result)}

    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/status/{status_id}/view")
async def view_status(status_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        db.table("status_views").upsert(
            {"status_id": status_id, "viewer_id": user["id"]},
            on_conflict="status_id,viewer_id",
        ).execute()

        try:
            db.rpc("increment_status_views", {"sid": status_id}).execute()
        except Exception:
            current = (
                db.table("user_status")
                .select("views_count")
                .eq("id", status_id)
                .single()
                .execute()
                .data
            )
            if current:
                db.table("user_status").update({
                    "views_count": (current.get("views_count") or 0) + 1
                }).eq("id", status_id).execute()

        return {"viewed": True}
    except Exception:
        return {"viewed": True}


@router.delete("/status/{status_id}")
async def delete_status(status_id: str, user: dict = Depends(get_current_user)):
    try:
        db = _db()
        db.table("user_status").update({"is_active": False}).eq(
            "id", status_id
        ).eq("user_id", user["id"]).execute()
        return {"deleted": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/status/upload-media")
async def upload_status_media(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    allowed = {
        "image/jpeg", "image/png", "image/webp", "image/gif",
        "video/mp4", "video/quicktime",
    }
    ct = file.content_type or "image/jpeg"
    if ct not in allowed:
        raise HTTPException(
            400, "Only images (JPEG/PNG/WebP/GIF) and videos (MP4/MOV) allowed"
        )

    contents = await file.read()
    if len(contents) > 50 * 1024 * 1024:
        raise HTTPException(400, "File must be under 50MB")

    try:
        sb = supabase_service.client   # uses .client property alias
        ext = (
            ct.split("/")[-1]
            .replace("jpeg", "jpg")
            .replace("quicktime", "mov")
        )
        is_video = ct.startswith("video/")
        bucket   = "status-media"
        filename = f"{user['id']}/{uuid.uuid4()}.{ext}"

        sb.storage.from_(bucket).upload(
            path=filename,
            file=contents,
            file_options={"content-type": ct, "upsert": "true"},
        )

        url = sb.storage.from_(bucket).get_public_url(filename)
        public_url = url if isinstance(url, str) else url.get("publicUrl", "")

        return {
            "url":          public_url,
            "media_type":   "video" if is_video else "image",
            "content_type": ct,
        }
    except Exception as e:
        raise HTTPException(500, str(e))
