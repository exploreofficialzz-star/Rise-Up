"""Referrals Router — Invite friends, earn premium rewards, track referral chain"""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/referrals", tags=["Referrals"])
logger = logging.getLogger(__name__)


class ApplyReferralRequest(BaseModel):
    referral_code: str


@router.get("/my-code")
async def get_my_referral_code(user: dict = Depends(get_current_user)):
    """Get user's referral code and referral stats"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)

    if not profile:
        raise HTTPException(404, "Profile not found")

    ref_code = profile.get("referral_code")
    if not ref_code:
        # Generate one if missing
        import hashlib
        ref_code = hashlib.md5(user_id.encode()).hexdigest()[:8].upper()
        await supabase_service.update_profile(user_id, {"referral_code": ref_code})

    # Count successful referrals
    referrals_res = (
        supabase_service.db.table("referrals")
        .select("*")
        .eq("referrer_id", user_id)
        .execute()
    )
    referrals = referrals_res.data or []

    rewarded     = [r for r in referrals if r["status"] == "rewarded"]
    pending      = [r for r in referrals if r["status"] in ("pending", "signed_up")]

    return {
        "referral_code":     ref_code,
        "referral_link":     f"https://riseup.app/join?ref={ref_code}",
        "whatsapp_message":  (
            f"🚀 Join me on RiseUp — the AI wealth mentor that's helping me build real income! "
            f"Sign up with my code *{ref_code}* and we both get FREE Premium for a week! 💰\n"
            f"Download: https://riseup.app/join?ref={ref_code}"
        ),
        "total_referrals":   len(referrals),
        "rewarded_count":    len(rewarded),
        "pending_count":     len(pending),
        "premium_days_earned": len(rewarded) * 7,
        "referrals":         referrals[-10:],  # last 10
    }


@router.post("/apply")
@limiter.limit("3/minute")
async def apply_referral_code(
    req: ApplyReferralRequest, request: Request, user: dict = Depends(get_current_user)
):
    """Apply a referral code during or after onboarding"""
    user_id = user["id"]
    code = req.referral_code.upper().strip()

    # Check if user was already referred
    profile = await supabase_service.get_profile(user_id)
    if profile and profile.get("referred_by"):
        raise HTTPException(400, "You've already used a referral code")

    # Call the RPC which handles all validation + premium grants atomically
    result = supabase_service.db.rpc("complete_referral", {
        "referred_uid": user_id,
        "ref_code":     code,
    }).execute()

    data = result.data
    if not data or not data.get("success"):
        reason = data.get("reason", "unknown") if data else "unknown"
        messages = {
            "invalid_code":    "That referral code doesn't exist",
            "self_referral":   "You can't use your own referral code",
            "already_referred":"You've already used a referral code",
        }
        raise HTTPException(400, messages.get(reason, "Invalid referral code"))

    # Unlock referral achievement for referrer
    referrer_id = data.get("referrer_id")
    if referrer_id:
        referrals_count_res = (
            supabase_service.db.table("referrals")
            .select("id", count="exact")
            .eq("referrer_id", referrer_id)
            .eq("status", "rewarded")
            .execute()
        )
        count = referrals_count_res.count or 0
        if count >= 1:
            supabase_service.db.rpc("unlock_achievement", {"uid": referrer_id, "ach_key": "first_referral"}).execute()
        if count >= 5:
            supabase_service.db.rpc("unlock_achievement", {"uid": referrer_id, "ach_key": "referrals_5"}).execute()

    return {
        "success":  True,
        "message":  "🎉 Referral applied! You and your friend both got 3 days of FREE Premium!",
        "reward":   "3 days Premium",
    }


@router.get("/leaderboard")
async def referral_leaderboard(user: dict = Depends(get_current_user)):
    """Top referrers leaderboard"""
    res = supabase_service.db.rpc(
        "get_referral_leaderboard", {}
    ).execute() if False else (  # RPC not defined yet — use direct query
        supabase_service.db
        .table("referrals")
        .select("referrer_id, profiles(full_name, country)")
        .eq("status", "rewarded")
        .execute()
    )

    # Aggregate manually
    from collections import Counter
    data = res.data or []
    counts = Counter(r["referrer_id"] for r in data)

    board = []
    for uid, count in counts.most_common(10):
        row = next((r for r in data if r["referrer_id"] == uid), {})
        profile = row.get("profiles") or {}
        board.append({
            "full_name":       profile.get("full_name", "Anonymous"),
            "country":         profile.get("country", ""),
            "referral_count":  count,
            "premium_earned":  f"{count * 7} days",
        })

    return {"leaderboard": board}
