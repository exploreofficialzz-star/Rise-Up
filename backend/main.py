"""RiseUp Backend — Main Application"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from config import settings
from middleware.rate_limit import limiter
from middleware.security import SecurityMiddleware
from services.supabase_service import get_supabase, get_supabase_anon
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

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Warm up DB connections at startup to eliminate cold-start lag."""
    try:
        # Force both singleton clients to initialise before any request hits
        get_supabase()
        get_supabase_anon()
        logger.info("✅ Supabase connections warmed up")
    except Exception as e:
        logger.warning(f"⚠️  Supabase warm-up failed (non-fatal): {e}")
    yield
    # Shutdown — nothing to clean up for sync supabase-py client


app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth platform with social features",
    version="2.0.0",
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

# ── Existing routers ───────────────────────────────────
app.include_router(auth.router,          prefix="/api/v1")
app.include_router(ai_agent.router,      prefix="/api/v1")
app.include_router(tasks.router,         prefix="/api/v1")
app.include_router(skills.router,        prefix="/api/v1")
app.include_router(payments.router,      prefix="/api/v1")
app.include_router(progress.router,      prefix="/api/v1")
app.include_router(community.router,     prefix="/api/v1")
app.include_router(streaks.router,       prefix="/api/v1")
app.include_router(goals.router,         prefix="/api/v1")
app.include_router(expenses.router,      prefix="/api/v1")
app.include_router(achievements.router,  prefix="/api/v1")
app.include_router(referrals.router,     prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(admin.router,         prefix="/api/v1")

# ── New social routers ─────────────────────────────────
app.include_router(posts.router,         prefix="/api/v1")
app.include_router(messages.router,      prefix="/api/v1")
app.include_router(live.router,          prefix="/api/v1")

# ── AI Workflow Engine ─────────────────────────────────
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
        "name": "RiseUp API",
        "version": "2.0.0",
        "status": "running",
        "platform": "Social Wealth Platform",
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/ping")
async def ping():
    """Lightweight keep-alive endpoint.
    Call this from a cron job (e.g. UptimeRobot free tier) every 10 minutes
    to prevent Render free-tier cold starts from adding 30s to first requests.
    """
    return {"pong": True}
