"""
RiseUp Autonomous Agent — v5 (APEX Global)
═══════════════════════════════════════════════════════════════════════════
Enhanced for global users with free tier models and persistent chat memory.
Features:
- Free/Premium model routing (Gemini, Groq, Ollama for free tier)
- Persistent chat sessions with context memory
- Conversation history with automatic summarization
- Multi-language support
- Global currency and timezone handling
- Rewarded Ads system: free users unlock API calls by watching ads
- Gamification: XP + coins earned on every API call
"""

import json
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing   import Optional, Dict, Any, List
from enum     import Enum

from fastapi           import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from fastapi.responses import StreamingResponse
from pydantic          import BaseModel, Field

from middleware.rate_limit       import limiter, AI_LIMIT, FREE_TIER_LIMIT
from services.ai_service         import ai_service
from services.supabase_service   import supabase_service
from services.web_search_service import web_search_service
from services.action_service     import (
    email_service, social_service, document_service, opportunity_scanner
)
from services.scraper_service    import scraper_engine
from utils.auth import get_current_user, get_current_user_optional

router = APIRouter(prefix="/agent", tags=["Agentic AI"])
logger = logging.getLogger(__name__)

# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════

class ModelTier(str, Enum):
    FREE = "free"
    STANDARD = "standard"
    PREMIUM = "premium"

MAX_REACT_ITERATIONS = 8
MAX_RETRIES          = 2
DEFAULT_DAILY_RUNS   = 5
PREMIUM_DAILY_RUNS   = 50

# Rewarded ads config
AD_CREDIT_PER_WATCH      = 1          # 1 API call credit per ad watched
MAX_AD_CREDITS_PER_DAY   = 20         # Cap to prevent abuse
AD_REWARD_XP             = 10         # XP reward for watching an ad
CALL_XP_FREE             = 5          # XP per API call (free user)
CALL_XP_PREMIUM          = 8          # XP per API call (premium user)
CALL_COINS_FREE          = 2          # Coins per API call (free user)
CALL_COINS_PREMIUM       = 5          # Coins per API call (premium user)

FREE_MODELS = {
    "primary": "gemini-1.5-flash-latest",
    "fallback": "llama-3.1-8b-instant",
    "local": "ollama/llama3.2",
    "vision": "gemini-1.5-flash-latest",
}

PREMIUM_MODELS = {
    "fast": "gpt-4o-mini",
    "smart": "gpt-4o",
    "reasoning": "o1-mini",
    "vision": "gpt-4o",
}

MAX_CHAT_HISTORY = 50
SUMMARIZE_THRESHOLD = 30
MAX_SESSION_AGE_DAYS = 30

# ═══════════════════════════════════════════════════════════════════
# REQUEST MODELS
# ═══════════════════════════════════════════════════════════════════

class AgentRequest(BaseModel):
    task:              str
    context:           Optional[str]   = None
    budget:            Optional[float] = 0.0
    hours_per_day:     Optional[float] = 2.0
    currency:          Optional[str]   = "USD"
    country:           Optional[str]   = None
    language:          Optional[str]   = "en"
    mode:              Optional[str]   = "full"
    workflow_id:       Optional[str]   = None
    session_id:        Optional[str]   = None
    allow_email:       bool = False
    allow_social_post: bool = False
    social_tokens:     Optional[Dict] = None
    use_free_models:   Optional[bool]  = None

class AgentChatRequest(BaseModel):
    message:           str
    session_id:        Optional[str]        = None
    workflow_id:       Optional[str]        = None
    title:             Optional[str]        = None
    context_override:  Optional[str]        = None
    history_limit:     int                  = 20
    stream:            bool                 = False
    # NOTE: history is NOT a field — it is always loaded from DB via session_id

class ChatSessionCreate(BaseModel):
    title:             Optional[str] = None
    context:           Optional[str] = None
    workflow_id:       Optional[str] = None
    tags:              List[str] = []

class ExecuteToolRequest(BaseModel):
    tool:              str
    input:             Dict[str, Any]
    workflow_id:       Optional[str] = None
    session_id:        Optional[str] = None

class QuickRequest(BaseModel):
    task:              str
    output_type:       Optional[str] = "any"
    language:          Optional[str] = "en"

class AnalyzeRequest(BaseModel):
    content:           str
    goal:              Optional[str] = "improve"
    context:           Optional[str] = None

class ScanRequest(BaseModel):
    force_refresh:     bool = False
    location:          Optional[str] = None

# ─── AD MODELS ───────────────────────────────────────────────────────

class AdWatchCompleteRequest(BaseModel):
    ad_id:      str                    # ID returned by your ad network SDK
    ad_type:    str = "rewarded_video" # rewarded_video | interstitial
    session_id: Optional[str] = None
    # Verification token from your ad network (AdMob, Unity Ads, etc.)
    verify_token: Optional[str] = None

class AdStatusResponse(BaseModel):
    credits_available:    int
    credits_used_today:   int
    credits_earned_today: int
    max_credits_per_day:  int
    can_watch_more:       bool
    xp_earned_from_ads:   int
    show_ad_prompt:       bool  # frontend should show the "Watch an ad" CTA

# ─── GAMIFICATION MODELS ─────────────────────────────────────────────

class GamificationState(BaseModel):
    xp:              int = 0
    coins:           int = 0
    level:           int = 1
    streak_days:     int = 0
    total_api_calls: int = 0
    badges:          List[str] = []

# ═══════════════════════════════════════════════════════════════════
# TOOL REGISTRY
# ═══════════════════════════════════════════════════════════════════

TOOLS: Dict[str, Dict] = {
    "write_content": {
        "category":    "thinking",
        "description": "Write complete copy-paste-ready content: scripts, captions, bios, pitches, ad copy in user's language.",
        "system": 'Write COMPLETE, ready-to-use content in the user\'s language. No placeholders. Return JSON: {"content":"FULL TEXT","type":"...","usage_tip":"..."}',
        "free_compatible": True,
    },
    "create_plan": {
        "category":    "thinking",
        "description": "Build a day-by-day execution calendar with specific completable daily actions.",
        "system": 'Create DETAILED day-by-day plan. Specific, completable actions. Return JSON: {"plan_title":"...","days":[{"day":1,"actions":[...],"goal":"..."}],"success_metric":"..."}',
        "free_compatible": True,
    },
    "estimate_income": {
        "category":    "thinking",
        "description": "Give realistic income estimates with best/worst/likely cases and clear reasoning for user's country.",
        "system": 'Give REALISTIC 2025 income estimates localized to user country. Return JSON: {"min_monthly":0,"max_monthly":0,"likely_monthly":0,"currency":"...","timeline_to_first_income":"...","reasoning":"..."}',
        "free_compatible": True,
    },
    "generate_ideas": {
        "category":    "thinking",
        "description": "Generate specific actionable business/content/product ideas with first steps and income potential.",
        "system": 'Generate SPECIFIC actionable ideas with first steps. Return JSON: {"ideas":[{"title":"...","description":"...","first_steps":[...],"income_potential":"...","effort":"low|medium|high"}]}',
        "free_compatible": True,
    },
    "breakdown_task": {
        "category":    "thinking",
        "description": "Break any goal into smallest executable components with critical path and quick wins.",
        "system": 'Break down like a senior PM. Return JSON: {"task_summary":"...","components":[...],"critical_path":[...],"quick_wins":[...]}',
        "free_compatible": True,
    },
    "create_template": {
        "category":    "thinking",
        "description": "Create complete ready-to-send templates: emails, proposals, scripts, cold DMs.",
        "system": 'Write READY-TO-USE complete template with real text. Return JSON: {"template_type":"...","template":"FULL TEXT","how_to_customize":"..."}',
        "free_compatible": True,
    },
    "write_cold_outreach": {
        "category":    "thinking",
        "description": "Write personalized cold emails, WhatsApp messages, LinkedIn/Twitter DMs to land clients or partnerships.",
        "system": 'Write HIGH-CONVERTING outreach. 3 variants: short (2-3 sentences), medium (1 paragraph), long (full email). Return JSON: {"short":"...","medium":"...","long":"...","subject_line":"...","follow_up":"..."}',
        "free_compatible": True,
    },
    "build_profile_content": {
        "category":    "thinking",
        "description": "Write optimized platform profiles: Fiverr gig, Upwork bio, LinkedIn summary, Twitter/Instagram bio.",
        "system": 'Write OPTIMIZED platform profiles that attract clients. Return JSON: {"platform":"...","headline":"...","bio":"...","skills":[...],"cta":"...","full_profile":"COMPLETE TEXT"}',
        "free_compatible": True,
    },
    "summarize_chat": {
        "category":    "thinking",
        "description": "Summarize long conversation history to preserve context while reducing token usage.",
        "system": "Summarize this conversation into key points, decisions made, and current context. Be concise but preserve all important details.",
        "free_compatible": True,
    },
    "web_search": {
        "category":    "research",
        "description": "Search the live internet for current info, platforms, pricing, job postings, news.",
        "handler":     "web_search",
        "free_compatible": True,
    },
    "deep_research": {
        "category":    "research",
        "description": "Run multiple searches on a topic and synthesize comprehensive real findings.",
        "handler":     "deep_research",
        "free_compatible": True,
    },
    "find_freelance_jobs": {
        "category":    "research",
        "description": "Find real live freelance job postings on Upwork, Freelancer, LinkedIn, and others.",
        "handler":     "find_freelance_jobs",
        "free_compatible": True,
    },
    "find_partners": {
        "category":    "research",
        "description": "Find potential business partners, collaborators, or co-founders in a niche.",
        "handler":     "find_partners",
        "free_compatible": True,
    },
    "find_free_resources": {
        "category":    "research",
        "description": "Find free tools, grants, free courses, and zero-capital resources for starting a business.",
        "handler":     "find_free_resources",
        "free_compatible": True,
    },
    "market_research": {
        "category":    "research",
        "description": "Research a market: competition level, demand, pricing benchmarks, opportunity score.",
        "system": 'Analyze market with real data. Return JSON: {"niche":"...","competition":"low|medium|high","demand":"...","avg_price":"...","opportunity_score":0,"insights":[...],"entry_strategy":"..."}',
        "free_compatible": True,
    },
    "scan_opportunities": {
        "category":    "research",
        "description": "Scan web for current income opportunities matching the user skills and goals.",
        "handler":     "scan_opportunities",
        "free_compatible": True,
    },
    "send_email": {
        "category":            "action",
        "description":         "Send a real email on behalf of the user to a client, partner, or prospect.",
        "handler":             "send_email",
        "requires_permission": "allow_email",
        "free_compatible":     True,
    },
    "post_twitter": {
        "category":            "action",
        "description":         "Post a tweet to Twitter/X on behalf of the user.",
        "handler":             "post_twitter",
        "requires_permission": "allow_social_post",
        "free_compatible":     True,
    },
    "post_linkedin": {
        "category":            "action",
        "description":         "Publish a post to LinkedIn on behalf of the user.",
        "handler":             "post_linkedin",
        "requires_permission": "allow_social_post",
        "free_compatible":     True,
    },
    "schedule_post": {
        "category":            "action",
        "description":         "Schedule a social media post for a future date/time.",
        "handler":             "schedule_post",
        "requires_permission": "allow_social_post",
        "free_compatible":     True,
    },
    "generate_contract": {
        "category":    "document",
        "description": "Generate a complete legally structured freelance service contract.",
        "handler":     "generate_contract",
        "free_compatible": True,
    },
    "generate_invoice": {
        "category":    "document",
        "description": "Generate a professional invoice for completed work.",
        "handler":     "generate_invoice",
        "free_compatible": True,
    },
    "generate_proposal": {
        "category":    "document",
        "description": "Generate a complete business proposal document.",
        "handler":     "generate_proposal",
        "free_compatible": True,
    },
    "generate_pitch_deck": {
        "category":    "document",
        "description": "Generate a complete pitch deck outline for investors or partners.",
        "handler":     "generate_pitch_deck",
        "free_compatible": True,
    },
    "scrape_live_opportunities": {
        "category":    "intelligence",
        "description": "Scrape real live opportunities from Indeed, RemoteOK, Reddit, HackerNews — all AI-scored.",
        "handler":     "scrape_live_opportunities",
        "free_compatible": True,
    },
    "score_opportunity": {
        "category":    "intelligence",
        "description": "AI-analyse a specific opportunity: match score 0-100, risk level, action steps, time to first earning.",
        "system": 'You are an opportunity analyst. Score this opportunity for the user. Return ONLY valid JSON: {"match_score":0-100,"summary":"2-sentence personalised summary","risk_level":"low|medium|high","action_steps":["Step 1","Step 2","Step 3"],"time_to_first_earning":"e.g. 1-2 weeks","potential_monthly":0}',
        "free_compatible": True,
    },
    "analyze_market_trends": {
        "category":    "intelligence",
        "description": "Analyse market trends for an industry or skill: demand, pay rates, competition, growth trajectory.",
        "system": 'You are a market analyst with current 2025/2026 data. Analyse the given industry/skill and return ONLY valid JSON: {"demand_level":"high|medium|low","avg_pay_range":{"min":0,"max":0,"currency":"USD","period":"month"},"growth_trajectory":"growing|stable|declining","competition_level":"high|medium|low","best_platforms":["..."],"in_demand_skills":["..."],"future_outlook":"...","recommendations":["..."]}',
        "free_compatible": True,
    },
    "create_daily_action_plan": {
        "category":    "intelligence",
        "description": "Generate a prioritised daily action plan with specific tasks, milestones, and income targets.",
        "system": 'You are a personal income strategist. Create a detailed daily action plan. Return ONLY valid JSON: {"overview":"...","daily_tasks":["..."],"weekly_milestones":["..."],"resources_needed":["..."],"potential_obstacles":["..."],"mitigation_strategies":["..."],"income_target":"...","confidence_score":0-100}',
        "free_compatible": True,
    },
    "create_follow_up_plan": {
        "category":    "intelligence",
        "description": "Create a follow-up plan for an application or outreach — what to send, when, and how to handle different responses.",
        "system": 'You are an outreach specialist. Create a complete follow-up sequence. Return ONLY valid JSON: {"follow_up_1":{"when":"e.g. 3 days after","message":"FULL TEXT","subject":"..."},"follow_up_2":{"when":"...","message":"...","subject":"..."},"if_no_response":"what to do if no reply after 2 follow-ups","if_rejected":"how to respond to a rejection"}',
        "free_compatible": True,
    },
    "track_earnings_insight": {
        "category":    "intelligence",
        "description": "Analyse the user's earnings history and give insights: growth rate, top sources, what to focus on to hit their income goal.",
        "system": 'You are a financial analyst. Analyse these earnings and give actionable insight. Return ONLY valid JSON: {"growth_rate":"...","top_source":"...","monthly_trend":"growing|stable|declining","insight":"3-sentence analysis","next_milestone":"...","recommended_action":"..."}',
        "free_compatible": True,
    },
    "growth_milestone_check": {
        "category":    "intelligence",
        "description": "Check the user's progress against their wealth stage milestones and tell them exactly what they need to do to reach the next stage.",
        "system": 'You are a wealth coach. Analyse the user\'s current stage and give milestone guidance. Return ONLY valid JSON: {"current_stage":"survival|earning|growing|wealth","progress_to_next":0-100,"next_stage":"...","gap":"...","milestones_achieved":["..."],"next_milestones":["..."],"action_to_advance":"The single most impactful thing they can do right now"}',
        "free_compatible": True,
    },
}

