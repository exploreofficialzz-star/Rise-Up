"""Progress Router — Stats, earnings, roadmap, profile, avatar upload"""
import base64
import uuid
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse

from models.schemas import ProfileUpdate, EarningLog
from services.supabase_service import supabase_service
from utils.auth import get_current_user
from config import settings

router = APIRouter(prefix="/progress", tags=["Progress"])
logger = logging.getLogger(__name__)


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


@router.post("/avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user)
):
    """Upload profile picture to Supabase Storage and update profile"""
    user_id = user["id"]

    # Validate file type
    allowed = {"image/jpeg", "image/png", "image/webp", "image/gif"}
    content_type = file.content_type or "image/jpeg"
    if content_type not in allowed:
        raise HTTPException(400, "Only JPEG, PNG, WebP and GIF images are allowed")

    # Validate file size (max 5MB)
    contents = await file.read()
    if len(contents) > 5 * 1024 * 1024:
        raise HTTPException(400, "Image must be under 5MB")

    try:
        sb = supabase_service.client
        ext = content_type.split("/")[-1].replace("jpeg", "jpg")
        filename = f"avatars/{user_id}/{uuid.uuid4()}.{ext}"

        # Upload to Supabase Storage bucket "avatars"
        sb.storage.from_("avatars").upload(
            filename,
            contents,
            {"content-type": content_type, "upsert": "true"}
        )

        # Get public URL
        url_result = sb.storage.from_("avatars").get_public_url(filename)
        avatar_url = url_result if isinstance(url_result, str) else url_result.get("publicUrl", "")

        # Update profile
        await supabase_service.update_profile(user_id, {"avatar_url": avatar_url})

        return {"avatar_url": avatar_url, "message": "Profile picture updated!"}

    except Exception as e:
        logger.error(f"Avatar upload error: {e}")
        raise HTTPException(500, f"Upload failed: {str(e)}")
