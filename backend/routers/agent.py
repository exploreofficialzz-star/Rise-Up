"""
RiseUp Agentic AI — Heavy Real-World Task Engine
─────────────────────────────────────────────────
This is NOT a chatbot. This is an AI AGENT that:
  1. Takes any income goal or task the user describes
  2. PLANS what needs to happen (dynamically, not hardcoded)
  3. EXECUTES each step using AI tools
  4. Produces REAL, ready-to-use outputs
  5. Tracks everything in the user's workflow

It handles: YouTube, freelance, ecommerce, physical business,
trading, content creation, coding gigs, affiliate, tutoring,
writing, design, social media, and anything else.
"""

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/agent", tags=["Agentic AI"])
logger = logging.getLogger(__name__)


# ── Request Models ────────────────────────────────────────────────

class AgentRequest(BaseModel):
    task: str                              # User's natural language task description
    context: Optional[str] = None         # Extra context the user provides
    budget: Optional[float] = 0.0         # Money they can invest
    hours_per_day: Optional[float] = 2.0
    currency: Optional[str] = "NGN"
    mode: Optional[str] = "full"          # full | plan_only | execute_step
    step_to_execute: Optional[str] = None # For execute_step mode
    workflow_id: Optional[str] = None     # Attach to existing workflow

class AgentChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None
    workflow_id: Optional[str] = None

class ExecuteToolRequest(BaseModel):
    tool: str           # write_content | research | create_plan | find_tools | estimate_income | create_template
    input: Dict[str, Any]
    workflow_id: Optional[str] = None


# ── The Agent Brain — System Prompt ──────────────────────────────

def _agent_system_prompt(profile: dict, task: str, budget: float, hours: float, currency: str) -> str:
    name = profile.get("full_name", "User")
    stage = profile.get("stage", "survival")
    skills = ", ".join(profile.get("current_skills", []) or ["none listed"])
    country = profile.get("country", "NG")
    monthly_income = profile.get("monthly_income", 0)

    return f"""You are RiseUp's Agentic AI — a heavyweight execution engine, not a chatbot.

USER PROFILE:
- Name: {name}
- Country: {country}
- Stage: {stage.upper()}
- Skills: {skills}
- Monthly Income: {currency} {monthly_income:,.0f}
- Budget to invest: {currency if budget > 0 else "$0 — FREE ONLY"} {budget if budget > 0 else "(must use free tools only)"}
- Daily time: {hours} hours/day

TASK: {task}

YOUR JOB:
You are an execution engine. You don't give advice. You BUILD plans and EXECUTE them.

WHAT YOU MUST DO:
1. Understand the task deeply — what does success actually look like?
2. Research what actually works RIGHT NOW in 2025/2026 for this exact task
3. Break it into concrete executable steps (not vague phases)
4. For each step, determine: can AI do this? Must the user do it? Can it be automated?
5. Find FREE tools first — only suggest paid if absolutely necessary
6. Write real outputs — scripts, descriptions, email templates, pitches, plans — ready to copy-paste
7. Give REALISTIC timelines and income estimates (not hype)
8. Identify what the user can AUTOMATE vs what needs their hands

TOOL EXECUTION RULES:
- When asked to write content: write the FULL content, not a template
- When asked to research: give SPECIFIC findings with platform names and numbers
- When asked to create a plan: give ACTIONABLE day-by-day steps
- When asked to find tools: list SPECIFIC free tools with URLs and exact use case
- When asked to estimate income: give REALISTIC range with WHY

RESPONSE FORMAT:
Always respond in valid JSON with this structure:
{{
  "agent_response": "Your natural explanation to the user",
  "plan": {{
    "title": "Short workflow title",
    "income_type": "youtube|freelance|ecommerce|physical|content|service|trading|other",
    "viability": 0-100,
    "timeline": "e.g. 4-8 weeks",
    "income_range": {{"min": 0, "max": 0, "currency": "{currency}"}},
    "warning": "One honest realistic warning"
  }},
  "steps": [
    {{
      "order": 1,
      "title": "Step title",
      "description": "Exact what to do",
      "type": "automated|manual|outsource",
      "ai_output": "If automated, the FULL ready-to-use content AI produces here",
      "tools": ["Tool 1", "Tool 2"],
      "time_minutes": 30,
      "is_critical": true
    }}
  ],
  "free_tools": [
    {{"name": "Tool name", "url": "url.com", "purpose": "Exact use", "is_free": true}}
  ],
  "immediate_action": "The ONE thing they should do in the next 10 minutes"
}}

CRITICAL: Return ONLY valid JSON. No markdown. No explanation outside the JSON.
Be SPECIFIC to this user's situation, country, and budget.
"""


