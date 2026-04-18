# backend/routers/groups.py
# Full groups feature: list, create, join/leave, posts, likes, members

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete, and_
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import uuid

from ..database import get_db
from ..models.user import User
from ..models.group import (
    Group, GroupMember, GroupPost, GroupPostLike,
)
from ..routers.auth import get_current_user

router = APIRouter(prefix="/groups", tags=["groups"])


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
    group_id: Optional[str] = None


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _group_dict(group: Group, member_count: int, is_joined: bool) -> dict:
    return {
        "id": str(group.id),
        "name": group.name,
        "description": group.description or "",
        "category": group.category or "",
        "topic": group.topic or "",
        "emoji": group.emoji or "💬",
        "is_private": group.is_private,
        "is_premium": False,
        "members_count": member_count,
        "member_count": member_count,
        "is_joined": is_joined,
        "created_at": group.created_at.isoformat() if group.created_at else None,
    }


def _post_dict(post: GroupPost, author: User, like_count: int, is_liked: bool) -> dict:
    return {
        "id": str(post.id),
        "content": post.content,
        "author_name": author.full_name or author.username if author else "Member",
        "avatar": "🌱",
        "likes_count": like_count,
        "likes": like_count,
        "comments_count": 0,
        "comments": 0,
        "is_liked": is_liked,
        "created_at": post.created_at.isoformat() if post.created_at else None,
    }


