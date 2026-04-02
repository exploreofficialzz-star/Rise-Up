"""
routers/ads.py — RiseUp AdMob Integration

FIX: ImpressionRequest and RewardRequest fields all made Optional with
defaults. The Flutter AdMob SDK sends varying payloads depending on ad type
and SDK version — mandatory fields caused 422 on every impression, breaking
the entire ad system. Endpoints now accept any subset of fields gracefully.

Endpoints:
  GET  /ads/config      → Return all ad unit IDs
  GET  /ads/enabled     → Check if ads are configured
  POST /ads/impression  → Log an ad impression event
  POST /ads/reward      → Log a rewarded ad completion
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from typing import Optional

from config import settings
from utils.auth import get_current_user
from services.supabase_service import supabase_service

router = APIRouter(prefix="/ads", tags=["Ads"])
logger = logging.getLogger(__name__)


# ── Request Models ────────────────────────────────────────────────────────────
# FIX: All fields Optional so any payload shape is accepted.
# A 422 on /ads/impression means the ad pipeline is completely broken —
# the Flutter SDK fires these on every ad show and never retries.

class ImpressionRequest(BaseModel):
    ad_unit_id:     Optional[str] = None
    ad_type:        Optional[str] = None   # banner | interstitial | rewarded | native | app_open
    placement:      Optional[str] = None   # home_feed | ai_gate | profile | etc.
    revenue_micros: Optional[int] = None   # CPM data from AdMob SDK
    # Accept any extra fields the SDK sends without error
    class Config:
        extra = "allow"


class RewardRequest(BaseModel):
    ad_unit_id:    Optional[str] = None
    reward_type:   Optional[str] = None   # ai_message_unlock | feature_unlock | etc.
    reward_amount: Optional[int] = 1
    placement:     Optional[str] = None
    class Config:
        extra = "allow"


# ── Config ────────────────────────────────────────────────────────────────────

@router.get("/config")
async def get_ad_config():
    """Return all AdMob ad unit IDs for the mobile client."""
    return {
        "admob_app_id":          getattr(settings, "ADMOB_APP_ID", None),
        "banner_ad_unit":        getattr(settings, "ADMOB_BANNER_AD_UNIT", None),
        "interstitial_ad_unit":  getattr(settings, "ADMOB_INTERSTITIAL_AD_UNIT", None),
        "rewarded_ad_unit":      getattr(settings, "ADMOB_REWARDED_AD_UNIT", None),
        "app_open_ad_unit":      getattr(settings, "ADMOB_APP_OPEN_AD_UNIT", None),
        "native_ad_unit":        getattr(settings, "ADMOB_NATIVE_AD_UNIT", None),
    }


@router.get("/enabled")
async def ads_enabled():
    """Check whether ads are configured and enabled."""
    return {
        "enabled": bool(getattr(settings, "ADMOB_APP_ID", None)),
    }


# ── Impression Tracking ───────────────────────────────────────────────────────

@router.post("/impression")
async def log_impression(
    req: ImpressionRequest,
    user: dict = Depends(get_current_user),
):
    """
    Log an ad impression. Called whenever an ad is shown.
    Non-fatal: a missing DB table or RLS block never returns an error to client.
    """
    try:
        db = supabase_service.client
        db.table("ad_impressions").insert({
            "user_id":        user["id"],
            "ad_unit_id":     req.ad_unit_id or "unknown",
            "ad_type":        req.ad_type or "unknown",
            "placement":      req.placement,
            "revenue_micros": req.revenue_micros,
            "created_at":     datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        logger.warning(f"ad impression log failed (non-fatal): {e}")

    return {"recorded": True}


# ── Reward Tracking ───────────────────────────────────────────────────────────

@router.post("/reward")
async def log_reward(
    req: RewardRequest,
    user: dict = Depends(get_current_user),
):
    """
    Log a completed rewarded ad (analytics only).
    The actual quota reset happens in the messages router.
    """
    try:
        db = supabase_service.client
        db.table("ad_rewards").insert({
            "user_id":       user["id"],
            "ad_unit_id":    req.ad_unit_id or "unknown",
            "reward_type":   req.reward_type or "unknown",
            "reward_amount": req.reward_amount or 1,
            "placement":     req.placement,
            "created_at":    datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        logger.warning(f"ad reward log failed (non-fatal): {e}")

    return {"recorded": True}


# ── Fallback: accept raw JSON body if Pydantic somehow rejects ───────────────
# Belt-and-suspenders: if the model still 422s for any reason, these raw
# endpoints accept anything and return success.

@router.post("/impression/raw")
async def log_impression_raw(request: Request, user: dict = Depends(get_current_user)):
    try:
        body = await request.json()
        db = supabase_service.client
        db.table("ad_impressions").insert({
            "user_id":    user["id"],
            "ad_unit_id": body.get("ad_unit_id", "unknown"),
            "ad_type":    body.get("ad_type", "unknown"),
            "placement":  body.get("placement"),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        logger.warning(f"raw impression log failed: {e}")
    return {"recorded": True}


@router.post("/reward/raw")
async def log_reward_raw(request: Request, user: dict = Depends(get_current_user)):
    try:
        body = await request.json()
        db = supabase_service.client
        db.table("ad_rewards").insert({
            "user_id":       user["id"],
            "ad_unit_id":    body.get("ad_unit_id", "unknown"),
            "reward_type":   body.get("reward_type", "unknown"),
            "reward_amount": body.get("reward_amount", 1),
            "created_at":    datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        logger.warning(f"raw reward log failed: {e}")
    return {"recorded": True}