# ═══════════════════════════════════════════════════════════════════
# CHAT MEMORY MANAGER
# ═══════════════════════════════════════════════════════════════════

class ChatMemoryManager:
    @staticmethod
    async def create_session(user_id: str, title: Optional[str] = None,
                             context: Optional[str] = None,
                             workflow_id: Optional[str] = None,
                             tags: List[str] = []) -> Dict[str, Any]:
        try:
            session_title = title or f"Chat {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')}"
            session_id = f"session_{user_id}_{int(datetime.now(timezone.utc).timestamp())}"

            sb = supabase_service.client
            result = sb.table("chat_sessions").insert({
                "id": session_id,
                "user_id": user_id,
                "title": session_title,
                "context": context,
                "workflow_id": workflow_id,
                "tags": tags,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "message_count": 0,
                "is_active": True,
                "summary": None,
            }).execute()

            return result.data[0] if result.data else {"id": session_id, "title": session_title}
        except Exception as e:
            logger.error(f"Failed to create session: {e}")
            return {"id": f"temp_{int(datetime.now(timezone.utc).timestamp())}", "title": title or "New Chat"}

    @staticmethod
    async def get_session(session_id: str, user_id: str) -> Optional[Dict]:
        try:
            sb = supabase_service.client
            result = sb.table("chat_sessions").select("*").eq("id", session_id).eq("user_id", user_id).single().execute()
            return result.data
        except Exception as e:
            logger.error(f"Failed to get session: {e}")
            return None

    @staticmethod
    async def list_sessions(user_id: str, limit: int = 50, include_archived: bool = False) -> List[Dict]:
        try:
            sb = supabase_service.client
            query = sb.table("chat_sessions").select("*").eq("user_id", user_id)
            if not include_archived:
                query = query.eq("is_active", True)
            result = query.order("updated_at", desc=True).limit(limit).execute()
            return result.data or []
        except Exception as e:
            logger.error(f"Failed to list sessions: {e}")
            return []

    @staticmethod
    async def save_message(session_id: str, user_id: str, role: str, content: str,
                           metadata: Optional[Dict] = None, model_used: Optional[str] = None) -> bool:
        try:
            sb = supabase_service.client
            sb.table("chat_messages").insert({
                "session_id": session_id,
                "user_id": user_id,
                "role": role,
                "content": content,
                "metadata": metadata or {},
                "model_used": model_used,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }).execute()

            sb.table("chat_sessions").update({
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", session_id).execute()

            return True
        except Exception as e:
            logger.error(f"Failed to save message: {e}")
            return False

    @staticmethod
    async def get_messages(session_id: str, user_id: str, limit: int = 50,
                           offset: int = 0, include_summary: bool = True) -> List[Dict]:
        try:
            sb = supabase_service.client
            result = sb.table("chat_messages").select("*").eq("session_id", session_id).eq("user_id", user_id).order("created_at", desc=True).limit(limit).offset(offset).execute()
            messages = list(reversed(result.data or []))

            if include_summary and offset == 0:
                session = await ChatMemoryManager.get_session(session_id, user_id)
                if session and session.get("summary"):
                    messages.insert(0, {
                        "role": "system",
                        "content": f"Previous conversation summary: {session['summary']}",
                        "is_summary": True,
                        "created_at": session.get("created_at")
                    })

            return messages
        except Exception as e:
            logger.error(f"Failed to get messages: {e}")
            return []

    @staticmethod
    async def update_session_summary(session_id: str, user_id: str, summary: str) -> bool:
        try:
            sb = supabase_service.client
            sb.table("chat_sessions").update({
                "summary": summary,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", session_id).eq("user_id", user_id).execute()
            return True
        except Exception as e:
            logger.error(f"Failed to update summary: {e}")
            return False

    @staticmethod
    async def rename_session(session_id: str, user_id: str, new_title: str) -> bool:
        try:
            sb = supabase_service.client
            sb.table("chat_sessions").update({
                "title": new_title,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", session_id).eq("user_id", user_id).execute()
            return True
        except Exception as e:
            logger.error(f"Failed to rename session: {e}")
            return False

    @staticmethod
    async def delete_session(session_id: str, user_id: str) -> bool:
        try:
            sb = supabase_service.client
            sb.table("chat_messages").delete().eq("session_id", session_id).eq("user_id", user_id).execute()
            sb.table("chat_sessions").delete().eq("id", session_id).eq("user_id", user_id).execute()
            return True
        except Exception as e:
            logger.error(f"Failed to delete session: {e}")
            return False

    @staticmethod
    async def auto_summarize_if_needed(session_id: str, user_id: str, ai_service_ref) -> bool:
        try:
            sb = supabase_service.client
            count_result = sb.table("chat_messages").select("count", count="exact").eq("session_id", session_id).execute()
            count = count_result.count or 0

            if count > SUMMARIZE_THRESHOLD:
                old_messages = await ChatMemoryManager.get_messages(session_id, user_id, limit=SUMMARIZE_THRESHOLD, offset=0)

                summary_prompt = "Summarize this conversation concisely, preserving key decisions, context, and action items:\n\n"
                for msg in old_messages[:20]:
                    summary_prompt += f"{msg['role']}: {msg['content'][:200]}...\n"

                result = await ai_service_ref.mentor_chat(
                    messages=[{"role": "user", "content": summary_prompt}],
                    system_prompt="Create a concise summary of this conversation. Focus on key points, decisions made, and current context.",
                    max_tokens=500,
                )

                summary = result["content"]
                await ChatMemoryManager.update_session_summary(session_id, user_id, summary)
                return True
            return False
        except Exception as e:
            logger.error(f"Auto-summarize failed: {e}")
            return False


# ═══════════════════════════════════════════════════════════════════
# REWARDED ADS MANAGER
# ═══════════════════════════════════════════════════════════════════

class AdManager:
    """
    Manages rewarded-ad credits for free-tier users.

    Flow:
      1. Free user hits daily quota  →  backend returns 402 with show_ad=True
      2. Flutter SDK shows a rewarded video ad (AdMob / Unity Ads)
      3. On ad completion the SDK calls POST /agent/ads/reward-complete
      4. AdManager grants 1 credit and awards XP/coins
      5. Next API call deducts the credit and proceeds normally

    Supabase tables needed:
      ad_credits (user_id PK, credits_available, credits_used_today,
                  credits_earned_today, quota_date, total_earned, updated_at)
    """

    @staticmethod
    def _today() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%d")

    @staticmethod
    async def get_credits(user_id: str) -> Dict[str, Any]:
        """Return current ad-credit state for the user."""
        today = AdManager._today()
        try:
            sb  = supabase_service.client
            row = sb.table("ad_credits").select("*").eq("user_id", user_id).maybe_single().execute()
            data = row.data or {}

            # Reset daily counters if stale date
            if data.get("quota_date") != today:
                data["credits_used_today"]   = 0
                data["credits_earned_today"] = 0
                data["quota_date"]           = today

            credits_available    = data.get("credits_available", 0)
            credits_earned_today = data.get("credits_earned_today", 0)
            credits_used_today   = data.get("credits_used_today", 0)

            return {
                "credits_available":    credits_available,
                "credits_used_today":   credits_used_today,
                "credits_earned_today": credits_earned_today,
                "max_credits_per_day":  MAX_AD_CREDITS_PER_DAY,
                "can_watch_more":       credits_earned_today < MAX_AD_CREDITS_PER_DAY,
                "xp_earned_from_ads":   data.get("xp_earned_from_ads", 0),
                "show_ad_prompt":       credits_available == 0,
            }
        except Exception as e:
            logger.error(f"AdManager.get_credits error: {e}")
            return {
                "credits_available": 0, "credits_used_today": 0,
                "credits_earned_today": 0, "max_credits_per_day": MAX_AD_CREDITS_PER_DAY,
                "can_watch_more": True, "xp_earned_from_ads": 0, "show_ad_prompt": True,
            }

    @staticmethod
    async def grant_credit(user_id: str, ad_id: str, ad_type: str = "rewarded_video") -> Dict[str, Any]:
        """
        Called after the ad network confirms a completed ad view.
        Grants 1 API-call credit + XP + coins.
        Returns updated credit state + gamification delta.
        """
        today = AdManager._today()
        try:
            sb  = supabase_service.client
            row = sb.table("ad_credits").select("*").eq("user_id", user_id).maybe_single().execute()
            data = row.data or {}

            # Reset daily counters if date changed
            if data.get("quota_date") != today:
                data["credits_earned_today"] = 0
                data["credits_used_today"]   = 0
                data["quota_date"]           = today

            earned_today = data.get("credits_earned_today", 0)
            if earned_today >= MAX_AD_CREDITS_PER_DAY:
                return {
                    "granted": False,
                    "reason": f"Daily ad limit of {MAX_AD_CREDITS_PER_DAY} reached. Come back tomorrow!",
                    "credits_available": data.get("credits_available", 0),
                }

            new_credits    = data.get("credits_available", 0) + AD_CREDIT_PER_WATCH
            new_earned     = earned_today + AD_CREDIT_PER_WATCH
            new_xp_ads     = data.get("xp_earned_from_ads", 0) + AD_REWARD_XP
            new_total      = data.get("total_earned", 0) + AD_CREDIT_PER_WATCH

            upsert_payload = {
                "user_id":             user_id,
                "credits_available":   new_credits,
                "credits_earned_today":new_earned,
                "credits_used_today":  data.get("credits_used_today", 0),
                "quota_date":          today,
                "total_earned":        new_total,
                "xp_earned_from_ads":  new_xp_ads,
                "last_ad_id":          ad_id,
                "last_ad_type":        ad_type,
                "updated_at":          datetime.now(timezone.utc).isoformat(),
            }

            sb.table("ad_credits").upsert(upsert_payload, on_conflict="user_id").execute()

            # Award gamification rewards
            gami = await GamificationManager.award(
                user_id, xp=AD_REWARD_XP, coins=CALL_COINS_FREE,
                reason="rewarded_ad_watched"
            )

            return {
                "granted":           True,
                "credits_available": new_credits,
                "credits_earned_today": new_earned,
                "xp_awarded":        AD_REWARD_XP,
                "coins_awarded":     CALL_COINS_FREE,
                "gamification":      gami,
                "message":           f"🎉 +{AD_CREDIT_PER_WATCH} API credit! Keep going! 🚀",
            }
        except Exception as e:
            logger.error(f"AdManager.grant_credit error: {e}")
            return {"granted": False, "reason": str(e), "credits_available": 0}

    @staticmethod
    async def consume_credit(user_id: str) -> bool:
        """
        Deduct 1 credit before an API call.
        Returns True if successful, False if no credits.
        """
        today = AdManager._today()
        try:
            sb  = supabase_service.client
            row = sb.table("ad_credits").select("*").eq("user_id", user_id).maybe_single().execute()
            data = row.data or {}

            if data.get("quota_date") != today:
                # Credits reset daily — but accumulated credits DON'T reset
                # (only the earned_today and used_today counters reset)
                pass

            credits = data.get("credits_available", 0)
            if credits <= 0:
                return False

            sb.table("ad_credits").update({
                "credits_available":  credits - 1,
                "credits_used_today": data.get("credits_used_today", 0) + 1,
                "updated_at":         datetime.now(timezone.utc).isoformat(),
            }).eq("user_id", user_id).execute()

            return True
        except Exception as e:
            logger.error(f"AdManager.consume_credit error: {e}")
            return False


# ═══════════════════════════════════════════════════════════════════
# GAMIFICATION MANAGER
# ═══════════════════════════════════════════════════════════════════

# XP thresholds per level (level 1 = 0 XP, level 2 = 100 XP, etc.)
XP_PER_LEVEL = 100

BADGES = {
    "first_call":      {"xp": 0,    "label": "🌱 First Step",      "desc": "Made your first AI call"},
    "call_10":         {"xp": 50,   "label": "🔥 On Fire",         "desc": "10 AI calls completed"},
    "call_50":         {"xp": 200,  "label": "⚡ Power User",      "desc": "50 AI calls completed"},
    "ad_watcher":      {"xp": 10,   "label": "📺 Ad Supporter",    "desc": "Watched your first rewarded ad"},
    "ad_10":           {"xp": 50,   "label": "💪 Committed",       "desc": "Watched 10 rewarded ads"},
    "streak_3":        {"xp": 75,   "label": "📅 3-Day Streak",    "desc": "Used APEX 3 days in a row"},
    "streak_7":        {"xp": 200,  "label": "🗓️ Weekly Warrior", "desc": "7-day usage streak"},
    "first_workflow":  {"xp": 100,  "label": "🗺️ Planner",        "desc": "Completed your first workflow"},
}


class GamificationManager:
    """Awards XP, coins, and badges on every API call and ad watch."""

    @staticmethod
    async def award(
        user_id: str,
        xp: int = 0,
        coins: int = 0,
        reason: str = "api_call",
    ) -> Dict[str, Any]:
        """
        Award XP + coins to the user and check for level-ups/badges.
        Persists to `user_gamification` table.
        """
        try:
            sb  = supabase_service.client
            row = sb.table("user_gamification").select("*").eq("user_id", user_id).maybe_single().execute()
            data = row.data or {
                "user_id": user_id, "xp": 0, "coins": 0, "level": 1,
                "total_api_calls": 0, "streak_days": 0, "badges": [],
                "last_active_date": None,
            }

            today     = AdManager._today()
            last_date = data.get("last_active_date")
            yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")

            # Streak logic
            streak = data.get("streak_days", 0)
            if last_date == yesterday:
                streak += 1
            elif last_date != today:
                streak = 1

            new_xp    = data.get("xp", 0) + xp
            new_coins = data.get("coins", 0) + coins
            new_calls = data.get("total_api_calls", 0) + (1 if reason == "api_call" else 0)
            new_level = max(1, new_xp // XP_PER_LEVEL + 1)
            leveled_up = new_level > data.get("level", 1)

            # Badge checks
            current_badges = set(data.get("badges") or [])
            new_badges: List[str] = []

            if new_calls == 1 and "first_call" not in current_badges:
                new_badges.append("first_call")
            if new_calls >= 10 and "call_10" not in current_badges:
                new_badges.append("call_10")
            if new_calls >= 50 and "call_50" not in current_badges:
                new_badges.append("call_50")
            if streak >= 3 and "streak_3" not in current_badges:
                new_badges.append("streak_3")
            if streak >= 7 and "streak_7" not in current_badges:
                new_badges.append("streak_7")
            if reason == "rewarded_ad_watched":
                ad_count = data.get("ad_watches", 0) + 1
                if "ad_watcher" not in current_badges:
                    new_badges.append("ad_watcher")
                if ad_count >= 10 and "ad_10" not in current_badges:
                    new_badges.append("ad_10")
            else:
                ad_count = data.get("ad_watches", 0)

            all_badges = list(current_badges | set(new_badges))

            # Extra XP for new badges
            badge_xp = sum(BADGES[b]["xp"] for b in new_badges if b in BADGES)
            new_xp += badge_xp

            upsert = {
                "user_id":           user_id,
                "xp":                new_xp,
                "coins":             new_coins,
                "level":             new_level,
                "total_api_calls":   new_calls,
                "streak_days":       streak,
                "badges":            all_badges,
                "ad_watches":        ad_count,
                "last_active_date":  today,
                "updated_at":        datetime.now(timezone.utc).isoformat(),
            }
            sb.table("user_gamification").upsert(upsert, on_conflict="user_id").execute()

            return {
                "xp_earned":    xp + badge_xp,
                "coins_earned": coins,
                "new_level":    new_level,
                "leveled_up":   leveled_up,
                "streak_days":  streak,
                "new_badges":   [{"id": b, **BADGES[b]} for b in new_badges if b in BADGES],
                "totals": {
                    "xp": new_xp, "coins": new_coins,
                    "level": new_level, "streak": streak,
                },
            }
        except Exception as e:
            logger.error(f"GamificationManager.award error: {e}")
            return {"xp_earned": xp, "coins_earned": coins, "new_level": 1,
                    "leveled_up": False, "streak_days": 0, "new_badges": [], "totals": {}}

    @staticmethod
    async def get_state(user_id: str) -> Dict[str, Any]:
        """Return current gamification state for the user."""
        try:
            sb  = supabase_service.client
            row = sb.table("user_gamification").select("*").eq("user_id", user_id).maybe_single().execute()
            data = row.data or {}
            xp   = data.get("xp", 0)
            lvl  = data.get("level", 1)
            return {
                "xp":             xp,
                "coins":          data.get("coins", 0),
                "level":          lvl,
                "xp_to_next":     (lvl * XP_PER_LEVEL) - xp,
                "progress_pct":   int((xp % XP_PER_LEVEL) / XP_PER_LEVEL * 100),
                "streak_days":    data.get("streak_days", 0),
                "total_api_calls":data.get("total_api_calls", 0),
                "badges":         data.get("badges", []),
                "ad_watches":     data.get("ad_watches", 0),
            }
        except Exception as e:
            logger.error(f"GamificationManager.get_state error: {e}")
            return {"xp": 0, "coins": 0, "level": 1, "xp_to_next": 100,
                    "progress_pct": 0, "streak_days": 0, "total_api_calls": 0,
                    "badges": [], "ad_watches": 0}


# ═══════════════════════════════════════════════════════════════════
# MODEL ROUTER
# ═══════════════════════════════════════════════════════════════════

class ModelRouter:
    @staticmethod
    def select_model(user: Dict, task_complexity: str = "standard", prefer_free: Optional[bool] = None) -> Dict:
        is_premium = user.get("is_premium", False)
        use_free = prefer_free if prefer_free is not None else not is_premium

        if use_free or not is_premium:
            if task_complexity == "simple":
                return {"model": FREE_MODELS["fallback"], "provider": "groq",
                        "tier": "free", "max_tokens": 2000, "temperature": 0.7}
            elif task_complexity == "vision":
                return {"model": FREE_MODELS["vision"], "provider": "google",
                        "tier": "free", "max_tokens": 4000, "temperature": 0.7}
            else:
                return {"model": FREE_MODELS["primary"], "provider": "google",
                        "tier": "free", "max_tokens": 4000, "temperature": 0.7}
        else:
            if task_complexity == "reasoning":
                return {"model": PREMIUM_MODELS["reasoning"], "provider": "openai",
                        "tier": "premium", "max_tokens": 4000, "temperature": 0.7}
            elif task_complexity == "vision":
                return {"model": PREMIUM_MODELS["vision"], "provider": "openai",
                        "tier": "premium", "max_tokens": 4000, "temperature": 0.7}
            else:
                return {"model": PREMIUM_MODELS["smart"], "provider": "openai",
                        "tier": "premium", "max_tokens": 4000, "temperature": 0.7}

    @staticmethod
    async def chat_with_model(messages: List[Dict], system: str, user: Dict,
                              task_complexity: str = "standard",
                              prefer_free: Optional[bool] = None,
                              max_tokens: Optional[int] = None,
                              stream: bool = False) -> Dict:
        config = ModelRouter.select_model(user, task_complexity, prefer_free)

        if max_tokens:
            config["max_tokens"] = max_tokens

        try:
            result = await ai_service.mentor_chat(
                messages=messages,
                system_prompt=system,
                max_tokens=config["max_tokens"],
            )

            return {
                "content":      result.get("content", ""),
                "model":        config["model"],
                "provider":     config["provider"],
                "tier":         config["tier"],
                "usage":        {},
                "raw_response": result,
            }
        except Exception as e:
            logger.error(f"Model {config['model']} failed: {e}")
            if config["tier"] == "premium":
                fallback = ModelRouter.select_model(user, task_complexity, prefer_free=True)
                result = await ai_service.mentor_chat(
                    messages=messages,
                    system_prompt=system,
                    max_tokens=fallback["max_tokens"],
                )
                return {
                    "content":      result.get("content", ""),
                    "model":        fallback["model"],
                    "provider":     fallback["provider"],
                    "tier":         "free (fallback)",
                    "usage":        {},
                    "raw_response": result,
                }
            raise


# ═══════════════════════════════════════════════════════════════════
# TOOL EXECUTOR
# ═══════════════════════════════════════════════════════════════════

async def _execute_tool(tool_name: str, tool_input: dict,
                        profile: dict, permissions: dict,
                        session_id: Optional[str] = None,
                        user_id: Optional[str] = None) -> str:
    meta = TOOLS.get(tool_name)
    if not meta:
        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    required_perm = meta.get("requires_permission")
    if required_perm and not permissions.get(required_perm, False):
        return json.dumps({"skipped": True,
                           "reason": f"Permission '{required_perm}' not granted.",
                           "content_preview": tool_input})

    handler  = meta.get("handler")
    currency = profile.get("currency", "USD")
    country  = profile.get("country", "US")
    language = profile.get("language", "en")

    if handler == "web_search":
        results = await web_search_service.search(tool_input.get("query", ""), num=8)
        return json.dumps({"results": results[:8], "language": language})

    if handler == "deep_research":
        result = await web_search_service.deep_research(
            tool_input.get("topic", tool_input.get("query", "")),
            tool_input.get("sub_queries"),
        )
        return json.dumps({**result, "language": language})

    if handler == "find_freelance_jobs":
        jobs = await web_search_service.find_freelance_jobs(
            tool_input.get("skill", ""), country)
        return json.dumps({"jobs": jobs, "country": country})

    if handler == "find_partners":
        partners = await web_search_service.find_partners(
            tool_input.get("niche", ""), country)
        return json.dumps({"partners": partners, "country": country})

    if handler == "find_free_resources":
        res = await web_search_service.find_free_resources(
            tool_input.get("business_type", tool_input.get("type", "")))
        return json.dumps({"resources": res, "country": country})

    if handler == "scan_opportunities":
        opps = await opportunity_scanner.scan_for_user(profile)
        return json.dumps({"opportunities": opps, "country": country})

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
            user_id or profile.get("id", ""),
        ))

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
        return json.dumps({"document": doc, "type": "contract", "language": language})

    if handler == "generate_invoice":
        doc = document_service.generate_invoice(
            client_name      = tool_input.get("client_name", "Client"),
            freelancer_name  = profile.get("full_name", "Freelancer"),
            freelancer_email = profile.get("email", ""),
            items            = tool_input.get("items", []),
            currency         = tool_input.get("currency", currency),
        )
        return json.dumps({"document": doc, "type": "invoice", "language": language})

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
        return json.dumps({"document": doc, "type": "proposal", "language": language})

    if handler == "generate_pitch_deck":
        doc = document_service.generate_pitch_deck_outline(
            business_name = tool_input.get("business_name", ""),
            problem       = tool_input.get("problem", ""),
            solution      = tool_input.get("solution", ""),
            market_size   = tool_input.get("market_size", ""),
            traction      = tool_input.get("traction", ""),
            ask           = tool_input.get("ask", ""),
        )
        return json.dumps({"document": doc, "type": "pitch_deck", "language": language})

    if handler == "scrape_live_opportunities":
        opp_types = tool_input.get("types", ["jobs", "hustles", "freelance"])
        query     = tool_input.get("query", " ".join(profile.get("current_skills", [])[:3]))
        opps      = await scraper_engine.find_opportunities(
            profile     = profile,
            opp_types   = opp_types,
            query       = query,
            max_results = tool_input.get("max_results", 20),
            score_with_ai = True,
        )
        return json.dumps({"opportunities": opps, "total": len(opps), "country": country})

    system   = meta.get("system", "Return ONLY valid JSON.")
    user_msg = (
        f"User: {country}, {currency}, language={language}, "
        f"skills={profile.get('current_skills', [])}, "
        f"stage={profile.get('stage','survival')}\n"
        f"Input: {json.dumps(tool_input)}\nReturn ONLY valid JSON."
    )

    for attempt in range(MAX_RETRIES):
        try:
            result = await ModelRouter.chat_with_model(
                messages=[{"role": "user", "content": user_msg}],
                system=system,
                user=profile,
                task_complexity="simple" if tool_name in ["write_content", "create_template"] else "standard",
                prefer_free=True,
                max_tokens=2500,
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
                return json.dumps({"error": str(e), "partial_response": raw if 'raw' in locals() else ""})
            await asyncio.sleep(0.5)
    return json.dumps({"error": "Tool failed after retries"})


# ═══════════════════════════════════════════════════════════════════
# SYSTEM PROMPTS
# ═══════════════════════════════════════════════════════════════════

def _agent_system(profile, task, budget, hours, currency, permissions, language="en") -> str:
    name    = profile.get("full_name", "User")
    stage   = profile.get("stage", "survival")
    skills  = ", ".join(profile.get("current_skills", []) or ["none"])
    country = profile.get("country", "US")
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

    lang_instruction = ""
    if language != "en":
        lang_instruction = f"\nIMPORTANT: Respond in {language} language (ISO code: {language})."

    return f"""You are APEX — RiseUp's Autonomous Agent. You WORK, not chat.

USER: {name} | {country} | {stage.upper()} | Skills: {skills}
Income: {currency} {income:,.0f}/mo | Budget: {"FREE ONLY" if not budget else f"{currency} {budget:,.0f}"} | Time: {hours}h/day

PERMISSIONS: {" | ".join(perms)}{lang_instruction}

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
- Respond in user's preferred language when specified
"""

def _final_system(currency, language="en") -> str:
    lang_note = f' "language": "{language}",' if language != "en" else ""
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
  "wealth_insight": "One deeper insight about their path to financial growth",{lang_note}
  "model_tier_used": "free|premium"
}}
"""

def _chat_system(profile, session_context: Optional[str] = None, language: str = "en") -> str:
    name     = profile.get("full_name", "User")
    country  = profile.get("country", "US")
    currency = profile.get("currency", "USD")
    skills   = ", ".join(profile.get("current_skills", []) or [])

    context_section = ""
    if session_context:
        context_section = f"\nPREVIOUS CONTEXT:\n{session_context}\n"

    lang_instruction = f"\nRespond in {language} language." if language != "en" else ""

    return f"""You are APEX — RiseUp's Autonomous Agent for {name}.
Location: {country} | Currency: {currency} | Skills: {skills}
You are in a continuous conversation. Remember previous messages and maintain context.
Produce COMPLETE, ready-to-use outputs. No placeholders. Be specific to {country}.{context_section}{lang_instruction}

If the user asks you to remember something, acknowledge it. If they reference previous discussion, use that context.
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

async def _react_loop(task, profile, budget, hours, currency, permissions,
                      language="en", session_id=None, user_id=None) -> Dict:
    system   = _agent_system(profile, task, budget, hours, currency, permissions, language)
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

        result = await ModelRouter.chat_with_model(
            messages=messages + ([{"role": "assistant", "content": ctx}] if ctx else []),
            system=system,
            user=profile,
            task_complexity="standard",
            prefer_free=True,
            max_tokens=800,
        )

        last_result = result
        turn = _parse(result["content"])

        obs = ""
        if turn["tool"] and turn["tool"] in TOOLS:
            obs = await _execute_tool(turn["tool"], turn["tool_input"] or {"query": task},
                                      profile, permissions, session_id, user_id)
        elif turn["tool"]:
            obs = json.dumps({"error": f"Tool '{turn['tool']}' not in registry"})

        memory.append({
            "thought":     turn["thought"],
            "tool":        turn["tool"],
            "input":       turn["tool_input"],
            "observation": obs,
            "iteration":   i,
        })

        if session_id and user_id:
            await ChatMemoryManager.save_message(
                session_id, user_id, "assistant",
                f"Step {i}: {turn['thought'][:200]}...",
                {"tool": turn["tool"], "iteration": i, "observation_preview": obs[:200]}
            )

        if turn["done"] or i == MAX_REACT_ITERATIONS:
            break

    return {"memory": memory, "iterations": len(memory),
            "model": last_result.get("model", "unknown"),
            "tier": last_result.get("tier", "free")}


# ═══════════════════════════════════════════════════════════════════
# QUOTA & UTILITIES
# ═══════════════════════════════════════════════════════════════════

async def _check_quota(user_id: str, is_premium: bool = False) -> Dict:
    """
    Check if the user can make an API call.

    Priority order:
      1. Premium users → always allowed (up to PREMIUM_DAILY_RUNS)
      2. Free users within DEFAULT_DAILY_RUNS → allowed
      3. Free users who exhausted quota but have ad credits → allowed (credit consumed)
      4. Free users with no quota and no credits → blocked, show_ad=True
    """
    limit = PREMIUM_DAILY_RUNS if is_premium else DEFAULT_DAILY_RUNS
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    key   = f"agent_runs:{user_id}:{today}"

    try:
        sb   = supabase_service.client
        row  = sb.table("agent_run_quota").select("*").eq("quota_key", key).maybe_single().execute()
        used = row.data["runs_used"] if row.data else 0

        if used < limit:
            # Within regular quota — increment and allow
            if row.data:
                sb.table("agent_run_quota").update({"runs_used": used + 1}).eq("quota_key", key).execute()
            else:
                sb.table("agent_run_quota").insert({
                    "quota_key": key, "user_id": user_id, "runs_used": 1,
                    "quota_date": today, "quota_limit": limit,
                }).execute()
            return {
                "allowed":       True,
                "runs_used":     used + 1,
                "runs_limit":    limit,
                "tier":          "premium" if is_premium else "free",
                "via_ad_credit": False,
                "show_ad":       False,
            }

        # Quota exhausted — check ad credits (free users only)
        if not is_premium:
            consumed = await AdManager.consume_credit(user_id)
            if consumed:
                ad_state = await AdManager.get_credits(user_id)
                return {
                    "allowed":         True,
                    "runs_used":       used,
                    "runs_limit":      limit,
                    "tier":            "free",
                    "via_ad_credit":   True,
                    "show_ad":         False,
                    "ad_credits_left": ad_state["credits_available"],
                    "message":         "✅ Ad credit used — keep it up! 🎉",
                }

            # No quota, no credits
            ad_state = await AdManager.get_credits(user_id)
            return {
                "allowed":          False,
                "runs_used":        used,
                "runs_limit":       limit,
                "tier":             "free",
                "via_ad_credit":    False,
                "show_ad":          ad_state["can_watch_more"],
                "can_watch_more":   ad_state["can_watch_more"],
                "credits_available":ad_state["credits_available"],
                "resets_at":        f"{today}T23:59:59Z",
                "upgrade_prompt":   "Upgrade to Premium for unlimited runs",
            }

        # Premium quota exhausted
        return {
            "allowed":    False,
            "runs_used":  used,
            "runs_limit": limit,
            "resets_at":  f"{today}T23:59:59Z",
            "tier":       "premium",
            "show_ad":    False,
        }
    except Exception as e:
        logger.warning(f"Quota check error: {e}")
        return {"allowed": True, "runs_used": 1, "runs_limit": limit, "tier": "free",
                "via_ad_credit": False, "show_ad": False}


async def _award_call_gamification(user_id: str, is_premium: bool) -> Dict:
    """Award XP + coins for completing an API call."""
    xp    = CALL_XP_PREMIUM if is_premium else CALL_XP_FREE
    coins = CALL_COINS_PREMIUM if is_premium else CALL_COINS_FREE
    return await GamificationManager.award(user_id, xp=xp, coins=coins, reason="api_call")


def _sse(event, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data) if not isinstance(data, str) else data}\n\n"

def _build_final_prompt(task, memory) -> str:
    memory_text = "\n\n".join(
        f"[Step {m['iteration']}]\nTHOUGHT: {m['thought']}\n"
        f"TOOL: {m['tool'] or 'none'}\nRESULT: {m['observation']}"
        for m in memory
    )
    return f"TASK: {task}\n\nRESEARCH & ACTIONS:\n{memory_text}\n\nWrite the final structured response."

async def _finalize(task, memory, currency, language="en", tier="free") -> Dict:
    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": _build_final_prompt(task, memory)}],
        system=_final_system(currency, language),
        user={"is_premium": tier == "premium"},
        task_complexity="standard",
        prefer_free=(tier == "free"),
        max_tokens=4000,
    )

    raw = result["content"].strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    try:
        parsed = json.loads(raw.strip())
        parsed["model_tier_used"] = result.get("tier", tier)
        return parsed
    except Exception:
        s, e = raw.find("{"), raw.rfind("}") + 1
        if s >= 0 and e > s:
            try:
                parsed = json.loads(raw[s:e])
                parsed["model_tier_used"] = result.get("tier", tier)
                return parsed
            except:
                pass
        return {"agent_response": raw, "model_tier_used": result.get("tier", tier)}

async def _save_workflow(user_id, task, data, currency, workflow_id=None, session_id=None):
    plan  = data.get("plan", {})
    steps = data.get("steps", [])
    if not (plan and steps):
        return workflow_id

    try:
        sb = supabase_service.client
        if not workflow_id:
            wf = sb.table("workflows").insert({
                "user_id":            user_id,
                "title":              plan.get("title", task[:50]),
                "goal":               task,
                "income_type":        plan.get("income_type", "other"),
                "currency":           currency,
                "status":             "active",
                "total_revenue":      0.0,
                "viability_score":    plan.get("viability", 75),
                "realistic_timeline": plan.get("timeline", ""),
                "potential_min":      plan.get("income_range", {}).get("min", 0),
                "potential_max":      plan.get("income_range", {}).get("max", 0),
                "honest_warning":     plan.get("warning", ""),
                "research_snapshot":  json.dumps(data),
                "session_id":         session_id,
                "model_tier_used":    data.get("model_tier_used", "free"),
            }).execute()
            workflow_id = wf.data[0]["id"] if wf.data else None

        if workflow_id and steps:
            sb.table("workflow_steps").insert([{
                "workflow_id":  workflow_id,
                "user_id":      user_id,
                "order_index":  s.get("order", i + 1),
                "title":        s.get("title", ""),
                "description":  s.get("description", ""),
                "step_type":    s.get("type", "manual"),
                "time_minutes": s.get("time_minutes", 30),
                "tools":        json.dumps(s.get("tools", [])),
                "ai_output":    s.get("ai_output", ""),
                "status":       "pending",
            } for i, s in enumerate(steps)]).execute()

        free_tools = data.get("free_tools", [])
        if free_tools and workflow_id:
            sb.table("workflow_tools").insert([{
                "workflow_id": workflow_id,
                "name":        t.get("name", ""),
                "url":         t.get("url", ""),
                "purpose":     t.get("purpose", ""),
                "is_free":     t.get("is_free", True),
            } for t in free_tools]).execute()

        for doc in data.get("documents_generated", []):
            if doc.get("content") and workflow_id:
                try:
                    sb.table("agent_documents").insert({
                        "workflow_id": workflow_id,
                        "user_id":     user_id,
                        "doc_type":    doc.get("type", "document"),
                        "content":     doc.get("content", ""),
                        "session_id":  session_id,
                    }).execute()
                except Exception:
                    pass
    except Exception as e:
        logger.error(f"Workflow save error: {e}")
    return workflow_id


# ═══════════════════════════════════════════════════════════════════
# ── REWARDED ADS ENDPOINTS ──────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════

@router.post("/ads/reward-complete")
@limiter.limit(FREE_TIER_LIMIT)
async def ad_reward_complete(
    req:     AdWatchCompleteRequest,
    request: Request,
    user:    dict = Depends(get_current_user),
):
    """
    Called by the Flutter SDK immediately after the user completes a rewarded ad.
    Grants 1 API-call credit + XP + coins.

    Flutter integration:
      RewardedAd.show(onUserEarnedReward: (ad, reward) async {
        await api.post('/agent/ads/reward-complete', {
          'ad_id': ad.adUnitId,
          'ad_type': 'rewarded_video',
        });
      });
    """
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)

    # Premium users don't need to watch ads — graceful no-op
    if is_premium:
        return {
            "granted": True,
            "message": "Premium users don't need ads 🎉",
            "is_premium": True,
        }

    result = await AdManager.grant_credit(
        user_id  = user_id,
        ad_id    = req.ad_id,
        ad_type  = req.ad_type,
    )

    if req.session_id and result.get("granted"):
        await ChatMemoryManager.save_message(
            req.session_id, user_id, "system",
            "User watched a rewarded ad and earned 1 API credit.",
            {"type": "ad_reward", "ad_id": req.ad_id, "credits_available": result.get("credits_available")}
        )

    return result


@router.get("/ads/credits")
async def get_ad_credits(user: dict = Depends(get_current_user)):
    """
    Return current ad-credit balance + whether to show the 'Watch Ad' CTA.

    Flutter: poll this before each API call to decide whether to gate behind an ad.
    """
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)

    if is_premium:
        return {
            "is_premium":           True,
            "credits_available":    999,
            "can_watch_more":       False,
            "show_ad_prompt":       False,
            "max_credits_per_day":  MAX_AD_CREDITS_PER_DAY,
            "credits_used_today":   0,
            "credits_earned_today": 0,
            "xp_earned_from_ads":   0,
        }

    state = await AdManager.get_credits(user_id)
    return state


