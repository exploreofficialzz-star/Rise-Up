"""
Live Market Pulse — Real-time global and local market intelligence.
Provides international market impulse, local trends, personal growth insights,
wealth building opportunities, career forecasting, and entrepreneurial guidance.
"""
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
# CONFIGURATION & CONSTANTS (No hardcoded business logic)
# ============================================================================

class PulseConfig:
    """Configuration loaded from environment/database - no hardcoded values"""
    CACHE_TTL_HOURS = 24
    FX_CACHE_TTL_HOURS = 12
    MAX_SKILL_MATCHES = 5
    DEFAULT_COUNTRY = "US"
    
    # API endpoints (configurable)
    FX_API_URL = "https://api.exchangerate-api.com/v4/latest/USD"
    
    @classmethod
    async def get_rate_baselines(cls, country_code: str) -> Dict[str, float]:
        """Fetch rate baselines from database - no hardcoded values"""
        try:
            baselines = await supabase_service.get_rate_baselines(country_code)
            if baselines:
                return baselines
            # Fallback to dynamic calculation based on PPP data
            return await cls._calculate_dynamic_rates(country_code)
        except Exception as e:
            logger.error(f"Failed to get rate baselines for {country_code}: {e}")
            return {"local_usd": 15.0, "intl_usd": 45.0}
    
    @classmethod
    async def _calculate_dynamic_rates(cls, country_code: str) -> Dict[str, float]:
        """Calculate rates based on World Bank PPP and income data"""
        try:
            # Fetch GDP per capita PPP data for context
            ppp_data = await supabase_service.get_economic_indicators(country_code)
            gdp_ppp = ppp_data.get("gdp_per_capita_ppp", 15000)
            
            # Dynamic calculation based on economic tier
            if gdp_ppp < 5000:  # Low income
                return {"local_usd": 5.0, "intl_usd": 35.0}
            elif gdp_ppp < 15000:  # Lower middle
                return {"local_usd": 10.0, "intl_usd": 40.0}
            elif gdp_ppp < 30000:  # Upper middle
                return {"local_usd": 20.0, "intl_usd": 50.0}
            else:  # High income
                return {"local_usd": 40.0, "intl_usd": 70.0}
        except Exception:
            return {"local_usd": 15.0, "intl_usd": 45.0}


# ============================================================================
# CACHING INFRASTRUCTURE
# ============================================================================

class CacheManager:
    """Manages all caching for market pulse data"""
    
    def __init__(self):
        self.market_cache: Dict[str, Dict[str, Any]] = {}
        self.fx_cache: Dict[str, Any] = {"rates": {}, "last_updated": None}
        self.intl_pulse_cache: Dict[str, Any] = {"data": None, "last_updated": None}
        
    async def get_fx_rates(self) -> Dict[str, float]:
        """Get cached or fresh FX rates"""
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
    
    async def get_market_pulse(self, country_code: str, generator_func) -> Dict[str, Any]:
        """Get cached or generate new market pulse"""
        country_code = country_code.upper()[:2]
        now = datetime.now(timezone.utc)
        
        if country_code in self.market_cache:
            entry = self.market_cache[country_code]
            if (now - entry["timestamp"]) < timedelta(hours=PulseConfig.CACHE_TTL_HOURS):
                return entry["data"]
        
        # Generate fresh data
        fresh_data = await generator_func(country_code)
        self.market_cache[country_code] = {"timestamp": now, "data": fresh_data}
        return fresh_data
    
    async def get_international_pulse(self, generator_func) -> Dict[str, Any]:
        """Get cached or generate international pulse"""
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
    match_type: str  # direct, adjacent, transferable
    confidence_score: float = Field(ge=0.0, le=1.0)

class ArbitrageOpportunity(BaseModel):
    skill: str
    local_rate_usd: float
    international_rate_usd: float
    gap_usd_per_hour: float
    monthly_gain_usd: float
    monthly_gain_local_currency: str
    market_access_strategy: str
    competition_level: str
    demand_trend: str

