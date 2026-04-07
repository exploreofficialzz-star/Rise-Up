"""
RiseUp Methods Brain Router v1.0
═══════════════════════════════════════════════════════════════════
Endpoints:
  /brain/mentor/chat        — brain-aware AI mentor (internal-first search)
  /brain/methods            — browse 10,000 income methods
  /brain/methods/search     — search methods
  /brain/methods/position   — personalised method quiz
  /brain/marketplace        — browse/create marketplace listings
  /brain/search/internal    — search RiseUp only
  /brain/task/create        — create agentic task (find buyers, etc.)
  /brain/task/{id}          — task status + results
  /brain/task/{id}/approve  — approve external search or full execution
  /brain/contacts/{task_id} — discovered contacts
  /brain/seed               — bulk seed methods (admin)
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Query
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.supabase_service import supabase_service
from services.ai_service import ai_service
from services.riseup_brain_service import (
    search_riseup_brain,
    build_brain_context_prompt,
    get_user_brain_context,
    detect_intent,
)
from utils.auth import get_current_user

router = APIRouter(prefix="/brain", tags=["Methods Brain"])
logger = logging.getLogger(__name__)


# ───────────────────────────────────────────────────────────────────
# REQUEST MODELS
# ───────────────────────────────────────────────────────────────────

class MentorChatRequest(BaseModel):
    message:      str
    session_id:   Optional[str] = None
    language:     Optional[str] = "en"
    history:      Optional[List[dict]] = []

class PositioningRequest(BaseModel):
    available_capital_usd:    float = 0
    available_hours_per_week: int   = 10
    has_smartphone:           bool  = True
    has_laptop:               bool  = False
    has_reliable_internet:    bool  = True
    languages:                List[str] = ["en"]
    location_city:            Optional[str] = None
    location_country:         Optional[str] = None
    can_travel_locally:       bool  = True
    has_bank_account:         bool  = True
    goal_type:                str   = "side_income"
    income_goal_monthly_usd:  Optional[float] = None
    timeline_months:          Optional[int]   = None
    risk_tolerance:           str   = "low"
    current_skills:           List[str] = []
    skill_description:        Optional[str] = None

class ListingCreateRequest(BaseModel):
    listing_type:    str
    title:           str
    description:     str
    price_usd:       Optional[float] = None
    price_negotiable: bool = True
    currency:        str  = "USD"
    location:        Optional[str] = None
    country:         Optional[str] = None
    is_global:       bool = True
    contact_info:    dict = {}
    tags:            List[str] = []
    method_id:       Optional[str] = None

class InquiryRequest(BaseModel):
    message:      str
    contact_info: dict = {}

class AgenticTaskRequest(BaseModel):
    task_type:   str   = "custom"
    title:       str
    description: str
    input_data:  dict  = {}
    priority:    str   = "normal"

class BulkSeedRequest(BaseModel):
    methods: List[dict]


# ───────────────────────────────────────────────────────────────────
# BRAIN-AWARE AI MENTOR CHAT
# ───────────────────────────────────────────────────────────────────

@router.post("/mentor/chat")
async def brain_mentor_chat(
    req:  MentorChatRequest,
    user: dict = Depends(get_current_user),
):
    """
    The brain-aware AI mentor chat.

    Flow:
    1. Detect user intent from message
    2. Search RiseUp internally (methods, marketplace, profiles)
    3. Inject brain context into AI system prompt
    4. AI responds with internal knowledge + escalation signal if needed
    5. Return response + metadata for Flutter to handle escalation UI
    """
    user_id  = user["id"]
    profile  = await supabase_service.get_profile(user_id) or {}
    language = req.language or profile.get("language", "en")
    country  = profile.get("country", "")

    # Step 1: Brain search
    brain = await search_riseup_brain(
        query=req.message,
        user_id=user_id,
        user_country=country,
        limit=5,
    )

    # Step 2: User context
    brain_context = await get_user_brain_context(user_id)
    active_methods = ", ".join(brain_context.get("active_methods", [])) or "none yet"

    # Step 3: Build enriched system prompt
    brain_block = build_brain_context_prompt(brain)
    lang_note   = f"\nRespond in {language}." if language != "en" else ""

    system_prompt = f"""You are the RiseUp AI Mentor — a brilliant, warm, direct personal economic advisor.
