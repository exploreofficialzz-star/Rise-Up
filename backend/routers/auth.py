"""
RiseUp Auth Router — Production Ready (Pydantic v2)

OTP Flow (v3 — merged):
  • signup            → Supabase sends 6-digit OTP (enable_confirmations=true)
  • verify-otp        → submit code → returns full session tokens
  • forgot-password   → sends OTP via sign_in_with_otp (not a magic link)
  • verify-reset-otp  → submit code → returns temp session for password change
  • reset-password    → uses temp session to update_user password
  • /auth/me          → validates JWT directly (no set_session corruption),
                        merges DB profile row + JWT metadata into flat response
"""
import logging
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
    """Service-role client — bypasses RLS. Use only for trusted server ops."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_auth_client():
    """Anon-key client — respects RLS. Use for all user-facing auth calls."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


# ═════════════════════════════════════════════════════════════════════════════
# ENDPOINTS
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignUpRequest, request: Request):
    """
    Register a new user.
    With enable_confirmations=true, Supabase sends a 6-digit OTP to the email.
    Returns empty tokens + email_confirmed=False → Flutter shows OTP screen.
    """
    try:
        client = get_supabase_auth_client()

        user_metadata = {
            k: v for k, v in {
                "full_name":     req.full_name or "",
                "country_code":  req.country_code,
                "timezone":      req.timezone,
                "currency":      req.currency,
                "language":      req.language,
                "referral_code": req.referral_code,
            }.items() if v is not None
        }

        logger.info(f"Signing up user: {req.email}")

        res = client.auth.sign_up({
            "email":    req.email.lower().strip(),
            "password": req.password,
            "options": {
                "data": user_metadata,
            },
        })

        if not res.user:
            raise HTTPException(400, "Signup failed. Please try again.")

        has_session     = res.session is not None
        email_confirmed = res.user.email_confirmed_at is not None

        logger.info(
            f"Signup: {res.user.id} — "
            f"OTP sent={'yes' if not has_session else 'no (auto-confirmed)'}"
        )

        return {
            "access_token":    res.session.access_token  if has_session else "",
            "refresh_token":   res.session.refresh_token if has_session else "",
            "token_type":      "bearer",
            "user_id":         res.user.id,
            "email":           res.user.email,
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


@router.post("/verify-otp", response_model=AuthResponse)
async def verify_email_otp(request: Request):
    """
    Verify the 6-digit OTP sent after signup.
    On success returns a full session so Flutter logs the user in immediately.
    """
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()
        token = body.get("token", "").strip()

        if not email or not token:
            raise HTTPException(400, "Email and code are required")

        if len(token) != 6 or not token.isdigit():
            raise HTTPException(400, "Code must be exactly 6 digits")

        client = get_supabase_auth_client()
        res = client.auth.verify_otp({
            "email": email,
            "token": token,
            "type":  "signup",
        })

        if not res.user or not res.session:
            raise HTTPException(400, "Invalid or expired code. Please try again.")

        logger.info(f"Email OTP verified for user: {res.user.id}")

        return {
            "access_token":    res.session.access_token,
            "refresh_token":   res.session.refresh_token,
            "token_type":      "bearer",
            "user_id":         res.user.id,
            "email":           res.user.email,
            "email_confirmed": True,
        }

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "token" in error_msg and ("invalid" in error_msg or "expired" in error_msg):
            raise HTTPException(400, "Code is invalid or has expired. Request a new one.")
        logger.error(f"OTP verify error: {e}")
        raise HTTPException(400, "Verification failed. Please try again.")


@router.post("/signin", response_model=AuthResponse)
async def signin(req: SignInRequest, request: Request):
    """Sign in existing user."""
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
            "access_token":    res.session.access_token,
            "refresh_token":   res.session.refresh_token,
            "token_type":      "bearer",
            "user_id":         res.user.id,
            "email":           res.user.email,
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
        body        = await request.json()
        refresh_tok = body.get("refresh_token")

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
    """
    Send a 6-digit OTP for password reset.
    sign_in_with_otp delivers a code the user types in — not a magic link.
    should_create_user=False — only existing accounts receive the code.
    """
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()

        if not email:
            raise HTTPException(400, "Email required")

        client = get_supabase_auth_client()
        client.auth.sign_in_with_otp({
            "email": email,
            "options": {
                "should_create_user": False,
            },
        })
        logger.info(f"Password reset OTP dispatched for: {email}")

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Password reset OTP dispatch error (non-fatal): {e}")

    # Always return success — prevents email enumeration
    return {
        "message": "If an account exists for that email, a 6-digit code is on its way.",
        "success": True,
    }


@router.post("/verify-reset-otp")
async def verify_reset_otp(request: Request):
    """
    Verify the 6-digit OTP from the forgot-password flow.
    Returns a temporary session the client uses to call /reset-password.
    """
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()
        token = body.get("token", "").strip()

        if not email or not token:
            raise HTTPException(400, "Email and code are required")

        if len(token) != 6 or not token.isdigit():
            raise HTTPException(400, "Code must be exactly 6 digits")

        client = get_supabase_auth_client()
        # type="email" for OTPs sent via sign_in_with_otp
        res = client.auth.verify_otp({
            "email": email,
            "token": token,
            "type":  "email",
        })

        if not res.user or not res.session:
            raise HTTPException(400, "Invalid or expired code. Please request a new one.")

        logger.info(f"Reset OTP verified for: {res.user.id}")

        return {
            "access_token":  res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "user_id":       res.user.id,
        }

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e).lower()
        if "token" in error_msg and ("invalid" in error_msg or "expired" in error_msg):
            raise HTTPException(400, "Code is invalid or has expired. Request a new one.")
        logger.error(f"Reset OTP verify error: {e}")
        raise HTTPException(400, "Verification failed. Please try again.")


