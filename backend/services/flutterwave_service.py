"""Flutterwave payment service — global debit/credit + multi-currency"""
import hashlib
import hmac
import json
import logging
import uuid
from typing import Optional

import httpx

from config import settings

logger = logging.getLogger(__name__)

FLW_BASE = "https://api.flutterwave.com/v3"


class FlutterwaveService:
    def __init__(self):
        self.secret_key = settings.FLUTTERWAVE_SECRET_KEY
        self.public_key = settings.FLUTTERWAVE_PUBLIC_KEY
        self._headers = lambda: {
            "Authorization": f"Bearer {self.secret_key}",
            "Content-Type": "application/json"
        }

    def _generate_tx_ref(self, user_id: str) -> str:
        return f"riseup-{user_id[:8]}-{uuid.uuid4().hex[:8]}"

    async def initiate_payment(
        self,
        user_id: str,
        email: str,
        amount: float,
        currency: str,
        plan: str = "monthly",
        redirect_url: str = None,
        name: str = None,
        phone: str = None,
    ) -> dict:
        """Create a payment link for subscription or feature unlock"""
        tx_ref = self._generate_tx_ref(user_id)
        title = "RiseUp Premium Monthly" if plan == "monthly" else "RiseUp Premium Yearly"

        payload = {
            "tx_ref": tx_ref,
            "amount": amount,
            "currency": currency,
            "redirect_url": redirect_url or f"{settings.FRONTEND_URL}/payment/callback",
            "customer": {
                "email": email,
                "name": name or "RiseUp User",
                "phonenumber": phone or ""
            },
            "customizations": {
                "title": title,
                "description": "Unlock unlimited AI mentorship, skill modules & wealth tools",
                "logo": f"{settings.FRONTEND_URL}/assets/logo.png"
            },
            "meta": {
                "user_id": user_id,
                "plan": plan,
                "source": "riseup_app"
            }
        }

        async with httpx.AsyncClient() as client:
            res = await client.post(
                f"{FLW_BASE}/payments",
                headers=self._headers(),
                json=payload,
                timeout=30
            )
            data = res.json()

        if data.get("status") == "success":
            return {
                "success": True,
                "tx_ref": tx_ref,
                "payment_link": data["data"]["link"],
                "amount": amount,
                "currency": currency
            }

        logger.error(f"Flutterwave payment initiation failed: {data}")
        return {"success": False, "error": data.get("message", "Payment failed")}

    async def verify_payment(self, transaction_id: str) -> dict:
        """Verify a payment by transaction ID"""
        async with httpx.AsyncClient() as client:
            res = await client.get(
                f"{FLW_BASE}/transactions/{transaction_id}/verify",
                headers=self._headers(),
                timeout=30
            )
            data = res.json()

        if data.get("status") == "success":
            tx = data["data"]
            return {
                "success": True,
                "status": tx["status"],
                "amount": tx["amount"],
                "currency": tx["currency"],
                "customer_email": tx["customer"]["email"],
                "tx_ref": tx["tx_ref"],
                "flw_ref": tx.get("flw_ref"),
                "meta": tx.get("meta", {}),
                "verified": tx["status"] == "successful"
            }

        return {"success": False, "error": data.get("message")}

    async def verify_by_tx_ref(self, tx_ref: str) -> dict:
        """Verify payment by our tx_ref"""
        async with httpx.AsyncClient() as client:
            res = await client.get(
                f"{FLW_BASE}/transactions",
                headers=self._headers(),
                params={"tx_ref": tx_ref},
                timeout=30
            )
            data = res.json()

        if data.get("status") == "success" and data.get("data"):
            tx = data["data"][0]
            return {
                "success": True,
                "verified": tx["status"] == "successful",
                "amount": tx["amount"],
                "currency": tx["currency"],
                "tx_id": tx["id"],
                "tx_ref": tx["tx_ref"],
                "meta": tx.get("meta", {})
            }

        return {"success": False, "error": "Transaction not found"}

    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        """Verify Flutterwave webhook signature"""
        if not settings.FLUTTERWAVE_WEBHOOK_HASH:
            return True  # skip in dev

        expected = hmac.new(
            settings.FLUTTERWAVE_WEBHOOK_HASH.encode("utf-8"),
            payload,
            hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature or "")

    def get_price_for_currency(self, plan: str, currency: str) -> float:
        """Get subscription price in appropriate currency"""
        usd_monthly = settings.SUBSCRIPTION_MONTHLY_USD
        usd_yearly = settings.SUBSCRIPTION_YEARLY_USD

        base = usd_monthly if plan == "monthly" else usd_yearly

        # Approximate conversion rates (use live rates in production)
        rates = {
            "NGN": 1600, "GHS": 15.5, "KES": 130, "ZAR": 18.5,
            "USD": 1, "GBP": 0.79, "EUR": 0.92, "CAD": 1.36,
            "AUD": 1.52, "INR": 83.5
        }
        rate = rates.get(currency.upper(), 1)
        return round(base * rate, 2)


flutterwave_service = FlutterwaveService()
