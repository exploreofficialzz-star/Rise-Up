# backend/routers/groups.py
# Full groups feature: list, create, join/leave, posts, likes, members
# Uses Supabase client (matches project architecture — no SQLAlchemy)

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import uuid

from services.supabase_service import supabase_service
from routers.auth import get_current_user

router = APIRouter(prefix="/groups", tags=["groups"])

db = supabase_service.db


# ─────────────────────────────────────────────────────────────────────────────
# Schemas
# ─────────────────────────────────────────────────────────────────────────────

class CreateGroupBody(BaseModel):
    name: str
    description: Optional[str] = ""
    category: Optional[str] = ""
    topic: Optional[str] = ""
    emoji: Optional[str] = "💬"
    is_private: Optional[bool] = False


class CreatePostBody(BaseModel):
    content: str


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _group_dict(group: dict, member_count: int, is_joined: bool) -> dict:
    return {
        "id":            group.get("id"),
        "name":          group.get("name", ""),
        "description":   group.get("description", ""),
        "category":      group.get("category", ""),
        "topic":         group.get("topic", ""),
        "emoji":         group.get("emoji", "💬"),
        "is_private":    group.get("is_private", False),
        "is_premium":    False,
        "members_count": member_count,
        "member_count":  member_count,
        "is_joined":     is_joined,
        "created_at":    group.get("created_at"),
    }


def _post_dict(post: dict, author: dict, like_count: int, is_liked: bool) -> dict:
    author_name = "Member"
    if author:
        author_name = author.get("full_name") or author.get("username") or "Member"
    return {
        "id":             post.get("id"),
        "content":        post.get("content", ""),
        "author_name":    author_name,
        "avatar":         "🌱",
        "likes_count":    like_count,
        "likes":          like_count,
        "comments_count": 0,
        "comments":       0,
        "is_liked":       is_liked,
        "created_at":     post.get("created_at"),
    }


def _member_dict(user: dict, membership: dict) -> dict:
    return {
        "id":        user.get("id"),
        "name":      user.get("full_name") or user.get("username") or "Member",
        "username":  user.get("username", ""),
        "avatar":    "🌱",
        "is_admin":  membership.get("is_admin", False),
        "role":      "admin" if membership.get("is_admin") else "member",
        "joined_at": membership.get("joined_at"),
    }


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups
# ─────────────────────────────────────────────────────────────────────────────

@router.get("")
async def list_groups(current_user: dict = Depends(get_current_user)):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])

    res = db.table("groups").select("*").order("created_at", desc=True).execute()
    groups = res.data or []

    out = []
    for g in groups:
        gid = str(g["id"])

        count_res = (
            db.table("group_members")
            .select("id", count="exact")
            .eq("group_id", gid)
            .execute()
        )
        member_count = count_res.count or 0

        joined_res = (
            db.table("group_members")
            .select("id")
            .eq("group_id", gid)
            .eq("user_id", user_id)
            .execute()
        )
        is_joined = bool(joined_res.data)
        out.append(_group_dict(g, member_count, is_joined))

    return {"groups": out}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups
# ─────────────────────────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_group(
    body: CreateGroupBody,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Group name is required")

    group_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()

    res = db.table("groups").insert({
        "id":          group_id,
        "name":        name,
        "description": body.description or "",
        "category":    body.category or "",
        "topic":       body.topic or "",
        "emoji":       body.emoji or "💬",
        "is_private":  body.is_private or False,
        "created_by":  user_id,
        "created_at":  now,
    }).execute()

    if not res.data:
        raise HTTPException(status_code=500, detail="Failed to create group")

    group = res.data[0]

    db.table("group_members").insert({
        "id":        str(uuid.uuid4()),
        "group_id":  group_id,
        "user_id":   user_id,
        "is_admin":  True,
        "joined_at": now,
    }).execute()

    return {"group": _group_dict(group, 1, True), "message": "Group created"}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}")
