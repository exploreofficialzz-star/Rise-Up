"""
RiseUp Rate Limiting
Uses slowapi (in-memory) — upgrade to Redis for multi-instance deployments
"""
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request
from fastapi.responses import JSONResponse

# Limiter instance — key by IP
limiter = Limiter(key_func=get_remote_address, default_limits=["200/minute"])


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={
            "detail": "Too many requests. Please slow down and try again shortly.",
            "retry_after": "60 seconds"
        },
        headers={"Retry-After": "60"}
    )


# ── Per-endpoint limit decorators (import in routers) ──
# AI endpoints — expensive, limit tightly
AI_LIMIT = "20/minute"

# Auth endpoints — prevent brute force
AUTH_LIMIT = "10/minute"

# General API
GENERAL_LIMIT = "60/minute"

# Payment — very strict
PAYMENT_LIMIT = "5/minute"
