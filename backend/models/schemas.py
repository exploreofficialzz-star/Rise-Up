"""
RiseUp Pydantic Schemas v3.0
Adds brain fields to ChatResponse for Flutter escalation UI.
"""

from typing import Optional, List, Any, Dict
from pydantic import BaseModel, Field


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