@router.post("/reset-password", response_model=MessageResponse)
async def reset_password(request: Request):
    """
    Set a new password using the temp session from /verify-reset-otp.
    Client sends access_token + refresh_token + new password.
    """
    try:
        body             = await request.json()
        access_token     = body.get("access_token",  "").strip()
        refresh_token_v  = body.get("refresh_token", "").strip()
        new_password     = body.get("password", "")

        if not access_token or not new_password:
            raise HTTPException(400, "Access token and new password are required")

        if len(new_password) < 8:
            raise HTTPException(400, "Password must be at least 8 characters")

        if not any(c.isalpha() for c in new_password) or \
           not any(c.isdigit() for c in new_password):
            raise HTTPException(400, "Password must contain letters and numbers")

        client = get_supabase_auth_client()
        client.auth.set_session(access_token, refresh_token_v)
        res = client.auth.update_user({"password": new_password})

        if not res.user:
            raise HTTPException(400, "Failed to reset password. Please try again.")

        logger.info(f"Password reset successful for: {res.user.id}")
        return {
            "message": "Password reset successfully. You can now sign in.",
            "success": True,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Reset password error: {e}")
        raise HTTPException(400, "Failed to reset password. Please try again.")


@router.post("/resend-verification", response_model=MessageResponse)
async def resend_verification(request: Request):
    """Resend the 6-digit signup OTP."""
    try:
        body  = await request.json()
        email = body.get("email", "").lower().strip()

        if not email:
            raise HTTPException(400, "Email required")

        client = get_supabase_auth_client()
        client.auth.resend({"type": "signup", "email": email})
        logger.info(f"Signup OTP resent to: {email}")

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Resend OTP error (non-fatal): {e}")

    return {
        "message": "A new 6-digit code has been sent if the account exists.",
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
    """
    Get current user info + profile.

    FIX: Validates JWT directly via get_user(jwt) — never uses set_session()
    which corrupts the auth client state causing endless 401 refresh loops.
    Merges DB profile row with JWT metadata into a flat response so Flutter
    can read full_name / stage / avatar_url at the top level.
    """
    if not credentials:
        raise HTTPException(401, "Authentication required")

    token = credentials.credentials

    try:
        client = get_supabase_auth_client()

        # ── 1. Validate JWT directly — no set_session ────────────────────
        user_response = client.auth.get_user(token)
        if not user_response or not user_response.user:
            raise HTTPException(401, "Invalid token")

        user      = user_response.user
        metadata  = user.user_metadata or {}
        user_id   = user.id

        # ── 2. Pull real profile row (service role bypasses RLS) ─────────
        profile_row: dict = {}
        try:
            svc_client = get_supabase_client()
            res = (
                svc_client.table("profiles")
                .select(
                    "full_name, username, stage, avatar_url, country, "
                    "currency, bio, subscription_tier, is_premium"
                )
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
            profile_row = res.data or {}
        except Exception as db_err:
            logger.warning(f"/auth/me profile DB lookup failed (non-fatal): {db_err}")

        # ── 3. Merge: DB row wins, fall back to JWT metadata ─────────────
        full_name  = profile_row.get("full_name")  or metadata.get("full_name")  or ""
        username   = profile_row.get("username")   or metadata.get("username")   or ""
        stage      = profile_row.get("stage")      or "survival"
        avatar_url = profile_row.get("avatar_url") or metadata.get("avatar_url")
        country    = profile_row.get("country")    or metadata.get("country_code", "")
        currency   = profile_row.get("currency")   or metadata.get("currency", "USD")
        bio        = profile_row.get("bio", "")
        is_premium = (
            profile_row.get("is_premium")
            or profile_row.get("subscription_tier") == "premium"
            or False
        )

        logger.info(f"/auth/me OK: {user_id}")

        return {
            "user_id":           user_id,
            "id":                user_id,
            "email":             user.email,
            "full_name":         full_name,
            "username":          username,
            "stage":             stage,
            "avatar_url":        avatar_url,
            "country":           country,
            "currency":          currency,
            "bio":               bio,
            "is_premium":        is_premium,
            "subscription_tier": profile_row.get("subscription_tier", "free"),
            "metadata":          metadata,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Get user error: {e}")
        raise HTTPException(401, "Invalid or expired token")