# ═══════════════════════════════════════════════════════════════════
# ── GAMIFICATION ENDPOINTS ──────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════

@router.get("/gamification")
async def get_gamification(user: dict = Depends(get_current_user)):
    """Return the user's full gamification state: XP, coins, level, badges, streak."""
    state = await GamificationManager.get_state(user["id"])
    return state


@router.get("/gamification/badges")
async def list_badges(user: dict = Depends(get_current_user)):
    """List all possible badges and which ones the user has earned."""
    state = await GamificationManager.get_state(user["id"])
    earned = set(state.get("badges", []))
    return {
        "earned": [
            {"id": b, **BADGES[b], "earned": True}
            for b in earned if b in BADGES
        ],
        "locked": [
            {"id": b, **BADGES[b], "earned": False}
            for b in BADGES if b not in earned
        ],
        "total_badges": len(BADGES),
        "earned_count": len(earned),
    }


# ═══════════════════════════════════════════════════════════════════
# MAIN AGENT ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.post("/run")
@limiter.limit(AI_LIMIT)
async def run_agent(req: AgentRequest, request: Request,
                    user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    currency   = req.currency or profile.get("currency", "USD")
    country    = req.country  or profile.get("country",  "US")
    language   = req.language or profile.get("language", "en")
    profile["country"] = country

    use_free = req.use_free_models if req.use_free_models is not None else not is_premium

    quota = await _check_quota(user_id, is_premium)
    if not quota["allowed"]:
        raise HTTPException(402, {
            "error":          "Daily run limit reached",
            "runs_used":      quota["runs_used"],
            "runs_limit":     quota["runs_limit"],
            "show_ad":        quota.get("show_ad", True),
            "can_watch_more": quota.get("can_watch_more", True),
            "upgrade_prompt": "Upgrade to Premium for unlimited runs, or watch a short ad to continue.",
            "tier":           quota["tier"],
        })

    permissions = {
        "allow_email":       req.allow_email,
        "allow_social_post": req.allow_social_post,
        "social_tokens":     req.social_tokens or {}
    }

    session_id = req.session_id
    if not session_id:
        session    = await ChatMemoryManager.create_session(
            user_id,
            title      = f"Agent Run: {req.task[:30]}...",
            context    = req.context,
            workflow_id= req.workflow_id
        )
        session_id = session["id"]

    await ChatMemoryManager.save_message(
        session_id, user_id, "user",
        f"Task: {req.task}\nBudget: {req.budget}\nHours: {req.hours_per_day}",
        {"type": "agent_request", "budget": req.budget, "hours": req.hours_per_day}
    )

    react = await _react_loop(
        req.task, profile, req.budget or 0,
        req.hours_per_day or 2, currency, permissions,
        language, session_id, user_id
    )

    tier        = "premium" if is_premium and not use_free else "free"
    agent_data  = await _finalize(req.task, react["memory"], currency, language, tier)
    workflow_id = await _save_workflow(user_id, req.task, agent_data, currency, req.workflow_id, session_id)

    await ChatMemoryManager.save_message(
        session_id, user_id, "assistant",
        agent_data.get("agent_response", "Task completed"),
        {"type": "agent_completion", "workflow_id": workflow_id,
         "tools_used": [m["tool"] for m in react["memory"] if m["tool"]]}
    )

    # Gamification rewards
    gami = await _award_call_gamification(user_id, is_premium)

    return {
        **agent_data,
        "workflow_id":   workflow_id,
        "session_id":    session_id,
        "model_used":    react["model"],
        "model_tier":    tier,
        "iterations":    react["iterations"],
        "task":          req.task,
        "quota":         quota,
        "gamification":  gami,
        "via_ad_credit": quota.get("via_ad_credit", False),
    }


@router.post("/run-stream")
@limiter.limit(AI_LIMIT)
async def run_agent_stream(req: AgentRequest, request: Request,
                           user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    currency   = req.currency or profile.get("currency", "USD")
    language   = req.language or profile.get("language", "en")
    use_free   = req.use_free_models if req.use_free_models is not None else not is_premium

    permissions = {
        "allow_email":       req.allow_email,
        "allow_social_post": req.allow_social_post,
        "social_tokens":     req.social_tokens or {}
    }

    async def stream():
        quota = await _check_quota(user_id, is_premium)
        yield _sse("quota_check", {
            **quota,
            "runs_remaining": quota["runs_limit"] - quota["runs_used"],
            "tier":           "free" if use_free else "premium",
        })

        if not quota["allowed"]:
            yield _sse("error", {
                "message":        "Daily run limit reached.",
                "show_ad":        quota.get("show_ad", True),
                "can_watch_more": quota.get("can_watch_more", True),
                "resets_at":      quota.get("resets_at", ""),
                "tier":           quota["tier"],
            })
            return

        session    = await ChatMemoryManager.create_session(
            user_id,
            title      = f"Stream: {req.task[:30]}...",
            context    = req.context,
            workflow_id= req.workflow_id
        )
        session_id = session["id"]
        await ChatMemoryManager.save_message(session_id, user_id, "user", req.task)

        system     = _agent_system(profile, req.task, req.budget or 0,
                                   req.hours_per_day or 2, currency, permissions, language)
        messages   = [{"role": "user", "content": f"Begin: {req.task}"}]
        memory     = []
        last_model = "unknown"
        tier_used  = "free" if use_free else "premium"

        for i in range(1, MAX_REACT_ITERATIONS + 1):
            ctx = ""
            if memory:
                ctx = "\n─── COMPLETED ───\n" + "".join(
                    f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'} | {m['observation'][:250]}...\n"
                    if len(m['observation']) > 250
                    else f"\n[{m['iteration']}] TOOL={m['tool'] or 'NONE'} | {m['observation']}\n"
                    for m in memory
                ) + "\n─── Continue ───"

            result = await ModelRouter.chat_with_model(
                messages=messages + ([{"role": "assistant", "content": ctx}] if ctx else []),
                system=system,
                user=profile,
                task_complexity="standard",
                prefer_free=use_free,
                max_tokens=800,
            )

            last_model = result.get("model", "unknown")
            tier_used  = result.get("tier", tier_used)
            turn = _parse(result["content"])
            cat  = TOOLS.get(turn["tool"] or "", {}).get("category", "")

            yield _sse("thinking", {
                "iteration": i,
                "thought":   turn["thought"],
                "total":     MAX_REACT_ITERATIONS,
                "model":     last_model,
                "tier":      tier_used,
            })

            obs = ""
            if turn["tool"] and turn["tool"] in TOOLS:
                tool_input = turn["tool_input"] or {"query": req.task}
                yield _sse("tool_call", {
                    "iteration": i,
                    "tool":      turn["tool"],
                    "category":  cat,
                    "input":     tool_input,
                })

                obs = await _execute_tool(turn["tool"], tool_input, profile, permissions, session_id, user_id)

                try:
                    preview = json.loads(obs)
                except Exception:
                    preview = {"raw": obs[:300]}

                yield _sse("tool_result", {
                    "iteration": i,
                    "tool":      turn["tool"],
                    "category":  cat,
                    "preview":   str(obs)[:350],
                })

                if cat == "action":
                    yield _sse("action_done", {"tool": turn["tool"], "result": preview})

            elif turn["tool"]:
                obs = json.dumps({"error": f"Unknown tool: {turn['tool']}"})

            memory.append({
                "thought":     turn["thought"],
                "tool":        turn["tool"],
                "input":       turn["tool_input"],
                "observation": obs,
                "iteration":   i,
            })

            if turn["done"] or i == MAX_REACT_ITERATIONS:
                break

        yield _sse("finalizing", {"message": "Writing your complete plan...", "model": last_model})

        agent_data  = await _finalize(req.task, memory, currency, language, tier_used)
        workflow_id = await _save_workflow(user_id, req.task, agent_data, currency, req.workflow_id, session_id)

        await ChatMemoryManager.save_message(
            session_id, user_id, "assistant",
            json.dumps(agent_data),
            {"type": "stream_complete", "workflow_id": workflow_id}
        )

        # Gamification
        gami = await _award_call_gamification(user_id, is_premium)

        yield _sse("complete", {
            **agent_data,
            "workflow_id":   workflow_id,
            "session_id":    session_id,
            "model_used":    last_model,
            "model_tier":    tier_used,
            "iterations":    len(memory),
            "task":          req.task,
            "quota":         quota,
            "gamification":  gami,
            "via_ad_credit": quota.get("via_ad_credit", False),
        })

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":       "no-cache",
            "X-Accel-Buffering":   "no",
            "Access-Control-Allow-Origin": "*",
        }
    )


