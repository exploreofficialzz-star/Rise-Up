"""
Collaboration Router — Income goal partnerships
Users create or join collaborations to build bigger income together.
"""
import logging
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, GENERAL_LIMIT, AI_LIMIT
from services.supabase_service import supabase_service
from services.ai_service import ai_service
from utils.auth import get_current_user

router = APIRouter(prefix="/collaborations", tags=["Collaboration"])
logger = logging.getLogger(__name__)


class CreateCollabRequest(BaseModel):
    title: str
    description: str
    income_type: str = "other"
    emoji: str = "🤝"
    tag: str = ""
    potential_revenue: str = ""
    roles: List[str] = []
    max_members: int = 5
    revenue_split: str = "equal"


class JoinRequest(BaseModel):
    role_name: Optional[str] = None


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_collabs(
    request: Request,
    status: str = "open",
    income_type: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """List all open collaborations"""
    sb = supabase_service.client
    query = sb.table("collaborations").select(
        "*, profiles!collaborations_owner_id_fkey(full_name, avatar_url, stage, is_verified)"
    ).eq("status", status)

    if income_type:
        query = query.eq("income_type", income_type)

    result = query.order("created_at", desc=True).limit(50).execute()
    collabs = result.data or []

    # Check which ones user has joined
    user_id = user["id"]
    for c in collabs:
        members = sb.table("collaboration_members").select("status").eq(
            "collaboration_id", c["id"]).eq("user_id", user_id).execute()
        c["user_status"] = members.data[0]["status"] if members.data else None

    return {"collaborations": collabs}


@router.get("/mine")
@limiter.limit(GENERAL_LIMIT)
async def my_collabs(request: Request, user: dict = Depends(get_current_user)):
    """Get collabs owned by user + collabs user has joined"""
    user_id = user["id"]
    sb = supabase_service.client

    # Owned
    owned = sb.table("collaborations").select("*").eq(
        "owner_id", user_id).order("created_at", desc=True).execute()

    # Joined
    joined_ids = sb.table("collaboration_members").select(
        "collaboration_id").eq("user_id", user_id).eq("status", "accepted").execute()
    joined_collab_ids = [m["collaboration_id"] for m in (joined_ids.data or [])]

    joined = []
    if joined_collab_ids:
        joined_res = sb.table("collaborations").select("*").in_(
            "id", joined_collab_ids).execute()
        joined = joined_res.data or []

    # Pending requests
    pending_ids = sb.table("collaboration_members").select(
        "collaboration_id").eq("user_id", user_id).eq("status", "pending").execute()
    pending_collab_ids = [m["collaboration_id"] for m in (pending_ids.data or [])]
    pending = []
    if pending_collab_ids:
        pending_res = sb.table("collaborations").select("*").in_(
            "id", pending_collab_ids).execute()
        pending = pending_res.data or []

    return {
        "owned": owned.data or [],
        "joined": joined,
        "pending": pending,
    }


@router.post("/")
@limiter.limit(GENERAL_LIMIT)
async def create_collab(
    req: CreateCollabRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Create a new collaboration"""
    user_id = user["id"]
    sb = supabase_service.client

    result = sb.table("collaborations").insert({
        "owner_id": user_id,
        "title": req.title,
        "description": req.description,
        "income_type": req.income_type,
        "emoji": req.emoji,
        "tag": req.tag,
        "potential_revenue": req.potential_revenue,
        "roles_needed": len(req.roles),
        "roles_filled": 0,
        "max_members": req.max_members,
        "revenue_split": req.revenue_split,
        "status": "open",
    }).execute()

    collab = result.data[0]
    collab_id = collab["id"]

    # Save roles
    if req.roles:
        sb.table("collaboration_roles").insert([{
            "collaboration_id": collab_id,
            "role_name": role,
            "is_filled": False,
        } for role in req.roles]).execute()

    return {"collaboration": collab, "message": "Collaboration created!"}


@router.get("/{collab_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_collab(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Get full collaboration details"""
    sb = supabase_service.client
    user_id = user["id"]

    collab = sb.table("collaborations").select(
        "*, profiles!collaborations_owner_id_fkey(full_name, avatar_url, stage, is_verified)"
    ).eq("id", collab_id).single().execute()

    if not collab.data:
        raise HTTPException(404, "Collaboration not found")

    roles = sb.table("collaboration_roles").select("*").eq(
        "collaboration_id", collab_id).execute()

    members = sb.table("collaboration_members").select(
        "*, profiles!collaboration_members_user_id_fkey(full_name, avatar_url, stage)"
    ).eq("collaboration_id", collab_id).eq("status", "accepted").execute()

    user_status = sb.table("collaboration_members").select("status").eq(
        "collaboration_id", collab_id).eq("user_id", user_id).execute()

    return {
        "collaboration": collab.data,
        "roles": roles.data or [],
        "members": members.data or [],
        "user_status": user_status.data[0]["status"] if user_status.data else None,
        "is_owner": collab.data.get("owner_id") == user_id,
    }


@router.post("/{collab_id}/request")
@limiter.limit(GENERAL_LIMIT)
async def request_to_join(
    collab_id: str,
    req: JoinRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Request to join a collaboration"""
    user_id = user["id"]
    sb = supabase_service.client

    # Check not already a member
    existing = sb.table("collaboration_members").select("id, status").eq(
        "collaboration_id", collab_id).eq("user_id", user_id).execute()

    if existing.data:
        status = existing.data[0]["status"]
        if status == "accepted":
            raise HTTPException(400, "Already a member")
        if status == "pending":
            raise HTTPException(400, "Request already sent")

    # Get role id if specified
    role_id = None
    if req.role_name:
        role = sb.table("collaboration_roles").select("id").eq(
            "collaboration_id", collab_id).eq("role_name", req.role_name).eq(
            "is_filled", False).execute()
        if role.data:
            role_id = role.data[0]["id"]

    sb.table("collaboration_members").insert({
        "collaboration_id": collab_id,
        "user_id": user_id,
        "role_id": role_id,
        "status": "pending",
    }).execute()

    return {"message": "Request sent! The owner will review your application."}


@router.patch("/{collab_id}/members/{member_user_id}")
@limiter.limit(GENERAL_LIMIT)
async def respond_to_request(
    collab_id: str,
    member_user_id: str,
    action: str,  # accept | reject
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Accept or reject a join request (owner only)"""
    user_id = user["id"]
    sb = supabase_service.client

    # Verify ownership
    collab = sb.table("collaborations").select("owner_id, roles_filled, max_members").eq(
        "id", collab_id).single().execute()
    if not collab.data or collab.data["owner_id"] != user_id:
        raise HTTPException(403, "Only the collaboration owner can do this")

    if action not in ("accept", "reject"):
        raise HTTPException(400, "action must be 'accept' or 'reject'")

    new_status = "accepted" if action == "accept" else "rejected"
    sb.table("collaboration_members").update({"status": new_status}).eq(
        "collaboration_id", collab_id).eq("user_id", member_user_id).execute()

    if action == "accept":
        new_filled = (collab.data.get("roles_filled") or 0) + 1
        sb.table("collaborations").update({"roles_filled": new_filled}).eq("id", collab_id).execute()

    return {"message": f"Member {action}ed successfully"}


@router.delete("/{collab_id}")
@limiter.limit(GENERAL_LIMIT)
async def close_collab(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Close a collaboration (owner only)"""
    sb = supabase_service.client
    sb.table("collaborations").update({"status": "closed"}).eq(
        "id", collab_id).eq("owner_id", user["id"]).execute()
    return {"message": "Collaboration closed"}


@router.post("/{collab_id}/ai-match")
@limiter.limit(AI_LIMIT)
async def ai_match_roles(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """AI suggests the best roles for a collaboration goal"""
    sb = supabase_service.client
    collab = sb.table("collaborations").select("title, description, income_type").eq(
        "id", collab_id).single().execute()

    if not collab.data:
        raise HTTPException(404, "Collaboration not found")

    c = collab.data
    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Collaboration: {c['title']}\nType: {c['income_type']}\nDescription: {c['description']}\n\nWhat are the 3-5 most important roles needed for this collaboration to succeed? Return JSON: {{\"roles\": [{{\"name\": \"\", \"description\": \"\", \"skills_needed\": []}}]}}"}],
        system="You are a collaboration strategist. Return ONLY valid JSON. No markdown.",
        max_tokens=600,
    )

    import json
    raw = result["content"].strip().strip("```json").strip("```").strip()
    try:
        roles_data = json.loads(raw)
    except Exception:
        roles_data = {"roles": []}

    return {"suggested_roles": roles_data.get("roles", []), "model": result.get("model")}
