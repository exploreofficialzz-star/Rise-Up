"""
RiseUp Autonomous Agent — v4 (APEX)
═══════════════════════════════════════════════════════════════════════════
This is a REAL autonomous agent. It doesn't just plan — it WORKS.

  ┌─────────────────────────────────────────────────────────────────┐
  │ THINKS  →  Reasons step-by-step with chain-of-thought           │
  │ SEARCHES → Reads the live internet for real data                │
  │ ACTS    →  Sends emails, posts social media, generates docs     │
  │ HUNTS   →  Finds real freelance jobs + partnership opps         │
  │ BUILDS  →  Creates contracts, invoices, business plans          │
  │ STREAMS →  Shows the user everything in real-time               │
  │ SAVES   →  Persists every output to the user's workflow         │
  └─────────────────────────────────────────────────────────────────┘

28 tools across 4 categories:
  🧠 THINKING  — write_content, create_plan, estimate_income, generate_ideas,
                  breakdown_task, create_template, write_cold_outreach, build_profile_content
  🌐 RESEARCH  — web_search, deep_research, find_freelance_jobs, find_partners,
                  find_free_resources, market_research, scan_opportunities
  📤 ACTIONS   — send_email, post_twitter, post_linkedin, schedule_post
  📄 DOCUMENTS — generate_contract, generate_invoice, generate_proposal, generate_pitch_deck
"""

import json
import logging
import asyncio
from datetime import datetime, timezone
from typing   import Optional, Dict, Any, List

from fastapi           import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic          import BaseModel

from middleware.rate_limit       import limiter, AI_LIMIT
from services.ai_service         import ai_service
from services.supabase_service   import supabase_service
from services.web_search_service import web_search_service
from services.action_service     import (
    email_service, social_service, document_service, opportunity_scanner
)
from services.scraper_service    import scraper_engine
from utils.auth import get_current_user

router = APIRouter(prefix="/agent", tags=["Agentic AI"])
logger = logging.getLogger(__name__)

MAX_REACT_ITERATIONS = 8
MAX_RETRIES          = 2
DEFAULT_DAILY_RUNS   = 3
PREMIUM_DAILY_RUNS   = 25


# ═══════════════════════════════════════════════════════════════════
# REQUEST MODELS
# ═══════════════════════════════════════════════════════════════════

class AgentRequest(BaseModel):
    task:              str
    context:           Optional[str]   = None
    budget:            Optional[float] = 0.0
    hours_per_day:     Optional[float] = 2.0
    currency:          Optional[str]   = "NGN"
    mode:              Optional[str]   = "full"
    workflow_id:       Optional[str]   = None
    allow_email:       bool = False
    allow_social_post: bool = False
    social_tokens:     Optional[Dict] = None

class AgentChatRequest(BaseModel):
    message:     str
    session_id:  Optional[str]        = None
    workflow_id: Optional[str]        = None
    history:     Optional[List[Dict]] = None

class ExecuteToolRequest(BaseModel):
    tool:        str
    input:       Dict[str, Any]
    workflow_id: Optional[str] = None

class QuickRequest(BaseModel):
    task:        str
    output_type: Optional[str] = "any"

class AnalyzeRequest(BaseModel):
    content: str
    goal:    Optional[str] = "improve"

class ScanRequest(BaseModel):
    force_refresh: bool = False


# ═══════════════════════════════════════════════════════════════════
# TOOL REGISTRY
# ═══════════════════════════════════════════════════════════════════

