"""
Live Market Pulse — Real-time global and local market intelligence.
Provides today's briefing, international market impulse, local trends,
personal growth insights, wealth building, career forecasting, and entrepreneurial guidance.
"""
import asyncio
import json
import logging
import httpx
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, Depends, Request, HTTPException
from pydantic import BaseModel, Field

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/pulse", tags=["Market Pulse"])
logger = logging.getLogger(__name__)


# ============================================================================
# CONFIGURATION
# ============================================================================

class PulseConfig:
    CACHE_TTL_HOURS = 24
    FX_CACHE_TTL_HOURS = 12
    MAX_SKILL_MATCHES = 5
    DEFAULT_COUNTRY = "US"
    FX_API_URL = "https://api.exchangerate-api.com/v4/latest/USD"

    @classmethod
    async def get_rate_baselines(cls, country_code: str) -> Dict[str, float]:
        try:
            baselines = await supabase_service.get_rate_baselines(country_code)
            if baselines:
                return baselines
            return await cls._calculate_dynamic_rates(country_code)
        except Exception as e:
            logger.error(f"Failed to get rate baselines for {country_code}: {e}")
            return {"local_usd": 15.0, "intl_usd": 45.0}

    @classmethod
    async def _calculate_dynamic_rates(cls, country_code: str) -> Dict[str, float]:
        try:
            ppp_data = await supabase_service.get_economic_indicators(country_code)
            gdp_ppp = ppp_data.get("gdp_per_capita_ppp", 15000)
            if gdp_ppp < 5000:
                return {"local_usd": 5.0, "intl_usd": 35.0}
            elif gdp_ppp < 15000:
                return {"local_usd": 10.0, "intl_usd": 40.0}
            elif gdp_ppp < 30000:
                return {"local_usd": 20.0, "intl_usd": 50.0}
            else:
                return {"local_usd": 40.0, "intl_usd": 70.0}
        except Exception:
            return {"local_usd": 15.0, "intl_usd": 45.0}


# ============================================================================
# CACHE MANAGER
# ============================================================================

class CacheManager:
    def __init__(self):
        self.today_cache: Dict[str, Dict[str, Any]] = {}
        self.market_cache: Dict[str, Dict[str, Any]] = {}
        self.fx_cache: Dict[str, Any] = {"rates": {}, "last_updated": None}
        self.intl_pulse_cache: Dict[str, Any] = {"data": None, "last_updated": None}

    async def get_fx_rates(self) -> Dict[str, float]:
        now = datetime.now(timezone.utc)
        if (self.fx_cache["last_updated"] and
                (now - self.fx_cache["last_updated"]) < timedelta(hours=PulseConfig.FX_CACHE_TTL_HOURS)):
            return self.fx_cache["rates"]
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(PulseConfig.FX_API_URL, timeout=10.0)
                response.raise_for_status()
                data = response.json()
                self.fx_cache["rates"] = data.get("rates", {})
                self.fx_cache["last_updated"] = now
                return self.fx_cache["rates"]
        except Exception as e:
            logger.error(f"FX fetch failed: {e}")
            return self.fx_cache["rates"] or {"USD": 1.0}

    async def get_today_pulse(self, country_code: str, generator_func) -> Dict[str, Any]:
        key = country_code.upper()
        now = datetime.now(timezone.utc)
        if key in self.today_cache:
            entry = self.today_cache[key]
            if (now - entry["timestamp"]) < timedelta(hours=PulseConfig.CACHE_TTL_HOURS):
                return entry["data"]
        fresh_data = await generator_func(key)
        self.today_cache[key] = {"timestamp": now, "data": fresh_data}
        return fresh_data

    async def get_market_pulse(self, country_code: str, generator_func) -> Dict[str, Any]:
        country_code = country_code.upper()[:2]
        now = datetime.now(timezone.utc)
        if country_code in self.market_cache:
            entry = self.market_cache[country_code]
            if (now - entry["timestamp"]) < timedelta(hours=PulseConfig.CACHE_TTL_HOURS):
                return entry["data"]
        fresh_data = await generator_func(country_code)
        self.market_cache[country_code] = {"timestamp": now, "data": fresh_data}
        return fresh_data

    async def get_international_pulse(self, generator_func) -> Dict[str, Any]:
        now = datetime.now(timezone.utc)
        if (self.intl_pulse_cache["last_updated"] and
                (now - self.intl_pulse_cache["last_updated"]) < timedelta(hours=PulseConfig.CACHE_TTL_HOURS)):
            return self.intl_pulse_cache["data"]
        fresh_data = await generator_func()
        self.intl_pulse_cache["data"] = fresh_data
        self.intl_pulse_cache["last_updated"] = now
        return fresh_data


