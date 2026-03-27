"""
RiseUp Pydantic Models — Global Production Ready (Pydantic v2)
"""

from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator
from typing import Optional, List, Any, Dict
from datetime import datetime
from enum import Enum
import re


# ═════════════════════════════════════════════════════════════════════════════
# GLOBAL ENUMS
# ═════════════════════════════════════════════════════════════════════════════

class CurrencyCode(str, Enum):
    USD = "USD"
    EUR = "EUR"
    GBP = "GBP"
    JPY = "JPY"
    CNY = "CNY"
    NGN = "NGN"
    INR = "INR"
    BRL = "BRL"
    MXN = "MXN"
    ZAR = "ZAR"
    KES = "KES"
    GHS = "GHS"
    PHP = "PHP"
    IDR = "IDR"
    PKR = "PKR"
    BDT = "BDT"
    EGP = "EGP"
    TRY = "TRY"
    RUB = "RUB"
    AUD = "AUD"
    CAD = "CAD"
    BTC = "BTC"
    ETH = "ETH"
    USDT = "USDT"


class LanguageCode(str, Enum):
    EN = "en"
    ES = "es"
    FR = "fr"
    DE = "de"
    PT = "pt"
    HI = "hi"
    AR = "ar"
    ZH = "zh"
    JA = "ja"
    RU = "ru"
    BN = "bn"
    SW = "sw"
    YO = "yo"
    IG = "ig"
    HA = "ha"


class RegionCode(str, Enum):
    NORTH_AMERICA = "north_america"
    EUROPE = "europe"
    LATIN_AMERICA = "latin_america"
    AFRICA_WEST = "africa_west"
    AFRICA_EAST = "africa_east"
    AFRICA_SOUTH = "africa_south"
    MIDDLE_EAST = "middle_east"
    SOUTH_ASIA = "south_asia"
    EAST_ASIA = "east_asia"
    SOUTHEAST_ASIA = "southeast_asia"
    OCEANIA = "oceania"


class PaymentMethod(str, Enum):
    PAYPAL = "paypal"
    WISE = "wise"
    PAYONEER = "payoneer"
    FLUTTERWAVE = "flutterwave"
    STRIPE = "stripe"
    CRYPTO_USDT = "crypto_usdt"
    BANK_TRANSFER = "bank_transfer"
    MOBILE_MONEY = "mobile_money"
    MPESA = "mpesa"
    UPI = "upi"


class UserStage(str, Enum):
    SURVIVAL = "survival"
    STABILITY = "stability"
    GROWTH = "growth"
    WEALTH = "wealth"
    LEGACY = "legacy"


class WealthType(str, Enum):
    ACTIVE = "active"
    PASSIVE = "passive"
    PORTFOLIO = "portfolio"
    HYBRID = "hybrid"


class LearningStyle(str, Enum):
    VISUAL = "visual"
    AUDITORY = "auditory"
    READING = "reading"
    KINESTHETIC = "kinesthetic"
    SOCIAL = "social"


class RiskTolerance(str, Enum):
    CONSERVATIVE = "conservative"
    MODERATE = "moderate"
    AGGRESSIVE = "aggressive"


class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    BLOCKED = "blocked"
    CANCELLED = "cancelled"


class NotificationType(str, Enum):
    SYSTEM = "system"
    GOAL_ACHIEVED = "goal_achieved"
    TASK_DUE = "task_due"
    STREAK_BROKEN = "streak_broken"
    REFERRAL = "referral"
    PAYMENT = "payment"
    AI_INSIGHT = "ai_insight"


