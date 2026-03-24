"""
Contract + Invoice Engine
From 'I got a client' to 'money received' — fully inside RiseUp.
AI writes the contract. AI generates the invoice. App tracks payment.
Nothing like this exists in any wealth-building app.
"""
import json, logging, uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/contracts", tags=["Contracts & Invoices"])
logger = logging.getLogger(__name__)


class GenerateContractRequest(BaseModel):
    service_type: str          # e.g. "social media management", "logo design"
    client_name: str
    client_email: Optional[str] = None
    deliverables: List[str]
    amount_usd: float
    payment_terms: str = "50% upfront, 50% on delivery"
    duration_days: int = 14
    revision_rounds: int = 2
    freelancer_name: Optional[str] = None


class GenerateInvoiceRequest(BaseModel):
    client_name: str
    client_email: Optional[str] = None
    items: List[dict]           # [{description, quantity, rate_usd}]
    due_days: int = 7
    notes: Optional[str] = None
    contract_id: Optional[str] = None


class UpdateContractRequest(BaseModel):
    status: Optional[str] = None   # draft | sent | signed | completed | cancelled
    signed_at: Optional[str] = None
    notes: Optional[str] = None


@router.post("/generate")
@limiter.limit(AI_LIMIT)
async def generate_contract(req: GenerateContractRequest, request: Request, user: dict = Depends(get_current_user)):
    """AI writes a professional contract ready to send to client"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}
    freelancer = req.freelancer_name or profile.get("full_name", "Freelancer")

    result = await ai_service.chat(
        messages=[{"role": "user", "content": json.dumps(req.dict())}],
        system=f"""Write a professional freelance service contract.
Freelancer: {freelancer}
Make it professional, legally sound, protective for both parties, clear and specific.
JSON response:
{{
  "contract_title": "...",
  "contract_text": "FULL CONTRACT TEXT — all clauses, professional language, ready to sign",
  "key_terms_summary": ["term 1", "term 2"],
  "payment_milestone_1": "...",
  "payment_milestone_2": "...",
  "protection_clauses": ["what protects the freelancer"],
  "client_obligations": ["what the client must do"]
}}""",
        max_tokens=2000,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        contract_data = json.loads(raw)
    except Exception:
        contract_data = {"contract_text": result["content"]}

    # Save to database
    invoice_num = f"CTR-{datetime.now().year}-{str(uuid.uuid4())[:8].upper()}"
    try:
        saved = supabase_service.client.table("contracts").insert({
            "user_id": user_id,
            "contract_number": invoice_num,
            "client_name": req.client_name,
            "client_email": req.client_email,
            "service_type": req.service_type,
            "deliverables": json.dumps(req.deliverables),
            "amount_usd": req.amount_usd,
            "payment_terms": req.payment_terms,
            "duration_days": req.duration_days,
            "status": "draft",
            "contract_text": contract_data.get("contract_text", ""),
            "ai_data": json.dumps(contract_data),
        }).execute()
        contract_id = saved.data[0]["id"] if saved.data else None
    except Exception as e:
        logger.error(f"Contract save: {e}")
        contract_id = None

    return {
        **contract_data,
        "contract_id": contract_id,
        "contract_number": invoice_num,
        "amount_usd": req.amount_usd,
        "model": result.get("model"),
    }


@router.post("/invoice/generate")
@limiter.limit(AI_LIMIT)
async def generate_invoice(req: GenerateInvoiceRequest, request: Request, user: dict = Depends(get_current_user)):
    """Generate a professional invoice"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}
    freelancer = profile.get("full_name", "Freelancer")

    subtotal = sum(item.get("quantity", 1) * item.get("rate_usd", 0) for item in req.items)
    due_date = (datetime.now(timezone.utc) + timedelta(days=req.due_days)).strftime("%B %d, %Y")
    invoice_num = f"INV-{datetime.now().year}-{str(uuid.uuid4())[:6].upper()}"

    invoice = {
        "invoice_number": invoice_num,
        "freelancer_name": freelancer,
        "client_name": req.client_name,
        "client_email": req.client_email,
        "issue_date": datetime.now().strftime("%B %d, %Y"),
        "due_date": due_date,
        "items": req.items,
        "subtotal_usd": round(subtotal, 2),
        "total_usd": round(subtotal, 2),
        "notes": req.notes or "Thank you for your business!",
        "payment_instructions": f"Please pay within {req.due_days} days. Bank transfer or mobile money accepted.",
        "late_fee_note": "A 5% late fee applies after the due date.",
    }

    try:
        saved = supabase_service.client.table("invoices").insert({
            "user_id": user_id,
            "invoice_number": invoice_num,
            "contract_id": req.contract_id,
            "client_name": req.client_name,
            "client_email": req.client_email,
            "amount_usd": subtotal,
            "due_date": (datetime.now(timezone.utc) + timedelta(days=req.due_days)).isoformat(),
            "status": "draft",
            "invoice_data": json.dumps(invoice),
        }).execute()
        invoice_id = saved.data[0]["id"] if saved.data else None
    except Exception as e:
        logger.error(f"Invoice save: {e}")
        invoice_id = None

    return {**invoice, "invoice_id": invoice_id}


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_contracts(request: Request, user: dict = Depends(get_current_user)):
    sb = supabase_service.client
    contracts = sb.table("contracts").select("*").eq("user_id", user["id"]).order("created_at", desc=True).limit(50).execute()
    invoices = sb.table("invoices").select("*").eq("user_id", user["id"]).order("created_at", desc=True).limit(50).execute()
    total_invoiced = sum((i.get("amount_usd") or 0) for i in (invoices.data or []))
    paid = sum((i.get("amount_usd") or 0) for i in (invoices.data or []) if i.get("status") == "paid")
    return {
        "contracts": contracts.data or [],
        "invoices": invoices.data or [],
        "total_invoiced_usd": round(total_invoiced, 2),
        "total_paid_usd": round(paid, 2),
        "outstanding_usd": round(total_invoiced - paid, 2),
    }


@router.patch("/{contract_id}")
@limiter.limit(GENERAL_LIMIT)
async def update_contract(contract_id: str, req: UpdateContractRequest, request: Request, user: dict = Depends(get_current_user)):
    data = {k: v for k, v in req.dict().items() if v is not None}
    supabase_service.client.table("contracts").update(data).eq("id", contract_id).eq("user_id", user["id"]).execute()
    return {"updated": True}


@router.patch("/invoice/{invoice_id}/paid")
@limiter.limit(GENERAL_LIMIT)
async def mark_invoice_paid(invoice_id: str, request: Request, user: dict = Depends(get_current_user)):
    inv = supabase_service.client.table("invoices").update({
        "status": "paid", "paid_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", invoice_id).eq("user_id", user["id"]).execute()

    if inv.data:
        amount = inv.data[0].get("amount_usd", 0)
        await supabase_service.log_earning(user["id"], amount, "other", invoice_id, "Invoice payment", "USD")

    return {"marked_paid": True, "amount_usd": inv.data[0].get("amount_usd") if inv.data else 0}