# ── Tool Execution Prompts ────────────────────────────────────────

TOOL_PROMPTS = {
    "write_content": """You are a professional content writer. Write the COMPLETE, ready-to-use content requested.
Do NOT write templates or placeholders. Write the actual content.
Return JSON: {{"content": "THE FULL WRITTEN CONTENT", "type": "...", "usage_tip": "..."}}""",

    "research": """You are a research engine. Find SPECIFIC, current information about the topic.
Include real platform names, real statistics from 2024-2026, real tools, real methods.
Return JSON: {{"findings": [...], "key_insight": "...", "sources_to_check": [...]}}""",

    "create_plan": """You are a strategic planner. Create a DETAILED, day-by-day execution plan.
Every action must be specific and completable in that time.
Return JSON: {{"plan_title": "...", "days": [{{"day": 1, "actions": [...], "goal": "..."}}], "success_metric": "..."}}""",

    "find_tools": """You are a tool researcher. Find SPECIFIC free tools that solve the exact problem.
Include: name, URL, what it does, how to use it, free tier limits.
Return JSON: {{"free_tools": [...], "paid_upgrades": [...]}}""",

    "estimate_income": """You are an income analyst. Give REALISTIC income estimates based on real data.
Include best case, worst case, and most likely case with reasoning.
Return JSON: {{"min_monthly": 0, "max_monthly": 0, "likely_monthly": 0, "currency": "...", "timeline_to_first_income": "...", "reasoning": "..."}}""",

    "create_template": """You create READY-TO-USE templates (emails, proposals, scripts, pitches, etc.)
Write the FULL template with real text, not placeholders where possible.
Return JSON: {{"template_type": "...", "template": "THE FULL TEXT", "how_to_customize": "..."}}""",

    "breakdown_task": """You break down ANY task into its smallest executable components.
Think like a senior project manager. Nothing vague.
Return JSON: {{"task_summary": "...", "components": [...], "critical_path": [...], "quick_wins": [...]}}""",
}


# ── Main Agent Endpoint ───────────────────────────────────────────

@router.post("/run")
@limiter.limit(AI_LIMIT)
async def run_agent(
    req: AgentRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Main agentic endpoint. Takes ANY task and produces a complete
    execution plan + ready-to-use outputs.
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}

    system = _agent_system_prompt(
        profile, req.task,
        req.budget or 0,
        req.hours_per_day or 2,
        req.currency or "NGN"
    )

    user_message = f"""TASK: {req.task}
{f"ADDITIONAL CONTEXT: {req.context}" if req.context else ""}
BUDGET: {"$0 - free tools only" if not req.budget else f"${req.budget}"}
DAILY TIME: {req.hours_per_day} hours"""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": user_message}],
        system=system,
        max_tokens=3000,
    )

    raw = result["content"].strip()
    # Strip markdown fences if model added them
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"): raw = raw[4:]
    raw = raw.strip()

    try:
        agent_data = json.loads(raw)
    except json.JSONDecodeError:
        start, end = raw.find("{"), raw.rfind("}") + 1
        if start >= 0 and end > start:
            agent_data = json.loads(raw[start:end])
        else:
            raise HTTPException(500, "Agent failed to produce a plan. Please try again.")

    # Save as workflow if plan was produced
    workflow_id = req.workflow_id
    plan = agent_data.get("plan", {})
    steps = agent_data.get("steps", [])

    if plan and steps and not workflow_id:
        try:
            sb = supabase_service.client
            wf = sb.table("workflows").insert({
                "user_id": user_id,
                "title": plan.get("title", req.task[:50]),
                "goal": req.task,
                "income_type": plan.get("income_type", "other"),
                "currency": req.currency or "NGN",
                "status": "active",
                "total_revenue": 0.0,
                "viability_score": plan.get("viability", 75),
                "realistic_timeline": plan.get("timeline", ""),
                "potential_min": plan.get("income_range", {}).get("min", 0),
                "potential_max": plan.get("income_range", {}).get("max", 0),
                "honest_warning": plan.get("warning", ""),
                "research_snapshot": json.dumps(agent_data),
            }).execute()

            workflow_id = wf.data[0]["id"] if wf.data else None

            if workflow_id and steps:
                step_rows = [{
                    "workflow_id": workflow_id,
                    "user_id": user_id,
                    "order_index": s.get("order", i + 1),
                    "title": s.get("title", ""),
                    "description": s.get("description", ""),
                    "step_type": s.get("type", "manual"),
                    "time_minutes": s.get("time_minutes", 30),
                    "tools": json.dumps(s.get("tools", [])),
                    "ai_output": s.get("ai_output", ""),
                    "status": "pending",
                } for i, s in enumerate(steps)]
                sb.table("workflow_steps").insert(step_rows).execute()

                # Save tools
                tools = agent_data.get("free_tools", [])
                if tools:
                    sb.table("workflow_tools").insert([{
                        "workflow_id": workflow_id,
                        "name": t.get("name", ""),
                        "url": t.get("url", ""),
                        "purpose": t.get("purpose", ""),
                        "is_free": t.get("is_free", True),
                    } for t in tools]).execute()

        except Exception as e:
            logger.error(f"Workflow save error: {e}")

    return {
        **agent_data,
        "workflow_id": workflow_id,
        "model_used": result.get("model", "unknown"),
        "task": req.task,
    }


