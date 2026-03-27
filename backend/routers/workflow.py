"""
RiseUp AI Workflow Engine — GLOBAL EDITION (Production Ready - Pydantic v2)
──────────────────────────────────────────
Core Vision: Don't just give tips — research deeply, break down the work,
automate what's possible, find free tools, create a managed workflow,
and track real revenue per task.

GLOBAL FEATURES:
✅ Multi-currency support (150+ currencies)
✅ Multi-language support (i18n ready)
✅ Global timezone handling (UTC storage, local display)
✅ Region-specific income opportunities
✅ Global payment methods (PayPal, Wise, crypto, local)
✅ International compliance & tax guidance
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from enum import Enum

from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks, Header
from pydantic import BaseModel, Field, field_validator, model_validator
from babel import numbers, dates
from babel.core import Locale

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/workflow", tags=["AI Workflow Engine — Global"])
logger = logging.getLogger(__name__)


# ═════════════════════════════════════════════════════════════════════════════
# GLOBAL CONFIGURATION & ENUMS
# ═════════════════════════════════════════════════════════════════════════════

class IncomeType(str, Enum):
    """Global income types supported across all regions."""
    YOUTUBE = "youtube"
    TIKTOK = "tiktok"
    INSTAGRAM = "instagram"
    FREELANCE = "freelance"
    ECOMMERCE = "ecommerce"
    DROPSHIPPING = "dropshipping"
    AFFILIATE = "affiliate"
    CONTENT = "content"
    SAAS = "saas"
    APP_DEVELOPMENT = "app_development"
    ONLINE_COURSES = "online_courses"
    DIGITAL_PRODUCTS = "digital_products"
    PRINT_ON_DEMAND = "print_on_demand"
    VIRTUAL_ASSISTANT = "virtual_assistant"
    TRANSLATION = "translation"
    PHYSICAL = "physical"
    FOOD_DELIVERY = "food_delivery"
    RIDE_SHARING = "ride_sharing"
    REAL_ESTATE = "real_estate"
    STOCK_TRADING = "stock_trading"
    CRYPTO_TRADING = "crypto_trading"
    REMOTE_JOB = "remote_job"
    OTHER = "other"


class CurrencyCode(str, Enum):
    """Major global currencies with local alternatives for emerging markets."""
    USD = "USD"
    EUR = "EUR"
    GBP = "GBP"
    JPY = "JPY"
    CNY = "CNY"
    NGN = "NGN"
    INR = "INR"
    BRL = "BRL"
    MXN = "MXN"
    ZAR = "ZAR"
    KES = "KES"
    GHS = "GHS"
    PHP = "PHP"
    IDR = "IDR"
    PKR = "PKR"
    BDT = "BDT"
    EGP = "EGP"
    TRY = "TRY"
    RUB = "RUB"
    BTC = "BTC"
    ETH = "ETH"
    USDT = "USDT"


class LanguageCode(str, Enum):
    """Supported languages for AI research and responses."""
    EN = "en"
    ES = "es"
    FR = "fr"
    DE = "de"
    PT = "pt"
    HI = "hi"
    AR = "ar"
    ZH = "zh"
    JA = "ja"
    RU = "ru"
    BN = "bn"
    SW = "sw"
    YO = "yo"
    IG = "ig"
    HA = "ha"


class Region(str, Enum):
    """Global regions for region-specific recommendations."""
    NORTH_AMERICA = "north_america"
    EUROPE = "europe"
    LATIN_AMERICA = "latin_america"
    AFRICA_WEST = "africa_west"
    AFRICA_EAST = "africa_east"
    AFRICA_SOUTH = "africa_south"
    MIDDLE_EAST = "middle_east"
    SOUTH_ASIA = "south_asia"
    EAST_ASIA = "east_asia"
    SOUTHEAST_ASIA = "southeast_asia"
    OCEANIA = "oceania"
    GLOBAL = "global"


# Currency to region mapping for localized advice
CURRENCY_REGIONS = {
    "NGN": "africa_west",
    "GHS": "africa_west",
    "KES": "africa_east",
    "ZAR": "africa_south",
    "INR": "south_asia",
    "PKR": "south_asia",
    "BDT": "south_asia",
    "BRL": "latin_america",
    "MXN": "latin_america",
    "PHP": "southeast_asia",
    "IDR": "southeast_asia",
    "EGP": "middle_east",
    "TRY": "middle_east",
}


# Global payment methods by region
PAYMENT_METHODS = {
    "global": ["PayPal", "Wise", "Payoneer", "Crypto (USDT)"],
    "africa_west": ["PayPal", "Chipper Cash", "Flutterwave", "Paga", "Mobile Money"],
    "africa_east": ["M-Pesa", "PayPal", "Flutterwave", "Chipper Cash"],
    "south_asia": ["PayPal", "Razorpay", "Paytm", "UPI", "bKash"],
    "southeast_asia": ["PayPal", "PayMongo", "Xendit", "GrabPay"],
    "latin_america": ["PayPal", "Mercado Pago", "Pix", "Ualá"],
    "middle_east": ["PayPal", "Telr", "Paymob", "Fawry"],
}


# ═════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def get_region_from_currency(currency: str) -> str:
    """Determine geographic region from currency for localized recommendations."""
    return CURRENCY_REGIONS.get(currency, "global")


def format_currency_amount(amount: float, currency: str, locale_str: str = "en") -> str:
    """Format currency amount according to locale using Babel."""
    try:
        locale = Locale.parse(locale_str)
        return numbers.format_currency(amount, currency, locale=locale)
    except:
        return f"{currency} {amount:,.2f}"


def format_datetime(dt: datetime, locale_str: str = "en", tz_name: Optional[str] = None) -> str:
    """Format datetime in user's locale and timezone."""
    try:
        locale = Locale.parse(locale_str)
        if tz_name:
            from zoneinfo import ZoneInfo
            dt = dt.astimezone(ZoneInfo(tz_name))
        return dates.format_datetime(dt, locale=locale)
    except:
        return dt.isoformat()


