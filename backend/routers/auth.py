"""
RiseUp Auth Router — Production Ready (Pydantic v2)
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
# PYDANTIC MODELS (v2 Compatible)
# ═════════════════════════════════════════════════════════════════════════════

class SignUpRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    full_name: Optional[str] = Field(default=None, max_length=100)
    country_code: Optional[str] = Field(default=None, max_length=2)
    timezone: Optional[str] = Field(default="UTC")
    currency: str = Field(default="USD")
    language: str = Field(default="en")
    referral_code: Optional[str] = None


class SignInRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    user_id: str
    email: str
    email_confirmed: bool = False


class MessageResponse(BaseModel):
    message: str
    success: bool = True


# ═════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def get_supabase_client():
    """Get Supabase client with service role key."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_auth_client():
    """Get Supabase client with anon key for auth operations."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


# ═════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION ENDPOINTS
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignUpRequest, request: Request):
    """
    Register a new user.
    """
    try:
        client = get_supabase_auth_client()
        
        # Build user metadata
        user_metadata = {
            "full_name": req.full_name or "",
            "country_code": req.country_code,
            "timezone": req.timezone,
            "currency": req.currency,
            "language": req.language,
            "referral_code": req.referral_code,
        }
        
        # Remove None values
        user_metadata = {k: v for k, v in user_metadata.items() if v is not None}
        
        logger.info(f"Signing up user: {req.email}")
        
        res = client.auth.sign_up({
            "email": req.email.lower().strip(),
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
            "access_token": res.session.access_token if res.session else "",
            "refresh_token": res.session.refresh_token if res.session else "",
            "token_type": "bearer",
            "user_id": res.user.id,
            "email": res.user.email,
            "email_confirmed": res.user.email_confirmed_at is not None,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "already registered" in error_msg:
            raise HTTPException(status_code=400, detail="An account with this email already exists.")
        logger.error(f"Signup error: {e}")
        raise HTTPException(status_code=400, detail=f"Registration failed: {str(e)}")


@router.post("/signin", response_model=AuthResponse)
async def signin(req: SignInRequest, request: Request):
    """
    Sign in existing user.
    """
    try:
        client = get_supabase_auth_client()
        
        email = req.email.lower().strip()
        logger.info(f"Signing in user: {email}")
        
        res = client.auth.sign_in_with_password({
            "email": email,
            "password": req.password
        })
        
        if not res.user or not res.session:
            logger.warning(f"Invalid credentials for: {email}")
            raise HTTPException(status_code=401, detail="Invalid email or password.")
        
        email_confirmed = res.user.email_confirmed_at is not None
        
        if not email_confirmed:
            logger.warning(f"Email not confirmed for: {email}")
            # Still allow login but you could block here if needed
        
        logger.info(f"Signin successful: {res.user.id}")
        
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type": "bearer",
            "user_id": res.user.id,
            "email": res.user.email,
            "email_confirmed": email_confirmed,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "invalid login credentials" in error_msg:
            raise HTTPException(status_code=401, detail="Invalid email or password.")
        logger.error(f"Signin error: {e}")
        raise HTTPException(status_code=401, detail="Authentication failed.")


@router.post("/refresh")
async def refresh_token(request: Request):
    """
    Refresh access token.
    """
    try:
        body = await request.json()
        refresh_token = body.get("refresh_token")
        
        if not refresh_token:
            raise HTTPException(status_code=400, detail="Refresh token required")
        
        client = get_supabase_auth_client()
        res = client.auth.refresh_session(refresh_token)
        
        if not res.session:
            raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")
        
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "token_type": "bearer",
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Refresh error: {e}")
        raise HTTPException(status_code=401, detail="Session expired.")


@router.post("/forgot-password", response_model=MessageResponse)
async def forgot_password(request: Request):
    """
    Send password reset email.
    """
    try:
        body = await request.json()
        email = body.get("email", "").lower().strip()
        
        if not email:
            raise HTTPException(status_code=400, detail="Email required")
        
        client = get_supabase_auth_client()
        client.auth.reset_password_email(
            email,
            options={"redirect_to": f"{settings.FRONTEND_URL}/auth/callback?type=recovery"}
        )
        
        logger.info(f"Password reset requested for: {email}")
        
    except Exception as e:
        logger.warning(f"Password reset error: {e}")
    
    # Always return success to prevent email enumeration
    return {
        "message": "If an account exists with that email, you'll receive a reset link shortly.",
        "success": True
    }


@router.get("/version")
async def version_check(app_version: str = "1.0.0"):
    """
    Check API version.
    """
    return {
        "current_version": app_version,
        "min_required_version": "1.0.0",
        "update_required": False,
        "update_message": None,
    }


@router.get("/me")
async def get_current_user_info(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """
    Get current user info.
    """
    if not credentials:
        raise HTTPException(status_code=401, detail="Authentication required")
    
    try:
        client = get_supabase_auth_client()
        client.auth.set_session(credentials.credentials, "")
        user = client.auth.get_user()
        
        if not user or not user.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        return {
            "user_id": user.user.id,
            "email": user.user.email,
            "metadata": user.user.user_metadata or {},
        }
        
    except Exception as e:
        logger.error(f"Get user error: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")