TOOLS: Dict[str, Dict] = {
    # ── THINKING ──────────────────────────────────────────────────
    "write_content": {
        "category":    "thinking",
        "description": "Write complete copy-paste-ready content: scripts, captions, bios, pitches, ad copy.",
        "system": 'Write COMPLETE, ready-to-use content. No placeholders. Return JSON: {"content":"FULL TEXT","type":"...","usage_tip":"..."}',
    },
    "create_plan": {
        "category":    "thinking",
        "description": "Build a day-by-day execution calendar with specific completable daily actions.",
        "system": 'Create DETAILED day-by-day plan. Specific, completable actions. Return JSON: {"plan_title":"...","days":[{"day":1,"actions":[...],"goal":"..."}],"success_metric":"..."}',
    },
    "estimate_income": {
        "category":    "thinking",
        "description": "Give realistic income estimates with best/worst/likely cases and clear reasoning.",
        "system": 'Give REALISTIC 2025 income estimates. Return JSON: {"min_monthly":0,"max_monthly":0,"likely_monthly":0,"currency":"...","timeline_to_first_income":"...","reasoning":"..."}',
    },
    "generate_ideas": {
        "category":    "thinking",
        "description": "Generate specific actionable business/content/product ideas with first steps and income potential.",
        "system": 'Generate SPECIFIC actionable ideas with first steps. Return JSON: {"ideas":[{"title":"...","description":"...","first_steps":[...],"income_potential":"...","effort":"low|medium|high"}]}',
    },
    "breakdown_task": {
        "category":    "thinking",
        "description": "Break any goal into smallest executable components with critical path and quick wins.",
        "system": 'Break down like a senior PM. Return JSON: {"task_summary":"...","components":[...],"critical_path":[...],"quick_wins":[...]}',
    },
    "create_template": {
        "category":    "thinking",
        "description": "Create complete ready-to-send templates: emails, proposals, scripts, cold DMs.",
        "system": 'Write READY-TO-USE complete template with real text. Return JSON: {"template_type":"...","template":"FULL TEXT","how_to_customize":"..."}',
    },
    "write_cold_outreach": {
        "category":    "thinking",
        "description": "Write personalized cold emails, WhatsApp messages, LinkedIn/Twitter DMs to land clients or partnerships.",
        "system": 'Write HIGH-CONVERTING outreach. 3 variants: short (2-3 sentences), medium (1 paragraph), long (full email). Return JSON: {"short":"...","medium":"...","long":"...","subject_line":"...","follow_up":"..."}',
    },
    "build_profile_content": {
        "category":    "thinking",
        "description": "Write optimized platform profiles: Fiverr gig, Upwork bio, LinkedIn summary, Twitter/Instagram bio.",
        "system": 'Write OPTIMIZED platform profiles that attract clients. Return JSON: {"platform":"...","headline":"...","bio":"...","skills":[...],"cta":"...","full_profile":"COMPLETE TEXT"}',
    },

    # ── RESEARCH ──────────────────────────────────────────────────
    "web_search": {
        "category":    "research",
        "description": "Search the live internet for current info, platforms, pricing, job postings, news.",
        "handler":     "web_search",
    },
    "deep_research": {
        "category":    "research",
        "description": "Run multiple searches on a topic and synthesize comprehensive real findings.",
        "handler":     "deep_research",
    },
    "find_freelance_jobs": {
        "category":    "research",
        "description": "Find real live freelance job postings on Upwork, Freelancer, LinkedIn, and others.",
        "handler":     "find_freelance_jobs",
    },
    "find_partners": {
        "category":    "research",
        "description": "Find potential business partners, collaborators, or co-founders in a niche.",
        "handler":     "find_partners",
    },
    "find_free_resources": {
        "category":    "research",
        "description": "Find free tools, grants, free courses, and zero-capital resources for starting a business.",
        "handler":     "find_free_resources",
    },
    "market_research": {
        "category":    "research",
        "description": "Research a market: competition level, demand, pricing benchmarks, opportunity score.",
        "system": 'Analyze market with real data. Return JSON: {"niche":"...","competition":"low|medium|high","demand":"...","avg_price":"...","opportunity_score":0,"insights":[...],"entry_strategy":"..."}',
    },
    "scan_opportunities": {
        "category":    "research",
        "description": "Scan web for current income opportunities matching the user skills and goals.",
        "handler":     "scan_opportunities",
    },

    # ── ACTIONS ───────────────────────────────────────────────────
    "send_email": {
        "category":            "action",
        "description":         "Send a real email on behalf of the user to a client, partner, or prospect.",
        "handler":             "send_email",
        "requires_permission": "allow_email",
    },
    "post_twitter": {
        "category":            "action",
        "description":         "Post a tweet to Twitter/X on behalf of the user.",
        "handler":             "post_twitter",
        "requires_permission": "allow_social_post",
    },
    "post_linkedin": {
        "category":            "action",
        "description":         "Publish a post to LinkedIn on behalf of the user.",
        "handler":             "post_linkedin",
        "requires_permission": "allow_social_post",
    },
    "schedule_post": {
        "category":            "action",
        "description":         "Schedule a social media post for a future date/time.",
        "handler":             "schedule_post",
        "requires_permission": "allow_social_post",
    },

    # ── DOCUMENTS ─────────────────────────────────────────────────
    "generate_contract": {
        "category":    "document",
        "description": "Generate a complete legally structured freelance service contract.",
        "handler":     "generate_contract",
    },
    "generate_invoice": {
        "category":    "document",
        "description": "Generate a professional invoice for completed work.",
        "handler":     "generate_invoice",
    },
    "generate_proposal": {
        "category":    "document",
        "description": "Generate a complete business proposal document.",
        "handler":     "generate_proposal",
    },
    "generate_pitch_deck": {
        "category":    "document",
        "description": "Generate a complete pitch deck outline for investors or partners.",
        "handler":     "generate_pitch_deck",
    },

    # ── 🔭 INTELLIGENCE (from GrowthAI) ─────────────────────────
    "scrape_live_opportunities": {
        "category":    "intelligence",
        "description": "Scrape real live opportunities from Indeed, RemoteOK, Reddit, HackerNews and a curated database — all AI-scored against the user's profile.",
        "handler":     "scrape_live_opportunities",
    },
    "score_opportunity": {
        "category":    "intelligence",
        "description": "AI-analyse a specific opportunity: match score 0-100, risk level, action steps, time to first earning.",
        "system": (
            "You are an opportunity analyst. Score this opportunity for the user. "
            "Return ONLY valid JSON: "
            '{"match_score":0-100,"summary":"2-sentence personalised summary",'
            '"risk_level":"low|medium|high","action_steps":["Step 1","Step 2","Step 3"],'
            '"time_to_first_earning":"e.g. 1-2 weeks","potential_monthly":0}'
        ),
    },
    "analyze_market_trends": {
        "category":    "intelligence",
        "description": "Analyse market trends for an industry or skill: demand, pay rates, competition, growth trajectory, best platforms, future outlook.",
        "system": (
            "You are a market analyst with current 2025/2026 data. "
            "Analyse the given industry/skill and return ONLY valid JSON: "
            '{"demand_level":"high|medium|low","avg_pay_range":{"min":0,"max":0,"currency":"USD","period":"month"},'
            '"growth_trajectory":"growing|stable|declining","competition_level":"high|medium|low",'
            '"best_platforms":["..."],"in_demand_skills":["..."],"future_outlook":"...",'
            '"recommendations":["..."]}'
        ),
    },
    "create_daily_action_plan": {
        "category":    "intelligence",
        "description": "Generate a prioritised daily action plan with specific tasks, milestones, and income targets for the user's current stage.",
        "system": (
            "You are a personal income strategist. Create a detailed daily action plan. "
            "Return ONLY valid JSON: "
            '{"overview":"...","daily_tasks":["..."],"weekly_milestones":["..."],'
            '"resources_needed":["..."],"potential_obstacles":["..."],'
            '"mitigation_strategies":["..."],"income_target":"...","confidence_score":0-100}'
        ),
    },
    "create_follow_up_plan": {
        "category":    "intelligence",
        "description": "Create a follow-up plan for an application or outreach — what to send, when, and how to handle different responses.",
        "system": (
            "You are an outreach specialist. Create a complete follow-up sequence. "
            "Return ONLY valid JSON: "
            '{"follow_up_1":{"when":"e.g. 3 days after","message":"FULL TEXT","subject":"..."},'
            '"follow_up_2":{"when":"...","message":"...","subject":"..."},'
            '"if_no_response":"what to do if no reply after 2 follow-ups",'
            '"if_rejected":"how to respond to a rejection"}'
        ),
    },
    "track_earnings_insight": {
        "category":    "intelligence",
        "description": "Analyse the user's earnings history and give insights: growth rate, top sources, what to focus on to hit their income goal.",
        "system": (
            "You are a financial analyst. Analyse these earnings and give actionable insight. "
            "Return ONLY valid JSON: "
            '{"growth_rate":"...","top_source":"...","monthly_trend":"growing|stable|declining",'
            '"insight":"3-sentence analysis","next_milestone":"...","recommended_action":"..."}'
        ),
    },
    "growth_milestone_check": {
        "category":    "intelligence",
        "description": "Check the user's progress against their wealth stage milestones and tell them exactly what they need to do to reach the next stage.",
        "system": (
            "You are a wealth coach. Analyse the user's current stage and give milestone guidance. "
            "Return ONLY valid JSON: "
            '{"current_stage":"survival|earning|growing|wealth",'
            '"progress_to_next":0-100,"next_stage":"...","gap":"...",'
            '"milestones_achieved":["..."],"next_milestones":["..."],'
            '"action_to_advance":"The single most impactful thing they can do right now"}'
        ),
    },
}