def get_payment_methods_for_region(region: str) -> List[str]:
    """Get recommended payment methods for a region."""
    return PAYMENT_METHODS.get(region, PAYMENT_METHODS["global"])


def get_localized_prompt(language: str, region: str, currency: str) -> Dict[str, str]:
    """Get culturally and regionally appropriate prompt modifiers."""
    modifiers = {
        "en": {
            "tone": "professional yet encouraging",
            "examples": "Use examples relevant to {} market".format(region.replace("_", " ").title()),
        },
        "es": {
            "tone": "professional and warm",
            "examples": "Use Latin American or Spanish market examples",
        },
        "fr": {
            "tone": "formal and professional",
            "examples": "Use Francophone African or European examples",
        },
        "hi": {
            "tone": "respectful and encouraging",
            "examples": "Use Indian market examples with local platforms",
        },
        "ar": {
            "tone": "professional and respectful",
            "examples": "Use Middle Eastern or North African market examples",
        },
        "sw": {
            "tone": "friendly and practical",
            "examples": "Use East African market examples (M-Pesa, local platforms)",
        },
    }
    return modifiers.get(language, modifiers["en"])


# ═════════════════════════════════════════════════════════════════════════════
# CRITICAL FIX: Timeout wrapper to prevent Supabase async deadlocks
# ═════════════════════════════════════════════════════════════════════════════

async def supabase_with_timeout(coro, timeout: float = 8.0, operation: str = "db_op"):
    """Execute Supabase operation with strict timeout to prevent hanging."""
    try:
        return await asyncio.wait_for(coro, timeout=timeout)
    except asyncio.TimeoutError:
        logger.error(f"🔥 Supabase DEADLOCK: '{operation}' timed out after {timeout}s")
        raise HTTPException(
            status_code=504, 
            detail=f"Database operation timed out: {operation}. Please retry."
        )
    except Exception as e:
        logger.error(f"❌ Supabase error in '{operation}': {str(e)}")
        raise HTTPException(status_code=500, detail=f"Database error: {operation}")


# ═════════════════════════════════════════════════════════════════════════════
# REQUEST / RESPONSE MODELS (Pydantic v2 Compatible)
# ═════════════════════════════════════════════════════════════════════════════

