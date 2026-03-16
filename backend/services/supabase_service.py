"""Supabase database service"""
from supabase import create_client, Client
from config import settings
import logging

logger = logging.getLogger(__name__)

_client: Client = None


def get_supabase() -> Client:
    global _client
    if not _client:
        _client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)
    return _client


def get_supabase_anon() -> Client:
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


class SupabaseService:
    def __init__(self):
        self.db = get_supabase()

    # ── Profiles ──────────────────────────────────────────
    async def get_profile(self, user_id: str) -> dict:
        res = self.db.table("profiles").select("*").eq("id", user_id).single().execute()
        return res.data

    async def update_profile(self, user_id: str, data: dict) -> dict:
        res = self.db.table("profiles").update(data).eq("id", user_id).execute()
        return res.data[0] if res.data else {}

    async def upsert_profile(self, user_id: str, data: dict) -> dict:
        data["id"] = user_id
        res = self.db.table("profiles").upsert(data).execute()
        return res.data[0] if res.data else {}

    # ── Conversations ──────────────────────────────────────
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

    async def save_message(self, conversation_id: str, user_id: str, role: str, content: str, ai_model: str = None, metadata: dict = None) -> dict:
        res = self.db.table("messages").insert({
            "conversation_id": conversation_id,
            "user_id": user_id,
            "role": role,
            "content": content,
            "ai_model": ai_model,
            "metadata": metadata or {}
        }).execute()
        # Update conversation message count
        self.db.rpc("increment_message_count", {"conv_id": conversation_id}).execute()
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

    # ── Tasks ──────────────────────────────────────────────
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
        res = self.db.table("tasks").update(data).eq("id", task_id).eq("user_id", user_id).execute()
        return res.data[0] if res.data else {}

    # ── Skills ────────────────────────────────────────────
    async def get_skill_modules(self, is_premium: bool = None) -> list:
        q = self.db.table("skill_modules").select("*")
        if is_premium is not None:
            q = q.eq("is_premium", is_premium)
        return q.execute().data or []

    async def enroll_skill(self, user_id: str, module_id: str) -> dict:
        res = self.db.table("user_skill_enrollments").upsert({
            "user_id": user_id,
            "module_id": module_id,
            "status": "enrolled"
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

    async def update_enrollment(self, enrollment_id: str, user_id: str, data: dict) -> dict:
        res = self.db.table("user_skill_enrollments").update(data).eq("id", enrollment_id).eq("user_id", user_id).execute()
        return res.data[0] if res.data else {}

    # ── Roadmap ───────────────────────────────────────────
    async def upsert_roadmap(self, user_id: str, roadmap_data: dict) -> dict:
        roadmap_data["user_id"] = user_id
        res = self.db.table("roadmaps").upsert(roadmap_data, on_conflict="user_id").execute()
        return res.data[0] if res.data else {}

    async def get_roadmap(self, user_id: str) -> dict:
        res = self.db.table("roadmaps").select("*, milestones(*)").eq("user_id", user_id).single().execute()
        return res.data or {}

    # ── Earnings ──────────────────────────────────────────
    async def log_earning(self, user_id: str, amount: float, source_type: str, source_id: str = None, description: str = None, currency: str = "NGN") -> dict:
        res = self.db.table("earnings").insert({
            "user_id": user_id,
            "amount": amount,
            "source_type": source_type,
            "source_id": source_id,
            "description": description,
            "currency": currency
        }).execute()
        # Update total_earned on profile
        self.db.rpc("increment_total_earned", {"uid": user_id, "amount": amount}).execute()
        return res.data[0] if res.data else {}

    async def get_earnings_summary(self, user_id: str) -> dict:
        res = self.db.table("earnings").select("amount, currency, source_type, earned_at").eq("user_id", user_id).execute()
        data = res.data or []
        total = sum(e["amount"] for e in data)
        return {"total": total, "count": len(data), "breakdown": data[-10:]}

    # ── Feature Unlocks ───────────────────────────────────
    async def unlock_feature(self, user_id: str, feature_key: str, method: str, expires_at=None) -> dict:
        res = self.db.table("feature_unlocks").insert({
            "user_id": user_id,
            "feature_key": feature_key,
            "unlock_method": method,
            "is_active": True,
            "expires_at": expires_at
        }).execute()
        return res.data[0] if res.data else {}

    async def check_feature_access(self, user_id: str, feature_key: str) -> bool:
        profile = await self.get_profile(user_id)
        if profile and profile.get("subscription_tier") == "premium":
            return True

        from datetime import datetime, timezone
        res = (
            self.db.table("feature_unlocks")
            .select("*")
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
            from dateutil.parser import parse
            if parse(unlock["expires_at"]) > now:
                return True
        return False

    # ── Payments ──────────────────────────────────────────
    async def create_payment(self, user_id: str, tx_ref: str, amount: float, currency: str, payment_type: str, plan: str = "monthly") -> dict:
        res = self.db.table("payments").insert({
            "user_id": user_id,
            "flutterwave_tx_ref": tx_ref,
            "amount": amount,
            "currency": currency,
            "payment_type": payment_type,
            "plan": plan,
            "status": "pending"
        }).execute()
        return res.data[0] if res.data else {}

    async def update_payment(self, tx_ref: str, data: dict) -> dict:
        res = self.db.table("payments").update(data).eq("flutterwave_tx_ref", tx_ref).execute()
        return res.data[0] if res.data else {}

    # ── Ad Views ──────────────────────────────────────────
    async def log_ad_view(self, user_id: str, ad_unit_id: str, feature_unlocked: str = None) -> dict:
        res = self.db.table("ad_views").insert({
            "user_id": user_id,
            "ad_unit_id": ad_unit_id,
            "ad_type": "rewarded",
            "feature_unlocked": feature_unlocked,
            "reward_granted": feature_unlocked is not None
        }).execute()
        return res.data[0] if res.data else {}

    # ── Progress Stats ────────────────────────────────────
    async def get_user_stats(self, user_id: str) -> dict:
        profile = await self.get_profile(user_id)
        tasks = await self.get_tasks(user_id)
        enrollments = await self.get_enrollments(user_id)
        earnings = await self.get_earnings_summary(user_id)

        completed_tasks = [t for t in tasks if t["status"] == "completed"]
        active_tasks = [t for t in tasks if t["status"] == "in_progress"]

        return {
            "profile": profile,
            "total_earned": earnings["total"],
            "tasks": {
                "total": len(tasks),
                "completed": len(completed_tasks),
                "active": len(active_tasks),
                "suggested": len([t for t in tasks if t["status"] == "suggested"])
            },
            "skills": {
                "enrolled": len(enrollments),
                "completed": len([e for e in enrollments if e["status"] == "completed"]),
                "in_progress": len([e for e in enrollments if e["status"] == "in_progress"])
            },
            "stage": profile.get("stage", "survival") if profile else "survival",
            "subscription": profile.get("subscription_tier", "free") if profile else "free"
        }


supabase_service = SupabaseService()
