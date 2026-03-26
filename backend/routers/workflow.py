"""
RiseUp AI Workflow Engine
─────────────────────────
Core Vision: Don't just give tips — research deeply, break down the work,
automate what's possible, find free tools, create a managed workflow,
and track real revenue per task.

ENHANCED VERSION: Fixed Supabase async deadlocks, added timeouts,
background tasks, and parallel processing to prevent hanging.
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/workflow", tags=["AI Workflow Engine"])
logger = logging.getLogger(__name__)


# ═════════════════════════════════════════════════════════════════════════════
# CRITICAL FIX: Timeout wrapper to prevent Supabase async deadlocks
# ═════════════════════════════════════════════════════════════════════════════

async def supabase_with_timeout(coro, timeout: float = 8.0, operation: str = "db_op"):
    """
    Execute Supabase operation with strict timeout to prevent hanging.
    The Supabase Python client has known deadlock issues with sequential async calls.
    """
    try:
        return await asyncio.wait_for(coro, timeout=timeout)
    except asyncio.TimeoutError:
        logger.error(f"🔥 Supabase DEADLOCK: Operation '{operation}' timed out after {timeout}s")
        raise HTTPException(
            status_code=504, 
            detail=f"Database operation timed out: {operation}. Please retry."
        )
    except Exception as e:
        logger.error(f"❌ Supabase error in '{operation}': {str(e)}")
        raise HTTPException(status_code=500, detail=f"Database error: {operation}")


# ═════════════════════════════════════════════════════════════════════════════
# Request / Response Models
# ═════════════════════════════════════════════════════════════════════════════

class ResearchRequest(BaseModel):
    goal: str                          # "I want to earn on YouTube in 2 months"
    currency: Optional[str] = "NGN"
    available_hours_per_day: Optional[float] = 2.0
    budget: Optional[float] = 0.0     # How much they can invest ($0 = free tools only)


class CreateWorkflowRequest(BaseModel):
    title: str
    goal: str
    income_type: str                   # youtube, freelance, physical, ecommerce, etc.
    research_data: dict                # The AI research result
    currency: Optional[str] = "NGN"


class LogRevenueRequest(BaseModel):
    amount: float
    currency: Optional[str] = "NGN"
    source: Optional[str] = ""
    note: Optional[str] = ""


class UpdateStepRequest(BaseModel):
    status: str                        # pending / in_progress / done / skipped


# ═════════════════════════════════════════════════════════════════════════════
# AI Research Prompt
# ═════════════════════════════════════════════════════════════════════════════

def _build_research_prompt(goal: str, budget: float, hours: float, currency: str) -> str:
    budget_label = "ZERO ($0 / free tools only)" if budget == 0 else f"${budget}"
    return f"""You are RiseUp's deep research engine. A user has an income goal and you must do REAL research and give EXECUTION-READY results — not generic tips.

USER GOAL: {goal}
DAILY TIME AVAILABLE: {hours} hours/day
STARTING BUDGET: {budget_label}
PREFERRED CURRENCY: {currency}

YOUR JOB — Analyze this goal and return a JSON object (NO markdown, NO backticks, ONLY raw JSON) with this EXACT structure:

