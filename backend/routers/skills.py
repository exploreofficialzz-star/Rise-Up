"""Skills Router — Earn while learning modules (Global Support)"""
from fastapi import APIRouter, Depends, HTTPException, Header, Request
from typing import Optional

from models.schemas import EnrollRequest, ProgressUpdate
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/skills", tags=["Skills"])


@router.get("/modules")
async def get_modules(
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header("en-US", description="User's preferred locale"),
    user_timezone: Optional[str] = Header("UTC", description="User's local timezone")
):
    profile = await supabase_service.get_profile(user["id"])
    is_premium = profile.get("subscription_tier") == "premium" if profile else False
    
    # Passing language and timezone down to the service to fetch localized content
    # Make sure to update your supabase_service to filter or join translated tables based on locale
    modules = await supabase_service.get_skill_modules(locale=accept_language, timezone=user_timezone)
    
    return {"modules": modules, "is_premium": is_premium}


@router.post("/enroll")
async def enroll(
    req: EnrollRequest, 
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header("en-US")
):
    # Check if module is premium
    modules = await supabase_service.get_skill_modules(locale=accept_language)
    module = next((m for m in modules if m["id"] == req.module_id), None)
    if not module:
        raise HTTPException(status_code=404, detail="Module not found")

    if module.get("is_premium"):
        has_access = await supabase_service.check_feature_access(user["id"], "premium_skills")
        if not has_access:
            # Consider using a localization dictionary for error messages in a production app
            raise HTTPException(status_code=403, detail="This module requires Premium. Upgrade or watch an ad to unlock!")

    enrollment = await supabase_service.enroll_skill(user["id"], req.module_id)
    return {"enrollment": enrollment, "message": "Enrolled! Start your first lesson now 🎉"}


@router.get("/my-courses")
async def my_courses(
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header("en-US")
):
    enrollments = await supabase_service.get_enrollments(user["id"], locale=accept_language)
    return {"enrollments": enrollments}


@router.patch("/progress")
async def update_progress(
    req: ProgressUpdate, 
    user: dict = Depends(get_current_user),
    currency: Optional[str] = Header("USD", description="User's local currency code")
):
    data = {
        "progress_percent": req.progress_percent,
        "current_lesson": req.current_lesson,
        "status": "completed" if req.progress_percent >= 100 else "in_progress"
    }
    
    if req.earnings_from_skill:
        data["earnings_from_skill"] = req.earnings_from_skill
        # Pass the currency code to the service so earnings are normalized or tracked accurately across borders
        await supabase_service.log_earning(
            user_id=user["id"], 
            amount=req.earnings_from_skill, 
            source="skill", 
            reference_id=req.enrollment_id,
            currency=currency
        )

    updated = await supabase_service.update_enrollment(req.enrollment_id, user["id"], data)
    return {"enrollment": updated}