@router.post("/chat")
@limiter.limit(AI_LIMIT)
async def agent_chat(req: AgentChatRequest, request: Request,
                     user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    language   = profile.get("language", "en")
    use_free   = not is_premium

    # ── Quota gate ──────────────────────────────────────────────────
    quota = await _check_quota(user_id, is_premium)
    if not quota["allowed"]:
        raise HTTPException(402, {
            "error":          "Daily chat limit reached",
            "show_ad":        quota.get("show_ad", True),
            "can_watch_more": quota.get("can_watch_more", True),
            "upgrade_prompt": "Watch an ad to unlock more chats, or upgrade to Premium.",
            "tier":           quota["tier"],
        })
    # ────────────────────────────────────────────────────────────────

    session_id = req.session_id
    if not session_id:
        recent_sessions = await ChatMemoryManager.list_sessions(user_id, limit=5)
        for sess in recent_sessions:
            if sess.get("workflow_id") == req.workflow_id and sess.get("is_active"):
                session_id = sess["id"]
                break

        if not session_id:
            session = await ChatMemoryManager.create_session(
                user_id,
                title      = req.title or f"Chat {datetime.now(timezone.utc).strftime('%H:%M')}",
                context    = req.context_override,
                workflow_id= req.workflow_id,
                tags       = ["chat"]
            )
            session_id = session["id"]

    session         = await ChatMemoryManager.get_session(session_id, user_id)
    session_context = session.get("summary") if session else None

    await ChatMemoryManager.auto_summarize_if_needed(session_id, user_id, ai_service)

    # ── Load history from DB (NOT from req.history — field does not exist) ──
    db_messages = await ChatMemoryManager.get_messages(
        session_id, user_id, limit=req.history_limit
    )
    history = [
        {"role": m["role"], "content": m["content"]}
        for m in db_messages if not m.get("is_summary")
    ]
    # ────────────────────────────────────────────────────────────────

    system = _chat_system(profile, session_context, language)
    history.append({"role": "user", "content": req.message})

    result = await ModelRouter.chat_with_model(
        messages=history,
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=use_free,
        max_tokens=2500,
        stream=req.stream
    )

    ai_content = result["content"]

    await ChatMemoryManager.save_message(
        session_id, user_id, "user", req.message,
        {"workflow_id": req.workflow_id}
    )
    await ChatMemoryManager.save_message(
        session_id, user_id, "assistant", ai_content,
        {"model": result["model"], "tier": result["tier"]},
        model_used=result["model"]
    )

    if session and session.get("message_count", 0) == 0:
        title_result = await ModelRouter.chat_with_model(
            messages=[{"role": "user", "content": f"Summarize this in 5 words or less: {req.message}"}],
            system="Create a very short title.",
            user=user,
            task_complexity="simple",
            prefer_free=True,
            max_tokens=20,
        )
        new_title = title_result["content"].strip()[:50]
        await ChatMemoryManager.rename_session(session_id, user_id, new_title)

    # Gamification
    gami = await _award_call_gamification(user_id, is_premium)

    return {
        "content":       ai_content,
        "session_id":    session_id,
        "model_used":    result["model"],
        "model_tier":    result["tier"],
        "message_count": (session.get("message_count", 0) + 2) if session else 2,
        "gamification":  gami,
        "via_ad_credit": quota.get("via_ad_credit", False),
    }


@router.post("/chat/stream")
@limiter.limit(AI_LIMIT)
async def agent_chat_stream(req: AgentChatRequest, request: Request,
                            user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    profile    = await supabase_service.get_profile(user_id) or {}
    language   = profile.get("language", "en")
    use_free   = not is_premium

    session_id = req.session_id
    if not session_id:
        session    = await ChatMemoryManager.create_session(
            user_id, title=req.title or "Streaming Chat", workflow_id=req.workflow_id
        )
        session_id = session["id"]

    db_messages = await ChatMemoryManager.get_messages(session_id, user_id, limit=req.history_limit)
    history = [
        {"role": m["role"], "content": m["content"]}
        for m in db_messages if not m.get("is_summary")
    ]
    history.append({"role": "user", "content": req.message})

    await ChatMemoryManager.save_message(session_id, user_id, "user", req.message)

    system = _chat_system(profile, None, language)

    async def stream_chat():
        full_response = ""
        try:
            # Quota check inside stream
            quota = await _check_quota(user_id, is_premium)
            if not quota["allowed"]:
                yield _sse("error", {
                    "message":        "Daily chat limit reached.",
                    "show_ad":        quota.get("show_ad", True),
                    "can_watch_more": quota.get("can_watch_more", True),
                })
                return

            result = await ModelRouter.chat_with_model(
                messages=history,
                system=system,
                user=user,
                task_complexity="standard",
                prefer_free=use_free,
                max_tokens=2500,
                stream=False
            )

            words = result["content"].split()
            for i, word in enumerate(words):
                chunk = word + (" " if i < len(words) - 1 else "")
                full_response += chunk
                yield _sse("token", {"content": chunk, "session_id": session_id})
                await asyncio.sleep(0.01)

            await ChatMemoryManager.save_message(
                session_id, user_id, "assistant", full_response,
                {"model": result["model"], "tier": result["tier"], "streamed": True},
                model_used=result["model"]
            )

            gami = await _award_call_gamification(user_id, is_premium)

            yield _sse("complete", {
                "content":       full_response,
                "session_id":    session_id,
                "model_used":    result["model"],
                "model_tier":    result["tier"],
                "gamification":  gami,
                "via_ad_credit": quota.get("via_ad_credit", False),
            })

        except Exception as e:
            logger.error(f"Stream error: {e}")
            yield _sse("error", {"message": str(e), "session_id": session_id})

    return StreamingResponse(
        stream_chat(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


# ═══════════════════════════════════════════════════════════════════
# CHAT SESSION MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

@router.get("/chat/sessions")
async def list_chat_sessions(
    limit:            int  = 50,
    include_archived: bool = False,
    user: dict = Depends(get_current_user)
):
    sessions = await ChatMemoryManager.list_sessions(
        user["id"], limit=limit, include_archived=include_archived
    )
    return {
        "sessions":     sessions,
        "total":        len(sessions),
        "active_count": sum(1 for s in sessions if s.get("is_active"))
    }

@router.post("/chat/sessions")
async def create_chat_session(req: ChatSessionCreate, user: dict = Depends(get_current_user)):
    session = await ChatMemoryManager.create_session(
        user["id"], title=req.title, context=req.context,
        workflow_id=req.workflow_id, tags=req.tags
    )
    return session

@router.get("/chat/sessions/{session_id}")
async def get_chat_session(session_id: str, user: dict = Depends(get_current_user)):
    session = await ChatMemoryManager.get_session(session_id, user["id"])
    if not session:
        raise HTTPException(404, "Session not found")
    messages = await ChatMemoryManager.get_messages(session_id, user["id"], limit=20)
    return {
        **session,
        "recent_messages":  messages,
        "message_preview":  [m["content"][:100] for m in messages[-3:]] if messages else []
    }

@router.get("/chat/sessions/{session_id}/messages")
async def get_session_messages(
    session_id: str,
    limit:  int = 50,
    offset: int = 0,
    user: dict = Depends(get_current_user)
):
    messages = await ChatMemoryManager.get_messages(
        session_id, user["id"], limit=limit, offset=offset
    )
    return {"messages": messages, "session_id": session_id, "has_more": len(messages) == limit}

@router.post("/chat/sessions/{session_id}/rename")
async def rename_chat_session(session_id: str, new_title: str,
                               user: dict = Depends(get_current_user)):
    success = await ChatMemoryManager.rename_session(session_id, user["id"], new_title)
    if not success:
        raise HTTPException(400, "Failed to rename session")
    return {"success": True, "session_id": session_id, "new_title": new_title}

@router.delete("/chat/sessions/{session_id}")
async def delete_chat_session(session_id: str, user: dict = Depends(get_current_user)):
    success = await ChatMemoryManager.delete_session(session_id, user["id"])
    if not success:
        raise HTTPException(400, "Failed to delete session")
    return {"success": True, "session_id": session_id}


# ═══════════════════════════════════════════════════════════════════
# DIRECT TOOL EXECUTION
# ═══════════════════════════════════════════════════════════════════

@router.post("/execute-tool")
@limiter.limit(AI_LIMIT)
async def execute_tool(req: ExecuteToolRequest, request: Request,
                       user: dict = Depends(get_current_user)):
    if req.tool not in TOOLS:
        raise HTTPException(400, {"error": f"Unknown tool: {req.tool}", "valid": list(TOOLS.keys())})

    profile     = await supabase_service.get_profile(user["id"]) or {}
    permissions = {"allow_email": True, "allow_social_post": True, "social_tokens": {}}

    raw = await _execute_tool(
        req.tool, req.input, profile, permissions, req.session_id, user["id"]
    )

    try:
        output = json.loads(raw)
    except Exception:
        output = {"result": raw}

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "tool",
            f"Executed {req.tool}",
            {"tool": req.tool, "output_preview": str(output)[:200]}
        )

    gami = await _award_call_gamification(user["id"], user.get("is_premium", False))

    return {"tool": req.tool, "output": output, "session_id": req.session_id, "gamification": gami}


@router.post("/quick")
@limiter.limit(FREE_TIER_LIMIT)
async def quick_execute(req: QuickRequest, request: Request,
                        user: dict = Depends(get_current_user_optional)):
    profile  = {}
    if user:
        profile = await supabase_service.get_profile(user["id"]) or {}

    currency = profile.get("currency", "USD")
    country  = profile.get("country", "US")
    language = req.language or profile.get("language", "en")

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": req.task}],
        system=(
            f"You are APEX for users in {country}. "
            f"TASK: {req.task}. Produce COMPLETE ready-to-use output. "
            f"Be specific to {country}. Use {currency}. Respond in {language}."
        ),
        user=user or {"is_premium": False},
        task_complexity="simple",
        prefer_free=True,
        max_tokens=1800,
    )

    return {
        "output":     result["content"],
        "task":       req.task,
        "model_used": result["model"],
        "model_tier": result["tier"],
        "language":   language,
    }


@router.post("/analyze")
@limiter.limit(AI_LIMIT)
async def analyze(req: AnalyzeRequest, request: Request,
                  user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    is_premium = user.get("is_premium", False)

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": f"Analyze and improve:\n\n{req.content}"}],
        system=(
            f"Improvement engine. Goal: {req.goal}. "
            f"Context: {req.context or 'general'}. "
            f"Currency: {profile.get('currency','USD')}. "
            'Return JSON: {"issues":[...],"improved_version":"FULL REWRITE","key_changes":[...],'
            '"score_before":0,"score_after":0}'
        ),
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=2000,
    )

    # ── FIX: raw is at the same indent level as result, NOT inside the call ──
    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        output = json.loads(raw)
    except Exception:
        output = {"improved_version": result["content"], "issues": [], "key_changes": []}

    gami = await _award_call_gamification(user["id"], is_premium)

    return {
        "analysis":   output,
        "model_used": result["model"],
        "model_tier": result["tier"],
        "gamification": gami,
    }


@router.post("/scan")
@limiter.limit(AI_LIMIT)
async def scan(req: ScanRequest, request: Request,
               user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"]) or {}

    if req.location:
        profile["country"] = req.location

    opps = await scraper_engine.find_opportunities(
        profile=profile, max_results=20, score_with_ai=True,
    )

    return {
        "opportunities": opps,
        "total":         len(opps),
        "location":      profile.get("country", "global"),
        "scanned_at":    datetime.now(timezone.utc).isoformat(),
    }


# ═══════════════════════════════════════════════════════════════════
# GROWTH AI ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

class OpportunitySearchRequest(BaseModel):
    query:         Optional[str]       = None
    types:         Optional[List[str]] = None
    max_results:   int                 = 20
    score_with_ai: bool                = True
    session_id:    Optional[str]       = None

class MarketAnalysisRequest(BaseModel):
    industry: str
    skill:    Optional[str] = None
    location: Optional[str] = None

class DailyPlanRequest(BaseModel):
    goal:       Optional[str] = None
    timeframe:  Optional[str] = "today"
    session_id: Optional[str] = None

class ScoreOpportunityRequest(BaseModel):
    opportunity: Dict[str, Any]
    session_id:  Optional[str] = None

class FollowUpRequest(BaseModel):
    context:    str
    session_id: Optional[str] = None

class EarningInsightRequest(BaseModel):
    earnings:   List[Dict[str, Any]]
    session_id: Optional[str] = None

class MilestoneRequest(BaseModel):
    monthly_income: Optional[float] = None
    session_id:     Optional[str]   = None


@router.post("/opportunities/search")
@limiter.limit(AI_LIMIT)
async def search_opportunities(req: OpportunitySearchRequest, request: Request,
                                user: dict = Depends(get_current_user)):
    profile = await supabase_service.get_profile(user["id"]) or {}
    query   = req.query or " ".join((profile.get("current_skills") or [])[:3])

    opps = await scraper_engine.find_opportunities(
        profile=profile, opp_types=req.types or ["jobs", "hustles", "freelance"],
        query=query, max_results=req.max_results, score_with_ai=req.score_with_ai,
    )

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Found {len(opps)} opportunities for: {query}",
            {"type": "opportunity_search", "count": len(opps), "query": query}
        )

    return {"total": len(opps), "opportunities": opps, "query": query}


@router.get("/opportunities/trending")
async def get_trending_opportunities(
    category: Optional[str] = None,
    limit:    int           = 20,
    user: dict = Depends(get_current_user_optional),
):
    opps = await scraper_engine.get_trending(category=category, limit=limit)
    return {"total": len(opps), "opportunities": opps, "category": category}


@router.post("/market-analysis")
@limiter.limit(AI_LIMIT)
async def market_analysis(req: MarketAnalysisRequest, request: Request,
                           user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    currency   = profile.get("currency", "USD")
    country    = req.location or profile.get("country", "US")
    is_premium = user.get("is_premium", False)

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

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content":
                   f"Analyse market for: {req.industry}" + (f", skill: {req.skill}" if req.skill else "")}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=800,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"summary": result["content"]}

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**data, "industry": req.industry, "skill": req.skill,
            "model_used": result["model"], "model_tier": result["tier"], "gamification": gami}


