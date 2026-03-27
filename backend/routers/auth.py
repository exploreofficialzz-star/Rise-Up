"""
RiseUp Auth Router — Global Production Ready
Supabase-backed authentication with rate limiting and global context
"""

import logging
from typing import Optional
from datetime import datetime
from fastapi import APIRouter, HTTPException, Request, Depends, BackgroundTasks
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from config import settings
from middleware.rate_limit import limiter, AUTH_LIMIT
from models.schemas import (
    SignUpRequest, SignInRequest, SignUpResponse, SignInResponse,
    PasswordResetRequest, PasswordUpdateRequest, VersionCheckResponse,
    TokenRefreshResponse, MessageResponse
)
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)
security = HTTPBearer(auto_error=False)


# ═════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def _get_auth_client():
    """Get Supabase auth client."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


def _handle_auth_error(e: Exception, context: str) -> HTTPException:
    """Convert Supabase auth errors to user-friendly messages."""
    err_str = str(e).lower()
    error_messages = {
        "already registered": "An account with this email already exists.",
        "already exists": "An account with this email already exists.",
        "invalid login credentials": "Invalid email or password.",
        "user not found": "No account found with this email.",
        "email not confirmed": "Please verify your email before signing in.",
        "password": "Password does not meet security requirements.",
        "rate limit": "Too many attempts. Please try again later.",
        "jwt expired": "Your session has expired. Please sign in again.",
        "invalid jwt": "Invalid session. Please sign in again.",
        "user banned": "This account has been suspended. Contact support.",
    }
    
    for key, message in error_messages.items():
        if key in err_str:
            status_code = 400 if "already" in key else 401
            return HTTPException(status_code=status_code, detail=message)
    
    logger.error(f"{context} error: {e}")
    return HTTPException(status_code=500, detail="An unexpected error occurred. Please try again.")


# ═════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION ENDPOINTS
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/signup", response_model=SignUpResponse)
@limiter.limit(AUTH_LIMIT)
async def signup(req: SignUpRequest, request: Request, background_tasks: BackgroundTasks):
    """
    Register a new user with global context support.
    """
    try:
        client = _get_auth_client()
        
        user_metadata = {
            "full_name": req.full_name or "",
            "country_code": req.country_code,
            "timezone": req.timezone,
            "currency": req.currency.value if req.currency else "USD",
            "language": req.language.value if req.language else "en",
            "signup_source": "mobile_app",
            "referral_code": req.referral_code,
            "signup_ip": request.client.host if request.client else None,
            "signup_at": datetime.utcnow().isoformat(),
        }
        
        user_metadata = {k: v for k, v in user_metadata.items() if v is not None}
        
        res = client.auth.sign_up({
            "email": req.email,
            "password": req.password,
            "options": {
                "data": user_metadata,
                "email_redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=signup"
            }
        })
        
        if not res.user:
            raise HTTPException(status_code=400, detail="Signup failed. Please try again.")
        
        logger.info(f"New user signup: {res.user.id} from {req.country_code or 'unknown'}")
        
        return {
            "user_id": res.user.id,
            "email": res.user.email,
            "access_token": res.session.access_token if res.session else None,
            "refresh_token": res.session.refresh_token if res.session else None,
            "token_type": "bearer",
            "email_confirmed": res.user.email_confirmed_at is not None,
            "onboarding_complete": False,
            "currency": user_metadata.get("currency", "USD"),
            "language": user_metadata.get("language", "en"),
            "message": "Account created! Please check your email to verify your account."
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise _handle_auth_error(e, "Signup")


@router.post("/signin", response_model=SignInResponse)
@limiter.limit(AUTH_LIMIT)
async def signin(req: SignInRequest, request: Request):
    """
    Authenticate existing user.
    """
    try:
        client = _get_auth_client()
        
        res = client.auth.sign_in_with_password({
            "email": req.email,
            "password": req.password
        })
        
        if not res.user or not res.session:
            raise HTTPException(status_code=401, detail="Invalid email or password.")
        
        email_confirmed = res.user.email_confirmed_at is not None
        user_metadata = res.user.user_metadata or {}
        
        logger.info(f"User signin: {res.user.id}")
        
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type": "bearer",
            "expires_in": 3600,
            "user_id": res.user.id,
            "email": res.user.email,
            "email_confirmed": email_confirmed,
            "onboarding_complete": user_metadata.get("onboarding_completed", False),
            "currency": user_metadata.get("currency", "USD"),
            "language": user_metadata.get("language", "en"),
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise _handle_auth_error(e, "Signin")


@router.post("/refresh", response_model=TokenRefreshResponse)
@limiter.limit("30/minute")
async def refresh_token(request: Request, credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)):
    """
    Refresh access token using refresh token.
    """
    refresh_token = None
    
    if credentials and credentials.credentials:
        refresh_token = credentials.credentials
    else:
        try:
            body = await request.json()
            refresh_token = body.get("refresh_token")
        except:
            pass
    
    if not refresh_token:
        raise HTTPException(status_code=400, detail="Refresh token is required")
    
    try:
        client = _get_auth_client()
        res = client.auth.refresh_session(refresh_token)
        
        if not res.session:
            raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")
        
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type": "bearer",
            "expires_in": 3600,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise _handle_auth_error(e, "Token refresh")


@router.post("/signout", response_model=MessageResponse)
async def signout(request: Request, credentials: HTTPAuthorizationCredentials = Depends(security)):
    """
    Sign out user and invalidate session.
    """
    try:
        client = _get_auth_client()
        
        if credentials and credentials.credentials:
            try:
                client.auth.set_session(credentials.credentials, "")
                client.auth.sign_out()
            except Exception as e:
                logger.warning(f"Supabase signout error (non-critical): {e}")
        
        return {
            "message": "Signed out successfully",
            "success": True
        }
        
    except Exception as e:
        logger.warning(f"Signout error: {e}")
        return {
            "message": "Signed out successfully",
            "success": True
        }


@router.post("/forgot-password", response_model=MessageResponse)
@limiter.limit("5/minute")
async def forgot_password(req: PasswordResetRequest, request: Request):
    """
    Send password reset email.
    """
    try:
        client = _get_auth_client()
        
        client.auth.reset_password_email(
            req.email,
            options={"redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=recovery"}
        )
        
        logger.info(f"Password reset requested for: {req.email}")
        
    except Exception as e:
        logger.warning(f"Password reset request for {req.email}: {e}")
    
    return {
        "message": "If an account exists with that email, you'll receive a reset link shortly.",
        "success": True
    }


@router.post("/reset-password", response_model=MessageResponse)
@limiter.limit("5/minute")
async def reset_password(req: PasswordUpdateRequest, request: Request):
    """
    Reset password with token from email.
    """
    try:
        client = _get_auth_client()
        
        res = client.auth.update_user({
            "password": req.new_password
        })
        
        if not res.user:
            raise HTTPException(status_code=400, detail="Password reset failed. Please try again.")
        
        logger.info(f"Password reset successful for: {res.user.id}")
        
        return {
            "message": "Password updated successfully. Please sign in with your new password.",
            "success": True
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise _handle_auth_error(e, "Password reset")


@router.post("/resend-verification", response_model=MessageResponse)
@limiter.limit("3/minute")
async def resend_verification(req: PasswordResetRequest, request: Request):
    """
    Resend email verification link.
    """
    try:
        client = _get_auth_client()
        
        client.auth.resend({
            "type": "signup",
            "email": req.email,
            "options": {
                "email_redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=signup"
            }
        })
        
        logger.info(f"Verification email resent for: {req.email}")
        
    except Exception as e:
        logger.warning(f"Resend verification for {req.email}: {e}")
    
    return {
        "message": "Verification email sent. Please check your inbox.",
        "success": True
    }


@router.get("/verify-email")
async def verify_email(token: str, type: str = "signup"):
    """
    Handle email verification callback from Supabase.
    """
    try:
        client = _get_auth_client()
        
        res = client.auth.verify_otp({
            "token_hash": token,
            "type": type
        })
        
        if res.user:
            return {
                "success": True,
                "message": "Email verified successfully!",
                "user_id": res.user.id,
                "redirect_to": f"{settings.FRONTEND_URL}/login?verified=true"
            }
        
    except Exception as e:
        logger.error(f"Email verification failed: {e}")
    
    return {
        "success": False,
        "message": "Verification failed or link expired. Please request a new one.",
        "redirect_to": f"{settings.FRONTEND_URL}/login?error=verification_failed"
    }


# ═════════════════════════════════════════════════════════════════════════════
# VERSION & HEALTH CHECKS
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/version", response_model=VersionCheckResponse)
@limiter.limit("100/minute")
async def version_check(app_version: str = "1.0.0", platform: str = "android"):
    """
    Check if the app version is supported.
    """
    MIN_VERSIONS = {
        "android": "1.0.0",
        "ios": "1.0.0",
        "web": "1.0.0"
    }
    
    STORE_URLS = {
        "android": "https://play.google.com/store/apps/details?id=com.chastech.riseup",
        "ios": "https://apps.apple.com/app/riseup/id0000000000",
        "web": settings.FRONTEND_URL
    }

    def parse_version(v: str):
        try:
            return tuple(int(x) for x in v.split(".")[:3])
        except Exception:
            return (1, 0, 0)

    current = parse_version(app_version)
    minimum = parse_version(MIN_VERSIONS.get(platform, "1.0.0"))
    update_required = current < minimum

    return {
        "current_version": app_version,
        "min_required_version": MIN_VERSIONS.get(platform, "1.0.0"),
        "update_required": update_required,
        "update_message": (
            "A required update is available. Please update RiseUp to continue."
            if update_required else "You're up to date!"
        ),
        "download_url": STORE_URLS.get(platform, settings.FRONTEND_URL),
        "force_update": update_required,
        "release_notes": None
    }


@router.get("/me")
async def get_current_user_info(user: dict = Depends(get_current_user)):
    """
    Get current authenticated user info.
    """
    return {
        "user_id": user.get("id"),
        "email": user.get("email"),
        "role": user.get("role", "user"),
        "metadata": user.get("user_metadata", {}),
        "created_at": user.get("created_at"),
        "last_sign_in_at": user.get("last_sign_in_at")
    }


@router.get("/health")
async def auth_health():
    """
    Health check for auth service.
    """
    return {
        "status": "healthy",
        "service": "auth",
        "timestamp": datetime.utcnow().isoformat()
    }
