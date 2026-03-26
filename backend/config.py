from pydantic_settings import BaseSettings
from typing import Optional, List
import logging

logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    APP_NAME: str = "RiseUp"
    APP_ENV: str = "development"
    APP_SECRET_KEY: str = "change-me-in-production"
    FRONTEND_URL: str = "http://localhost:3000"

    # ── Supabase ───────────────────────────────────────────────
    # Optional so Settings() never crashes at import time.
    # validate_supabase() is called in main.py on startup to fail
    # fast with a clear error instead of a confusing ImportError.
    SUPABASE_URL: Optional[str] = None
    SUPABASE_ANON_KEY: Optional[str] = None
    SUPABASE_SERVICE_ROLE_KEY: Optional[str] = None

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

    def validate_supabase(self) -> None:
        """Call on startup — fails fast with a clear error if Supabase vars are missing."""
        missing = [
            name for name, val in [
                ("SUPABASE_URL", self.SUPABASE_URL),
                ("SUPABASE_ANON_KEY", self.SUPABASE_ANON_KEY),
                ("SUPABASE_SERVICE_ROLE_KEY", self.SUPABASE_SERVICE_ROLE_KEY),
            ] if not val
        ]
        if missing:
            raise RuntimeError(
                f"\n\n❌ RiseUp startup failed — missing environment variables:\n"
                f"   {', '.join(missing)}\n\n"
                f"   → Go to Render dashboard → your service → Environment tab\n"
                f"   → Add the missing variables and redeploy.\n"
            )

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
