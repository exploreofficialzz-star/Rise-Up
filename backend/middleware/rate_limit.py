"""
RiseUp Rate Limiting — v2.0
Keys on user_id for authenticated routes (prevents carrier-NAT abuse),
falls back to IP for unauthenticated routes.
"""
import logging
from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)


def _get_user_or_ip(request: Request) -> str:
    """
    Use last 16 chars of JWT as rate-limit key for authenticated requests.
    Falls back to client IP for anonymous/public routes.
    """
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:]
        if token:
            return f"user:{token[-16:]}"
    return get_remote_address(request)


# ── Limiter instance (attach to FastAPI app in main.py) ──────────
limiter = Limiter(key_func=_get_user_or_ip)


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    """Return a clean 429 with Retry-After instead of a 500."""
    return JSONResponse(
        status_code=429,
        content={
            "detail":      "Too many requests. Please slow down and try again shortly.",
            "retry_after": "60 seconds",
        },
        headers={"Retry-After": "60"},
    )


# ── Per-endpoint rate limits ─────────────────────────────────────
# Authenticated / expensive AI calls
AI_LIMIT         = "20/minute"

# Free-tier users — slightly relaxed so quick-hit endpoints feel snappy
# agent.py uses this on /quick and /ads/reward-complete
FREE_TIER_LIMIT  = "30/minute"

# Auth endpoints — brute-force protection
AUTH_LIMIT       = "10/minute"

# General CRUD endpoints
GENERAL_LIMIT    = "60/minute"

# Payment endpoints — very strict to prevent abuse
PAYMENT_LIMIT    = "5/minute"

# Webhook endpoints — high volume allowed from trusted servers
WEBHOOK_LIMIT    = "120/minute"