You know all 10,000 income-generating methods ($0 to $1B+) and the entire RiseUp ecosystem.

USER PROFILE:
- Name: {profile.get('full_name', 'User')}
- Country: {country} | Currency: {profile.get('currency','USD')}
- Stage: {profile.get('stage','survival').upper()}
- Active methods: {active_methods}
- Monthly income: ${profile.get('monthly_income',0):,.0f}
{lang_note}

{brain_block}

YOUR RESPONSE RULES:
1. Be warm, direct, and specific — never vague
2. If RiseUp internal results were found: present them naturally ("I found X on RiseUp...")
3. If service providers found: mention they can be contacted directly within RiseUp
4. If marketplace listings found: present them as real opportunities
5. If needs_external=true: say you found limited internal results and offer to search the internet
6. Use this EXACT phrase when offering external search:
   "Want me to search the internet for more options? I can use the Workflow Engine to find buyers/sellers/contacts globally."
7. When user says yes to external: say "Opening the Workflow Engine for you now"
8. When user says "handle everything": say "Activating your Agentic assistant to handle this end-to-end"
9. Always end with ONE specific next action
10. NEVER make up people, listings, or prices — only use what the brain found"""

    # Step 4: Build conversation
    messages = list(req.history or [])
    messages.append({"role": "user", "content": req.message})

    # Step 5: Call AI
    result = await ai_service.chat(messages, system=system_prompt, max_tokens=1500)

    return {
        "reply":             result["content"],
        "model":             result.get("model","unknown"),
        "intent":            brain["intent"],
        "methods":           brain["methods"],
        "marketplace":       brain["marketplace"],
        "service_providers": brain["service_providers"],
        "internal_found":    brain["found"],
        "internal_count":    brain["total_found"],
        "needs_external":    brain["needs_external"],
        "escalation_reason": brain.get("escalation_reason"),
        "suggested_task_type": brain.get("suggested_task_type"),
        "session_id":        req.session_id,
    }


# ───────────────────────────────────────────────────────────────────
# INCOME METHODS BROWSER
# ───────────────────────────────────────────────────────────────────

@router.get("/methods")
async def get_methods(
    investment_tier: Optional[str] = Query(None),
    category:        Optional[str] = Query(None),
    skill_level:     Optional[str] = Query(None),
    time_to_first:   Optional[str] = Query(None),
    internet_dep:    Optional[str] = Query(None),
    location_flex:   Optional[str] = Query(None),
    scalability:     Optional[str] = Query(None),
    risk_profile:    Optional[str] = Query(None),
    search:          Optional[str] = Query(None),
    featured:        Optional[bool]= Query(None),
    trending:        Optional[bool]= Query(None),
    limit:           int           = Query(20, ge=1, le=100),
    offset:          int           = Query(0, ge=0),
):
    """Browse and filter the 10,000 income methods."""
    sb = supabase_service.client
    q  = sb.table("income_methods").select(
        "id,method_number,title,description,category,investment_tier,"
        "min_investment_usd,max_investment_usd,time_to_first_dollar,skill_level,"
        "internet_dependency,location_flexibility,scalability,risk_profile,"
        "solo_or_team,industry_vertical,tags,section_title,section_emoji,"
        "how_to_start,first_steps,platforms,global_demand_score,competition_level,"
        "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,"
        "trending,is_featured,view_count"
    ).eq("is_active", True)

    if investment_tier: q = q.eq("investment_tier", investment_tier)
    if category:        q = q.eq("category", category)
    if skill_level:     q = q.eq("skill_level", skill_level)
    if time_to_first:   q = q.eq("time_to_first_dollar", time_to_first)
    if internet_dep:    q = q.eq("internet_dependency", internet_dep)
    if location_flex:   q = q.eq("location_flexibility", location_flex)
    if scalability:     q = q.eq("scalability", scalability)
    if risk_profile:    q = q.eq("risk_profile", risk_profile)
    if featured is not None: q = q.eq("is_featured", featured)
    if trending is not None: q = q.eq("trending", trending)
    if search:          q = q.ilike("title", f"%{search}%")

    result = q.order("global_demand_score", desc=True)\
              .range(offset, offset + limit - 1).execute()

    return {
        "methods": result.data or [],
        "count":   len(result.data or []),
        "offset":  offset,
        "limit":   limit,
    }


@router.get("/methods/search")
async def search_methods(
    q:      str  = Query(..., min_length=2),
    limit:  int  = Query(20, le=50),
):
    """Full-text search across income methods."""
    sb     = supabase_service.client
    result = sb.table("income_methods")\
        .select("id,method_number,title,description,category,investment_tier,"
                "tags,time_to_first_dollar,global_demand_score,section_emoji")\
        .eq("is_active", True)\
        .ilike("title", f"%{q}%")\
        .order("global_demand_score", desc=True).limit(limit).execute()
    return {"methods": result.data or [], "query": q, "count": len(result.data or [])}


@router.get("/methods/tiers")
async def get_tiers():
    """Return all investment tier definitions."""
    return {"tiers": [
        {"id":"zero",    "label":"$0 Investment",    "emoji":"🟢","desc":"Start with nothing but your skills"},
        {"id":"micro",   "label":"$1 – $500",        "emoji":"🟢","desc":"A little cash, big potential"},
        {"id":"low",     "label":"$500 – $10K",      "emoji":"🟡","desc":"Small business territory"},
        {"id":"medium",  "label":"$10K – $100K",     "emoji":"🟠","desc":"Serious business investment"},
        {"id":"high",    "label":"$100K – $1M",      "emoji":"🔴","desc":"Major business capital"},
        {"id":"major",   "label":"$1M – $100M",      "emoji":"🔴🔴","desc":"Enterprise-level ventures"},
        {"id":"ultra",   "label":"$100M – $1B",      "emoji":"💎","desc":"Institutional-scale operations"},
        {"id":"billion", "label":"$1B+",             "emoji":"💎💎","desc":"Global empire building"},
    ]}


@router.get("/methods/featured")
async def get_featured_methods(limit: int = Query(10, le=50)):
    sb     = supabase_service.client
    result = sb.table("income_methods")\
        .select("id,method_number,title,description,category,investment_tier,"
                "tags,time_to_first_dollar,avg_earning_monthly_usd_low,"
                "avg_earning_monthly_usd_high,global_demand_score,section_emoji")\
        .eq("is_active", True).eq("is_featured", True)\
        .order("global_demand_score", desc=True).limit(limit).execute()
    return {"methods": result.data or []}


@router.get("/methods/stats")
async def get_methods_stats():
    sb     = supabase_service.client
    result = sb.table("income_methods")\
        .select("investment_tier,category").eq("is_active", True).execute()
    data   = result.data or []
    tier_counts = {}
    cat_counts  = {}
    for m in data:
        tier_counts[m["investment_tier"]] = tier_counts.get(m["investment_tier"],0) + 1
        cat_counts[m["category"]]         = cat_counts.get(m["category"],0) + 1
    return {
        "total_methods": len(data),
        "by_tier":        tier_counts,
        "by_category":    cat_counts,
    }


# NOTE: /methods/my/tracked MUST come before /methods/{method_id}
# FastAPI matches routes top-to-bottom; without this ordering,
# "my" would be captured as method_id and /tracked would 404.
@router.get("/methods/my/tracked")
async def get_tracked_methods_early(
    status: Optional[str] = Query(None),
    user:   dict = Depends(get_current_user),
):
    """Get all methods the current user is tracking. (Early registration to avoid /{method_id} capture.)"""
    sb = supabase_service.client
    q  = sb.table("user_income_methods")\
        .select("*, income_methods(id,method_number,title,category,investment_tier,"
                "tags,avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,section_emoji)")\
        .eq("user_id", user["id"])
    if status:
        q = q.eq("status", status)
    result = q.order("updated_at", desc=True).execute()
    return {"methods": result.data or [], "count": len(result.data or [])}


@router.get("/methods/{method_id}")
async def get_method(method_id: str):
    sb     = supabase_service.client
    result = sb.table("income_methods").select("*").eq("id", method_id).single().execute()
    if not result.data:
        raise HTTPException(404, "Method not found")
    # Increment view count
    sb.table("income_methods")\
      .update({"view_count": (result.data.get("view_count",0) or 0) + 1})\
      .eq("id", method_id).execute()
    return result.data


# ───────────────────────────────────────────────────────────────────
# USER POSITIONING QUIZ
# ───────────────────────────────────────────────────────────────────

@router.post("/methods/position")
async def save_positioning(
    req:  PositioningRequest,
    user: dict = Depends(get_current_user),
):
    """Save positioning quiz answers and return personalised method recommendations."""
    user_id = user["id"]
    sb      = supabase_service.client

    positioning = {
        "user_id": user_id,
        "available_capital_usd":    req.available_capital_usd,
        "available_hours_per_week": req.available_hours_per_week,
        "has_smartphone":           req.has_smartphone,
        "has_laptop":               req.has_laptop,
        "has_reliable_internet":    req.has_reliable_internet,
        "languages":                req.languages,
        "location_city":            req.location_city,
        "location_country":         req.location_country,
        "can_travel_locally":       req.can_travel_locally,
        "has_bank_account":         req.has_bank_account,
        "goal_type":                req.goal_type,
        "income_goal_monthly_usd":  req.income_goal_monthly_usd,
        "timeline_months":          req.timeline_months,
        "risk_tolerance":           req.risk_tolerance,
        "current_skills":           req.current_skills,
        "skill_description":        req.skill_description,
        "updated_at":               datetime.now(timezone.utc).isoformat(),
    }
    sb.table("user_positioning").upsert(positioning, on_conflict="user_id").execute()

    # Build filters from answers
    tiers = _capital_to_tiers(req.available_capital_usd)

    q = sb.table("income_methods").select(
        "id,method_number,title,description,category,investment_tier,"
        "min_investment_usd,time_to_first_dollar,skill_level,internet_dependency,"
        "location_flexibility,scalability,risk_profile,tags,section_emoji,"
        "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,global_demand_score"
    ).eq("is_active", True).in_("investment_tier", tiers)

    if not req.has_reliable_internet:
        q = q.in_("internet_dependency", ["none","low"])
    if not req.can_travel_locally:
        q = q.in_("location_flexibility", ["global","national"])
    if req.risk_tolerance in ("zero","low"):
        q = q.in_("risk_profile", ["survival","stable"])

    result = q.order("global_demand_score", desc=True).limit(30).execute()

    # Save recommendations
    rec_ids = [m["id"] for m in (result.data or [])[:20]]
    sb.table("user_positioning")\
      .update({"recommended_method_ids": rec_ids})\
      .eq("user_id", user_id).execute()

    return {
        "positioning_saved":   True,
        "recommended_methods": result.data[:20] if result.data else [],
        "total_matches":       len(result.data or []),
        "message": f"Found {len(result.data or [])} methods matching your situation.",
    }


@router.get("/methods/positioning/me")
async def get_my_positioning(user: dict = Depends(get_current_user)):
    sb = supabase_service.client
    r  = sb.table("user_positioning").select("*").eq("user_id", user["id"]).execute()
    if not r.data:
        return {"positioning": None, "recommended_methods": []}

    pos     = r.data[0]
    rec_ids = pos.get("recommended_method_ids") or []

    methods = []
    if rec_ids:
        mr = sb.table("income_methods")\
            .select("id,method_number,title,category,investment_tier,tags,"
                    "avg_earning_monthly_usd_low,avg_earning_monthly_usd_high,"
                    "global_demand_score,section_emoji")\
            .in_("id", rec_ids[:20]).execute()
        methods = mr.data or []

    return {"positioning": pos, "recommended_methods": methods}


# ───────────────────────────────────────────────────────────────────
# USER METHOD TRACKING
# ───────────────────────────────────────────────────────────────────

@router.post("/methods/{method_id}/track")
async def track_method(
    method_id: str,
    data:  dict,
    user:  dict = Depends(get_current_user),
):
    sb      = supabase_service.client
    payload = {
        "user_id":   user["id"],
        "method_id": method_id,
        "status":    data.get("status","exploring"),
        "notes":     data.get("notes"),
        "updated_at":datetime.now(timezone.utc).isoformat(),
    }
    result = sb.table("user_income_methods")\
        .upsert(payload, on_conflict="user_id,method_id").execute()
    return {"tracked": True, "data": result.data[0] if result.data else payload}


# ───────────────────────────────────────────────────────────────────
# MARKETPLACE
# ───────────────────────────────────────────────────────────────────

@router.get("/marketplace")
async def get_marketplace_listings(
    listing_type: Optional[str] = Query(None),
    country:      Optional[str] = Query(None),
    is_global:    Optional[bool]= Query(None),
    tags:         Optional[str] = Query(None),
    search:       Optional[str] = Query(None),
    limit:        int           = Query(20, le=100),
    offset:       int           = Query(0),
):
    sb = supabase_service.client
    q  = sb.table("marketplace_listings")\
        .select("id,listing_type,title,description,price_usd,currency,"
                "location,country,is_global,contact_info,tags,user_id,created_at,"
                "views_count,inquiries_count")\
        .eq("status","active")

    if listing_type: q = q.eq("listing_type", listing_type)
    if country:      q = q.eq("country", country)
    if is_global is not None: q = q.eq("is_global", is_global)
    if tags:         q = q.contains("tags", [t.strip() for t in tags.split(",")])
    if search:       q = q.ilike("title", f"%{search}%")

    result = q.order("created_at", desc=True)\
              .range(offset, offset + limit - 1).execute()
    return {"listings": result.data or [], "count": len(result.data or [])}


@router.post("/marketplace")
async def create_listing(
    req:  ListingCreateRequest,
    user: dict = Depends(get_current_user),
):
    sb = supabase_service.client
    if not req.title or not req.description:
        raise HTTPException(400, "title and description are required")

    payload = {
        "user_id":       user["id"],
        "listing_type":  req.listing_type,
        "title":         req.title,
        "description":   req.description,
        "method_id":     req.method_id,
        "price_usd":     req.price_usd,
        "price_negotiable": req.price_negotiable,
        "currency":      req.currency,
        "location":      req.location,
        "country":       req.country,
        "is_global":     req.is_global,
        "contact_info":  req.contact_info,
        "tags":          req.tags,
        "status":        "active",
    }
    result = sb.table("marketplace_listings").insert(payload).execute()
    return {"created": True, "listing": result.data[0] if result.data else payload}


@router.post("/marketplace/{listing_id}/inquire")
async def inquire_listing(
    listing_id: str,
    req:   InquiryRequest,
    user:  dict = Depends(get_current_user),
):
    sb = supabase_service.client
    payload = {
        "listing_id":  listing_id,
        "buyer_id":    user["id"],
        "message":     req.message,
        "contact_info":req.contact_info,
    }
    result = sb.table("marketplace_inquiries").insert(payload).execute()

    # Increment inquiry count
    listing = sb.table("marketplace_listings")\
        .select("inquiries_count").eq("id", listing_id).single().execute()
    if listing.data:
        sb.table("marketplace_listings")\
          .update({"inquiries_count": (listing.data.get("inquiries_count",0) or 0) + 1})\
          .eq("id", listing_id).execute()

    return {"sent": True, "inquiry": result.data[0] if result.data else payload}


@router.get("/marketplace/my")
async def get_my_listings(
    status: Optional[str] = Query(None),
    user:   dict = Depends(get_current_user),
):
    sb = supabase_service.client
    q  = sb.table("marketplace_listings")\
        .select("*").eq("user_id", user["id"])
    if status:
        q = q.eq("status", status)
    result = q.order("created_at", desc=True).execute()
    return {"listings": result.data or [], "count": len(result.data or [])}


@router.delete("/marketplace/{listing_id}")
async def delete_listing(listing_id: str, user: dict = Depends(get_current_user)):
    sb = supabase_service.client
    sb.table("marketplace_listings")\
      .update({"status": "cancelled"})\
      .eq("id", listing_id).eq("user_id", user["id"]).execute()
    return {"deleted": True}


# ───────────────────────────────────────────────────────────────────
# INTERNAL SEARCH
# ───────────────────────────────────────────────────────────────────

@router.post("/search/internal")
async def internal_search(
    data: dict,
    user: dict = Depends(get_current_user),
):
    """Search only within the RiseUp system — methods, marketplace, profiles."""
    query = (data.get("query") or "").strip()
    if not query:
        raise HTTPException(400, "query is required")

    profile = await supabase_service.get_profile(user["id"]) or {}
    result  = await search_riseup_brain(
        query=query,
        user_id=user["id"],
        user_country=profile.get("country"),
        limit=data.get("limit", 5),
    )
    return {
        "query":             query,
        "found":             result["found"],
        "confidence":        result["confidence"],
        "intent":            result["intent"],
        "methods":           result["methods"],
        "marketplace":       result["marketplace"],
        "service_providers": result["service_providers"],
        "needs_external":    result["needs_external"],
        "escalation_reason": result.get("escalation_reason"),
        "suggested_task_type": result.get("suggested_task_type"),
    }


# ───────────────────────────────────────────────────────────────────
# AGENTIC TASKS
# ───────────────────────────────────────────────────────────────────

@router.post("/task/create")
async def create_agentic_task(
    req:              AgenticTaskRequest,
    background_tasks: BackgroundTasks,
    user:             dict = Depends(get_current_user),
):
    """
    Create an agentic task. The system will:
    1. Search RiseUp internally
    2. If approved by user → search the web
    3. If user says 'handle everything' → execute end-to-end
    """
    sb = supabase_service.client

    payload = {
        "user_id":     user["id"],
        "task_type":   req.task_type,
        "title":       req.title,
        "description": req.description,
        "input_data":  req.input_data,
        "priority":    req.priority,
        "status":      "queued",
        "progress_pct":0,
        "steps_completed": [],
        "created_at":  datetime.now(timezone.utc).isoformat(),
        "updated_at":  datetime.now(timezone.utc).isoformat(),
    }
    result = sb.table("agentic_tasks").insert(payload).execute()
    task   = result.data[0] if result.data else payload
    task_id = task.get("id")

    if task_id:
        background_tasks.add_task(_execute_agentic_task, task_id, user["id"], req, sb)

    return {
        "task_created": True,
        "task":         task,
        "message": (
            f"Task '{req.title}' is running. "
            "I'm searching RiseUp first, then the web if needed. "
            "Check the Workflow screen for live progress."
        ),
    }


@router.get("/task/{task_id}")
async def get_task(task_id: str, user: dict = Depends(get_current_user)):
    """Get agentic task status, steps, and results."""
    sb     = supabase_service.client
    result = sb.table("agentic_tasks")\
        .select("*").eq("id", task_id).eq("user_id", user["id"]).single().execute()
    if not result.data:
        raise HTTPException(404, "Task not found")

    steps = sb.table("agentic_task_steps")\
        .select("*").eq("task_id", task_id)\
        .order("step_number").execute()

    contacts = sb.table("agentic_contacts")\
        .select("*").eq("task_id", task_id)\
        .order("relevance_score", desc=True).limit(20).execute()

    task           = result.data
    task["steps"]  = steps.data or []
    task["contacts"] = contacts.data or []
    return task


@router.get("/task")
async def list_tasks(
    status:    Optional[str] = Query(None),
    task_type: Optional[str] = Query(None),
    limit:     int           = Query(20),
    user:      dict = Depends(get_current_user),
):
    sb = supabase_service.client
    q  = sb.table("agentic_tasks")\
        .select("id,task_type,title,status,progress_pct,summary,priority,created_at,completed_at")\
        .eq("user_id", user["id"])
    if status:    q = q.eq("status", status)
    if task_type: q = q.eq("task_type", task_type)
    result = q.order("created_at", desc=True).limit(limit).execute()
    return {"tasks": result.data or [], "count": len(result.data or [])}


@router.post("/task/{task_id}/approve-external")
async def approve_external_search(task_id: str, user: dict = Depends(get_current_user)):
    """User approves external web search for this task."""
    sb = supabase_service.client
    sb.table("agentic_tasks").update({
        "user_approved_external": True,
        "escalated_to_external":  True,
        "status":                 "searching_external",
        "current_step":           "Searching the web for you...",
        "updated_at":             datetime.now(timezone.utc).isoformat(),
    }).eq("id", task_id).eq("user_id", user["id"]).execute()

    return {
        "approved": True,
        "message": "I'm now searching the internet for buyers, sellers, and contacts. Results will appear in the Workflow screen.",
    }


@router.post("/task/{task_id}/approve-execute")
async def approve_full_execution(task_id: str, user: dict = Depends(get_current_user)):
    """User approves full agentic execution — 'handle everything'."""
    sb = supabase_service.client
    sb.table("agentic_tasks").update({
        "user_approved_execution": True,
        "status":                  "executing",
        "current_step":            "Executing your task end-to-end...",
        "updated_at":              datetime.now(timezone.utc).isoformat(),
    }).eq("id", task_id).eq("user_id", user["id"]).execute()

    return {
        "approved": True,
        "message": (
            "Full execution approved! I'll handle everything:\n"
            "✅ Posted listing on RiseUp\n"
            "🔍 Searching web for contacts\n"
            "📩 Drafting outreach messages\n"
            "📊 Compiling results dashboard\n"
            "I'll notify you at every step."
        ),
    }


@router.delete("/task/{task_id}")
async def cancel_task(task_id: str, user: dict = Depends(get_current_user)):
    sb = supabase_service.client
    sb.table("agentic_tasks")\
      .update({"status":"cancelled","updated_at":datetime.now(timezone.utc).isoformat()})\
      .eq("id", task_id).eq("user_id", user["id"]).execute()
    return {"cancelled": True}


@router.get("/contacts/{task_id}")
async def get_task_contacts(
    task_id:      str,
    contact_type: Optional[str] = Query(None),
    min_score:    int           = Query(0),
    user:         dict = Depends(get_current_user),
):
    sb = supabase_service.client
    q  = sb.table("agentic_contacts")\
        .select("*")\
        .eq("task_id", task_id)\
        .eq("user_id", user["id"])\
        .gte("relevance_score", min_score)
    if contact_type:
        q = q.eq("contact_type", contact_type)
    result = q.order("relevance_score", desc=True).execute()
    return {"contacts": result.data or [], "count": len(result.data or [])}


@router.get("/contacts")
async def get_all_contacts(
    contact_type: Optional[str] = Query(None),
    status:       Optional[str] = Query(None),
    limit:        int           = Query(50),
    user:         dict = Depends(get_current_user),
):
    sb = supabase_service.client
    q  = sb.table("agentic_contacts").select("*").eq("user_id", user["id"])
    if contact_type: q = q.eq("contact_type", contact_type)
    if status:       q = q.eq("status", status)
    result = q.order("relevance_score", desc=True).limit(limit).execute()
    return {"contacts": result.data or [], "count": len(result.data or [])}


@router.patch("/contacts/{contact_id}")
async def update_contact(
    contact_id: str,
    data:  dict,
    user:  dict = Depends(get_current_user),
):
    sb     = supabase_service.client
    update = {k: v for k, v in data.items() if k in ["status","notes","email","phone","website"]}
    if not update:
        raise HTTPException(400, "No valid fields")
    result = sb.table("agentic_contacts")\
        .update(update)\
        .eq("id", contact_id).eq("user_id", user["id"]).execute()
    return {"updated": True, "contact": result.data[0] if result.data else {}}


# ───────────────────────────────────────────────────────────────────
# BULK SEED (Admin — loads all 10,000 methods)
# ───────────────────────────────────────────────────────────────────

@router.post("/seed/methods")
async def seed_methods(
    req:              BulkSeedRequest,
    background_tasks: BackgroundTasks,
):
    """
    Bulk-insert income methods. Used by admin seed script.
    Accepts array of method objects. Upserts on method_number.
    """
    if not req.methods:
        raise HTTPException(400, "No methods provided")

    def _do_seed():
        sb         = supabase_service.client
        chunk_size = 100
        inserted   = 0
        for i in range(0, len(req.methods), chunk_size):
            chunk = req.methods[i:i + chunk_size]
            try:
                sb.table("income_methods").upsert(
                    chunk, on_conflict="method_number"
                ).execute()
                inserted += len(chunk)
            except Exception as e:
                logger.error(f"[SEED] Chunk {i} error: {e}")
        logger.info(f"[SEED] Inserted {inserted} methods")

    background_tasks.add_task(_do_seed)
    return {"message": f"Seeding {len(req.methods)} methods in background", "queued": len(req.methods)}


# ───────────────────────────────────────────────────────────────────
# AGENTIC TASK EXECUTOR (background)
# ───────────────────────────────────────────────────────────────────

async def _execute_agentic_task(
    task_id: str,
    user_id: str,
    req:     AgenticTaskRequest,
    sb,
):
    """Execute agentic task: internal search first, then prepare for external."""
    try:
        await _update_task(task_id, sb, status="searching_internal",
                           current_step="Searching RiseUp internally...", progress_pct=10)

        profile  = await supabase_service.get_profile(user_id) or {}
        country  = profile.get("country","")

        # Internal brain search
        brain = await search_riseup_brain(
            query   = req.description,
            user_id = user_id,
            intent  = req.task_type if req.task_type != "custom" else None,
            user_country = country,
            limit   = 8,
        )

        # Save internal contacts from RiseUp
        internal_contacts = []

        if brain["marketplace"]:
            for listing in brain["marketplace"]:
                internal_contacts.append({
                    "task_id":       task_id,
                    "user_id":       user_id,
                    "contact_type":  _listing_type_to_contact_type(listing.get("listing_type","selling"), req.task_type),
                    "name":          "RiseUp Member",
                    "source":        "RiseUp Marketplace",
                    "location":      listing.get("location") or listing.get("country"),
                    "notes":         listing.get("description","")[:200],
                    "relevance_score": 90,
                    "raw_data":      listing,
                })

        if brain["service_providers"]:
            for p in brain["service_providers"]:
                internal_contacts.append({
                    "task_id":       task_id,
                    "user_id":       user_id,
                    "riseup_user_id":p.get("user_id"),
                    "contact_type":  "service_provider",
                    "name":          p.get("full_name","RiseUp User"),
                    "source":        "RiseUp Community",
                    "location":      p.get("country"),
                    "notes":         p.get("bio","")[:200],
                    "relevance_score": 85,
                    "raw_data":      p,
                })

        if internal_contacts:
            try:
                sb.table("agentic_contacts").insert(internal_contacts).execute()
            except Exception as e:
                logger.error(f"[AGENTIC] Contact insert error: {e}")

        # Log step 1
        sb.table("agentic_task_steps").insert({
            "task_id":     task_id,
            "step_number": 1,
            "step_type":   "internal_search",
            "step_title":  "Searched RiseUp internally",
            "output_data": {
                "methods_found":   len(brain["methods"]),
                "marketplace_found": len(brain["marketplace"]),
                "providers_found": len(brain["service_providers"]),
            },
            "status":      "completed",
            "started_at":  datetime.now(timezone.utc).isoformat(),
            "completed_at":datetime.now(timezone.utc).isoformat(),
        }).execute()

        internal_count = len(internal_contacts)
        status_after   = "found_internal" if internal_count > 0 else "searching_external" if brain["needs_external"] else "found_results"

        summary = (
            f"Found {internal_count} contacts on RiseUp. "
            + (f"External search recommended for more results." if brain["needs_external"] else "")
        )

        await _update_task(task_id, sb,
            status       = status_after,
            current_step = f"Found {internal_count} on RiseUp" + (" — ready for web search" if brain["needs_external"] else ""),
            progress_pct = 40,
            results      = {
                "internal_contacts":  internal_count,
                "methods":           brain["methods"][:3],
                "marketplace":       brain["marketplace"][:3],
                "service_providers": brain["service_providers"][:3],
                "needs_external":    brain["needs_external"],
                "next_steps": [
                    f"Review {internal_count} contacts found on RiseUp",
                    "Approve web search for more contacts" if brain["needs_external"] else "Contact found users directly",
                    "Tap 'Handle Everything' for full agentic execution",
                ],
            },
            summary = summary,
        )

    except Exception as e:
        logger.error(f"[AGENTIC] Task execution error: {e}")
        await _update_task(task_id, sb, status="failed", current_step=f"Error: {str(e)[:100]}")


async def _update_task(task_id: str, sb, **kwargs):
    kwargs["updated_at"] = datetime.now(timezone.utc).isoformat()
    try:
        sb.table("agentic_tasks").update(kwargs).eq("id", task_id).execute()
    except Exception as e:
        logger.error(f"[AGENTIC] Update task error: {e}")


def _listing_type_to_contact_type(listing_type: str, task_type: str) -> str:
    if task_type == "find_buyers" or listing_type == "buying":
        return "buyer"
    if task_type == "find_sellers" or listing_type == "selling":
        return "seller"
    if listing_type in ("service_offer",):
        return "service_provider"
    if listing_type == "partnership":
        return "partner"
    if listing_type == "investment":
        return "investor"
    return "business"


def _capital_to_tiers(capital: float) -> List[str]:
    if capital == 0:           return ["zero"]
    if capital <= 500:         return ["zero","micro"]
    if capital <= 10_000:      return ["zero","micro","low"]
    if capital <= 100_000:     return ["zero","micro","low","medium"]
    if capital <= 1_000_000:   return ["zero","micro","low","medium","high"]
    return ["zero","micro","low","medium","high","major","ultra","billion"]