{{
  "income_type": "youtube|freelance|ecommerce|physical|affiliate|content|service|other",
  "title": "Short catchy workflow title (max 8 words)",
  "viability_score": 85,
  "realistic_timeline": "6-8 weeks",
  "potential_monthly_income": {{
    "min": 15000,
    "max": 80000,
    "currency": "{currency}"
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
    {{"name": "TubeBuddy Pro", "cost_monthly": 9, "currency": "USD", "purpose": "Advanced A/B testing + analytics", "unlock_at_revenue": 10000}}
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
    {{"milestone": "First monetized video", "action": "Enable ads, add affiliate links", "expected_revenue": 2000, "currency": "{currency}"}}
  ],
  "success_factors": [
    "Consistency is everything — post 2-3 times/week minimum",
    "Solve specific problems — don't be generic",
    "Engage in comments for first 48 hours of every upload"
  ],
  "honest_warning": "YouTube takes 3-6 months to generate serious income. The first month is about learning and building. Don't quit after 2 videos."
}}

CRITICAL RULES:
- Be SPECIFIC to what's actually working in 2025/2026
- If budget is $0, ALL tools must be free — no exceptions  
- Steps must be ACTIONABLE today, not vague
- Revenue estimates must be REALISTIC for a beginner, not hype numbers
- Return ONLY the JSON object. No explanation. No markdown."""


# ═════════════════════════════════════════════════════════════════════════════
# Background Task: Save workflow details (steps & tools)
# Prevents main request from hanging due to multiple sequential inserts
# ═════════════════════════════════════════════════════════════════════════════

async def _save_workflow_details(
    sb, 
    workflow_id: str, 
    user_id: str, 
    steps: list, 
    free_tools: list, 
    paid_tools: list
):
    """
    Background task to save workflow steps and tools.
    Runs independently to prevent blocking the main request/response cycle.
    """
    logger.info(f"🔄 Background task started for workflow {workflow_id}")
    
    errors = []
    
    try:
        # ── Insert steps ──
        if steps:
            step_rows = [{
                "workflow_id": workflow_id,
                "user_id": user_id,
                "order_index": s.get("order", i + 1),
                "title": s.get("title", ""),
                "description": s.get("description", ""),
                "step_type": s.get("type", "manual"),
                "time_minutes": s.get("time_minutes", 30),
                "tools": json.dumps(s.get("tools", [])),
                "status": "pending",
            } for i, s in enumerate(steps)]
            
            try:
                await supabase_with_timeout(
                    sb.table("workflow_steps").insert(step_rows).execute(),
                    timeout=15.0,
                    operation=f"insert_steps_{workflow_id}"
                )
                logger.info(f"✅ Inserted {len(step_rows)} steps for workflow {workflow_id}")
            except Exception as e:
                error_msg = f"Failed to insert steps: {str(e)}"
                logger.error(f"❌ {error_msg}")
                errors.append(error_msg)

        # ── Insert free tools ──
        if free_tools:
            tool_rows = [{
                "workflow_id": workflow_id,
                "name": t.get("name", ""),
                "url": t.get("url", ""),
                "purpose": t.get("purpose", ""),
                "category": t.get("category", ""),
                "is_free": True,
            } for t in free_tools]
            
            try:
                await supabase_with_timeout(
                    sb.table("workflow_tools").insert(tool_rows).execute(),
                    timeout=10.0,
                    operation=f"insert_free_tools_{workflow_id}"
                )
                logger.info(f"✅ Inserted {len(tool_rows)} free tools for workflow {workflow_id}")
            except Exception as e:
                error_msg = f"Failed to insert free tools: {str(e)}"
                logger.error(f"❌ {error_msg}")
                errors.append(error_msg)

        # ── Insert paid tools ──
        if paid_tools:
            paid_rows = [{
                "workflow_id": workflow_id,
                "name": t.get("name", ""),
                "url": "",
                "purpose": t.get("purpose", ""),
                "category": "upgrade",
                "is_free": False,
                "cost_monthly": t.get("cost_monthly", 0),
                "unlock_at_revenue": t.get("unlock_at_revenue", 0),
            } for t in paid_tools]
            
            try:
                await supabase_with_timeout(
                    sb.table("workflow_tools").insert(paid_rows).execute(),
                    timeout=10.0,
                    operation=f"insert_paid_tools_{workflow_id}"
                )
                logger.info(f"✅ Inserted {len(paid_rows)} paid tools for workflow {workflow_id}")
            except Exception as e:
                error_msg = f"Failed to insert paid tools: {str(e)}"
                logger.error(f"❌ {error_msg}")
                errors.append(error_msg)

        if errors:
            logger.warning(f"⚠️ Background task completed with {len(errors)} errors for workflow {workflow_id}")
        else:
            logger.info(f"🎉 Background task completed successfully for workflow {workflow_id}")

    except Exception as e:
        logger.exception(f"💥 Background task crashed for workflow {workflow_id}: {e}")


# ═════════════════════════════════════════════════════════════════════════════
# API Endpoints
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/research")
@limiter.limit(AI_LIMIT)
async def research_income_goal(
    req: ResearchRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Deep AI research on an income goal.
    Returns breakdown: what AI can do, what user must do,
    free tools, step-by-step workflow, and revenue milestones.
    """
    prompt = _build_research_prompt(
        req.goal, req.budget or 0.0,
        req.available_hours_per_day or 2.0,
        req.currency or "NGN"
    )

    # Add timeout to AI call to prevent hanging
    try:
        result = await asyncio.wait_for(
            ai_service.chat(
                messages=[{"role": "user", "content": prompt}],
                system="You are a deep income research engine. Return ONLY valid JSON. No markdown. No explanation. No backticks.",
                max_tokens=2500,
            ),
            timeout=30.0
        )
    except asyncio.TimeoutError:
        logger.error("AI research timed out after 30s")
        raise HTTPException(status_code=504, detail="AI research timed out. Please try again.")

    content = result.get("content", "").strip()
    
    # Robust JSON extraction with multiple fallback patterns
    research_data = None
    
    # Try direct parse first
    try:
        research_data = json.loads(content)
    except json.JSONDecodeError:
        pass
    
    # Try to extract from markdown code blocks
    if research_data is None:
        patterns = [
            (r'```json\s*([\s\S]*?)\s*```', 1),      # ```json ... ```
            (r'```\s*([\s\S]*?)\s*```', 1),          # ``` ... ```
            (r'(\{{[\s\S]*\}})', 0),                 # Raw JSON object (capture group 0 = full match)
        ]
        
        for pattern, group in patterns:
            match = re.search(pattern, content)
            if match:
                try:
                    candidate = match.group(group)
                    research_data = json.loads(candidate)
                    logger.info(f"JSON extracted using pattern: {pattern[:20]}...")
                    break
                except json.JSONDecodeError:
                    continue
    
    # Final fallback: find first { and last }
    if research_data is None:
        start = content.find('{')
        end = content.rfind('}')
        if start >= 0 and end > start:
            try:
                candidate = content[start:end+1]
                research_data = json.loads(candidate)
                logger.info("JSON extracted using bracket matching")
            except json.JSONDecodeError:
                pass
    
    if research_data is None:
        logger.error(f"JSON parse failed. Content preview: {content[:500]}")
        raise HTTPException(status_code=500, detail="AI returned invalid format. Please retry.")

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
    background_tasks: BackgroundTasks,
    user: dict = Depends(get_current_user)
):
    """
    Create a workflow from AI research results and save to Supabase.
    
    CRITICAL FIX: Uses timeouts and background tasks to prevent Supabase deadlock.
    Only the main workflow record is inserted synchronously.
    Steps and tools are saved in background to avoid hanging.
    """
    user_id = user["id"]
    sb = supabase_service.client
    workflow_id = None

    try:
        # ── STEP 1: Create main workflow record (with timeout protection) ──
        workflow_data = {
            "user_id": user_id,
            "title": req.title,
            "goal": req.goal,
            "income_type": req.income_type,
            "currency": req.currency or "NGN",
            "status": "active",
            "total_revenue": 0.0,
            "viability_score": req.research_data.get("viability_score", 75),
            "realistic_timeline": req.research_data.get("realistic_timeline", ""),
            "potential_min": req.research_data.get("potential_monthly_income", {}).get("min", 0),
            "potential_max": req.research_data.get("potential_monthly_income", {}).get("max", 0),
            "honest_warning": req.research_data.get("honest_warning", ""),
            "research_snapshot": json.dumps(req.research_data),
        }

        workflow_resp = await supabase_with_timeout(
            sb.table("workflows").insert(workflow_data).execute(),
            timeout=10.0,
            operation="insert_main_workflow"
        )

        if not workflow_resp.data:
            raise HTTPException(status_code=500, detail="Failed to create workflow - no data returned")

        workflow = workflow_resp.data[0]
        workflow_id = workflow["id"]
        logger.info(f"✅ Created workflow {workflow_id} for user {user_id}")

        # ── STEP 2: Queue steps & tools as background tasks (NON-BLOCKING) ──
        # This prevents the deadlock that occurs with multiple sequential inserts
        steps = req.research_data.get("step_by_step_workflow", [])
        free_tools = req.research_data.get("free_tools", [])
        paid_tools = req.research_data.get("paid_tools_when_ready", [])

        if steps or free_tools or paid_tools:
            background_tasks.add_task(
                _save_workflow_details,
                sb,
                workflow_id,
                user_id,
                steps,
                free_tools,
                paid_tools
            )
            logger.info(f"🔄 Queued background task for {len(steps)} steps, {len(free_tools)} free tools, {len(paid_tools)} paid tools")

        # Return immediately - don't wait for background tasks
        return {
            "workflow_id": workflow_id,
            "title": req.title,
            "status": "created",
            "message": "Workflow created! Your income execution plan is ready.",
            "details_queued": {
                "steps": len(steps),
                "free_tools": len(free_tools),
                "paid_tools": len(paid_tools)
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"💥 Workflow creation failed: {str(e)}")
        
        # Cleanup partial workflow if created
        if workflow_id:
            try:
                await supabase_with_timeout(
                    sb.table("workflows").delete().eq("id", workflow_id).execute(),
                    timeout=5.0,
                    operation="cleanup_failed_workflow"
                )
                logger.info(f"🧹 Cleaned up partial workflow {workflow_id}")
            except Exception as cleanup_error:
                logger.error(f"Failed to cleanup workflow {workflow_id}: {cleanup_error}")
        
        raise HTTPException(status_code=500, detail=f"Failed to create workflow: {str(e)}")


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_my_workflows(
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Get all workflows for the current user."""
    user_id = user["id"]
    sb = supabase_service.client

    try:
        resp = await supabase_with_timeout(
            sb.table("workflows")
            .select("id, title, goal, income_type, status, total_revenue, currency, viability_score, realistic_timeline, potential_min, potential_max, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute(),
            timeout=8.0,
            operation="list_workflows"
        )
        return {"workflows": resp.data or []}
    except Exception as e:
        logger.error(f"Failed to list workflows: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch workflows")


@router.get("/{workflow_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_workflow_detail(
    workflow_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Get full workflow details — steps, tools, revenue.
    
    ENHANCED: Fetches all data in parallel to prevent sequential hanging.
    """
    user_id = user["id"]
    sb = supabase_service.client

    try:
        # Fetch all data in parallel with individual timeouts
        # This prevents the "sequential query deadlock" issue
        coroutines = {
            "workflow": supabase_with_timeout(
                sb.table("workflows").select("*").eq("id", workflow_id).eq("user_id", user_id).single().execute(),
                timeout=5.0,
                operation="get_workflow"
            ),
            "steps": supabase_with_timeout(
                sb.table("workflow_steps").select("*").eq("workflow_id", workflow_id).order("order_index").execute(),
                timeout=5.0,
                operation="get_steps"
            ),
            "tools": supabase_with_timeout(
                sb.table("workflow_tools").select("*").eq("workflow_id", workflow_id).execute(),
                timeout=5.0,
                operation="get_tools"
            ),
            "revenue": supabase_with_timeout(
                sb.table("workflow_revenue").select("*").eq("workflow_id", workflow_id).order("created_at", desc=True).limit(20).execute(),
                timeout=5.0,
                operation="get_revenue"
            ),
        }

        # Execute all queries concurrently
        results = await asyncio.gather(*coroutines.values(), return_exceptions=True)
        results_dict = dict(zip(coroutines.keys(), results))

        # Check for any exceptions
        for key, result in results_dict.items():
            if isinstance(result, Exception):
                logger.error(f"Failed to fetch {key}: {result}")
                raise HTTPException(status_code=500, detail=f"Failed to fetch {key}")

        wf_resp = results_dict["workflow"]
        steps_resp = results_dict["steps"]
        tools_resp = results_dict["tools"]
        revenue_resp = results_dict["revenue"]

        if not wf_resp.data:
            raise HTTPException(status_code=404, detail="Workflow not found")

        workflow = wf_resp.data
        steps = steps_resp.data or []
        tools = tools_resp.data or []
        revenue_logs = revenue_resp.data or []

        # Parse steps tools field (stored as JSON string)
        for s in steps:
            if isinstance(s.get("tools"), str):
                try:
                    s["tools"] = json.loads(s["tools"])
                except Exception:
                    s["tools"] = []

        return {
            "workflow": workflow,
            "steps": steps,
            "tools": {
                "free": [t for t in tools if t.get("is_free")],
                "paid_upgrades": [t for t in tools if not t.get("is_free")],
            },
            "revenue_logs": revenue_logs,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get workflow detail: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch workflow details")


@router.patch("/{workflow_id}/step/{step_id}")
@limiter.limit(GENERAL_LIMIT)
async def update_step_status(
    workflow_id: str,
    step_id: str,
    req: UpdateStepRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Mark a workflow step as done / in_progress / skipped."""
    user_id = user["id"]
    sb = supabase_service.client

    try:
        # Update step with timeout
        await supabase_with_timeout(
            sb.table("workflow_steps")
            .update({"status": req.status, "updated_at": datetime.now(timezone.utc).isoformat()})
            .eq("id", step_id)
            .eq("workflow_id", workflow_id)
            .eq("user_id", user_id)
            .execute(),
            timeout=5.0,
            operation="update_step"
        )

        # Calculate progress
        steps_resp = await supabase_with_timeout(
            sb.table("workflow_steps").select("status").eq("workflow_id", workflow_id).execute(),
            timeout=5.0,
            operation="get_progress"
        )

        total = len(steps_resp.data or [])
        done = sum(1 for s in (steps_resp.data or []) if s["status"] == "done")
        progress_pct = int((done / total * 100)) if total > 0 else 0

        # Update workflow progress
        await supabase_with_timeout(
            sb.table("workflows").update({"progress_percent": progress_pct}).eq("id", workflow_id).execute(),
            timeout=5.0,
            operation="update_progress"
        )

        return {
            "step_id": step_id, 
            "status": req.status, 
            "overall_progress": progress_pct
        }

    except Exception as e:
        logger.error(f"Failed to update step: {e}")
        raise HTTPException(status_code=500, detail="Failed to update step")


@router.post("/{workflow_id}/log-revenue")
@limiter.limit(GENERAL_LIMIT)
async def log_revenue(
    workflow_id: str,
    req: LogRevenueRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """Log revenue earned from this specific workflow."""
    user_id = user["id"]
    sb = supabase_service.client

    try:
        # Insert revenue log
        await supabase_with_timeout(
            sb.table("workflow_revenue").insert({
                "workflow_id": workflow_id,
                "user_id": user_id,
                "amount": req.amount,
                "currency": req.currency or "NGN",
                "source": req.source or "",
                "note": req.note or "",
            }).execute(),
            timeout=5.0,
            operation="log_revenue"
        )

        # Get current total revenue
        wf_resp = await supabase_with_timeout(
            sb.table("workflows").select("total_revenue").eq("id", workflow_id).single().execute(),
            timeout=5.0,
            operation="get_current_revenue"
        )

        current = float(wf_resp.data.get("total_revenue", 0) if wf_resp.data else 0)
        new_total = current + req.amount

        # Update workflow total_revenue
        await supabase_with_timeout(
            sb.table("workflows").update({"total_revenue": new_total}).eq("id", workflow_id).execute(),
            timeout=5.0,
            operation="update_total_revenue"
        )

        # Also log to general earnings table (best effort)
        try:
            await supabase_with_timeout(
                sb.table("earnings").insert({
                    "user_id": user_id,
                    "amount": req.amount,
                    "currency": req.currency or "NGN",
                    "source": f"Workflow: {req.source or 'workflow'}",
                    "note": req.note or "",
                    "workflow_id": workflow_id,
                }).execute(),
                timeout=3.0,
                operation="log_general_earnings"
            )
        except Exception as e:
            logger.warning(f"Failed to log to general earnings (non-critical): {e}")

        return {
            "logged": req.amount,
            "workflow_total": new_total,
            "currency": req.currency,
            "message": f"Revenue logged! Total from this workflow: {req.currency} {new_total:,.0f}",
        }

    except Exception as e:
        logger.error(f"Failed to log revenue: {e}")
        raise HTTPException(status_code=500, detail="Failed to log revenue")


@router.get("/{workflow_id}/analytics")
@limiter.limit(GENERAL_LIMIT)
async def workflow_analytics(
    workflow_id: str,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Get analytics for a specific workflow — revenue over time, step completion rate.
    
    ENHANCED: Parallel fetching to prevent hanging.
    """
    user_id = user["id"]
    sb = supabase_service.client

    try:
        # Parallel fetch revenue logs and steps
        revenue_coro = supabase_with_timeout(
            sb.table("workflow_revenue")
            .select("amount, currency, created_at, source")
            .eq("workflow_id", workflow_id)
            .eq("user_id", user_id)
            .order("created_at")
            .execute(),
            timeout=5.0,
            operation="get_revenue_logs"
        )
        
        steps_coro = supabase_with_timeout(
            sb.table("workflow_steps").select("status, step_type").eq("workflow_id", workflow_id).execute(),
            timeout=5.0,
            operation="get_steps_summary"
        )

        rev_resp, steps_resp = await asyncio.gather(
            revenue_coro, 
            steps_coro, 
            return_exceptions=True
        )

        if isinstance(rev_resp, Exception):
            raise rev_resp
        if isinstance(steps_resp, Exception):
            raise steps_resp

        logs = rev_resp.data or []
        steps = steps_resp.data or []

        # Calculate statistics
        total = len(steps)
        done = sum(1 for s in steps if s["status"] == "done")
        automated = sum(1 for s in steps if s["step_type"] == "automated")
        manual = sum(1 for s in steps if s["step_type"] == "manual")

        # Daily revenue aggregation
        daily = {}
        for log in logs:
            day = log["created_at"][:10]  # YYYY-MM-DD
            daily[day] = daily.get(day, 0) + float(log["amount"])

        total_revenue = sum(float(l["amount"]) for l in logs)

        return {
            "workflow_id": workflow_id,
            "total_revenue": total_revenue,
            "revenue_logs": logs,
            "daily_revenue": [{"date": d, "amount": a} for d, a in sorted(daily.items())],
            "steps_summary": {
                "total": total,
                "done": done,
                "remaining": total - done,
                "progress_percent": int(done / total * 100) if total > 0 else 0,
                "automated_steps": automated,
                "manual_steps": manual,
            },
        }

    except Exception as e:
        logger.error(f"Failed to get analytics: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch analytics")


@router.post("/{workflow_id}/ai-assist")
@limiter.limit(AI_LIMIT)
async def ai_assist_on_step(
    workflow_id: str,
    request: Request,
    step_title: str,
    user_question: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """
    AI executes or assists on a specific workflow step.
    e.g., "Write me a script for my first YouTube video about budgeting"
    """
    user_id = user["id"]
    sb = supabase_service.client

    try:
        # Get workflow context with timeout
        wf_resp = await supabase_with_timeout(
            sb.table("workflows").select("title, goal, income_type").eq("id", workflow_id).single().execute(),
            timeout=5.0,
            operation="get_workflow_context"
        )
        wf_data = wf_resp.data or {}

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

        # AI call with timeout
        result = await asyncio.wait_for(
            ai_service.chat(
                messages=[{"role": "user", "content": prompt}],
                system="You are an AI income execution engine. Produce real, usable output — not advice.",
                max_tokens=1500,
            ),
            timeout=20.0
        )

        return {
            "step": step_title,
            "ai_output": result["content"],
            "model_used": result.get("model", "unknown"),
        }

    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="AI assistance timed out")
    except Exception as e:
        logger.error(f"AI assist failed: {e}")
        raise HTTPException(status_code=500, detail="AI assistance failed")