# ── Agent Chat (conversational execution) ────────────────────────

@router.post("/chat")
@limiter.limit(AI_LIMIT)
async def agent_chat(
    req: AgentChatRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Conversational agent — user can ask follow-up questions,
    request rewrites, ask AI to execute specific steps.
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}

    # Load session history if exists
    history = []
    if req.session_id:
        try:
            msgs = await supabase_service.get_messages(req.session_id, limit=10)
            history = [{"role": m["role"], "content": m["content"]}
                       for m in msgs if m["role"] in ("user", "assistant")]
        except Exception:
            pass

    # Load workflow context if provided
    workflow_context = ""
    if req.workflow_id:
        try:
            sb = supabase_service.client
            wf = sb.table("workflows").select("title, goal, income_type").eq("id", req.workflow_id).single().execute()
            if wf.data:
                workflow_context = f"\nACTIVE WORKFLOW: {wf.data['title']} — Goal: {wf.data['goal']}"
        except Exception:
            pass

    name = profile.get("full_name", "User")
    stage = profile.get("stage", "survival")
    skills = ", ".join(profile.get("current_skills", []) or [])
    currency = profile.get("currency", "NGN")

    system = f"""You are RiseUp's Agentic AI — an execution engine.

USER: {name} | Stage: {stage.upper()} | Skills: {skills} | Currency: {currency}
{workflow_context}

You are in CONVERSATION MODE. The user wants to:
- Get clarification on steps
- Ask you to write/create/produce something specific
- Get help executing a particular step
- Ask follow-up questions about their workflow

RULES:
- Be DIRECT and SPECIFIC
- When asked to write something — WRITE IT IN FULL (no placeholders)
- When asked to research something — give SPECIFIC findings
- Keep responses focused and action-oriented
- If the user asks you to produce content/templates/scripts — produce them completely

Respond naturally but powerfully. You are a senior consultant who produces real work."""

    history.append({"role": "user", "content": req.message})

    result = await ai_service.chat(
        messages=history,
        system=system,
        max_tokens=2000,
    )

    ai_content = result["content"]

    # Save to conversation
    session_id = req.session_id
    try:
        if not session_id:
            conv = await supabase_service.create_conversation(user_id, title="Agent Session")
            session_id = conv["id"]
        await supabase_service.save_message(session_id, user_id, "user", req.message)
        await supabase_service.save_message(session_id, user_id, "assistant", ai_content,
                                            ai_model=result.get("model"))
    except Exception as e:
        logger.error(f"Session save error: {e}")

    return {
        "content": ai_content,
        "session_id": session_id,
        "model_used": result.get("model", "unknown"),
    }


# ── Execute a Specific Tool ───────────────────────────────────────

