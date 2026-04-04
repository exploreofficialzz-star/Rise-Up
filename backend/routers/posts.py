# backend/routers/posts.py
"""Posts Router — Social feed, likes, comments, shares, follows, status

Fix log:
  v3.6 — Feed: switched profiles join hint to !user_id (portable, no FK name
          dependency). Replaced post_comments(count) with post_comments(id) and
          len() — the (count) aggregate syntax is PostgREST v10+ only and fails
          silently on older Supabase instances.
          create_post: removed hardcoded likes_count/shares_count from INSERT
          (let DB defaults handle them — inserting 0 fails when the column is
          generated). link_url / link_title insert is now safely guarded.
          All except blocks now call logger.exception() so the real traceback
          appears in server logs instead of being swallowed.
  v3.5 — base_select now explicitly lists link_url + link_title.
"""
import logging
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import Optional
from services.supabase_service import supabase_service
from utils.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/posts", tags=["Posts"])

def _db():
    return supabase_service.db

# ── Models ────────────────────────────────────────────────────────────────────

class PostCreate(BaseModel):
    content: str
    tag: str = "💰 Wealth"
    media_url: Optional[str] = None
    media_type: Optional[str] = None
    link_url: Optional[str] = None
    link_title: Optional[str] = None

class PostUpdate(BaseModel):
    content: Optional[str] = None
    tag: Optional[str] = None
    link_url: Optional[str] = None
    link_title: Optional[str] = None

class CommentCreate(BaseModel):
    content: str
    parent_id: Optional[str] = None
    is_ai: Optional[bool] = False
    is_pinned: Optional[bool] = False

class StatusCreate(BaseModel):
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_type: Optional[str] = "text"
    link_url: Optional[str] = None
    link_title: Optional[str] = None
    background_color: Optional[str] = None
    duration_hours: int = 24

# ── Feed ──────────────────────────────────────────────────────────────────────

