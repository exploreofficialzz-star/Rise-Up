"""
Client CRM + Follow-up Engine
Track every prospect, conversation, proposal.
Agent auto-reminds. Spots patterns. Closes more deals.
No freelance/wealth app has a CRM. This changes that.
"""
import json, logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/crm", tags=["Client CRM"])
logger = logging.getLogger(__name__)


class AddClientRequest(BaseModel):
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    platform: Optional[str] = None   # where you met them
    service_interest: Optional[str] = None
    budget_usd: Optional[float] = None
    notes: Optional[str] = None
    status: str = "prospect"   # prospect | contacted | proposal_sent | negotiating | won | lost | recurring


class AddInteractionRequest(BaseModel):
    client_id: str
    interaction_type: str   # message | call | proposal | meeting | follow_up | payment
    summary: str
    outcome: Optional[str] = None
    next_action: Optional[str] = None
    next_action_date: Optional[str] = None


class UpdateClientRequest(BaseModel):
    status: Optional[str] = None
    notes: Optional[str] = None
    budget_usd: Optional[float] = None
    service_interest: Optional[str] = None
    next_follow_up: Optional[str] = None


@router.post("/clients")
@limiter.limit(GENERAL_LIMIT)
async def add_client(req: AddClientRequest, request: Request, user: dict = Depends(get_current_user)):
    saved = supabase_service.client.table("crm_clients").insert({
        "user_id": user["id"],
        "name": req.name, "email": req.email, "phone": req.phone,
        "platform": req.platform, "service_interest": req.service_interest,
        "budget_usd": req.budget_usd, "notes": req.notes, "status": req.status,
    }).execute()
    return {"client": saved.data[0] if saved.data else {}, "message": f"Added {req.name} to your CRM"}


@router.get("/clients")
@limiter.limit(GENERAL_LIMIT)
async def list_clients(request: Request, status: Optional[str] = None, user: dict = Depends(get_current_user)):
    query = supabase_service.client.table("crm_clients").select("*").eq("user_id", user["id"])
    if status:
        query = query.eq("status", status)
    result = query.order("created_at", desc=True).limit(100).execute()
    clients = result.data or []

    won = [c for c in clients if c["status"] == "won"]
    pipeline_value = sum((c.get("budget_usd") or 0) for c in clients if c["status"] not in ("won","lost"))
    close_rate = round(len(won) / max(len([c for c in clients if c["status"] in ("won","lost")]), 1) * 100)

    return {
        "clients": clients,
        "stats": {
            "total": len(clients),
            "prospects": len([c for c in clients if c["status"] == "prospect"]),
            "in_pipeline": len([c for c in clients if c["status"] in ("contacted","proposal_sent","negotiating")]),
            "won": len(won),
            "lost": len([c for c in clients if c["status"] == "lost"]),
            "pipeline_value_usd": pipeline_value,
            "close_rate_pct": close_rate,
        }
    }


@router.post("/interactions")
@limiter.limit(GENERAL_LIMIT)
async def add_interaction(req: AddInteractionRequest, request: Request, user: dict = Depends(get_current_user)):
    saved = supabase_service.client.table("crm_interactions").insert({
        "user_id": user["id"], "client_id": req.client_id,
        "interaction_type": req.interaction_type, "summary": req.summary,
        "outcome": req.outcome, "next_action": req.next_action,
        "next_action_date": req.next_action_date,
    }).execute()
    if req.next_action_date:
        supabase_service.client.table("crm_clients").update({
            "next_follow_up": req.next_action_date
        }).eq("id", req.client_id).eq("user_id", user["id"]).execute()
    return {"interaction": saved.data[0] if saved.data else {}}