# ═══════════════════════════════════════════════════════════════════
# TOOL EXECUTOR
# ═══════════════════════════════════════════════════════════════════

async def _execute_tool(tool_name: str, tool_input: dict,
                         profile: dict, permissions: dict) -> str:
    meta = TOOLS.get(tool_name)
    if not meta:
        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    required_perm = meta.get("requires_permission")
    if required_perm and not permissions.get(required_perm, False):
        return json.dumps({"skipped": True,
                           "reason": f"Permission '{required_perm}' not granted.",
                           "content_preview": tool_input})

    handler  = meta.get("handler")
    currency = profile.get("currency", "NGN")
    country  = profile.get("country",  "NG")

    # Web research handlers
    if handler == "web_search":
        results = await web_search_service.search(tool_input.get("query", ""), num=8)
        return json.dumps({"results": results[:8]})

    if handler == "deep_research":
        result = await web_search_service.deep_research(
            tool_input.get("topic", tool_input.get("query", "")),
            tool_input.get("sub_queries"),
        )
        return json.dumps(result)

    if handler == "find_freelance_jobs":
        jobs = await web_search_service.find_freelance_jobs(
            tool_input.get("skill", ""), country
        )
        return json.dumps({"jobs": jobs})

    if handler == "find_partners":
        partners = await web_search_service.find_partners(
            tool_input.get("niche", ""), country
        )
        return json.dumps({"partners": partners})

    if handler == "find_free_resources":
        res = await web_search_service.find_free_resources(
            tool_input.get("business_type", tool_input.get("type", ""))
        )
        return json.dumps({"resources": res})

    if handler == "scan_opportunities":
        opps = await opportunity_scanner.scan_for_user(profile)
        return json.dumps({"opportunities": opps})

    # Action handlers
    if handler == "send_email":
        result = await email_service.send(
            to_email  = tool_input.get("to", ""),
            subject   = tool_input.get("subject", ""),
            body_text = tool_input.get("body", ""),
            body_html = tool_input.get("body_html"),
            from_name = profile.get("full_name", "RiseUp Agent"),
            reply_to  = tool_input.get("reply_to"),
        )
        return json.dumps(result)

    if handler == "post_twitter":
        tokens = permissions.get("social_tokens", {}).get("twitter", {})
        return json.dumps(await social_service.post_twitter(tool_input.get("text", ""), tokens))

    if handler == "post_linkedin":
        tokens = permissions.get("social_tokens", {}).get("linkedin", {})
        return json.dumps(await social_service.post_linkedin(tool_input.get("text", ""), tokens))

    if handler == "schedule_post":
        return json.dumps(await social_service.schedule_post(
            tool_input.get("platform", ""),
            tool_input.get("text", ""),
            tool_input.get("schedule_at", ""),
            profile.get("id", ""),
        ))

    # Document handlers
    if handler == "generate_contract":
        doc = document_service.generate_freelance_contract(
            client_name     = tool_input.get("client_name", "Client"),
            freelancer_name = tool_input.get("freelancer_name", profile.get("full_name", "Freelancer")),
            project_title   = tool_input.get("project_title", ""),
            deliverables    = tool_input.get("deliverables", []),
            amount          = tool_input.get("amount", 0),
            currency        = tool_input.get("currency", currency),
            deadline        = tool_input.get("deadline", ""),
            payment_terms   = tool_input.get("payment_terms", "50% upfront, 50% on delivery"),
        )
        return json.dumps({"document": doc, "type": "contract"})

    if handler == "generate_invoice":
        doc = document_service.generate_invoice(
            client_name      = tool_input.get("client_name", "Client"),
            freelancer_name  = profile.get("full_name", "Freelancer"),
            freelancer_email = profile.get("email", ""),
            items            = tool_input.get("items", []),
            currency         = tool_input.get("currency", currency),
        )
        return json.dumps({"document": doc, "type": "invoice"})

    if handler == "generate_proposal":
        doc = document_service.generate_business_proposal(
            business_name = tool_input.get("business_name", ""),
            owner_name    = profile.get("full_name", ""),
            business_type = tool_input.get("business_type", ""),
            target_market = tool_input.get("target_market", ""),
            problem       = tool_input.get("problem", ""),
            solution      = tool_input.get("solution", ""),
            revenue_model = tool_input.get("revenue_model", ""),
            startup_costs = tool_input.get("startup_costs", ""),
            timeline      = tool_input.get("timeline", ""),
            contact_email = profile.get("email", ""),
        )
        return json.dumps({"document": doc, "type": "proposal"})

    if handler == "generate_pitch_deck":
        doc = document_service.generate_pitch_deck_outline(
            business_name = tool_input.get("business_name", ""),
            problem       = tool_input.get("problem", ""),
            solution      = tool_input.get("solution", ""),
            market_size   = tool_input.get("market_size", ""),
            traction      = tool_input.get("traction", ""),
            ask           = tool_input.get("ask", ""),
        )
        return json.dumps({"document": doc, "type": "pitch_deck"})

    # ── Intelligence handlers (from GrowthAI) ────────────────────

    if handler == "scrape_live_opportunities":
        opp_types = tool_input.get("types", ["jobs", "hustles", "freelance"])
        query     = tool_input.get("query", " ".join(profile.get("current_skills", [])[:3]))
        opps      = await scraper_engine.find_opportunities(
            profile=profile,
            opp_types=opp_types,
            query=query,
            max_results=tool_input.get("max_results", 20),
            score_with_ai=True,
        )
        return json.dumps({"opportunities": opps, "total": len(opps)})

    # AI thinking tools
    system  = meta.get("system", "Return ONLY valid JSON.")
    user_msg = (
        f"User: {country}, {currency}, skills={profile.get('current_skills', [])}, "
        f"stage={profile.get('stage','survival')}\n"
        f"Input: {json.dumps(tool_input)}\nReturn ONLY valid JSON."
    )
    for attempt in range(MAX_RETRIES):
        try:
            result = await ai_service.chat(
                messages=[{"role": "user", "content": user_msg}],
                system=system, max_tokens=2500,
            )
            raw = result["content"].strip()
            if raw.startswith("```"):
                raw = raw.split("```")[1]
                if raw.startswith("json"):
                    raw = raw[4:]
            json.loads(raw.strip())
            return raw.strip()
        except Exception as e:
            if attempt == MAX_RETRIES - 1:
                return json.dumps({"error": str(e)})
            await asyncio.sleep(0.5)
    return json.dumps({"error": "Tool failed"})


