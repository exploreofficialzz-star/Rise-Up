"""
RiseUp API — Main FastAPI Application
ChAs Tech Group
"""
import logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from config import settings
from middleware.security import SecurityHeadersMiddleware
from middleware.rate_limit import limiter, rate_limit_exceeded_handler
from routers import auth, ai_agent, tasks, skills, payments, progress, community

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s"
)
logger = logging.getLogger(__name__)

# ── App ───────────────────────────────────────────────────────
app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth-building platform by ChAs Tech Group",
    version="1.0.0",
    docs_url="/docs" if settings.APP_ENV != "production" else None,
    redoc_url=None,
)

# ── Rate Limiter State ────────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)

# ── Middleware (order matters — outermost first) ───────────────
# 1. Security headers + bot blocking
app.add_middleware(SecurityHeadersMiddleware)

# 2. CORS — locked to known origins only
_allowed = list(set(
    settings.allowed_origins_list + [
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
    ]
))
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed,
    allow_origin_regex=r"https://.*\.(onrender\.com|github\.io)$",
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Requested-With"],
    expose_headers=["X-RiseUp-Model", "X-RiseUp-Version", "X-Response-Time"],
    max_age=86400,
)

# 3. Rate limiting
app.add_middleware(SlowAPIMiddleware)

# ── Routers ───────────────────────────────────────────────────
app.include_router(auth.router,      prefix="/api/v1")
app.include_router(ai_agent.router,  prefix="/api/v1")
app.include_router(tasks.router,     prefix="/api/v1")
app.include_router(skills.router,    prefix="/api/v1")
app.include_router(payments.router,  prefix="/api/v1")
app.include_router(progress.router,  prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")


# ── Root & Health ─────────────────────────────────────────────
@app.get("/")
async def root():
    return {
        "app": "RiseUp API",
        "version": "1.0.0",
        "min_app_version": "1.0.0",   # bump this to force client updates
        "status": "running",
        "owner": "ChAs Tech Group",
        "platforms": ["android", "ios", "web"],
        "mission": "Guiding you from survival mode to long-term wealth 🚀"
    }


@app.get("/health")
async def health():
    from services.ai_service import ai_service
    return {
        "status": "healthy",
        "version": "1.0.0",
        "min_app_version": "1.0.0",
        "ai_models_available": ai_service.get_available_models(),
        "environment": settings.APP_ENV,
    }


# ── Global exception handler ──────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error on {request.url}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Something went wrong. Our team has been notified."}
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
