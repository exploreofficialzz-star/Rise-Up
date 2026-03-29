# backend/routers/skills.py
"""
AI-Powered Skills Router — Global, Adaptive, Earn-While-Learning
- AI generates personalized skill paths based on user context
- Ad-supported free tier (3 skills max)
- Premium for unlimited access
- Aggregates global learning resources (YouTube, courses, docs)
"""
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from pydantic import BaseModel, Field, validator
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from services.currency_service import currency_service
from services.notification_service import notification_service
from utils.auth import get_current_user

router = APIRouter(prefix="/skills", tags=["Skills"])
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# Pydantic Models
# ─────────────────────────────────────────────────────────────

class GenerateSkillPathRequest(BaseModel):
    skill_name: str = Field(..., min_length=2, max_length=100, description="Skill to learn")
    current_level: str = Field("beginner", pattern="^(beginner|intermediate|advanced)$")
    goal_description: Optional[str] = Field(None, max_length=500, description="What you want to achieve")
    time_available_hours_week: int = Field(5, ge=1, le=40)
    preferred_learning_style: Optional[str] = Field(None, pattern="^(video|reading|hands_on|mixed)$")


class EnrollRequest(BaseModel):
    skill_path_id: str
    use_ad_unlock: Optional[bool] = False


class ProgressUpdateRequest(BaseModel):
    enrollment_id: str
    lesson_completed: int
    time_spent_minutes: int = Field(..., ge=0, le=480)
    notes: Optional[str] = None
    earnings_logged: Optional[float] = None


class SkillFeedbackRequest(BaseModel):
    skill_path_id: str
    rating: int = Field(..., ge=1, le=5)
    feedback: Optional[str] = Field(None, max_length=500)


class ResourceSubmissionRequest(BaseModel):
    skill_path_id: str
    resource_url: str = Field(..., max_length=500)
    resource_type: str = Field(..., pattern="^(video|article|course|documentation|tool)$")
    title: str = Field(..., min_length=3, max_length=200)
    description: Optional[str] = Field(None, max_length=500)


# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

async def get_user_context(user_id: str) -> Dict[str, Any]:
    """Gather comprehensive user context for AI personalization"""
    profile = await supabase_service.get_profile(user_id) or {}
    
    # Get user's country and language
    country = profile.get("country", "US")
    language = profile.get("language", "en")
    
    # Get existing skill enrollments
    enrollments = supabase_service.client.table("skill_enrollments").select(
        "status, progress_percent, skill_path_id, completed_at"
    ).eq("user_id", user_id).execute()
    
    enrolled_count = len(enrollments.data or [])
    completed_count = len([e for e in (enrollments.data or []) if e.get("status") == "completed"])
    
    # Check free tier limit
    is_premium = profile.get("subscription_tier") == "premium"
    can_enroll_free = is_premium or enrolled_count < 3
    
    return {
        "profile": profile,
        "country": country,
        "language": language,
        "currency": profile.get("currency", "USD"),
        "experience_level": profile.get("experience_level", "beginner"),
        "current_skills": profile.get("current_skills", []) or [],
        "enrolled_count": enrolled_count,
        "completed_count": completed_count,
        "is_premium": is_premium,
        "can_enroll_free": can_enroll_free,
        "ad_unlocks_remaining": max(0, 3 - enrolled_count) if not is_premium else 0,
    }