# ═══════════════════════════════════════════════════════════════════
# SYSTEM PROMPTS
# ═══════════════════════════════════════════════════════════════════

def _agent_system(profile, task, budget, hours, currency, permissions) -> str:
    name    = profile.get("full_name", "User")
    stage   = profile.get("stage", "survival")
    skills  = ", ".join(profile.get("current_skills", []) or ["none"])
    country = profile.get("country", "NG")
    income  = profile.get("monthly_income", 0)
    perms   = []
    if permissions.get("allow_email"):
        perms.append("✅ send_email permitted")
    if permissions.get("allow_social_post"):
        perms.append("✅ post_twitter / post_linkedin permitted")
    if not perms:
        perms.append("⚠️  No action permissions — thinking & research tools only this run")

    tool_list = "\n".join(
        f"  [{m['category'].upper():8}] {n}: {m['description']}"
        for n, m in TOOLS.items()
    )

    return f"""You are APEX — RiseUp's Autonomous Agent. You WORK, not chat.

USER: {name} | {country} | {stage.upper()} | Skills: {skills}
Income: {currency} {income:,.0f}/mo | Budget: {"FREE ONLY" if not budget else f"{currency} {budget:,.0f}"} | Time: {hours}h/day

PERMISSIONS: {" | ".join(perms)}

TASK: {task}

TOOLS ({len(TOOLS)} available):
{tool_list}

REACT FORMAT — output EXACTLY this every turn:
THOUGHT: <explicit reasoning about what to do and why>
TOOL: <tool_name or NONE>
TOOL_INPUT: <JSON object or null>
DONE: <true|false>

APEX MISSION RULES:
- Use web search tools FIRST — never fabricate statistics
- For ANY income/opportunity task → scrape_live_opportunities first (real scored results)
- Zero budget task? → find_free_resources + scrape_live_opportunities (curated hustles)
- Market unknown? → analyze_market_trends before recommending anything
- Freelance/client work? → scrape_live_opportunities + write_cold_outreach + optionally send_email
- Social media goal? → write_content + post_twitter/post_linkedin (if permitted)
- Business setup? → deep_research + find_free_resources + build_profile_content + generate_proposal
- Partnership goal? → find_partners + write_cold_outreach + optionally send_email
- Contracts needed? → web_search for client + generate_contract + optionally send_email
- Daily plan needed? → create_daily_action_plan with specific tasks + milestones
- User applied somewhere? → create_follow_up_plan with timed sequence
- Progress question? → growth_milestone_check to show exact gap to next stage
- Set DONE=true only when you have enough to write a complete, actionable final answer
- All content must be SPECIFIC to {country} and use {currency}
"""


def _final_system(currency) -> str:
    return f"""Write the FINAL complete output for this APEX Agent run.
You have all the research, tool outputs, and reasoning. Be comprehensive.

Return ONLY valid JSON (no fences):
{{
  "agent_response": "What the agent did and found — warm and direct (3-5 sentences)",
  "plan": {{
    "title": "Short workflow title",
    "income_type": "freelance|youtube|ecommerce|service|content|trading|other",
    "viability": 0-100,
    "timeline": "e.g. 2-4 weeks",
    "income_range": {{"min": 0, "max": 0, "currency": "{currency}"}},
    "warning": "One honest warning"
  }},
  "steps": [{{
    "order": 1, "title": "...", "description": "Specific actions",
    "type": "automated|manual|outsource",
    "ai_output": "If automated — COMPLETE ready-to-use content here",
    "tools": ["..."], "time_minutes": 30, "is_critical": true
  }}],
  "free_tools": [{{"name":"...","url":"...","purpose":"...","is_free":true}}],
  "documents_generated": [{{"type":"contract|invoice|proposal","content":"FULL DOC TEXT"}}],
  "outreach_messages": [{{"type":"email|dm|whatsapp","subject":"...","body":"COMPLETE MESSAGE"}}],
  "opportunities_found": [{{"title":"...","url":"...","platform":"...","fit_score":0-100,"why":"..."}}],
  "social_posts": [{{"platform":"twitter|linkedin","text":"COMPLETE POST","posted":false}}],
  "immediate_action": "The ONE specific thing to do in the next 10 minutes",
  "wealth_insight": "One deeper insight about their path to financial growth"
}}
"""


# ═══════════════════════════════════════════════════════════════════
# REACT LOOP
# ═══════════════════════════════════════════════════════════════════

def _parse(text: str) -> Dict:
    out = {"thought": "", "tool": None, "tool_input": None, "done": False}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("THOUGHT:"):
            out["thought"] = line[8:].strip()
        elif line.startswith("TOOL:"):
            v = line[5:].strip()
            out["tool"] = None if v.upper() in ("NONE", "NULL", "") else v
        elif line.startswith("TOOL_INPUT:"):
            v = line[11:].strip()
            if v and v.lower() not in ("null", "none"):
                try:
                    out["tool_input"] = json.loads(v)
                except Exception:
                    out["tool_input"] = {"query": v}
        elif line.startswith("DONE:"):
            out["done"] = line[5:].strip().lower() == "true"
    return out


async def _react_loop(task, profile, budget, hours, currency, permissions) -> Dict:
    system   = _agent_system(profile, task, budget, hours, currency, permissions)
    messages = [{"role": "user", "content": f"Begin: {task}"}]
    memory   = []
    last_result = {}

    for i in range(1, MAX_REACT_ITERATIONS + 1):
        ctx = ""
        if memory:
            ctx = "\n─── COMPLETED STEPS ───\n" + "".join(
                f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'}\n"
                f"THOUGHT: {m['thought']}\n"
                f"RESULT: {m['observation'][:350]}...\n" if len(m['observation']) > 350
                else f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'}\n"
                     f"THOUGHT: {m['thought']}\n"
                     f"RESULT: {m['observation']}\n"
                for m in memory
            ) + "\n─── Continue ───"

        result = await ai_service.chat(
            messages=messages + ([{"role": "assistant", "content": ctx}] if ctx else []),
            system=system, max_tokens=800,
        )
        last_result = result
        turn = _parse(result["content"])

        obs = ""
        if turn["tool"] and turn["tool"] in TOOLS:
            obs = await _execute_tool(turn["tool"], turn["tool_input"] or {"query": task},
                                       profile, permissions)
        elif turn["tool"]:
            obs = json.dumps({"error": f"Tool '{turn['tool']}' not in registry"})

        memory.append({
            "thought":     turn["thought"],
            "tool":        turn["tool"],
            "input":       turn["tool_input"],
            "observation": obs,
            "iteration":   i,
        })
        if turn["done"] or i == MAX_REACT_ITERATIONS:
            break

    return {"memory": memory, "iterations": len(memory), "model": last_result.get("model", "unknown")}