@router.post("/daily-plan")
@limiter.limit(AI_LIMIT)
async def create_daily_plan(req: DailyPlanRequest, request: Request,
                             user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    currency   = profile.get("currency", "USD")
    country    = profile.get("country",  "US")
    stage      = profile.get("stage",    "survival")
    skills     = ", ".join(profile.get("current_skills", []) or ["not set"])
    income     = profile.get("monthly_income", 0)
    goal       = req.goal or f"Grow my income from {currency} {income:,.0f}/mo"
    is_premium = user.get("is_premium", False)

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

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": f"Create my daily plan. Goal: {goal}. Timeframe: {req.timeframe}"}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=1500,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan = json.loads(raw)
    except Exception:
        plan = {"overview": result["content"], "daily_tasks": []}

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

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Created daily plan: {plan.get('overview', 'Plan created')}",
            {"type": "daily_plan", "goal": goal}
        )

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**plan, "goal": goal, "model_used": result["model"],
            "model_tier": result["tier"], "gamification": gami}


@router.post("/score-opportunity")
@limiter.limit(AI_LIMIT)
async def score_opportunity(req: ScoreOpportunityRequest, request: Request,
                             user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    opp        = req.opportunity
    currency   = profile.get("currency", "USD")
    country    = profile.get("country",  "US")
    skills     = profile.get("current_skills", [])
    stage      = profile.get("stage", "survival")
    is_premium = user.get("is_premium", False)

    system = (
        f"You are an opportunity analyst. User: {country}, {stage} stage, "
        f"skills: {skills}, currency: {currency}. "
        "Score this opportunity for them. Return ONLY valid JSON: "
        '{"match_score":0-100,"summary":"2-sentence personalised summary",'
        '"risk_level":"low|medium|high","action_steps":["Step 1","Step 2","Step 3"],'
        '"time_to_first_earning":"e.g. 1-2 weeks",'
        '"potential_monthly":0,"why_good_fit":"...","why_might_not_fit":"..."}'
    )

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": f"Score this opportunity:\n{json.dumps(opp, indent=2)}"}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=600,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"match_score": 50, "summary": result["content"]}

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Scored opportunity: {opp.get('title', 'Unknown')} - Match: {data.get('match_score', 'N/A')}%",
            {"type": "opportunity_score", "match_score": data.get("match_score")}
        )

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**data, "opportunity_title": opp.get("title", ""),
            "model_used": result["model"], "model_tier": result["tier"], "gamification": gami}