def build_skill_generation_prompt(context: Dict, request: GenerateSkillPathRequest) -> tuple:
    """Build AI prompt for personalized skill path generation"""
    
    user_ctx = context["profile"]
    country = context["country"]
    language = context["language"]
    
    system_prompt = f"""You are an expert curriculum designer and career coach.
Create a personalized skill learning path that helps users earn money while learning.

USER CONTEXT:
- Country: {country}
- Language: {language}
- Current skills: {', '.join(context['current_skills']) or 'None'}
- Experience level: {context['experience_level']}
- Time available: {request.time_available_hours_week} hours/week

SKILL PATH REQUIREMENTS:
1. Must be monetizable within 30 days of starting
2. Use globally accessible resources (YouTube, free courses, documentation)
3. Include region-specific platforms where relevant
4. Provide resources in {language} when available, English as fallback
5. Each lesson must have a clear "earning milestone"

OUTPUT FORMAT - Valid JSON only:
{{
  "skill_path": {{
    "title": "Compelling skill path title",
    "description": "Why this skill matters and earning potential",
    "category": "tech|creative|business|marketing|trade",
    "difficulty": "beginner|intermediate|advanced",
    "estimated_time_to_first_earning_days": <number>,
    "average_income_potential": {{
      "monthly_usd": <amount>,
      "hourly_rate_usd": <amount>,
      "local_currency": "{context['currency']}",
      "local_monthly_estimate": <amount>
    }},
    "prerequisites": ["skill 1", "skill 2"],
    "tools_needed": [
      {{
        "name": "Tool name",
        "cost": "free|$amount",
        "alternative": "free alternative if paid",
        "purpose": "what it's for"
      }}
    ],
    "curriculum": [
      {{
        "module_number": 1,
        "title": "Module title",
        "description": "What you'll learn",
        "estimated_hours": <number>,
        "earning_milestone": "What you can earn after this module",
        "lessons": [
          {{
            "lesson_number": 1,
            "title": "Lesson title",
            "type": "video|reading|project|practice",
            "description": "What to do",
            "time_minutes": <15-120>,
            "resources": [
              {{
                "type": "youtube|article|course|documentation|tool",
                "title": "Resource title",
                "url": "full URL",
                "source": "YouTube channel or website name",
                "language": "en|{language}|multi",
                "is_free": true,
                "quality_rating": "beginner|intermediate|advanced",
                "description": "Why this resource"
              }}
            ],
            "action_items": ["specific task 1", "specific task 2"],
            "deliverable": "What to produce/submit",
            "verification_method": "How to confirm completion"
          }}
        ]
      }}
    ],
    "portfolio_projects": [
      {{
        "title": "Project name",
        "description": "What to build",
        "skills_demonstrated": ["skill 1", "skill 2"],
        "client_attractiveness": "Why clients care",
        "time_estimate_hours": <number>
      }}
    ],
    "first_client_strategies": [
      {{
        "platform": "Upwork|Fiverr|LinkedIn|Local|Other",
        "approach": "Specific strategy",
        "message_template": "Initial outreach message",
        "pricing_suggestion": "What to charge initially"
      }}
    ],
    "community_resources": [
      {{
        "name": "Community name",
        "type": "discord|reddit|forum|local",
        "url": "link",
        "purpose": "How it helps"
      }}
    ],
    "local_opportunities": [
      {{
        "type": "platform|marketplace|local_business",
        "name": "Opportunity name",
        "url": "link if applicable",
        "description": "How to approach"
      }}
    ]
  }}
}}"""

    user_prompt = f"""Create a personalized learning path for: {request.skill_name}

Current level: {request.current_level}
Goal: {request.goal_description or 'Learn and start earning as soon as possible'}
Learning style: {request.preferred_learning_style or 'mixed'}
Available time: {request.time_available_hours_week} hours per week

Make this specific to {country}. Include local platforms, consider local market rates, and suggest resources available in {language} where possible."""

    return system_prompt, user_prompt


def parse_ai_skill_response(raw_content: str) -> Dict:
    """Safely parse AI skill generation response"""
    cleaned = raw_content.strip()
    for prefix in ["```json", "```", "`"]:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()
    for suffix in ["```", "`"]:
        if cleaned.endswith(suffix):
            cleaned = cleaned[:-len(suffix)].strip()
    
    try:
        parsed = json.loads(cleaned)
        return parsed.get("skill_path", parsed)
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}, content: {raw_content[:500]}")
        # Try to extract JSON from text
        try:
            start = cleaned.find('{')
            end = cleaned.rfind('}')
            if start != -1 and end != -1:
                parsed = json.loads(cleaned[start:end+1])
                return parsed.get("skill_path", parsed)
        except Exception:
            pass
        raise ValueError(f"Could not parse AI response: {str(e)}")


# ─────────────────────────────────────────────────────────────
# API Endpoints
# ─────────────────────────────────────────────────────────────

