"""
backend/services/token_service.py
APEX Token Engine — Production v1.0

Every APEX action costs tokens (Manus-style execution metering).
Free  users : 500 tokens / day
Premium     : unlimited (10,000 ceiling — effectively infinite)
Rewarded ad : +100 tokens per watch, max 5 ads/day

All calls are async-safe.  Falls back gracefully if DB is unavailable.
"""

import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

# ── Quotas ──────────────────────────────────────────────────────────────────
FREE_DAILY_TOKENS    = 500
PREMIUM_DAILY_TOKENS = 10_000
AD_TOKENS_PER_WATCH  = 100
MAX_AD_WATCHES_DAY   = 5

# ── Per-tool token costs ─────────────────────────────────────────────────────
TOOL_TOKEN_COSTS: Dict[str, int] = {
    # ── Research ──────────────────────────────────────────────────────────
    "web_search":                15,
    "deep_research":             45,
    "find_freelance_jobs":       15,
    "find_partners":             15,
    "find_free_resources":       15,
    "scan_opportunities":        15,
    "scrape_live_opportunities": 15,
    "market_research":           15,
    # ── Thinking / AI generation ───────────────────────────────────────────
    "write_content":             10,
    "create_plan":               10,
    "estimate_income":           10,
    "generate_ideas":            10,
    "breakdown_task":            10,
    "create_template":           10,
    "write_cold_outreach":       10,
    "build_profile_content":     10,
    "summarize_chat":            10,
    "score_opportunity":         10,
    "analyze_market_trends":     10,
    "create_daily_action_plan":  10,
    "create_follow_up_plan":     10,
    "track_earnings_insight":    10,
    "growth_milestone_check":    10,
    # ── Documents ─────────────────────────────────────────────────────────
    "generate_contract":         25,
    "generate_invoice":          25,
    "generate_proposal":         25,
    "generate_pitch_deck":       25,
    # ── Actions ───────────────────────────────────────────────────────────
    "send_email":                10,
    "post_twitter":              10,
    "post_linkedin":             10,
    "schedule_post":             10,
    # ── Browser automation ────────────────────────────────────────────────
    "browser_navigate":          20,
    "browser_click":             10,
    "browser_fill":              10,
    "browser_scroll":             5,
    "browser_wait":               5,
    "browser_extract":           10,
    "browser_action":            10,
    "screenshot_analyze":        12,
    # ── Internal pipeline steps ───────────────────────────────────────────
    "_reasoning_step":           10,
    "_final_synthesis":          30,
}