cache_manager = CacheManager()


# ============================================================================
# DATA MODELS
# ============================================================================

class SkillMatch(BaseModel):
    opportunity: str
    your_skill: str
    match_type: str
    confidence_score: float = Field(ge=0.0, le=1.0)


# ============================================================================
# PROMPT TEMPLATES
# ============================================================================

class PromptTemplates:

    @staticmethod
    def today_pulse(country_code: str, user_skills: List[str]) -> Dict[str, str]:
        """
        Generates the daily market briefing.
        Response MUST match exactly what the Flutter frontend expects:
          trending_now, emerging_opportunities, overbooked_avoid,
          morning_briefing, date, action_today, platform_intelligence, rate_trends
        """
        today_str = datetime.now(timezone.utc).strftime("%A, %B %d, %Y")
        skills_str = ", ".join(user_skills) if user_skills else "general digital skills"

        return {
            "system": (
                "You are a Daily Market Intelligence AI delivering concise, actionable market data. "
                "Your responses must be real-world grounded, specific, and immediately useful. "
                "Return ONLY valid JSON — no markdown, no explanation, no preamble."
            ),
            "user": (
                f"Generate today's market pulse for {today_str}.\n"
                f"Country context: {country_code}\n"
                f"User skills: {skills_str}\n\n"
                "Return ONLY this exact JSON structure — no extra keys, no markdown:\n"
                "{\n"
                '  "trending_now": [\n'
                '    "8 skill or niche names that have high demand RIGHT NOW (e.g. AI Chatbot Development)"\n'
                "  ],\n"
                '  "emerging_opportunities": [\n'
                '    "5 opportunities just starting to gain traction (e.g. AI Voice Agent Building)"\n'
                "  ],\n"
                '  "overbooked_avoid": [\n'
                '    "5 oversaturated markets (e.g. Generic Logo Design)"\n'
                "  ],\n"
                f'  "morning_briefing": "2-3 sentence market overview for {today_str} — specific trends, not generic advice",\n'
                f'  "date": "{today_str}",\n'
                '  "action_today": [\n'
                '    "3 specific actionable tasks a freelancer or entrepreneur can do today"\n'
                "  ],\n"
                '  "platform_intelligence": "One paragraph on current Upwork, Fiverr, LinkedIn, Toptal trends — what is working and what is not",\n'
                '  "rate_trends": "One paragraph on current hourly/project rate trends — what categories are paying more and what is declining"\n'
                "}"
            ),
        }

    @staticmethod
    def international_pulse(skills_context: List[str] = None) -> Dict[str, str]:
        skills_str = ", ".join(skills_context) if skills_context else "various digital skills"
        return {
            "system": (
                "You are a Global Market Intelligence AI synthesizing data from WEF Future of Jobs, "
                "World Bank, LinkedIn Workforce Reports, and global freelance platform analytics. "
                "Return ONLY valid JSON — no markdown, no preamble."
            ),
            "user": (
                f"Analyze the current global labor market as of {datetime.now().strftime('%B %Y')}.\n"
                f"Context: User has skills in {skills_str}\n\n"
                "Return ONLY this JSON:\n"
                "{\n"
                '  "global_trends": {\n'
                '    "tech_adoption_impact": "specific data on how tech adoption is reshaping jobs",\n'
                '    "fastest_growing_roles": [{"role": "", "growth_rate": "", "avg_salary_usd": 0}],\n'
                '    "declining_roles": ["role names to avoid"],\n'
                '    "skills_expiration_timeline": {"skill_name": "years_until_obsolete"}\n'
                "  },\n"
                '  "emerging_sectors": [{"sector": "", "market_size_growth": "", "top_opportunities": []}],\n'
                '  "geographic_arbitrage": [{"region": "", "opportunity": "", "remote_friendly": true}],\n'
                '  "future_proofing": {\n'
                '    "immediate_skills": ["skill to acquire now"],\n'
                '    "career_pivots": [{"from": "", "to": "", "transition_difficulty": ""}],\n'
                '    "ai_augmentation": "how to position with AI"\n'
                "  },\n"
                f'  "timestamp": "{datetime.now(timezone.utc).isoformat()}"\n'
                "}"
            ),
        }

    @staticmethod
    def local_pulse(country_code: str, user_skills: List[str], economic_context: Dict) -> Dict[str, str]:
        skills_str = ", ".join(user_skills) if user_skills else "general digital skills"
        return {
            "system": (
                "You are a Local Market Intelligence AI analyzing country-specific economic data. "
                "Return ONLY valid JSON — no markdown, no preamble."
            ),
            "user": (
                f"Analyze the local market for country: {country_code}\n"
                f"User Skills: {skills_str}\n"
                f"Economic Context: {json.dumps(economic_context)}\n\n"
                "Return ONLY this JSON:\n"
                "{\n"
                '  "economic_indicators": {\n'
                '    "unemployment_rate": "",\n'
                '    "inflation_trend": "",\n'
                '    "currency_strength": "",\n'
                '    "gdp_growth": ""\n'
                "  },\n"
                '  "skill_demand": {\n'
                '    "hot_skills": [{"skill": "", "local_salary_range": "", "demand_level": ""}],\n'
                '    "oversaturated": ["skill names"],\n'
                '    "skill_gaps": ["gap opportunities"]\n'
                "  },\n"
                '  "platform_landscape": [{"platform": "", "effectiveness": "", "payment_methods": []}],\n'
                '  "seasonal_context": "current seasonal demand note",\n'
                '  "cultural_notes": "cultural business insights",\n'
                '  "local_opportunities": ["opportunity descriptions"]\n'
                "}"
            ),
        }

    @staticmethod
    def career_forecast(current_skills: List[str], interests: List[str], country: str) -> Dict[str, str]:
        return {
            "system": (
                "You are a Career Forecasting AI using labor market analytics and economic projections. "
                "Return ONLY valid JSON array — no markdown, no preamble."
            ),
            "user": (
                f"Generate career forecasts.\n"
                f"Current Skills: {json.dumps(current_skills)}\n"
                f"Interests: {json.dumps(interests)}\n"
                f"Country: {country}\n\n"
                "Return a JSON array of career path objects. Each object must have:\n"
                "title, current_demand, growth_projection, entry_barrier, time_to_proficiency,\n"
                "salary_range_usd (object with min and max as numbers),\n"
                "required_skills (array), upskill_path (array), ai_impact (string),\n"
                "geographic_hotspots (array), timeline_category (immediate|short|long)"
            ),
        }

    @staticmethod
    def entrepreneurial_scan(country: str, skills: List[str], capital_tier: str) -> Dict[str, str]:
        return {
            "system": (
                "You are an Entrepreneurship Intelligence AI analyzing market gaps and opportunities. "
                "Return ONLY valid JSON array — no markdown, no preamble."
            ),
            "user": (
                f"Identify entrepreneurial opportunities.\n"
                f"Country: {country}\n"
                f"Skills: {json.dumps(skills)}\n"
                f"Capital Tier: {capital_tier}\n\n"
                "Return a JSON array of opportunity objects. Each object must have:\n"
                "sector, problem_statement, solution_approach, market_size_usd,\n"
                "startup_cost_range_usd (object with min and max as numbers),\n"
                "time_to_revenue, scalability_score (1-10 integer), risk_level,\n"
                "local_adaptations (object with country-specific notes)"
            ),
        }

    @staticmethod
    def wealth_strategy(country: str, income_level: str, risk_tolerance: str, time_available: int) -> Dict[str, str]:
        return {
            "system": (
                "You are a Wealth Building Strategist AI specializing in income diversification. "
                "Return ONLY valid JSON array — no markdown, no preamble."
            ),
            "user": (
                f"Create wealth building strategies.\n"
                f"Country: {country}\n"
                f"Income Level: {income_level}\n"
                f"Risk Tolerance: {risk_tolerance}\n"
                f"Time Available: {time_available} hours/week\n\n"
                "Return a JSON array of strategy objects. Each object must have:\n"
                "strategy_type (active_income|passive_income|investment|skill_arbitrage),\n"
                "title, description, initial_capital_required_usd (number),\n"
                "time_commitment_hours_week (integer), expected_roi_annual_percent (number),\n"
                "risk_profile, action_steps (array), resources_needed (array)"
            ),
        }

    @staticmethod
    def personal_growth_assessment(current_challenges: List[str], goals: List[str]) -> Dict[str, str]:
        return {
            "system": (
                "You are a Personal Development AI combining productivity science and coaching. "
                "Return ONLY valid JSON array — no markdown, no preamble."
            ),
            "user": (
                f"Generate growth insights.\n"
                f"Challenges: {json.dumps(current_challenges)}\n"
                f"Goals: {json.dumps(goals)}\n\n"
                "Return a JSON array of insight objects. Each object must have:\n"
                "category (mindset|productivity|networking|health|learning),\n"
                "insight, actionable_tip, recommended_resource (nullable string),\n"
                "implementation_timeline"
            ),
        }


