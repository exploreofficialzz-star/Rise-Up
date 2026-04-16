"""
Collaboration Router — Income goal partnerships  v2.0
Production-ready: fixed Supabase join queries, batch membership
lookups, auto emoji/tag derivation, proper error handling.
"""
import logging
from typing import Optional, List, Dict

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, GENERAL_LIMIT, AI_LIMIT
from services.supabase_service import supabase_service
from services.ai_service import ai_service
from utils.auth import get_current_user

router = APIRouter(prefix="/collaborations", tags=["Collaboration"])
logger = logging.getLogger(__name__)

# ─── Income type metadata ─────────────────────────────────────────────────────
_INCOME_META: Dict[str, tuple] = {
    "youtube":   ("▶️",  "▶️ YouTube"),
    "freelance": ("💻",  "💻 Agency"),
    "ecommerce": ("🛍️", "🛍️ eCommerce"),
    "content":   ("📝",  "✍️ Content"),
    "affiliate": ("🔗",  "🔗 Affiliate"),
    "physical":  ("🏪",  "🏪 Physical"),
    "app":       ("📱",  "📱 SaaS"),
    "education": ("📚",  "📚 Edu"),
    "music":     ("🎵",  "🎵 Music"),
    "creative":  ("🎨",  "🎨 Creative"),
    "other":     ("🤝",  "🤝 Other"),
}


def _get_meta(income_type: str) -> tuple:
    return _INCOME_META.get(income_type, _INCOME_META["other"])


# ─── Supabase helpers ─────────────────────────────────────────────────────────

def _enrich_profiles(sb, collabs: list) -> list:
    """
    Separately fetch profile data for collab owners and attach it.
    Called as a fallback when the joined select fails.
    """
    if not collabs:
        return collabs
    owner_ids = list({c["owner_id"] for c in collabs if c.get("owner_id")})
    if not owner_ids:
        return collabs
    try:
        res = sb.table("profiles").select(
            "id, full_name, avatar_url, is_verified"
        ).in_("id", owner_ids).execute()
        profiles_map = {p["id"]: p for p in (res.data or [])}
    except Exception as e:
        logger.warning(f"_enrich_profiles: profile fetch failed — {e}")
        profiles_map = {}

    for c in collabs:
        c["profiles"] = profiles_map.get(c.get("owner_id"), {})
    return collabs


def _fetch_collabs_with_profiles(sb, query_builder) -> list:
    """
    Try joined select first (fast path). If that fails because of FK name
    issues or schema differences, fall back to a plain select + separate
    profile fetch (slow but reliable).
    """
    # Fast path — Supabase auto-detects FK when there is exactly one FK
    # from collaborations.owner_id → profiles.id
    try:
        result = query_builder(
            sb.table("collaborations").select(
                "*, profiles(full_name, avatar_url, is_verified)"
            )
        ).execute()
        return result.data or []
    except Exception as e:
        logger.warning(f"Joined select failed ({e}), falling back to two-query approach")

    # Slow path — plain select then enrich
    try:
        result = query_builder(
            sb.table("collaborations").select("*")
        ).execute()
        return _enrich_profiles(sb, result.data or [])
    except Exception as e2:
        logger.error(f"Fallback plain select also failed: {e2}")
        return []


def _batch_user_status(sb, user_id: str, collab_ids: list) -> dict:
    """Return {collab_id: status} for the given user across all collab IDs."""
    if not collab_ids:
        return {}
    try:
        res = sb.table("collaboration_members").select(
            "collaboration_id, status"
        ).eq("user_id", user_id).in_("collaboration_id", collab_ids).execute()
        return {m["collaboration_id"]: m["status"] for m in (res.data or [])}
    except Exception as e:
        logger.warning(f"_batch_user_status failed: {e}")
        return {}


# ─── Request schemas ──────────────────────────────────────────────────────────

class CreateCollabRequest(BaseModel):
    title: str
    description: str = ""
    income_type: str = "other"
    emoji: str = ""          # auto-derived if empty
    tag: str = ""            # auto-derived if empty
    potential_revenue: str = ""
    roles: List[str] = []
    max_members: int = 5
    revenue_split: str = "equal"


