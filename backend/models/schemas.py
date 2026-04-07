"""
RiseUp Pydantic Schemas v3.1
Adds all missing models: TaskUpdate, PaymentInitRequest, PaymentVerifyRequest,
AdUnlockRequest, ProfileUpdate, EarningLog — required by tasks, payments,
and progress routers.
"""

from typing import Optional, List, Any, Dict
from pydantic import BaseModel, Field


# ── Chat ──────────────────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message:          str
    conversation_id:  Optional[str] = None
    mode:             str            = "mentor"
    # Modes: mentor | onboarding | tasks | roadmap | general
    preferred_model:  Optional[str] = None
    language:         Optional[str] = None


class ChatResponse(BaseModel):
    content:            str
    conversation_id:    str
    message_id:         str
    ai_model:           str              = "unknown"
    onboarding_complete: bool            = False
    extracted_profile:  Optional[Dict]   = None
    suggested_tasks:    Optional[List]   = None

    # v3.0 Brain fields — Flutter uses these to show escalation UI
    brain_intent:             Optional[str]  = None
    brain_internal_found:     bool           = False
    brain_methods:            List[Dict]     = Field(default_factory=list)
    brain_marketplace:        List[Dict]     = Field(default_factory=list)
    brain_service_providers:  List[Dict]     = Field(default_factory=list)
    brain_needs_external:     bool           = False
    brain_escalation_reason:  Optional[str]  = None
    brain_suggested_task_type:Optional[str]  = None
    complementary_users:      List[Dict]     = Field(default_factory=list)


class GenerateTasksRequest(BaseModel):
    count:    int  = Field(default=5, ge=1, le=20)
    urgency:  str  = "immediate"
    category: Optional[str] = None


# ── Tasks ─────────────────────────────────────────────────────────────────────

class TaskUpdate(BaseModel):
    status:           Optional[str]   = None   # pending | in_progress | completed | skipped
    actual_earnings:  Optional[float] = None
    notes:            Optional[str]   = None
    priority:         Optional[str]   = None   # low | medium | high
    due_date:         Optional[str]   = None   # ISO 8601


# ── Payments ──────────────────────────────────────────────────────────────────

class PaymentInitRequest(BaseModel):
    plan:     str            # monthly | yearly
    currency: Optional[str] = None   # defaults to profile currency


class PaymentVerifyRequest(BaseModel):
    transaction_id: Optional[str] = None   # Flutterwave transaction ID
    tx_ref:         Optional[str] = None   # internal tx reference


class AdUnlockRequest(BaseModel):
    feature_key:    str
    ad_unit_id:     str
    duration_hours: Optional[int] = 1


# ── Progress / Profile ────────────────────────────────────────────────────────

class ProfileUpdate(BaseModel):
    full_name:    Optional[str]   = None
    bio:          Optional[str]   = None
    phone:        Optional[str]   = None
    country:      Optional[str]   = None
    currency:     Optional[str]   = None
    stage:        Optional[str]   = None   # survival | stability | growth | wealth
    skills:       Optional[List[str]] = None
    goals:        Optional[List[str]] = None
    avatar_url:   Optional[str]   = None
    language:     Optional[str]   = None


class EarningLog(BaseModel):
    amount:      float
    source_type: str            # task | referral | investment | other
    source_id:   Optional[str]  = None
    description: Optional[str]  = None
    currency:    str             = "NGN"