# ============================================================================
# HELPERS
# ============================================================================

def _clean_json(raw: str) -> str:
    """Strip markdown fences from AI response."""
    raw = raw.strip()
    for fence in ["```json", "```", "`"]:
        raw = raw.removeprefix(fence).removesuffix(fence).strip()
    return raw


async def generate_international_pulse(skills: List[str] = None) -> Dict[str, Any]:
    prompts = PromptTemplates.international_pulse(skills)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.3,
        )
        data = json.loads(_clean_json(result["content"]))
        data["_metadata"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scope": "international",
            "model": result.get("model", "unknown"),
        }
        return data
    except Exception as e:
        logger.error(f"International pulse generation failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate international market pulse")


async def generate_local_pulse(country_code: str, user_skills: List[str]) -> Dict[str, Any]:
    economic_context = await fetch_economic_context(country_code)
    prompts = PromptTemplates.local_pulse(country_code, user_skills, economic_context)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=1500,
            temperature=0.3,
        )
        data = json.loads(_clean_json(result["content"]))
        data["_metadata"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scope": "local",
            "country": country_code,
            "model": result.get("model", "unknown"),
        }
        return data
    except Exception as e:
        logger.error(f"Local pulse generation failed for {country_code}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to generate local pulse for {country_code}")


