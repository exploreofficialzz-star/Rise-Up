"""
RiseUp Rate Limiting
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
    """Use JWT user_id as rate limit key for authenticated requests; IP for anonymous."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:]
        if token:
            # Use the last 16 chars of the token as a stable-enough key
            # (avoids decoding the JWT on every request while still being user-specific)
            return f"user:{token[-16:]}"
    return get_remote_address(request)


limiter = Limiter(key_func=_get_user_or_ip, default_limits=["200/minute"])


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={
            "detail": "Too many requests. Please slow down and try again shortly.",
            "retry_after": "60 seconds",
        },
        headers={"Retry-After": "60"},
    )


# ── Per-endpoint limits ──────────────────────────────────────
AI_LIMIT      = "20/minute"   # AI endpoints — expensive
AUTH_LIMIT    = "10/minute"   # Prevent brute force
GENERAL_LIMIT = "60/minute"   # Standard API
PAYMENT_LIMIT = "5/minute"    # Very strict