class JoinRequest(BaseModel):
    role_name: Optional[str] = None


class MemberActionRequest(BaseModel):
    action: str  # "accept" | "reject"


# ─── Routes ───────────────────────────────────────────────────────────────────

@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_collabs(
    request: Request,
    status: str = "open",
    income_type: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """List all open collaborations with owner profiles."""
    sb = supabase_service.client
    user_id = user["id"]

    def _apply_filters(q):
        q = q.eq("status", status)
        if income_type:
            q = q.eq("income_type", income_type)
        return q.order("created_at", desc=True).limit(50)

    collabs = _fetch_collabs_with_profiles(sb, _apply_filters)

    # Attach current user's membership status in one batch query
    collab_ids = [c["id"] for c in collabs if c.get("id")]
    status_map = _batch_user_status(sb, user_id, collab_ids)
    for c in collabs:
        c["user_status"] = status_map.get(c.get("id"))

    return {"collaborations": collabs, "total": len(collabs)}


@router.get("/mine")
@limiter.limit(GENERAL_LIMIT)
async def my_collabs(request: Request, user: dict = Depends(get_current_user)):
    """Get collabs owned by the user plus any they've joined or requested."""
    user_id = user["id"]
    sb = supabase_service.client

    # ── Owned ────────────────────────────────────────────────────────────────
    try:
        owned_res = sb.table("collaborations").select("*").eq(
            "owner_id", user_id
        ).order("created_at", desc=True).execute()
        owned = owned_res.data or []
    except Exception as e:
        logger.error(f"my_collabs owned fetch failed: {e}")
        owned = []

    # ── Memberships (accepted + pending) ─────────────────────────────────────
    try:
        memberships_res = sb.table("collaboration_members").select(
            "collaboration_id, status"
        ).eq("user_id", user_id).execute()
        memberships = memberships_res.data or []
    except Exception as e:
        logger.error(f"my_collabs memberships fetch failed: {e}")
        memberships = []

    accepted_ids = [m["collaboration_id"] for m in memberships if m["status"] == "accepted"]
    pending_ids  = [m["collaboration_id"] for m in memberships if m["status"] == "pending"]

    def _fetch_collab_batch(ids):
        if not ids:
            return []
        try:
            res = sb.table("collaborations").select("*").in_("id", ids).execute()
            return res.data or []
        except Exception as e:
            logger.warning(f"_fetch_collab_batch failed: {e}")
            return []

    joined  = _fetch_collab_batch(accepted_ids)
    pending = _fetch_collab_batch(pending_ids)

    return {"owned": owned, "joined": joined, "pending": pending}


@router.get("/{collab_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_collab(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Full collaboration detail: collab + roles + members + user status."""
    sb = supabase_service.client
    user_id = user["id"]

    # Collab
    try:
        collab_res = sb.table("collaborations").select("*").eq(
            "id", collab_id
        ).single().execute()
    except Exception as e:
        logger.error(f"get_collab fetch failed: {e}")
        raise HTTPException(status_code=404, detail="Collaboration not found")

    if not collab_res.data:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    collab = collab_res.data

    # Owner profile
    owner_id = collab.get("owner_id")
    if owner_id:
        try:
            profile_res = sb.table("profiles").select(
                "id, full_name, avatar_url, is_verified"
            ).eq("id", owner_id).single().execute()
            collab["profiles"] = profile_res.data or {}
        except Exception:
            collab["profiles"] = {}
    else:
        collab["profiles"] = {}

    # Roles
    try:
        roles_res = sb.table("collaboration_roles").select("*").eq(
            "collaboration_id", collab_id
        ).execute()
        roles = roles_res.data or []
    except Exception:
        roles = []

    # Accepted members (with profile)
    try:
        members_res = sb.table("collaboration_members").select(
            "*, profiles(full_name, avatar_url)"
        ).eq("collaboration_id", collab_id).eq("status", "accepted").execute()
        members = members_res.data or []
    except Exception:
        try:
            members_res = sb.table("collaboration_members").select("*").eq(
                "collaboration_id", collab_id
            ).eq("status", "accepted").execute()
            members = members_res.data or []
        except Exception:
            members = []

    # Current user's status
    try:
        user_mem_res = sb.table("collaboration_members").select("status").eq(
            "collaboration_id", collab_id
        ).eq("user_id", user_id).execute()
        user_status = user_mem_res.data[0]["status"] if user_mem_res.data else None
    except Exception:
        user_status = None

    # Pending join requests (only visible to owner)
    pending_requests = []
    if collab.get("owner_id") == user_id:
        try:
            pending_res = sb.table("collaboration_members").select(
                "*, profiles(full_name, avatar_url)"
            ).eq("collaboration_id", collab_id).eq("status", "pending").execute()
            pending_requests = pending_res.data or []
        except Exception:
            pass

    return {
        "collaboration":    collab,
        "roles":            roles,
        "members":          members,
        "user_status":      user_status,
        "is_owner":         collab.get("owner_id") == user_id,
        "pending_requests": pending_requests,
    }


@router.post("/")
@limiter.limit(GENERAL_LIMIT)
async def create_collab(
    req: CreateCollabRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Create a new collaboration."""
    if not req.title.strip():
        raise HTTPException(status_code=422, detail="Title is required")

    user_id = user["id"]
    sb = supabase_service.client

    # Auto-derive emoji and tag from income_type if not supplied by client
    default_emoji, default_tag = _get_meta(req.income_type)
    emoji = req.emoji.strip() or default_emoji
    tag   = req.tag.strip()   or default_tag

    try:
        result = sb.table("collaborations").insert({
            "owner_id":         user_id,
            "title":            req.title.strip(),
            "description":      req.description.strip(),
            "income_type":      req.income_type,
            "emoji":            emoji,
            "tag":              tag,
            "potential_revenue": req.potential_revenue.strip(),
            "roles_needed":     len(req.roles),
            "roles_filled":     0,
            "max_members":      req.max_members,
            "revenue_split":    req.revenue_split,
            "status":           "open",
        }).execute()
    except Exception as e:
        logger.error(f"create_collab insert failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to create collaboration. Please try again.")

    if not result.data:
        raise HTTPException(status_code=500, detail="Collaboration creation returned no data")

    collab    = result.data[0]
    collab_id = collab["id"]

    # Insert roles
    if req.roles:
        try:
            sb.table("collaboration_roles").insert([
                {"collaboration_id": collab_id, "role_name": r.strip(), "is_filled": False}
                for r in req.roles if r.strip()
            ]).execute()
        except Exception as e:
            logger.warning(f"create_collab roles insert failed (non-fatal): {e}")

    logger.info(f"Collaboration created: {collab_id} by user {user_id}")
    return {"collaboration": collab, "message": "Collaboration posted successfully!"}


@router.post("/{collab_id}/request")
@limiter.limit(GENERAL_LIMIT)
async def request_to_join(
    collab_id: str,
    req: JoinRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Request to join a collaboration."""
    user_id = user["id"]
    sb = supabase_service.client

    # Verify collab exists and is open
    try:
        collab_res = sb.table("collaborations").select("id, status, owner_id").eq(
            "id", collab_id
        ).single().execute()
    except Exception as e:
        logger.error(f"request_to_join collab check failed: {e}")
        raise HTTPException(status_code=404, detail="Collaboration not found")

    if not collab_res.data:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    collab = collab_res.data
    if collab.get("status") != "open":
        raise HTTPException(status_code=400, detail="This collaboration is no longer accepting requests")

    if collab.get("owner_id") == user_id:
        raise HTTPException(status_code=400, detail="You cannot request to join your own collaboration")

    # Check existing membership
    try:
        existing_res = sb.table("collaboration_members").select("id, status").eq(
            "collaboration_id", collab_id
        ).eq("user_id", user_id).execute()
        existing = existing_res.data or []
    except Exception:
        existing = []

    if existing:
        current_status = existing[0]["status"]
        if current_status == "accepted":
            raise HTTPException(status_code=400, detail="You are already a member of this collaboration")
        if current_status == "pending":
            raise HTTPException(status_code=400, detail="You already have a pending request for this collaboration")

    # Resolve role id
    role_id = None
    if req.role_name:
        try:
            role_res = sb.table("collaboration_roles").select("id").eq(
                "collaboration_id", collab_id
            ).eq("role_name", req.role_name).eq("is_filled", False).execute()
            if role_res.data:
                role_id = role_res.data[0]["id"]
        except Exception:
            pass

    try:
        sb.table("collaboration_members").insert({
            "collaboration_id": collab_id,
            "user_id":          user_id,
            "role_id":          role_id,
            "status":           "pending",
        }).execute()
    except Exception as e:
        logger.error(f"request_to_join insert failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to send join request. Please try again.")

    return {"message": "Join request sent! The owner will review your application."}


@router.patch("/{collab_id}/members/{member_user_id}")
@limiter.limit(GENERAL_LIMIT)
async def respond_to_request(
    collab_id: str,
    member_user_id: str,
    body: MemberActionRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Accept or reject a join request (owner only)."""
    user_id = user["id"]
    sb = supabase_service.client

    if body.action not in ("accept", "reject"):
        raise HTTPException(status_code=400, detail="action must be 'accept' or 'reject'")

    # Verify ownership
    try:
        collab_res = sb.table("collaborations").select(
            "owner_id, roles_filled, max_members"
        ).eq("id", collab_id).single().execute()
    except Exception:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    if not collab_res.data:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    if collab_res.data["owner_id"] != user_id:
        raise HTTPException(status_code=403, detail="Only the collaboration owner can accept or reject requests")

    new_status = "accepted" if body.action == "accept" else "rejected"
    try:
        sb.table("collaboration_members").update({"status": new_status}).eq(
            "collaboration_id", collab_id
        ).eq("user_id", member_user_id).execute()
    except Exception as e:
        logger.error(f"respond_to_request update failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to update request status")

    if body.action == "accept":
        new_filled = (collab_res.data.get("roles_filled") or 0) + 1
        try:
            sb.table("collaborations").update({"roles_filled": new_filled}).eq(
                "id", collab_id
            ).execute()
        except Exception as e:
            logger.warning(f"roles_filled increment failed (non-fatal): {e}")

    return {"message": f"Member {body.action}ed successfully"}


@router.delete("/{collab_id}")
@limiter.limit(GENERAL_LIMIT)
async def close_collab(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Close a collaboration (owner only)."""
    sb = supabase_service.client
    user_id = user["id"]

    try:
        res = sb.table("collaborations").update({"status": "closed"}).eq(
            "id", collab_id
        ).eq("owner_id", user_id).execute()
    except Exception as e:
        logger.error(f"close_collab failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to close collaboration")

    if not (res.data or []):
        raise HTTPException(status_code=403, detail="Collaboration not found or you are not the owner")

    return {"message": "Collaboration closed successfully"}


@router.post("/{collab_id}/ai-match")
@limiter.limit(AI_LIMIT)
async def ai_match_roles(
    collab_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """AI suggests the best roles for a collaboration goal."""
    sb = supabase_service.client

    try:
        collab_res = sb.table("collaborations").select(
            "title, description, income_type"
        ).eq("id", collab_id).single().execute()
    except Exception:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    if not collab_res.data:
        raise HTTPException(status_code=404, detail="Collaboration not found")

    c = collab_res.data
    try:
        result = await ai_service.chat(
            messages=[{
                "role": "user",
                "content": (
                    f"Collaboration: {c['title']}\n"
                    f"Type: {c['income_type']}\n"
                    f"Description: {c['description']}\n\n"
                    "What are the 3-5 most important roles needed for this collaboration to succeed? "
                    'Return JSON: {"roles": [{"name": "", "description": "", "skills_needed": []}]}'
                ),
            }],
            system="You are a collaboration strategist. Return ONLY valid JSON. No markdown.",
            max_tokens=600,
        )
    except Exception as e:
        logger.error(f"ai_match_roles AI call failed: {e}")
        raise HTTPException(status_code=503, detail="AI service temporarily unavailable. Please try again.")

    import json
    raw = result["content"].strip().strip("```json").strip("```").strip()
    try:
        roles_data = json.loads(raw)
    except Exception:
        roles_data = {"roles": []}

    return {
        "suggested_roles": roles_data.get("roles", []),
        "model": result.get("model"),
    }

