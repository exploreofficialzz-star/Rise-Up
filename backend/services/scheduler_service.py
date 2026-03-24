"""
RiseUp Background Scheduler
─────────────────────────────────────────────────────────────────────
Adapted from GrowthAI's scheduler.py.

Schedule:
  • Every 1h  → quick scan (RemoteOK + Reddit top posts)
  • Every 6h  → full scan across all sources
  • Daily 8am → push daily opportunity digest to users
  • Sunday 6pm→ weekly progress summary per user
"""

import asyncio
import logging
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from config import settings

logger = logging.getLogger(__name__)
_scheduler: AsyncIOScheduler = None


# ── Jobs ──────────────────────────────────────────────────────────

async def _quick_scan():
    """Hourly quick scan — RemoteOK + Reddit."""
    try:
        from services.scraper_service import scraper_engine
        result = await scraper_engine.scan_all()
        logger.info(f"Quick scan: {result['total']} opportunities collected")
    except Exception as e:
        logger.error(f"Quick scan error: {e}")


async def _full_scan():
    """Every-6h comprehensive scan."""
    try:
        from services.scraper_service import scraper_engine
        result = await scraper_engine.scan_all()
        logger.info(f"Full scan complete: {result}")
    except Exception as e:
        logger.error(f"Full scan error: {e}")


async def _daily_digest():
    """8am daily — notify users of top new opportunities."""
    try:
        from services.supabase_service import supabase_service
        from services.scraper_service  import scraper_engine
        from services.action_service   import email_service

        sb      = supabase_service.client
        users_r = sb.table("profiles").select("id,full_name,email,current_skills,currency,stage") \
                    .not_.is_("email", "null").execute()
        users = users_r.data or []

        for user in users[:50]:     # cap at 50 per run to avoid overloading
            try:
                opps = await scraper_engine.find_opportunities(
                    profile=user, max_results=5, score_with_ai=False)
                if not opps:
                    continue
                lines = "\n".join(
                    f"• {o['title']} ({o['source']}) — {o['description'][:80]}..."
                    for o in opps[:3]
                )
                name  = user.get("full_name", "").split()[0] or "there"
                await email_service.send(
                    to_email  = user["email"],
                    subject   = f"⚡ {name}, here are today's top opportunities",
                    body_text = f"Hey {name},\n\nHere are 3 opportunities picked for you today:\n\n{lines}\n\nLog into RiseUp to see full details and let APEX help you act on them.\n\n— The APEX Team",
                )
            except Exception:
                pass

        logger.info(f"Daily digest sent to {len(users)} users")
    except Exception as e:
        logger.error(f"Daily digest error: {e}")


async def _weekly_summary():
    """Sunday 6pm — weekly progress summary."""
    try:
        from services.supabase_service import supabase_service
        from services.action_service   import email_service

        sb      = supabase_service.client
        users_r = sb.table("profiles").select("id,full_name,email,stage,monthly_income") \
                    .not_.is_("email", "null").execute()
        users   = users_r.data or []

        for user in users[:50]:
            try:
                name = user.get("full_name", "").split()[0] or "there"
                await email_service.send(
                    to_email  = user["email"],
                    subject   = f"📊 {name}, your weekly RiseUp summary",
                    body_text = (
                        f"Hey {name},\n\n"
                        "Here's your weekly wealth-building update.\n\n"
                        "Open RiseUp and tell APEX what you worked on this week — "
                        "it will analyse your progress and show you exactly what to do next.\n\n"
                        "Keep building 💪\n\n— The APEX Team"
                    ),
                )
            except Exception:
                pass

        logger.info(f"Weekly summary sent to {len(users)} users")
    except Exception as e:
        logger.error(f"Weekly summary error: {e}")


# ── Public API ────────────────────────────────────────────────────

def start_scheduler():
    global _scheduler
    _scheduler = AsyncIOScheduler(timezone="UTC")

    # Hourly quick scan
    _scheduler.add_job(
        _quick_scan, IntervalTrigger(hours=1),
        id="quick_scan", name="Hourly opportunity scan", replace_existing=True,
    )

    # 6-hourly full scan
    _scheduler.add_job(
        _full_scan, IntervalTrigger(hours=6),
        id="full_scan", name="Full opportunity scan", replace_existing=True,
    )

    # Daily digest — 8am UTC
    _scheduler.add_job(
        _daily_digest, CronTrigger(hour=8, minute=0),
        id="daily_digest", name="Daily opportunity digest", replace_existing=True,
    )

    # Weekly summary — Sunday 18:00 UTC
    _scheduler.add_job(
        _weekly_summary, CronTrigger(day_of_week="sun", hour=18, minute=0),
        id="weekly_summary", name="Weekly progress summary", replace_existing=True,
    )

    _scheduler.start()
    jobs = [j.name for j in _scheduler.get_jobs()]
    logger.info(f"Scheduler started: {jobs}")


def stop_scheduler():
    global _scheduler
    if _scheduler:
        _scheduler.shutdown()
        logger.info("Scheduler stopped")


def get_status() -> dict:
    if not _scheduler:
        return {"running": False, "jobs": []}
    return {
        "running": _scheduler.running,
        "jobs": [
            {
                "id":       j.id,
                "name":     j.name,
                "next_run": j.next_run_time.isoformat() if j.next_run_time else None,
            }
            for j in _scheduler.get_jobs()
        ],
    }
