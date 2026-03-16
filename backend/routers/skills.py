"""Skills Router — Earn while learning modules"""
from fastapi import APIRouter, Depends, HTTPException

from models.schemas import EnrollRequest, ProgressUpdate
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/skills", tags=["Skills"])


@router.get("/modules")
async def get_modules(user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"])
    is_premium = profile.get("subscription_tier") == "premium" if profile else False
    modules = await supabase_service.get_skill_modules()
    return {"modules": modules, "is_premium": is_premium}


@router.post("/enroll")
async def enroll(req: EnrollRequest, user: dict = Depends(get_current_user)):
    # Check if module is premium
    modules = await supabase_service.get_skill_modules()
    module = next((m for m in modules if m["id"] == req.module_id), None)
    if not module:
        raise HTTPException(404, "Module not found")

    if module.get("is_premium"):
        has_access = await supabase_service.check_feature_access(user["id"], "premium_skills")
        if not has_access:
            raise HTTPException(403, "This module requires Premium. Upgrade or watch an ad to unlock!")

    enrollment = await supabase_service.enroll_skill(user["id"], req.module_id)
    return {"enrollment": enrollment, "message": "Enrolled! Start your first lesson now 🎉"}


@router.get("/my-courses")
async def my_courses(user: dict = Depends(get_current_user)):
    enrollments = await supabase_service.get_enrollments(user["id"])
    return {"enrollments": enrollments}


@router.patch("/progress")
async def update_progress(req: ProgressUpdate, user: dict = Depends(get_current_user)):
    data = {
        "progress_percent": req.progress_percent,
        "current_lesson": req.current_lesson,
        "status": "completed" if req.progress_percent >= 100 else "in_progress"
    }
    if req.earnings_from_skill:
        data["earnings_from_skill"] = req.earnings_from_skill
        await supabase_service.log_earning(
            user["id"], req.earnings_from_skill, "skill", req.enrollment_id
        )

    updated = await supabase_service.update_enrollment(req.enrollment_id, user["id"], data)
    return {"enrollment": updated}