@router.post("/follow-up-plan")
@limiter.limit(AI_LIMIT)
async def create_follow_up_plan(req: FollowUpRequest, request: Request,
                                 user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    name       = profile.get("full_name", "User")
    is_premium = user.get("is_premium", False)

    system = (
        f"You are an outreach expert for {name}. "
        "Create a complete follow-up sequence with FULL message text. "
        "Return ONLY valid JSON: "
        '{"follow_up_1":{"when":"e.g. 3 days after","subject":"...","message":"FULL MESSAGE TEXT"},'
        '"follow_up_2":{"when":"...","subject":"...","message":"FULL MESSAGE TEXT"},'
        '"if_no_response":"what to do if still no reply after follow-up 2",'
        '"if_rejected":"how to respond gracefully to a rejection and pivot",'
        '"if_interested":"next steps if they respond positively"}'
    )

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": f"Create follow-up plan for: {req.context}"}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=1200,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        plan = json.loads(raw)
    except Exception:
        plan = {"follow_up_1": {"message": result["content"]}}

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Created follow-up plan for: {req.context[:50]}...",
            {"type": "follow_up_plan", "context": req.context}
        )

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**plan, "context": req.context, "model_used": result["model"],
            "model_tier": result["tier"], "gamification": gami}


@router.post("/earnings-insight")
@limiter.limit(AI_LIMIT)
async def earnings_insight(req: EarningInsightRequest, request: Request,
                            user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    currency   = profile.get("currency", "USD")
    goal       = profile.get("target_monthly_income", 0)
    is_premium = user.get("is_premium", False)

    system = (
        f"You are a financial analyst. Currency: {currency}. Income goal: {currency} {goal:,.0f}/mo. "
        "Analyse these earnings and give actionable insight. Return ONLY valid JSON: "
        '{"growth_rate":"e.g. +23% MoM","top_source":"...","monthly_trend":"growing|stable|declining",'
        '"total_analysed":0,"average_monthly":0,"insight":"3-sentence analysis",'
        '"next_milestone":"...","recommended_action":"single most impactful next step",'
        '"months_to_goal":0}'
    )

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": f"Analyse these earnings:\n{json.dumps(req.earnings, indent=2)}"}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=700,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"insight": result["content"]}

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Earnings insight: {data.get('insight', 'Analysis complete')[:100]}...",
            {"type": "earnings_insight", "growth_rate": data.get("growth_rate")}
        )

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**data, "model_used": result["model"], "model_tier": result["tier"], "gamification": gami}


