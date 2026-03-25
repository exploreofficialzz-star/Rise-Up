"""
RiseUp AI Workflow Engine
─────────────────────────
Primary currency: USD (global default).
Users can view amounts in their local currency via the toggle on the frontend.
"""

import json
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/workflow", tags=["AI Workflow Engine"])
logger = logging.getLogger(__name__)


# ── Request / Response Models ─────────────────────────────────────
class ResearchRequest(BaseModel):
    goal: str
    currency: Optional[str] = "USD"              # defaults to USD
    available_hours_per_day: Optional[float] = 2.0
    budget: Optional[float] = 0.0               # investment budget in USD


class CreateWorkflowRequest(BaseModel):
    title: str
    goal: str
    income_type: str
    research_data: dict
    currency: Optional[str] = "USD"


class LogRevenueRequest(BaseModel):
    amount: float
    currency: Optional[str] = "USD"
    source: Optional[str] = ""
    note: Optional[str] = ""


class UpdateStepRequest(BaseModel):
    status: str     # pending / in_progress / done / skipped


# ── AI Research Prompt ────────────────────────────────────────────
def _build_research_prompt(goal: str, budget: float, hours: float, currency: str) -> str:
    budget_label = "ZERO ($0 / free tools only)" if budget == 0 else f"${budget} USD"
    return f"""You are RiseUp's deep research engine. A user has an income goal and you must do REAL research and give EXECUTION-READY results — not generic tips.

USER GOAL: {goal}
DAILY TIME AVAILABLE: {hours} hours/day
STARTING BUDGET: {budget_label}
PRIMARY CURRENCY: {currency}

YOUR JOB — Analyze this goal and return a JSON object (NO markdown, NO backticks, ONLY raw JSON) with this EXACT structure:

{{
  "income_type": "youtube|freelance|ecommerce|physical|affiliate|content|service|other",
  "title": "Short catchy workflow title (max 8 words)",
  "viability_score": 85,
  "realistic_timeline": "6-8 weeks",
  "potential_monthly_income": {{
    "min": 200,
    "max": 800,
    "currency": "USD"
  }},
  "what_is_working_now": [
    "Specific thing that works in 2025/2026 for this income type",
    "Another specific current strategy with real data/context",
    "Third working strategy"
  ],
  "breakdown": {{
    "ai_can_do": [
      {{"task": "Research video topics & trending keywords", "how": "AI scans YouTube trends & suggests titles", "saves_hours": 3}},
      {{"task": "Write video scripts", "how": "AI generates full script from topic", "saves_hours": 2}},
      {{"task": "Generate thumbnail ideas", "how": "AI writes Canva-ready thumbnail text & layout", "saves_hours": 1}}
    ],
    "user_must_do": [
      {{"task": "Record the video", "why": "Requires your face/voice — can't be automated", "time_required": "1-2 hours"}},
      {{"task": "Upload and optimize", "why": "Requires your YouTube account login", "time_required": "30 min"}}
    ],
    "can_outsource_later": [
      {{"task": "Video editing", "cost_when_ready": "$5-15/video", "platform": "Fiverr"}}
    ]
  }},
  "free_tools": [
    {{"name": "Canva Free", "url": "canva.com", "purpose": "Thumbnails & channel art", "category": "design"}},
    {{"name": "TubeBuddy Free", "url": "tubebuddy.com", "purpose": "Keyword research & tag optimization", "category": "analytics"}},
    {{"name": "OBS Studio", "url": "obsproject.com", "purpose": "Free screen/video recording", "category": "recording"}},
    {{"name": "DaVinci Resolve Free", "url": "blackmagicdesign.com/products/davinciresolve", "purpose": "Professional video editing — free", "category": "editing"}}
  ],
  "paid_tools_when_ready": [
    {{"name": "TubeBuddy Pro", "cost_monthly": 9, "currency": "USD", "purpose": "Advanced A/B testing + analytics", "unlock_at_revenue": 500}}
  ],
  "step_by_step_workflow": [
    {{"order": 1, "title": "Set up your YouTube channel", "description": "Create channel, add art, write description with keywords", "type": "manual", "time_minutes": 45, "tools": ["Canva Free"]}},
    {{"order": 2, "title": "AI researches your first 10 video topics", "description": "Tell RiseUp your niche and it generates 10 optimized titles + descriptions", "type": "automated", "time_minutes": 5, "tools": []}},
    {{"order": 3, "title": "Record your first video", "description": "Use your phone. 5-10 mins. Focus on solving one problem.", "type": "manual", "time_minutes": 30, "tools": ["OBS Studio"]}},
    {{"order": 4, "title": "AI writes your SEO description + tags", "description": "Paste your topic, RiseUp generates the full description + 20 tags", "type": "automated", "time_minutes": 2, "tools": []}},
    {{"order": 5, "title": "Upload + monetization setup", "description": "Enable monetization, join YouTube Partner Program when eligible", "type": "manual", "time_minutes": 20, "tools": []}},
    {{"order": 6, "title": "Track your growth weekly", "description": "Log views, subs, and first revenue in RiseUp", "type": "manual", "time_minutes": 10, "tools": []}}
  ],
  "physical_business_note": null,
  "automation_opportunities": [
    "Script generation from any topic title",
    "SEO tags and description optimization",
    "Thumbnail text and layout suggestions",
    "Comment reply templates",
    "Posting schedule optimization"
  ],
  "revenue_milestones": [
    {{"milestone": "First 1,000 subscribers", "action": "Apply for YouTube Partner Program", "expected_at_week": 8}},
    {{"milestone": "First monetized video", "action": "Enable ads, add affiliate links", "expected_revenue_usd": 50}}
  ],
  "success_factors": [
    "Consistency is everything — post 2-3 times/week minimum",
    "Solve specific problems — don't be generic",
    "Engage in comments for first 48 hours of every upload"
  ],
  "honest_warning": "YouTube takes 3-6 months to generate serious income. The first month is about learning and building. Don't quit after 2 videos."
}}

CRITICAL RULES:
- All revenue figures must be in USD (the app converts to local currency automatically)
- If budget is $0, ALL tools must be free — no exceptions
- Steps must be ACTIONABLE today, not vague
- Revenue estimates must be REALISTIC for a beginner, not hype numbers
- Be SPECIFIC to what's actually working in 2025/2026
- Return ONLY the JSON object. No explanation. No markdown."""


