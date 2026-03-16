from pydantic import BaseModel, EmailStr
from typing import Optional, List, Any
from datetime import datetime


# ── Auth ──────────────────────────────────────────────
class SignUpRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: Optional[str] = None


class SignInRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str


# ── Profile ───────────────────────────────────────────
class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    country: Optional[str] = None
    currency: Optional[str] = None
    wealth_type: Optional[str] = None
    learning_style: Optional[str] = None
    risk_tolerance: Optional[str] = None
    monthly_income: Optional[float] = None
    income_sources: Optional[List[str]] = None
    monthly_expenses: Optional[float] = None
    current_skills: Optional[List[str]] = None
    short_term_goal: Optional[str] = None
    long_term_goal: Optional[str] = None
    ambitions: Optional[str] = None
    health_energy: Optional[str] = None
    obstacles: Optional[str] = None
    onboarding_completed: Optional[bool] = None
    survival_mode: Optional[bool] = None
    stage: Optional[str] = None


# ── Chat ──────────────────────────────────────────────
class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    conversation_id: Optional[str] = None
    mode: Optional[str] = "general"  # general | onboarding | task_gen | roadmap
    preferred_model: Optional[str] = None


class ChatResponse(BaseModel):
    content: str
    conversation_id: str
    message_id: str
    ai_model: str
    onboarding_complete: bool = False
    extracted_profile: Optional[dict] = None
    suggested_tasks: Optional[list] = None


# ── Tasks ─────────────────────────────────────────────
class TaskUpdate(BaseModel):
    status: Optional[str] = None
    actual_earnings: Optional[float] = None


class GenerateTasksRequest(BaseModel):
    count: Optional[int] = 5
    category: Optional[str] = None


# ── Skills ────────────────────────────────────────────
class EnrollRequest(BaseModel):
    module_id: str


class ProgressUpdate(BaseModel):
    enrollment_id: str
    progress_percent: int
    current_lesson: int
    earnings_from_skill: Optional[float] = None


# ── Payments ──────────────────────────────────────────
class PaymentInitRequest(BaseModel):
    plan: str = "monthly"  # monthly | yearly
    currency: str = "NGN"


class PaymentVerifyRequest(BaseModel):
    tx_ref: str
    transaction_id: Optional[str] = None


# ── Unlocks ───────────────────────────────────────────
class AdUnlockRequest(BaseModel):
    feature_key: str
    ad_unit_id: str
    duration_hours: Optional[int] = 1


class FeatureCheckRequest(BaseModel):
    feature_key: str


# ── Progress ──────────────────────────────────────────
class EarningLog(BaseModel):
    amount: float
    source_type: str
    source_id: Optional[str] = None
    description: Optional[str] = None
    currency: str = "NGN"