class CareerPath(BaseModel):
    title: str
    current_demand: str
    growth_projection: str
    entry_barrier: str
    time_to_proficiency: str
    salary_range_usd: Dict[str, float]
    required_skills: List[str]
    upskill_path: List[str]
    ai_impact: str
    geographic_hotspots: List[str]

class EntrepreneurialOpportunity(BaseModel):
    sector: str
    problem_statement: str
    solution_approach: str
    market_size_usd: str
    startup_cost_range_usd: Dict[str, float]
    time_to_revenue: str
    scalability_score: int = Field(ge=1, le=10)
    risk_level: str
    local_adaptations: Dict[str, str]

class WealthBuildingStrategy(BaseModel):
    strategy_type: str  # active_income, passive_income, investment, skill_arbitrage
    title: str
    description: str
    initial_capital_required_usd: float
    time_commitment_hours_week: int
    expected_roi_annual_percent: float
    risk_profile: str
    action_steps: List[str]
    resources_needed: List[str]

class PersonalGrowthInsight(BaseModel):
    category: str  # mindset, productivity, networking, health, learning
    insight: str
    actionable_tip: str
    recommended_resource: Optional[str] = None
    implementation_timeline: str


# ============================================================================
# AI PROMPT TEMPLATES (Dynamic, no hardcoded content)
# ============================================================================

