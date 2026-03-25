"""Payments Router — Flutterwave subscriptions & feature unlocks
Primary currency: USD. Users pay in their local currency if preferred;
all USD prices are converted via flutterwave_service.get_price_for_currency().
"""
import logging
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, Header
from typing import Optional

from models.schemas import PaymentInitRequest, PaymentVerifyRequest, AdUnlockRequest
from services.flutterwave_service import flutterwave_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user
from config import settings

router = APIRouter(prefix="/payments", tags=["Payments"])
logger = logging.getLogger(__name__)


@router.post("/initiate")
async def initiate_payment(req: PaymentInitRequest, user: dict = Depends(get_current_user)):
    """Create Flutterwave payment link for subscription.
    Charges in the user's preferred currency (default USD).
    """
    profile = await supabase_service.get_profile(user["id"])
    if not profile:
        raise HTTPException(400, "Complete onboarding first")

    # Prefer explicitly passed currency, then user's display currency, then USD
    currency = req.currency or profile.get("currency", "USD") or "USD"
    amount   = flutterwave_service.get_price_for_currency(req.plan, currency)

    result = await flutterwave_service.initiate_payment(
        user_id=user["id"],
        email=user["email"],
        amount=amount,
        currency=currency,
        plan=req.plan,
        name=profile.get("full_name"),
        phone=profile.get("phone")
    )

    if not result["success"]:
        raise HTTPException(400, result.get("error", "Payment initiation failed"))

    # Record pending payment
    await supabase_service.create_payment(
        user_id=user["id"],
        tx_ref=result["tx_ref"],
        amount=amount,
        currency=currency,
        payment_type="subscription",
        plan=req.plan
    )

    return {
        "payment_link":   result["payment_link"],
        "tx_ref":         result["tx_ref"],
        "amount":         amount,
        "currency":       currency,
        "usd_equivalent": result.get("usd_equivalent", amount if currency == "USD" else None),
        "plan":           req.plan
    }


@router.post("/verify")
async def verify_payment(req: PaymentVerifyRequest, user: dict = Depends(get_current_user)):
    """Verify payment and activate premium subscription."""
    if req.transaction_id:
        result = await flutterwave_service.verify_payment(req.transaction_id)
    else:
        result = await flutterwave_service.verify_by_tx_ref(req.tx_ref)

    if not result["success"] or not result.get("verified"):
        raise HTTPException(400, "Payment verification failed")

    meta = result.get("meta", {})
    plan = meta.get("plan", "monthly")
    expires_at = (
        datetime.now(timezone.utc) + timedelta(days=30 if plan == "monthly" else 365)
    ).isoformat()

    await supabase_service.update_profile(user["id"], {
        "subscription_tier": "premium",
        "subscription_expires_at": expires_at
    })

    await supabase_service.update_payment(req.tx_ref, {
        "status": "successful",
        "flutterwave_tx_id": str(result.get("tx_id", ""))
    })

    await supabase_service.log_earning(
        user["id"], 0, "other", description="Premium subscription activated"
    )

    return {
        "success":    True,
        "message":    "🎉 Welcome to RiseUp Premium! All features unlocked.",
        "expires_at": expires_at,
        "plan":       plan
    }


@router.post("/webhook")
async def flutterwave_webhook(
    request: Request,
    verif_hash: Optional[str] = Header(None, alias="verif-hash")
):
    """Flutterwave webhook for server-side payment confirmation."""
    body = await request.body()

    if not flutterwave_service.verify_webhook_signature(body, verif_hash or ""):
        raise HTTPException(401, "Invalid webhook signature")

    import json
    data  = json.loads(body)
    event = data.get("event")

    if event == "charge.completed":
        tx = data.get("data", {})
        if tx.get("status") == "successful":
            meta    = tx.get("meta", {})
            user_id = meta.get("user_id")
            plan    = meta.get("plan", "monthly")
            tx_ref  = tx.get("tx_ref")

            if user_id and tx_ref:
                expires_at = (
                    datetime.now(timezone.utc) + timedelta(days=30 if plan == "monthly" else 365)
                ).isoformat()
                await supabase_service.update_profile(user_id, {
                    "subscription_tier": "premium",
                    "subscription_expires_at": expires_at
                })
                await supabase_service.update_payment(tx_ref, {"status": "successful"})
                logger.info(f"Webhook: Premium activated for user {user_id}")

    return {"status": "ok"}


@router.post("/ad-unlock")
async def unlock_via_ad(req: AdUnlockRequest, user: dict = Depends(get_current_user)):
    """Grant temporary feature access after watching a rewarded ad."""
    expires_at = (
        datetime.now(timezone.utc) + timedelta(hours=req.duration_hours or 1)
    ).isoformat()

    unlock = await supabase_service.unlock_feature(
        user["id"], req.feature_key, "ad", expires_at
    )
    await supabase_service.log_ad_view(user["id"], req.ad_unit_id, req.feature_key)

    return {
        "success":    True,
        "feature":    req.feature_key,
        "expires_at": expires_at,
        "message":    f"✅ Feature unlocked for {req.duration_hours} hour(s)!"
    }


@router.get("/check-access/{feature_key}")
async def check_feature_access(feature_key: str, user: dict = Depends(get_current_user)):
    has_access = await supabase_service.check_feature_access(user["id"], feature_key)
    return {"feature": feature_key, "has_access": has_access}


@router.get("/subscription-status")
async def subscription_status(user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"])
    if not profile:
        return {"tier": "free", "expires_at": None}

    tier    = profile.get("subscription_tier", "free")
    expires = profile.get("subscription_expires_at")

    if tier == "premium" and expires:
        from dateutil.parser import parse
        if parse(expires) < datetime.now(timezone.utc):
            await supabase_service.update_profile(user["id"], {"subscription_tier": "free"})
            tier = "free"

    # Return price in both USD and user's local currency
    display_currency = profile.get("currency", "USD")
    local_currency   = profile.get("local_currency", display_currency)

    return {
        "tier":                      tier,
        "expires_at":                expires,
        "is_premium":                tier == "premium",
        "monthly_price_usd":         settings.SUBSCRIPTION_MONTHLY_USD,
        "yearly_price_usd":          settings.SUBSCRIPTION_YEARLY_USD,
        "monthly_price_local":       flutterwave_service.get_price_for_currency("monthly", display_currency),
        "yearly_price_local":        flutterwave_service.get_price_for_currency("yearly", display_currency),
        "display_currency":          display_currency,
        "local_currency":            local_currency,
    }
