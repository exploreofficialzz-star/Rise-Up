"""Progress Router — Stats, earnings, roadmap, profile, avatar upload"""
import base64
import uuid
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
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
        # supabase-py v2.x: file_options uses content_type (underscore), upsert is bool
        try:
            sb.storage.from_("avatars").upload(
                path=filename,
                file=contents,
                file_options={"content-type": content_type, "upsert": True},
            )
        except Exception as upload_err:
            # If file already exists and upsert failed, try remove + re-upload
            err_str = str(upload_err).lower()
            if "already exists" in err_str or "duplicate" in err_str or "23505" in err_str:
                try:
                    sb.storage.from_("avatars").remove([filename])
                except Exception:
                    pass
                sb.storage.from_("avatars").upload(
                    path=filename,
                    file=contents,
                    file_options={"content-type": content_type},
                )
            else:
                raise upload_err

        # Get public URL — supabase-py v2 returns a string directly
        url_result = sb.storage.from_("avatars").get_public_url(filename)
        avatar_url = url_result if isinstance(url_result, str) else (
            url_result.get("publicUrl") or url_result.get("public_url") or ""
        )

        # Update profile
        await supabase_service.update_profile(user_id, {"avatar_url": avatar_url})

        return {"avatar_url": avatar_url, "message": "Profile picture updated!"}

    except Exception as e:
        logger.error(f"Avatar upload error: {e}")
        raise HTTPException(500, f"Upload failed: {str(e)}")


@router.get("/leaderboard")
async def get_leaderboard(request: Request = None, user: dict = Depends(get_current_user)):
    """Real earnings leaderboard — verified, not fake. Includes the requesting user's rank."""
    try:
        leaders = supabase_service.client.table("profiles").select(
            "id, full_name, stage, country, total_earned, currency, xp_points, subscription_tier"
        ).gt("total_earned", 0).order("total_earned", desc=True).limit(50).execute()

        result = []
        self_rank = None
        self_entry = None

        for i, p in enumerate(leaders.data or []):
            entry = {
                "rank": i + 1,
                "user_id": p.get("id", ""),
                "full_name": p.get("full_name", "User"),
                "stage": p.get("stage", "survival"),
                "country": p.get("country", ""),
                "total_earned": p.get("total_earned", 0),
                "currency": p.get("currency", "USD"),
                "xp_points": p.get("xp_points", 0),
                "is_self": p.get("id") == user["id"],
            }
            result.append(entry)
            if p.get("id") == user["id"]:
                self_rank = i + 1
                self_entry = entry

        # If the user is not in the top 50, find their actual rank
        if self_rank is None:
            try:
                user_profile = supabase_service.client.table("profiles").select(
                    "id, full_name, stage, country, total_earned, currency, xp_points"
                ).eq("id", user["id"]).single().execute()
                up = user_profile.data or {}
                user_earned = up.get("total_earned", 0)

                # Count how many users have strictly more earned
                count_res = supabase_service.client.table("profiles").select(
                    "id", count="exact"
                ).gt("total_earned", user_earned).execute()
                approx_rank = (count_res.count or 0) + 1

                self_entry = {
                    "rank": approx_rank,
                    "user_id": user["id"],
                    "full_name": up.get("full_name", "You"),
                    "stage": up.get("stage", "survival"),
                    "country": up.get("country", ""),
                    "total_earned": user_earned,
                    "currency": up.get("currency", "USD"),
                    "xp_points": up.get("xp_points", 0),
                    "is_self": True,
                }
                self_rank = approx_rank
            except Exception:
                pass

        return {
            "leaders": result,
            "total": len(result),
            "self_rank": self_rank,
            "self_entry": self_entry,
        }
    except Exception as e:
        return {"leaders": [], "total": 0, "self_rank": None, "self_entry": None}