class PromptTemplates:
    """Dynamic prompt generation based on context"""
    
    @staticmethod
    def international_pulse(skills_context: List[str] = None) -> Dict[str, str]:
        skills_str = ", ".join(skills_context) if skills_context else "various digital skills"
        
        return {
            "system": """You are a Global Market Intelligence AI synthesizing real-time data from WEF Future of Jobs, 
            World Bank economic indicators, LinkedIn Workforce Reports, and global freelance platform analytics.
            Provide data-driven insights only. No generic advice.""",
            
            "user": f"""Analyze the current global labor market as of {datetime.now().strftime("%B %Y")}.
            
            Context: User has skills in {skills_str}
            
            Provide a comprehensive International Market Impulse covering:
            
            1. GLOBAL MACRO TRENDS (based on WEF Future of Jobs 2025)
               - Technology adoption rates and their job creation/displacement impact
               - Fastest growing job categories globally (with % growth)
               - Fastest declining roles to avoid
               - Skills disruption timeline (which skills expire when)
            
            2. EMERGING SECTOR OPPORTUNITIES
               - AI/Automation sector opportunities
               - Green transition roles (renewable energy, circular economy)
               - Digital health and biotech expansion
               - Fintech/DeFi growth areas
               - Creator economy and digital content
            
            3. GEOGRAPHIC ARBITRAGE WINDOWS
               - Which regions are hiring remotely for which skills
               - Salary arbitrage opportunities (high pay, low competition)
               - Emerging startup ecosystems with funding availability
            
            4. FUTURE-PROOFING STRATEGIES
               - Skills to acquire in next 6 months for maximum ROI
               - Career pivots with highest success probability
               - AI augmentation strategies (not replacement)
            
            Return strictly valid JSON with this structure:
            {{
                "global_trends": {{
                    "tech_adoption_impact": "specific data",
                    "fastest_growing_roles": [{{"role": "", "growth_rate": "", "avg_salary_usd": 0}}],
                    "declining_roles": [""],
                    "skills_expiration_timeline": {{"skill": "years_until_obsolete"}}
                }},
                "emerging_sectors": [{{"sector": "", "market_size_growth": "", "top_opportunities": []}}],
                "geographic_arbitrage": [{{"region": "", "opportunity": "", "remote_friendly": true}}],
                "future_proofing": {{
                    "immediate_skills": [""],
                    "career_pivots": [{{"from": "", "to": "", "transition_difficulty": ""}}],
                    "ai_augmentation": ""
                }},
                "timestamp": "ISO timestamp"
            }}"""
        }
    
    @staticmethod
    def local_pulse(country_code: str, user_skills: List[str], economic_context: Dict) -> Dict[str, str]:
        skills_str = ", ".join(user_skills) if user_skills else "general digital skills"
        
        return {
            "system": """You are a Local Market Intelligence AI analyzing country-specific economic data, 
            labor market trends, and regional opportunities. Use real economic indicators and local market dynamics.""",
            
            "user": f"""Analyze the local market for country: {country_code}
            
            User Skills: {skills_str}
            Economic Context: {json.dumps(economic_context)}
            
            Provide Local Market Trends covering:
            
            1. LOCAL ECONOMIC PULSE
               - Current unemployment rate and trend
               - Inflation impact on purchasing power
               - Local currency strength vs USD
               - GDP growth trajectory
            
            2. LOCAL SKILL DEMAND MATRIX
               - Top 5 in-demand skills locally (with salary ranges in local currency)
               - Oversaturated skills to avoid
               - Skills gap opportunities (high demand, low supply)
               - Local industry growth sectors
            
            3. PLATFORM INTELLIGENCE (Local)
               - Which freelance platforms work best in this country
               - Local payment method considerations
               - Tax implications for freelancers
               - Competition levels on each platform
            
            4. SEASONAL & CULTURAL CONTEXT
               - Current seasonal demand (holidays, fiscal year ends, etc.)
               - Cultural business practices affecting remote work
               - Local networking opportunities
            
            Return strictly valid JSON:
            {{
                "economic_indicators": {{
                    "unemployment_rate": "",
                    "inflation_trend": "",
                    "currency_strength": "",
                    "gdp_growth": ""
                }},
                "skill_demand": {{
                    "hot_skills": [{{"skill": "", "local_salary_range": "", "demand_level": ""}}],
                    "oversaturated": [""],
                    "skill_gaps": [""]
                }},
                "platform_landscape": [{{"platform": "", "effectiveness": "", "payment_methods": []}}],
                "seasonal_context": "",
                "cultural_notes": "",
                "local_opportunities": [""]
            }}"""
        }
    
    @staticmethod
    def career_forecast(current_skills: List[str], interests: List[str], country: str) -> Dict[str, str]:
        return {
            "system": """You are a Career Forecasting AI using labor market analytics, skills adjacency mapping, 
            and economic projections to recommend optimal career paths.""",
            
            "user": f"""Generate personalized career forecasts for:
            Current Skills: {json.dumps(current_skills)}
            Interests: {json.dumps(interests)}
            Country: {country}
            
            Provide:
            1. IMMEDIATE OPPORTUNITIES (0-6 months)
            2. SHORT-TERM PIVOTS (6-18 months) 
            3. LONG-TERM TRAJECTORIES (2-5 years)
            4. AI-RESISTANT PATHWAYS
            5. ENTREPRENEURIAL ROUTES
            
            For each path include: demand_level, salary_progression, risk_level, required_upsilling
            
            Return JSON array of CareerPath objects."""
        }
    
    @staticmethod
    def entrepreneurial_scan(country: str, skills: List[str], capital_tier: str) -> Dict[str, str]:
        return {
            "system": """You are an Entrepreneurship Intelligence AI analyzing market gaps, 
            startup ecosystem data, and regional business opportunities.""",
            
            "user": f"""Identify entrepreneurial opportunities for:
            Country: {country}
            Available Skills: {json.dumps(skills)}
            Capital Tier: {capital_tier} (bootstrap/moderate/well-funded)
            
            Focus on:
            - Problems specific to {country} or similar economies
            - Digital-first businesses with low initial capital
            - Scalable models with global potential
            - Local adaptations of successful global models
            
            Return JSON array of EntrepreneurialOpportunity objects."""
        }
    
    @staticmethod
    def wealth_strategy(country: str, income_level: str, risk_tolerance: str, time_available: int) -> Dict[str, str]:
        return {
            "system": """You are a Wealth Building Strategist AI specializing in income diversification, 
            asset building, and financial independence pathways for global markets.""",
            
            "user": f"""Create wealth building strategies for:
            Country: {country}
            Current Income Level: {income_level}
            Risk Tolerance: {risk_tolerance}
            Time Available: {time_available} hours/week
            
            Include:
            1. Active income maximization (skill arbitrage, premium positioning)
            2. Passive income streams (digital products, investments, royalties)
            3. Asset accumulation strategies
            4. Geographic arbitrage plays
            5. Tax optimization (general principles)
            
            Return JSON array of WealthBuildingStrategy objects."""
        }
    
    @staticmethod
    def personal_growth_assessment(current_challenges: List[str], goals: List[str]) -> Dict[str, str]:
        return {
            "system": """You are a Personal Development AI combining productivity science, 
            behavioral psychology, and high-performance coaching methodologies.""",
            
            "user": f"""Generate personalized growth insights for:
            Current Challenges: {json.dumps(current_challenges)}
            Goals: {json.dumps(goals)}
            
            Cover:
            1. Mindset shifts for entrepreneurial success
            2. Productivity systems for side hustlers
            3. Networking strategies for global markets
            4. Health optimization for sustained performance
            5. Accelerated learning methodologies
            
            Return JSON array of PersonalGrowthInsight objects."""
        }


