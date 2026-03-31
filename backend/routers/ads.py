"""
routers/ads.py — RiseUp AdMob Integration

Endpoints:
  GET  /ads/config      → Return all ad unit IDs (including native)
  GET  /ads/enabled     → Check if ads are configured
  POST /ads/impression  → Log an ad impression event
  POST /ads/reward      → Log a rewarded ad completion
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional

from config import settings
from utils.auth import get_current_user
from services.supabase_service import supabase_service

router = APIRouter(prefix="/ads", tags=["Ads"])
logger = logging.getLogger(__name__)


# ── Request Models ────────────────────────────────────────────────────────────

class ImpressionRequest(BaseModel):
    ad_unit_id: str
    ad_type: str                      # banner | interstitial | rewarded | native | app_open
    placement: Optional[str] = None   # e.g. "home_feed", "ai_gate", "profile"
    revenue_micros: Optional[int] = None  # optional CPM data from AdMob SDK


class RewardRequest(BaseModel):
    ad_unit_id: str
    reward_type: str                  # e.g. "ai_message_unlock"
    reward_amount: Optional[int] = 1
    placement: Optional[str] = None


# ── Config ────────────────────────────────────────────────────────────────────

@router.get("/config")
async def get_ad_config():
    """Return all AdMob ad unit IDs for the mobile client."""
    return {
        "admob_app_id":           getattr(settings, "ADMOB_APP_ID", None),
        "banner_ad_unit":         getattr(settings, "ADMOB_BANNER_AD_UNIT", None),
        "interstitial_ad_unit":   getattr(settings, "ADMOB_INTERSTITIAL_AD_UNIT", None),
        "rewarded_ad_unit":       getattr(settings, "ADMOB_REWARDED_AD_UNIT", None),
        "app_open_ad_unit":       getattr(settings, "ADMOB_APP_OPEN_AD_UNIT", None),
        "native_ad_unit":         getattr(settings, "ADMOB_NATIVE_AD_UNIT", None),
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
    Log an ad impression. Called by the client whenever an ad is shown.
    Stores to ad_impressions table if it exists; otherwise silently succeeds
    so a missing table never breaks the client.
    """
    try:
        db = supabase_service.client
        db.table("ad_impressions").insert({
            "user_id":        user["id"],
            "ad_unit_id":     req.ad_unit_id,
            "ad_type":        req.ad_type,
            "placement":      req.placement,
            "revenue_micros": req.revenue_micros,
            "created_at":     datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        # Non-fatal: table may not exist yet or RLS blocks insert
        logger.warning(f"ad impression log failed (non-fatal): {e}")

    return {"recorded": True}


# ── Reward Tracking ───────────────────────────────────────────────────────────

@router.post("/reward")
async def log_reward(
    req: RewardRequest,
    user: dict = Depends(get_current_user),
):
    """
    Log a completed rewarded ad. Called by the client after the user earns
    a reward (e.g. AI message unlock). The actual quota reset happens on the
    messages router; this endpoint is purely for analytics.
    """
    try:
        db = supabase_service.client
        db.table("ad_rewards").insert({
            "user_id":       user["id"],
            "ad_unit_id":    req.ad_unit_id,
            "reward_type":   req.reward_type,
            "reward_amount": req.reward_amount,
            "placement":     req.placement,
            "created_at":    datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        logger.warning(f"ad reward log failed (non-fatal): {e}")

    return {"recorded": True}