async def generate_today_pulse(country_code: str, user_skills: List[str]) -> Dict[str, Any]:
    """
    Generate today's combined briefing with ALL keys the Flutter frontend expects:
    trending_now, emerging_opportunities, overbooked_avoid, morning_briefing,
    date, action_today, platform_intelligence, rate_trends
    """
    prompts = PromptTemplates.today_pulse(country_code, user_skills)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=1200,
            temperature=0.4,
        )
        data = json.loads(_clean_json(result["content"]))

        # Validate and guarantee all required keys exist
        data.setdefault("trending_now", [])
        data.setdefault("emerging_opportunities", [])
        data.setdefault("overbooked_avoid", [])
        data.setdefault("morning_briefing", "Market data is being analyzed.")
        data.setdefault("date", datetime.now(timezone.utc).strftime("%A, %B %d, %Y"))
        data.setdefault("action_today", [])
        data.setdefault("platform_intelligence", None)
        data.setdefault("rate_trends", None)

        data["_metadata"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scope": "today",
            "country": country_code,
            "model": result.get("model", "unknown"),
        }
        return data
    except Exception as e:
        logger.error(f"Today pulse generation failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate today's market pulse")


async def fetch_economic_context(country_code: str) -> Dict[str, Any]:
    try:
        indicators = await supabase_service.get_economic_indicators(country_code)
        if indicators:
            return indicators
        return {"country_code": country_code, "data_source": "fallback",
                "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        logger.warning(f"Could not fetch economic context for {country_code}: {e}")
        return {}


async def calculate_skill_matches(
    user_skills: List[str], opportunities: List[str]
) -> List[SkillMatch]:
    if not user_skills or not opportunities:
        return []
    prompt = (
        f"Match these user skills: {json.dumps(user_skills)}\n"
        f"To these opportunities: {json.dumps(opportunities)}\n\n"
        "Return a JSON array. Each item: opportunity, your_skill, "
        "match_type (direct|adjacent|transferable), confidence_score (0.0-1.0)"
    )
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompt}],
            system="You are a skills matching AI. Return ONLY valid JSON array — no markdown.",
            max_tokens=800,
            temperature=0.2,
        )
        matches = json.loads(_clean_json(result["content"]))
        return [SkillMatch(**m) for m in matches[:PulseConfig.MAX_SKILL_MATCHES]]
    except Exception as e:
        logger.error(f"Skill matching failed: {e}")
        matches = []
        for skill in user_skills:
            for opp in opportunities:
                skill_words = set(skill.lower().split())
                opp_words = set(opp.lower().split())
                overlap = skill_words & opp_words
                if overlap:
                    confidence = len(overlap) / max(len(skill_words), len(opp_words))
                    matches.append(SkillMatch(
                        opportunity=opp, your_skill=skill,
                        match_type="direct" if confidence > 0.7 else "adjacent",
                        confidence_score=round(confidence, 2),
                    ))
        return matches[:PulseConfig.MAX_SKILL_MATCHES]