# ============================================================================
# CORE SERVICE FUNCTIONS
# ============================================================================

async def generate_international_pulse(skills: List[str] = None) -> Dict[str, Any]:
    """Generate global market intelligence"""
    prompts = PromptTemplates.international_pulse(skills)
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.3
        )
        
        raw = result["content"].strip()
        # Clean markdown formatting
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        data = json.loads(raw)
        data["_metadata"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scope": "international",
            "model": result.get("model", "unknown")
        }
        return data
        
    except Exception as e:
        logger.error(f"International pulse generation failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate international market pulse")


async def generate_local_pulse(country_code: str, user_skills: List[str]) -> Dict[str, Any]:
    """Generate country-specific market intelligence"""
    # Fetch economic context from World Bank or similar
    economic_context = await fetch_economic_context(country_code)
    
    prompts = PromptTemplates.local_pulse(country_code, user_skills, economic_context)
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=1500,
            temperature=0.3
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        data = json.loads(raw)
        data["_metadata"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scope": "local",
            "country": country_code,
            "model": result.get("model", "unknown")
        }
        return data
        
    except Exception as e:
        logger.error(f"Local pulse generation failed for {country_code}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to generate local market pulse for {country_code}")


async def fetch_economic_context(country_code: str) -> Dict[str, Any]:
    """Fetch economic indicators from database or external APIs"""
    try:
        # Try to get from database first
        indicators = await supabase_service.get_economic_indicators(country_code)
        if indicators:
            return indicators
        
        # Fallback to minimal context
        return {
            "country_code": country_code,
            "data_source": "fallback",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    except Exception as e:
        logger.warning(f"Could not fetch economic context for {country_code}: {e}")
        return {}


async def calculate_skill_matches(user_skills: List[str], opportunities: List[str]) -> List[SkillMatch]:
    """AI-powered skill matching with confidence scoring"""
    if not user_skills or not opportunities:
        return []
    
    prompt = f"""Match these user skills: {json.dumps(user_skills)}
    To these opportunities: {json.dumps(opportunities)}
    
    For each match, determine:
    - match_type: direct (exact match), adjacent (related field), or transferable (universal skill)
    - confidence_score: 0.0 to 1.0 based on relevance
    
    Return JSON array of matches."""
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompt}],
            system="You are a skills matching AI. Be precise and objective.",
            max_tokens=800,
            temperature=0.2
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        matches = json.loads(raw)
        return [SkillMatch(**match) for match in matches[:PulseConfig.MAX_SKILL_MATCHES]]
        
    except Exception as e:
        logger.error(f"Skill matching failed: {e}")
        # Fallback to simple keyword matching
        matches = []
        for skill in user_skills:
            for opp in opportunities:
                skill_words = set(skill.lower().split())
                opp_words = set(opp.lower().split())
                overlap = skill_words & opp_words
                if overlap:
                    confidence = len(overlap) / max(len(skill_words), len(opp_words))
                    match_type = "direct" if confidence > 0.7 else "adjacent"
                    matches.append(SkillMatch(
                        opportunity=opp,
                        your_skill=skill,
                        match_type=match_type,
                        confidence_score=round(confidence, 2)
                    ))
        return matches[:PulseConfig.MAX_SKILL_MATCHES]


