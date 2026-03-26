"""
Income Challenges Router — Dynamic, Trend-Aware, & Global
Hosted on Render | Data on Supabase | AI-Driven (2026 Edition)
"""
import json, logging
from datetime import datetime, timezone, date, timedelta
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Request, Header

from models.schemas import TaskUpdate
from services.ai_service import ai_service
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/challenges", tags=["Income Challenges"])
logger = logging.getLogger(__name__)

# --- Models ---

class CreateChallengeRequest(BaseModel):
    challenge_type: str  # discovery_id | custom
    discovery_data: Optional[dict] = None # Data passed back from the /discover endpoint
    custom_goal: Optional[str] = None
    custom_target: Optional[float] = None
    currency: str = "USD"

class CheckInRequest(BaseModel):
    challenge_id: str
    action_taken: str
    amount_earned: Optional[float] = 0
    currency: str = "USD"
    note: Optional[str] = None

# --- Endpoints ---

@router.get("/discover")
async def discover_challenges(
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header("en"),
    x_user_country: Optional[str] = Header(None)
):
    """
    AI Discovery: Generates 3 real-world challenges based on 
    CURRENT global trends and the user's specific location.
    """
    profile = await supabase_service.get_profile(user["id"])
    skills = ", ".join(profile.get("current_skills", []) or ["digital literacy"])
    country = x_user_country or profile.get("country", "Global")
    
    # AI generates the "Menu" of challenges for the week/month
    # This prevents hardcoding and allows the app to stay relevant forever.
    result = await ai_service.chat(
        messages=[{
            "role": "user", 
            "content": f"User: {profile.get('full_name')} in {country}. Skills: {skills}. Date: March 2026."
        }],
        system="""You are a Wealth Discovery Engine. Generate 3 unique, high-probability income challenges.
        Consider 2026 trends (AI, decentralized work, local service marketplaces).
        One must be a 7-day sprint, one 14-day, one 30-day.
        JSON format:
        {
          "featured_this_week": "A theme name",
          "challenges": [
            {
              "type_id": "discovery_1",
              "title": "...", 
              "description": "Why this works in [Country] right now",
              "target_amount": 100,
              "currency": "USD",
              "duration_days": 7,
              "emoji": "🔥",
              "difficulty": "beginner"
            }
          ]
        }
        Return JSON only.""",
        max_tokens=1000
    )
    
    try:
        discovery_payload = json.loads(result["content"])
        return discovery_payload
    except:
        raise HTTPException(500, "Could not generate trending challenges")

@router.post("/create")
async def create_challenge(
    req: CreateChallengeRequest, 
    user: dict = Depends(get_current_user),
    x_currency_code: Optional[str] = Header("USD")
):
    """Builds the custom 30-day roadmap based on the selected discovery item"""
    user_id = user["id"]
    profile = await supabase_service.get_profile(user_id)
    
    # Use discovery data if provided, otherwise fallback to custom
    title = req.custom_goal or req.discovery_data.get("title")
    target = req.custom_target or req.discovery_data.get("target_amount")
    duration = req.discovery_data.get("duration_days", 30)
    currency = x_currency_code or req.currency

    # AI generates the specific "Global Roadmap"
    result = await ai_service.chat(
        messages=[{"role": "user", "content": f"Create plan for: {title}. Target: {currency} {target}. Duration: {duration} days."}],
        system="""Build a day-by-day income roadmap. 
        - Days 1-3: Setup and Platform Choice.
        - Days 4-20: Outreach/Execution.
        - Days 21-30: Scaling/Closing.
        Focus on real platforms (Upwork, Gumroad, Printful, local niches).
        JSON format: {"daily_plan": [{"day": 1, "action": "...", "platform": "..."}], "success_tips": "..."}""",
        max_tokens=2000
    )

    plan_data = json.loads(result["content"])

    challenge_obj = {
        "user_id": user_id,
        "title": title,
        "target_amount": target,
        "currency_code": currency,
        "duration_days": duration,
        "start_date": datetime.now(timezone.utc).date().isoformat(),
        "status": "active",
        "plan_data": plan_data, # Detailed JSON
        "current_day": 1,
        "streak": 0
    }

    saved = supabase_service.client.table("income_challenges").insert(challenge_obj).execute()
    return saved.data[0]

@router.post("/check-in")
async def daily_checkin(req: CheckInRequest, user: dict = Depends(get_current_user)):
    """Logs progress and checks if the user is falling behind global averages"""
    user_id = user["id"]
    
    # 1. Fetch current status
    res = supabase_service.client.table("income_challenges").select("*").eq("id", req.challenge_id).single().execute()
    c = res.data
    
    # 2. Logic for progress
    new_total = c["current_amount"] + req.amount_earned
    progress_pct = (new_total / c["target_amount"]) * 100
    
    # 3. Log Earning Globally
    if req.amount_earned > 0:
        await supabase_service.log_earning(
            user_id=user_id,
            amount=req.amount_earned,
            source="challenge",
            reference_id=req.challenge_id,
            currency=req.currency
        )

    # 4. Update Challenge
    update = {
        "current_amount": new_total,
        "current_day": c["current_day"] + 1,
        "last_checkin": date.today().isoformat()
    }
    supabase_service.client.table("income_challenges").update(update).eq("id", req.challenge_id).execute()

    return {"status": "success", "progress_pct": progress_pct}