# ═══════════════════════════════════════════════════════════════════
# QUOTA
# ═══════════════════════════════════════════════════════════════════

async def _check_quota(user_id, is_premium=False) -> Dict:
    limit = PREMIUM_DAILY_RUNS if is_premium else DEFAULT_DAILY_RUNS
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    key   = f"agent_runs:{user_id}:{today}"
    try:
        sb   = supabase_service.client
        row  = sb.table("agent_run_quota").select("*").eq("quota_key", key).maybe_single().execute()
        used = row.data["runs_used"] if row.data else 0
        if used >= limit:
            return {"allowed": False, "runs_used": used, "runs_limit": limit,
                    "resets_at": f"{today}T23:59:59Z"}
        if row.data:
            sb.table("agent_run_quota").update({"runs_used": used + 1}).eq("quota_key", key).execute()
        else:
            sb.table("agent_run_quota").insert({
                "quota_key": key, "user_id": user_id, "runs_used": 1,
                "quota_date": today, "quota_limit": limit,
            }).execute()
        return {"allowed": True, "runs_used": used + 1, "runs_limit": limit}
    except Exception as e:
        logger.warning(f"Quota check error: {e}")
        return {"allowed": True, "runs_used": 1, "runs_limit": limit}


# ═══════════════════════════════════════════════════════════════════
# WORKFLOW SAVE
# ═══════════════════════════════════════════════════════════════════

async def _save_workflow(user_id, task, data, currency, workflow_id=None):
    plan  = data.get("plan", {})
    steps = data.get("steps", [])
    if not (plan and steps):
        return workflow_id
    try:
        sb = supabase_service.client
        if not workflow_id:
            wf = sb.table("workflows").insert({
                "user_id":            user_id, "title": plan.get("title", task[:50]),
                "goal":               task,    "income_type": plan.get("income_type", "other"),
                "currency":           currency, "status": "active", "total_revenue": 0.0,
                "viability_score":    plan.get("viability", 75),
                "realistic_timeline": plan.get("timeline", ""),
                "potential_min":      plan.get("income_range", {}).get("min", 0),
                "potential_max":      plan.get("income_range", {}).get("max", 0),
                "honest_warning":     plan.get("warning", ""),
                "research_snapshot":  json.dumps(data),
            }).execute()
            workflow_id = wf.data[0]["id"] if wf.data else None

        if workflow_id and steps:
            sb.table("workflow_steps").insert([{
                "workflow_id":  workflow_id, "user_id": user_id,
                "order_index":  s.get("order", i + 1), "title": s.get("title", ""),
                "description":  s.get("description", ""), "step_type": s.get("type", "manual"),
                "time_minutes": s.get("time_minutes", 30),
                "tools":        json.dumps(s.get("tools", [])),
                "ai_output":    s.get("ai_output", ""), "status": "pending",
            } for i, s in enumerate(steps)]).execute()

        free_tools = data.get("free_tools", [])
        if free_tools and workflow_id:
            sb.table("workflow_tools").insert([{
                "workflow_id": workflow_id, "name": t.get("name", ""),
                "url": t.get("url", ""), "purpose": t.get("purpose", ""),
                "is_free": t.get("is_free", True),
            } for t in free_tools]).execute()

        # Save generated documents
        for doc in data.get("documents_generated", []):
            if doc.get("content") and workflow_id:
                try:
                    sb.table("agent_documents").insert({
                        "workflow_id": workflow_id, "user_id": user_id,
                        "doc_type": doc.get("type", "document"),
                        "content":  doc.get("content", ""),
                    }).execute()
                except Exception:
                    pass
    except Exception as e:
        logger.error(f"Workflow save error: {e}")
    return workflow_id


def _sse(event, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data) if not isinstance(data, str) else data}\n\n"


def _build_final_prompt(task, memory) -> str:
    memory_text = "\n\n".join(
        f"[Step {m['iteration']}]\nTHOUGHT: {m['thought']}\n"
        f"TOOL: {m['tool'] or 'none'}\nRESULT: {m['observation']}"
        for m in memory
    )
    return f"TASK: {task}\n\nRESEARCH & ACTIONS:\n{memory_text}\n\nWrite the final structured response."


async def _finalize(task, memory, currency) -> Dict:
    final = await ai_service.chat(
        messages=[{"role": "user", "content": _build_final_prompt(task, memory)}],
        system=_final_system(currency), max_tokens=4000,
    )
    raw = final["content"].strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    try:
        return json.loads(raw.strip())
    except Exception:
        s, e = raw.find("{"), raw.rfind("}") + 1
        return json.loads(raw[s:e]) if s >= 0 and e > s else {"agent_response": raw}


