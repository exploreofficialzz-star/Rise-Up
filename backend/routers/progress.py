"""Progress Router — Stats, earnings, roadmap, profile"""
from fastapi import APIRouter, Depends, HTTPException

from models.schemas import ProfileUpdate, EarningLog
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/progress", tags=["Progress"])


@router.get("/stats")
async def get_stats(user: dict = Depends(get_current_user)):
    stats = await supabase_service.get_user_stats(user["id"])
    return stats


@router.get("/earnings")
async def get_earnings(user: dict = Depends(get_current_user)):
    summary = await supabase_service.get_earnings_summary(user["id"])
    return summary


@router.post("/log-earning")
async def log_earning(req: EarningLog, user: dict = Depends(get_current_user)):
    earned = await supabase_service.log_earning(
        user["id"], req.amount, req.source_type,
        req.source_id, req.description, req.currency
    )
    return {"earning": earned, "message": f"💰 {req.currency} {req.amount:,.0f} logged!"}


@router.get("/roadmap")
async def get_roadmap(user: dict = Depends(get_current_user)):
    roadmap = await supabase_service.get_roadmap(user["id"])
    return {"roadmap": roadmap}


@router.get("/profile")
async def get_profile(user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"])
    return {"profile": profile}


@router.patch("/profile")
async def update_profile(req: ProfileUpdate, user: dict = Depends(get_current_user)):
    data = req.dict(exclude_none=True)
    updated = await supabase_service.update_profile(user["id"], data)
    return {"profile": updated, "message": "Profile updated!"}
