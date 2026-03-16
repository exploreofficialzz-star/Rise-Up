"""
RiseUp API — Main FastAPI Application
ChAs Tech Group
"""
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import settings
from routers import auth, ai_agent, tasks, skills, payments, progress, community

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

# App
app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth-building platform by ChAs Tech Group",
    version="1.0.0",
    docs_url="/docs" if settings.APP_ENV != "production" else None,
    redoc_url=None,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list + ["*"],  # lock down in prod
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(auth.router, prefix="/api/v1")
app.include_router(ai_agent.router, prefix="/api/v1")
app.include_router(tasks.router, prefix="/api/v1")
app.include_router(skills.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(progress.router, prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")


@app.get("/")
async def root():
    return {
        "app": "RiseUp API",
        "version": "1.0.0",
        "status": "running",
        "owner": "ChAs Tech Group",
        "mission": "Guiding you from survival mode to long-term wealth 🚀"
    }


@app.get("/health")
async def health():
    from services.ai_service import ai_service
    return {
        "status": "healthy",
        "ai_models_available": ai_service.get_available_models(),
        "environment": settings.APP_ENV
    }


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error. Our team has been notified."}
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