# ═══════════════════════════════════════════════════════════════════
# ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.post("/run")
@limiter.limit(AI_LIMIT)
async def run_agent(req: AgentRequest, request: Request,
                    user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    currency   = req.currency or profile.get("currency", "NGN")

    quota = await _check_quota(user_id, is_premium)
    if not quota["allowed"]:
        raise HTTPException(429, {
            "error": "Daily run limit reached",
            "runs_used": quota["runs_used"], "runs_limit": quota["runs_limit"],
            "upgrade_prompt": "Upgrade to Premium for 25 runs/day",
        })

    permissions = {"allow_email": req.allow_email,
                   "allow_social_post": req.allow_social_post,
                   "social_tokens": req.social_tokens or {}}

    react = await _react_loop(req.task, profile, req.budget or 0,
                               req.hours_per_day or 2, currency, permissions)
    agent_data  = await _finalize(req.task, react["memory"], currency)
    workflow_id = await _save_workflow(user_id, req.task, agent_data, currency, req.workflow_id)

    return {**agent_data, "workflow_id": workflow_id,
            "model_used": react["model"], "iterations": react["iterations"],
            "task": req.task, "quota": quota}


@router.post("/run-stream")
@limiter.limit(AI_LIMIT)
async def run_agent_stream(req: AgentRequest, request: Request,
                            user: dict = Depends(get_current_user)):
    """
    Full streaming agent run via SSE.
    Events: quota_check | thinking | tool_call | tool_result | action_done | finalizing | complete | error
    """
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    currency   = req.currency or profile.get("currency", "NGN")
    permissions = {"allow_email": req.allow_email,
                   "allow_social_post": req.allow_social_post,
                   "social_tokens": req.social_tokens or {}}

    async def stream():
        quota = await _check_quota(user_id, is_premium)
        yield _sse("quota_check", {**quota, "runs_remaining": quota["runs_limit"] - quota["runs_used"]})

        if not quota["allowed"]:
            yield _sse("error", {"message": "Daily run limit reached. Upgrade for more runs.",
                                  "resets_at": quota.get("resets_at", "")})
            return

        system   = _agent_system(profile, req.task, req.budget or 0,
                                  req.hours_per_day or 2, currency, permissions)
        messages = [{"role": "user", "content": f"Begin: {req.task}"}]
        memory   = []
        last_model = "unknown"

        for i in range(1, MAX_REACT_ITERATIONS + 1):
            ctx = ""
            if memory:
                ctx = "\n─── COMPLETED ───\n" + "".join(
                    f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'} | {m['observation'][:250]}...\n"
                    if len(m['observation']) > 250
                    else f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'} | {m['observation']}\n"
                    for m in memory
                ) + "\n─── Continue ───"

            result = await ai_service.chat(
                messages=messages + ([{"role": "assistant", "content": ctx}] if ctx else []),
                system=system, max_tokens=800,
            )
            last_model = result.get("model", "unknown")
            turn = _parse(result["content"])
            cat  = TOOLS.get(turn["tool"] or "", {}).get("category", "")

            yield _sse("thinking", {
                "iteration": i, "thought": turn["thought"],
                "total": MAX_REACT_ITERATIONS,
            })

            obs = ""
            if turn["tool"] and turn["tool"] in TOOLS:
                tool_input = turn["tool_input"] or {"query": req.task}
                yield _sse("tool_call", {"iteration": i, "tool": turn["tool"],
                                          "category": cat, "input": tool_input})
                obs = await _execute_tool(turn["tool"], tool_input, profile, permissions)

                try:
                    preview = json.loads(obs)
                except Exception:
                    preview = {"raw": obs[:300]}

                yield _sse("tool_result", {"iteration": i, "tool": turn["tool"],
                                            "category": cat,
                                            "preview": str(obs)[:350]})
                if cat == "action":
                    yield _sse("action_done", {"tool": turn["tool"], "result": preview})

            elif turn["tool"]:
                obs = json.dumps({"error": f"Unknown tool: {turn['tool']}"})

            memory.append({"thought": turn["thought"], "tool": turn["tool"],
                            "input": turn["tool_input"], "observation": obs, "iteration": i})

            if turn["done"] or i == MAX_REACT_ITERATIONS:
                break

        yield _sse("finalizing", {"message": "Writing your complete plan..."})
        agent_data  = await _finalize(req.task, memory, currency)
        workflow_id = await _save_workflow(user_id, req.task, agent_data, currency, req.workflow_id)

        yield _sse("complete", {**agent_data, "workflow_id": workflow_id,
                                 "model_used": last_model, "iterations": len(memory),
                                 "task": req.task, "quota": quota})

    return StreamingResponse(stream(), media_type="text/event-stream",
                              headers={"Cache-Control": "no-cache",
                                        "X-Accel-Buffering": "no",
                                        "Access-Control-Allow-Origin": "*"})


@router.post("/chat")
@limiter.limit(AI_LIMIT)
async def agent_chat(req: AgentChatRequest, request: Request,
                      user: dict = Depends(get_current_user)):
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id) or {}
    history: List[Dict] = req.history[-14:] if req.history else []
    if not history and req.session_id:
        try:
            msgs    = await supabase_service.get_messages(req.session_id, limit=14)
            history = [{"role": m["role"], "content": m["content"]}
                       for m in msgs if m["role"] in ("user", "assistant")]
        except Exception:
            pass

    wf_ctx = ""
    if req.workflow_id:
        try:
            wf = supabase_service.client.table("workflows") \
                   .select("title,goal").eq("id", req.workflow_id).single().execute()
            if wf.data:
                wf_ctx = f"\nWORKFLOW: {wf.data['title']} — {wf.data['goal']}"
        except Exception:
            pass

    system = (
        f"You are APEX — RiseUp's Autonomous Agent for {profile.get('full_name','User')}.\n"
        f"Country: {profile.get('country','NG')} | Skills: {', '.join(profile.get('current_skills',[]) or [])}"
        f" | Currency: {profile.get('currency','NGN')}{wf_ctx}\n\n"
        "RULES: Write COMPLETE deliverables. No placeholders. Full text always. "
        "Specific to user's country and context. You produce real work, not advice."
    )

    history.append({"role": "user", "content": req.message})
    result     = await ai_service.chat(messages=history, system=system, max_tokens=2500)
    ai_content = result["content"]

    session_id = req.session_id
    try:
        if not session_id:
            conv       = await supabase_service.create_conversation(user_id, "APEX Session")
            session_id = conv["id"]
        await supabase_service.save_message(session_id, user_id, "user", req.message)
        await supabase_service.save_message(session_id, user_id, "assistant", ai_content,
                                            ai_model=result.get("model"))
    except Exception as e:
        logger.error(f"Session save: {e}")

    return {"content": ai_content, "session_id": session_id, "model_used": result.get("model")}


@router.post("/execute-tool")
@limiter.limit(AI_LIMIT)
async def execute_tool(req: ExecuteToolRequest, request: Request,
                        user: dict = Depends(get_current_user)):
    if req.tool not in TOOLS:
        raise HTTPException(400, {"error": f"Unknown tool: {req.tool}", "valid": list(TOOLS.keys())})
    profile = await supabase_service.get_profile(user["id"]) or {}
    permissions = {"allow_email": True, "allow_social_post": True, "social_tokens": {}}
    raw = await _execute_tool(req.tool, req.input, profile, permissions)
    try:
        output = json.loads(raw)
    except Exception:
        output = {"result": raw}
    if req.workflow_id and req.input.get("step_id"):
        try:
            supabase_service.client.table("workflow_steps") \
                .update({"ai_output": json.dumps(output)}) \
                .eq("id", req.input["step_id"]).eq("workflow_id", req.workflow_id).execute()
        except Exception:
            pass
    return {"tool": req.tool, "output": output}