@router.get("/follow-ups/due")
@limiter.limit(GENERAL_LIMIT)
async def get_due_followups(request: Request, user: dict = Depends(get_current_user)):
    """Get clients that need following up today"""
    today = datetime.now(timezone.utc).date().isoformat()
    sb = supabase_service.client

    overdue = sb.table("crm_clients").select("*").eq("user_id", user["id"]).lte(
        "next_follow_up", today
    ).neq("status", "won").neq("status", "lost").execute()

    no_contact_3days = sb.table("crm_clients").select("*").eq(
        "user_id", user["id"]
    ).eq("status", "contacted").is_("next_follow_up", "null").execute()

    return {
        "overdue_followups": overdue.data or [],
        "no_contact_3days": no_contact_3days.data or [],
        "total_needing_attention": len(overdue.data or []) + len(no_contact_3days.data or []),
        "message": f"You have {len(overdue.data or [])} follow-ups due today." if overdue.data else "All follow-ups are on track 🎯"
    }


@router.post("/clients/{client_id}/ai-followup")
@limiter.limit(AI_LIMIT)
async def generate_followup_message(client_id: str, request: Request, user: dict = Depends(get_current_user)):
    """AI writes the perfect follow-up message for this specific client"""
    user_id = user["id"]
    sb = supabase_service.client

    client = sb.table("crm_clients").select("*").eq("id", client_id).eq("user_id", user_id).single().execute()
    if not client.data:
        raise HTTPException(404, "Client not found")

    interactions = sb.table("crm_interactions").select("*").eq(
        "client_id", client_id
    ).order("created_at", desc=True).limit(5).execute()

    c = client.data
    history = interactions.data or []
    profile = await supabase_service.get_profile(user_id) or {}

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Client: {json.dumps(c)}\nHistory: {json.dumps([h.get('summary','') for h in history])}"}],
        system=f"""You are a sales coach for {profile.get('full_name','the freelancer')}.
Write the perfect follow-up message for this client.
Be specific to their situation. Not generic. Not pushy.
Move the deal forward naturally.
JSON: {{"message":"FULL MESSAGE TEXT ready to send","send_via":"platform/email/whatsapp","timing":"when to send this","subject_line":"if email","tone":"warm|professional|urgent"}}""",
        max_tokens=500,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        msg = json.loads(raw)
    except Exception:
        msg = {"message": result["content"]}

    return {"follow_up": msg, "client": c["name"], "model": result.get("model")}


@router.get("/analytics")
@limiter.limit(GENERAL_LIMIT)
async def crm_analytics(request: Request, user: dict = Depends(get_current_user)):
    """CRM analytics — patterns, conversion rates, best platforms"""
    user_id = user["id"]
    sb = supabase_service.client

    clients = sb.table("crm_clients").select("*").eq("user_id", user_id).execute()
    all_clients = clients.data or []

    if not all_clients:
        return {"has_data": False}

    platform_wins = {}
    for c in all_clients:
        p = c.get("platform", "unknown")
        if p not in platform_wins:
            platform_wins[p] = {"total": 0, "won": 0}
        platform_wins[p]["total"] += 1
        if c["status"] == "won":
            platform_wins[p]["won"] += 1

    best_platform = max(platform_wins.items(), key=lambda x: x[1]["won"]) if platform_wins else None

    total_earned = sum((c.get("budget_usd") or 0) for c in all_clients if c["status"] == "won")
    avg_deal = total_earned / max(len([c for c in all_clients if c["status"] == "won"]), 1)

    return {
        "has_data": True,
        "total_clients": len(all_clients),
        "total_earned_usd": round(total_earned, 2),
        "avg_deal_size_usd": round(avg_deal, 2),
        "best_platform": best_platform[0] if best_platform else None,
        "platform_breakdown": platform_wins,
        "insight": f"Your best source of clients is {best_platform[0]} — focus there." if best_platform and best_platform[1]["won"] > 0 else "Get more clients to unlock pattern insights.",
    }


@router.patch("/clients/{client_id}")
@limiter.limit(GENERAL_LIMIT)
async def update_client(client_id: str, req: UpdateClientRequest, request: Request, user: dict = Depends(get_current_user)):
    data = {k: v for k, v in req.dict().items() if v is not None}
    if data:
        supabase_service.client.table("crm_clients").update(data).eq("id", client_id).eq("user_id", user["id"]).execute()
    return {"updated": True}
