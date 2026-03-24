"""Auth Router — Supabase-backed authentication with rate limiting"""
import logging
from fastapi import APIRouter, HTTPException, Request

from config import settings
from middleware.rate_limit import limiter, AUTH_LIMIT
from models.schemas import (
    SignUpRequest, SignInRequest,
    PasswordResetRequest, PasswordUpdateRequest
)
from services.supabase_service import supabase_service

router = APIRouter(prefix="/auth", tags=["Auth"])
logger = logging.getLogger(__name__)


def _client():
    """Return the shared anon Supabase client (singleton — no new client per request)."""
    from services.supabase_service import get_supabase_anon
    return get_supabase_anon()


# ── Sign Up ───────────────────────────────────────────────────
@router.post("/signup")
@limiter.limit(AUTH_LIMIT)
async def signup(req: SignUpRequest, request: Request):
    try:
        res = _client().auth.sign_up({
            "email": req.email,
            "password": req.password,
            "options": {
                "data": {"full_name": req.full_name or ""},
                "email_redirect_to": f"{settings.FRONTEND_URL}/login"
            }
        })
        if not res.user:
            raise HTTPException(400, "Signup failed. Please try again.")
        return {
            "user_id": res.user.id,
            "email": res.user.email,
            "access_token": res.session.access_token if res.session else None,
            "refresh_token": res.session.refresh_token if res.session else None,
            "email_confirmed": res.user.email_confirmed_at is not None,
            "message": "Account created! Please check your email to verify your account."
        }
    except HTTPException:
        raise
    except Exception as e:
        err = str(e).lower()
        if "already registered" in err or "already exists" in err:
            raise HTTPException(400, "An account with this email already exists.")
        if "password" in err:
            raise HTTPException(400, "Password does not meet requirements.")
        logger.error(f"Signup error: {e}")
        raise HTTPException(400, "Registration failed. Please try again.")


# ── Sign In ───────────────────────────────────────────────────
@router.post("/signin")
@limiter.limit(AUTH_LIMIT)
async def signin(req: SignInRequest, request: Request):
    try:
        res = _client().auth.sign_in_with_password({
            "email": req.email,
            "password": req.password
        })
        if not res.user or not res.session:
            raise HTTPException(401, "Invalid email or password.")
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "user_id": res.user.id,
            "email": res.user.email,
            "email_confirmed": res.user.email_confirmed_at is not None,
            "token_type": "bearer"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Signin failed for {req.email}: {e}")
        raise HTTPException(401, "Invalid email or password.")


# ── Refresh Token ─────────────────────────────────────────────
@router.post("/refresh")
@limiter.limit("30/minute")
async def refresh_token(body: dict, request: Request):
    token = body.get("refresh_token", "")
    if not token:
        raise HTTPException(400, "refresh_token is required")
    try:
        res = _client().auth.refresh_session(token)
        if not res.session:
            raise HTTPException(401, "Session expired. Please sign in again.")
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(401, "Session expired. Please sign in again.")


# ── Sign Out ──────────────────────────────────────────────────
@router.post("/signout")
async def signout(request: Request):
    try:
        _client().auth.sign_out()
    except Exception:
        pass
    return {"message": "Signed out successfully"}


# ── Password Reset Request ────────────────────────────────────
@router.post("/forgot-password")
@limiter.limit("5/minute")
async def forgot_password(req: PasswordResetRequest, request: Request):
    """Send password reset email via Supabase"""
    try:
        _client().auth.reset_password_email(
            req.email,
            options={"redirect_to": f"{settings.FRONTEND_URL}/reset-password"}
        )
    except Exception as e:
        logger.warning(f"Password reset request for {req.email}: {e}")
    return {
        "message": "If an account exists with that email, you'll receive a reset link shortly."
    }


# ── Resend Verification Email ─────────────────────────────────
@router.post("/resend-verification")
@limiter.limit("3/minute")
async def resend_verification(req: PasswordResetRequest, request: Request):
    """Resend email verification"""
    try:
        _client().auth.resend({
            "type": "signup",
            "email": req.email,
            "options": {
                "email_redirect_to": f"{settings.FRONTEND_URL}/login"
            }
        })
    except Exception as e:
        logger.warning(f"Resend verification for {req.email}: {e}")
    return {"message": "Verification email sent. Please check your inbox."}


# ── Version Check ─────────────────────────────────────────────
@router.get("/version")
async def version_check(app_version: str = "1.0.0"):
    """Check if the app version is still supported"""
    MIN_VERSION = "1.0.0"

    def parse_version(v: str):
        try:
            return tuple(int(x) for x in v.split(".")[:3])
        except Exception:
            return (1, 0, 0)

    current = parse_version(app_version)
    minimum = parse_version(MIN_VERSION)
    update_required = current < minimum

    return {
        "current_version": app_version,
        "min_required_version": MIN_VERSION,
        "update_required": update_required,
        "update_message": (
            "A required update is available. Please update RiseUp to continue."
            if update_required else None
        ),
        "store_url_android": "https://play.google.com/store/apps/details?id=com.chastech.riseup",
        "store_url_ios": "https://apps.apple.com/app/riseup/id0000000000",
    }