@router.post("/quick")
@limiter.limit(AI_LIMIT)
async def quick_execute(req: QuickRequest, request: Request,
                         user: dict = Depends(get_current_user)):
    profile  = await supabase_service.get_profile(user["id"]) or {}
    currency = profile.get("currency", "NGN")
    country  = profile.get("country", "NG")
    result   = await ai_service.chat(
        messages=[{"role": "user", "content": req.task}],
        system=(f"You are APEX for {profile.get('full_name','User')} in {country}. "
                f"TASK: {req.task}. Produce COMPLETE ready-to-use output. "
                f"Be specific to {country}. Use {currency}. No generic advice."),
        max_tokens=1800,
    )
    return {"output": result["content"], "task": req.task, "model_used": result.get("model")}


@router.post("/analyze")
@limiter.limit(AI_LIMIT)
async def analyze(req: AnalyzeRequest, request: Request,
                   user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"]) or {}
    result  = await ai_service.chat(
        messages=[{"role": "user", "content": f"Analyze and improve:\n\n{req.content}"}],
        system=(f"Improvement engine. Goal: {req.goal}. Currency: {profile.get('currency','NGN')}. "
                'Return JSON: {"issues":[...],"improved_version":"FULL REWRITE","key_changes":[...],'
                '"score_before":0,"score_after":0}'),
        max_tokens=2000,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        output = json.loads(raw)
    except Exception:
        output = {"improved_version": result["content"], "issues": [], "key_changes": []}
    return {"analysis": output, "model_used": result.get("model")}


@router.post("/scan")
@limiter.limit(AI_LIMIT)
async def scan(req: ScanRequest, request: Request,
                user: dict = Depends(get_current_user)):
    """Scan web + curated DB for real opportunities, AI-scored against the user's profile."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    opps    = await scraper_engine.find_opportunities(
        profile=profile,
        max_results=20,
        score_with_ai=True,
    )
    return {"opportunities": opps, "total": len(opps),
            "scanned_at": datetime.now(timezone.utc).isoformat()}


# ── GrowthAI-derived endpoints ────────────────────────────────────

class OpportunitySearchRequest(BaseModel):
    query:           Optional[str]       = None
    types:           Optional[List[str]] = None   # jobs | freelance | hustles
    max_results:     int                 = 20
    score_with_ai:   bool                = True

class MarketAnalysisRequest(BaseModel):
    industry: str
    skill:    Optional[str] = None

class DailyPlanRequest(BaseModel):
    goal:      Optional[str] = None
    timeframe: Optional[str] = "today"

class ScoreOpportunityRequest(BaseModel):
    opportunity: Dict[str, Any]

class FollowUpRequest(BaseModel):
    context: str   # e.g. "applied for copywriter role at Acme on Upwork 3 days ago"

class EarningInsightRequest(BaseModel):
    earnings: List[Dict[str, Any]]  # [{source, amount, date}, ...]

class MilestoneRequest(BaseModel):
    monthly_income: Optional[float] = None


@router.post("/opportunities/search")
@limiter.limit(AI_LIMIT)
async def search_opportunities(
    req: OpportunitySearchRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Search real live opportunities from RemoteOK, Reddit, HackerNews
    and a curated hustle database — all AI-scored for the user.
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    query   = req.query or " ".join(
        (profile.get("current_skills") or [])[:3]
    )
    opps = await scraper_engine.find_opportunities(
        profile       = profile,
        opp_types     = req.types or ["jobs", "hustles", "freelance"],
        query         = query,
        max_results   = req.max_results,
        score_with_ai = req.score_with_ai,
    )
    return {"total": len(opps), "opportunities": opps}


@router.get("/opportunities/trending")
async def get_trending_opportunities(
    category: Optional[str] = None,
    limit:    int            = 20,
    user: dict = Depends(get_current_user),
):
    """Get trending opportunities across all categories."""
    opps = await scraper_engine.get_trending(category=category, limit=limit)
    return {"total": len(opps), "opportunities": opps}


@router.post("/market-analysis")
@limiter.limit(AI_LIMIT)
async def market_analysis(
    req: MarketAnalysisRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Analyse market trends for any industry or skill:
    demand level, pay ranges, growth trajectory, best platforms, future outlook.
    """
    profile  = await supabase_service.get_profile(user["id"]) or {}
    currency = profile.get("currency", "USD")
    country  = profile.get("country", "NG")

    system = (
        "You are a market analyst with current 2025/2026 data. "
        f"User is in {country}, currency {currency}. "
        "Analyse the given industry/skill. Return ONLY valid JSON: "
        '{"demand_level":"high|medium|low",'
        '"avg_pay_range":{"min":0,"max":0,"currency":"USD","period":"month"},'
        '"growth_trajectory":"growing|stable|declining",'
        '"competition_level":"high|medium|low",'
        '"best_platforms":["..."],"in_demand_skills":["..."],'
        '"future_outlook":"...","recommendations":["..."]}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content":
                   f"Analyse market for: {req.industry}"
                   + (f", skill: {req.skill}" if req.skill else "")}],
        system=system,
        max_tokens=800,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"summary": result["content"]}
    return {**data, "industry": req.industry, "skill": req.skill}


