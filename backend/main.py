"""
RiseUp Backend — Main Application v3.0
Focused on the 4 pillars: Mentor · Workflow · Market · APEX
"""
import sys
import traceback
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from config import settings

app = FastAPI(
    title="RiseUp API",
    description="AI-powered income operating system",
    version="3.0.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url=None,
)

_UPLOAD_PATHS = ("/upload-media", "/upload_media")
_MAX_UPLOAD   = 500 * 1024 * 1024
_MAX_DEFAULT  =   5 * 1024 * 1024


class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl:
            size  = int(cl)
            is_upload = any(p in request.url.path for p in _UPLOAD_PATHS)
            limit = _MAX_UPLOAD if is_upload else _MAX_DEFAULT
            if size > limit:
                label = "500 MB" if is_upload else "5 MB"
                return JSONResponse({"detail": f"Request body too large. Max: {label}."}, status_code=413)
        return await call_next(request)


app.add_middleware(BodySizeLimitMiddleware)

try:
    from middleware.rate_limit import limiter, rate_limit_exceeded_handler
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
except Exception as e:
    print(f"Rate limiting skipped: {e}")

try:
    from middleware.security import SecurityMiddleware
    app.add_middleware(CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
    app.add_middleware(SecurityMiddleware)
except Exception as e:
    print(f"Middleware error: {e}")

loaded_routers: list[str]             = []
failed_routers: list[tuple[str, str]] = []


def load_router(name: str, module_name: str, router_attr: str = "router") -> bool:
    try:
        module = __import__(f"routers.{module_name}", fromlist=[router_attr])
        router = getattr(module, router_attr)
        app.include_router(router, prefix="/api/v1")
        loaded_routers.append(name)
        print(f"  ✅ {name}")
        return True
    except Exception as e:
        print(f"  ❌ {name}: {e}")
        failed_routers.append((name, str(e)))
        return False


print("\n" + "=" * 50)
print("RISEUP v3.0 — LOADING CORE ROUTERS")
print("=" * 50)

# ── Core (always first) ──────────────────────────────────────────
load_router("auth",         "auth")
load_router("payments",     "payments")
load_router("ads",          "ads")
load_router("notifications","notifications")
load_router("admin",        "admin")

# ── The 4 Pillars ────────────────────────────────────────────────
load_router("mentor",       "mentor")      # AI Mentor (chat, sessions, daily check-in)
load_router("agent",        "agent")       # APEX autonomous agent + browser orchestrator
load_router("workflow",     "workflow")    # Workflow engine + task router
load_router("market_pulse", "market_pulse")# Market intelligence + opportunities

# ── Supporting features ──────────────────────────────────────────
load_router("methods_brain","methods_brain") # 10,000 income methods database
load_router("goals",        "goals")
load_router("tasks",        "tasks")
load_router("skills",       "skills")
load_router("progress",     "progress")
load_router("income_memory","income_memory")

print(f"\n✅ {len(loaded_routers)} routers loaded | ❌ {len(failed_routers)} failed\n")


@app.get("/")
async def root():
    return {"name": "RiseUp API", "version": "3.0.0", "status": "running",
            "pillars": ["Mentor", "APEX", "Workflow", "MarketPulse"],
            "loaded": loaded_routers, "failed": [n for n, _ in failed_routers]}


@app.get("/health")
async def health():
    from datetime import datetime
    return {"status": "healthy" if "auth" in loaded_routers else "degraded",
            "timestamp": datetime.utcnow().isoformat(),
            "routers_loaded": len(loaded_routers)}


print("🚀 RiseUp v3.0 ready!")