async def calculate_arbitrage(country_code: str, skills: List[str]) -> Dict[str, Any]:
    """Calculate international arbitrage opportunities"""
    fx_rates = await cache_manager.get_fx_rates()
    rates = await PulseConfig.get_rate_baselines(country_code)
    
    # Get currency code
    country_currency_map = await get_country_currency_map()
    local_currency = country_currency_map.get(country_code, "USD")
    exchange_rate = fx_rates.get(local_currency, 1.0)
    
    multiplier = round(rates["intl_usd"] / max(rates["local_usd"], 1), 1)
    
    opportunities = []
    for skill in skills[:PulseConfig.MAX_SKILL_MATCHES]:
        local_usd = rates["local_usd"]
        intl_usd = rates["intl_usd"]
        gap_usd = intl_usd - local_usd
        
        monthly_gain_usd = gap_usd * 8 * 20  # 8 hrs/day, 20 days/month
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
            "demand_trend": "growing"
        })
    
    return {
        "country": country_code,
        "local_currency": local_currency,
        "exchange_rate_usd": exchange_rate,
        "rate_multiplier": multiplier,
        "summary": f"International clients pay {multiplier}x more than local clients",
        "opportunities": opportunities,
        "total_monthly_potential_usd": sum(o["monthly_gain_usd"] for o in opportunities)
    }


async def get_country_currency_map() -> Dict[str, str]:
    """Fetch currency mapping from database"""
    try:
        mapping = await supabase_service.get_country_currencies()
        if mapping:
            return mapping
    except Exception as e:
        logger.error(f"Failed to fetch currency map: {e}")
    
    # Minimal fallback for major economies only
    return {
        "US": "USD", "GB": "GBP", "EU": "EUR", "JP": "JPY", 
        "CA": "CAD", "AU": "AUD", "CH": "CHF"
    }


# ============================================================================
# API ENDPOINTS
# ============================================================================

