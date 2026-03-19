"""
RiseUp Security Middleware
- Security headers on every response
- Request size limits
- Basic bot / abuse detection
"""
import logging
import time
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

logger = logging.getLogger(__name__)

# Max body size: 512 KB (prevents giant AI prompt abuse)
MAX_BODY_SIZE = 512 * 1024

# Paths that are completely public (no auth, no rate limit counting)
PUBLIC_PATHS = {"/", "/health", "/docs", "/openapi.json"}

# Suspicious patterns in request paths
_SUSPICIOUS = [
    ".php", ".asp", ".env", ".git", "wp-admin",
    "wp-login", "phpMyAdmin", "xmlrpc", "../", "..%2F",
]


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Adds security headers to every response."""

    async def dispatch(self, request: Request, call_next):
        # Block obviously malicious paths immediately
        path = request.url.path.lower()
        if any(s in path for s in _SUSPICIOUS):
            logger.warning(f"Blocked suspicious path: {path} from {request.client}")
            return JSONResponse({"detail": "Not found"}, status_code=404)

        # Check body size for mutation requests
        if request.method in ("POST", "PUT", "PATCH"):
            content_length = request.headers.get("content-length")
            if content_length and int(content_length) > MAX_BODY_SIZE:
                return JSONResponse(
                    {"detail": "Request body too large"},
                    status_code=413
                )

        start = time.time()
        response: Response = await call_next(request)
        duration = time.time() - start

        # ── Security Headers ──────────────────────────────────
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = (
            "geolocation=(), microphone=(), camera=(), payment=()"
        )
        response.headers["X-RiseUp-Version"] = "1.0.0"
        response.headers["X-Response-Time"] = f"{duration:.3f}s"

        # HSTS — only on HTTPS
        if request.url.scheme == "https":
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains; preload"
            )

        # Remove server fingerprinting
        response.headers.pop("Server", None)
        response.headers.pop("X-Powered-By", None)

        return response
