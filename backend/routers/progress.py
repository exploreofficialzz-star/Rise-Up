"""Progress Router — Stats, earnings, roadmap, profile, avatar upload"""
import uuid
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request

from models.schemas import ProfileUpdate, EarningLog
from services.supabase_service import supabase_service
from utils.auth import get_current_user

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
    return {
        "earning": earned,
        "message": f"💰 {req.currency} {req.amount:,.0f} logged!",
    }


@router.get("/roadmap")
async def get_roadmap(user: dict = Depends(get_current_user)):
    roadmap = await supabase_service.get_roadmap(user["id"])
    return {"roadmap": roadmap}


@router.get("/profile")
async def get_profile(user: dict = Depends(get_current_user)):
    """
    Returns the current user's full profile plus lightweight stats.
    Shape: { "profile": {...}, "stats": {...} }

    Both keys are always present so screens can safely destructure either
    without guarding for missing keys.
    """
    profile = await supabase_service.get_profile(user["id"])

    # ── Inline social stats (followers / following / post count) ─────────────
    # Try to fetch from a dedicated method; fall back to zero-values so the
    # response never breaks even if the stats table is empty.
    stats: dict = {}
    try:
        stats = await supabase_service.get_user_stats(user["id"]) or {}
    except Exception as e:
        logger.warning(f"Could not fetch stats for {user['id']}: {e}")

    # Merge follower/following counts into the profile map so the Flutter
    # ProfileScreen can read them from _profile directly.
    if profile and isinstance(profile, dict):
        profile.setdefault("followers_count", stats.get("followers", 0))
        profile.setdefault("following_count", stats.get("following", 0))
        profile.setdefault("is_premium",
                           profile.get("subscription_tier") == "premium")

    return {
        "profile": profile or {},
        "stats": stats,
    }


@router.patch("/profile")
async def update_profile(
    req: ProfileUpdate,
    user: dict = Depends(get_current_user),
):
    """
    Partial profile update — only fields present in the request body are
    written to the database. Uses model_dump(exclude_none=True) so fields
    the client did not send are never overwritten.
    """
    # ── Pydantic v2: use model_dump, NOT .dict() ──────────────────────────────
    data = req.model_dump(exclude_none=True)

    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    try:
        updated = await supabase_service.update_profile(user["id"], data)
    except Exception as e:
        logger.error(f"Profile update failed for {user['id']}: {e}")
        raise HTTPException(status_code=500, detail="Profile update failed")

    # Ensure the response always includes is_premium so the client can gate UI
    if updated and isinstance(updated, dict):
        updated.setdefault("is_premium",
                           updated.get("subscription_tier") == "premium")

    return {
        "profile": updated or {},
        "message": "Profile saved!",
    }


@router.post("/avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Upload profile picture to Supabase Storage bucket 'avatars' and update
    the user's profile row with the new public URL.

    Accepts: JPEG, PNG, WebP, GIF — max 5 MB.
    Returns: { "avatar_url": "https://...", "message": "..." }
    """
    user_id = user["id"]

    # ── Validate MIME type ────────────────────────────────────────────────────
    allowed_types = {"image/jpeg", "image/png", "image/webp", "image/gif"}
    content_type = (file.content_type or "image/jpeg").lower().split(";")[0].strip()
    if content_type not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail="Only JPEG, PNG, WebP and GIF images are allowed",
        )

    # ── Read & validate size ──────────────────────────────────────────────────
    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="File is empty")
    if len(contents) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")

    # ── Build unique storage path ─────────────────────────────────────────────
    ext = content_type.split("/")[-1].replace("jpeg", "jpg")
    filename = f"avatars/{user_id}/{uuid.uuid4()}.{ext}"

    try:
        sb = supabase_service.client

        # ── Upload with upsert ────────────────────────────────────────────────
        try:
            sb.storage.from_("avatars").upload(
                path=filename,
                file=contents,
                file_options={"content-type": content_type, "upsert": "true"},
            )
        except Exception as upload_err:
            err_str = str(upload_err).lower()
            if any(k in err_str for k in ("already exists", "duplicate", "23505")):
                # Remove stale file then re-upload without upsert flag
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

        # ── Get public URL ────────────────────────────────────────────────────
        url_result = sb.storage.from_("avatars").get_public_url(filename)
        avatar_url: str = (
            url_result
            if isinstance(url_result, str)
            else (
                url_result.get("publicUrl")
                or url_result.get("public_url")
                or ""
            )
        )

        if not avatar_url:
            raise HTTPException(status_code=500, detail="Could not generate public URL")

        # ── Persist URL to profile ────────────────────────────────────────────
        await supabase_service.update_profile(user_id, {"avatar_url": avatar_url})

        logger.info(f"Avatar uploaded for {user_id}: {filename}")
        return {
            "avatar_url": avatar_url,
            "message": "Profile picture updated!",
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Avatar upload error for {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


@router.get("/leaderboard")
async def get_leaderboard(
    user: dict = Depends(get_current_user),
    limit: int = 50,
):
    """Real earnings leaderboard — verified, not fake"""
    try:
        leaders = (
            supabase_service.client
            .table("profiles")
            .select(
                "id, full_name, stage, country, total_earned, currency, "
                "xp_points, subscription_tier, avatar_url"
            )
            .gt("total_earned", 0)
            .order("total_earned", desc=True)
            .limit(min(limit, 100))
            .execute()
        )

        result = []
        for i, p in enumerate(leaders.data or []):
            result.append({
                "rank": i + 1,
                "user_id": p.get("id"),
                "full_name": p.get("full_name", "User"),
                "stage": p.get("stage", "survival"),
                "country": p.get("country", ""),
                "total_earned": p.get("total_earned", 0),
                "currency": p.get("currency", "USD"),
                "xp_points": p.get("xp_points", 0),
                "avatar_url": p.get("avatar_url"),
                "is_premium": p.get("subscription_tier") == "premium",
            })

        return {"leaders": result, "total": len(result)}

    except Exception as e:
        logger.error(f"Leaderboard error: {e}")
        return {"leaders": [], "total": 0}