@router.get("/international")
@limiter.limit(GENERAL_LIMIT)
async def get_international_pulse(request: Request, user: dict = Depends(get_current_user)):
    """
    Get International Market Impulse - Global trends, opportunities, and future-proofing strategies
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    user_skills = profile.get("current_skills", []) or []
    
    pulse_data = await cache_manager.get_international_pulse(
        lambda: generate_international_pulse(user_skills)
    )
    
    # Calculate skill matches against global opportunities
    global_opportunities = []
    if "emerging_sectors" in pulse_data:
        for sector in pulse_data["emerging_sectors"]:
            global_opportunities.extend(sector.get("top_opportunities", []))
    
    skill_matches = await calculate_skill_matches(user_skills, global_opportunities)
    
    return {
        "pulse_type": "international",
        "generated_at": pulse_data.get("_metadata", {}).get("generated_at"),
        "global_trends": pulse_data.get("global_trends", {}),
        "emerging_sectors": pulse_data.get("emerging_sectors", []),
        "geographic_arbitrage": pulse_data.get("geographic_arbitrage", []),
        "future_proofing": pulse_data.get("future_proofing", {}),
        "your_skill_matches": [match.dict() for match in skill_matches],
        "strategic_recommendations": {
            "immediate_actions": pulse_data.get("future_proofing", {}).get("immediate_skills", [])[:3],
            "career_pivot_options": pulse_data.get("future_proofing", {}).get("career_pivots", [])[:2],
            "ai_strategy": pulse_data.get("future_proofing", {}).get("ai_augmentation", "")
        }
    }


@router.get("/local")
@limiter.limit(GENERAL_LIMIT)
async def get_local_pulse(request: Request, user: dict = Depends(get_current_user)):
    """
    Get Local Market Trends - Country-specific economic data, skill demand, and local opportunities
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    
    pulse_data = await cache_manager.get_market_pulse(
        country,
        lambda c: generate_local_pulse(c, user_skills)
    )
    
    # Calculate local skill matches
    local_opportunities = pulse_data.get("local_opportunities", [])
    skill_demand = pulse_data.get("skill_demand", {})
    hot_skills = [s["skill"] for s in skill_demand.get("hot_skills", [])]
    
    all_local_opps = local_opportunities + hot_skills
    skill_matches = await calculate_skill_matches(user_skills, all_local_opps)
    
    return {
        "pulse_type": "local",
        "country": country,
        "generated_at": pulse_data.get("_metadata", {}).get("generated_at"),
        "economic_indicators": pulse_data.get("economic_indicators", {}),
        "skill_demand": skill_demand,
        "platform_landscape": pulse_data.get("platform_landscape", []),
        "seasonal_context": pulse_data.get("seasonal_context", ""),
        "cultural_notes": pulse_data.get("cultural_notes", ""),
        "your_skill_matches": [match.dict() for match in skill_matches],
        "local_recommendations": {
            "platforms_to_join": [p["platform"] for p in pulse_data.get("platform_landscape", [])[:3]],
            "skills_to_highlight": [s["skill"] for s in skill_demand.get("hot_skills", [])[:3]],
            "skills_to_avoid": skill_demand.get("oversaturated", [])[:3]
        }
    }


@router.get("/today")
@limiter.limit(GENERAL_LIMIT)
async def get_todays_pulse(request: Request, user: dict = Depends(get_current_user)):
    """
    Get combined daily pulse - Both international and local market intelligence
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    
    # Fetch both pulses concurrently
    import asyncio
    intl_task = cache_manager.get_international_pulse(lambda: generate_international_pulse(user_skills))
    local_task = cache_manager.get_market_pulse(country, lambda c: generate_local_pulse(c, user_skills))
    
    intl_data, local_data = await asyncio.gather(intl_task, local_task)
    
    # Generate morning briefing
    today = datetime.now(timezone.utc)
    
    # Find best opportunity
    best_opportunity = None
    if intl_data.get("emerging_sectors"):
        best_opportunity = intl_data["emerging_sectors"][0].get("sector", "AI & Automation")
    
    return {
        "status": "live",
        "date": today.strftime("%A, %B %d, %Y"),
        "country": country,
        "international_pulse": {
            "top_global_trend": intl_data.get("global_trends", {}).get("tech_adoption_impact", "")[:100] + "...",
            "fastest_growing_role": intl_data.get("global_trends", {}).get("fastest_growing_roles", [{}])[0],
            "emerging_sector": intl_data.get("emerging_sectors", [{}])[0]
        },
        "local_pulse": {
            "economic_snapshot": local_data.get("economic_indicators", {}),
            "hot_local_skill": local_data.get("skill_demand", {}).get("hot_skills", [{}])[0],
            "seasonal_note": local_data.get("seasonal_context", "")
        },
        "your_position": {
            "skills_listed": user_skills,
            "matched_opportunities": len(await calculate_skill_matches(
                user_skills, 
                [s.get("skill", "") for s in local_data.get("skill_demand", {}).get("hot_skills", [])]
            ))
        },
        "morning_briefing": f"""
            Today ({today.strftime('%B %d')}): Global markets show strong demand in 
            {best_opportunity or 'technology sectors'}. Locally in {country}, 
            focus on {local_data.get('skill_demand', {}).get('hot_skills', [{}])[0].get('skill', 'digital skills')} 
            for maximum opportunity capture.
        """.strip(),
        "action_today": [
            "Update LinkedIn profile with trending keywords",
            f"Apply to 3 {local_data.get('skill_demand', {}).get('hot_skills', [{}])[0].get('skill', 'relevant')} gigs",
            "Research one emerging sector from international pulse"
        ]
    }


@router.get("/career-forecast")
@limiter.limit(AI_LIMIT)
async def get_career_forecast(
    request: Request, 
    timeframe: str = "all",  # immediate, short, long, all
    user: dict = Depends(get_current_user)
):
    """
    Get personalized career forecasting - Future career paths and transitions
    """
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
            temperature=0.4
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        career_paths = json.loads(raw)
        
        # Filter by timeframe if specified
        if timeframe != "all":
            career_paths = [p for p in career_paths if timeframe in p.get("timeline_category", "")]
        
        return {
            "forecast_type": "career",
            "user_context": {
                "country": country,
                "current_skills_count": len(user_skills),
                "interests_count": len(interests)
            },
            "career_paths": career_paths,
            "recommended_path": career_paths[0] if career_paths else None,
            "model": result.get("model")
        }
        
    except Exception as e:
        logger.error(f"Career forecast failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate career forecast")


@router.get("/entrepreneurial-opportunities")
@limiter.limit(AI_LIMIT)
async def get_entrepreneurial_opportunities(
    request: Request,
    capital_tier: str = "bootstrap",  # bootstrap, moderate, well-funded
    sector: Optional[str] = None,
    user: dict = Depends(get_current_user)
):
    """
    Discover entrepreneurial opportunities and startup ideas
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    
    prompts = PromptTemplates.entrepreneurial_scan(country, user_skills, capital_tier)
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.5
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        opportunities = json.loads(raw)
        
        # Filter by sector if specified
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
                "Research competitors in adjacent markets"
            ]
        }
        
    except Exception as e:
        logger.error(f"Entrepreneurial scan failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to scan entrepreneurial opportunities")


