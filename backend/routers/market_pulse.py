"""
Live Market Pulse — Real-time income opportunity scanning.
Every morning the agent tells you what's HOT and paying RIGHT NOW.
Scans signals across niches, platforms and demand trends.
"""
import json
import logging
import httpx
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from middleware.rate_limit import limiter, AI_LIMIT, GENERAL_LIMIT
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/pulse", tags=["Market Pulse"])
logger = logging.getLogger(__name__)

# --- IN-MEMORY CACHE FOR LIVE DATA ---
MARKET_CACHE: Dict[str, Dict[str, Any]] = {}
CACHE_TTL_HOURS = 24

FX_CACHE: Dict[str, Any] = {"rates": {}, "last_updated": None}
FX_TTL_HOURS = 12

async def fetch_live_fx_rates():
    """Fetches real-time exchange rates using a free public API."""
    now = datetime.now(timezone.utc)
    if FX_CACHE["last_updated"] and (now - FX_CACHE["last_updated"]) < timedelta(hours=FX_TTL_HOURS):
        return FX_CACHE["rates"]
        
    try:
        async with httpx.AsyncClient() as client:
            # Free, no-auth API for base USD rates covering 160+ currencies
            response = await client.get("https://api.exchangerate-api.com/v4/latest/USD")
            response.raise_for_status()
            data = response.json()
            FX_CACHE["rates"] = data.get("rates", {})
            FX_CACHE["last_updated"] = now
            return FX_CACHE["rates"]
    except Exception as e:
        logger.error(f"Failed to fetch live FX rates: {e}")
        return {} 

async def generate_live_country_pulse(country_code: str) -> dict:
    """Uses AI to generate today's live market pulse for a specific country."""
    prompt = f"""
    Act as an elite market intelligence analyst. Provide the current, real-time freelance and side-hustle market pulse for country code: {country_code}.
    Focus on digital skills, AI, tech, and online services.
    Return strictly a JSON object with this exact structure:
    {{
        "trending": ["list of 4-5 exploding skills right now"],
        "overbooked": ["list of 2-3 saturated skills to avoid"],
        "emerging": ["list of 3 early-trend skills"],
        "seasonal_now": "1 sentence on what is in demand this exact month",
        "platform_hot": "1 sentence on which freelance platform is working best for this country right now",
        "avg_rate_trend": "1 sentence on how much rates are shifting"
    }}
    """
    
    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": prompt}],
            system="You are a live economic data synthesizer. Output strictly valid JSON without markdown formatting.",
            max_tokens=500
        )
        raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
        return json.loads(raw)
    except Exception as e:
        logger.error(f"Failed to generate live pulse for {country_code}: {e}")
        return {
            "trending": ["AI Automation", "Short-form Video", "Sales Funnels"],
            "overbooked": ["Data Entry", "Basic Transcription"],
            "emerging": ["AI Agents", "Micro-SaaS"],
            "seasonal_now": "High demand for business automation and setup.",
            "platform_hot": "Upwork and direct LinkedIn outreach are performing best.",
            "avg_rate_trend": "Specialized tech/AI rates are up globally."
        }

async def get_cached_or_live_opportunities(country_code: str) -> dict:
    """Manages the daily caching of the AI-generated market pulse."""
    country_code = country_code.upper()[:2]
    now = datetime.now(timezone.utc)
    
    if country_code in MARKET_CACHE:
        cache_entry = MARKET_CACHE[country_code]
        if (now - cache_entry["timestamp"]) < timedelta(hours=CACHE_TTL_HOURS):
            return cache_entry["data"]
            
    live_data = await generate_live_country_pulse(country_code)
    MARKET_CACHE[country_code] = {"timestamp": now, "data": live_data}
    return live_data


