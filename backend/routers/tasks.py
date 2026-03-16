"""Tasks Router — Income task management"""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException

from models.schemas import TaskUpdate
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/tasks", tags=["Tasks"])


@router.get("/")
async def get_tasks(status: str = None, user: dict = Depends(get_current_user)):
    tasks = await supabase_service.get_tasks(user["id"], status)
    return {"tasks": tasks, "count": len(tasks)}


@router.patch("/{task_id}")
async def update_task(task_id: str, req: TaskUpdate, user: dict = Depends(get_current_user)):
    data = req.dict(exclude_none=True)
    if req.status == "completed":
        data["completed_at"] = datetime.now(timezone.utc).isoformat()
        # Log earning if actual_earnings provided
        if req.actual_earnings:
            profile = await supabase_service.get_profile(user["id"])
            await supabase_service.log_earning(
                user["id"],
                req.actual_earnings,
                "task",
                task_id,
                currency=profile.get("currency", "NGN") if profile else "NGN"
            )

    updated = await supabase_service.update_task(task_id, user["id"], data)
    if not updated:
        raise HTTPException(404, "Task not found")
    return {"task": updated}


@router.delete("/{task_id}")
async def skip_task(task_id: str, user: dict = Depends(get_current_user)):
    updated = await supabase_service.update_task(task_id, user["id"], {"status": "skipped"})
    return {"task": updated, "message": "Task skipped"}
