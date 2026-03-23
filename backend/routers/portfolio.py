"""
Portfolio Builder — Auto-generated from RiseUp activity.
AI writes case studies. Real earnings as proof. Shareable link instantly.
No other wealth-building app generates a professional portfolio.
"""
import json, logging
from datetime import datetime, timezone
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/portfolio", tags=["Portfolio"])
logger = logging.getLogger(__name__)


class AddProjectRequest(BaseModel):
    title: str
    service_type: str
    client_industry: Optional[str] = None
    challenge_solved: str
    result_achieved: str
    amount_usd: Optional[float] = None
    platform_used: Optional[str] = None
    skills_used: List[str] = []
    duration_days: Optional[int] = None
    testimonial: Optional[str] = None
    is_public: bool = True


@router.post("/generate-from-workflow/{workflow_id}")
@limiter.limit(AI_LIMIT)
async def generate_from_workflow(workflow_id: str, request: Request, user: dict = Depends(get_current_user)):
    """Auto-generate a portfolio case study from a completed workflow"""
    user_id = user["id"]
    sb = supabase_service.client

    wf = sb.table("workflows").select("*").eq("id", workflow_id).eq("user_id", user_id).single().execute()
    if not wf.data:
        raise HTTPException(404, "Workflow not found")

    steps = sb.table("workflow_steps").select("*").eq("workflow_id", workflow_id).execute()
    profile = await supabase_service.get_profile(user_id) or {}

    w = wf.data
    completed_steps = [s for s in (steps.data or []) if s.get("status") == "done"]

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Workflow: {w['title']}\nGoal: {w['goal']}\nEarned: ${w['total_revenue']}\nCompleted steps: {len(completed_steps)}/{len(steps.data or [])}\nIncome type: {w['income_type']}"}],
        system=f"""Write a professional portfolio case study for {profile.get('full_name','the freelancer')}.
Make it compelling for potential clients. Show real results.
JSON:
{{
  "case_study_title": "Compelling title",
  "summary": "2-sentence compelling summary",
  "challenge": "What problem was solved",
  "approach": "How it was done",
  "results": "Specific measurable results",
  "skills_demonstrated": ["skill 1"],
  "client_value": "The dollar/time/growth value delivered to clients",
  "call_to_action": "What similar clients should do next"
}}""",
        max_tokens=800,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        case_study = json.loads(raw)
    except Exception:
        case_study = {"summary": result["content"]}

    saved = sb.table("portfolio_items").insert({
        "user_id": user_id,
        "workflow_id": workflow_id,
        "title": case_study.get("case_study_title", w["title"]),
        "service_type": w["income_type"],
        "challenge_solved": case_study.get("challenge", ""),
        "result_achieved": case_study.get("results", ""),
        "amount_usd": w["total_revenue"],
        "skills_used": json.dumps(case_study.get("skills_demonstrated", [])),
        "case_study_data": json.dumps(case_study),
        "is_public": True,
        "source": "workflow",
    }).execute()

    return {"portfolio_item": saved.data[0] if saved.data else {}, "case_study": case_study}


@router.post("/projects")
@limiter.limit(GENERAL_LIMIT)
async def add_project(req: AddProjectRequest, request: Request, user: dict = Depends(get_current_user)):
    """Manually add a project to portfolio"""
    user_id = user["id"]
    saved = supabase_service.client.table("portfolio_items").insert({
        "user_id": user_id,
        "title": req.title,
        "service_type": req.service_type,
        "client_industry": req.client_industry,
        "challenge_solved": req.challenge_solved,
        "result_achieved": req.result_achieved,
        "amount_usd": req.amount_usd,
        "platform_used": req.platform_used,
        "skills_used": json.dumps(req.skills_used),
        "duration_days": req.duration_days,
        "testimonial": req.testimonial,
        "is_public": req.is_public,
        "source": "manual",
    }).execute()
    return {"portfolio_item": saved.data[0] if saved.data else {}}


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def get_portfolio(request: Request, user: dict = Depends(get_current_user)):
    user_id = user["id"]
    sb = supabase_service.client
    items = sb.table("portfolio_items").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    profile = await supabase_service.get_profile(user_id) or {}
    all_items = items.data or []
    total_value = sum((i.get("amount_usd") or 0) for i in all_items)
    services = list(set(i.get("service_type", "") for i in all_items if i.get("service_type")))
    return {
        "items": all_items,
        "stats": {
            "total_projects": len(all_items),
            "total_value_usd": round(total_value, 2),
            "services_offered": services[:6],
        },
        "share_url": f"riseup.app/portfolio/{user_id}",
        "profile_headline": profile.get("bio", ""),
    }


@router.get("/public/{user_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_public_portfolio(user_id: str, request: Request):
    """Public portfolio — shareable link"""
    sb = supabase_service.client
    items = sb.table("portfolio_items").select("*").eq("user_id", user_id).eq("is_public", True).order("created_at", desc=True).execute()
    profile = await supabase_service.get_profile(user_id) or {}
    all_items = items.data or []
    return {
        "name": profile.get("full_name", ""),
        "bio": profile.get("bio", ""),
        "status": profile.get("status", ""),
        "skills": profile.get("current_skills", []),
        "country": profile.get("country", ""),
        "projects": all_items,
        "total_projects": len(all_items),
        "total_value_usd": round(sum((i.get("amount_usd") or 0) for i in all_items), 2),
    }


@router.post("/ai-bio")
@limiter.limit(AI_LIMIT)
async def generate_professional_bio(request: Request, user: dict = Depends(get_current_user)):
    """AI generates a professional bio + pitch from portfolio and profile"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}
    items = supabase_service.client.table("portfolio_items").select("title,service_type,result_achieved").eq("user_id", user_id).limit(5).execute()

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Name: {profile.get('full_name')}\nSkills: {', '.join(profile.get('current_skills',[]) or [])}\nCountry: {profile.get('country','')}\nGoal: {profile.get('short_term_goal','')}\nProjects: {json.dumps([i.get('title','') for i in (items.data or [])])}"}],
        system="""Write a professional freelancer bio and pitch.
JSON: {"short_bio":"2 sentences for profile","full_bio":"5-6 sentences for portfolio","pitch":"30-second verbal pitch","linkedin_headline":"under 120 chars","fiverr_tagline":"under 80 chars","unique_value_prop":"what makes this person different"}""",
        max_tokens=600,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        bio_data = json.loads(raw)
    except Exception:
        bio_data = {"short_bio": result["content"]}

    return {"bio": bio_data}