class TokenService:
    """Stateless token service — uses Supabase as the store."""

    @staticmethod
    def _today() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # ── Lazy import to avoid circular dependency ─────────────────────────────
    @staticmethod
    def _db():
        from services.supabase_service import supabase_service
        return supabase_service.client

    # ────────────────────────────────────────────────────────────────────────
    # get_state
    # ────────────────────────────────────────────────────────────────────────
    @staticmethod
    async def get_state(user_id: str, is_premium: bool = False) -> Dict[str, Any]:
        today       = TokenService._today()
        daily_limit = PREMIUM_DAILY_TOKENS if is_premium else FREE_DAILY_TOKENS
        try:
            row = (
                TokenService._db()
                .table("apex_token_quota")
                .select("*")
                .eq("user_id", user_id)
                .eq("quota_date", today)
                .maybe_single()
                .execute()
            )
            data       = row.data or {}
            used       = int(data.get("tokens_used", 0))
            ad_bonus   = int(data.get("ad_bonus_tokens", 0))
            ad_watches = int(data.get("ad_watches_today", 0))
            total      = daily_limit + ad_bonus
            remaining  = max(0, total - used)
            return {
                "tokens_used":        used,
                "tokens_remaining":   remaining,
                "tokens_daily_limit": daily_limit,
                "ad_bonus_tokens":    ad_bonus,
                "ad_watches_today":   ad_watches,
                "ad_watches_left":    max(0, MAX_AD_WATCHES_DAY - ad_watches),
                "total_available":    total,
                "percent_used":       int(used / total * 100) if total > 0 else 0,
                "is_premium":         is_premium,
                "exhausted":          remaining == 0,
                "can_watch_ad":       (not is_premium) and (ad_watches < MAX_AD_WATCHES_DAY),
            }
        except Exception as e:
            logger.error("TokenService.get_state: %s", e)
            # Fail open — never block the user on a DB error
            return {
                "tokens_used": 0, "tokens_remaining": daily_limit,
                "tokens_daily_limit": daily_limit, "ad_bonus_tokens": 0,
                "ad_watches_today": 0, "ad_watches_left": MAX_AD_WATCHES_DAY,
                "total_available": daily_limit, "percent_used": 0,
                "is_premium": is_premium, "exhausted": False,
                "can_watch_ad": not is_premium,
            }

    # ────────────────────────────────────────────────────────────────────────
    # deduct
    # ────────────────────────────────────────────────────────────────────────
    @staticmethod
    async def deduct(
        user_id: str,
        tool_name: str,
        is_premium: bool = False,
        override_cost: Optional[int] = None,
    ) -> Dict[str, Any]:
        cost        = override_cost if override_cost is not None else TOOL_TOKEN_COSTS.get(tool_name, 10)
        today       = TokenService._today()
        daily_limit = PREMIUM_DAILY_TOKENS if is_premium else FREE_DAILY_TOKENS

        if is_premium:
            # Premium — still deduct for analytics but always allow
            try:
                TokenService._db().table("apex_token_quota").upsert(
                    {
                        "user_id":    user_id,
                        "quota_date": today,
                        "tokens_used": TokenService._db()
                            .rpc("increment_tokens", {"uid": user_id, "d": today, "amt": cost})
                            .execute().data or cost,
                        "daily_limit": daily_limit,
                        "updated_at": datetime.now(timezone.utc).isoformat(),
                    },
                    on_conflict="user_id,quota_date",
                ).execute()
            except Exception:
                pass  # Never block premium users
            return {"allowed": True, "cost": cost, "remaining": PREMIUM_DAILY_TOKENS, "exhausted": False}

        try:
            row = (
                TokenService._db()
                .table("apex_token_quota")
                .select("tokens_used,ad_bonus_tokens,ad_watches_today")
                .eq("user_id", user_id)
                .eq("quota_date", today)
                .maybe_single()
                .execute()
            )
            data       = row.data or {}
            used       = int(data.get("tokens_used", 0))
            ad_bonus   = int(data.get("ad_bonus_tokens", 0))
            ad_watches = int(data.get("ad_watches_today", 0))
            total      = daily_limit + ad_bonus
            remaining  = max(0, total - used)

            if remaining < cost:
                return {
                    "allowed":     False,
                    "cost":        cost,
                    "remaining":   remaining,
                    "exhausted":   True,
                    "can_watch_ad": ad_watches < MAX_AD_WATCHES_DAY,
                    "message":     f"Only {remaining} tokens left. Watch an ad for +{AD_TOKENS_PER_WATCH} tokens.",
                }

            new_used = used + cost
            TokenService._db().table("apex_token_quota").upsert(
                {
                    "user_id":          user_id,
                    "quota_date":       today,
                    "tokens_used":      new_used,
                    "ad_bonus_tokens":  ad_bonus,
                    "ad_watches_today": ad_watches,
                    "daily_limit":      daily_limit,
                    "updated_at":       datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="user_id,quota_date",
            ).execute()

            new_remaining = max(0, total - new_used)
            return {
                "allowed":      True,
                "cost":         cost,
                "remaining":    new_remaining,
                "used":         new_used,
                "exhausted":    new_remaining == 0,
                "percent_used": int(new_used / total * 100) if total > 0 else 0,
            }
        except Exception as e:
            logger.error("TokenService.deduct: %s", e)
            # Fail open — never silently block on DB error
            return {"allowed": True, "cost": cost, "remaining": 999, "exhausted": False}

    # ────────────────────────────────────────────────────────────────────────
    # grant_ad_tokens
    # ────────────────────────────────────────────────────────────────────────
    @staticmethod
    async def grant_ad_tokens(user_id: str) -> Dict[str, Any]:
        today = TokenService._today()
        try:
            row = (
                TokenService._db()
                .table("apex_token_quota")
                .select("*")
                .eq("user_id", user_id)
                .eq("quota_date", today)
                .maybe_single()
                .execute()
            )
            data       = row.data or {}
            ad_watches = int(data.get("ad_watches_today", 0))
            if ad_watches >= MAX_AD_WATCHES_DAY:
                return {
                    "granted":            False,
                    "reason":             f"Maximum {MAX_AD_WATCHES_DAY} ads per day reached.",
                    "come_back_tomorrow": True,
                    "show_subscribe":     True,
                    "ads_remaining":      0,
                }
            new_bonus   = int(data.get("ad_bonus_tokens", 0)) + AD_TOKENS_PER_WATCH
            new_watches = ad_watches + 1
            TokenService._db().table("apex_token_quota").upsert(
                {
                    "user_id":          user_id,
                    "quota_date":       today,
                    "tokens_used":      int(data.get("tokens_used", 0)),
                    "ad_bonus_tokens":  new_bonus,
                    "ad_watches_today": new_watches,
                    "daily_limit":      FREE_DAILY_TOKENS,
                    "updated_at":       datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="user_id,quota_date",
            ).execute()
            ads_remaining = MAX_AD_WATCHES_DAY - new_watches
            return {
                "granted":          True,
                "tokens_granted":   AD_TOKENS_PER_WATCH,
                "ad_bonus_total":   new_bonus,
                "ad_watches_today": new_watches,
                "ads_remaining":    ads_remaining,
                "show_subscribe":   ads_remaining == 0,
                "message": (
                    f"🎉 +{AD_TOKENS_PER_WATCH} APEX tokens! "
                    f"{ads_remaining} ad{'s' if ads_remaining != 1 else ''} left today."
                ),
            }
        except Exception as e:
            logger.error("TokenService.grant_ad_tokens: %s", e)
            return {"granted": False, "reason": str(e)}

    @staticmethod
    def cost_of(tool_name: str) -> int:
        return TOOL_TOKEN_COSTS.get(tool_name, 10)


# ── Singleton ────────────────────────────────────────────────────────────────
token_service = TokenService()
