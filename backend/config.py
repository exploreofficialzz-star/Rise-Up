"""
RiseUp Backend Configuration — Production Ready (Pydantic v2)
"""

from pydantic_settings import BaseSettings
from pydantic import ConfigDict, Field
from typing import Optional, List


class Settings(BaseSettings):
    """
    Application settings with Pydantic v2 compatibility.
    All sensitive values loaded from environment variables.
    """
    
    # ═══════════════════════════════════════════════════════════════════════
    # APPLICATION
    # ═══════════════════════════════════════════════════════════════════════
    
    APP_NAME: str = "RiseUp"
    APP_ENV: str = Field(default="development", pattern="^(development|staging|production)$")
    APP_SECRET_KEY: str = "change-me-in-production"
    FRONTEND_URL: str = "http://localhost:3000"
    
    # ═══════════════════════════════════════════════════════════════════════
    # DATABASE (SUPABASE)
    # ═══════════════════════════════════════════════════════════════════════
    
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: str
    SUPABASE_SERVICE_ROLE_KEY: str
    
    # ═══════════════════════════════════════════════════════════════════════
    # AI SERVICES
    # ═══════════════════════════════════════════════════════════════════════
    
    GROQ_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    COHERE_API_KEY: Optional[str] = None
    OPENAI_API_KEY: Optional[str] = None
    ANTHROPIC_API_KEY: Optional[str] = None
    OPENROUTER_API_KEY: Optional[str] = None
    
    AI_PREFERENCE: str = Field(default="auto", pattern="^(auto|groq|gemini|openai|anthropic|cohere|openrouter)$")
    GROQ_MODEL: str = "llama-3.3-70b-versatile"
    OPENROUTER_MODEL: str = "mistralai/mistral-7b-instruct:free"
    AI_DEFAULT_TEMPERATURE: float = Field(default=0.7, ge=0.0, le=2.0)
    AI_MAX_TOKENS: int = Field(default=2000, ge=100, le=8000)
    
    # ═══════════════════════════════════════════════════════════════════════
    # WEB SEARCH
    # ═══════════════════════════════════════════════════════════════════════
    
    SERPER_API_KEY: Optional[str] = None
    TAVILY_API_KEY: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # EMAIL
    # ═══════════════════════════════════════════════════════════════════════
    
    SENDGRID_API_KEY: Optional[str] = None
    EMAIL_FROM: str = "agent@riseup.app"
    EMAIL_FROM_NAME: str = "RiseUp Agent"
    SMTP_HOST: Optional[str] = None
    SMTP_PORT: int = Field(default=465, ge=1, le=65535)
    SMTP_USER: Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # SOCIAL MEDIA
    # ═══════════════════════════════════════════════════════════════════════
    
    TWITTER_CLIENT_ID: Optional[str] = None
    TWITTER_CLIENT_SECRET: Optional[str] = None
    TWITTER_ACCESS_TOKEN: Optional[str] = None
    TWITTER_ACCESS_TOKEN_SECRET: Optional[str] = None
    
    LINKEDIN_CLIENT_ID: Optional[str] = None
    LINKEDIN_CLIENT_SECRET: Optional[str] = None
    LINKEDIN_ACCESS_TOKEN: Optional[str] = None
    LINKEDIN_PERSON_URN: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # PAYMENTS (FLUTTERWAVE)
    # ═══════════════════════════════════════════════════════════════════════
    
    FLUTTERWAVE_PUBLIC_KEY: Optional[str] = None
    FLUTTERWAVE_SECRET_KEY: Optional[str] = None
    FLUTTERWAVE_ENCRYPTION_KEY: Optional[str] = None
    FLUTTERWAVE_WEBHOOK_HASH: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # PRICING
    # ═══════════════════════════════════════════════════════════════════════
    
    SUBSCRIPTION_MONTHLY_USD: float = Field(default=15.99, ge=0)
    SUBSCRIPTION_YEARLY_USD: float = Field(default=99.99, ge=0)
    SUBSCRIPTION_LIFETIME_USD: float = Field(default=299.99, ge=0)
    
    # ═══════════════════════════════════════════════════════════════════════
    # ADVERTISING (ADMOB)
    # ═══════════════════════════════════════════════════════════════════════
    
    ADMOB_APP_ID: Optional[str] = None
    ADMOB_REWARDED_AD_UNIT: Optional[str] = None
    ADMOB_BANNER_AD_UNIT: Optional[str] = None
    ADMOB_INTERSTITIAL_AD_UNIT: Optional[str] = None
    ADMOB_APP_OPEN_AD_UNIT: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # CORS & SECURITY
    # ═══════════════════════════════════════════════════════════════════════
    
    ALLOWED_ORIGINS: str = "http://localhost:3000"
    JWT_ALGORITHM: str = Field(default="HS256", pattern="^(HS256|HS384|HS512|RS256)$")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=60, ge=5)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=30, ge=1)
    
    # ═══════════════════════════════════════════════════════════════════════
    # FIREBASE
    # ═══════════════════════════════════════════════════════════════════════
    
    FIREBASE_SERVICE_ACCOUNT_JSON: Optional[str] = None
    
    # ═══════════════════════════════════════════════════════════════════════
    # ADMIN
    # ═══════════════════════════════════════════════════════════════════════
    
    ADMIN_SECRET_KEY: Optional[str] = None
    ADMIN_EMAILS: Optional[str] = None  # Comma-separated list
    
    # ═══════════════════════════════════════════════════════════════════════
    # RATE LIMITING
    # ═══════════════════════════════════════════════════════════════════════
    
    RATE_LIMIT_AUTH: str = "5/minute"
    RATE_LIMIT_AI: str = "10/minute"
    RATE_LIMIT_GENERAL: str = "100/minute"
    
    # ═══════════════════════════════════════════════════════════════════════
    # PROPERTIES
    # ═══════════════════════════════════════════════════════════════════════
    
    @property
    def allowed_origins_list(self) -> List[str]:
        """Parse CORS origins string into list."""
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]
    
    @property
    def admin_emails_list(self) -> List[str]:
        """Parse admin emails string into list."""
        if not self.ADMIN_EMAILS:
            return []
        return [e.strip() for e in self.ADMIN_EMAILS.split(",") if e.strip()]
    
    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.APP_ENV == "development"
    
    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.APP_ENV == "production"
    
    @property
    def is_staging(self) -> bool:
        """Check if running in staging mode."""
        return self.APP_ENV == "staging"
    
    @property
    def docs_enabled(self) -> bool:
        """Check if API docs should be enabled."""
        return self.is_development or self.is_staging
    
    # ═══════════════════════════════════════════════════════════════════════
    # PYDANTIC V2 CONFIG
    # ═══════════════════════════════════════════════════════════════════════
    
    model_config = ConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
        validate_assignment=True,
    )


# Global settings instance
settings = Settings()


def get_settings() -> Settings:
    """Get application settings."""
    return settings