# ── Endpoints ─────────────────────────────────────────────────────

@router.post("/research")
@limiter.limit(AI_LIMIT)
async def research_income_goal(
    req: ResearchRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Deep AI research on an income goal."""
    # Use user profile currency as context if not specified
    profile = await supabase_service.get_profile(user["id"])
    effective_currency = req.currency or (profile.get("currency") if profile else None) or "USD"

    prompt = _build_research_prompt(
        req.goal, req.budget or 0.0,
        req.available_hours_per_day or 2.0,
        effective_currency
    )

    result = await ai_service.chat(
        messages=[{"role": "user", "content": prompt}],
        system="You are a deep income research engine. Return ONLY valid JSON. No markdown. No explanation. No backticks.",
        max_tokens=2500,
    )

    content = result["content"].strip()
    if content.startswith("```"):
        content = content.split("```")[1]
        if content.startswith("json"):
            content = content[4:]
    content = content.strip()

    try:
        research_data = json.loads(content)
    except json.JSONDecodeError:
        start = content.find("{")
        end = content.rfind("}") + 1
        if start >= 0 and end > start:
            research_data = json.loads(content[start:end])
        else:
            raise HTTPException(status_code=500, detail="AI research failed to return valid data. Try again.")

    return {
        "goal": req.goal,
        "research": research_data,
        "ai_model_used": result.get("model", "unknown"),
    }


@router.post("/create")
@limiter.limit(GENERAL_LIMIT)
async def create_workflow(
    req: CreateWorkflowRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Create a workflow from AI research results and save to Supabase."""
    user_id = user["id"]
    sb = supabase_service.client

    effective_currency = req.currency or "USD"

    workflow_resp = sb.table("workflows").insert({
        "user_id":            user_id,
        "title":              req.title,
        "goal":               req.goal,
        "income_type":        req.income_type,
        "currency":           effective_currency,
        "status":             "active",
        "total_revenue":      0.0,
        "viability_score":    req.research_data.get("viability_score", 75),
        "realistic_timeline": req.research_data.get("realistic_timeline", ""),
        "potential_min":      req.research_data.get("potential_monthly_income", {}).get("min", 0),
        "potential_max":      req.research_data.get("potential_monthly_income", {}).get("max", 0),
        "honest_warning":     req.research_data.get("honest_warning", ""),
        "research_snapshot":  json.dumps(req.research_data),
    }).execute()

    workflow = workflow_resp.data[0]
    workflow_id = workflow["id"]

    # Save workflow steps
    steps = req.research_data.get("step_by_step_workflow", [])
    if steps:
        step_rows = [{
            "workflow_id":  workflow_id,
            "user_id":      user_id,
            "order_index":  s.get("order", i + 1),
            "title":        s.get("title", ""),
            "description":  s.get("description", ""),
            "step_type":    s.get("type", "manual"),
            "time_minutes": s.get("time_minutes", 30),
            "tools":        json.dumps(s.get("tools", [])),
            "status":       "pending",
        } for i, s in enumerate(steps)]
        sb.table("workflow_steps").insert(step_rows).execute()

    # Save free tools
    free_tools = req.research_data.get("free_tools", [])
    if free_tools:
        tool_rows = [{
            "workflow_id": workflow_id,
            "name":        t.get("name", ""),
            "url":         t.get("url", ""),
            "purpose":     t.get("purpose", ""),
            "category":    t.get("category", ""),
            "is_free":     True,
        } for t in free_tools]
        sb.table("workflow_tools").insert(tool_rows).execute()

    # Save paid tools
    paid_tools = req.research_data.get("paid_tools_when_ready", [])
    if paid_tools:
        paid_rows = [{
            "workflow_id":       workflow_id,
            "name":              t.get("name", ""),
            "url":               "",
            "purpose":           t.get("purpose", ""),
            "category":          "upgrade",
            "is_free":           False,
            "cost_monthly":      t.get("cost_monthly", 0),
            "unlock_at_revenue": t.get("unlock_at_revenue", 0),
        } for t in paid_tools]
        sb.table("workflow_tools").insert(paid_rows).execute()

    return {
        "workflow_id": workflow_id,
        "title":       req.title,
        "status":      "created",
        "message":     "Workflow created! Your income execution plan is ready.",
    }


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_my_workflows(request: Request, user: dict = Depends(get_current_user)):
    """Get all workflows for the current user."""
    user_id = user["id"]
    sb = supabase_service.client

    resp = sb.table("workflows")\
        .select("id, title, goal, income_type, status, total_revenue, currency, viability_score, realistic_timeline, potential_min, potential_max, created_at")\
        .eq("user_id", user_id)\
        .order("created_at", desc=True)\
        .execute()

    return {"workflows": resp.data or []}


@router.get("/{workflow_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_workflow_detail(
    workflow_id: str, request: Request, user: dict = Depends(get_current_user)
):
    """Get full workflow details — steps, tools, revenue."""
    user_id = user["id"]
    sb = supabase_service.client

    wf_resp = sb.table("workflows")\
        .select("*")\
        .eq("id", workflow_id)\
        .eq("user_id", user_id)\
        .single()\
        .execute()

    if not wf_resp.data:
        raise HTTPException(status_code=404, detail="Workflow not found")

    workflow = wf_resp.data
    steps_resp  = sb.table("workflow_steps").select("*").eq("workflow_id", workflow_id).order("order_index").execute()
    tools_resp  = sb.table("workflow_tools").select("*").eq("workflow_id", workflow_id).execute()
    revenue_resp = sb.table("workflow_revenue").select("*").eq("workflow_id", workflow_id).order("created_at", desc=True).limit(20).execute()

    steps = steps_resp.data or []
    for s in steps:
        if isinstance(s.get("tools"), str):
            try:
                s["tools"] = json.loads(s["tools"])
            except Exception:
                s["tools"] = []

    return {
        "workflow": workflow,
        "steps":    steps,
        "tools":    {
            "free":         [t for t in (tools_resp.data or []) if t.get("is_free")],
            "paid_upgrades":[t for t in (tools_resp.data or []) if not t.get("is_free")],
        },
        "revenue_logs": revenue_resp.data or [],
    }


@router.patch("/{workflow_id}/step/{step_id}")
@limiter.limit(GENERAL_LIMIT)
async def update_step_status(
    workflow_id: str, step_id: str, req: UpdateStepRequest,
    request: Request, user: dict = Depends(get_current_user)
):
    """Mark a workflow step as done / in_progress / skipped."""
    user_id = user["id"]
    sb = supabase_service.client

    sb.table("workflow_steps")\
        .update({"status": req.status, "updated_at": datetime.now(timezone.utc).isoformat()})\
        .eq("id", step_id).eq("workflow_id", workflow_id).eq("user_id", user_id)\
        .execute()

    all_steps = sb.table("workflow_steps").select("status").eq("workflow_id", workflow_id).execute()
    total = len(all_steps.data or [])
    done  = sum(1 for s in (all_steps.data or []) if s["status"] == "done")
    progress_pct = int((done / total * 100)) if total > 0 else 0

    sb.table("workflows").update({"progress_percent": progress_pct}).eq("id", workflow_id).execute()

    return {"step_id": step_id, "status": req.status, "overall_progress": progress_pct}


@router.post("/{workflow_id}/log-revenue")
@limiter.limit(GENERAL_LIMIT)
async def log_revenue(
    workflow_id: str, req: LogRevenueRequest,
    request: Request, user: dict = Depends(get_current_user)
):
    """Log revenue earned from this workflow. Defaults to USD."""
    user_id = user["id"]
    sb = supabase_service.client
    effective_currency = req.currency or "USD"

    sb.table("workflow_revenue").insert({
        "workflow_id": workflow_id,
        "user_id":     user_id,
        "amount":      req.amount,
        "currency":    effective_currency,
        "source":      req.source or "",
        "note":        req.note or "",
    }).execute()

    wf = sb.table("workflows").select("total_revenue").eq("id", workflow_id).single().execute()
    current   = float(wf.data.get("total_revenue", 0) if wf.data else 0)
    new_total = current + req.amount

    sb.table("workflows").update({"total_revenue": new_total}).eq("id", workflow_id).execute()

    try:
        sb.table("earnings").insert({
            "user_id":     user_id,
            "amount":      req.amount,
            "currency":    effective_currency,
            "source":      f"Workflow: {req.source or 'workflow'}",
            "note":        req.note or "",
            "workflow_id": workflow_id,
        }).execute()
    except Exception:
        pass

    return {
        "logged":          req.amount,
        "workflow_total":  new_total,
        "currency":        effective_currency,
        "message":         f"Revenue logged! Total from this workflow: {effective_currency} {new_total:,.2f}",
    }


@router.get("/{workflow_id}/analytics")
@limiter.limit(GENERAL_LIMIT)
async def workflow_analytics(
    workflow_id: str, request: Request, user: dict = Depends(get_current_user)
):
    """Analytics for a workflow — revenue over time, step completion rate."""
    user_id = user["id"]
    sb = supabase_service.client

    rev_resp = sb.table("workflow_revenue")\
        .select("amount, currency, created_at, source")\
        .eq("workflow_id", workflow_id).eq("user_id", user_id)\
        .order("created_at").execute()

    logs = rev_resp.data or []

    steps_resp = sb.table("workflow_steps").select("status, step_type").eq("workflow_id", workflow_id).execute()
    steps    = steps_resp.data or []
    total    = len(steps)
    done     = sum(1 for s in steps if s["status"] == "done")
    automated= sum(1 for s in steps if s["step_type"] == "automated")
    manual   = sum(1 for s in steps if s["step_type"] == "manual")

    daily = {}
    for log in logs:
        day = log["created_at"][:10]
        daily[day] = daily.get(day, 0) + float(log["amount"])

    total_revenue = sum(float(l["amount"]) for l in logs)

    return {
        "workflow_id":    workflow_id,
        "total_revenue":  total_revenue,
        "currency":       "USD",
        "revenue_logs":   logs,
        "daily_revenue":  [{"date": d, "amount": a} for d, a in sorted(daily.items())],
        "steps_summary":  {
            "total": total, "done": done,
            "remaining": total - done,
            "progress_percent": int(done / total * 100) if total > 0 else 0,
            "automated_steps": automated, "manual_steps": manual,
        },
    }


@router.post("/{workflow_id}/ai-assist")
@limiter.limit(AI_LIMIT)
async def ai_assist_on_step(
    workflow_id: str, request: Request,
    step_title: str, user_question: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """AI executes or assists on a specific workflow step."""
    sb = supabase_service.client
    wf = sb.table("workflows").select("title, goal, income_type").eq("id", workflow_id).single().execute()
    wf_data = wf.data or {}

    question = user_question or f"Help me complete this step: {step_title}"

    prompt = f"""You are RiseUp AI executing a workflow step for a user.

WORKFLOW: {wf_data.get('title', '')}
GOAL: {wf_data.get('goal', '')}
INCOME TYPE: {wf_data.get('income_type', '')}
CURRENT STEP: {step_title}
USER REQUEST: {question}

Provide specific, actionable, ready-to-use output for this step.
If it's content (script, description, tags) — write the full content, ready to copy-paste.
If it's strategy — give exact steps to take TODAY.
Be specific, not generic. This user is counting on you to get real results."""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": prompt}],
        system="You are an AI income execution engine. Produce real, usable output — not advice.",
        max_tokens=1500,
    )

    return {
        "step":       step_title,
        "ai_output":  result["content"],
        "model_used": result.get("model", "unknown"),
    }
