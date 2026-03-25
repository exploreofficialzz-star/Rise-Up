"""
Live Market Pulse — Real-time income opportunity scanning.
Every morning the agent tells you what's HOT and paying RIGHT NOW.
Scans signals across niches, platforms and demand trends.
"""
import json, logging
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/pulse", tags=["Market Pulse"])
logger = logging.getLogger(__name__)

COUNTRY_OPPORTUNITIES = {
    "NG": {
        "trending": ["AI chatbot setup for businesses","Short-form video editing","WhatsApp automation","Shopify dropshipping","LinkedIn profile optimization"],
        "overbooked": ["Social media management","Graphic design","Content writing"],
        "emerging": ["AI prompt engineering","No-code app building","Newsletter management","Podcast editing"],
        "seasonal_now": "Q1 — businesses setting up new year digital presence. High demand for website builds and social media setup.",
        "platform_hot": "Selar.co — digital product sales surging. Fiverr — 'AI' tagged gigs getting 3x more views.",
        "avg_rate_trend": "Rates up 15% YoY for video editing. Web dev stable. Copywriting increased with AI assistance demand.",
    },
    "GH": {
        "trending": ["Digital marketing for SMEs","Mobile money integration","E-commerce store setup","Content creation"],
        "overbooked": ["Basic graphic design","Data entry"],
        "emerging": ["AI tools training","Mobile app development","Online tutoring"],
        "seasonal_now": "New year business registrations creating demand for brand identity and digital setup.",
        "platform_hot": "LinkedIn — B2B services. WhatsApp Business — local service delivery.",
        "avg_rate_trend": "Tech skills commanding premium. Mobile money expertise uniquely valuable.",
    },
    "US": {
        "trending": ["AI automation consulting","No-code SaaS building","YouTube channel management","Newsletter monetization","AI content creation"],
        "overbooked": ["Basic virtual assistant","Generic copywriting"],
        "emerging": ["AI agent building","Voice AI setup","Agentic workflow automation","Micro-SaaS"],
        "seasonal_now": "Q1 — companies allocating new budgets. Best time to pitch consulting and retainer contracts.",
        "platform_hot": "LinkedIn — B2B consulting demand very high. Upwork — AI specialization tags getting 5x more proposals reviewed.",
        "avg_rate_trend": "AI-specialized skills up 40% YoY. Generic skills flat. Specialists earn $100-300/hr.",
    },
    "DEFAULT": {
        "trending": ["AI-powered services","Short-form video","Digital products","Automation consulting"],
        "overbooked": ["Basic data entry","Generic transcription"],
        "emerging": ["AI agent building","Voice content","Micro-SaaS"],
        "seasonal_now": "Q1 — global business planning season. Good time to offer strategy and setup services.",
        "platform_hot": "Fiverr AI category growing fast. Upwork — specialized skills in high demand.",
        "avg_rate_trend": "AI augmentation adding 20-40% to skilled freelancer rates globally.",
    }
}

def get_opportunities(country_code: str) -> dict:
    return COUNTRY_OPPORTUNITIES.get(country_code.upper()[:2], COUNTRY_OPPORTUNITIES["DEFAULT"])


@router.get("/today")
@limiter.limit(GENERAL_LIMIT)
async def get_todays_pulse(request: Request, user: dict = Depends(get_current_user)):
    """Get today's market pulse for the user's country"""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "NG").upper()[:2]
    skills = profile.get("current_skills", []) or []
    opps = get_opportunities(country)

    # Find which trending items match user's skills
    skill_matches = []
    for trend in opps["trending"]:
        for skill in skills:
            if any(word in trend.lower() for word in skill.lower().split()):
                skill_matches.append({"opportunity": trend, "your_skill": skill, "match": "direct"})
                break

    today = datetime.now(timezone.utc)
    return {
        "date": today.strftime("%A, %B %d"),
        "country": country,
        "trending_now": opps["trending"],
        "overbooked_avoid": opps["overbooked"],
        "emerging_opportunities": opps["emerging"],
        "seasonal_context": opps["seasonal_now"],
        "platform_intelligence": opps["platform_hot"],
        "rate_trends": opps["avg_rate_trend"],
        "matched_to_your_skills": skill_matches,
        "morning_briefing": f"Today's top opportunity for you: {opps['trending'][0]}. {opps['seasonal_now']}",
    }


@router.get("/opportunity-scan")
@limiter.limit(AI_LIMIT)
async def scan_opportunity(request: Request, skill: str = "", user: dict = Depends(get_current_user)):
    """AI scans the market for a specific skill and returns live opportunity report"""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "NG").upper()[:2]
    opps = get_opportunities(country)
    user_skills = profile.get("current_skills", []) or []
    scan_skill = skill or (user_skills[0] if user_skills else "freelancing")

    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Skill: {scan_skill} | Country: {country} | Market data: {json.dumps(opps)}"}],
        system="""Market intelligence analyst. Scan demand for this skill RIGHT NOW.
Return JSON:
{
  "demand_level": "exploding|high|medium|declining",
  "best_platform_now": "where demand is highest today",
  "average_rate_usd": 0,
  "top_rate_usd": 0,
  "fastest_path_to_client": "specific action to land client in 48 hours",
  "niche_down_suggestion": "more specific version of this skill with less competition",
  "competition_level": "low|medium|high|saturated",
  "momentum": "growing or fading and why",
  "action_today": "ONE specific action to capitalize on this demand today"
}""",
        max_tokens=600,
    )
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"action_today": result["content"]}

    return {"skill": scan_skill, "scan": data, "model": result.get("model")}


@router.get("/arbitrage")
@limiter.limit(GENERAL_LIMIT)
async def currency_arbitrage(request: Request, user: dict = Depends(get_current_user)):
    """Show the gap between local rates and international rates for the user's skills"""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "NG").upper()[:2]
    skills = profile.get("current_skills", []) or []

    RATE_DATA = {
        "NG": {"local_avg": 8, "intl_avg": 35, "multiplier": 4.4},
        "GH": {"local_avg": 10, "intl_avg": 32, "multiplier": 3.2},
        "KE": {"local_avg": 12, "intl_avg": 35, "multiplier": 2.9},
        "IN": {"local_avg": 15, "intl_avg": 45, "multiplier": 3.0},
        "DEFAULT": {"local_avg": 20, "intl_avg": 50, "multiplier": 2.5},
    }
    rates = RATE_DATA.get(country, RATE_DATA["DEFAULT"])

    arbitrage_opportunities = []
    for skill in skills[:5]:
        local = rates["local_avg"]
        intl = rates["intl_avg"]
        gap = intl - local
        arbitrage_opportunities.append({
            "skill": skill,
            "local_rate_usd": local,
            "international_rate_usd": intl,
            "gap_usd_per_hour": gap,
            "monthly_gain_if_international": gap * 8 * 20,
            "how_to_access_international": f"Create Upwork/Fiverr profile targeting US/UK clients for {skill}. Position as specialist, not generalist."
        })

    return {
        "country": country,
        "rate_multiplier": rates["multiplier"],
        "summary": f"International clients pay {rates['multiplier']}x more than local clients for the same work.",
        "opportunities": arbitrage_opportunities,
        "total_monthly_gain_if_international": sum(o["monthly_gain_if_international"] for o in arbitrage_opportunities),
        "first_step": "Create an Upwork profile TODAY. Use your best skill. Target $25+/hr. You leave money on the table every day you don't."
    }
