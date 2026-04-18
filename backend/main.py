"""
RiseUp Backend — Main Application (Production v2.2)

v2.2: Added groups router registration (fixes 404 on /groups and /messages/groups).
v2.1: Added mentor router registration (fixes 404 on /mentor/chat).
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

# ── App ─────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="RiseUp API",
    description="AI-powered wealth platform with social features",
    version="2.2.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url=None,
)

# ── Body Size Limit Middleware ───────────────────────────────────────────────
# Must be added BEFORE SecurityMiddleware so it wraps the whole stack.
# Starlette middleware executes in reverse-add order (last added = outermost).

_UPLOAD_PATHS = ("/upload-media", "/upload_media")
_MAX_UPLOAD   = 500 * 1024 * 1024   # 500 MB — videos up to ~15 min
_MAX_DEFAULT  =   5 * 1024 * 1024   #   5 MB — all other endpoints


class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl:
            size  = int(cl)
            is_upload = any(p in request.url.path for p in _UPLOAD_PATHS)
            limit = _MAX_UPLOAD if is_upload else _MAX_DEFAULT
            if size > limit:
                label = "500 MB" if is_upload else "5 MB"
                return JSONResponse(
                    {"detail": f"Request body too large. Maximum allowed: {label}."},
                    status_code=413,
                )
        return await call_next(request)


app.add_middleware(BodySizeLimitMiddleware)

# ── Rate Limiting ────────────────────────────────────────────────────────────
try:
    from middleware.rate_limit import limiter, rate_limit_exceeded_handler
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
    print("✅ Rate limiting loaded")
except Exception as e:
    print(f"❌ Rate limiting failed: {e}")
    traceback.print_exc()

# ── CORS & Security ──────────────────────────────────────────────────────────
try:
    from middleware.security import SecurityMiddleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(SecurityMiddleware)
    print("✅ CORS and Security middleware loaded")
except Exception as e:
    print(f"❌ Middleware failed: {e}")
    traceback.print_exc()

# ── Router Loader ────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("LOADING ROUTERS")
print("=" * 60)

loaded_routers: list[str]             = []
failed_routers: list[tuple[str, str]] = []


def load_router(name: str, module_name: str, router_attr: str = "router") -> bool:
    """Import a router module and register it. Logs success/failure."""
    try:
        print(f"\n📦 Loading {name}...")
        module = __import__(f"routers.{module_name}", fromlist=[router_attr])
        router = getattr(module, router_attr)
        app.include_router(router, prefix="/api/v1")
        loaded_routers.append(name)
        print(f"   ✅ {name} loaded successfully")
        return True
    except Exception as e:
        print(f"   ❌ {name} FAILED: {e}")
        traceback.print_exc()
        failed_routers.append((name, str(e)))
        return False


# ── Critical routers first ────────────────────────────────────────────────
load_router("auth",     "auth")
load_router("workflow", "workflow")

# ── AI routers ────────────────────────────────────────────────────────────
load_router("ai_agent", "ai_agent")   # /ai/*  — generic AI chat, tasks, roadmap
load_router("mentor",   "mentor")     # /mentor/* — AI Wealth Mentor (chat sessions,
                                      #             brain context, APEX delegation)

# ── Feature routers ───────────────────────────────────────────────────────
load_router("tasks",         "tasks")
load_router("skills",        "skills")
load_router("payments",      "payments")
load_router("progress",      "progress")
load_router("community",     "community")
load_router("streaks",       "streaks")
load_router("goals",         "goals")
load_router("expenses",      "expenses")
load_router("achievements",  "achievements")
load_router("referrals",     "referrals")
load_router("notifications", "notifications")
load_router("admin",         "admin")
load_router("posts",         "posts")
load_router("messages",      "messages")
load_router("groups",        "groups")        # ← NEW: /groups/* full groups feature
load_router("live",          "live")
load_router("agent",         "agent")
load_router("collaboration", "collaboration")
load_router("ads",           "ads")
load_router("income_memory", "income_memory")
load_router("market_pulse",  "market_pulse")
load_router("contracts",     "contracts")
load_router("crm",           "crm")
load_router("challenges",    "challenges")
load_router("portfolio",     "portfolio")
load_router("methods_brain", "methods_brain")

# ── Summary ───────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("ROUTER LOADING SUMMARY")
print("=" * 60)
print(f"✅ Loaded: {len(loaded_routers)} routers")
for r in loaded_routers:
    print(f"   - {r}")

if failed_routers:
    print(f"\n❌ Failed: {len(failed_routers)} routers")
    for name, error in failed_routers:
        print(f"   - {name}: {error}")

print("=" * 60 + "\n")


# ── Health & Debug Endpoints ─────────────────────────────────────────────────

@app.get("/")
async def root():
    return {
        "name":            "RiseUp API",
        "version":         "2.2.0",
        "status":          "running",
        "platform":        "Social Wealth Platform",
        "loaded_routers":  loaded_routers,
        "failed_routers":  [name for name, _ in failed_routers],
    }


@app.get("/health")
async def health():
    from datetime import datetime
    return {
        "status":          "healthy" if "auth" in loaded_routers else "degraded",
        "timestamp":       datetime.utcnow().isoformat(),
        "environment":     settings.APP_ENV,
        "routers_loaded":  len(loaded_routers),
        "routers_failed":  len(failed_routers),
    }


@app.get("/debug/routers")
async def debug_routers():
    """List every registered route — useful for confirming endpoints exist."""
    routes = []
    for route in app.routes:
        if hasattr(route, "methods") and hasattr(route, "path"):
            routes.append({
                "path":    route.path,
                "methods": list(route.methods),
                "name":    route.name,
            })
    return {
        "total_routes":   len(routes),
        "routes":         sorted(routes, key=lambda x: x["path"]),
        "loaded_routers": loaded_routers,
        "failed_routers": [
            {"name": name, "error": error}
            for name, error in failed_routers
        ],
    }


print("🚀 Application startup complete!")
