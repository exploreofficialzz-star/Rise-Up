"""
RiseUp Auth Router — Global Production Ready (DEBUG VERSION)
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


def _handle_auth_error(e: Exception, context: str, email: str = None) -> HTTPException:
    """Convert Supabase auth errors to user-friendly messages."""
    err_str = str(e).lower()
    error_msg = str(e)
    
    logger.error(f"Auth error in {context}: {error_msg} | Email: {email}")
    
    # Specific error patterns
    if "already registered" in err_str or "already exists" in err_str:
        return HTTPException(status_code=400, detail="An account with this email already exists.")
    
    if "invalid login credentials" in err_str:
        return HTTPException(status_code=401, detail="Invalid email or password. Please check your credentials.")
    
    if "email not confirmed" in err_str:
        return HTTPException(status_code=401, detail="Please verify your email before signing in. Check your inbox.")
    
    if "user not found" in err_str:
        return HTTPException(status_code=401, detail="No account found with this email.")
    
    if "password" in err_str and "strength" in err_str:
        return HTTPException(status_code=400, detail="Password is too weak. Use at least 8 characters with letters and numbers.")
    
    if "jwt" in err_str or "token" in err_str:
        return HTTPException(status_code=401, detail="Session expired. Please sign in again.")
    
    if "rate limit" in err_str:
        return HTTPException(status_code=429, detail="Too many attempts. Please try again later.")
    
    # Default
    return HTTPException(status_code=500, detail=f"Authentication error: {str(e)}")


# ═════════════════════════════════════════════════════════════════════════════
# DEBUG ENDPOINT
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/debug-signin")
async def debug_signin(req: SignInRequest, request: Request):
    """
    Debug endpoint to see exactly what's happening during signin.
    """
    debug_info = {
        "email_received": req.email,
        "email_normalized": req.email.lower().strip(),
        "password_length": len(req.password) if req.password else 0,
        "supabase_url": settings.SUPABASE_URL[:20] + "..." if settings.SUPABASE_URL else None,
        "has_anon_key": bool(settings.SUPABASE_ANON_KEY),
        "timestamp": datetime.utcnow().isoformat(),
    }
    
    try:
        client = _get_auth_client()
        
        # Try to sign in
        res = client.auth.sign_in_with_password({
            "email": req.email.lower().strip(),
            "password": req.password
        })
        
        debug_info["supabase_response"] = {
            "has_user": res.user is not None,
            "has_session": res.session is not None,
            "user_id": res.user.id if res.user else None,
            "email_confirmed": res.user.email_confirmed_at is not None if res.user else None,
        }
        
        if res.user and res.session:
            return {
                "success": True,
                "debug": debug_info,
                "user_id": res.user.id,
                "access_token": res.session.access_token[:20] + "...",
            }
        else:
            return {
                "success": False,
                "debug": debug_info,
                "error": "No user or session returned",
            }
            
    except Exception as e:
        debug_info["error"] = str(e)
        debug_info["error_type"] = type(e).__name__
        return {
            "success": False,
            "debug": debug_info,
            "error": str(e),
        }


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
        
        # Normalize email
        email = req.email.lower().strip()
        
        user_metadata = {
            "full_name": (req.full_name or "").strip(),
            "country_code": req.country_code,
            "timezone": req.timezone or "UTC",
            "currency": req.currency.value if req.currency else "USD",
            "language": req.language.value if req.language else "en",
            "signup_source": "mobile_app",
            "referral_code": req.referral_code,
        }
        
        # Remove None values
        user_metadata = {k: v for k, v in user_metadata.items() if v is not None}
        
        logger.info(f"Attempting signup for: {email}")
        
        res = client.auth.sign_up({
            "email": email,
            "password": req.password,
            "options": {
                "data": user_metadata,
                "email_redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=signup"
            }
        })
        
        if not res.user:
            raise HTTPException(status_code=400, detail="Signup failed. Please try again.")
        
        logger.info(f"Signup successful: {res.user.id}")
        
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
        raise _handle_auth_error(e, "Signup", req.email)


@router.post("/signin", response_model=SignInResponse)
@limiter.limit(AUTH_LIMIT)
async def signin(req: SignInRequest, request: Request):
    """
    Authenticate existing user.
    """
    try:
        client = _get_auth_client()
        
        # Normalize email
        email = req.email.lower().strip()
        
        logger.info(f"Attempting signin for: {email}")
        
        res = client.auth.sign_in_with_password({
            "email": email,
            "password": req.password
        })
        
        if not res.user or not res.session:
            logger.warning(f"Signin failed for {email}: No user or session")
            raise HTTPException(status_code=401, detail="Invalid email or password.")
        
        email_confirmed = res.user.email_confirmed_at is not None
        user_metadata = res.user.user_metadata or {}
        
        # Check if email is confirmed
        if not email_confirmed:
            logger.warning(f"Signin attempt for unconfirmed email: {email}")
            # Still allow signin but warn
            # Or uncomment below to block:
            # raise HTTPException(status_code=401, detail="Please verify your email before signing in.")
        
        logger.info(f"Signin successful: {res.user.id}")
        
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
        raise _handle_auth_error(e, "Signin", req.email)


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
            req.email.lower().strip(),
            options={"redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=recovery"}
        )
        
        logger.info(f"Password reset requested for: {req.email}")
        
    except Exception as e:
        logger.warning(f"Password reset request for {req.email}: {e}")
    
    return {
        "message": "If an account exists with that email, you'll receive a reset link shortly.",
        "success": True
    }


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
            "email": req.email.lower().strip(),
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
