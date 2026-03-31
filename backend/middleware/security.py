"""
RiseUp Security Middleware
- Security headers on every response
- Request size limits (per-route, not global)
- Basic bot / abuse detection

FIX v2: Replaced single MAX_BODY_SIZE (512 KB) with per-route limits.
  Upload routes (/upload-media, /avatar) → 500 MB
  All other POST/PUT/PATCH                → 512 KB
  The old 512 KB global limit was blocking every image and video upload
  with a 413 before the request even reached the FastAPI router.
"""
import logging
import time
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

logger = logging.getLogger(__name__)

# ── Body size limits ────────────────────────────────────────────────────────
MAX_BODY_SIZE_DEFAULT = 512 * 1024          # 512 KB  — general API calls
MAX_BODY_SIZE_UPLOAD  = 500 * 1024 * 1024  # 500 MB  — media upload routes

# Any path segment that indicates a file upload endpoint
_UPLOAD_PATH_SEGMENTS = ("/upload-media", "/upload_media", "/avatar")

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

        # ── Per-route body size check ───────────────────────────────────────
        # Upload routes are allowed up to 500 MB.
        # Everything else stays at the original 512 KB limit.
        if request.method in ("POST", "PUT", "PATCH"):
            content_length = request.headers.get("content-length")
            if content_length:
                is_upload = any(seg in path for seg in _UPLOAD_PATH_SEGMENTS)
                limit = MAX_BODY_SIZE_UPLOAD if is_upload else MAX_BODY_SIZE_DEFAULT
                if int(content_length) > limit:
                    label = "500 MB" if is_upload else "512 KB"
                    logger.warning(
                        f"Body too large: {int(content_length)} bytes on {path} "
                        f"(limit {label})"
                    )
                    return JSONResponse(
                        {"detail": f"Request body too large. Maximum: {label}"},
                        status_code=413,
                    )

        start = time.time()
        response: Response = await call_next(request)
        duration = time.time() - start

        # ── Security Headers ───────────────────────────────────────────────
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
        if "server" in response.headers:
            del response.headers["server"]
        if "x-powered-by" in response.headers:
            del response.headers["x-powered-by"]

        return response


# Alias so main.py can import either name
SecurityMiddleware = SecurityHeadersMiddleware