async def calculate_arbitrage(country_code: str, skills: List[str]) -> Dict[str, Any]:
    fx_rates = await cache_manager.get_fx_rates()
    rates = await PulseConfig.get_rate_baselines(country_code)
    country_currency_map = await get_country_currency_map()
    local_currency = country_currency_map.get(country_code, "USD")
    exchange_rate = fx_rates.get(local_currency, 1.0)
    multiplier = round(rates["intl_usd"] / max(rates["local_usd"], 1), 1)
    opportunities = []
    for skill in skills[:PulseConfig.MAX_SKILL_MATCHES]:
        local_usd = rates["local_usd"]
        intl_usd = rates["intl_usd"]
        gap_usd = intl_usd - local_usd
        monthly_gain_usd = gap_usd * 8 * 20
        monthly_gain_local = round(monthly_gain_usd * exchange_rate, 2)
        opportunities.append({
            "skill": skill,
            "local_rate_usd": local_usd,
            "international_rate_usd": intl_usd,
            "gap_usd_per_hour": gap_usd,
            "monthly_gain_usd": monthly_gain_usd,
            "monthly_gain_local_currency": f"{local_currency} {monthly_gain_local:,.2f}",
            "market_access_strategy": f"Target US/UK/EU clients on Upwork/Fiverr/LinkedIn for {skill}",
            "competition_level": "medium",
            "demand_trend": "growing",
        })
    return {
        "country": country_code,
        "local_currency": local_currency,
        "exchange_rate_usd": exchange_rate,
        "rate_multiplier": multiplier,
        "summary": f"International clients pay {multiplier}x more than local clients",
        "opportunities": opportunities,
        "total_monthly_potential_usd": sum(o["monthly_gain_usd"] for o in opportunities),
    }


