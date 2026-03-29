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
    profile = await supabase_service.get_profile(user["id"])
    stats: dict = {}
    try:
        stats = await supabase_service.get_user_stats(user["id"]) or {}
    except Exception as e:
        logger.warning(f"Could not fetch stats for {user['id']}: {e}")

    if profile and isinstance(profile, dict):
        profile.setdefault("followers_count", stats.get("followers", 0))
        profile.setdefault("following_count", stats.get("following", 0))
        profile.setdefault("is_premium",
                           profile.get("subscription_tier") == "premium")

    return {"profile": profile or {}, "stats": stats}


@router.patch("/profile")
async def update_profile(
    req: ProfileUpdate,
    user: dict = Depends(get_current_user),
):
    data = req.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    try:
        updated = await supabase_service.update_profile(user["id"], data)
    except Exception as e:
        logger.error(f"Profile update failed for {user['id']}: {e}")
        raise HTTPException(status_code=500, detail="Profile update failed")

    if updated and isinstance(updated, dict):
        updated.setdefault("is_premium",
                           updated.get("subscription_tier") == "premium")

    return {"profile": updated or {}, "message": "Profile saved!"}


# ── MIME type → file extension map (all common image formats) ─────────────────
_IMAGE_TYPES: dict[str, str] = {
    "image/jpeg":      "jpg",
    "image/jpg":       "jpg",
    "image/png":       "png",
    "image/webp":      "webp",
    "image/gif":       "gif",
    "image/heic":      "heic",
    "image/heif":      "heif",
    "image/avif":      "avif",
    "image/bmp":       "bmp",
    "image/tiff":      "tiff",
    "image/tif":       "tiff",
    "image/svg+xml":   "svg",
    "image/x-icon":    "ico",
    "image/vnd.microsoft.icon": "ico",
    "image/jfif":      "jpg",
    "image/pjpeg":     "jpg",
    "image/x-png":     "png",
}

_MAX_SIZE_BYTES = 10 * 1024 * 1024   # 10 MB — generous for any device camera
_BUCKET         = "avatars"


@router.post("/avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Upload profile picture to Supabase Storage bucket 'avatars'.

    Accepts any common image format:
      JPEG · PNG · WebP · GIF · HEIC · HEIF · AVIF · BMP · TIFF · SVG · ICO

    Max size: 10 MB.
    Returns: { "avatar_url": "...", "message": "..." }
    """
    user_id = user["id"]

    # ── Normalise & validate MIME type ────────────────────────────────────────
    raw_ct       = (file.content_type or "").lower().split(";")[0].strip()
    # Some mobile clients send no content-type — sniff by filename extension
    if not raw_ct or raw_ct == "application/octet-stream":
        fname = (file.filename or "").lower()
        for mime, _ in _IMAGE_TYPES.items():
            if fname.endswith(mime.split("/")[-1]) or fname.endswith(
                _IMAGE_TYPES.get(mime, "")
            ):
                raw_ct = mime
                break
        else:
            raw_ct = "image/jpeg"   # safe default for unknown mobile uploads

    if raw_ct not in _IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unsupported image format '{raw_ct}'. "
                "Accepted: JPEG, PNG, WebP, GIF, HEIC, HEIF, AVIF, BMP, TIFF, SVG, ICO"
            ),
        )

    ext = _IMAGE_TYPES[raw_ct]

    # ── Read & validate size ──────────────────────────────────────────────────
    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="File is empty")
    if len(contents) > _MAX_SIZE_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"Image must be under {_MAX_SIZE_BYTES // (1024*1024)} MB"
        )

    # ── Build unique storage path  {user_id}/{uuid}.{ext} ────────────────────
    storage_path = f"{user_id}/{uuid.uuid4()}.{ext}"

    try:
        sb = supabase_service.client

        # ── Upload (upsert=true handles re-uploads cleanly) ───────────────────
        try:
            sb.storage.from_(_BUCKET).upload(
                path=storage_path,
                file=contents,
                file_options={"content-type": raw_ct, "upsert": "true"},
            )
        except Exception as upload_err:
            err_str = str(upload_err).lower()
            if any(k in err_str for k in ("already exists", "duplicate", "23505")):
                # Remove stale object then retry without upsert flag
                try:
                    sb.storage.from_(_BUCKET).remove([storage_path])
                except Exception:
                    pass
                sb.storage.from_(_BUCKET).upload(
                    path=storage_path,
                    file=contents,
                    file_options={"content-type": raw_ct},
                )
            else:
                raise

        # ── Resolve public URL ────────────────────────────────────────────────
        url_result = sb.storage.from_(_BUCKET).get_public_url(storage_path)
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

        logger.info(f"✅ Avatar uploaded for {user_id} ({ext}, {len(contents)//1024} KB): {storage_path}")
        return {
            "avatar_url": avatar_url,
            "message":    "Profile picture updated! 📸",
            "format":     ext,
            "size_kb":    round(len(contents) / 1024, 1),
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
                "rank":       i + 1,
                "user_id":    p.get("id"),
                "full_name":  p.get("full_name", "User"),
                "stage":      p.get("stage", "survival"),
                "country":    p.get("country", ""),
                "total_earned": p.get("total_earned", 0),
                "currency":   p.get("currency", "USD"),
                "xp_points":  p.get("xp_points", 0),
                "avatar_url": p.get("avatar_url"),
                "is_premium": p.get("subscription_tier") == "premium",
            })

        return {"leaders": result, "total": len(result)}

    except Exception as e:
        logger.error(f"Leaderboard error: {e}")
        return {"leaders": [], "total": 0}