@router.post("/daily-plan")
@limiter.limit(AI_LIMIT)
async def create_daily_plan(
    req: DailyPlanRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Generate a personalised daily action plan with specific tasks,
    time allocations, and income milestones for the user's current stage.
    """
    profile  = await supabase_service.get_profile(user["id"]) or {}
    currency = profile.get("currency", "USD")
    country  = profile.get("country",  "NG")
    stage    = profile.get("stage",    "survival")
    skills   = ", ".join(profile.get("current_skills", []) or ["not set"])
    income   = profile.get("monthly_income", 0)
    goal     = req.goal or f"Grow my income from {currency} {income:,.0f}/mo"

    system = (
        f"You are a personal income coach for {profile.get('full_name','User')} "
        f"in {country} ({stage.upper()} stage). Currency: {currency}. Skills: {skills}. "
        "Create a SPECIFIC, time-blocked daily action plan. "
        "Return ONLY valid JSON: "
        '{"overview":"...","daily_tasks":[{"time":"8am","task":"...","duration_mins":30}],'
        '"weekly_milestones":["..."],"resources_needed":["..."],'
        '"potential_obstacles":["..."],"mitigation_strategies":["..."],'
        '"income_target":"...","confidence_score":0-100}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Create my daily plan. Goal: {goal}. Timeframe: {req.timeframe}"}],
        system=system,
        max_tokens=1500,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan = json.loads(raw)
    except Exception:
        plan = {"overview": result["content"], "daily_tasks": []}

    # Persist as tasks in Supabase
    try:
        sb = supabase_service.client
        for t in (plan.get("daily_tasks") or [])[:8]:
            sb.table("tasks").insert({
                "user_id":     user["id"],
                "title":       t.get("task", ""),
                "description": f"Time: {t.get('time','')} | Duration: {t.get('duration_mins',30)}min",
                "status":      "pending",
                "category":    "daily_plan",
            }).execute()
    except Exception as e:
        logger.warning(f"Task save error: {e}")

    return {**plan, "goal": goal, "model_used": result.get("model")}


@router.post("/score-opportunity")
@limiter.limit(AI_LIMIT)
async def score_opportunity(
    req: ScoreOpportunityRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    AI-score a specific opportunity against the user's profile.
    Returns match score, risk level, action steps, time to first earning.
    """
    profile  = await supabase_service.get_profile(user["id"]) or {}
    opp      = req.opportunity
    currency = profile.get("currency", "USD")
    country  = profile.get("country",  "NG")
    skills   = profile.get("current_skills", [])
    stage    = profile.get("stage", "survival")

    system = (
        f"You are an opportunity analyst. User: {country}, {stage} stage, "
        f"skills: {skills}, currency: {currency}. "
        "Score this opportunity for them. Return ONLY valid JSON: "
        '{"match_score":0-100,"summary":"2-sentence personalised summary",'
        '"risk_level":"low|medium|high","action_steps":["Step 1","Step 2","Step 3"],'
        '"time_to_first_earning":"e.g. 1-2 weeks",'
        '"potential_monthly":0,"why_good_fit":"...","why_might_not_fit":"..."}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content":
                   f"Score this opportunity:\n{json.dumps(opp, indent=2)}"}],
        system=system,
        max_tokens=600,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"match_score": 50, "summary": result["content"]}
    return {**data, "opportunity_title": opp.get("title", "")}


@router.post("/follow-up-plan")
@limiter.limit(AI_LIMIT)
async def create_follow_up_plan(
    req: FollowUpRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Create a follow-up sequence for an application or outreach —
    complete with message text, timing, and how to handle each response.
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    name    = profile.get("full_name", "User")
    system  = (
        f"You are an outreach expert for {name}. "
        "Create a complete follow-up sequence with FULL message text. "
        "Return ONLY valid JSON: "
        '{"follow_up_1":{"when":"e.g. 3 days after","subject":"...","message":"FULL MESSAGE TEXT"},'
        '"follow_up_2":{"when":"...","subject":"...","message":"FULL MESSAGE TEXT"},'
        '"if_no_response":"what to do if still no reply after follow-up 2",'
        '"if_rejected":"how to respond gracefully to a rejection and pivot",'
        '"if_interested":"next steps if they respond positively"}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Create follow-up plan for: {req.context}"}],
        system=system,
        max_tokens=1200,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan = json.loads(raw)
    except Exception:
        plan = {"follow_up_1": {"message": result["content"]}}
    return {**plan, "context": req.context, "model_used": result.get("model")}


@router.post("/earnings-insight")
@limiter.limit(AI_LIMIT)
async def earnings_insight(
    req: EarningInsightRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Analyse earnings history and return growth rate, top sources,
    trend, and the recommended next action to hit the income goal.
    """
    profile  = await supabase_service.get_profile(user["id"]) or {}
    currency = profile.get("currency", "USD")
    goal     = profile.get("target_monthly_income", 0)

    system = (
        f"You are a financial analyst. Currency: {currency}. Income goal: {currency} {goal:,.0f}/mo. "
        "Analyse these earnings and give actionable insight. Return ONLY valid JSON: "
        '{"growth_rate":"e.g. +23% MoM","top_source":"...","monthly_trend":"growing|stable|declining",'
        '"total_analysed":0,"average_monthly":0,"insight":"3-sentence analysis",'
        '"next_milestone":"...","recommended_action":"single most impactful next step",'
        '"months_to_goal":0}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content":
                   f"Analyse these earnings:\n{json.dumps(req.earnings, indent=2)}"}],
        system=system,
        max_tokens=700,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"insight": result["content"]}
    return {**data, "model_used": result.get("model")}


@router.post("/milestone-check")
@limiter.limit(AI_LIMIT)
async def milestone_check(
    req: MilestoneRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """
    Check progress against wealth stage milestones.
    Returns current stage, % to next, milestones achieved, and single best action.
    """
    profile        = await supabase_service.get_profile(user["id"]) or {}
    currency       = profile.get("currency", "USD")
    stage          = profile.get("stage",    "survival")
    income         = req.monthly_income or profile.get("monthly_income", 0)
    target         = profile.get("target_monthly_income", 0)
    skills         = profile.get("current_skills", [])
    country        = profile.get("country", "NG")

    system = (
        f"You are a wealth coach for {profile.get('full_name','User')} in {country}. "
        f"Current stage: {stage}. Monthly income: {currency} {income:,.0f}. "
        f"Target: {currency} {target:,.0f}. Skills: {skills}. "
        "Analyse their milestone progress. Return ONLY valid JSON: "
        '{"current_stage":"survival|earning|growing|wealth",'
        '"progress_to_next":0-100,"next_stage":"...","income_gap":0,'
        '"milestones_achieved":["..."],"next_milestones":["..."],'
        '"stage_definition":"what defines their current stage",'
        '"action_to_advance":"The ONE thing that would most accelerate their progress",'
        '"timeline_to_next_stage":"realistic estimate e.g. 2-3 months"}'
    )
    result = await ai_service.chat(
        messages=[{"role": "user", "content": "Analyse my wealth stage progress."}],
        system=system,
        max_tokens=700,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"current_stage": stage, "action_to_advance": result["content"]}
    return {**data, "model_used": result.get("model")}


@router.get("/quota")
async def get_quota(user: dict = Depends(get_current_user)):
    limit = PREMIUM_DAILY_RUNS if user.get("is_premium") else DEFAULT_DAILY_RUNS
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    key   = f"agent_runs:{user['id']}:{today}"
    try:
        sb   = supabase_service.client
        row  = sb.table("agent_run_quota").select("runs_used").eq("quota_key", key).maybe_single().execute()
        used = row.data["runs_used"] if row.data else 0
        return {"runs_used": used, "runs_limit": limit, "runs_remaining": limit - used}
    except Exception:
        return {"runs_used": 0, "runs_limit": limit, "runs_remaining": limit}


@router.get("/tools")
async def list_tools():
    return {
        "total": len(TOOLS),
        "categories": {
            cat: [{"name": n, "description": m["description"]}
                  for n, m in TOOLS.items() if m["category"] == cat]
            for cat in ["thinking", "research", "action", "document", "intelligence"]
        },
    }

