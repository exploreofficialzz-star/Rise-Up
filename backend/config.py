from pydantic_settings import BaseSettings
from typing import Optional, List


class Settings(BaseSettings):
    APP_NAME: str = "RiseUp"
    APP_ENV: str = "development"
    APP_SECRET_KEY: str = "change-me-in-production"
    FRONTEND_URL: str = "http://localhost:3000"

    # Supabase
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: str
    SUPABASE_SERVICE_ROLE_KEY: str

    # AI Keys
    GROQ_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    COHERE_API_KEY: Optional[str] = None
    OPENAI_API_KEY: Optional[str] = None
    ANTHROPIC_API_KEY: Optional[str] = None
    OPENROUTER_API_KEY: Optional[str] = None
    AI_PREFERENCE: str = "auto"
    GROQ_MODEL: str = "llama-3.3-70b-versatile"
    OPENROUTER_MODEL: str = "mistralai/mistral-7b-instruct:free"

    # Flutterwave
    FLUTTERWAVE_PUBLIC_KEY: Optional[str] = None
    FLUTTERWAVE_SECRET_KEY: Optional[str] = None
    FLUTTERWAVE_ENCRYPTION_KEY: Optional[str] = None
    FLUTTERWAVE_WEBHOOK_HASH: Optional[str] = None

    # Pricing
    SUBSCRIPTION_MONTHLY_USD: float = 15.99
    SUBSCRIPTION_YEARLY_USD: float = 99.99

    # AdMob
    ADMOB_APP_ID: Optional[str] = None
    ADMOB_REWARDED_AD_UNIT: Optional[str] = None
    ADMOB_BANNER_AD_UNIT: Optional[str] = None
    ADMOB_INTERSTITIAL_AD_UNIT: Optional[str] = None
    ADMOB_APP_OPEN_AD_UNIT: Optional[str] = None

    # CORS
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    @property
    def allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