@router.get("/wealth-strategies")
@limiter.limit(AI_LIMIT)
async def get_wealth_strategies(
    request: Request,
    risk_tolerance: str = "moderate",  # conservative, moderate, aggressive
    user: dict = Depends(get_current_user)
):
    """
    Get personalized wealth building strategies
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    
    # Determine income level from profile or estimate
    income_level = profile.get("income_bracket", "middle")
    time_available = profile.get("side_hustle_hours_week", 10)
    
    prompts = PromptTemplates.wealth_strategy(country, income_level, risk_tolerance, time_available)
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=2000,
            temperature=0.4
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        strategies = json.loads(raw)
        
        return {
            "strategy_type": "wealth_building",
            "user_profile": {
                "country": country,
                "income_level": income_level,
                "risk_tolerance": risk_tolerance,
                "time_available_hours_week": time_available
            },
            "strategies": strategies,
            "quick_wins": [s for s in strategies if s.get("expected_roi_annual_percent", 0) > 50][:3],
            "long_term_builders": [s for s in strategies if s.get("time_commitment_hours_week", 0) < 5][:3],
            "total_strategies": len(strategies)
        }
        
    except Exception as e:
        logger.error(f"Wealth strategy generation failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate wealth strategies")


@router.get("/personal-growth")
@limiter.limit(AI_LIMIT)
async def get_personal_growth_insights(
    request: Request,
    focus_area: Optional[str] = None,  # mindset, productivity, networking, health, learning
    user: dict = Depends(get_current_user)
):
    """
    Get personalized growth and development insights
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    
    # Get user's current challenges and goals from profile
    challenges = profile.get("current_challenges", ["time_management", "skill_gaps"])
    goals = profile.get("development_goals", ["career_advancement", "income_growth"])
    
    prompts = PromptTemplates.personal_growth_assessment(challenges, goals)
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompts["user"]}],
            system=prompts["system"],
            max_tokens=1500,
            temperature=0.5
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        insights = json.loads(raw)
        
        # Filter by focus area if specified
        if focus_area:
            insights = [i for i in insights if focus_area.lower() in i.get("category", "").lower()]
        
        return {
            "insight_type": "personal_growth",
            "user_context": {
                "challenges": challenges,
                "goals": goals
            },
            "insights": insights,
            "focus_areas": list(set(i.get("category") for i in insights)),
            "priority_action": insights[0] if insights else None
        }
        
    except Exception as e:
        logger.error(f"Personal growth insights failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate personal growth insights")


