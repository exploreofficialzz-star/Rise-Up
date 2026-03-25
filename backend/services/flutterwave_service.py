"""Flutterwave payment service — global debit/credit + multi-currency
Primary currency: USD. All prices are defined in USD and converted to the
user's preferred currency at checkout using approximate rates.
"""
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

# ── Approximate USD conversion rates (update via live API in production) ──
# 1 USD = N units of local currency
CURRENCY_RATES: dict[str, float] = {
    "USD":  1.0,
    "GBP":  0.79,
    "EUR":  0.92,
    "CAD":  1.36,
    "AUD":  1.52,
    "CHF":  0.90,
    "SGD":  1.34,
    "JPY":  150.0,
    "CNY":  7.20,
    # Africa
    "NGN":  1600.0,
    "GHS":  15.5,
    "KES":  130.0,
    "ZAR":  18.5,
    "EGP":  48.0,
    "TZS":  2600.0,
    "UGX":  3750.0,
    "XOF":  615.0,
    "XAF":  615.0,
    "MAD":  10.0,
    "ETB":  56.0,
    "ZMW":  27.0,
    # Asia / Middle East
    "INR":  83.5,
    "PHP":  56.0,
    "PKR":  278.0,
    "BDT":  110.0,
    "IDR":  15700.0,
    "MYR":  4.70,
    "AED":  3.67,
    "SAR":  3.75,
    # Americas / LatAm
    "BRL":  5.00,
    "MXN":  17.20,
}


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

    def usd_to_local(self, usd_amount: float, currency: str) -> float:
        """Convert a USD amount to the target currency using stored rates."""
        rate = CURRENCY_RATES.get(currency.upper(), 1.0)
        return round(usd_amount * rate, 2)

    def local_to_usd(self, local_amount: float, currency: str) -> float:
        """Convert a local currency amount to USD."""
        rate = CURRENCY_RATES.get(currency.upper(), 1.0)
        if rate == 0:
            return local_amount
        return round(local_amount / rate, 2)

    def get_price_for_currency(self, plan: str, currency: str) -> float:
        """
        Return subscription price in the user's preferred currency.
        Base prices are always in USD; converted using CURRENCY_RATES.
        """
        usd_base = (
            settings.SUBSCRIPTION_MONTHLY_USD
            if plan == "monthly"
            else settings.SUBSCRIPTION_YEARLY_USD
        )
        return self.usd_to_local(usd_base, currency)

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
        """Create a Flutterwave payment link.
        Amount should already be in the target currency (use get_price_for_currency first).
        """
        tx_ref = self._generate_tx_ref(user_id)
        title = "RiseUp Premium Monthly" if plan == "monthly" else "RiseUp Premium Yearly"

        # Also store the USD equivalent in meta for reconciliation
        usd_equivalent = self.local_to_usd(amount, currency)

        payload = {
            "tx_ref": tx_ref,
            "amount": amount,
            "currency": currency.upper(),
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
                "source": "riseup_app",
                "usd_equivalent": usd_equivalent,
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
                "currency": currency.upper(),
                "usd_equivalent": usd_equivalent,
            }

        logger.error(f"Flutterwave payment initiation failed: {data}")
        return {"success": False, "error": data.get("message", "Payment failed")}

    async def verify_payment(self, transaction_id: str) -> dict:
        """Verify a payment by transaction ID."""
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
        """Verify payment by our tx_ref."""
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
        """Verify Flutterwave webhook signature."""
        if not settings.FLUTTERWAVE_WEBHOOK_HASH:
            return True  # skip in dev

        expected = hmac.new(
            settings.FLUTTERWAVE_WEBHOOK_HASH.encode("utf-8"),
            payload,
            hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature or "")


flutterwave_service = FlutterwaveService()
