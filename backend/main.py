"""
RiseUp Backend — Main Application
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from config import settings
from middleware.rate_limit import limiter, rate_limit_exceeded_handler
from middleware.security import SecurityMiddleware

# Import routers one by one with error handling
routers_to_load = []

try:
    from routers import auth
    routers_to_load.append(("auth", auth.router))
except Exception as e:
    print(f"Failed to load auth router: {e}")

try:
    from routers import ai_agent
    routers_to_load.append(("ai_agent", ai_agent.router))
except Exception as e:
    print(f"Failed to load ai_agent router: {e}")

try:
    from routers import tasks
    routers_to_load.append(("tasks", tasks.router))
except Exception as e:
    print(f"Failed to load tasks router: {e}")

try:
    from routers import skills
    routers_to_load.append(("skills", skills.router))
except Exception as e:
    print(f"Failed to load skills router: {e}")

try:
    from routers import payments
    routers_to_load.append(("payments", payments.router))
except Exception as e:
    print(f"Failed to load payments router: {e}")

try:
    from routers import progress
    routers_to_load.append(("progress", progress.router))
except Exception as e:
    print(f"Failed to load progress router: {e}")

try:
    from routers import community
    routers_to_load.append(("community", community.router))
except Exception as e:
    print(f"Failed to load community router: {e}")

try:
    from routers import streaks
    routers_to_load.append(("streaks", streaks.router))
except Exception as e:
    print(f"Failed to load streaks router: {e}")

try:
    from routers import goals
    routers_to_load.append(("goals", goals.router))
except Exception as e:
    print(f"Failed to load goals router: {e}")

try:
    from routers import expenses
    routers_to_load.append(("expenses", expenses.router))
except Exception as e:
    print(f"Failed to load expenses router: {e}")

try:
    from routers import achievements
    routers_to_load.append(("achievements", achievements.router))
except Exception as e:
    print(f"Failed to load achievements router: {e}")

try:
    from routers import referrals
    routers_to_load.append(("referrals", referrals.router))
except Exception as e:
    print(f"Failed to load referrals router: {e}")

try:
    from routers import notifications
    routers_to_load.append(("notifications", notifications.router))
except Exception as e:
    print(f"Failed to load notifications router: {e}")

try:
    from routers import admin
    routers_to_load.append(("admin", admin.router))
except Exception as e:
    print(f"Failed to load admin router: {e}")

try:
    from routers import posts
    routers_to_load.append(("posts", posts.router))
except Exception as e:
    print(f"Failed to load posts router: {e}")

try:
    from routers import messages
    routers_to_load.append(("messages", messages.router))
except Exception as e:
    print(f"Failed to load messages router: {e}")

try:
    from routers import live
    routers_to_load.append(("live", live.router))
except Exception as e:
    print(f"Failed to load live router: {e}")

try:
    from routers import workflow
    routers_to_load.append(("workflow", workflow.router))
except Exception as e:
    print(f"Failed to load workflow router: {e}")

try:
    from routers import agent
    routers_to_load.append(("agent", agent.router))
except Exception as e:
    print(f"Failed to load agent router: {e}")

try:
    from routers import collaboration
    routers_to_load.append(("collaboration", collaboration.router))
except Exception as e:
    print(f"Failed to load collaboration router: {e}")

try:
    from routers import ads
    routers_to_load.append(("ads", ads.router))
except Exception as e:
    print(f"Failed to load ads router: {e}")

try:
    from routers import income_memory
    routers_to_load.append(("income_memory", income_memory.router))
except Exception as e:
    print(f"Failed to load income_memory router: {e}")

try:
    from routers import market_pulse
    routers_to_load.append(("market_pulse", market_pulse.router))
except Exception as e:
    print(f"Failed to load market_pulse router: {e}")

try:
    from routers import contracts
    routers_to_load.append(("contracts", contracts.router))
except Exception as e:
    print(f"Failed to load contracts router: {e}")

try:
    from routers import crm
    routers_to_load.append(("crm", crm.router))
except Exception as e:
    print(f"Failed to load crm router: {e}")

try:
    from routers import challenges
    routers_to_load.append(("challenges", challenges.router))
except Exception as e:
    print(f"Failed to load challenges router: {e}")

try:
    from routers import portfolio
    routers_to_load.append(("portfolio", portfolio.router))
except Exception as e:
    print(f"Failed to load portfolio router: {e}")


# Create FastAPI app
app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth platform with social features",
    version="2.0.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url=None,
)

# ── Rate limiting ──────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)

# ── CORS ───────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(SecurityMiddleware)

# ── Register routers ───────────────────────────────────
for name, router in routers_to_load:
    try:
        app.include_router(router, prefix="/api/v1")
        print(f"✅ Loaded router: {name}")
    except Exception as e:
        print(f"❌ Failed to register router {name}: {e}")


@app.get("/")
async def root():
    return {
        "name": "RiseUp API",
        "version": "2.0.0",
        "status": "running",
        "platform": "Social Wealth Platform",
        "loaded_modules": len(routers_to_load),
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": __import__("datetime").datetime.utcnow().isoformat(),
        "environment": settings.APP_ENV,
    }