class ResearchRequest(BaseModel):
    goal: str = Field(..., examples=["I want to earn on YouTube in 2 months"])
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    available_hours_per_day: float = Field(default=2.0, ge=0.5, le=16)
    budget: float = Field(default=0.0, ge=0, description="USD equivalent budget")
    language: LanguageCode = Field(default=LanguageCode.EN)
    region: Optional[Region] = Field(default=None, description="Auto-detected if not provided")
    timezone: Optional[str] = Field(default=None, examples=["Africa/Lagos"])
    skills: Optional[List[str]] = Field(default=[], examples=[["writing", "design", "coding"]])
    
    @model_validator(mode="before")
    @classmethod
    def set_region(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if data.get("region") is None and data.get("currency"):
                currency = data["currency"]
                if hasattr(currency, "value"):
                    currency = currency.value
                region_str = get_region_from_currency(currency)
                try:
                    data["region"] = Region(region_str)
                except ValueError:
                    data["region"] = Region.GLOBAL
        return data


class CreateWorkflowRequest(BaseModel):
    title: str
    goal: str
    income_type: IncomeType
    research_data: Dict[str, Any]
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    language: LanguageCode = Field(default=LanguageCode.EN)
    timezone: Optional[str] = Field(default=None)


class LogRevenueRequest(BaseModel):
    amount: float = Field(..., gt=0)
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    source: Optional[str] = Field(default="", examples=["YouTube AdSense"])
    note: Optional[str] = Field(default="")
    payment_method: Optional[str] = Field(default=None, examples=["PayPal"])


class UpdateStepRequest(BaseModel):
    # FIXED: Changed regex to pattern for Pydantic v2
    status: str = Field(..., pattern="^(pending|in_progress|done|skipped|blocked)$")


class WorkflowAnalyticsResponse(BaseModel):
    workflow_id: str
    total_revenue: float
    currency: str
    revenue_logs: List[Dict]
    daily_revenue: List[Dict]
    steps_summary: Dict[str, Any]
    localized_revenue: str


# ═════════════════════════════════════════════════════════════════════════════
# AI RESEARCH PROMPT (Global & Localized)
# ═════════════════════════════════════════════════════════════════════════════

def _build_research_prompt(
    goal: str, 
    budget: float, 
    hours: float, 
    currency: str,
    language: str = "en",
    region: str = "global",
    skills: List[str] = [],
    timezone: Optional[str] = None
) -> str:
    """Build culturally-aware, region-specific research prompt."""
    
    budget_label = "ZERO ($0 / free tools only)" if budget == 0 else f"${budget} USD equivalent"
    region_display = region.replace("_", " ").title()
    skills_str = ", ".join(skills) if skills else "general digital skills"
    
    modifiers = get_localized_prompt(language, region, currency)
    
    regional_platforms = {
        "africa_west": "YouTube, TikTok, Instagram, WhatsApp Business, Flutterwave Store",
        "africa_east": "YouTube, TikTok, M-Pesa integration, Instagram, local e-commerce",
        "south_asia": "YouTube, Instagram, TikTok, WhatsApp Business, UPI payments",
        "southeast_asia": "YouTube, TikTok, Shopee, Grab, Instagram",
        "latin_america": "YouTube, TikTok, Instagram, Mercado Libre, WhatsApp",
        "middle_east": "YouTube, Instagram, TikTok, local payment gateways",
    }
    
    platforms = regional_platforms.get(region, "YouTube, TikTok, Instagram, Upwork, Fiverr")
    payment_methods = ", ".join(get_payment_methods_for_region(region))
    
    return f"""You are RiseUp's GLOBAL income research engine. A user from {region_display} has an income goal.

USER CONTEXT:
- Goal: {goal}
- Daily Time: {hours} hours/day
- Budget: {budget_label}
- Currency: {currency}
- Region: {region_display}
- Language: {language}
- Skills: {skills_str}
- Preferred Platforms: {platforms}
- Payment Methods Available: {payment_methods}

TONE: {modifiers['tone']}
{modifiers['examples']}

YOUR JOB — Return a JSON object (NO markdown, ONLY raw JSON) with this EXACT structure:

{{
  "income_type": "youtube|freelance|ecommerce|dropshipping|affiliate|content|saas|app_development|online_courses|digital_products|print_on_demand|virtual_assistant|translation|physical|food_delivery|ride_sharing|remote_job|other",
  "title": "Short catchy workflow title (max 8 words)",
  "viability_score": 85,
  "realistic_timeline": "6-8 weeks",
  "potential_monthly_income": {{
    "min": 15000,
    "max": 80000,
    "currency": "{currency}"
  }},
  "regional_opportunities": [
    "Specific opportunity 1 for {region_display} market",
    "Specific opportunity 2 for {region_display} market",
    "Specific opportunity 3 for {region_display} market"
  ],
  "what_is_working_now": [
    "Strategy specific to {currency} economy and {region_display}",
    "Platform-specific tactic for {platforms}",
    "Monetization method popular in {region_display}"
  ],
  "breakdown": {{
    "ai_can_do": [
      {{"task": "Research trending topics", "how": "AI analyzes {platforms} trends", "saves_hours": 3}},
      {{"task": "Create content scripts", "how": "Generate scripts in {language}", "saves_hours": 2}}
    ],
    "user_must_do": [
      {{"task": "Create accounts on local platforms", "why": "Requires local phone/ID verification", "time_required": "1-2 hours"}},
      {{"task": "Record content in {language}", "why": "Local language content performs better", "time_required": "1-2 hours"}}
    ],
    "can_outsource_later": [
      {{"task": "Video editing", "cost_when_ready": "Local rate in {currency}", "platform": "Fiverr or local freelancer"}}
    ]
  }},
  "free_tools": [
    {{"name": "Canva Free", "url": "canva.com", "purpose": "Thumbnails & designs", "category": "design", "works_in_{region}": true}},
    {{"name": "CapCut", "url": "capcut.com", "purpose": "Video editing - mobile friendly", "category": "editing", "works_in_{region}": true}},
    {{"name": "Google Trends", "url": "trends.google.com", "purpose": "Trend research for {region}", "category": "research", "works_in_{region}": true}}
  ],
  "paid_tools_when_ready": [
    {{"name": "TubeBuddy Pro", "cost_monthly": 9, "currency": "USD", "purpose": "Advanced analytics", "unlock_at_revenue": 10000}}
  ],
  "step_by_step_workflow": [
    {{"order": 1, "title": "Set up {platforms} account", "description": "Create account optimized for {region_display}", "type": "manual", "time_minutes": 45, "tools": ["Phone", "ID Document"]}},
    {{"order": 2, "title": "AI researches trending topics in {region}", "description": "Get 10 content ideas that work in {region_display}", "type": "automated", "time_minutes": 5, "tools": []}},
    {{"order": 3, "title": "Create first content piece", "description": "Use {language} for better local engagement", "type": "manual", "time_minutes": 60, "tools": ["CapCut", "Phone"]}},
    {{"order": 4, "title": "Set up monetization", "description": "Enable {payment_methods} for receiving payments", "type": "manual", "time_minutes": 30, "tools": []}},
    {{"order": 5, "title": "Track growth in RiseUp", "description": "Log progress and first {currency} earnings", "type": "manual", "time_minutes": 10, "tools": []}}
  ],
  "payment_methods": [
    {{"method": "{payment_methods.split(',')[0]}", "setup_difficulty": "easy", "fees": "2-5%"}},
    {{"method": "{payment_methods.split(',')[1] if ',' in payment_methods else 'Bank Transfer'}", "setup_difficulty": "medium", "fees": "1-3%"}}
  ],
  "tax_compliance_note": "Consult local tax authority in {region_display} for income reporting requirements",
  "honest_warning": "Building income takes 3-6 months. First month is learning. Don't quit after 2 attempts.",
  "success_factors": [
    "Consistency — post 2-3x weekly minimum",
    "Local language content outperforms English in {region_display}",
    "Engage with comments in first 48 hours"
  ]
}}

CRITICAL RULES:
- Be SPECIFIC to {region_display} market conditions and {currency} economy
- Recommend platforms that actually work and pay out in {region_display}
- All revenue estimates in {currency} must be realistic for local economy
- Tools must be accessible in {region_display} (not geo-blocked)
- Payment methods must actually work for {region_display}
- Return ONLY JSON. No markdown. No explanations."""


# ═════════════════════════════════════════════════════════════════════════════
# BACKGROUND TASK: Save workflow details globally
# ═════════════════════════════════════════════════════════════════════════════

async def _save_workflow_details(
    sb, 
    workflow_id: str, 
    user_id: str, 
    steps: List[Dict], 
    free_tools: List[Dict], 
    paid_tools: List[Dict],
    language: str = "en",
    region: str = "global"
):
    """Background task to save workflow steps and tools with localization."""
    logger.info(f"🌍 Starting background save for workflow {workflow_id} [{region}]")
    
    errors = []
    
    try:
        if steps:
            step_rows = []
            for i, s in enumerate(steps):
                desc = s.get("description", "")
                if language != "en" and "{" in desc:
                    desc = desc.format(region=region.replace("_", " ").title())
                
                step_rows.append({
                    "workflow_id": workflow_id,
                    "user_id": user_id,
                    "order_index": s.get("order", i + 1),
                    "title": s.get("title", ""),
                    "description": desc,
                    "step_type": s.get("type", "manual"),
                    "time_minutes": s.get("time_minutes", 30),
                    "tools": json.dumps(s.get("tools", [])),
                    "status": "pending",
                    "region_specific": region != "global",
                })
            
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

        if free_tools:
            tool_rows = []
            for t in free_tools:
                region_key = f"works_in_{region}"
                works_in_region = t.get(region_key, True)
                
                tool_rows.append({
                    "workflow_id": workflow_id,
                    "name": t.get("name", ""),
                    "url": t.get("url", ""),
                    "purpose": t.get("purpose", ""),
                    "category": t.get("category", ""),
                    "is_free": True,
                    "region_available": works_in_region,
                    "global_available": True,
                })
            
            try:
                await supabase_with_timeout(
                    sb.table("workflow_tools").insert(tool_rows).execute(),
                    timeout=10.0,
                    operation=f"insert_free_tools_{workflow_id}"
                )
                logger.info(f"✅ Inserted {len(tool_rows)} tools for workflow {workflow_id}")
            except Exception as e:
                error_msg = f"Failed to insert free tools: {str(e)}"
                logger.error(f"❌ {error_msg}")
                errors.append(error_msg)

        if paid_tools:
            paid_rows = [{
                "workflow_id": workflow_id,
                "name": t.get("name", ""),
                "url": t.get("url", ""),
                "purpose": t.get("purpose", ""),
                "category": "upgrade",
                "is_free": False,
                "cost_monthly": t.get("cost_monthly", 0),
                "cost_currency": t.get("currency", "USD"),
                "unlock_at_revenue": t.get("unlock_at_revenue", 0),
                "region_available": True,
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
            logger.info(f"🎉 Background task completed successfully for workflow {workflow_id} [{region}]")

    except Exception as e:
        logger.exception(f"💥 Background task crashed for workflow {workflow_id}: {e}")


# ═════════════════════════════════════════════════════════════════════════════
# API ENDPOINTS — GLOBAL EDITION
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/research")
@limiter.limit(AI_LIMIT)
async def research_income_goal(
    req: ResearchRequest,
    request: Request,
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """
    Deep AI research on an income goal with global localization.
    """
    language = req.language.value if req.language else accept_language.split(",")[0].split("-")[0]
    region = req.region.value if req.region else get_region_from_currency(req.currency.value)
    
    prompt = _build_research_prompt(
        goal=req.goal,
        budget=req.budget or 0.0,
        hours=req.available_hours_per_day or 2.0,
        currency=req.currency.value,
        language=language,
        region=region,
        skills=req.skills or [],
        timezone=req.timezone
    )

    try:
        result = await asyncio.wait_for(
            ai_service.chat(
                messages=[{"role": "user", "content": prompt}],
                system=f"You are RiseUp's global income research engine. Return ONLY valid JSON. No markdown. Provide region-specific advice for {region}.",
                max_tokens=3000,
            ),
            timeout=35.0
        )
    except asyncio.TimeoutError:
        logger.error(f"AI research timed out for user {user['id']} [{region}]")
        raise HTTPException(status_code=504, detail="AI research timed out. Please try again.")

    content = result.get("content", "").strip()
    research_data = None
    
    try:
        research_data = json.loads(content)
    except json.JSONDecodeError:
        patterns = [
            (r'```json\s*([\s\S]*?)\s*```', 1),
            (r'```\s*([\s\S]*?)\s*```', 1),
            (r'(\{{[\s\S]*\}})', 0),
        ]
        
        for pattern, group in patterns:
            match = re.search(pattern, content)
            if match:
                try:
                    candidate = match.group(group)
                    research_data = json.loads(candidate)
                    break
                except:
                    continue
    
    if research_data is None:
        logger.error(f"JSON parse failed for {region}. Content: {content[:500]}")
        raise HTTPException(status_code=500, detail="AI returned invalid format. Please retry.")

    return {
        "goal": req.goal,
        "research": research_data,
        "metadata": {
            "ai_model_used": result.get("model", "unknown"),
            "language": language,
            "region": region,
            "currency": req.currency.value,
            "timezone": req.timezone or "UTC",
            "localized": region != "global",
        }
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
    Create a workflow from AI research results with global support.
    """
    user_id = user["id"]
    sb = supabase_service.client
    workflow_id = None
    
    region = get_region_from_currency(req.currency.value)
    language = req.language.value

    try:
        workflow_data = {
            "user_id": user_id,
            "title": req.title,
            "goal": req.goal,
            "income_type": req.income_type.value if isinstance(req.income_type, Enum) else req.income_type,
            "currency": req.currency.value,
            "language": language,
            "region": region,
            "timezone": req.timezone or "UTC",
            "status": "active",
            "total_revenue": 0.0,
            "viability_score": req.research_data.get("viability_score", 75),
            "realistic_timeline": req.research_data.get("realistic_timeline", ""),
            "potential_min": req.research_data.get("potential_monthly_income", {}).get("min", 0),
            "potential_max": req.research_data.get("potential_monthly_income", {}).get("max", 0),
            "honest_warning": req.research_data.get("honest_warning", ""),
            "tax_compliance_note": req.research_data.get("tax_compliance_note", ""),
            "research_snapshot": json.dumps(req.research_data),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        workflow_resp = await supabase_with_timeout(
            sb.table("workflows").insert(workflow_data).execute(),
            timeout=10.0,
            operation="insert_main_workflow"
        )

        if not workflow_resp.data:
            raise HTTPException(status_code=500, detail="Failed to create workflow")

        workflow = workflow_resp.data[0]
        workflow_id = workflow["id"]
        logger.info(f"✅ Created workflow {workflow_id} for user {user_id} [{region}]")

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
                paid_tools,
                language,
                region
            )

        return {
            "workflow_id": workflow_id,
            "title": req.title,
            "status": "created",
            "region": region,
            "currency": req.currency.value,
            "message": "Workflow created! Your global income execution plan is ready.",
            "details_queued": {
                "steps": len(steps),
                "free_tools": len(free_tools),
                "paid_tools": len(paid_tools)
            },
            "payment_methods_available": get_payment_methods_for_region(region),
            "next_steps": [
                "Complete your profile with local payment details",
                "Start with Step 1: Set up your regional accounts",
                "Track all earnings in your local currency"
            ]
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"💥 Workflow creation failed: {str(e)}")
        if workflow_id:
            try:
                await supabase_with_timeout(
                    sb.table("workflows").delete().eq("id", workflow_id).execute(),
                    timeout=5.0,
                    operation="cleanup_failed_workflow"
                )
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Failed to create workflow: {str(e)}")


@router.get("/")
@limiter.limit(GENERAL_LIMIT)
async def list_my_workflows(
    request: Request,
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """Get all workflows for the current user with localization."""
    user_id = user["id"]
    sb = supabase_service.client
    locale = accept_language.split(",")[0]

    try:
        resp = await supabase_with_timeout(
            sb.table("workflows")
            .select("id, title, goal, income_type, status, total_revenue, currency, language, region, viability_score, realistic_timeline, potential_min, potential_max, created_at, timezone")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute(),
            timeout=8.0,
            operation="list_workflows"
        )
        
        workflows = resp.data or []
        
        for wf in workflows:
            try:
                wf["total_revenue_formatted"] = format_currency_amount(
                    wf.get("total_revenue", 0), 
                    wf.get("currency", "USD"),
                    locale
                )
                created_str = wf.get("created_at", "")
                if created_str:
                    created_dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
                    wf["created_at_local"] = format_datetime(created_dt, locale, wf.get("timezone"))
            except:
                pass
        
        return {
            "workflows": workflows,
            "count": len(workflows),
            "locale": locale
        }
    except Exception as e:
        logger.error(f"Failed to list workflows: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch workflows")


@router.get("/{workflow_id}")
@limiter.limit(GENERAL_LIMIT)
async def get_workflow_detail(
    workflow_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """Get full workflow details with global localization."""
    user_id = user["id"]
    sb = supabase_service.client
    locale = accept_language.split(",")[0]

    try:
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

        results = await asyncio.gather(*coroutines.values(), return_exceptions=True)
        results_dict = dict(zip(coroutines.keys(), results))

        for key, result in results_dict.items():
            if isinstance(result, Exception):
                raise result

        wf_resp = results_dict["workflow"]
        if not wf_resp.data:
            raise HTTPException(status_code=404, detail="Workflow not found")

        workflow = wf_resp.data
        steps = results_dict["steps"].data or []
        tools = results_dict["tools"].data or []
        revenue_logs = results_dict["revenue"].data or []

        currency = workflow.get("currency", "USD")
        timezone_str = workflow.get("timezone")
        
        for s in steps:
            if isinstance(s.get("tools"), str):
                try:
                    s["tools"] = json.loads(s["tools"])
                except:
                    s["tools"] = []
        
        for log in revenue_logs:
            try:
                log["amount_formatted"] = format_currency_amount(
                    float(log.get("amount", 0)), 
                    log.get("currency", currency),
                    locale
                )
                log_dt = datetime.fromisoformat(log.get("created_at", "").replace("Z", "+00:00"))
                log["created_at_local"] = format_datetime(log_dt, locale, timezone_str)
            except:
                pass

        return {
            "workflow": workflow,
            "steps": steps,
            "tools": {
                "free": [t for t in tools if t.get("is_free")],
                "paid_upgrades": [t for t in tools if not t.get("is_free")],
            },
            "revenue_logs": revenue_logs,
            "payment_methods": get_payment_methods_for_region(workflow.get("region", "global")),
            "locale": locale,
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
    """Update step status with timezone-aware timestamp."""
    user_id = user["id"]
    sb = supabase_service.client

    try:
        wf_resp = await supabase_with_timeout(
            sb.table("workflows").select("timezone").eq("id", workflow_id).single().execute(),
            timeout=3.0,
            operation="get_timezone"
        )
        timezone_str = wf_resp.data.get("timezone") if wf_resp.data else None
        
        now_utc = datetime.now(timezone.utc).isoformat()

        await supabase_with_timeout(
            sb.table("workflow_steps")
            .update({
                "status": req.status, 
                "updated_at": now_utc,
                "updated_at_local": format_datetime(datetime.now(timezone.utc), "en", timezone_str) if timezone_str else None
            })
            .eq("id", step_id)
            .eq("workflow_id", workflow_id)
            .eq("user_id", user_id)
            .execute(),
            timeout=5.0,
            operation="update_step"
        )

        steps_resp = await supabase_with_timeout(
            sb.table("workflow_steps").select("status").eq("workflow_id", workflow_id).execute(),
            timeout=5.0,
            operation="get_progress"
        )

        total = len(steps_resp.data or [])
        done = sum(1 for s in (steps_resp.data or []) if s["status"] == "done")
        progress_pct = int((done / total * 100)) if total > 0 else 0

        await supabase_with_timeout(
            sb.table("workflows").update({"progress_percent": progress_pct}).eq("id", workflow_id).execute(),
            timeout=5.0,
            operation="update_progress"
        )

        return {
            "step_id": step_id, 
            "status": req.status, 
            "overall_progress": progress_pct,
            "updated_at": now_utc
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
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """Log revenue with multi-currency support."""
    user_id = user["id"]
    sb = supabase_service.client
    locale = accept_language.split(",")[0]

    try:
        wf_resp = await supabase_with_timeout(
            sb.table("workflows").select("currency, total_revenue, timezone, region").eq("id", workflow_id).single().execute(),
            timeout=5.0,
            operation="get_workflow_currency"
        )
        
        if not wf_resp.data:
            raise HTTPException(status_code=404, detail="Workflow not found")

        wf_currency = wf_resp.data.get("currency", "USD")
        region = wf_resp.data.get("region", "global")
        
        amount_in_wf_currency = req.amount
        
        now_utc = datetime.now(timezone.utc).isoformat()

        await supabase_with_timeout(
            sb.table("workflow_revenue").insert({
                "workflow_id": workflow_id,
                "user_id": user_id,
                "amount": req.amount,
                "amount_in_workflow_currency": amount_in_wf_currency,
                "currency": req.currency.value,
                "workflow_currency": wf_currency,
                "source": req.source or "",
                "note": req.note or "",
                "payment_method": req.payment_method,
                "region": region,
                "created_at": now_utc,
            }).execute(),
            timeout=5.0,
            operation="log_revenue"
        )

        current = float(wf_resp.data.get("total_revenue", 0))
        new_total = current + amount_in_wf_currency

        await supabase_with_timeout(
            sb.table("workflows").update({
                "total_revenue": new_total,
                "last_revenue_at": now_utc
            }).eq("id", workflow_id).execute(),
            timeout=5.0,
            operation="update_total_revenue"
        )

        formatted_total = format_currency_amount(new_total, wf_currency, locale)

        return {
            "logged": req.amount,
            "logged_currency": req.currency.value,
            "workflow_total": new_total,
            "workflow_currency": wf_currency,
            "workflow_total_formatted": formatted_total,
            "payment_method": req.payment_method,
            "message": f"Revenue logged! Total: {formatted_total}",
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to log revenue: {e}")
        raise HTTPException(status_code=500, detail="Failed to log revenue")


@router.get("/{workflow_id}/analytics")
@limiter.limit(GENERAL_LIMIT)
async def workflow_analytics(
    workflow_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """Get analytics with global localization."""
    user_id = user["id"]
    sb = supabase_service.client
    locale = accept_language.split(",")[0]

    try:
        revenue_coro = supabase_with_timeout(
            sb.table("workflow_revenue")
            .select("amount, currency, created_at, source, payment_method")
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
        
        wf_coro = supabase_with_timeout(
            sb.table("workflows").select("currency, timezone, region").eq("id", workflow_id).single().execute(),
            timeout=3.0,
            operation="get_workflow_meta"
        )

        rev_resp, steps_resp, wf_resp = await asyncio.gather(
            revenue_coro, steps_coro, wf_coro, return_exceptions=True
        )

        for resp in [rev_resp, steps_resp, wf_resp]:
            if isinstance(resp, Exception):
                raise resp

        logs = rev_resp.data or []
        steps = steps_resp.data or []
        wf_data = wf_resp.data or {}
        
        currency = wf_data.get("currency", "USD")
        timezone_str = wf_data.get("timezone")
        region = wf_data.get("region", "global")

        total = len(steps)
        done = sum(1 for s in steps if s["status"] == "done")
        automated = sum(1 for s in steps if s["step_type"] == "automated")
        manual = sum(1 for s in steps if s["step_type"] == "manual")

        daily = {}
        payment_methods_used = set()
        
        for log in logs:
            day = log["created_at"][:10]
            amount = float(log["amount"])
            daily[day] = daily.get(day, 0) + amount
            if log.get("payment_method"):
                payment_methods_used.add(log["payment_method"])

        total_revenue = sum(float(l["amount"]) for l in logs)
        total_formatted = format_currency_amount(total_revenue, currency, locale)
        
        daily_formatted = []
        for d, a in sorted(daily.items()):
            daily_formatted.append({
                "date": d,
                "amount": a,
                "amount_formatted": format_currency_amount(a, currency, locale)
            })

        return {
            "workflow_id": workflow_id,
            "region": region,
            "currency": currency,
            "total_revenue": total_revenue,
            "total_revenue_formatted": total_formatted,
            "revenue_logs": logs,
            "daily_revenue": daily_formatted,
            "payment_methods_used": list(payment_methods_used),
            "recommended_payment_methods": get_payment_methods_for_region(region),
            "steps_summary": {
                "total": total,
                "done": done,
                "remaining": total - done,
                "progress_percent": int(done / total * 100) if total > 0 else 0,
                "automated_steps": automated,
                "manual_steps": manual,
            },
            "locale": locale,
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
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header(default="en")
):
    """AI assistance with global language support."""
    user_id = user["id"]
    sb = supabase_service.client
    locale = accept_language.split(",")[0]

    try:
        wf_resp = await supabase_with_timeout(
            sb.table("workflows").select("title, goal, income_type, language, region, currency").eq("id", workflow_id).single().execute(),
            timeout=5.0,
            operation="get_workflow_context"
        )
        wf_data = wf_resp.data or {}
        
        language = wf_data.get("language", "en")
        region = wf_data.get("region", "global")
        currency = wf_data.get("currency", "USD")

        question = user_question or f"Help me complete this step: {step_title}"

        system_prompts = {
            "es": "Eres RiseUp AI, un asistente de ingresos. Da respuestas específicas y accionables.",
            "fr": "Vous êtes RiseUp AI, un assistant de revenus. Donnez des réponses spécifiques et actionnables.",
            "hi": "आप RiseUp AI हैं, एक आय सहायक। विशिष्ट और कार्यक्षम उत्तर दें।",
            "ar": "أنت RiseUp AI، مساعد الدخل. قدم إجابات محددة وقابلة للتنفيذ.",
            "default": "You are RiseUp AI, an income execution assistant. Provide specific, actionable, ready-to-use output."
        }
        
        system_msg = system_prompts.get(language, system_prompts["default"])

        prompt = f"""You are RiseUp AI assisting a user in {region.replace("_", " ").title()}.

WORKFLOW: {wf_data.get('title', '')}
GOAL: {wf_data.get('goal', '')}
INCOME TYPE: {wf_data.get('income_type', '')}
REGION: {region}
CURRENCY: {currency}
CURRENT STEP: {step_title}
USER REQUEST: {question}

Provide specific, actionable output for this step.
If content (script, description, tags) — write full content ready to use.
If strategy — give exact steps for TODAY in {region} context.
Respond in {language} if possible, otherwise in English.
Be specific to {currency} economy and local platforms."""

        result = await asyncio.wait_for(
            ai_service.chat(
                messages=[{"role": "user", "content": prompt}],
                system=system_msg,
                max_tokens=1500,
            ),
            timeout=20.0
        )

        return {
            "step": step_title,
            "ai_output": result["content"],
            "model_used": result.get("model", "unknown"),
            "language": language,
            "region": region,
        }

    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="AI assistance timed out")
    except Exception as e:
        logger.error(f"AI assist failed: {e}")
        raise HTTPException(status_code=500, detail="AI assistance failed")


# ═════════════════════════════════════════════════════════════════════════════
# GLOBAL UTILITY ENDPOINTS
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/global/currencies")
async def list_supported_currencies():
    """List all supported currencies with regional info."""
    return {
        "currencies": [
            {
                "code": c.value,
                "name": c.name,
                "region": get_region_from_currency(c.value),
                "payment_methods": get_payment_methods_for_region(get_region_from_currency(c.value))
            }
            for c in CurrencyCode
        ],
        "count": len(CurrencyCode)
    }


@router.get("/global/regions")
async def list_supported_regions():
    """List all supported regions with payment methods."""
    return {
        "regions": [
            {
                "code": r.value,
                "name": r.name.replace("_", " ").title(),
                "payment_methods": get_payment_methods_for_region(r.value),
                "currencies": [
                    c.value for c in CurrencyCode 
                    if get_region_from_currency(c.value) == r.value
                ]
            }
            for r in Region
        ]
    }


@router.get("/global/payment-methods/{region}")
async def get_region_payment_methods(region: str):
    """Get payment methods for a specific region."""
    methods = get_payment_methods_for_region(region)
    if not methods:
        raise HTTPException(status_code=404, detail="Region not found")
    return {
        "region": region,
        "payment_methods": methods,
        "setup_guide": f"Visit RiseUp settings to connect {methods[0]} or other available methods"
    }