async def get_country_currency_map() -> Dict[str, str]:
    try:
        mapping = await supabase_service.get_country_currencies()
        if mapping:
            return mapping
    except Exception as e:
        logger.error(f"Failed to fetch currency map: {e}")
    return {
        "US": "USD", "GB": "GBP", "EU": "EUR", "JP": "JPY",
        "CA": "CAD", "AU": "AUD", "CH": "CHF", "NG": "NGN",
        "GH": "GHS", "KE": "KES", "ZA": "ZAR", "IN": "INR",
        "BR": "BRL", "MX": "MXN", "PH": "PHP", "ID": "IDR",
    }


# ============================================================================
# ENDPOINTS
# ============================================================================

@router.get("/today")
@limiter.limit(GENERAL_LIMIT)
async def get_todays_pulse(request: Request, user: dict = Depends(get_current_user)):
    """
    Daily market briefing — returns the exact shape the Flutter frontend expects:
    trending_now, emerging_opportunities, overbooked_avoid, morning_briefing,
    date, action_today, platform_intelligence, rate_trends
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []

    data = await cache_manager.get_today_pulse(
        country,
        lambda c: generate_today_pulse(c, user_skills),
    )
    return data


@router.get("/international")
@limiter.limit(GENERAL_LIMIT)
async def get_international_pulse(request: Request, user: dict = Depends(get_current_user)):
    """Global trends, emerging sectors, geographic arbitrage, future-proofing."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    user_skills = profile.get("current_skills", []) or []

    pulse_data = await cache_manager.get_international_pulse(
        lambda: generate_international_pulse(user_skills)
    )

    global_opportunities = []
    for sector in pulse_data.get("emerging_sectors", []):
        global_opportunities.extend(sector.get("top_opportunities", []))

    skill_matches = await calculate_skill_matches(user_skills, global_opportunities)

    return {
        "pulse_type": "international",
        "generated_at": pulse_data.get("_metadata", {}).get("generated_at"),
        "global_trends": pulse_data.get("global_trends", {}),
        "emerging_sectors": pulse_data.get("emerging_sectors", []),
        "geographic_arbitrage": pulse_data.get("geographic_arbitrage", []),
        "future_proofing": pulse_data.get("future_proofing", {}),
        "your_skill_matches": [m.dict() for m in skill_matches],
        "strategic_recommendations": {
            "immediate_actions": pulse_data.get("future_proofing", {}).get("immediate_skills", [])[:3],
            "career_pivot_options": pulse_data.get("future_proofing", {}).get("career_pivots", [])[:2],
            "ai_strategy": pulse_data.get("future_proofing", {}).get("ai_augmentation", ""),
        },
    }


@router.get("/local")
@limiter.limit(GENERAL_LIMIT)
async def get_local_pulse(request: Request, user: dict = Depends(get_current_user)):
    """Country-specific economic data, skill demand, platform intelligence."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []

    pulse_data = await cache_manager.get_market_pulse(
        country,
        lambda c: generate_local_pulse(c, user_skills),
    )

    local_opportunities = pulse_data.get("local_opportunities", [])
    skill_demand = pulse_data.get("skill_demand", {})
    hot_skills = [s["skill"] for s in skill_demand.get("hot_skills", [])]
    skill_matches = await calculate_skill_matches(user_skills, local_opportunities + hot_skills)

    return {
        "pulse_type": "local",
        "country": country,
        "generated_at": pulse_data.get("_metadata", {}).get("generated_at"),
        "economic_indicators": pulse_data.get("economic_indicators", {}),
        "skill_demand": skill_demand,
        "platform_landscape": pulse_data.get("platform_landscape", []),
        "seasonal_context": pulse_data.get("seasonal_context", ""),
        "cultural_notes": pulse_data.get("cultural_notes", ""),
        "your_skill_matches": [m.dict() for m in skill_matches],
        "local_recommendations": {
            "platforms_to_join": [p["platform"] for p in pulse_data.get("platform_landscape", [])[:3]],
            "skills_to_highlight": [s["skill"] for s in skill_demand.get("hot_skills", [])[:3]],
            "skills_to_avoid": skill_demand.get("oversaturated", [])[:3],
        },
    }


@router.get("/career-forecast")
@limiter.limit(AI_LIMIT)
async def get_career_forecast(
    request: Request,
    timeframe: str = "all",
    user: dict = Depends(get_current_user),
):
    """Personalized career paths and transitions."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    interests = profile.get("interests", []) or []

    prompts = PromptTemplates.career_forecast(user_skills, interests, country)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.4,
        )
        career_paths = json.loads(_clean_json(result["content"]))
        if timeframe != "all":
            career_paths = [p for p in career_paths if timeframe in p.get("timeline_category", "")]
        return {
            "forecast_type": "career",
            "user_context": {"country": country, "current_skills_count": len(user_skills)},
            "career_paths": career_paths,
            "recommended_path": career_paths[0] if career_paths else None,
            "model": result.get("model"),
        }
    except Exception as e:
        logger.error(f"Career forecast failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate career forecast")