@router.post("/milestone-check")
@limiter.limit(AI_LIMIT)
async def milestone_check(req: MilestoneRequest, request: Request,
                           user: dict = Depends(get_current_user)):
    profile    = await supabase_service.get_profile(user["id"]) or {}
    currency   = profile.get("currency", "USD")
    stage      = profile.get("stage",    "survival")
    income     = req.monthly_income or profile.get("monthly_income", 0)
    target     = profile.get("target_monthly_income", 0)
    skills     = profile.get("current_skills", [])
    country    = profile.get("country", "US")
    is_premium = user.get("is_premium", False)

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

    result = await ModelRouter.chat_with_model(
        messages=[{"role": "user", "content": "Analyse my wealth stage progress."}],
        system=system,
        user=user,
        task_complexity="standard",
        prefer_free=not is_premium,
        max_tokens=700,
    )

    raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        data = json.loads(raw)
    except Exception:
        data = {"current_stage": stage, "action_to_advance": result["content"]}

    if req.session_id:
        await ChatMemoryManager.save_message(
            req.session_id, user["id"], "assistant",
            f"Milestone check: {data.get('current_stage', stage)} stage, {data.get('progress_to_next', 'N/A')}% to next",
            {"type": "milestone_check", "current_stage": data.get("current_stage", stage)}
        )

    gami = await _award_call_gamification(user["id"], is_premium)

    return {**data, "model_used": result["model"], "model_tier": result["tier"], "gamification": gami}