@router.post("/execute-tool")
@limiter.limit(AI_LIMIT)
async def execute_tool(
    req: ExecuteToolRequest,
    request: Request,
    user: dict = Depends(get_current_user)
):
    """
    Execute a specific AI tool.
    Tools: write_content | research | create_plan | find_tools |
           estimate_income | create_template | breakdown_task
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}

    if req.tool not in TOOL_PROMPTS:
        raise HTTPException(400, f"Unknown tool: {req.tool}. Valid: {list(TOOL_PROMPTS.keys())}")

    currency = profile.get("currency", "NGN")
    country = profile.get("country", "NG")

    system = TOOL_PROMPTS[req.tool]
    user_msg = f"""User context: {country}, currency {currency}
Tool input: {json.dumps(req.input)}
Return ONLY valid JSON. No markdown."""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": user_msg}],
        system=system,
        max_tokens=2000,
    )

    raw = result["content"].strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"): raw = raw[4:]
    raw = raw.strip()

    try:
        tool_output = json.loads(raw)
    except json.JSONDecodeError:
        start, end = raw.find("{"), raw.rfind("}") + 1
        if start >= 0 and end > start:
            tool_output = json.loads(raw[start:end])
        else:
            tool_output = {"result": raw}

    # If tied to a workflow step, save output
    if req.workflow_id and req.input.get("step_id"):
        try:
            sb = supabase_service.client
            sb.table("workflow_steps").update({
                "ai_output": json.dumps(tool_output)
            }).eq("id", req.input["step_id"]).eq("workflow_id", req.workflow_id).execute()
        except Exception:
            pass

    return {
        "tool": req.tool,
        "output": tool_output,
        "model_used": result.get("model", "unknown"),
    }


# ── Quick Execute — Produce content immediately ───────────────────

@router.post("/quick")
@limiter.limit(AI_LIMIT)
async def quick_execute(
    request: Request,
    task: str,
    output_type: str = "any",
    user: dict = Depends(get_current_user)
):
    """
    Fast execution for simple tasks:
    - "Write me a YouTube description for my budgeting video"
    - "Create an email pitch for my freelance services"
    - "Write a WhatsApp message to find my first client"
    - "Give me 10 content ideas for my niche"
    """
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}
    currency = profile.get("currency", "NGN")
    country = profile.get("country", "NG")
    name = profile.get("full_name", "User")

    system = f"""You are RiseUp's execution engine for {name} in {country}.

TASK: {task}
OUTPUT TYPE REQUESTED: {output_type}

Produce the COMPLETE, ready-to-use output immediately.
- If writing content: write the full text
- If creating a plan: write specific daily actions
- If researching: give specific findings with real data
- If making a template: write the complete template

Be specific to Nigeria/Africa context if the user is there.
Use {currency} for money references.
NO generic advice. Produce REAL work output."""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": task}],
        system=system,
        max_tokens=1500,
    )

    return {
        "output": result["content"],
        "task": task,
        "model_used": result.get("model", "unknown"),
    }


# ── Analyze and Improve Existing Work ────────────────────────────

@router.post("/analyze")
@limiter.limit(AI_LIMIT)
async def analyze_and_improve(
    request: Request,
    content: str,
    goal: str = "improve",
    user: dict = Depends(get_current_user)
):
    """
    Analyze user's existing work (post, bio, pitch, description)
    and produce an improved version.
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    currency = profile.get("currency", "NGN")

    system = f"""You are RiseUp's content improvement engine.

GOAL: {goal}
USER CURRENCY: {currency}

Analyze the provided content and:
1. Identify what's weak (be direct)
2. Rewrite it completely — improved, stronger, more effective
3. Explain the key changes

Return JSON: {{
  "issues": ["what was weak"],
  "improved_version": "THE COMPLETE REWRITTEN CONTENT",
  "key_changes": ["what you changed and why"],
  "score_before": 0-100,
  "score_after": 0-100
}}"""

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Analyze and improve this:\n\n{content}"}],
        system=system,
        max_tokens=1500,
    )

    raw = result["content"].strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"): raw = raw[4:]

    try:
        output = json.loads(raw.strip())
    except Exception:
        output = {"improved_version": result["content"], "issues": [], "key_changes": []}

    return {"analysis": output, "model_used": result.get("model")}