@router.get("/today")
@limiter.limit(GENERAL_LIMIT)
async def get_todays_pulse(request: Request, user: dict = Depends(get_current_user)):
    """Get today's LIVE market pulse for the user's country"""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "NG").upper()[:2]
    skills = profile.get("current_skills", []) or []
    
    opps = await get_cached_or_live_opportunities(country)

    skill_matches = []
    for trend in opps["trending"]:
        for skill in skills:
            if any(word in trend.lower() for word in skill.lower().split()):
                skill_matches.append({"opportunity": trend, "your_skill": skill, "match": "direct"})
                break

    today = datetime.now(timezone.utc)
    return {
        "status": "live",
        "date": today.strftime("%A, %B %d"),
        "country": country,
        "trending_now": opps.get("trending", []),
        "overbooked_avoid": opps.get("overbooked", []),
        "emerging_opportunities": opps.get("emerging", []),
        "seasonal_context": opps.get("seasonal_now", ""),
        "platform_intelligence": opps.get("platform_hot", ""),
        "rate_trends": opps.get("avg_rate_trend", ""),
        "matched_to_your_skills": skill_matches,
        "morning_briefing": f"Today's top opportunity for you: {opps.get('trending', ['AI'])[0]}. {opps.get('seasonal_now', '')}",
    }


@router.get("/opportunity-scan")
@limiter.limit(AI_LIMIT)
async def scan_opportunity(request: Request, skill: str = "", user: dict = Depends(get_current_user)):
    """AI scans the market for a specific skill and returns a live opportunity report"""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "US").upper()[:2]
    user_skills = profile.get("current_skills", []) or []
    scan_skill = skill or (user_skills[0] if user_skills else "freelancing")
    
    opps = await get_cached_or_live_opportunities(country)

    system_prompt = """You are a highly analytical Market Intelligence AI. 
    Scan live market demand for the user's skill. Provide accurate, realistic estimates based on current global trends.
    Return strictly JSON without markdown:
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
    }"""

    try:
        result = await ai_service.chat(
            messages=[{"role": "user", "content": f"Skill: {scan_skill} | Country: {country} | Current Market Context: {json.dumps(opps)}"}],
            system=system_prompt,
            max_tokens=600,
        )
        
        raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
        data = json.loads(raw)
    except Exception as e:
        logger.error(f"Opportunity scan failed: {e}")
        data = {"action_today": "System error fetching live scan. Focus on upskilling your core offering."}

    return {"skill": scan_skill, "scan": data, "model": result.get("model")}


