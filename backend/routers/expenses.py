"""Expenses & Budget Router — Track spending, set budgets, get net income analysis
All amounts default to USD. Users may log in their local currency if preferred.
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, field_validator
from middleware.rate_limit import limiter, GENERAL_LIMIT
from services.supabase_service import supabase_service
from utils.auth import get_current_user

router = APIRouter(prefix="/expenses", tags=["Expenses & Budget"])
logger = logging.getLogger(__name__)

EXPENSE_CATEGORIES = [
    "food", "transport", "rent", "utilities", "entertainment",
    "clothing", "health", "education", "savings", "debt", "business", "other"
]

CATEGORY_ICONS = {
    "food": "🍔", "transport": "🚗", "rent": "🏠", "utilities": "⚡",
    "entertainment": "🎮", "clothing": "👗", "health": "🏥",
    "education": "📚", "savings": "💰", "debt": "💳",
    "business": "💼", "other": "📦",
}


class ExpenseCreate(BaseModel):
    amount: float
    currency: str = "USD"       # USD by default; user can set to local currency
    category: str = "other"
    description: Optional[str] = None
    spent_at: Optional[str] = None   # ISO date string YYYY-MM-DD

    @field_validator("amount")
    @classmethod
    def positive_amount(cls, v):
        if v <= 0:
            raise ValueError("Amount must be positive")
        return v

    @field_validator("category")
    @classmethod
    def valid_category(cls, v):
        if v not in EXPENSE_CATEGORIES:
            return "other"
        return v


class BudgetSet(BaseModel):
    month: str          # 'YYYY-MM'
    category: str
    budget_amount: float
    currency: str = "USD"   # USD by default


# ── Expenses ─────────────────────────────────────────────────

@router.get("/")
async def list_expenses(
    month: Optional[str] = None,  # 'YYYY-MM'
    category: Optional[str] = None,
    limit: int = 50,
    user: dict = Depends(get_current_user),
):
    """Get expense history"""
    q = (supabase_service.db.table("expenses")
         .select("*")
         .eq("user_id", user["id"]))

    if month:
        start = f"{month}-01"
        year, mon = int(month[:4]), int(month[5:7])
        if mon == 12:
            end = f"{year + 1}-01-01"
        else:
            end = f"{year}-{mon + 1:02d}-01"
        q = q.gte("spent_at", start).lt("spent_at", end)

    if category:
        q = q.eq("category", category)

    res = q.order("spent_at", desc=True).limit(limit).execute()
    expenses = res.data or []

    # Add icons
    for e in expenses:
        e["icon"] = CATEGORY_ICONS.get(e.get("category", "other"), "📦")

    total = sum(float(e["amount"]) for e in expenses)
    return {"expenses": expenses, "total": total, "count": len(expenses)}


@router.post("/")
@limiter.limit(GENERAL_LIMIT)
async def log_expense(req: ExpenseCreate, request: Request, user: dict = Depends(get_current_user)):
    """Log a new expense"""
    data = {
        "user_id":     user["id"],
        "amount":      req.amount,
        "currency":    req.currency,
        "category":    req.category,
        "description": req.description,
        "spent_at":    req.spent_at or str(datetime.now(timezone.utc).date()),
    }
    res = supabase_service.db.table("expenses").insert(data).execute()
    expense = res.data[0] if res.data else {}
    expense["icon"] = CATEGORY_ICONS.get(req.category, "📦")

    return {
        "expense": expense,
        "message": f"{expense['icon']} {req.currency} {req.amount:,.2f} logged under {req.category}",
    }


@router.delete("/{expense_id}")
async def delete_expense(expense_id: str, user: dict = Depends(get_current_user)):
    """Delete an expense entry"""
    supabase_service.db.table("expenses").delete().eq("id", expense_id).eq("user_id", user["id"]).execute()
    return {"message": "Expense deleted"}


# ── Budget ───────────────────────────────────────────────────

@router.get("/budgets")
async def get_budgets(month: Optional[str] = None, user: dict = Depends(get_current_user)):
    """Get budget settings"""
    from datetime import date
    current_month = month or date.today().strftime("%Y-%m")
    res = (supabase_service.db.table("budgets")
           .select("*")
           .eq("user_id", user["id"])
           .eq("month", current_month)
           .execute())
    return {"budgets": res.data or [], "month": current_month}


@router.post("/budgets")
async def set_budget(req: BudgetSet, user: dict = Depends(get_current_user)):
    """Set or update a monthly category budget"""
    data = {
        "user_id":       user["id"],
        "month":         req.month,
        "category":      req.category,
        "budget_amount": req.budget_amount,
        "currency":      req.currency,
    }
    res = (supabase_service.db.table("budgets")
           .upsert(data, on_conflict="user_id,month,category")
           .execute())

    # Check budget_master achievement (5+ budget categories set)
    budgets_count = supabase_service.db.table("budgets").select("id", count="exact").eq("user_id", user["id"]).execute()
    if (budgets_count.count or 0) >= 5:
        supabase_service.db.rpc("unlock_achievement", {
            "uid": user["id"], "ach_key": "budget_master"
        }).execute()

    return {"budget": res.data[0] if res.data else {}, "message": f"✅ Budget set for {req.category}"}


@router.get("/summary")
async def get_monthly_summary(month: Optional[str] = None, user: dict = Depends(get_current_user)):
    """Get spending summary vs budget for a month, including net income"""
    from datetime import date
    current_month = month or date.today().strftime("%Y-%m")
    user_id = user["id"]

    # Expense breakdown vs budget
    breakdown_res = supabase_service.db.rpc("get_monthly_summary", {
        "uid": user_id, "month_str": current_month
    }).execute()
    breakdown = breakdown_res.data or []

    # Total income this month
    profile = await supabase_service.get_profile(user_id)
    monthly_income = float(profile.get("monthly_income") or 0) if profile else 0

    # Resolve display currency (USD default, or user's preferred)
    display_currency = profile.get("currency", "USD") if profile else "USD"
    local_currency   = profile.get("local_currency", display_currency) if profile else display_currency

    total_spent    = sum(float(b.get("spent") or 0) for b in breakdown)
    total_budgeted = sum(float(b.get("budgeted") or 0) for b in breakdown)
    net_income     = monthly_income - total_spent

    # Add icons
    for b in breakdown:
        b["icon"]       = CATEGORY_ICONS.get(b.get("category", "other"), "📦")
        b["over_budget"] = float(b.get("spent") or 0) > float(b.get("budgeted") or 0)

    return {
        "month":            current_month,
        "breakdown":        breakdown,
        "total_spent":      total_spent,
        "total_budgeted":   total_budgeted,
        "monthly_income":   monthly_income,
        "net_income":       net_income,
        "savings_rate":     round((net_income / monthly_income * 100), 1) if monthly_income > 0 else 0,
        "display_currency": display_currency,
        "local_currency":   local_currency,
    }
