"""Supabase database service — lazy-initialized singleton client"""
import logging
from typing import Optional

from supabase import create_client, Client
from config import settings

logger = logging.getLogger(__name__)

# ── Lazy singleton clients ───────────────────────────────────
_service_client: Optional[Client] = None
_anon_client: Optional[Client] = None


def get_supabase() -> Client:
    """Service-role client — full DB access (server-side only)"""
    global _service_client
    if _service_client is None:
        _service_client = create_client(
            settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY
        )
    return _service_client


def get_supabase_anon() -> Client:
    """Anon client — used for auth operations"""
    global _anon_client
    if _anon_client is None:
        _anon_client = create_client(
            settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY
        )
    return _anon_client


class SupabaseService:
    """High-level async wrapper around the Supabase Python client."""

    @property
    def db(self) -> Client:
        return get_supabase()

    @property
    def client(self) -> Client:
        """Alias for self.db — workflow.py and other routers may use .client directly."""
        return get_supabase()

    # ── Profiles ──────────────────────────────────────────────
    async def get_profile(self, user_id: str) -> dict:
        try:
            res = self.db.table("profiles").select("*").eq("id", user_id).single().execute()
            return res.data or {}
        except Exception as e:
            logger.warning(f"get_profile {user_id}: {e}")
            return {}

    async def update_profile(self, user_id: str, data: dict) -> dict:
        res = self.db.table("profiles").update(data).eq("id", user_id).execute()
        return res.data[0] if res.data else {}

    async def upsert_profile(self, user_id: str, data: dict) -> dict:
        data["id"] = user_id
        res = self.db.table("profiles").upsert(data).execute()
        return res.data[0] if res.data else {}

    # ── Conversations ──────────────────────────────────────────
    async def create_conversation(self, user_id: str, title: str = "New Chat") -> dict:
        res = self.db.table("conversations").insert(
            {"user_id": user_id, "title": title}
        ).execute()
        return res.data[0] if res.data else {}

    async def get_conversations(self, user_id: str, limit: int = 20) -> list:
        res = (
            self.db.table("conversations")
            .select("*")
            .eq("user_id", user_id)
            .order("updated_at", desc=True)
            .limit(limit)
            .execute()
        )
        return res.data or []

    async def save_message(
        self,
        conversation_id: str,
        user_id: str,
        role: str,
        content: str,
        ai_model: str = None,
        metadata: dict = None,
    ) -> dict:
        res = self.db.table("messages").insert({
            "conversation_id": conversation_id,
            "user_id": user_id,
            "role": role,
            "content": content,
            "ai_model": ai_model,
            "metadata": metadata or {},
        }).execute()
        try:
            self.db.rpc("increment_message_count", {"conv_id": conversation_id}).execute()
        except Exception:
            pass
        return res.data[0] if res.data else {}

    async def get_messages(self, conversation_id: str, limit: int = 50) -> list:
        res = (
            self.db.table("messages")
            .select("*")
            .eq("conversation_id", conversation_id)
            .order("created_at", desc=False)
            .limit(limit)
            .execute()
        )
        return res.data or []

    # ── Tasks ──────────────────────────────────────────────────
    async def create_tasks_bulk(self, user_id: str, tasks: list) -> list:
        for t in tasks:
            t["user_id"] = user_id
        res = self.db.table("tasks").insert(tasks).execute()
        return res.data or []

    async def get_tasks(self, user_id: str, status: str = None) -> list:
        q = self.db.table("tasks").select("*").eq("user_id", user_id)
        if status:
            q = q.eq("status", status)
        res = q.order("created_at", desc=True).execute()
        return res.data or []

    async def update_task(self, task_id: str, user_id: str, data: dict) -> dict:
        res = (
            self.db.table("tasks")
            .update(data)
            .eq("id", task_id)
            .eq("user_id", user_id)
            .execute()
        )
        return res.data[0] if res.data else {}

    # ── Skills ────────────────────────────────────────────────
    async def get_skill_modules(self, is_premium: bool = None) -> list:
        q = self.db.table("skill_modules").select("*")
        if is_premium is not None:
            q = q.eq("is_premium", is_premium)
        return q.order("created_at", desc=False).execute().data or []

    async def enroll_skill(self, user_id: str, module_id: str) -> dict:
        res = self.db.table("user_skill_enrollments").upsert({
            "user_id": user_id,
            "module_id": module_id,
            "status": "enrolled",
        }).execute()
        return res.data[0] if res.data else {}

    async def get_enrollments(self, user_id: str) -> list:
        res = (
            self.db.table("user_skill_enrollments")
            .select("*, skill_modules(*)")
            .eq("user_id", user_id)
            .execute()
        )
        return res.data or []

    async def update_enrollment(
        self, enrollment_id: str, user_id: str, data: dict
    ) -> dict:
        res = (
            self.db.table("user_skill_enrollments")
            .update(data)
            .eq("id", enrollment_id)
            .eq("user_id", user_id)
            .execute()
        )
        return res.data[0] if res.data else {}

    # ── Roadmap ───────────────────────────────────────────────
    async def upsert_roadmap(self, user_id: str, roadmap_data: dict) -> dict:
        roadmap_data["user_id"] = user_id
        res = self.db.table("roadmaps").upsert(
            roadmap_data, on_conflict="user_id"
        ).execute()
        return res.data[0] if res.data else {}

    async def get_roadmap(self, user_id: str) -> dict:
        try:
            res = (
                self.db.table("roadmaps")
                .select("*, milestones(*)")
                .eq("user_id", user_id)
                .single()
                .execute()
            )
            return res.data or {}
        except Exception:
            return {}

    # ── Earnings ──────────────────────────────────────────────
    async def log_earning(
        self,
        user_id: str,
        amount: float,
        source_type: str,
        source_id: str = None,
        description: str = None,
        currency: str = "NGN",
    ) -> dict:
        res = self.db.table("earnings").insert({
            "user_id": user_id,
            "amount": amount,
            "source_type": source_type,
            "source_id": source_id,
            "description": description,
            "currency": currency,
        }).execute()
        try:
            self.db.rpc(
                "increment_total_earned", {"uid": user_id, "amount": amount}
            ).execute()
        except Exception:
            pass
        return res.data[0] if res.data else {}

    async def get_earnings_summary(self, user_id: str) -> dict:
        res = (
            self.db.table("earnings")
            .select("amount, currency, source_type, earned_at")
            .eq("user_id", user_id)
            .order("earned_at", desc=True)
            .execute()
        )
        data = res.data or []
        total = sum(float(e["amount"]) for e in data)
        return {"total": total, "count": len(data), "breakdown": data[:10]}

    # ── Feature Unlocks ───────────────────────────────────────
    async def unlock_feature(
        self,
        user_id: str,
        feature_key: str,
        method: str,
        expires_at=None,
    ) -> dict:
        res = self.db.table("feature_unlocks").insert({
            "user_id": user_id,
            "feature_key": feature_key,
            "unlock_method": method,
            "is_active": True,
            "expires_at": expires_at,
        }).execute()
        return res.data[0] if res.data else {}

    async def check_feature_access(self, user_id: str, feature_key: str) -> bool:
        profile = await self.get_profile(user_id)
        if profile and profile.get("subscription_tier") == "premium":
            expires = profile.get("subscription_expires_at")
            if expires:
                from datetime import datetime, timezone
                from dateutil.parser import parse as parse_dt
                if parse_dt(expires) > datetime.now(timezone.utc):
                    return True
            else:
                return True

        from datetime import datetime, timezone
        from dateutil.parser import parse as parse_dt

        res = (
            self.db.table("feature_unlocks")
            .select("expires_at")
            .eq("user_id", user_id)
            .eq("feature_key", feature_key)
            .eq("is_active", True)
            .execute()
        )
        if not res.data:
            return False

        now = datetime.now(timezone.utc)
        for unlock in res.data:
            if not unlock.get("expires_at"):
                return True
            if parse_dt(unlock["expires_at"]) > now:
                return True
        return False

    # ── Payments ──────────────────────────────────────────────
    async def create_payment(
        self,
        user_id: str,
        tx_ref: str,
        amount: float,
        currency: str,
        payment_type: str,
        plan: str = "monthly",
    ) -> dict:
        res = self.db.table("payments").insert({
            "user_id": user_id,
            "flutterwave_tx_ref": tx_ref,
            "amount": amount,
            "currency": currency,
            "payment_type": payment_type,
            "plan": plan,
            "status": "pending",
        }).execute()
        return res.data[0] if res.data else {}

    async def update_payment(self, tx_ref: str, data: dict) -> dict:
        res = (
            self.db.table("payments")
            .update(data)
            .eq("flutterwave_tx_ref", tx_ref)
            .execute()
        )
        return res.data[0] if res.data else {}

    # ── Ad Views ──────────────────────────────────────────────
    async def log_ad_view(
        self, user_id: str, ad_unit_id: str, feature_unlocked: str = None
    ) -> dict:
        res = self.db.table("ad_views").insert({
            "user_id": user_id,
            "ad_unit_id": ad_unit_id,
            "ad_type": "rewarded",
            "feature_unlocked": feature_unlocked,
            "reward_granted": feature_unlocked is not None,
        }).execute()
        return res.data[0] if res.data else {}

    # ── Progress Stats ────────────────────────────────────────
    async def get_user_stats(self, user_id: str) -> dict:
        profile     = await self.get_profile(user_id)
        tasks       = await self.get_tasks(user_id)
        enrollments = await self.get_enrollments(user_id)
        earnings    = await self.get_earnings_summary(user_id)

        completed_tasks = [t for t in tasks if t.get("status") == "completed"]
        active_tasks    = [t for t in tasks if t.get("status") == "in_progress"]

        return {
            "profile":      profile,
            "total_earned": earnings["total"],
            "tasks": {
                "total":     len(tasks),
                "completed": len(completed_tasks),
                "active":    len(active_tasks),
                "suggested": len([t for t in tasks if t.get("status") == "suggested"]),
            },
            "skills": {
                "enrolled":   len(enrollments),
                "completed":  len([e for e in enrollments if e.get("status") == "completed"]),
                "in_progress":len([e for e in enrollments if e.get("status") == "in_progress"]),
            },
            "stage":        profile.get("stage", "survival") if profile else "survival",
            "subscription": profile.get("subscription_tier", "free") if profile else "free",
        }

    # ── Market Pulse / Economic Context ───────────────────────
    async def get_economic_indicators(self, country_code: str) -> dict:
        """
        Fetch cached economic indicators for a given country from the DB.

        Tries the `economic_indicators` table first (populated by a background
        scheduler or migration).  Falls back to a safe empty dict so callers
        never crash — market_pulse.py logs a warning and continues without it.

        Expected table schema (create via migration if needed):
          economic_indicators (
            country_code  TEXT PRIMARY KEY,
            gdp_growth    NUMERIC,
            inflation     NUMERIC,
            unemployment  NUMERIC,
            currency_trend TEXT,
            interest_rate  NUMERIC,
            updated_at    TIMESTAMPTZ DEFAULT now()
          )
        """
        try:
            res = (
                self.db.table("economic_indicators")
                .select("*")
                .eq("country_code", country_code.upper())
                .single()
                .execute()
            )
            return res.data or {}
        except Exception as e:
            logger.debug(f"get_economic_indicators({country_code}): {e}")
            return {}

    async def upsert_economic_indicators(
        self, country_code: str, data: dict
    ) -> dict:
        """
        Upsert economic indicator data for a country (called by scheduler / admin).
        """
        data["country_code"] = country_code.upper()
        try:
            res = (
                self.db.table("economic_indicators")
                .upsert(data, on_conflict="country_code")
                .execute()
            )
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.warning(f"upsert_economic_indicators({country_code}): {e}")
            return {}

    # ── Market Pulse Cache ────────────────────────────────────
    async def get_pulse_cache(self, cache_key: str) -> dict:
        """
        Retrieve a cached market-pulse payload by key.

        Expected table schema:
          pulse_cache (
            cache_key   TEXT PRIMARY KEY,
            payload     JSONB,
            expires_at  TIMESTAMPTZ,
            created_at  TIMESTAMPTZ DEFAULT now()
          )
        """
        try:
            from datetime import datetime, timezone
            res = (
                self.db.table("pulse_cache")
                .select("payload, expires_at")
                .eq("cache_key", cache_key)
                .single()
                .execute()
            )
            if not res.data:
                return {}
            # Honour TTL
            expires_at = res.data.get("expires_at")
            if expires_at:
                from dateutil.parser import parse as parse_dt
                if parse_dt(expires_at) < datetime.now(timezone.utc):
                    return {}  # expired
            return res.data.get("payload") or {}
        except Exception as e:
            logger.debug(f"get_pulse_cache({cache_key}): {e}")
            return {}

    async def set_pulse_cache(
        self, cache_key: str, payload: dict, ttl_seconds: int = 3600
    ) -> bool:
        """Store a market-pulse payload with a TTL."""
        try:
            from datetime import datetime, timezone, timedelta
            expires_at = (
                datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
            ).isoformat()
            self.db.table("pulse_cache").upsert({
                "cache_key":  cache_key,
                "payload":    payload,
                "expires_at": expires_at,
            }, on_conflict="cache_key").execute()
            return True
        except Exception as e:
            logger.warning(f"set_pulse_cache({cache_key}): {e}")
            return False

    # ── Notifications ─────────────────────────────────────────
    async def create_notification(
        self,
        user_id: str,
        title: str,
        body: str,
        notif_type: str = "info",
        metadata: dict = None,
    ) -> dict:
        try:
            res = self.db.table("notifications").insert({
                "user_id":  user_id,
                "title":    title,
                "body":     body,
                "type":     notif_type,
                "metadata": metadata or {},
                "is_read":  False,
            }).execute()
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.warning(f"create_notification: {e}")
            return {}

    async def get_notifications(
        self, user_id: str, limit: int = 50, unread_only: bool = False
    ) -> list:
        try:
            q = (
                self.db.table("notifications")
                .select("*")
                .eq("user_id", user_id)
            )
            if unread_only:
                q = q.eq("is_read", False)
            res = q.order("created_at", desc=True).limit(limit).execute()
            return res.data or []
        except Exception as e:
            logger.warning(f"get_notifications: {e}")
            return []

    async def mark_notification_read(
        self, notification_id: str, user_id: str
    ) -> bool:
        try:
            self.db.table("notifications").update({"is_read": True}).eq(
                "id", notification_id
            ).eq("user_id", user_id).execute()
            return True
        except Exception as e:
            logger.warning(f"mark_notification_read: {e}")
            return False

    # ── Goals ─────────────────────────────────────────────────
    async def create_goal(self, user_id: str, goal_data: dict) -> dict:
        goal_data["user_id"] = user_id
        try:
            res = self.db.table("goals").insert(goal_data).execute()
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.warning(f"create_goal: {e}")
            return {}

    async def get_goals(self, user_id: str, status: str = None) -> list:
        try:
            q = self.db.table("goals").select("*").eq("user_id", user_id)
            if status:
                q = q.eq("status", status)
            res = q.order("created_at", desc=True).execute()
            return res.data or []
        except Exception as e:
            logger.warning(f"get_goals: {e}")
            return []

    async def update_goal(self, goal_id: str, user_id: str, data: dict) -> dict:
        try:
            res = (
                self.db.table("goals")
                .update(data)
                .eq("id", goal_id)
                .eq("user_id", user_id)
                .execute()
            )
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.warning(f"update_goal: {e}")
            return {}

    # ── Agent Quota ───────────────────────────────────────────
    async def get_agent_quota(self, user_id: str) -> dict:
        """
        Return the current agent usage quota for a user.
        Falls back to a sensible default if the table doesn't exist yet.
        """
        try:
            res = (
                self.db.table("agent_quotas")
                .select("*")
                .eq("user_id", user_id)
                .single()
                .execute()
            )
            return res.data or {"user_id": user_id, "used": 0, "limit": 10}
        except Exception as e:
            logger.debug(f"get_agent_quota({user_id}): {e}")
            return {"user_id": user_id, "used": 0, "limit": 10}

    async def increment_agent_quota(self, user_id: str, amount: int = 1) -> bool:
        try:
            self.db.rpc(
                "increment_agent_quota", {"uid": user_id, "amount": amount}
            ).execute()
            return True
        except Exception as e:
            logger.warning(f"increment_agent_quota({user_id}): {e}")
            return False


supabase_service = SupabaseService()