async def get_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])

    res = db.table("groups").select("*").eq("id", group_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Group not found")
    group = res.data[0]

    count_res = (
        db.table("group_members")
        .select("id", count="exact")
        .eq("group_id", group_id)
        .execute()
    )
    member_count = count_res.count or 0

    joined_res = (
        db.table("group_members")
        .select("id")
        .eq("group_id", group_id)
        .eq("user_id", user_id)
        .execute()
    )
    is_joined = bool(joined_res.data)

    return {"group": _group_dict(group, member_count, is_joined)}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/join
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/join")
async def toggle_join(
    group_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])

    res = db.table("groups").select("id").eq("id", group_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Group not found")

    existing = (
        db.table("group_members")
        .select("id")
        .eq("group_id", group_id)
        .eq("user_id", user_id)
        .execute()
    )

    if existing.data:
        db.table("group_members").delete().eq("group_id", group_id).eq("user_id", user_id).execute()
        return {"joined": False, "message": "Left group"}
    else:
        db.table("group_members").insert({
            "id":        str(uuid.uuid4()),
            "group_id":  group_id,
            "user_id":   user_id,
            "is_admin":  False,
            "joined_at": datetime.utcnow().isoformat(),
        }).execute()
        return {"joined": True, "message": "Joined group"}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}/posts
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}/posts")
async def list_posts(
    group_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])

    res = (
        db.table("group_posts")
        .select("*")
        .eq("group_id", group_id)
        .order("created_at", desc=True)
        .limit(50)
        .execute()
    )
    posts = res.data or []

    out = []
    for p in posts:
        author_res = (
            db.table("profiles").select("id, full_name, username").eq("id", p["user_id"]).execute()
        )
        author = author_res.data[0] if author_res.data else {}

        like_res = (
            db.table("group_post_likes")
            .select("id", count="exact")
            .eq("post_id", p["id"])
            .execute()
        )
        like_count = like_res.count or 0

        liked_res = (
            db.table("group_post_likes")
            .select("id")
            .eq("post_id", p["id"])
            .eq("user_id", user_id)
            .execute()
        )
        is_liked = bool(liked_res.data)
        out.append(_post_dict(p, author, like_count, is_liked))

    return {"posts": out}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/posts
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/posts", status_code=status.HTTP_201_CREATED)
async def create_post(
    group_id: str,
    body: CreatePostBody,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])
    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Content is required")

    res = db.table("group_posts").insert({
        "id":         str(uuid.uuid4()),
        "group_id":   group_id,
        "user_id":    user_id,
        "content":    content,
        "created_at": datetime.utcnow().isoformat(),
    }).execute()

    if not res.data:
        raise HTTPException(status_code=500, detail="Failed to create post")

    post = res.data[0]

    author_res = (
        db.table("profiles").select("id, full_name, username").eq("id", user_id).execute()
    )
    author = author_res.data[0] if author_res.data else {}

    return {"post": _post_dict(post, author, 0, False), "message": "Post created"}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/posts/{post_id}/like
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/posts/{post_id}/like")
async def toggle_like(
    group_id: str,
    post_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = str(current_user.id if hasattr(current_user, "id") else current_user["id"])

    existing = (
        db.table("group_post_likes")
        .select("id")
        .eq("post_id", post_id)
        .eq("user_id", user_id)
        .execute()
    )

    if existing.data:
        db.table("group_post_likes").delete().eq("post_id", post_id).eq("user_id", user_id).execute()
        return {"liked": False}
    else:
        db.table("group_post_likes").insert({
            "id":         str(uuid.uuid4()),
            "post_id":    post_id,
            "user_id":    user_id,
            "created_at": datetime.utcnow().isoformat(),
        }).execute()
        return {"liked": True}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}/members
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}/members")
async def list_members(
    group_id: str,
    current_user: dict = Depends(get_current_user),
):
    res = (
        db.table("group_members")
        .select("*")
        .eq("group_id", group_id)
        .order("is_admin", desc=True)
        .limit(100)
        .execute()
    )
    memberships = res.data or []

    out = []
    for m in memberships:
        user_res = (
            db.table("profiles")
            .select("id, full_name, username")
            .eq("id", m["user_id"])
            .execute()
        )
        user = user_res.data[0] if user_res.data else None
        if user:
            out.append(_member_dict(user, m))

    return {"members": out}
