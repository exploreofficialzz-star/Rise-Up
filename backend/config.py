"""
RiseUp Backend Configuration — Production Ready (Pydantic v2)
"""

from pydantic_settings import BaseSettings
from pydantic import ConfigDict
from typing import Optional, List


class Settings(BaseSettings):
    """Application settings with Pydantic v2 compatibility."""
    
    APP_NAME: str = "RiseUp"
    APP_ENV: str = "development"
    APP_SECRET_KEY: str = "change-me-in-production"
    FRONTEND_URL: str = "http://localhost:3000"

    # ── Supabase ───────────────────────────────────────────────
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: str
    SUPABASE_SERVICE_ROLE_KEY: str

    # ── AI Keys ────────────────────────────────────────────────
    GROQ_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    COHERE_API_KEY: Optional[str] = None
    OPENAI_API_KEY: Optional[str] = None
    ANTHROPIC_API_KEY: Optional[str] = None
    OPENROUTER_API_KEY: Optional[str] = None
    AI_PREFERENCE: str = "auto"
    GROQ_MODEL: str = "llama-3.3-70b-versatile"
    OPENROUTER_MODEL: str = "mistralai/mistral-7b-instruct:free"

    # ── Web Search (for agent real-world research) ─────────────
    SERPER_API_KEY: Optional[str] = None
    TAVILY_API_KEY: Optional[str] = None

    # ── Email Sending ──────────────────────────────────────────
    SENDGRID_API_KEY: Optional[str] = None
    EMAIL_FROM: str = "agent@riseup.app"
    EMAIL_FROM_NAME: str = "RiseUp Agent"
    SMTP_HOST: Optional[str] = None
    SMTP_PORT: int = 465
    SMTP_USER: Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None

    # ── Social Media ───────────────────────────────────────────
    TWITTER_CLIENT_ID: Optional[str] = None
    TWITTER_CLIENT_SECRET: Optional[str] = None
    TWITTER_ACCESS_TOKEN: Optional[str] = None
    LINKEDIN_CLIENT_ID: Optional[str] = None
    LINKEDIN_CLIENT_SECRET: Optional[str] = None
    LINKEDIN_ACCESS_TOKEN: Optional[str] = None
    LINKEDIN_PERSON_URN: Optional[str] = None

    # ── Payments ───────────────────────────────────────────────
    FLUTTERWAVE_PUBLIC_KEY: Optional[str] = None
    FLUTTERWAVE_SECRET_KEY: Optional[str] = None
    FLUTTERWAVE_ENCRYPTION_KEY: Optional[str] = None
    FLUTTERWAVE_WEBHOOK_HASH: Optional[str] = None

    # ── Pricing ────────────────────────────────────────────────
    SUBSCRIPTION_MONTHLY_USD: float = 15.99
    SUBSCRIPTION_YEARLY_USD: float = 99.99

    # ── AdMob ──────────────────────────────────────────────────
    ADMOB_APP_ID: Optional[str] = None
    ADMOB_REWARDED_AD_UNIT: Optional[str] = None
    ADMOB_BANNER_AD_UNIT: Optional[str] = None
    ADMOB_INTERSTITIAL_AD_UNIT: Optional[str] = None
    ADMOB_APP_OPEN_AD_UNIT: Optional[str] = None

    # ── CORS ───────────────────────────────────────────────────
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    # ── Firebase ───────────────────────────────────────────────
    FIREBASE_SERVICE_ACCOUNT_JSON: Optional[str] = None

    # ── Admin ──────────────────────────────────────────────────
    ADMIN_SECRET_KEY: Optional[str] = None

    @property
    def allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]

    # PYDANTIC V2 FIX: Changed from class Config to model_config
    model_config = ConfigDict(
        env_file=".env",
        case_sensitive=True,
        extra="ignore",  # Ignore extra env vars instead of erroring
        env_file_encoding="utf-8",
    )


settings = Settings()
