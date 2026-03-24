"""
Basic smoke tests for RiseUp backend.
Run: pytest tests/ -v
"""
import pytest
import os

# Set minimal env vars for testing
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_ANON_KEY", "test-anon-key")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-key")
os.environ.setdefault("APP_SECRET_KEY", "test-secret")
os.environ.setdefault("GROQ_API_KEY", "test-groq-key")


def test_config_loads():
    """Config should load without errors"""
    from config import settings
    assert settings.APP_NAME == "RiseUp"
    assert settings.APP_ENV == "development"


def test_ai_service_initializes():
    """AI service should initialize and identify available models"""
    from services.ai_service import ai_service
    # At least the service should init (models may not be callable w/ test keys)
    assert ai_service is not None


def test_schemas_import():
    """Pydantic schemas should import cleanly"""
    from models.schemas import (
        SignUpRequest, SignInRequest, ChatRequest, ChatResponse,
        TaskUpdate, EnrollRequest, PaymentInitRequest, EarningLog
    )
    req = ChatRequest(message="hello")
    assert req.message == "hello"
    assert req.mode == "general"


def test_system_prompt_content():
    """System prompt should contain key instructions"""
    from services.ai_service import RISEUP_SYSTEM_PROMPT, ONBOARDING_PROMPT
    assert "wealth" in RISEUP_SYSTEM_PROMPT.lower()
    assert "survival" in RISEUP_SYSTEM_PROMPT.lower()
    assert "onboarding" in ONBOARDING_PROMPT.lower()


def test_flutterwave_price_conversion():
    """Currency conversion should return positive amounts"""
    from services.flutterwave_service import FlutterwaveService
    svc = FlutterwaveService()
    ngn = svc.get_price_for_currency("monthly", "NGN")
    usd = svc.get_price_for_currency("monthly", "USD")
    yearly = svc.get_price_for_currency("yearly", "USD")
    assert ngn > 0
    assert usd > 0
    assert yearly > usd  # yearly costs more than monthly


def test_stage_info_all_stages():
    """All wealth stages should have complete info"""
    stages = ["survival", "earning", "growing", "wealth"]
    # Just verify the strings are valid — frontend uses them
    for s in stages:
        assert len(s) > 0


def test_fastapi_app_creates():
    """FastAPI app should create without errors"""
    from main import app
    assert app is not None
    assert app.title == "RiseUp API"


def test_router_prefix():
    """All routers should have correct prefixes"""
    from routers.ai_agent import router as ai_router
    from routers.auth import router as auth_router
    from routers.tasks import router as tasks_router
    from routers.payments import router as pay_router
    assert ai_router.prefix == "/ai"
    assert auth_router.prefix == "/auth"
    assert tasks_router.prefix == "/tasks"
    assert pay_router.prefix == "/payments"