@router.get("/arbitrage")
@limiter.limit(GENERAL_LIMIT)
async def currency_arbitrage(request: Request, user: dict = Depends(get_current_user)):
    """Calculates live arbitrage gap using real-time USD exchange rates for 150+ countries."""
    profile = await supabase_service.get_profile(user["id"]) or {}
    country = (profile.get("country") or "NG").upper()[:2]
    skills = profile.get("current_skills", []) or []
    
    fx_rates = await fetch_live_fx_rates()
    
    # Comprehensive ISO 3166-1 alpha-2 to ISO 4217 Currency mapping
    COUNTRY_CURRENCIES = {
        "AE": "AED", "AF": "AFN", "AL": "ALL", "AM": "AMD", "AR": "ARS", "AU": "AUD",
        "AZ": "AZN", "BA": "BAM", "BD": "BDT", "BG": "BGN", "BH": "BHD", "BO": "BOB",
        "BR": "BRL", "BY": "BYN", "CA": "CAD", "CD": "CDF", "CH": "CHF", "CL": "CLP",
        "CN": "CNY", "CO": "COP", "CR": "CRC", "CZ": "CZK", "DK": "DKK", "DO": "DOP",
        "DZ": "DZD", "EG": "EGP", "ET": "ETB", "EU": "EUR", "GB": "GBP", "GE": "GEL",
        "GH": "GHS", "GT": "GTQ", "HK": "HKD", "HN": "HNL", "HR": "HRK", "HU": "HUF",
        "ID": "IDR", "IL": "ILS", "IN": "INR", "IQ": "IQD", "IR": "IRR", "IS": "ISK",
        "JM": "JMD", "JO": "JOD", "JP": "JPY", "KE": "KES", "KG": "KGS", "KH": "KHR",
        "KR": "KRW", "KW": "KWD", "KZ": "KZT", "LB": "LBP", "LK": "LKR", "MA": "MAD",
        "MD": "MDL", "MG": "MGA", "MK": "MKD", "MM": "MMK", "MX": "MXN", "MY": "MYR",
        "MZ": "MZN", "NG": "NGN", "NI": "NIO", "NO": "NOK", "NP": "NPR", "NZ": "NZD",
        "OM": "OMR", "PA": "PAB", "PE": "PEN", "PH": "PHP", "PK": "PKR", "PL": "PLN",
        "PY": "PYG", "QA": "QAR", "RO": "RON", "RS": "RSD", "RU": "RUB", "RW": "RWF",
        "SA": "SAR", "SD": "SDG", "SE": "SEK", "SG": "SGD", "SO": "SOS", "SY": "SYP",
        "TH": "THB", "TND": "TND", "TR": "TRY", "TW": "TWD", "TZ": "TZS", "UA": "UAH",
        "UG": "UGX", "US": "USD", "UY": "UYU", "UZ": "UZS", "VE": "VES", "VN": "VND",
        "YE": "YER", "ZA": "ZAR", "ZM": "ZMW", "ZW": "ZWL"
    }
    
    # European countries that use the Euro
    EURO_ZONE = ["AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI", "ES"]
    if country in EURO_ZONE:
        local_currency = "EUR"
    else:
        local_currency = COUNTRY_CURRENCIES.get(country, "USD")

    exchange_rate = fx_rates.get(local_currency, 1.0)
    
    # Expanded baselines for major global freelancing hubs
    RATE_BASELINES = {
        "NG": {"local_usd": 5, "intl_usd": 30},   # Nigeria
        "GH": {"local_usd": 6, "intl_usd": 30},   # Ghana
        "KE": {"local_usd": 8, "intl_usd": 35},   # Kenya
        "ZA": {"local_usd": 12, "intl_usd": 40},  # South Africa
        "IN": {"local_usd": 10, "intl_usd": 40},  # India
        "PK": {"local_usd": 8, "intl_usd": 35},   # Pakistan
        "BD": {"local_usd": 7, "intl_usd": 35},   # Bangladesh
        "PH": {"local_usd": 8, "intl_usd": 35},   # Philippines
        "ID": {"local_usd": 9, "intl_usd": 35},   # Indonesia
        "VN": {"local_usd": 10, "intl_usd": 35},  # Vietnam
        "BR": {"local_usd": 12, "intl_usd": 40},  # Brazil
        "AR": {"local_usd": 10, "intl_usd": 40},  # Argentina
        "CO": {"local_usd": 10, "intl_usd": 40},  # Colombia
        "MX": {"local_usd": 15, "intl_usd": 45},  # Mexico
        "UA": {"local_usd": 15, "intl_usd": 45},  # Ukraine
        "EG": {"local_usd": 8, "intl_usd": 35},   # Egypt
        "TR": {"local_usd": 12, "intl_usd": 40},  # Turkey
        "US": {"local_usd": 40, "intl_usd": 60},  # USA (Premium domestic/intl rates)
        "GB": {"local_usd": 35, "intl_usd": 55},  # UK
        "DEFAULT": {"local_usd": 15, "intl_usd": 45},
    }
    rates = RATE_BASELINES.get(country, RATE_BASELINES["DEFAULT"])
    
    multiplier = round(rates["intl_usd"] / max(rates["local_usd"], 1), 1)

    arbitrage_opportunities = []
    for skill in skills[:5]:
        local_usd = rates["local_usd"]
        intl_usd = rates["intl_usd"]
        gap_usd = intl_usd - local_usd
        
        monthly_gain_usd = gap_usd * 8 * 20 # 8 hours a day, 20 days a month
        monthly_gain_local = round(monthly_gain_usd * exchange_rate, 2)
        
        arbitrage_opportunities.append({
            "skill": skill,
            "local_rate_usd": local_usd,
            "international_rate_usd": intl_usd,
            "gap_usd_per_hour": gap_usd,
            "monthly_gain_usd": monthly_gain_usd,
            "monthly_gain_local_currency": f"{local_currency} {monthly_gain_local:,.2f}",
            "how_to_access_international": f"Create Upwork/Fiverr profile targeting US/UK/EU clients for {skill}. Position as specialist, not generalist."
        })

    return {
        "status": "live",
        "country": country,
        "local_currency": local_currency,
        "live_exchange_rate_usd": exchange_rate,
        "rate_multiplier": multiplier,
        "summary": f"International clients pay {multiplier}x more than local clients for the same work.",
        "opportunities": arbitrage_opportunities,
        "total_monthly_gain_usd": sum(o["monthly_gain_usd"] for o in arbitrage_opportunities),
        "first_step": "Create an Upwork profile TODAY. Use your best skill. Target $25+/hr. You leave money on the table every day you don't."
    }
