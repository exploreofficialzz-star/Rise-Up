"""Auth helpers — token validation using Supabase JWT"""
import logging
from typing import Optional
from fastapi import HTTPException, Depends, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from supabase import create_client

from config import settings

logger = logging.getLogger(__name__)
bearer = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer)
) -> dict:
    """Validate Supabase JWT and return user info"""
    token = credentials.credentials
    try:
        client = create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)
        user = client.auth.get_user(token)
        if not user or not user.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": user.user.id, "email": user.user.email, "token": token}
    except Exception as e:
        logger.error(f"Auth error: {e}")
        raise HTTPException(status_code=401, detail="Authentication failed")


async def get_current_user_optional(
    request: Request
) -> Optional[dict]:
    """Validate Supabase JWT if present, return None if no token or invalid"""
    auth_header = request.headers.get("authorization")
    
    if not auth_header:
        return None
    
    try:
        # Extract token from "Bearer <token>"
        scheme, _, token = auth_header.partition(" ")
        if scheme.lower() != "bearer" or not token:
            return None
        
        client = create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)
        user = client.auth.get_user(token)
        
        if not user or not user.user:
            return None
            
        return {"id": user.user.id, "email": user.user.email, "token": token}
        
    except Exception as e:
        logger.debug(f"Optional auth failed (this is OK): {e}")
        return None