@router.post("/generate-path", response_model=Dict)
@limiter.limit(AI_LIMIT)
async def generate_skill_path(
    request: Request,
    req: GenerateSkillPathRequest,
    user: dict = Depends(get_current_user)
):
    """
    AI generates a personalized skill learning path with global resources.
    Preview only - doesn't enroll yet.
    """
    user_id = user["id"]
    
    try:
        context = await get_user_context(user_id)
        
        # Build prompts
        system_prompt, user_prompt = build_skill_generation_prompt(context, req)
        
        # Generate with AI
        result = await ai_service.chat(
            messages=[{"role": "user", "content": user_prompt}],
            system=system_prompt,
            max_tokens=4000,
            temperature=0.7,
        )
        
        # Parse response
        skill_path = parse_ai_skill_response(result["content"])
        
        # Add metadata
        skill_path["generated_at"] = datetime.now(timezone.utc).isoformat()
        skill_path["ai_model"] = result.get("model", "unknown")
        skill_path["user_context"] = {
            "country": context["country"],
            "language": context["language"],
            "experience_level": req.current_level,
        }
        
        # Store as preview (not enrolled yet)
        preview_id = str(uuid.uuid4())
        preview_record = {
            "id": preview_id,
            "user_id": user_id,
            "skill_name": req.skill_name,
            "skill_path_data": json.dumps(skill_path),
            "expires_at": (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat(),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        
        supabase_service.client.table("skill_path_previews").insert(preview_record).execute()
        
        # Check enrollment eligibility
        enrollment_status = {
            "can_enroll_free": context["can_enroll_free"],
            "is_premium": context["is_premium"],
            "enrolled_count": context["enrolled_count"],
            "ad_unlocks_remaining": context["ad_unlocks_remaining"],
            "requires_action": "none" if context["can_enroll_free"] else ("ad" if context["ad_unlocks_remaining"] > 0 else "upgrade"),
        }
        
        return {
            "preview_id": preview_id,
            "skill_path": skill_path,
            "enrollment_status": enrollment_status,
            "message": "Preview generated. Enroll to start learning!",
        }
        
    except Exception as e:
        logger.exception("Skill path generation failed")
        raise HTTPException(500, f"Failed to generate skill path: {str(e)}")


@router.post("/enroll", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def enroll(
    request: Request,
    req: EnrollRequest,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """
    Enroll in a skill path. Free users limited to 3 skills.
    Can unlock additional slots by watching ads.
    """
    user_id = user["id"]
    
    try:
        context = await get_user_context(user_id)
        
        # Check enrollment eligibility
        if not context["can_enroll_free"]:
            if req.use_ad_unlock and context["ad_unlocks_remaining"] > 0:
                # Ad unlock used - proceed
                ad_unlock_used = True
            else:
                return {
                    "enrolled": False,
                    "reason": "limit_reached",
                    "message": "You've reached your 3 free skill limit.",
                    "options": {
                        "watch_ad": context["ad_unlocks_remaining"] > 0,
                        "upgrade_premium": True,
                        "ad_unlocks_remaining": context["ad_unlocks_remaining"],
                    }
                }
        else:
            ad_unlock_used = False
        
        # Get preview data
        preview = supabase_service.client.table("skill_path_previews").select(
            "*"
        ).eq("id", req.skill_path_id).eq("user_id", user_id).single().execute()
        
        if not preview.data:
            raise HTTPException(404, "Skill path preview not found or expired")
        
        skill_path = json.loads(preview.data["skill_path_data"])
        
        # Create enrollment
        enrollment_id = str(uuid.uuid4())
        enrollment_record = {
            "id": enrollment_id,
            "user_id": user_id,
            "skill_path_id": req.skill_path_id,
            "skill_name": skill_path.get("title", "Unknown Skill"),
            "category": skill_path.get("category", "other"),
            "difficulty": skill_path.get("difficulty", "beginner"),
            "status": "active",
            "progress_percent": 0,
            "current_module": 1,
            "current_lesson": 1,
            "total_modules": len(skill_path.get("curriculum", [])),
            "skill_path_data": preview.data["skill_path_data"],  # Store full path
            "started_at": datetime.now(timezone.utc).isoformat(),
            "ad_unlock_used": ad_unlock_used,
            "estimated_completion": (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
        }
        
        saved = supabase_service.client.table("skill_enrollments").insert(
            enrollment_record
        ).execute()
        
        if not saved.data:
            raise HTTPException(500, "Failed to create enrollment")
        
        enrollment = saved.data[0]
        
        # Schedule welcome notification
        background_tasks.add_task(
            notification_service.send_skill_start,
            user_id=user_id,
            skill_name=enrollment["skill_name"],
            first_lesson=skill_path.get("curriculum", [{}])[0].get("lessons", [{}])[0].get("title", "Get started!")
        )
        
        return {
            "enrolled": True,
            "enrollment": enrollment,
            "first_lesson": skill_path.get("curriculum", [{}])[0].get("lessons", [{}])[0],
            "message": f"🎓 Enrolled in {enrollment['skill_name']}! Start your first lesson.",
            "ad_unlock_used": ad_unlock_used,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Enrollment failed")
        raise HTTPException(500, f"Enrollment failed: {str(e)}")


@router.get("/my-courses", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def my_courses(
    request: Request,
    status: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """Get user's enrolled skill paths with progress"""
    user_id = user["id"]
    
    query = supabase_service.client.table("skill_enrollments").select(
        "*"
    ).eq("user_id", user_id)
    
    if status:
        query = query.eq("status", status)
    
    result = query.order("started_at", desc=True).execute()
    enrollments = result.data or []
    
    # Calculate stats
    total = len(enrollments)
    active = len([e for e in enrollments if e["status"] == "active"])
    completed = len([e for e in enrollments if e["status"] == "completed"])
    
    # Calculate total earnings from skills
    earnings_result = supabase_service.client.table("skill_earnings").select(
        "amount_usd"
    ).eq("user_id", user_id).execute()
    
    total_earnings = sum(e.get("amount_usd", 0) for e in (earnings_result.data or []))
    
    # Get context for enrollment limits
    context = await get_user_context(user_id)
    
    return {
        "enrollments": enrollments,
        "statistics": {
            "total_enrolled": total,
            "active": active,
            "completed": completed,
            "total_earnings_usd": round(total_earnings, 2),
            "completion_rate": round(completed / total * 100, 1) if total > 0 else 0,
        },
        "limits": {
            "is_premium": context["is_premium"],
            "max_free_skills": 3,
            "enrolled_count": context["enrolled_count"],
            "remaining_free_slots": max(0, 3 - context["enrolled_count"]),
            "can_enroll_more": context["can_enroll_free"],
            "ad_unlocks_remaining": context["ad_unlocks_remaining"],
        }
    }


@router.get("/enrollment/{enrollment_id}", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def get_enrollment_detail(
    enrollment_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Get detailed enrollment with full curriculum"""
    user_id = user["id"]
    
    enrollment = supabase_service.client.table("skill_enrollments").select(
        "*"
    ).eq("id", enrollment_id).eq("user_id", user_id).single().execute()
    
    if not enrollment.data:
        raise HTTPException(404, "Enrollment not found")
    
    e = enrollment.data
    
    # Parse skill path data
    skill_path = json.loads(e.get("skill_path_data", "{}"))
    
    # Get progress history
    progress = supabase_service.client.table("skill_progress").select(
        "*"
    ).eq("enrollment_id", enrollment_id).order("created_at", desc=True).execute()
    
    # Get earnings from this skill
    earnings = supabase_service.client.table("skill_earnings").select(
        "*"
    ).eq("enrollment_id", enrollment_id).execute()
    
    # Calculate next actions
    current_module_idx = e.get("current_module", 1) - 1
    current_lesson_idx = e.get("current_lesson", 1) - 1
    
    curriculum = skill_path.get("curriculum", [])
    next_lesson = None
    if current_module_idx < len(curriculum):
        module = curriculum[current_module_idx]
        lessons = module.get("lessons", [])
        if current_lesson_idx < len(lessons):
            next_lesson = lessons[current_lesson_idx]
    
    return {
        "enrollment": e,
        "skill_path": skill_path,
        "progress_history": progress.data or [],
        "earnings": earnings.data or [],
        "next_lesson": next_lesson,
        "completion_estimate": e.get("estimated_completion"),
    }


@router.post("/progress", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def update_progress(
    request: Request,
    req: ProgressUpdateRequest,
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """Update learning progress and optionally log earnings"""
    user_id = user["id"]
    
    # Verify enrollment
    enrollment = supabase_service.client.table("skill_enrollments").select(
        "*"
    ).eq("id", req.enrollment_id).eq("user_id", user_id).single().execute()
    
    if not enrollment.data:
        raise HTTPException(404, "Enrollment not found")
    
    e = enrollment.data
    
    # Calculate new progress
    total_modules = e.get("total_modules", 1)
    total_lessons = sum(len(m.get("lessons", [])) for m in json.loads(e.get("skill_path_data", "{}")).get("curriculum", []))
    
    # Simple progress calculation (can be enhanced)
    progress_percent = min((req.lesson_completed / max(total_lessons, 1)) * 100, 100)
    
    # Determine status
    status = "completed" if progress_percent >= 100 else "active"
    
    update_data = {
        "progress_percent": round(progress_percent, 1),
        "current_lesson": req.lesson_completed,
        "status": status,
        "last_activity_at": datetime.now(timezone.utc).isoformat(),
    }
    
    # Update module if lesson threshold crossed
    skill_path = json.loads(e.get("skill_path_data", "{}"))
    curriculum = skill_path.get("curriculum", [])
    lessons_so_far = 0
    for idx, module in enumerate(curriculum):
        module_lessons = len(module.get("lessons", []))
        if req.lesson_completed <= lessons_so_far + module_lessons:
            update_data["current_module"] = idx + 1
            break
        lessons_so_far += module_lessons
    
    # Log progress entry
    progress_entry = {
        "id": str(uuid.uuid4()),
        "enrollment_id": req.enrollment_id,
        "user_id": user_id,
        "lesson_number": req.lesson_completed,
        "time_spent_minutes": req.time_spent_minutes,
        "notes": req.notes,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    supabase_service.client.table("skill_progress").insert(progress_entry).execute()
    
    # Handle earnings
    earnings_logged = None
    if req.earnings_logged and req.earnings_logged > 0:
        # Convert to USD for tracking
        profile = await supabase_service.get_profile(user_id) or {}
        currency = profile.get("currency", "USD")
        amount_usd = await currency_service.convert_to_usd(req.earnings_logged, currency)
        
        earnings_entry = {
            "id": str(uuid.uuid4()),
            "enrollment_id": req.enrollment_id,
            "user_id": user_id,
            "amount_local": req.earnings_logged,
            "amount_usd": amount_usd,
            "currency_local": currency,
            "lesson_number": req.lesson_completed,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        supabase_service.client.table("skill_earnings").insert(earnings_entry).execute()
        
        # Update enrollment earnings total
        update_data["earnings_from_skill"] = (e.get("earnings_from_skill") or 0) + amount_usd
        
        earnings_logged = {
            "amount_local": req.earnings_logged,
            "amount_usd": amount_usd,
            "currency": currency,
        }
        
        # Check for first earning milestone
        if update_data["earnings_from_skill"] > 0 and (e.get("earnings_from_skill") or 0) == 0:
            background_tasks.add_task(
                notification_service.send_first_earning_congrats,
                user_id=user_id,
                skill_name=e["skill_name"],
                amount_usd=amount_usd
            )
    
    # Update enrollment
    updated = supabase_service.client.table("skill_enrollments").update(
        update_data
    ).eq("id", req.enrollment_id).execute()
    
    # Check completion
    if status == "completed" and e.get("status") != "completed":
        update_data["completed_at"] = datetime.now(timezone.utc).isoformat()
        background_tasks.add_task(
            notification_service.send_skill_complete,
            user_id=user_id,
            skill_name=e["skill_name"]
        )
    
    return {
        "updated": True,
        "progress": {
            "percent": update_data["progress_percent"],
            "current_module": update_data.get("current_module", e.get("current_module")),
            "current_lesson": req.lesson_completed,
            "status": status,
        },
        "earnings_logged": earnings_logged,
        "time_logged_minutes": req.time_spent_minutes,
        "next_milestone": _get_next_milestone(skill_path, req.lesson_completed),
    }


def _get_next_milestone(skill_path: Dict, current_lesson: int) -> Optional[Dict]:
    """Determine next earning milestone"""
    curriculum = skill_path.get("curriculum", [])
    lessons_so_far = 0
    
    for module in curriculum:
        module_lessons = len(module.get("lessons", []))
        if lessons_so_far + module_lessons > current_lesson:
            remaining = (lessons_so_far + module_lessons) - current_lesson
            return {
                "module": module.get("title"),
                "lessons_remaining": remaining,
                "earning_milestone": module.get("earning_milestone"),
            }
        lessons_so_far += module_lessons
    
    return None


@router.post("/{enrollment_id}/complete", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def mark_complete(
    enrollment_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Manually mark skill as completed"""
    user_id = user["id"]
    
    enrollment = supabase_service.client.table("skill_enrollments").select(
        "*"
    ).eq("id", enrollment_id).eq("user_id", user_id).single().execute()
    
    if not enrollment.data:
        raise HTTPException(404, "Enrollment not found")
    
    updated = supabase_service.client.table("skill_enrollments").update({
        "status": "completed",
        "progress_percent": 100,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", enrollment_id).execute()
    
    return {
        "completed": True,
        "enrollment": updated.data[0] if updated.data else None,
        "message": "🎉 Skill marked as complete! Add it to your portfolio.",
    }


@router.post("/feedback", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def submit_feedback(
    request: Request,
    req: SkillFeedbackRequest,
    user: dict = Depends(get_current_user)
):
    """Submit feedback to improve AI skill generation"""
    user_id = user["id"]
    
    feedback_record = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "skill_path_id": req.skill_path_id,
        "rating": req.rating,
        "feedback": req.feedback,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    
    supabase_service.client.table("skill_feedback").insert(feedback_record).execute()
    
    return {"feedback_recorded": True}


@router.post("/submit-resource", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def submit_resource(
    request: Request,
    req: ResourceSubmissionRequest,
    user: dict = Depends(get_current_user)
):
    """Community resource submission for skill paths"""
    user_id = user["id"]
    
    # Verify user has enrolled in this skill
    enrollment = supabase_service.client.table("skill_enrollments").select(
        "id"
    ).eq("skill_path_id", req.skill_path_id).eq("user_id", user_id).execute()
    
    if not enrollment.data:
        raise HTTPException(403, "Must be enrolled to submit resources")
    
    submission = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "skill_path_id": req.skill_path_id,
        "resource_url": req.resource_url,
        "resource_type": req.resource_type,
        "title": req.title,
        "description": req.description,
        "status": "pending_review",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    
    supabase_service.client.table("skill_resource_submissions").insert(submission).execute()
    
    return {
        "submitted": True,
        "message": "Resource submitted for review. Thanks for contributing!",
    }


@router.get("/discover", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def discover_skills(
    request: Request,
    category: Optional[str] = None,
    difficulty: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """
    Discover popular skills based on community data.
    Returns trending skills with success rates.
    """
    # Get popular skills from completed enrollments
    query = supabase_service.client.table("skill_enrollments").select(
        "skill_name, category, difficulty, count"
    ).eq("status", "completed")
    
    if category:
        query = query.eq("category", category)
    if difficulty:
        query = query.eq("difficulty", difficulty)
    
    # Group by skill name
    popular = query.execute()
    
    # Get average earnings by skill
    earnings_by_skill = supabase_service.client.rpc(
        "get_average_earnings_by_skill"
    ).execute()
    
    # Get user's context for personalization
    context = await get_user_context(user["id"])
    
    return {
        "trending_skills": popular.data or [],
        "earnings_data": earnings_by_skill.data or [],
        "recommended_for_you": _generate_recommendations(context),
        "filters": {
            "categories": ["tech", "creative", "business", "marketing", "trade"],
            "difficulties": ["beginner", "intermediate", "advanced"],
        }
    }


def _generate_recommendations(context: Dict) -> List[Dict]:
    """Generate skill recommendations based on user context"""
    recommendations = []
    
    # Based on experience level
    if context["experience_level"] == "beginner":
        recommendations.extend([
            {"skill": "Social Media Management", "reason": "High demand, low barrier"},
            {"skill": "Basic Web Development", "reason": "Build foundation for tech career"},
        ])
    elif context["experience_level"] == "intermediate":
        recommendations.extend([
            {"skill": "AI Tool Integration", "reason": "Leverage your existing tech knowledge"},
            {"skill": "Consulting", "reason": "Monetize your experience"},
        ])
    
    # Based on time available
    if context.get("time_available_hours_week", 0) < 10:
        recommendations.append({
            "skill": "Micro-Freelancing",
            "reason": f"Only {context.get('time_available_hours_week')} hrs/week - perfect for quick gigs"
        })
    
    return recommendations


@router.delete("/enrollment/{enrollment_id}", response_model=Dict)
@limiter.limit(GENERAL_LIMIT)
async def drop_enrollment(
    enrollment_id: str,
    request: Request,
    reason: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """Drop/withdraw from a skill enrollment"""
    user_id = user["id"]
    
    enrollment = supabase_service.client.table("skill_enrollments").select(
        "*"
    ).eq("id", enrollment_id).eq("user_id", user_id).single().execute()
    
    if not enrollment.data:
        raise HTTPException(404, "Enrollment not found")
    
    # Log abandonment if reason provided
    if reason:
        supabase_service.client.table("skill_abandonments").insert({
            "id": str(uuid.uuid4()),
            "enrollment_id": enrollment_id,
            "user_id": user_id,
            "skill_name": enrollment.data.get("skill_name"),
            "reason": reason,
            "progress_at_drop": enrollment.data.get("progress_percent", 0),
            "dropped_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    
    # Soft delete - mark as dropped
    supabase_service.client.table("skill_enrollments").update({
        "status": "dropped",
        "dropped_at": datetime.now(timezone.utc).isoformat(),
        "drop_reason": reason,
    }).eq("id", enrollment_id).execute()
    
    return {
        "dropped": True,
        "message": "Enrollment dropped. Your slot is now free for another skill!",
    }