@router.get("/entrepreneurial-opportunities")
@limiter.limit(AI_LIMIT)
async def get_entrepreneurial_opportunities(
    request: Request,
    capital_tier: str = "bootstrap",
    sector: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Entrepreneurial opportunities and startup ideas."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []

    prompts = PromptTemplates.entrepreneurial_scan(country, user_skills, capital_tier)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.5,
        )
        opportunities = json.loads(_clean_json(result["content"]))
        if sector:
            opportunities = [o for o in opportunities if sector.lower() in o.get("sector", "").lower()]
        return {
            "opportunity_type": "entrepreneurial",
            "capital_tier": capital_tier,
            "country": country,
            "opportunities": opportunities,
            "total_opportunities": len(opportunities),
            "recommended_focus": opportunities[0] if opportunities else None,
            "next_steps": [
                "Validate problem with 10 potential customers",
                "Build MVP using no-code tools",
                "Join local startup community",
                "Research competitors in adjacent markets",
            ],
        }
    except Exception as e:
        logger.error(f"Entrepreneurial scan failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to scan entrepreneurial opportunities")


@router.get("/wealth-strategies")
@limiter.limit(AI_LIMIT)
async def get_wealth_strategies(
    request: Request,
    risk_tolerance: str = "moderate",
    user: dict = Depends(get_current_user),
):
    """Personalized wealth building strategies."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    income_level = profile.get("income_bracket", "middle")
    time_available = profile.get("side_hustle_hours_week", 10)

    prompts = PromptTemplates.wealth_strategy(country, income_level, risk_tolerance, time_available)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.4,
        )
        strategies = json.loads(_clean_json(result["content"]))
        return {
            "strategy_type": "wealth_building",
            "user_profile": {
                "country": country,
                "income_level": income_level,
                "risk_tolerance": risk_tolerance,
                "time_available_hours_week": time_available,
            },
            "strategies": strategies,
            "quick_wins": [s for s in strategies if s.get("expected_roi_annual_percent", 0) > 50][:3],
            "long_term_builders": [s for s in strategies if s.get("time_commitment_hours_week", 0) < 5][:3],
            "total_strategies": len(strategies),
        }
    except Exception as e:
        logger.error(f"Wealth strategy generation failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate wealth strategies")


@router.get("/personal-growth")
@limiter.limit(AI_LIMIT)
async def get_personal_growth_insights(
    request: Request,
    focus_area: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Personalized growth and development insights."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    challenges = profile.get("current_challenges", ["time_management", "skill_gaps"])
    goals = profile.get("development_goals", ["career_advancement", "income_growth"])

    prompts = PromptTemplates.personal_growth_assessment(challenges, goals)
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=1500,
            temperature=0.5,
        )
        insights = json.loads(_clean_json(result["content"]))
        if focus_area:
            insights = [i for i in insights if focus_area.lower() in i.get("category", "").lower()]
        return {
            "insight_type": "personal_growth",
            "user_context": {"challenges": challenges, "goals": goals},
            "insights": insights,
            "focus_areas": list(set(i.get("category") for i in insights if i.get("category"))),
            "priority_action": insights[0] if insights else None,
        }
    except Exception as e:
        logger.error(f"Personal growth insights failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate personal growth insights")


@router.get("/opportunity-scan")
@limiter.limit(AI_LIMIT)
async def scan_opportunity(
    request: Request,
    skill: str = "",
    user: dict = Depends(get_current_user),
):
    """Deep scan for a specific skill — full market analysis."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    scan_skill = skill.strip() or (user_skills[0] if user_skills else "digital services")

    system_prompt = (
        "You are a Market Intelligence AI. Analyze specific skill demand. "
        "Return ONLY valid JSON — no markdown, no preamble."
    )
    user_prompt = (
        f"Deep market scan for skill: {scan_skill}\n"
        f"Country: {country}\n\n"
        "Return ONLY this JSON:\n"
        "{\n"
        '  "demand_level": "HIGH|MEDIUM|LOW",\n'
        '  "best_platform_now": "platform name",\n'
        '  "average_rate_usd": 0,\n'
        '  "momentum": "Rising|Stable|Declining",\n'
        '  "action_today": "single specific action to take today",\n'
        '  "fastest_path_to_client": "specific strategy",\n'
        '  "niche_down_suggestion": "specific niche within this skill",\n'
        '  "competition_level": "HIGH|MEDIUM|LOW",\n'
        '  "top_client_countries": ["country names"],\n'
        '  "rate_entry_usd": 0,\n'
        '  "rate_senior_usd": 0\n'
        "}"
    )

    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": user_prompt}],
            system=system_prompt,
            max_tokens=800,
            temperature=0.3,
        )
        scan_data = json.loads(_clean_json(result["content"]))
        return {
            "skill_scanned": scan_skill,
            "country": country,
            "scan_results": scan_data,
            "model": result.get("model"),
        }
    except Exception as e:
        logger.error(f"Opportunity scan failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to complete opportunity scan")


