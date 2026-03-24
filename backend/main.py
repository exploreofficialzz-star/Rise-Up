"""RiseUp Backend — Main Application v3 (APEX + GrowthAI merged)"""
from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from config import settings
from middleware.rate_limit import limiter
from middleware.security import SecurityMiddleware

logger = logging.getLogger(__name__)


# ── Lifespan (startup / shutdown) ─────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ───────────────────────────────────────
    try:
        from services.scheduler_service import start_scheduler
        start_scheduler()
        logger.info("Background scheduler started")
    except Exception as e:
        logger.warning(f"Scheduler failed to start (non-fatal): {e}")

    yield

    # ── Shutdown ──────────────────────────────────────
    try:
        from services.scheduler_service import stop_scheduler
        stop_scheduler()
        logger.info("Scheduler stopped")
    except Exception:
        pass


app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth platform — APEX Agent + GrowthAI intelligence",
    version="3.0.0",
    docs_url="/docs" if settings.APP_ENV != "production" else None,
    redoc_url=None,
    lifespan=lifespan,
)

# ── Rate limiting ──────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ───────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(SecurityMiddleware)

# ── Routers ────────────────────────────────────────────
from routers import (
    auth, ai_agent, tasks, skills, payments,
    progress, community, streaks, goals,
    expenses, achievements, referrals,
    notifications, admin,
    posts, messages, live,
    workflow, agent, collaboration, ads,
    income_memory, market_pulse, contracts,
    crm, challenges, portfolio,
)

app.include_router(auth.router,           prefix="/api/v1")
app.include_router(ai_agent.router,       prefix="/api/v1")
app.include_router(tasks.router,          prefix="/api/v1")
app.include_router(skills.router,         prefix="/api/v1")
app.include_router(payments.router,       prefix="/api/v1")
app.include_router(progress.router,       prefix="/api/v1")
app.include_router(community.router,      prefix="/api/v1")
app.include_router(streaks.router,        prefix="/api/v1")
app.include_router(goals.router,          prefix="/api/v1")
app.include_router(expenses.router,       prefix="/api/v1")
app.include_router(achievements.router,   prefix="/api/v1")
app.include_router(referrals.router,      prefix="/api/v1")
app.include_router(notifications.router,  prefix="/api/v1")
app.include_router(admin.router,          prefix="/api/v1")
app.include_router(posts.router,          prefix="/api/v1")
app.include_router(messages.router,       prefix="/api/v1")
app.include_router(live.router,           prefix="/api/v1")
app.include_router(workflow.router,       prefix="/api/v1")
app.include_router(agent.router,          prefix="/api/v1")
app.include_router(collaboration.router,  prefix="/api/v1")
app.include_router(ads.router,            prefix="/api/v1")
app.include_router(income_memory.router,  prefix="/api/v1")
app.include_router(market_pulse.router,   prefix="/api/v1")
app.include_router(contracts.router,      prefix="/api/v1")
app.include_router(crm.router,            prefix="/api/v1")
app.include_router(challenges.router,     prefix="/api/v1")
app.include_router(portfolio.router,      prefix="/api/v1")


@app.get("/")
async def root():
    return {
        "name":     "RiseUp API",
        "version":  "3.0.0",
        "status":   "running",
        "platform": "APEX Agent + GrowthAI Intelligence",
    }


@app.get("/health")
async def health():
    try:
        from services.scheduler_service import get_status
        sched = get_status()
    except Exception:
        sched = {"running": False}
    return {"status": "healthy", "scheduler": sched}
