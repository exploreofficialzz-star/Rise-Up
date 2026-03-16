"""Auth Router — Supabase-backed authentication"""
from fastapi import APIRouter, HTTPException
from supabase import create_client

from config import settings
from models.schemas import SignUpRequest, SignInRequest

router = APIRouter(prefix="/auth", tags=["Auth"])


def _get_client():
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)


@router.post("/signup")
async def signup(req: SignUpRequest):
    client = _get_client()
    try:
        res = client.auth.sign_up({
            "email": req.email,
            "password": req.password,
            "options": {"data": {"full_name": req.full_name or ""}}
        })
        if not res.user:
            raise HTTPException(400, "Signup failed")
        return {
            "user_id": res.user.id,
            "email": res.user.email,
            "access_token": res.session.access_token if res.session else None,
            "message": "Account created! Check your email to verify."
        }
    except Exception as e:
        raise HTTPException(400, str(e))


@router.post("/signin")
async def signin(req: SignInRequest):
    client = _get_client()
    try:
        res = client.auth.sign_in_with_password({
            "email": req.email,
            "password": req.password
        })
        if not res.user or not res.session:
            raise HTTPException(401, "Invalid credentials")
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "user_id": res.user.id,
            "email": res.user.email,
            "token_type": "bearer"
        }
    except Exception as e:
        raise HTTPException(401, str(e))


@router.post("/refresh")
async def refresh_token(refresh_token: str):
    client = _get_client()
    try:
        res = client.auth.refresh_session(refresh_token)
        if not res.session:
            raise HTTPException(401, "Token refresh failed")
        return {
            "access_token": res.session.access_token,
            "refresh_token": res.session.refresh_token,
        }
    except Exception as e:
        raise HTTPException(401, str(e))


@router.post("/signout")
async def signout(token: str):
    client = _get_client()
    client.auth.sign_out()
    return {"message": "Signed out"}
