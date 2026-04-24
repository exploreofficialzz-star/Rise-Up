"""
backend/services/token_service.py  — RiseUp Token Engine v2.0
"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

FREE_DAILY_TOKENS    = 500
PREMIUM_DAILY_TOKENS = 10_000
ADS_PER_REDEMPTION   = 2
MAX_REDEMPTIONS_DAY  = 3
MAX_AD_WATCHES_DAY   = 20
LOCK_HOURS_AFTER_MAX = 4
AD_TOKENS_SCHEDULE   = [40, 30, 20]

TOOL_TOKEN_COSTS: Dict[str, int] = {
    "chat_message": 10, "summarize_chat": 10,
    "market_pulse_check": 5, "scan_opportunities": 15,
    "web_search": 15, "deep_research": 45,
    "scrape_live_opportunities": 15, "analyze_market_trends": 10,
    "score_opportunity": 10, "workflow_plan": 20,
    "create_plan": 20, "generate_ideas": 10,
    "write_content": 10, "write_cold_outreach": 10,
    "build_profile_content": 10, "create_template": 10,
    "estimate_income": 10, "breakdown_task": 10,
    "create_daily_action_plan": 10, "create_follow_up_plan": 10,
    "track_earnings_insight": 10, "growth_milestone_check": 10,
    "browser_navigate": 15, "browser_click": 10,
    "browser_fill": 10, "browser_scroll": 5,
    "browser_wait": 5, "browser_extract": 10,
    "browser_action": 15, "screenshot_analyze": 12,
    "code_execute": 50, "code_run_project": 100,
    "file_process": 25, "generate_document": 25,
    "generate_proposal": 25, "generate_invoice": 25,
    "send_email": 10, "post_social": 10,
    "schedule_post": 10, "_reasoning_step": 10,
    "_final_synthesis": 30, "find_freelance_jobs": 15,
    "find_partners": 15, "find_free_resources": 15,
    "market_research": 15,
}


class TokenService:
    @staticmethod
    def _today() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%d")

    @staticmethod
    def _db():
        from services.supabase_service import supabase_service
        return supabase_service.client

    @staticmethod
    async def get_state(user_id: str, is_premium: bool = False) -> Dict[str, Any]:
        today = TokenService._today()
        daily_limit = PREMIUM_DAILY_TOKENS if is_premium else FREE_DAILY_TOKENS
        try:
            row = (TokenService._db().table("apex_token_quota").select("*")
                   .eq("user_id", user_id).eq("quota_date", today).maybe_single().execute())
            data        = (row.data if row is not None else None) or {}
            used        = int(data.get("tokens_used", 0))
            ad_bonus    = int(data.get("ad_bonus_tokens", 0))
            ad_watches  = int(data.get("ad_watches_today", 0))
            redemptions = int(data.get("ad_redemptions_today", 0))
            lock_until  = data.get("lock_until_iso")
            total       = daily_limit + ad_bonus
            remaining   = max(0, total - used)

            locked, lock_mins = False, 0
            if lock_until:
                try:
                    lock_dt = datetime.fromisoformat(lock_until)
                    now_dt  = datetime.now(timezone.utc)
                    if lock_dt > now_dt:
                        locked = True
                        lock_mins = int((lock_dt - now_dt).total_seconds() / 60)
                except Exception:
                    pass

            next_reward = AD_TOKENS_SCHEDULE[redemptions] if redemptions < len(AD_TOKENS_SCHEDULE) else 0
            return {
                "tokens_used": used, "tokens_remaining": remaining,
                "tokens_daily_limit": daily_limit, "ad_bonus_tokens": ad_bonus,
                "ad_watches_today": ad_watches, "ad_redemptions_today": redemptions,
                "total_available": total, "percent_used": int(used / total * 100) if total > 0 else 0,
                "is_premium": is_premium, "exhausted": remaining == 0,
                "can_redeem_ads": not is_premium and not locked and redemptions < MAX_REDEMPTIONS_DAY and ad_watches < MAX_AD_WATCHES_DAY,
                "ads_per_redemption": ADS_PER_REDEMPTION, "next_reward_tokens": next_reward,
                "redemptions_left": max(0, MAX_REDEMPTIONS_DAY - redemptions),
                "locked": locked, "lock_minutes_left": lock_mins,
                "day_locked": ad_watches >= MAX_AD_WATCHES_DAY,
            }
        except Exception as e:
            logger.error("get_state: %s", e)
            return {"tokens_remaining": daily_limit, "exhausted": False,
                    "can_redeem_ads": not is_premium, "next_reward_tokens": AD_TOKENS_SCHEDULE[0],
                    "locked": False, "day_locked": False, "tokens_daily_limit": daily_limit}

    @staticmethod
    async def deduct(user_id: str, tool_name: str, is_premium: bool = False, override_cost: Optional[int] = None) -> Dict[str, Any]:
        cost        = override_cost if override_cost is not None else TOOL_TOKEN_COSTS.get(tool_name, 10)
        today       = TokenService._today()
        daily_limit = PREMIUM_DAILY_TOKENS if is_premium else FREE_DAILY_TOKENS

        if is_premium:
            try:
                row = (TokenService._db().table("apex_token_quota").select("tokens_used")
                       .eq("user_id", user_id).eq("quota_date", today).maybe_single().execute())
                used = int(((row.data if row is not None else None) or {}).get("tokens_used", 0))
                TokenService._db().table("apex_token_quota").upsert(
                    {"user_id": user_id, "quota_date": today, "tokens_used": used + cost,
                     "daily_limit": daily_limit, "updated_at": datetime.now(timezone.utc).isoformat()},
                    on_conflict="user_id,quota_date").execute()
            except Exception:
                pass
            return {"allowed": True, "cost": cost, "remaining": PREMIUM_DAILY_TOKENS, "exhausted": False}

        try:
            row = (TokenService._db().table("apex_token_quota")
                   .select("tokens_used,ad_bonus_tokens,ad_watches_today,ad_redemptions_today")
                   .eq("user_id", user_id).eq("quota_date", today).maybe_single().execute())
            data        = (row.data if row is not None else None) or {}
            used        = int(data.get("tokens_used", 0))
            ad_bonus    = int(data.get("ad_bonus_tokens", 0))
            ad_watches  = int(data.get("ad_watches_today", 0))
            redemptions = int(data.get("ad_redemptions_today", 0))
            total       = daily_limit + ad_bonus
            remaining   = max(0, total - used)

            if remaining < cost:
                next_reward = AD_TOKENS_SCHEDULE[redemptions] if redemptions < len(AD_TOKENS_SCHEDULE) else 0
                return {
                    "allowed": False, "cost": cost, "remaining": remaining,
                    "exhausted": True, "next_reward_tokens": next_reward,
                    "can_redeem_ads": ad_watches < MAX_AD_WATCHES_DAY and redemptions < MAX_REDEMPTIONS_DAY,
                    "day_locked": ad_watches >= MAX_AD_WATCHES_DAY,
                }

            TokenService._db().table("apex_token_quota").upsert(
                {"user_id": user_id, "quota_date": today, "tokens_used": used + cost,
                 "ad_bonus_tokens": ad_bonus, "ad_watches_today": ad_watches,
                 "ad_redemptions_today": redemptions, "daily_limit": daily_limit,
                 "updated_at": datetime.now(timezone.utc).isoformat()},
                on_conflict="user_id,quota_date").execute()

            new_remaining = max(0, total - used - cost)
            return {"allowed": True, "cost": cost, "remaining": new_remaining,
                    "exhausted": new_remaining == 0}
        except Exception as e:
            logger.error("deduct: %s", e)
            return {"allowed": True, "cost": cost, "remaining": 999, "exhausted": False}

    @staticmethod
    async def record_ad_watch(user_id: str) -> Dict[str, Any]:
        today = TokenService._today()
        try:
            row = (TokenService._db().table("apex_token_quota").select("*")
                   .eq("user_id", user_id).eq("quota_date", today).maybe_single().execute())
            data        = (row.data if row is not None else None) or {}
            ad_watches  = int(data.get("ad_watches_today", 0))
            redemptions = int(data.get("ad_redemptions_today", 0))
            if ad_watches >= MAX_AD_WATCHES_DAY:
                return {"recorded": False, "day_locked": True}
            new_watches  = ad_watches + 1
            ads_in_cycle = new_watches - (redemptions * ADS_PER_REDEMPTION)
            TokenService._db().table("apex_token_quota").upsert(
                {"user_id": user_id, "quota_date": today, "ad_watches_today": new_watches,
                 "updated_at": datetime.now(timezone.utc).isoformat()},
                on_conflict="user_id,quota_date").execute()
            next_reward = AD_TOKENS_SCHEDULE[redemptions] if redemptions < len(AD_TOKENS_SCHEDULE) else 0
            return {
                "recorded": True, "ad_watches_today": new_watches,
                "ads_in_cycle": ads_in_cycle,
                "redemption_ready": ads_in_cycle >= ADS_PER_REDEMPTION and redemptions < MAX_REDEMPTIONS_DAY,
                "next_reward_tokens": next_reward,
                "ads_needed": max(0, ADS_PER_REDEMPTION - ads_in_cycle),
                "day_locked": new_watches >= MAX_AD_WATCHES_DAY,
            }
        except Exception as e:
            logger.error("record_ad_watch: %s", e)
            return {"recorded": False, "error": str(e)}

    @staticmethod
    async def claim_ad_redemption(user_id: str) -> Dict[str, Any]:
        today = TokenService._today()
        try:
            row = (TokenService._db().table("apex_token_quota").select("*")
                   .eq("user_id", user_id).eq("quota_date", today).maybe_single().execute())
            data        = (row.data if row is not None else None) or {}
            ad_watches  = int(data.get("ad_watches_today", 0))
            redemptions = int(data.get("ad_redemptions_today", 0))
            ad_bonus    = int(data.get("ad_bonus_tokens", 0))

            if redemptions >= MAX_REDEMPTIONS_DAY:
                return {"granted": False, "locked": True}
            if ad_watches < (redemptions + 1) * ADS_PER_REDEMPTION:
                return {"granted": False, "ads_still_needed": ((redemptions + 1) * ADS_PER_REDEMPTION) - ad_watches}

            reward          = AD_TOKENS_SCHEDULE[redemptions] if redemptions < len(AD_TOKENS_SCHEDULE) else 0
            new_redemptions = redemptions + 1
            new_bonus       = ad_bonus + reward
            lock_until_iso  = None
            if new_redemptions >= MAX_REDEMPTIONS_DAY:
                lock_until_iso = (datetime.now(timezone.utc) + timedelta(hours=LOCK_HOURS_AFTER_MAX)).isoformat()

            TokenService._db().table("apex_token_quota").upsert(
                {"user_id": user_id, "quota_date": today, "ad_bonus_tokens": new_bonus,
                 "ad_watches_today": ad_watches, "ad_redemptions_today": new_redemptions,
                 "lock_until_iso": lock_until_iso, "daily_limit": FREE_DAILY_TOKENS,
                 "updated_at": datetime.now(timezone.utc).isoformat()},
                on_conflict="user_id,quota_date").execute()

            redemptions_left = max(0, MAX_REDEMPTIONS_DAY - new_redemptions)
            return {
                "granted": True, "tokens_granted": reward, "ad_bonus_total": new_bonus,
                "redemptions_left": redemptions_left,
                "locked": new_redemptions >= MAX_REDEMPTIONS_DAY,
                "lock_hours": LOCK_HOURS_AFTER_MAX if new_redemptions >= MAX_REDEMPTIONS_DAY else 0,
                "day_locked": ad_watches >= MAX_AD_WATCHES_DAY,
                "show_subscribe": redemptions_left == 0,
                "message": f"🎉 +{reward} tokens! " + (f"{redemptions_left} reward(s) left today." if redemptions_left else "Come back in 4h or subscribe 🚀"),
            }
        except Exception as e:
            logger.error("claim_ad_redemption: %s", e)
            return {"granted": False, "error": str(e)}

    @staticmethod
    def cost_of(tool_name: str) -> int:
        return TOOL_TOKEN_COSTS.get(tool_name, 10)


token_service = TokenService()
