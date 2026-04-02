"""
RiseUp Auth Router — Production Ready (Pydantic v2)

FIX: signup() crashed when res.session is None (Supabase requires email
confirmation before issuing a session). Now returns a clean response with
empty tokens and email_confirmed=False so Flutter can show "Check your email"
instead of crashing with a 500.
"""
import logging
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException, Request, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field, ConfigDict

from config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)
security = HTTPBearer(auto_error=False)


# ═════════════════════════════════════════════════════════════════════════════
# PYDANTIC MODELS
# ═════════════════════════════════════════════════════════════════════════════

class SignUpRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    email:         EmailStr
    password:      str = Field(..., min_length=8, max_length=128)
    full_name:     Optional[str] = Field(default=None, max_length=100)
    country_code:  Optional[str] = Field(default=None, max_length=2)
    timezone:      Optional[str] = Field(default="UTC")
    currency:      str = Field(default="USD")
    language:      str = Field(default="en")
    referral_code: Optional[str] = None


class SignInRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    email:    EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token:    str
    refresh_token:   Optional[str] = None
    token_type:      str = "bearer"
    user_id:         str
    email:           str
    email_confirmed: bool = False


class MessageResponse(BaseModel):
    message: str
    success: bool = True


# ═════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def get_supabase_client():
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_auth_client():
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


# ═════════════════════════════════════════════════════════════════════════════
# ENDPOINTS
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignUpRequest, request: Request):
    """
    Register a new user.

    FIX: Supabase returns session=None when email confirmation is enabled.
    Old code did res.session.access_token → AttributeError → 500.
    Now returns empty tokens + email_confirmed=False so Flutter shows
    "Check your inbox" instead of crashing.
    """
    try:
        client = get_supabase_auth_client()

        user_metadata = {
            k: v for k, v in {
                "full_name":    req.full_name or "",
                "country_code": req.country_code,
                "timezone":     req.timezone,
                "currency":     req.currency,
                "language":     req.language,
                "referral_code": req.referral_code,
            }.items() if v is not None
        }

        logger.info(f"Signing up user: {req.email}")

        res = client.auth.sign_up({
            "email":    req.email.lower().strip(),
            "password": req.password,
            "options": {
                "data": user_metadata,
                "email_redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=signup",
            },
        })

        if not res.user:
            raise HTTPException(400, "Signup failed. Please try again.")

        # FIX: session is None when Supabase requires email confirmation.
        # Return safe empty values — Flutter handles email_confirmed=False.
        has_session      = res.session is not None
        email_confirmed  = res.user.email_confirmed_at is not None

        logger.info(
            f"Signup successful: {res.user.id} "
            f"session={'yes' if has_session else 'pending email confirmation'}"
        )

        return {
            "access_token":  res.session.access_token  if has_session else "",
            "refresh_token": res.session.refresh_token if has_session else "",
            "token_type":    "bearer",
            "user_id":       res.user.id,
            "email":         res.user.email,
            "email_confirmed": email_confirmed,
        }

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "already registered" in error_msg or "already been registered" in error_msg:
            raise HTTPException(400, "An account with this email already exists.")
        if "password" in error_msg and ("weak" in error_msg or "short" in error_msg):
            raise HTTPException(400, "Password is too weak. Use at least 8 characters.")
        logger.error(f"Signup error: {e}")
        raise HTTPException(400, f"Registration failed: {str(e)}")


@router.post("/signin", response_model=AuthResponse)
async def signin(req: SignInRequest, request: Request):
    """
    Sign in existing user.
    """
    try:
        client = get_supabase_auth_client()
        email  = req.email.lower().strip()

        logger.info(f"Signing in user: {email}")

        res = client.auth.sign_in_with_password({
            "email":    email,
            "password": req.password,
        })

        if not res.user or not res.session:
            raise HTTPException(401, "Invalid email or password.")

        email_confirmed = res.user.email_confirmed_at is not None
        logger.info(f"Signin successful: {res.user.id}")

        return {
            "access_token":  res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type":    "bearer",
            "user_id":       res.user.id,
            "email":         res.user.email,
            "email_confirmed": email_confirmed,
        }

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "invalid login credentials" in error_msg or "invalid" in error_msg:
            raise HTTPException(401, "Invalid email or password.")
        if "email not confirmed" in error_msg:
            raise HTTPException(401, "Please confirm your email before signing in.")
        logger.error(f"Signin error: {e}")
        raise HTTPException(401, "Authentication failed. Please try again.")


@router.post("/refresh")
async def refresh_token(request: Request):
    """Refresh access token."""
    try:
        body          = await request.json()
        refresh_tok   = body.get("refresh_token")

        if not refresh_tok:
            raise HTTPException(400, "Refresh token required")

        client = get_supabase_auth_client()
        res    = client.auth.refresh_session(refresh_tok)

        if not res.session:
            raise HTTPException(401, "Session expired. Please sign in again.")

        return {
            "access_token":  res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type":    "bearer",
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Refresh error: {e}")
        raise HTTPException(401, "Session expired. Please sign in again.")


@router.post("/signout")
async def signout(request: Request):
    """Sign out (best-effort, always returns success)."""
    try:
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        if token:
            client = get_supabase_auth_client()
            client.auth.sign_out()
    except Exception:
        pass
    return {"message": "Signed out successfully", "success": True}


@router.post("/forgot-password", response_model=MessageResponse)
async def forgot_password(request: Request):
    """Send password reset email."""
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()

        if not email:
            raise HTTPException(400, "Email required")

        client = get_supabase_auth_client()
        client.auth.reset_password_email(
            email,
            options={"redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=recovery"},
        )
        logger.info(f"Password reset requested for: {email}")

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Password reset error (non-fatal): {e}")

    # Always return success — prevents email enumeration
    return {
        "message": "If an account exists with that email, you'll receive a reset link shortly.",
        "success": True,
    }


@router.post("/resend-verification", response_model=MessageResponse)
async def resend_verification(request: Request):
    """Resend email verification."""
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()

        if not email:
            raise HTTPException(400, "Email required")

        client = get_supabase_auth_client()
        client.auth.resend({"type": "signup", "email": email})
        logger.info(f"Verification resent to: {email}")

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Resend verification error (non-fatal): {e}")

    return {
        "message": "Verification email sent if the account exists.",
        "success": True,
    }


@router.get("/version")
async def version_check(app_version: str = "1.0.0"):
    """Check API/app version."""
    return {
        "current_version":      app_version,
        "min_required_version": "1.0.0",
        "update_required":      False,
        "update_message":       None,
    }


@router.get("/me")
async def get_current_user_info(
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    """Get current user info from token."""
    if not credentials:
        raise HTTPException(401, "Authentication required")

    try:
        client = get_supabase_auth_client()
        client.auth.set_session(credentials.credentials, "")
        user = client.auth.get_user()

        if not user or not user.user:
            raise HTTPException(401, "Invalid token")

        return {
            "user_id":  user.user.id,
            "email":    user.user.email,
            "metadata": user.user.user_metadata or {},
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Get user error: {e}")
        raise HTTPException(401, "Invalid or expired token")