def _member_dict(user: User, membership: GroupMember) -> dict:
    return {
        "id": str(user.id),
        "name": user.full_name or user.username or "Member",
        "username": user.username or "",
        "avatar": "🌱",
        "is_admin": membership.is_admin,
        "role": "admin" if membership.is_admin else "member",
        "joined_at": membership.joined_at.isoformat() if membership.joined_at else None,
    }


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups  — list all groups (with membership status)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("")
async def list_groups(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Fetch all groups
    result = await db.execute(select(Group).order_by(Group.created_at.desc()))
    groups = result.scalars().all()

    # For each group get member count and whether current user joined
    out = []
    for g in groups:
        count_res = await db.execute(
            select(func.count()).where(GroupMember.group_id == g.id)
        )
        member_count = count_res.scalar() or 0

        joined_res = await db.execute(
            select(GroupMember).where(
                and_(
                    GroupMember.group_id == g.id,
                    GroupMember.user_id == current_user.id,
                )
            )
        )
        is_joined = joined_res.scalar_one_or_none() is not None
        out.append(_group_dict(g, member_count, is_joined))

    return {"groups": out}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups  — create a group
# ─────────────────────────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_group(
    body: CreateGroupBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Group name is required")

    group = Group(
        id=uuid.uuid4(),
        name=name,
        description=body.description or "",
        category=body.category or "",
        topic=body.topic or "",
        emoji=body.emoji or "💬",
        is_private=body.is_private or False,
        created_by=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(group)
    await db.flush()

    # Auto-join creator as admin
    membership = GroupMember(
        id=uuid.uuid4(),
        group_id=group.id,
        user_id=current_user.id,
        is_admin=True,
        joined_at=datetime.utcnow(),
    )
    db.add(membership)
    await db.commit()
    await db.refresh(group)

    return {"group": _group_dict(group, 1, True), "message": "Group created"}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}  — group detail
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}")
async def get_group(
    group_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        gid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Group not found")

    res = await db.execute(select(Group).where(Group.id == gid))
    group = res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    count_res = await db.execute(
        select(func.count()).where(GroupMember.group_id == gid)
    )
    member_count = count_res.scalar() or 0

    joined_res = await db.execute(
        select(GroupMember).where(
            and_(GroupMember.group_id == gid, GroupMember.user_id == current_user.id)
        )
    )
    is_joined = joined_res.scalar_one_or_none() is not None

    return {"group": _group_dict(group, member_count, is_joined)}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/join  — toggle join/leave
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/join")
async def toggle_join(
    group_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        gid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Group not found")

    res = await db.execute(select(Group).where(Group.id == gid))
    if not res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Group not found")

    existing = await db.execute(
        select(GroupMember).where(
            and_(GroupMember.group_id == gid, GroupMember.user_id == current_user.id)
        )
    )
    membership = existing.scalar_one_or_none()

    if membership:
        await db.execute(
            delete(GroupMember).where(
                and_(GroupMember.group_id == gid, GroupMember.user_id == current_user.id)
            )
        )
        await db.commit()
        return {"joined": False, "message": "Left group"}
    else:
        new_member = GroupMember(
            id=uuid.uuid4(),
            group_id=gid,
            user_id=current_user.id,
            is_admin=False,
            joined_at=datetime.utcnow(),
        )
        db.add(new_member)
        await db.commit()
        return {"joined": True, "message": "Joined group"}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}/posts
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}/posts")
async def list_posts(
    group_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        gid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Group not found")

    result = await db.execute(
        select(GroupPost)
        .where(GroupPost.group_id == gid)
        .order_by(GroupPost.created_at.desc())
        .limit(50)
    )
    posts = result.scalars().all()

    out = []
    for p in posts:
        # Author
        user_res = await db.execute(select(User).where(User.id == p.user_id))
        author = user_res.scalar_one_or_none()

        # Like count
        like_res = await db.execute(
            select(func.count()).where(GroupPostLike.post_id == p.id)
        )
        like_count = like_res.scalar() or 0

        # Is liked by current user
        liked_res = await db.execute(
            select(GroupPostLike).where(
                and_(
                    GroupPostLike.post_id == p.id,
                    GroupPostLike.user_id == current_user.id,
                )
            )
        )
        is_liked = liked_res.scalar_one_or_none() is not None

        out.append(_post_dict(p, author, like_count, is_liked))

    return {"posts": out}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/posts  — create a post
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/posts", status_code=status.HTTP_201_CREATED)
async def create_post(
    group_id: str,
    body: CreatePostBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        gid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Group not found")

    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Content is required")

    post = GroupPost(
        id=uuid.uuid4(),
        group_id=gid,
        user_id=current_user.id,
        content=content,
        created_at=datetime.utcnow(),
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)

    user_res = await db.execute(select(User).where(User.id == current_user.id))
    author = user_res.scalar_one_or_none()

    return {"post": _post_dict(post, author, 0, False), "message": "Post created"}


# ─────────────────────────────────────────────────────────────────────────────
# POST /groups/{group_id}/posts/{post_id}/like  — toggle like
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/{group_id}/posts/{post_id}/like")
async def toggle_like(
    group_id: str,
    post_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Post not found")

    existing = await db.execute(
        select(GroupPostLike).where(
            and_(
                GroupPostLike.post_id == pid,
                GroupPostLike.user_id == current_user.id,
            )
        )
    )
    like = existing.scalar_one_or_none()

    if like:
        await db.execute(
            delete(GroupPostLike).where(
                and_(
                    GroupPostLike.post_id == pid,
                    GroupPostLike.user_id == current_user.id,
                )
            )
        )
        await db.commit()
        return {"liked": False}
    else:
        new_like = GroupPostLike(
            id=uuid.uuid4(),
            post_id=pid,
            user_id=current_user.id,
            created_at=datetime.utcnow(),
        )
        db.add(new_like)
        await db.commit()
        return {"liked": True}


# ─────────────────────────────────────────────────────────────────────────────
# GET /groups/{group_id}/members
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{group_id}/members")
async def list_members(
    group_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        gid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Group not found")

    result = await db.execute(
        select(GroupMember)
        .where(GroupMember.group_id == gid)
        .order_by(GroupMember.is_admin.desc(), GroupMember.joined_at.asc())
        .limit(100)
    )
    memberships = result.scalars().all()

    out = []
    for m in memberships:
        user_res = await db.execute(select(User).where(User.id == m.user_id))
        user = user_res.scalar_one_or_none()
        if user:
            out.append(_member_dict(user, m))

    return {"members": out}