@router.get("/arbitrage")
@limiter.limit(GENERAL_LIMIT)
async def currency_arbitrage(request: Request, user: dict = Depends(get_current_user)):
    """Live arbitrage opportunities using real-time exchange rates."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    skills = profile.get("current_skills", []) or []

    if not skills:
        return {
            "status": "no_skills",
            "message": "Add skills to your profile to see arbitrage opportunities.",
            "opportunities": [],
            "total_monthly_potential_usd": 0,
        }

    arbitrage_data = await calculate_arbitrage(country, skills)
    return {
        "status": "live",
        "calculation_method": "dynamic_ppp_based",
        **arbitrage_data,
        "first_step": "Create profiles on Upwork and LinkedIn targeting US/UK/EU clients",
        "pro_tips": [
            "Price in USD, not local currency",
            "Highlight timezone advantages (24h productivity)",
            "Emphasise cultural diversity as asset",
            "Build portfolio with international case studies",
        ],
    }


@router.get("/comprehensive")
@limiter.limit(AI_LIMIT)
async def get_comprehensive_pulse(request: Request, user: dict = Depends(get_current_user)):
    """All features combined in a single call."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []

    intl_task = cache_manager.get_international_pulse(lambda: generate_international_pulse(user_skills))
    local_task = cache_manager.get_market_pulse(country, lambda c: generate_local_pulse(c, user_skills))
    arb_task = calculate_arbitrage(country, user_skills)

    intl_data, local_data, arb_data = await asyncio.gather(intl_task, local_task, arb_task)

    return {
        "pulse_type": "comprehensive",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "user_country": country,
        "sections": {
            "international_market_impulse": intl_data,
            "local_market_trends": local_data,
            "arbitrage_analysis": arb_data,
        },
        "navigation": {
            "today": "/pulse/today",
            "career_forecast": "/pulse/career-forecast",
            "entrepreneurship": "/pulse/entrepreneurial-opportunities",
            "wealth_strategies": "/pulse/wealth-strategies",
            "personal_growth": "/pulse/personal-growth",
            "skill_scan": "/pulse/opportunity-scan?skill=your_skill",
        },
    }
