"""Ads router — AdMob integration placeholder"""
from fastapi import APIRouter
from config import settings

router = APIRouter(prefix="/ads", tags=["ads"])


@router.get("/config")
async def get_ad_config():
    """Return AdMob ad unit IDs for the mobile client."""
    return {
        "admob_app_id": settings.ADMOB_APP_ID,
        "banner_ad_unit": settings.ADMOB_BANNER_AD_UNIT,
        "interstitial_ad_unit": settings.ADMOB_INTERSTITIAL_AD_UNIT,
        "rewarded_ad_unit": settings.ADMOB_REWARDED_AD_UNIT,
        "app_open_ad_unit": settings.ADMOB_APP_OPEN_AD_UNIT,
    }


@router.get("/enabled")
async def ads_enabled():
    """Check whether ads are configured and enabled."""
    return {
        "enabled": bool(settings.ADMOB_APP_ID),
    }