class PaymentStatus(str, Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"


class IncomeType(str, Enum):
    YOUTUBE = "youtube"
    TIKTOK = "tiktok"
    INSTAGRAM = "instagram"
    FREELANCE = "freelance"
    ECOMMERCE = "ecommerce"
    DROPSHIPPING = "dropshipping"
    AFFILIATE = "affiliate"
    CONTENT = "content"
    SAAS = "saas"
    APP_DEVELOPMENT = "app_development"
    ONLINE_COURSES = "online_courses"
    DIGITAL_PRODUCTS = "digital_products"
    PRINT_ON_DEMAND = "print_on_demand"
    VIRTUAL_ASSISTANT = "virtual_assistant"
    TRANSLATION = "translation"
    PHYSICAL = "physical"
    FOOD_DELIVERY = "food_delivery"
    RIDE_SHARING = "ride_sharing"
    REAL_ESTATE = "real_estate"
    STOCK_TRADING = "stock_trading"
    CRYPTO_TRADING = "crypto_trading"
    REMOTE_JOB = "remote_job"
    OTHER = "other"


# ═════════════════════════════════════════════════════════════════════════════
# BASE CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

class BaseSchema(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        populate_by_name=True,
        str_strip_whitespace=True,
        use_enum_values=True,
        extra="ignore",
    )


# ═════════════════════════════════════════════════════════════════════════════
# AUTH MODELS
# ═════════════════════════════════════════════════════════════════════════════

class SignUpRequest(BaseSchema):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    full_name: Optional[str] = Field(default=None, max_length=100)
    country_code: Optional[str] = Field(default=None, max_length=2)
    timezone: Optional[str] = Field(default="UTC")
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    language: LanguageCode = Field(default=LanguageCode.EN)
    referral_code: Optional[str] = Field(default=None, max_length=20)

    @field_validator('full_name')
    @classmethod
    def sanitize_name(cls, v):
        if v and len(v) > 100:
            raise ValueError('Name too long (max 100 characters)')
        return v.strip() if v else v

    @field_validator('password')
    @classmethod
    def validate_password_strength(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if len(v) > 128:
            raise ValueError('Password too long (max 128 characters)')
        if not re.search(r'[A-Za-z]', v) or not re.search(r'\d', v):
            raise ValueError('Password must contain at least one letter and one number')
        return v


class SignUpResponse(BaseSchema):
    user_id: str
    email: str
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    email_confirmed: bool = False
    onboarding_complete: bool = False
    currency: str = "USD"
    language: str = "en"
    message: str


class SignInRequest(BaseSchema):
    email: EmailStr
    password: str


class SignInResponse(BaseSchema):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 3600
    user_id: str
    email: str
    email_confirmed: bool = False
    onboarding_complete: bool = False
    currency: str = "USD"
    language: str = "en"


class TokenRefreshResponse(BaseSchema):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 3600


class PasswordResetRequest(BaseSchema):
    email: EmailStr


class PasswordUpdateRequest(BaseSchema):
    access_token: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator('new_password')
    @classmethod
    def validate_password_strength(cls, v):
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if len(v) > 128:
            raise ValueError('Password too long (max 128 characters)')
        if not re.search(r'[A-Za-z]', v) or not re.search(r'\d', v):
            raise ValueError('Password must contain at least one letter and one number')
        return v


class MessageResponse(BaseSchema):
    message: str
    success: bool = True


class VersionCheckResponse(BaseSchema):
    current_version: str
    min_required_version: str
    update_required: bool
    update_message: Optional[str] = None
    download_url: Optional[str] = None
    force_update: bool = False
    release_notes: Optional[str] = None


class AuthResponse(BaseSchema):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str


# ═════════════════════════════════════════════════════════════════════════════
# PROFILE MODELS
# ═════════════════════════════════════════════════════════════════════════════

class ProfileUpdate(BaseSchema):
    full_name: Optional[str] = Field(default=None, max_length=100)
    phone: Optional[str] = Field(default=None, max_length=20)
    country: Optional[str] = Field(default=None, max_length=2)
    country_region: Optional[RegionCode] = None
    currency: Optional[CurrencyCode] = Field(default=CurrencyCode.USD)
    language: Optional[LanguageCode] = Field(default=LanguageCode.EN)
    timezone: Optional[str] = Field(default="UTC")
    bio: Optional[str] = Field(default=None, max_length=500)
    status: Optional[str] = Field(default=None, max_length=200)
    avatar_url: Optional[str] = None
    wealth_type: Optional[WealthType] = None
    learning_style: Optional[LearningStyle] = None
    risk_tolerance: Optional[RiskTolerance] = None
    stage: Optional[UserStage] = Field(default=UserStage.SURVIVAL)
    monthly_income: Optional[float] = Field(default=None, ge=0)
    monthly_income_currency: CurrencyCode = Field(default=CurrencyCode.USD)
    income_sources: Optional[List[str]] = None
    monthly_expenses: Optional[float] = Field(default=None, ge=0)
    monthly_expenses_currency: CurrencyCode = Field(default=CurrencyCode.USD)
    current_skills: Optional[List[str]] = None
    desired_skills: Optional[List[str]] = None
    short_term_goal: Optional[str] = Field(default=None, max_length=200)
    long_term_goal: Optional[str] = Field(default=None, max_length=200)
    ambitions: Optional[str] = Field(default=None, max_length=500)
    health_energy: Optional[str] = None
    obstacles: Optional[str] = Field(default=None, max_length=500)
    available_hours_per_day: Optional[float] = Field(default=None, ge=0, le=24)
    onboarding_completed: Optional[bool] = None
    survival_mode: Optional[bool] = Field(default=False)
    preferred_payment_methods: Optional[List[PaymentMethod]] = None
    social_links: Optional[Dict[str, str]] = None


class ProfileResponse(BaseSchema):
    user_id: str
    email: str
    full_name: Optional[str] = None
    phone: Optional[str] = None
    country: Optional[str] = None
    country_region: Optional[str] = None
    currency: str = "USD"
    language: str = "en"
    timezone: str = "UTC"
    bio: Optional[str] = None
    status: Optional[str] = None
    avatar_url: Optional[str] = None
    wealth_type: Optional[str] = None
    learning_style: Optional[str] = None
    risk_tolerance: Optional[str] = None
    stage: str = "survival"
    monthly_income: Optional[float] = None
    income_sources: Optional[List[str]] = None
    monthly_expenses: Optional[float] = None
    current_skills: Optional[List[str]] = None
    short_term_goal: Optional[str] = None
    long_term_goal: Optional[str] = None
    ambitions: Optional[str] = None
    onboarding_completed: bool = False
    survival_mode: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


# ═════════════════════════════════════════════════════════════════════════════
# CHAT MODELS
# ═════════════════════════════════════════════════════════════════════════════

class ChatMessage(BaseSchema):
    role: str = Field(..., pattern="^(system|user|assistant)$")
    content: str = Field(..., max_length=8000)
    timestamp: Optional[datetime] = None


class ChatRequest(BaseSchema):
    message: str = Field(..., min_length=1, max_length=4000)
    conversation_id: Optional[str] = None
    mode: str = Field(default="general", pattern="^(general|workflow|coach|agent)$")
    preferred_model: Optional[str] = None
    language: Optional[LanguageCode] = None
    context_data: Optional[Dict[str, Any]] = None

    @field_validator('message')
    @classmethod
    def validate_message(cls, v):
        if not v or not v.strip():
            raise ValueError('Message cannot be empty')
        if len(v) > 4000:
            raise ValueError('Message too long (max 4000 characters)')
        return v.strip()


class ChatResponse(BaseSchema):
    content: str
    conversation_id: str
    message_id: str
    ai_model: str
    tokens_used: Optional[int] = None
    onboarding_complete: bool = False
    extracted_profile: Optional[dict] = None
    suggested_tasks: Optional[list] = None
    suggested_workflows: Optional[list] = None
    detected_language: Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# TASK MODELS
# ═════════════════════════════════════════════════════════════════════════════

class TaskCreate(BaseSchema):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(default=None, max_length=1000)
    category: Optional[str] = None
    priority: int = Field(default=1, ge=1, le=5)
    estimated_minutes: Optional[int] = Field(default=None, ge=0)
    due_date: Optional[datetime] = None
    tags: List[str] = Field(default=[])
    is_ai_generated: bool = False
    source_workflow_id: Optional[str] = None


class TaskUpdate(BaseSchema):
    title: Optional[str] = Field(default=None, max_length=200)
    description: Optional[str] = None
    status: Optional[TaskStatus] = None
    priority: Optional[int] = Field(default=None, ge=1, le=5)
    actual_minutes: Optional[int] = Field(default=None, ge=0)
    actual_earnings: Optional[float] = Field(default=None, ge=0)
    earnings_currency: CurrencyCode = Field(default=CurrencyCode.USD)
    completion_notes: Optional[str] = None


class TaskResponse(BaseSchema):
    id: str
    user_id: str
    title: str
    description: Optional[str] = None
    status: str
    priority: int
    estimated_minutes: Optional[int] = None
    actual_minutes: Optional[int] = None
    actual_earnings: Optional[float] = None
    earnings_currency: str = "USD"
    due_date: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    tags: List[str] = []
    is_ai_generated: bool = False
    created_at: datetime
    updated_at: Optional[datetime] = None


class GenerateTasksRequest(BaseSchema):
    count: int = Field(default=5, ge=1, le=20)
    category: Optional[str] = None
    skill_focus: Optional[str] = None
    income_target: Optional[float] = None
    currency: CurrencyCode = Field(default=CurrencyCode.USD)


# ═════════════════════════════════════════════════════════════════════════════
# GOAL MODELS
# ═════════════════════════════════════════════════════════════════════════════

class GoalCreate(BaseSchema):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(default=None, max_length=1000)
    category: str = Field(default="income")
    target_amount: Optional[float] = Field(default=None, ge=0)
    target_currency: CurrencyCode = Field(default=CurrencyCode.USD)
    deadline: Optional[datetime] = None
    is_public: bool = False


class GoalUpdate(BaseSchema):
    title: Optional[str] = Field(default=None, max_length=200)
    description: Optional[str] = None
    target_amount: Optional[float] = Field(default=None, ge=0)
    deadline: Optional[datetime] = None
    is_public: Optional[bool] = None
    status: Optional[str] = Field(default=None, pattern="^(active|completed|abandoned)$")


class GoalResponse(BaseSchema):
    id: str
    user_id: str
    title: str
    description: Optional[str] = None
    category: str
    target_amount: Optional[float] = None
    target_currency: str = "USD"
    current_amount: float = 0.0
    progress_percent: float = 0.0
    deadline: Optional[datetime] = None
    status: str
    is_public: bool = False
    created_at: datetime
    updated_at: Optional[datetime] = None


# ═════════════════════════════════════════════════════════════════════════════
# SKILL MODELS
# ═════════════════════════════════════════════════════════════════════════════

class EnrollRequest(BaseSchema):
    module_id: str
    preferred_language: Optional[LanguageCode] = None


class ProgressUpdate(BaseSchema):
    enrollment_id: str
    progress_percent: int = Field(..., ge=0, le=100)
    current_lesson: int = Field(..., ge=1)
    earnings_from_skill: Optional[float] = Field(default=None, ge=0)
    earnings_currency: CurrencyCode = Field(default=CurrencyCode.USD)
    time_spent_minutes: Optional[int] = Field(default=None, ge=0)


class SkillModuleResponse(BaseSchema):
    id: str
    title: str
    description: str
    category: str
    difficulty: str
    estimated_hours: int
    language: str = "en"
    is_premium: bool = False
    progress_percent: int = 0
    enrollment_status: Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# PAYMENT MODELS
# ═════════════════════════════════════════════════════════════════════════════

class PaymentInitRequest(BaseSchema):
    plan: str = Field(default="monthly", pattern="^(monthly|yearly|lifetime)$")
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    payment_method: Optional[PaymentMethod] = Field(default=PaymentMethod.FLUTTERWAVE)
    country_code: Optional[str] = Field(default=None, max_length=2)
    coupon_code: Optional[str] = None


class PaymentVerifyRequest(BaseSchema):
    tx_ref: str
    transaction_id: Optional[str] = None
    payment_provider: str = Field(default="flutterwave", pattern="^(flutterwave|stripe|paypal)$")


class PaymentResponse(BaseSchema):
    id: str
    status: str
    amount: float
    currency: str
    plan: str
    payment_method: Optional[str] = None
    provider: str
    created_at: datetime
    expires_at: Optional[datetime] = None


class SubscriptionStatus(BaseSchema):
    is_active: bool
    plan: Optional[str] = None
    expires_at: Optional[datetime] = None
    days_remaining: Optional[int] = None
    features: List[str] = []


# ═════════════════════════════════════════════════════════════════════════════
# UNLOCK MODELS
# ═════════════════════════════════════════════════════════════════════════════

class AdUnlockRequest(BaseSchema):
    feature_key: str = Field(..., pattern="^[a-z_]+$")
    ad_unit_id: str
    duration_hours: int = Field(default=1, ge=1, le=24)


class FeatureCheckRequest(BaseSchema):
    feature_key: str = Field(..., pattern="^[a-z_]+$")


class FeatureUnlockResponse(BaseSchema):
    feature_key: str
    unlocked: bool
    unlocked_until: Optional[datetime] = None
    unlock_method: str
    remaining_uses: Optional[int] = None


# ═════════════════════════════════════════════════════════════════════════════
# PROGRESS & EARNINGS MODELS
# ═════════════════════════════════════════════════════════════════════════════

class EarningLog(BaseSchema):
    amount: float = Field(..., gt=0)
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    source_type: str = Field(..., pattern="^(task|skill|workflow|referral|bonus|other)$")
    source_id: Optional[str] = None
    description: Optional[str] = Field(default=None, max_length=500)
    payment_method: Optional[PaymentMethod] = None
    transaction_reference: Optional[str] = None
    earned_at: Optional[datetime] = None


class EarningStats(BaseSchema):
    total_earnings: float = 0.0
    currency: str = "USD"
    this_month: float = 0.0
    last_month: float = 0.0
    by_source: Dict[str, float] = {}
    streak_days: int = 0


class DailyProgress(BaseSchema):
    date: str
    tasks_completed: int = 0
    earnings: float = 0.0
    skills_practiced: int = 0
    minutes_spent: int = 0


class WeeklyInsight(BaseSchema):
    week_start: str
    summary: str
    achievements: List[str] = []
    suggestions: List[str] = []
    trend: str = "stable"


# ═════════════════════════════════════════════════════════════════════════════
# REFERRAL MODELS
# ═════════════════════════════════════════════════════════════════════════════

class ReferralCreate(BaseSchema):
    code: Optional[str] = None


class ReferralResponse(BaseSchema):
    id: str
    code: str
    referrer_id: str
    referred_count: int = 0
    total_earnings: float = 0.0
    currency: str = "USD"
    is_active: bool = True


# ═════════════════════════════════════════════════════════════════════════════
# NOTIFICATION MODELS
# ═════════════════════════════════════════════════════════════════════════════

class NotificationCreate(BaseSchema):
    user_id: str
    type: str = Field(..., pattern="^(system|goal|task|earning|referral|payment|achievement)$")
    title: str = Field(..., max_length=100)
    message: str = Field(..., max_length=500)
    action_url: Optional[str] = None
    data: Dict[str, Any] = {}


class NotificationResponse(BaseSchema):
    id: str
    type: str
    title: str
    message: str
    is_read: bool = False
    action_url: Optional[str] = None
    created_at: datetime


# ═════════════════════════════════════════════════════════════════════════════
# ADMIN MODELS
# ═════════════════════════════════════════════════════════════════════════════

class AdminStats(BaseSchema):
    total_users: int
    active_users_today: int
    new_users_today: int
    total_revenue: float
    revenue_by_currency: Dict[str, float]
    top_countries: List[Dict[str, Any]]
    system_health: str


class UserAdminUpdate(BaseSchema):
    is_active: Optional[bool] = None
    role: Optional[str] = Field(default=None, pattern="^(user|premium|admin|super_admin)$")
    stage: Optional[str] = None
    notes: Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# WORKFLOW MODELS
# ═════════════════════════════════════════════════════════════════════════════

class WorkflowCreate(BaseSchema):
    title: str = Field(..., min_length=1, max_length=200)
    goal: str = Field(..., min_length=1, max_length=500)
    income_type: IncomeType
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    language: LanguageCode = Field(default=LanguageCode.EN)
    timezone: Optional[str] = Field(default="UTC")


class WorkflowUpdate(BaseSchema):
    title: Optional[str] = Field(default=None, max_length=200)
    status: Optional[str] = Field(default=None, pattern="^(active|paused|completed|abandoned)$")


class WorkflowStepUpdate(BaseSchema):
    status: str = Field(..., pattern="^(pending|in_progress|completed|skipped|blocked)$")
    notes: Optional[str] = None


class RevenueLog(BaseSchema):
    amount: float = Field(..., gt=0)
    currency: CurrencyCode = Field(default=CurrencyCode.USD)
    source: Optional[str] = Field(default=None, max_length=200)
    note: Optional[str] = Field(default=None, max_length=500)
    payment_method: Optional[str] = None
