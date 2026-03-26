"""Tasks Router — Income task management (Global Edition)"""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Header
from typing import Optional

from models.schemas import TaskUpdate
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/tasks", tags=["Tasks"])


@router.get("/")
async def get_tasks(
    status: str = None, 
    user: dict = Depends(get_current_user),
    accept_language: Optional[str] = Header("en", description="User's preferred language"),
    x_user_timezone: Optional[str] = Header("UTC", description="User's local timezone")
):
    # Pass language and timezone to the service layer to filter or translate tasks
    tasks = await supabase_service.get_tasks(
        user_id=user["id"], 
        status=status,
        locale=accept_language,
        timezone=x_user_timezone
    )
    return {"tasks": tasks, "count": len(tasks)}


@router.patch("/{task_id}")
async def update_task(
    task_id: str, 
    req: TaskUpdate, 
    user: dict = Depends(get_current_user),
    x_currency_code: Optional[str] = Header(None, description="Client-side currency override")
):
    data = req.dict(exclude_none=True)
    
    if req.status == "completed":
        data["completed_at"] = datetime.now(timezone.utc).isoformat()
        
        # Log earning with global currency support
        if req.actual_earnings:
            profile = await supabase_service.get_profile(user["id"])
            
            # Priority: 1. Header override, 2. Profile setting, 3. Global standard (USD)
            user_currency = x_currency_code or profile.get("currency") or "USD"
            
            await supabase_service.log_earning(
                user_id=user["id"],
                amount=req.actual_earnings,
                source="task",
                reference_id=task_id,
                currency=user_currency
            )

    updated = await supabase_service.update_task(task_id, user["id"], data)
    if not updated:
        raise HTTPException(status_code=404, detail="Task not found")
    return {"task": updated}


@router.delete("/{task_id}")
async def skip_task(task_id: str, user: dict = Depends(get_current_user)):
    # Standardizing response for global consistency
    updated = await supabase_service.update_task(task_id, user["id"], {"status": "skipped"})
    return {"task": updated, "message": "Task ignored/skipped"}
