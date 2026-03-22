"""RiseUp Backend — Main Application"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from config import settings
from middleware.rate_limit import limiter
from middleware.security import SecurityMiddleware
from routers import (
    auth, ai_agent, tasks, skills, payments,
    progress, community, streaks, goals,
    expenses, achievements, referrals,
    notifications, admin,
    # ── New social routers ─────────────────────────────
    posts, messages, live,
)

app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth platform with social features",
    version="2.0.0",
    docs_url="/docs" if settings.APP_ENV != "production" else None,
    redoc_url=None,
)

# ── Rate limiting ──────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ───────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS_LIST,
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