# ═══════════════════════════════════════════════════════════════════
# UTILITY ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.get("/quota")
async def get_quota(user: dict = Depends(get_current_user)):
    user_id    = user["id"]
    is_premium = user.get("is_premium", False)
    limit      = PREMIUM_DAILY_RUNS if is_premium else DEFAULT_DAILY_RUNS
    today      = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    key        = f"agent_runs:{user_id}:{today}"

    try:
        sb   = supabase_service.client
        row  = sb.table("agent_run_quota").select("runs_used").eq("quota_key", key).maybe_single().execute()
        used = row.data["runs_used"] if row.data else 0

        ad_state = await AdManager.get_credits(user_id) if not is_premium else {}

        return {
            "runs_used":        used,
            "runs_limit":       limit,
            "runs_remaining":   limit - used,
            "tier":             "premium" if is_premium else "free",
            "ad_credits":       ad_state.get("credits_available", 0) if not is_premium else None,
            "show_ad_prompt":   (used >= limit and not is_premium and ad_state.get("can_watch_more", True)),
        }
    except Exception:
        return {"runs_used": 0, "runs_limit": limit, "runs_remaining": limit,
                "tier": "premium" if is_premium else "free", "ad_credits": 0}


@router.get("/tools")
async def list_tools():
    return {
        "total": len(TOOLS),
        "categories": {
            cat: [{"name": n, "description": m["description"],
                   "free_compatible": m.get("free_compatible", True)}
                  for n, m in TOOLS.items() if m["category"] == cat]
            for cat in ["thinking", "research", "action", "document", "intelligence"]
        },
    }


@router.get("/models")
async def list_models(user: dict = Depends(get_current_user)):
    is_premium = user.get("is_premium", False)
    return {
        "tier":    "premium" if is_premium else "free",
        "models": {
            "free":    FREE_MODELS if not is_premium else {**FREE_MODELS, "note": "Also available as fallback"},
            "premium": PREMIUM_MODELS if is_premium else {"message": "Upgrade to access premium models"},
        },
        "current_limits": {
            "daily_runs":       PREMIUM_DAILY_RUNS if is_premium else DEFAULT_DAILY_RUNS,
            "max_chat_history": MAX_CHAT_HISTORY,
            "ad_credits_per_day": MAX_AD_CREDITS_PER_DAY if not is_premium else 0,
        },
    }