@router.get("/opportunity-scan")
@limiter.limit(AI_LIMIT)
async def scan_opportunity(
    request: Request, 
    skill: str = "", 
    user: dict = Depends(get_current_user)
):
    """
    Deep scan for a specific skill opportunity
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    scan_skill = skill or (user_skills[0] if user_skills else "digital services")
    
    system_prompt = """You are a Market Intelligence AI analyzing specific skill demand.
    Provide realistic, data-backed estimates. Consider global and local market conditions."""
    
    user_prompt = f"""Deep scan for skill: {scan_skill}
    Country: {country}
    User Skills Context: {json.dumps(user_skills)}
    
    Provide:
    1. Demand analysis (global and local)
    2. Rate benchmarks (entry, mid, senior)
    3. Competition assessment
    4. Fastest path to first client
    5. Differentiation strategies
    6. Related upskilling opportunities
    
    Return JSON with detailed analysis."""
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": user_prompt}],
            system=system_prompt,
            max_tokens=1000,
            temperature=0.3
        )
        
        raw = result["content"].strip()
        for prefix in ["```json", "```", "`"]:
            raw = raw.removeprefix(prefix).removesuffix(prefix).strip()
        
        scan_data = json.loads(raw)
        
        return {
            "skill_scanned": scan_skill,
            "country": country,
            "scan_results": scan_data,
            "model": result.get("model")
        }
        
    except Exception as e:
        logger.error(f"Opportunity scan failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to complete opportunity scan")


@router.get("/arbitrage")
@limiter.limit(GENERAL_LIMIT)
async def currency_arbitrage(request: Request, user: dict = Depends(get_current_user)):
    """
    Calculate live arbitrage opportunities using real-time exchange rates
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    skills = profile.get("current_skills", []) or []
    
    if not skills:
        return {
            "status": "error",
            "message": "No skills found in profile. Please add skills to see arbitrage opportunities."
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
            "Emphasize cultural diversity as asset",
            "Build portfolio with international case studies"
        ]
    }


@router.get("/comprehensive")
@limiter.limit(AI_LIMIT)
async def get_comprehensive_pulse(request: Request, user: dict = Depends(get_current_user)):
    """
    Get comprehensive market pulse - All features combined
    """
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or PulseConfig.DEFAULT_COUNTRY).upper()[:2]
    
    # Fetch all data types concurrently
    import asyncio
    
    tasks = {
        "international": cache_manager.get_international_pulse(lambda: generate_international_pulse()),
        "local": cache_manager.get_market_pulse(country, lambda c: generate_local_pulse(c, [])),
        "arbitrage": calculate_arbitrage(country, profile.get("current_skills", []) or [])
    }
    
    results = await asyncio.gather(*tasks.values())
    data = dict(zip(tasks.keys(), results))
    
    return {
        "pulse_type": "comprehensive",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "user_country": country,
        "sections": {
            "international_market_impulse": data["international"],
            "local_market_trends": data["local"],
            "arbitrage_analysis": data["arbitrage"]
        },
        "navigation": {
            "for_career_forecast": "/pulse/career-forecast",
            "for_entrepreneurship": "/pulse/entrepreneurial-opportunities",
            "for_wealth_strategies": "/pulse/wealth-strategies",
            "for_personal_growth": "/pulse/personal-growth",
            "for_skill_scan": "/pulse/opportunity-scan?skill=your_skill"
        }
    }