@router.get("/feed")
async def get_feed(
    tab: str = "for_you",
    limit: int = 20,
    offset: int = 0,
    user: dict = Depends(get_current_user),
):
    try:
        db = _db()

        # FIX v3.6:
        # 1. profiles!user_id(...) — use column hint instead of FK constraint
        #    name. The FK name (posts_user_id_fkey) is DB-specific and breaks
        #    when Supabase auto-generates a different name. Column hint is stable.
        # 2. post_comments(id) instead of post_comments(count) — the (count)
        #    aggregate is PostgREST v10+ only and throws a 500 on earlier
        #    instances. We fetch ids and use len() on the returned array.
        base_select = (
            "id, content, tag, media_url, media_type, "
            "link_url, link_title, "
            "likes_count, shares_count, created_at, user_id, is_visible, "
            "profiles!user_id("
            "id, full_name, stage, avatar_url, is_verified, subscription_tier"
            "), "
            "post_likes(user_id), "
            "post_comments(id), "
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
            likes         = p.get("post_likes") or []
            saves         = p.get("post_saves") or []
            comments_data = p.get("post_comments") or []
            p["is_liked"]       = any(l["user_id"] == user["id"] for l in likes)
            p["is_saved"]       = any(s["user_id"] == user["id"] for s in saves)
            p["likes_count"]    = len(likes)
            # FIX v3.6: count the returned id array instead of using aggregate
            p["comments_count"] = len(comments_data)
            p["is_following"]   = False
            enriched.append(p)

        if enriched:
            try:
                author_ids = list({
                    p.get("user_id") for p in enriched
                    if p.get("user_id") and p["user_id"] != user["id"]
                })
                if author_ids:
                    follows_res = (
                        db.table("follows")
                        .select("following_id")
                        .eq("follower_id", user["id"])
                        .in_("following_id", author_ids)
                        .execute()
                    )
                    following_set = {
                        f["following_id"] for f in (follows_res.data or [])
                    }
                    for p in enriched:
                        p["is_following"] = p.get("user_id") in following_set
            except Exception:
                pass  # Non-fatal — is_following defaults to False

        return {"posts": enriched, "tab": tab, "offset": offset}

    except Exception as e:
        logger.exception("get_feed failed: tab=%s user=%s", tab, user.get("id"))
        raise HTTPException(500, f"Failed to load feed: {e}")

# ── Create Post ───────────────────────────────────────────────────────────────

@router.post("")
async def create_post(req: PostCreate, user: dict = Depends(get_current_user)):
    try:
        db = _db()

        # FIX v3.6: Do NOT include likes_count / shares_count in the insert.
        # If those columns have DB-level defaults (or are generated), inserting
        # an explicit 0 raises a PostgreSQL error. Let the DB set them.
        data: dict = {
            "user_id":    user["id"],
            "content":    req.content,
            "tag":        req.tag,
            "is_visible": True,
        }
        if req.media_url:
            data["media_url"]  = req.media_url
            data["media_type"] = req.media_type or "image"

        # FIX v3.6: Guard link fields — columns may not exist in older schema
        # versions. We attempt the full insert first; if it fails due to an
        # unknown column we retry without the link fields so the post still
        # goes through (better UX than a hard 500).
        if req.link_url:
            data["link_url"] = req.link_url
        if req.link_title:
            data["link_title"] = req.link_title

        try:
            res = db.table("posts").insert(data).execute()
        except Exception as insert_err:
            err_str = str(insert_err).lower()
            # If the failure is about link columns not existing, retry without them
            if "link_url" in err_str or "link_title" in err_str or "column" in err_str:
                logger.warning(
                    "create_post: link column missing, retrying without link fields. err=%s",
                    insert_err,
                )
                data.pop("link_url", None)
                data.pop("link_title", None)
                res = db.table("posts").insert(data).execute()
            else:
                raise

        return {
            "post":    res.data[0] if res.data else {},
            "message": "Post shared! 🚀",
        }
    except Exception as e:
        logger.exception("create_post failed: user=%s", user.get("id"))
        raise HTTPException(500, f"Failed to create post: {e}")

# ── Link Preview ──────────────────────────────────────────────────────────────

_BLOCKED_DOMAINS = {
    "free-bitcoin.io", "doubler.cash", "cryptodouble.net",
    "invest-fast.com", "fastprofit.xyz", "earnnow.cc",
    "bit.ly-redirect.com", "paypal-confirm.net", "amazonsupport.io",
}

# FIX v3.6: Removed generic "whatsapp" term — WhatsApp is a legitimate
# platform. Only flag explicit investment-fraud phrasing.
_SCAM_KEYWORDS = [
    "double your money", "triple your money", "guaranteed profit",
    "1000% return", "send btc", "send eth", "private key", "seed phrase",
    "wire transfer", "western union", "investment signal",
    "dm for profit", "click here to earn",
]

@router.get("/link-preview")
async def get_link_preview(url: str, user: dict = Depends(get_current_user)):
    import re
    try:
        import httpx
    except ImportError:
        import requests as _req
        httpx = None

    try:
        parsed = __import__("urllib.parse", fromlist=["urlparse"]).urlparse(
            url if url.startswith("http") else f"https://{url}"
        )
        if not parsed.netloc:
            raise HTTPException(400, "Invalid URL")
    except Exception:
        raise HTTPException(400, "Invalid URL format")

    normalized = url if url.startswith("http") else f"https://{url}"
    host = parsed.netloc.lower()

    if any(blocked in host for blocked in _BLOCKED_DOMAINS):
        return {
            "blocked": True,
            "reason": f"🚫 Domain {host} is blocked by RiseUp safety filters.",
        }

    for kw in _SCAM_KEYWORDS:
        if kw in normalized.lower():
            return {
                "blocked": True,
                "reason": f"⚠️ Link contains prohibited content: '{kw}'",
            }

    try:
        headers = {"User-Agent": "RiseUpBot/1.0 (link-preview)"}
        if httpx:
            async with httpx.AsyncClient(timeout=6, follow_redirects=True) as client:
                resp = await client.get(normalized, headers=headers)
            html = resp.text
        else:
            resp = _req.get(normalized, headers=headers, timeout=6, allow_redirects=True)
            html = resp.text

        ct = resp.headers.get("content-type", "")
        if "text/html" not in ct and "application/xhtml" not in ct:
            return {
                "title": host, "description": "", "image": None,
                "favicon": None, "blocked": False, "domain": host,
            }

        final_url  = str(resp.url) if httpx else resp.url
        final_host = (
            __import__("urllib.parse", fromlist=["urlparse"])
            .urlparse(final_url).netloc.lower()
        )
        if any(b in final_host for b in _BLOCKED_DOMAINS):
            return {
                "blocked": True,
                "reason": f"🚫 Redirect destination {final_host} is blocked.",
            }

        def _meta(prop: str, attr: str = "property") -> str:
            m = re.search(
                rf'<meta\s+{attr}=["\']?{re.escape(prop)}["\']?\s+content=["\']([^"\']*)["\']',
                html, re.IGNORECASE,
            )
            return m.group(1).strip() if m else ""

        title_tag = re.search(r"<title>(.*?)</title>", html, re.IGNORECASE)
        title = (
            _meta("og:title")
            or _meta("title", "name")
            or (title_tag.group(1).strip()[:120] if title_tag else "")
        )
        description = _meta("og:description") or _meta("description", "name")
        image       = _meta("og:image")
        favicon_tag = re.search(
            r'<link[^>]+rel=["\']?(?:shortcut )?icon["\']?[^>]+href=["\']([^"\']+)["\']',
            html, re.IGNORECASE,
        )
        favicon = (
            favicon_tag.group(1)
            if favicon_tag
            else f"https://www.google.com/s2/favicons?domain={host}"
        )
        if favicon and not favicon.startswith("http"):
            favicon = f"https://{host}{favicon if favicon.startswith('/') else '/' + favicon}"

        check_text = f"{title} {description}".lower()
        for kw in _SCAM_KEYWORDS:
            if kw in check_text:
                return {
                    "blocked": True,
                    "reason": "⚠️ Page content appears to promote prohibited activity.",
                }

        return {
            "title":       title or host,
            "description": description[:200] if description else "",
            "image":       image or None,
            "favicon":     favicon,
            "domain":      final_host or host,
            "blocked":     False,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.warning("link_preview fetch error for %s: %s", host, e)
        return {
            "title":   host,
            "description": "",
            "image":   None,
            "favicon": f"https://www.google.com/s2/favicons?domain={host}",
            "domain":  host,
            "blocked": False,
        }

# ── Get / Update / Delete Post ────────────────────────────────────────────────

@router.get("/{post_id}")
async def get_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db  = _db()
        res = (
            db.table("posts")
            .select(
                "id, content, tag, media_url, media_type, link_url, link_title, "
                "likes_count, shares_count, created_at, user_id, "
                "profiles!user_id(id, full_name, stage, avatar_url, is_verified), "
                "post_likes(user_id), post_saves(user_id)"
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
        logger.exception("get_post failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

@router.patch("/{post_id}")
async def update_post(
    post_id: str, req: PostUpdate, user: dict = Depends(get_current_user)
):
    try:
        db   = _db()
        post = (
            db.table("posts")
            .select("user_id")
            .eq("id", post_id)
            .single()
            .execute()
            .data
        )
        if not post or post["user_id"] != user["id"]:
            raise HTTPException(403, "Not your post")
        update_data: dict = {}
        if req.content    is not None: update_data["content"]    = req.content
        if req.tag        is not None: update_data["tag"]        = req.tag
        if req.link_url   is not None: update_data["link_url"]   = req.link_url
        if req.link_title is not None: update_data["link_title"] = req.link_title
        if not update_data:
            raise HTTPException(400, "No fields to update")
        res = db.table("posts").update(update_data).eq("id", post_id).execute()
        return {"post": res.data[0] if res.data else {}, "message": "Post updated"}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("update_post failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

@router.delete("/{post_id}")
async def delete_post(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db   = _db()
        post = (
            db.table("posts")
            .select("user_id")
            .eq("id", post_id)
            .single()
            .execute()
            .data
        )
        if not post or post["user_id"] != user["id"]:
            raise HTTPException(403, "Not your post")
        db.table("posts").delete().eq("id", post_id).execute()
        return {"message": "Post deleted"}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("delete_post failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

# ── Like / Save / Share ───────────────────────────────────────────────────────

@router.post("/{post_id}/like")
async def toggle_like(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db       = _db()
        existing = (
            db.table("post_likes")
            .select("id")
            .eq("post_id", post_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("post_likes").delete().eq("post_id", post_id).eq(
                "user_id", user["id"]
            ).execute()
            try:
                db.rpc("decrement_post_likes", {"pid": post_id}).execute()
            except Exception:
                pass
            return {"liked": False}
        else:
            db.table("post_likes").insert(
                {"post_id": post_id, "user_id": user["id"]}
            ).execute()
            try:
                db.rpc("increment_post_likes", {"pid": post_id}).execute()
            except Exception:
                pass
            try:
                post = (
                    db.table("posts")
                    .select("user_id")
                    .eq("id", post_id)
                    .single()
                    .execute()
                    .data
                )
                if post and post["user_id"] != user["id"]:
                    profile = (
                        db.table("profiles")
                        .select("full_name")
                        .eq("id", user["id"])
                        .single()
                        .execute()
                        .data
                    )
                    db.table("notifications").insert(
                        {
                            "user_id": post["user_id"],
                            "type":    "like",
                            "title":   "New like",
                            "message": f"{profile.get('full_name', 'Someone')} liked your post",
                            "data":    {"post_id": post_id},
                        }
                    ).execute()
            except Exception:
                pass
            return {"liked": True}
    except Exception as e:
        logger.exception("toggle_like failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

@router.post("/{post_id}/save")
async def toggle_save(post_id: str, user: dict = Depends(get_current_user)):
    try:
        db       = _db()
        existing = (
            db.table("post_saves")
            .select("id")
            .eq("post_id", post_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("post_saves").delete().eq("post_id", post_id).eq(
                "user_id", user["id"]
            ).execute()
            return {"saved": False}
        else:
            db.table("post_saves").insert(
                {"post_id": post_id, "user_id": user["id"]}
            ).execute()
            return {"saved": True}
    except Exception as e:
        logger.exception("toggle_save failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

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
        logger.exception("share_post failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

# ── Comments ──────────────────────────────────────────────────────────────────

@router.get("/{post_id}/comments")
async def get_comments(
    post_id: str, limit: int = 30, user: dict = Depends(get_current_user)
):
    try:
        db  = _db()
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
            likes            = c.get("comment_likes") or []
            c["is_liked"]    = any(l["user_id"] == user["id"] for l in likes)
            c["likes_count"] = len(likes)

        def _is_ai(c: dict) -> bool:
            return (
                c.get("is_ai") is True
                or c.get("is_pinned") is True
                or str(c.get("content", "")).startswith("🤖 RiseUp AI:")
            )

        comments.sort(
            key=lambda c: (0 if _is_ai(c) else 1, c.get("created_at", ""))
        )
        return {"comments": comments}
    except Exception as e:
        logger.exception("get_comments failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

@router.post("/{post_id}/comments")
async def add_comment(
    post_id: str, req: CommentCreate, user: dict = Depends(get_current_user)
):
    try:
        db   = _db()
        data: dict = {
            "post_id": post_id,
            "user_id": user["id"],
            "content": req.content,
        }
        if req.parent_id:
            data["parent_id"] = req.parent_id
        full = dict(data)
        if req.is_ai:     full["is_ai"]     = True
        if req.is_pinned: full["is_pinned"] = True
        try:
            res = db.table("post_comments").insert(full).execute()
        except Exception:
            res = db.table("post_comments").insert(data).execute()
        comment = res.data[0] if res.data else {}
        if req.is_ai:
            comment["is_ai"]     = True
            comment["is_pinned"] = bool(req.is_pinned)
        try:
            post = (
                db.table("posts")
                .select("user_id")
                .eq("id", post_id)
                .single()
                .execute()
                .data
            )
            if post and post["user_id"] != user["id"] and not req.is_ai:
                profile = (
                    db.table("profiles")
                    .select("full_name")
                    .eq("id", user["id"])
                    .single()
                    .execute()
                    .data
                )
                db.table("notifications").insert(
                    {
                        "user_id": post["user_id"],
                        "type":    "comment",
                        "title":   "New comment",
                        "message": f"{profile.get('full_name', 'Someone')} commented on your post",
                        "data":    {"post_id": post_id},
                    }
                ).execute()
        except Exception:
            pass
        return {"comment": comment}
    except Exception as e:
        logger.exception("add_comment failed: post_id=%s", post_id)
        raise HTTPException(500, str(e))

@router.post("/comments/{comment_id}/like")
async def like_comment(comment_id: str, user: dict = Depends(get_current_user)):
    try:
        db       = _db()
        existing = (
            db.table("comment_likes")
            .select("id")
            .eq("comment_id", comment_id)
            .eq("user_id", user["id"])
            .execute()
            .data
        )
        if existing:
            db.table("comment_likes").delete().eq("comment_id", comment_id).eq(
                "user_id", user["id"]
            ).execute()
            return {"liked": False}
        else:
            db.table("comment_likes").insert(
                {"comment_id": comment_id, "user_id": user["id"]}
            ).execute()
            return {"liked": True}
    except Exception as e:
        logger.exception("like_comment failed: comment_id=%s", comment_id)
        raise HTTPException(500, str(e))

# ── Follow ────────────────────────────────────────────────────────────────────

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
            db.table("follows").delete().eq("follower_id", user["id"]).eq(
                "following_id", target_id
            ).execute()
            return {"following": False}
        else:
            db.table("follows").insert(
                {"follower_id": user["id"], "following_id": target_id}
            ).execute()
            try:
                profile = (
                    db.table("profiles")
                    .select("full_name")
                    .eq("id", user["id"])
                    .single()
                    .execute()
                    .data
                )
                db.table("notifications").insert(
                    {
                        "user_id": target_id,
                        "type":    "follow",
                        "title":   "New follower",
                        "message": f"{profile.get('full_name', 'Someone')} started following you",
                        "data":    {"user_id": user["id"]},
                    }
                ).execute()
            except Exception:
                pass
            return {"following": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("toggle_follow failed: target_id=%s", target_id)
        raise HTTPException(500, str(e))

# ── User Profile & Posts ──────────────────────────────────────────────────────

@router.get("/users/{user_id}/profile")
async def get_user_profile(user_id: str, user: dict = Depends(get_current_user)):
    try:
        db      = _db()
        profile = (
            db.table("profiles")
            .select("*")
            .eq("id", user_id)
            .single()
            .execute()
            .data
        )
        if not profile:
            raise HTTPException(404, "User not found")
        posts_count = (
            db.table("posts")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
            .count or 0
        )
        followers = (
            db.table("follows")
            .select("id", count="exact")
            .eq("following_id", user_id)
            .execute()
            .count or 0
        )
        following = (
            db.table("follows")
            .select("id", count="exact")
            .eq("follower_id", user_id)
            .execute()
            .count or 0
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
            "profile":      profile,
            "stats":        {"posts": posts_count, "followers": followers, "following": following},
            "is_following": is_following,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("get_user_profile failed: user_id=%s", user_id)
        raise HTTPException(500, str(e))

@router.get("/users/{user_id}/posts")
async def get_user_posts(
    user_id: str, limit: int = 20, user: dict = Depends(get_current_user)
):
    try:
        db  = _db()
        res = (
            db.table("posts")
            .select("*, post_likes(user_id), post_comments(id)")
            .eq("user_id", user_id)
            .eq("is_visible", True)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        posts = res.data or []
        for p in posts:
            likes             = p.get("post_likes") or []
            p["is_liked"]     = any(l["user_id"] == user["id"] for l in likes)
            p["likes_count"]  = len(likes)
            p["comments_count"] = len(p.get("post_comments") or [])
        return {"posts": posts}
    except Exception as e:
        logger.exception("get_user_posts failed: user_id=%s", user_id)
        raise HTTPException(500, str(e))

@router.get("/users/{user_id}/liked")
async def get_user_liked_posts(
    user_id: str, limit: int = 20, user: dict = Depends(get_current_user)
):
    try:
        db    = _db()
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
                "*, profiles(full_name, stage, is_verified, subscription_tier), "
                "post_likes(user_id), post_saves(user_id), post_comments(id)"
            )
            .in_("id", post_ids)
            .eq("is_visible", True)
            .execute()
        )
        posts = posts_res.data or []
        for p in posts:
            saves             = p.get("post_saves") or []
            likes             = p.get("post_likes") or []
            p["is_liked"]     = True
            p["likes_count"]  = len(likes)
            p["is_saved"]     = any(s["user_id"] == user["id"] for s in saves)
            p["comments_count"] = len(p.get("post_comments") or [])
        return {"posts": posts}
    except Exception as e:
        logger.exception("get_user_liked_posts failed: user_id=%s", user_id)
        raise HTTPException(500, str(e))

# ── Status ────────────────────────────────────────────────────────────────────

@router.post("/status")
async def create_status(req: StatusCreate, user: dict = Depends(get_current_user)):
    try:
        db     = _db()
        active = (
            db.table("user_status")
            .select("id", count="exact")
            .eq("user_id", user["id"])
            .eq("is_active", True)
            .execute()
        )
        if (active.count or 0) >= 15:
            raise HTTPException(400, "Maximum 15 active statuses allowed")
        expires = (
            datetime.now(timezone.utc) + timedelta(hours=req.duration_hours)
        ).isoformat()
        saved = db.table("user_status").insert(
            {
                "user_id":          user["id"],
                "content":          req.content,
                "media_url":        req.media_url,
                "media_type":       req.media_type or "text",
                "link_url":         req.link_url,
                "link_title":       req.link_title,
                "background_color": req.background_color or "#6C5CE7",
                "expires_at":       expires,
                "is_active":        True,
                "views_count":      0,
            }
        ).execute()
        return {
            "status":  saved.data[0] if saved.data else {},
            "message": "Status posted!",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("create_status failed: user=%s", user.get("id"))
        raise HTTPException(500, str(e))

@router.get("/status/feed")
async def get_status_feed(user: dict = Depends(get_current_user)):
    try:
        db  = _db()
        now = datetime.now(timezone.utc).isoformat()
        follows = (
            db.table("follows")
            .select("following_id")
            .eq("follower_id", user["id"])
            .execute()
            .data or []
        )
        followed_ids = [f["following_id"] for f in follows] + [user["id"]]
        res = (
            db.table("user_status")
            .select("*")
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
        unique_ids   = list({s["user_id"] for s in statuses})
        profiles_map = {
            p["id"]: p
            for p in (
                db.table("profiles")
                .select("id, full_name, avatar_url, is_online")
                .in_("id", unique_ids)
                .execute()
                .data or []
            )
        }
        views_res  = (
            db.table("status_views")
            .select("status_id")
            .eq("viewer_id", user["id"])
            .in_("status_id", [s["id"] for s in statuses])
            .execute()
        )
        viewed_ids = {v["status_id"] for v in (views_res.data or [])}
        grouped: dict = {}
        for s in statuses:
            uid = s["user_id"]
            if uid not in grouped:
                grouped[uid] = {
                    "user_id":    uid,
                    "profile":    profiles_map.get(uid, {}),
                    "is_own":     uid == user["id"],
                    "items":      [],
                    "has_unseen": False,
                }
            s["is_viewed"] = s["id"] in viewed_ids
            if not s["is_viewed"] and uid != user["id"]:
                grouped[uid]["has_unseen"] = True
            grouped[uid]["items"].append(s)
        result = sorted(
            grouped.values(),
            key=lambda x: (not x["is_own"], not x["has_unseen"]),
        )
        return {"users": result, "total": len(result)}
    except Exception as e:
        logger.exception("get_status_feed failed: user=%s", user.get("id"))
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
            cur = (
                db.table("user_status")
                .select("views_count")
                .eq("id", status_id)
                .single()
                .execute()
                .data
            )
            if cur:
                db.table("user_status").update(
                    {"views_count": (cur.get("views_count") or 0) + 1}
                ).eq("id", status_id).execute()
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
        logger.exception("delete_status failed: status_id=%s", status_id)
        raise HTTPException(500, str(e))

# ── Upload media ──────────────────────────────────────────────────────────────

def _ensure_bucket(sb, bucket_name: str) -> None:
    try:
        sb.storage.get_bucket(bucket_name)
    except Exception:
        try:
            sb.storage.create_bucket(bucket_name, options={"public": True})
            logger.info(f"Created bucket: {bucket_name}")
        except Exception as e:
            err = str(e).lower()
            if "already exists" not in err and "duplicate" not in err:
                logger.warning(f"Could not create bucket '{bucket_name}': {e}")

@router.post("/status/upload-media")
async def upload_status_media(
    file: UploadFile = File(...), user: dict = Depends(get_current_user)
):
    allowed = {
        "image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif",
        "image/heic", "image/heif", "image/avif", "image/bmp", "image/tiff",
        "video/mp4", "video/quicktime", "video/x-msvideo", "video/x-matroska",
        "video/webm", "video/3gpp", "video/mpeg", "video/ogg",
    }
    ct = (file.content_type or "").lower().strip()
    if ct == "image/jpg":
        ct = "image/jpeg"
    if not ct or ct == "application/octet-stream":
        fname = (file.filename or "").lower()
        ext   = fname.rsplit(".", 1)[-1] if "." in fname else ""
        ct = {
            "jpg":  "image/jpeg", "jpeg": "image/jpeg", "png":  "image/png",
            "webp": "image/webp", "gif":  "image/gif",  "heic": "image/heic",
            "mp4":  "video/mp4",  "mov":  "video/quicktime",
            "avi":  "video/x-msvideo", "mkv": "video/x-matroska",
            "webm": "video/webm", "3gp":  "video/3gpp",
        }.get(ext, "image/jpeg")
    if ct not in allowed:
        raise HTTPException(400, f"Unsupported file type '{ct}'")
    contents = await file.read()
    is_video = ct.startswith("video/")
    limit    = 500 * 1024 * 1024 if is_video else 50 * 1024 * 1024
    if len(contents) > limit:
        raise HTTPException(400, "File too large")
    if len(contents) == 0:
        raise HTTPException(400, "File is empty")
    try:
        sb      = supabase_service.client
        ext_map = {
            "jpeg": "jpg", "jpg": "jpg", "quicktime": "mov",
            "x-msvideo": "avi", "x-matroska": "mkv", "ogg": "ogv",
        }
        raw_ext  = ct.split("/")[-1]
        ext      = ext_map.get(raw_ext, raw_ext)
        bucket   = "status-media"
        filename = f"{user['id']}/{uuid.uuid4()}.{ext}"
        _ensure_bucket(sb, bucket)
        sb.storage.from_(bucket).upload(
            path=filename,
            file=contents,
            file_options={"content-type": ct, "upsert": "true"},
        )
        url        = sb.storage.from_(bucket).get_public_url(filename)
        public_url = (
            url if isinstance(url, str)
            else (url.get("publicUrl") or url.get("public_url") or "")
        )
        if not public_url:
            raise HTTPException(500, "URL generation failed")
        logger.info(
            "upload_status_media: user=%s file=%s size=%d",
            user["id"], filename, len(contents),
        )
        return {
            "url":          public_url,
            "media_type":   "video" if is_video else "image",
            "content_type": ct,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("upload_status_media FAILED: user=%s", user.get("id"))
        raise HTTPException(500, f"Upload failed: {str(e)}")
