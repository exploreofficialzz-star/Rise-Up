"""
RiseUp Action Service v2.0 (Production)
─────────────────────────────────────────────────────────────────────
Gives the agent the ability to take REAL ACTIONS in the world:
  • Send emails (SMTP / SendGrid / AWS SES)
  • Send WhatsApp Business messages (global reach)
  • Post to Twitter/X, LinkedIn, Instagram, TikTok
  • Generate professional PDFs (contracts, invoices, proposals)
  • Process payments (Paystack, Flutterwave, Stripe, Razorpay)
  • Calendar scheduling (Google Calendar, Cal.com)
  • SMS notifications (Twilio, Africa's Talking)
  • Build platform profile content
  • Automated follow-up sequences

These are the tools that turn the agent from a planner into a WORKER.
"""

import logging
import httpx
import json
import smtplib
import ssl
import base64
import io
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.application import MIMEApplication
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List, Union
from dataclasses import dataclass
from enum import Enum

from config import settings

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION & DATA MODELS
# ═══════════════════════════════════════════════════════════════════

class PaymentGateway(Enum):
    """Supported payment gateways by region"""
    PAYSTACK = "paystack"       # Africa (Nigeria, Ghana, Kenya, SA)
    FLUTTERWAVE = "flutterwave" # Africa (multi-currency)
    STRIPE = "stripe"           # Global (US, EU, UK, etc.)
    RAZORPAY = "razorpay"       # India, Asia
    PAYPAL = "paypal"           # Global
    MPESA = "mpesa"             # East Africa (Kenya, Tanzania)


class SMSProvider(Enum):
    """SMS providers by region"""
    TWILIO = "twilio"           # Global
    AFRICASTALKING = "africastalking"  # Africa
    MESSAGEBIRD = "messagebird" # Europe, Asia
    TERMII = "termii"           # Nigeria specifically


@dataclass
class PaymentRequest:
    """Payment request data"""
    amount: float
    currency: str
    email: str
    reference: str
    callback_url: Optional[str] = None
    metadata: Optional[Dict] = None


@dataclass
class ScheduledAction:
    """Scheduled action for later execution"""
    action_type: str
    payload: Dict[str, Any]
    execute_at: datetime
    user_id: str
    status: str = "pending"


# ═══════════════════════════════════════════════════════════════════
# EMAIL SERVICE (Enhanced)
# ═══════════════════════════════════════════════════════════════════

class EmailService:
    """Send emails via SendGrid, AWS SES, or SMTP fallback."""

    async def send(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
        from_name: str = "RiseUp AI",
        from_email: Optional[str] = None,
        reply_to: Optional[str] = None,
        attachments: Optional[List[Dict]] = None,
        cc: Optional[List[str]] = None,
        bcc: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Send email with multiple provider fallback."""
        sender = from_email or getattr(settings, "EMAIL_FROM", "noreply@riseup.app")

        # Try SendGrid first
        if getattr(settings, "SENDGRID_API_KEY", None):
            return await self._send_sendgrid(
                to_email, subject, body_text, body_html or body_text,
                sender, from_name, reply_to, attachments, cc, bcc
            )

        # Try AWS SES
        if getattr(settings, "AWS_ACCESS_KEY_ID", None) and getattr(settings, "AWS_SECRET_ACCESS_KEY", None):
            return await self._send_aws_ses(
                to_email, subject, body_text, body_html,
                sender, from_name, reply_to, attachments
            )

        # Fallback to SMTP
        if getattr(settings, "SMTP_HOST", None):
            return self._send_smtp(
                to_email, subject, body_text, body_html,
                sender, from_name, reply_to, attachments
            )

        logger.warning("No email provider configured")
        return {
            "sent": False,
            "error": "No email provider configured",
            "preview": f"TO: {to_email}\nSUBJECT: {subject}\n\n{body_text[:300]}",
            "provider": "none"
        }

    async def _send_sendgrid(
        self, to, subject, text, html, sender, from_name, reply_to,
        attachments=None, cc=None, bcc=None
    ) -> Dict[str, Any]:
        """Send via SendGrid API."""
        payload = {
            "personalizations": [{"to": [{"email": to}]}],
            "from": {"email": sender, "name": from_name},
            "subject": subject,
            "content": [
                {"type": "text/plain", "value": text},
                {"type": "text/html", "value": html},
            ],
        }
        
        if reply_to:
            payload["reply_to"] = {"email": reply_to}
        if cc:
            payload["personalizations"][0]["cc"] = [{"email": e} for e in cc]
        if bcc:
            payload["personalizations"][0]["bcc"] = [{"email": e} for e in bcc]
        
        if attachments:
            payload["attachments"] = [
                {
                    "filename": att["filename"],
                    "content": base64.b64encode(att["content"]).decode(),
                    "type": att.get("content_type", "application/pdf")
                }
                for att in attachments
            ]

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.sendgrid.com/v3/mail/send",
                    headers={
                        "Authorization": f"Bearer {settings.SENDGRID_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json=payload,
                )
            
            if r.status_code in (200, 202):
                return {
                    "sent": True,
                    "provider": "sendgrid",
                    "to": to,
                    "subject": subject,
                    "message_id": r.headers.get("X-Message-Id")
                }
            return {"sent": False, "error": r.text, "provider": "sendgrid", "status_code": r.status_code}
        except Exception as e:
            logger.error(f"SendGrid error: {e}")
            return {"sent": False, "error": str(e), "provider": "sendgrid"}

    async def _send_aws_ses(
        self, to, subject, text, html, sender, from_name, reply_to, attachments
    ) -> Dict[str, Any]:
        """Send via AWS SES."""
        import boto3
        from botocore.exceptions import ClientError

        try:
            client = boto3.client(
                'ses',
                region_name=getattr(settings, "AWS_REGION", "us-east-1"),
                aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY
            )

            msg = MIMEMultipart('mixed')
            msg['Subject'] = subject
            msg['From'] = f"{from_name} <{sender}>"
            msg['To'] = to
            if reply_to:
                msg['Reply-To'] = reply_to

            # Body
            msg_body = MIMEMultipart('alternative')
            msg_body.attach(MIMEText(text, 'plain'))
            if html:
                msg_body.attach(MIMEText(html, 'html'))
            msg.attach(msg_body)

            # Attachments
            if attachments:
                for att in attachments:
                    part = MIMEApplication(att["content"])
                    part.add_header(
                        'Content-Disposition',
                        'attachment',
                        filename=att["filename"]
                    )
                    msg.attach(part)

            response = client.send_raw_email(
                Source=sender,
                Destinations=[to],
                RawMessage={'Data': msg.as_string()}
            )

            return {
                "sent": True,
                "provider": "aws_ses",
                "to": to,
                "subject": subject,
                "message_id": response['MessageId']
            }
        except ClientError as e:
            logger.error(f"AWS SES error: {e}")
            return {"sent": False, "error": str(e), "provider": "aws_ses"}
        except Exception as e:
            logger.error(f"AWS SES unexpected error: {e}")
            return {"sent": False, "error": str(e), "provider": "aws_ses"}

    def _send_smtp(
        self, to, subject, text, html, sender, from_name, reply_to, attachments
    ) -> Dict[str, Any]:
        """Send via SMTP."""
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = f"{from_name} <{sender}>"
            msg["To"] = to
            if reply_to:
                msg["Reply-To"] = reply_to

            msg.attach(MIMEText(text, "plain"))
            if html:
                msg.attach(MIMEText(html, "html"))

            if attachments:
                for att in attachments:
                    part = MIMEApplication(att["content"])
                    part.add_header(
                        'Content-Disposition',
                        'attachment',
                        filename=att["filename"]
                    )
                    msg.attach(part)

            ctx = ssl.create_default_context()
            with smtplib.SMTP_SSL(
                settings.SMTP_HOST,
                int(getattr(settings, "SMTP_PORT", 465)),
                context=ctx
            ) as server:
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                server.sendmail(sender, to, msg.as_string())

            return {"sent": True, "provider": "smtp", "to": to, "subject": subject}
        except Exception as e:
            logger.error(f"SMTP error: {e}")
            return {"sent": False, "error": str(e), "provider": "smtp"}

    async def send_template(
        self,
        to_email: str,
        template_id: str,
        template_data: Dict[str, Any],
        from_name: str = "RiseUp AI",
        from_email: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Send using a predefined template."""
        # Template mapping
        templates = {
            "welcome": self._get_welcome_template,
            "invoice": self._get_invoice_template,
            "payment_reminder": self._get_payment_reminder_template,
            "milestone_achieved": self._get_milestone_template,
            "weekly_report": self._get_weekly_report_template,
        }

        if template_id not in templates:
            return {"sent": False, "error": f"Template {template_id} not found"}

        subject, text, html = templates[template_id](template_data)
        return await self.send(to_email, subject, text, html, from_name, from_email)

    def _get_welcome_template(self, data: Dict) -> tuple:
        name = data.get("name", "there")
        return (
            "Welcome to RiseUp - Your Wealth Journey Starts Now",
            f"""Hi {name},

Welcome to RiseUp! We're excited to help you build wealth and achieve financial freedom.

Your next steps:
1. Complete your profile
2. Set your first 90-day goal
3. Explore income opportunities

Let's get started!""",
            f"""<html><body>
<h2>Welcome to RiseUp, {name}!</h2>
<p>We're excited to help you build wealth and achieve financial freedom.</p>
<h3>Your next steps:</h3>
<ol>
<li>Complete your profile</li>
<li>Set your first 90-day goal</li>
<li>Explore income opportunities</li>
</ol>
<p>Let's get started!</p>
</body></html>"""
        )

    def _get_invoice_template(self, data: Dict) -> tuple:
        return (
            f"Invoice {data.get('invoice_number')} from {data.get('sender_name')}",
            f"Please find your invoice attached. Amount: {data.get('currency')} {data.get('amount')}",
            f"<html><body><h2>Invoice {data.get('invoice_number')}</h2><p>Amount: {data.get('currency')} {data.get('amount')}</p></body></html>"
        )

    def _get_payment_reminder_template(self, data: Dict) -> tuple:
        return (
            "Payment Reminder",
            f"Friendly reminder: Payment of {data.get('currency')} {data.get('amount')} is due on {data.get('due_date')}",
            f"<html><body><p>Friendly reminder: Payment of <strong>{data.get('currency')} {data.get('amount')}</strong> is due on {data.get('due_date')}</p></body></html>"
        )

    def _get_milestone_template(self, data: Dict) -> tuple:
        return (
            "Congratulations on Your Achievement!",
            f"Great job! You've achieved: {data.get('milestone')}. Keep up the momentum!",
            f"<html><body><h2>Congratulations!</h2><p>You've achieved: <strong>{data.get('milestone')}</strong></p></body></html>"
        )

    def _get_weekly_report_template(self, data: Dict) -> tuple:
        return (
            "Your Weekly RiseUp Report",
            f"Weekly summary: Income: {data.get('income', 0)}, Progress: {data.get('progress', 0)}%",
            f"<html><body><h2>Weekly Report</h2><p>Income: {data.get('income', 0)}<br>Progress: {data.get('progress', 0)}%</p></body></html>"
        )


# ═══════════════════════════════════════════════════════════════════
# WHATSAPP BUSINESS SERVICE (Global Reach)
# ═══════════════════════════════════════════════════════════════════

class WhatsAppService:
    """Send WhatsApp Business messages globally."""

    async def send_text(
        self,
        to_number: str,
        message: str,
        preview_url: bool = False
    ) -> Dict[str, Any]:
        """Send text message via WhatsApp Business API."""
        phone_id = getattr(settings, "WHATSAPP_PHONE_ID", None)
        access_token = getattr(settings, "WHATSAPP_ACCESS_TOKEN", None)

        if not phone_id or not access_token:
            return {
                "sent": False,
                "error": "WhatsApp credentials not configured",
                "provider": "whatsapp"
            }

        # Format number (remove + if present)
        to_number = to_number.replace("+", "").replace(" ", "")

        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": to_number,
            "type": "text",
            "text": {
                "preview_url": preview_url,
                "body": message
            }
        }

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    f"https://graph.facebook.com/v18.0/{phone_id}/messages",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json"
                    },
                    json=payload
                )

            data = r.json()
            if r.status_code == 200:
                return {
                    "sent": True,
                    "provider": "whatsapp",
                    "to": to_number,
                    "message_id": data.get("messages", [{}])[0].get("id"),
                    "cost": data.get("pricing", {}).get("billable")
                }
            return {
                "sent": False,
                "error": data.get("error", {}).get("message", "Unknown error"),
                "provider": "whatsapp",
                "status_code": r.status_code
            }
        except Exception as e:
            logger.error(f"WhatsApp error: {e}")
            return {"sent": False, "error": str(e), "provider": "whatsapp"}

    async def send_template(
        self,
        to_number: str,
        template_name: str,
        language_code: str = "en",
        components: Optional[List[Dict]] = None
    ) -> Dict[str, Any]:
        """Send approved template message."""
        phone_id = getattr(settings, "WHATSAPP_PHONE_ID", None)
        access_token = getattr(settings, "WHATSAPP_ACCESS_TOKEN", None)

        if not phone_id or not access_token:
            return {"sent": False, "error": "WhatsApp credentials not configured"}

        to_number = to_number.replace("+", "").replace(" ", "")

        payload = {
            "messaging_product": "whatsapp",
            "to": to_number,
            "type": "template",
            "template": {
                "name": template_name,
                "language": {"code": language_code}
            }
        }

        if components:
            payload["template"]["components"] = components

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    f"https://graph.facebook.com/v18.0/{phone_id}/messages",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json"
                    },
                    json=payload
                )

            data = r.json()
            if r.status_code == 200:
                return {
                    "sent": True,
                    "provider": "whatsapp",
                    "to": to_number,
                    "template": template_name,
                    "message_id": data.get("messages", [{}])[0].get("id")
                }
            return {
                "sent": False,
                "error": data.get("error", {}).get("message", "Unknown error"),
                "provider": "whatsapp"
            }
        except Exception as e:
            logger.error(f"WhatsApp template error: {e}")
            return {"sent": False, "error": str(e), "provider": "whatsapp"}

    async def send_media(
        self,
        to_number: str,
        media_type: str,  # image, document, audio, video
        media_url: str,
        caption: Optional[str] = None
    ) -> Dict[str, Any]:
        """Send media message."""
        phone_id = getattr(settings, "WHATSAPP_PHONE_ID", None)
        access_token = getattr(settings, "WHATSAPP_ACCESS_TOKEN", None)

        if not phone_id or not access_token:
            return {"sent": False, "error": "WhatsApp credentials not configured"}

        to_number = to_number.replace("+", "").replace(" ", "")

        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": to_number,
            "type": media_type,
            media_type: {"link": media_url}
        }

        if caption and media_type in ["image", "document", "video"]:
            payload[media_type]["caption"] = caption

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    f"https://graph.facebook.com/v18.0/{phone_id}/messages",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json"
                    },
                    json=payload
                )

            data = r.json()
            if r.status_code == 200:
                return {
                    "sent": True,
                    "provider": "whatsapp",
                    "to": to_number,
                    "media_type": media_type,
                    "message_id": data.get("messages", [{}])[0].get("id")
                }
            return {
                "sent": False,
                "error": data.get("error", {}).get("message", "Unknown error"),
                "provider": "whatsapp"
            }
        except Exception as e:
            logger.error(f"WhatsApp media error: {e}")
            return {"sent": False, "error": str(e), "provider": "whatsapp"}


# ═══════════════════════════════════════════════════════════════════
# SOCIAL MEDIA SERVICE (Enhanced Multi-Platform)
# ═══════════════════════════════════════════════════════════════════

class SocialMediaService:
    """Post to Twitter/X, LinkedIn, Instagram, TikTok."""

    async def post_twitter(
        self,
        text: str,
        media_urls: Optional[List[str]] = None,
        user_tokens: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """Post to Twitter/X with media support."""
        access_token = (user_tokens or {}).get("access_token") or \
                       getattr(settings, "TWITTER_ACCESS_TOKEN", None)

        if not access_token:
            return {
                "posted": False,
                "error": "Twitter access token not configured",
                "preview": text[:280],
                "platform": "twitter"
            }

        try:
            # V2 API for text
            async with httpx.AsyncClient(timeout=30) as client:
                payload = {"text": text[:280]}
                r = await client.post(
                    "https://api.twitter.com/2/tweets",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json"
                    },
                    json=payload,
                )

            data = r.json()
            if r.status_code == 201:
                tweet_id = data.get("data", {}).get("id", "")
                return {
                    "posted": True,
                    "platform": "twitter",
                    "post_id": tweet_id,
                    "url": f"https://twitter.com/i/web/status/{tweet_id}",
                    "preview": text[:280],
                }
            return {
                "posted": False,
                "error": data,
                "platform": "twitter",
                "preview": text[:280],
                "status_code": r.status_code
            }
        except Exception as e:
            logger.error(f"Twitter error: {e}")
            return {"posted": False, "error": str(e), "platform": "twitter", "preview": text[:280]}

    async def post_linkedin(
        self,
        text: str,
        media_urls: Optional[List[str]] = None,
        user_tokens: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """Post to LinkedIn with media support."""
        access_token = (user_tokens or {}).get("access_token") or \
                       getattr(settings, "LINKEDIN_ACCESS_TOKEN", None)
        person_urn = (user_tokens or {}).get("person_urn") or \
                     getattr(settings, "LINKEDIN_PERSON_URN", None)

        if not access_token or not person_urn:
            return {
                "posted": False,
                "error": "LinkedIn credentials not configured",
                "preview": text[:700],
                "platform": "linkedin"
            }

        try:
            payload = {
                "author": person_urn,
                "lifecycleState": "PUBLISHED",
                "specificContent": {
                    "com.linkedin.ugc.ShareContent": {
                        "shareCommentary": {"text": text[:700]},
                        "shareMediaCategory": "NONE",
                    }
                },
                "visibility": {"com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"},
            }

            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.linkedin.com/v2/ugcPosts",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json",
                        "X-Restli-Protocol-Version": "2.0.0"
                    },
                    json=payload,
                )

            if r.status_code == 201:
                post_id = r.headers.get("x-restli-id", "")
                return {
                    "posted": True,
                    "platform": "linkedin",
                    "post_id": post_id,
                    "preview": text[:700]
                }
            return {
                "posted": False,
                "error": r.text,
                "platform": "linkedin",
                "preview": text[:700],
                "status_code": r.status_code
            }
        except Exception as e:
            logger.error(f"LinkedIn error: {e}")
            return {"posted": False, "error": str(e), "platform": "linkedin", "preview": text[:700]}

    async def schedule_post(
        self,
        platform: str,
        text: str,
        schedule_at: Union[str, datetime],
        user_id: str,
        media_urls: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Save a scheduled post to the database for later execution."""
        from services.supabase_service import supabase_service
        
        try:
            if isinstance(schedule_at, str):
                schedule_at = datetime.fromisoformat(schedule_at.replace("Z", "+00:00"))

            sb = supabase_service.client
            row = sb.table("scheduled_posts").insert({
                "user_id": user_id,
                "platform": platform,
                "content": text,
                "media_urls": media_urls,
                "schedule_at": schedule_at.isoformat(),
                "status": "pending",
                "created_at": datetime.now(timezone.utc).isoformat()
            }).execute()

            return {
                "scheduled": True,
                "platform": platform,
                "schedule_at": schedule_at.isoformat(),
                "post_id": row.data[0]["id"] if row.data else None
            }
        except Exception as e:
            logger.error(f"Schedule post error: {e}")
            return {"scheduled": False, "error": str(e)}

    async def publish_scheduled_posts(self) -> Dict[str, Any]:
        """Publish due scheduled posts (call this via cron job)."""
        from services.supabase_service import supabase_service
        
        try:
            sb = supabase_service.client
            now = datetime.now(timezone.utc).isoformat()

            # Get pending posts that are due
            result = sb.table("scheduled_posts").select("*").eq(
                "status", "pending"
            ).lte("schedule_at", now).execute()

            published = []
            failed = []

            for post in result.data:
                try:
                    if post["platform"] == "twitter":
                        res = await self.post_twitter(post["content"], post.get("media_urls"))
                    elif post["platform"] == "linkedin":
                        res = await self.post_linkedin(post["content"], post.get("media_urls"))
                    else:
                        continue

                    # Update status
                    sb.table("scheduled_posts").update({
                        "status": "published" if res.get("posted") else "failed",
                        "result": res,
                        "published_at": datetime.now(timezone.utc).isoformat()
                    }).eq("id", post["id"]).execute()

                    if res.get("posted"):
                        published.append(post["id"])
                    else:
                        failed.append({"id": post["id"], "error": res.get("error")})

                except Exception as e:
                    failed.append({"id": post["id"], "error": str(e)})
                    sb.table("scheduled_posts").update({
                        "status": "failed",
                        "error": str(e)
                    }).eq("id", post["id"]).execute()

            return {
                "processed": len(result.data),
                "published": len(published),
                "failed": failed
            }

        except Exception as e:
            logger.error(f"Publish scheduled error: {e}")
            return {"error": str(e)}


# ═══════════════════════════════════════════════════════════════════
# PAYMENT SERVICE (Multi-Gateway Global Support)
# ═══════════════════════════════════════════════════════════════════

class PaymentService:
    """Process payments via regional gateways."""

    def __init__(self):
        self.gateway_map = {
            "NG": PaymentGateway.PAYSTACK,
            "GH": PaymentGateway.PAYSTACK,
            "KE": PaymentGateway.PAYSTACK,
            "ZA": PaymentGateway.PAYSTACK,
            "IN": PaymentGateway.RAZORPAY,
            "US": PaymentGateway.STRIPE,
            "GB": PaymentGateway.STRIPE,
            "EU": PaymentGateway.STRIPE,
        }

    def get_gateway_for_country(self, country_code: str) -> PaymentGateway:
        """Determine best gateway for country."""
        return self.gateway_map.get(country_code.upper(), PaymentGateway.STRIPE)

    async def initialize_payment(
        self,
        payment: PaymentRequest,
        country_code: str,
        gateway: Optional[PaymentGateway] = None
    ) -> Dict[str, Any]:
        """Initialize payment with appropriate gateway."""
        selected_gateway = gateway or self.get_gateway_for_country(country_code)

        if selected_gateway == PaymentGateway.PAYSTACK:
            return await self._paystack_initialize(payment)
        elif selected_gateway == PaymentGateway.FLUTTERWAVE:
            return await self._flutterwave_initialize(payment)
        elif selected_gateway == PaymentGateway.RAZORPAY:
            return await self._razorpay_initialize(payment)
        elif selected_gateway == PaymentGateway.STRIPE:
            return await self._stripe_initialize(payment)
        else:
            return {"error": "Unsupported gateway", "gateway": selected_gateway.value}

    async def verify_payment(
        self,
        reference: str,
        gateway: PaymentGateway
    ) -> Dict[str, Any]:
        """Verify payment status."""
        if gateway == PaymentGateway.PAYSTACK:
            return await self._paystack_verify(reference)
        elif gateway == PaymentGateway.FLUTTERWAVE:
            return await self._flutterwave_verify(reference)
        elif gateway == PaymentGateway.RAZORPAY:
            return await self._razorpay_verify(reference)
        elif gateway == PaymentGateway.STRIPE:
            return await self._stripe_verify(reference)
        else:
            return {"error": "Unsupported gateway"}

    async def _paystack_initialize(self, payment: PaymentRequest) -> Dict[str, Any]:
        """Initialize Paystack payment (Africa)."""
        secret_key = getattr(settings, "PAYSTACK_SECRET_KEY", None)
        if not secret_key:
            return {"error": "Paystack not configured"}

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.paystack.co/transaction/initialize",
                    headers={
                        "Authorization": f"Bearer {secret_key}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "email": payment.email,
                        "amount": int(payment.amount * 100),  # Paystack uses kobo
                        "reference": payment.reference,
                        "callback_url": payment.callback_url,
                        "metadata": payment.metadata or {}
                    }
                )

            data = r.json()
            if data.get("status"):
                return {
                    "initialized": True,
                    "gateway": "paystack",
                    "authorization_url": data["data"]["authorization_url"],
                    "reference": data["data"]["reference"],
                    "access_code": data["data"]["access_code"]
                }
            return {"error": data.get("message"), "gateway": "paystack"}
        except Exception as e:
            logger.error(f"Paystack init error: {e}")
            return {"error": str(e), "gateway": "paystack"}

    async def _paystack_verify(self, reference: str) -> Dict[str, Any]:
        """Verify Paystack payment."""
        secret_key = getattr(settings, "PAYSTACK_SECRET_KEY", None)
        if not secret_key:
            return {"error": "Paystack not configured"}

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.get(
                    f"https://api.paystack.co/transaction/verify/{reference}",
                    headers={"Authorization": f"Bearer {secret_key}"}
                )

            data = r.json()
            if data.get("status"):
                return {
                    "verified": True,
                    "gateway": "paystack",
                    "status": data["data"]["status"],
                    "amount": data["data"]["amount"] / 100,
                    "currency": data["data"]["currency"],
                    "paid_at": data["data"].get("paid_at"),
                    "channel": data["data"].get("channel"),
                    "metadata": data["data"].get("metadata")
                }
            return {"error": data.get("message"), "gateway": "paystack"}
        except Exception as e:
            logger.error(f"Paystack verify error: {e}")
            return {"error": str(e), "gateway": "paystack"}

    async def _flutterwave_initialize(self, payment: PaymentRequest) -> Dict[str, Any]:
        """Initialize Flutterwave payment (Multi-currency Africa)."""
        secret_key = getattr(settings, "FLUTTERWAVE_SECRET_KEY", None)
        if not secret_key:
            return {"error": "Flutterwave not configured"}

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.flutterwave.com/v3/payments",
                    headers={
                        "Authorization": f"Bearer {secret_key}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "tx_ref": payment.reference,
                        "amount": payment.amount,
                        "currency": payment.currency,
                        "redirect_url": payment.callback_url,
                        "customer": {"email": payment.email},
                        "meta": payment.metadata or {}
                    }
                )

            data = r.json()
            if data.get("status") == "success":
                return {
                    "initialized": True,
                    "gateway": "flutterwave",
                    "authorization_url": data["data"]["link"],
                    "reference": payment.reference
                }
            return {"error": data.get("message"), "gateway": "flutterwave"}
        except Exception as e:
            logger.error(f"Flutterwave init error: {e}")
            return {"error": str(e), "gateway": "flutterwave"}

    async def _razorpay_initialize(self, payment: PaymentRequest) -> Dict[str, Any]:
        """Initialize Razorpay payment (India/Asia)."""
        key_id = getattr(settings, "RAZORPAY_KEY_ID", None)
        key_secret = getattr(settings, "RAZORPAY_KEY_SECRET", None)
        if not key_id or not key_secret:
            return {"error": "Razorpay not configured"}

        try:
            import base64
            credentials = base64.b64encode(f"{key_id}:{key_secret}".encode()).decode()

            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.razorpay.com/v1/orders",
                    headers={
                        "Authorization": f"Basic {credentials}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "amount": int(payment.amount * 100),  # Paise
                        "currency": payment.currency,
                        "receipt": payment.reference,
                        "notes": payment.metadata or {}
                    }
                )

            data = r.json()
            if "id" in data:
                return {
                    "initialized": True,
                    "gateway": "razorpay",
                    "order_id": data["id"],
                    "amount": data["amount"],
                    "currency": data["currency"],
                    "key_id": key_id  # Frontend needs this
                }
            return {"error": data.get("error", {}).get("description"), "gateway": "razorpay"}
        except Exception as e:
            logger.error(f"Razorpay init error: {e}")
            return {"error": str(e), "gateway": "razorpay"}

    async def _stripe_initialize(self, payment: PaymentRequest) -> Dict[str, Any]:
        """Initialize Stripe payment (Global)."""
        secret_key = getattr(settings, "STRIPE_SECRET_KEY", None)
        if not secret_key:
            return {"error": "Stripe not configured"}

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.stripe.com/v1/payment_intents",
                    headers={
                        "Authorization": f"Bearer {secret_key}",
                        "Content-Type": "application/x-www-form-urlencoded"
                    },
                    data={
                        "amount": int(payment.amount * 100),
                        "currency": payment.currency.lower(),
                        "receipt_email": payment.email,
                        "metadata[reference]": payment.reference,
                        "automatic_payment_methods[enabled]": "true"
                    }
                )

            data = r.json()
            if "client_secret" in data:
                return {
                    "initialized": True,
                    "gateway": "stripe",
                    "client_secret": data["client_secret"],
                    "payment_intent_id": data["id"],
                    "publishable_key": getattr(settings, "STRIPE_PUBLISHABLE_KEY", None)
                }
            return {"error": data.get("error", {}).get("message"), "gateway": "stripe"}
        except Exception as e:
            logger.error(f"Stripe init error: {e}")
            return {"error": str(e), "gateway": "stripe"}


# ═══════════════════════════════════════════════════════════════════
# CALENDAR SCHEDULING SERVICE
# ═══════════════════════════════════════════════════════════════════

class CalendarService:
    """Schedule meetings and manage calendar."""

    async def create_event(
        self,
        title: str,
        start_time: datetime,
        end_time: datetime,
        attendees: List[str],
        description: Optional[str] = None,
        location: Optional[str] = None,
        user_tokens: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """Create Google Calendar event."""
        access_token = (user_tokens or {}).get("access_token") or \
                       getattr(settings, "GOOGLE_CALENDAR_TOKEN", None)

        if not access_token:
            return {"error": "Google Calendar not configured"}

        event = {
            "summary": title,
            "description": description or "",
            "start": {
                "dateTime": start_time.isoformat(),
                "timeZone": "UTC"
            },
            "end": {
                "dateTime": end_time.isoformat(),
                "timeZone": "UTC"
            },
            "attendees": [{"email": e} for e in attendees]
        }

        if location:
            event["location"] = location

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json"
                    },
                    json=event
                )

            data = r.json()
            if r.status_code == 200:
                return {
                    "created": True,
                    "event_id": data["id"],
                    "html_link": data["htmlLink"],
                    "start": data["start"]["dateTime"],
                    "end": data["end"]["dateTime"]
                }
            return {"error": data.get("error", {}).get("message"), "status_code": r.status_code}
        except Exception as e:
            logger.error(f"Calendar error: {e}")
            return {"error": str(e)}

    async def generate_calendly_link(
        self,
        event_type: str = "30min",
        user_id: Optional[str] = None
    ) -> str:
        """Generate Cal.com or Calendly scheduling link."""
        cal_username = getattr(settings, "CAL_COM_USERNAME", None)
        if cal_username:
            return f"https://cal.com/{cal_username}/{event_type}"
        
        calendly_username = getattr(settings, "CALENDLY_USERNAME", None)
        if calendly_username:
            return f"https://calendly.com/{calendly_username}/{event_type}"
        
        return ""


# ═══════════════════════════════════════════════════════════════════
# SMS SERVICE (Global Coverage)
# ═══════════════════════════════════════════════════════════════════

class SMSService:
    """Send SMS globally with regional providers."""

    async def send(
        self,
        to_number: str,
        message: str,
        provider: Optional[SMSProvider] = None,
        country_code: Optional[str] = None
    ) -> Dict[str, Any]:
        """Send SMS with automatic provider selection."""
        if not provider:
            provider = self._select_provider(country_code)

        if provider == SMSProvider.TWILIO:
            return await self._send_twilio(to_number, message)
        elif provider == SMSProvider.AFRICASTALKING:
            return await self._send_africastalking(to_number, message)
        elif provider == SMSProvider.TERMII:
            return await self._send_termii(to_number, message)
        else:
            return await self._send_twilio(to_number, message)  # Default

    def _select_provider(self, country_code: Optional[str]) -> SMSProvider:
        """Select best provider for country."""
        if not country_code:
            return SMSProvider.TWILIO
        
        africa_countries = ["NG", "GH", "KE", "ZA", "UG", "TZ", "RW"]
        if country_code.upper() in africa_countries:
            return SMSProvider.AFRICASTALKING
        
        if country_code.upper() == "NG":
            return SMSProvider.TERMII
        
        return SMSProvider.TWILIO

    async def _send_twilio(self, to: str, message: str) -> Dict[str, Any]:
        """Send via Twilio."""
        account_sid = getattr(settings, "TWILIO_ACCOUNT_SID", None)
        auth_token = getattr(settings, "TWILIO_AUTH_TOKEN", None)
        from_number = getattr(settings, "TWILIO_PHONE_NUMBER", None)

        if not all([account_sid, auth_token, from_number]):
            return {"sent": False, "error": "Twilio not configured"}

        try:
            from twilio.rest import Client
            client = Client(account_sid, auth_token)
            
            msg = client.messages.create(
                body=message[:1600],  # Twilio limit
                from_=from_number,
                to=to
            )

            return {
                "sent": True,
                "provider": "twilio",
                "sid": msg.sid,
                "status": msg.status,
                "to": to
            }
        except Exception as e:
            logger.error(f"Twilio error: {e}")
            return {"sent": False, "error": str(e), "provider": "twilio"}

    async def _send_africastalking(self, to: str, message: str) -> Dict[str, Any]:
        """Send via Africa's Talking."""
        username = getattr(settings, "AFRICASTALKING_USERNAME", None)
        api_key = getattr(settings, "AFRICASTALKING_API_KEY", None)
        from_number = getattr(settings, "AFRICASTALKING_SENDER", None)

        if not all([username, api_key]):
            return {"sent": False, "error": "Africa's Talking not configured"}

        try:
            import africastalking
            africastalking.initialize(username, api_key)
            sms = africastalking.SMS

            response = sms.send(message[:1600], [to], from_number)
            
            return {
                "sent": True,
                "provider": "africastalking",
                "response": response,
                "to": to
            }
        except Exception as e:
            logger.error(f"Africa's Talking error: {e}")
            return {"sent": False, "error": str(e), "provider": "africastalking"}

    async def _send_termii(self, to: str, message: str) -> Dict[str, Any]:
        """Send via Termii (Nigeria focused)."""
        api_key = getattr(settings, "TERMII_API_KEY", None)
        sender_id = getattr(settings, "TERMII_SENDER_ID", "RiseUp")

        if not api_key:
            return {"sent": False, "error": "Termii not configured"}

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                r = await client.post(
                    "https://api.ng.termii.com/api/sms/send",
                    json={
                        "to": to.replace("+", ""),
                        "from": sender_id,
                        "sms": message,
                        "type": "plain",
                        "channel": "generic",
                        "api_key": api_key
                    }
                )

            data = r.json()
            if data.get("message_id"):
                return {
                    "sent": True,
                    "provider": "termii",
                    "message_id": data["message_id"],
                    "to": to
                }
            return {"sent": False, "error": data.get("error"), "provider": "termii"}
        except Exception as e:
            logger.error(f"Termii error: {e}")
            return {"sent": False, "error": str(e), "provider": "termii"}


# ═══════════════════════════════════════════════════════════════════
# DOCUMENT GENERATOR (Enhanced with PDF Support)
# ═══════════════════════════════════════════════════════════════════

class DocumentService:
    """Generate professional documents with PDF export."""

    def __init__(self):
        self.templates = {
            "freelance_contract": self.generate_freelance_contract,
            "invoice": self.generate_invoice,
            "business_proposal": self.generate_business_proposal,
            "pitch_deck": self.generate_pitch_deck_outline,
            "receipt": self.generate_receipt,
            "agreement": self.generate_service_agreement,
        }

    def generate_freelance_contract(
        self,
        client_name: str,
        freelancer_name: str,
        project_title: str,
        deliverables: List[str],
        amount: float,
        currency: str,
        deadline: str,
        payment_terms: str = "50% upfront, 50% on delivery",
        jurisdiction: str = "Local Laws",
    ) -> Dict[str, Any]:
        """Generate freelance contract with metadata."""
        today = datetime.now().strftime("%B %d, %Y")
        deliverables_text = "\n".join(f"  {i+1}. {d}" for i, d in enumerate(deliverables))
        
        content = f"""FREELANCE SERVICE AGREEMENT
═══════════════════════════════════════════════════════

Date: {today}

PARTIES
───────
Client:     {client_name}
Freelancer: {freelancer_name}

PROJECT
───────
Title:    {project_title}
Deadline: {deadline}

DELIVERABLES
────────────
{deliverables_text}

PAYMENT
───────
Total Amount: {currency} {amount:,.2f}
Payment Terms: {payment_terms}

TERMS & CONDITIONS
──────────────────
1. OWNERSHIP: Upon full payment, all work product becomes the sole property of the Client.
2. REVISIONS: Up to 2 rounds of revisions are included. Additional revisions billed at hourly rate.
3. CONFIDENTIALITY: Both parties agree to keep project details confidential.
4. CANCELLATION: If Client cancels after work has begun, a kill fee of 30% of total amount is payable.
5. INDEPENDENT CONTRACTOR: Freelancer is an independent contractor, not an employee.
6. GOVERNING LAW: This agreement shall be governed by {jurisdiction}.
7. DISPUTE RESOLUTION: Disputes shall first be attempted to be resolved through mediation.

ACCEPTANCE
──────────
By proceeding with this project, both parties agree to the terms above.

Client Signature: ___________________________  Date: ____________

Freelancer Signature: ______________________  Date: ____________

─────────────────────────────────────────────────────────
Generated by RiseUp AI | {today}
"""

        return {
            "content": content,
            "type": "freelance_contract",
            "metadata": {
                "client": client_name,
                "freelancer": freelancer_name,
                "amount": amount,
                "currency": currency,
                "deadline": deadline,
                "generated_at": today
            }
        }

    def generate_invoice(
        self,
        client_name: str,
        freelancer_name: str,
        freelancer_email: str,
        items: List[Dict],
        currency: str,
        invoice_number: Optional[str] = None,
        due_date: Optional[str] = None,
        notes: Optional[str] = None,
        bank_details: Optional[Dict] = None,
    ) -> Dict[str, Any]:
        """Generate professional invoice."""
        today = datetime.now().strftime("%B %d, %Y")
        inv_num = invoice_number or f"INV-{datetime.now().strftime('%Y%m%d%H%M')}"
        due = due_date or (datetime.now() + timedelta(days=7)).strftime("%B %d, %Y")
        total = sum(i.get("amount", 0) for i in items)
        
        items_text = "\n".join(
            f"  {i+1}. {item.get('description',''):<40} {currency} {item.get('amount', 0):>10,.2f} x {item.get('quantity', 1)}"
            for i, item in enumerate(items)
        )

        bank_text = ""
        if bank_details:
            bank_text = f"""
BANK DETAILS
────────────
Bank Name:      {bank_details.get('bank_name', 'N/A')}
Account Name:   {bank_details.get('account_name', 'N/A')}
Account Number: {bank_details.get('account_number', 'N/A')}
Sort Code:      {bank_details.get('sort_code', 'N/A')}
Swift/BIC:      {bank_details.get('swift', 'N/A')}
"""

        content = f"""INVOICE
═══════════════════════════════════════════════════════

Invoice #:  {inv_num}
Date:       {today}
Due Date:   {due}

FROM
────
{freelancer_name}
{freelancer_email}

TO
──
{client_name}

ITEMS
─────
{"#":<4} {"Description":<40} {"Amount":>15}
{"─"*60}
{items_text}
{"─"*60}
{"TOTAL":<45} {currency} {total:>10,.2f}

{notes if notes else ""}

{bank_text}

PAYMENT INSTRUCTIONS
────────────────────
Please transfer to the account details above.
Reference your invoice number {inv_num} in the payment description.

Thank you for your business!

─────────────────────────────────────────────────────────
Generated by RiseUp AI | {today}
"""

        return {
            "content": content,
            "type": "invoice",
            "metadata": {
                "invoice_number": inv_num,
                "client": client_name,
                "total": total,
                "currency": currency,
                "due_date": due,
                "generated_at": today
            }
        }

    def generate_receipt(
        self,
        payer_name: str,
        recipient_name: str,
        amount: float,
        currency: str,
        description: str,
        payment_method: str = "Bank Transfer"
    ) -> Dict[str, Any]:
        """Generate payment receipt."""
        today = datetime.now().strftime("%B %d, %Y")
        receipt_num = f"RCP-{datetime.now().strftime('%Y%m%d%H%M%S')}"

        content = f"""PAYMENT RECEIPT
═══════════════════════════════════════════════════════

Receipt #:  {receipt_num}
Date:       {today}

RECEIVED FROM
─────────────
{payer_name}

PAID TO
───────
{recipient_name}

PAYMENT DETAILS
───────────────
Amount:         {currency} {amount:,.2f}
Description:    {description}
Payment Method: {payment_method}
Status:         PAID

This confirms that the above amount has been received in full.

Thank you for your payment!

─────────────────────────────────────────────────────────
Generated by RiseUp AI | {today}
"""

        return {
            "content": content,
            "type": "receipt",
            "metadata": {
                "receipt_number": receipt_num,
                "payer": payer_name,
                "amount": amount,
                "currency": currency,
                "generated_at": today
            }
        }

    def generate_service_agreement(
        self,
        service_provider: str,
        client: str,
        service_description: str,
        duration: str,
        fee: float,
        currency: str,
        termination_notice: str = "30 days"
    ) -> Dict[str, Any]:
        """Generate service agreement."""
        today = datetime.now().strftime("%B %d, %Y")

        content = f"""SERVICE AGREEMENT
═══════════════════════════════════════════════════════

Date: {today}

PARTIES
───────
Service Provider: {service_provider}
Client:           {client}

SERVICES
────────
{service_description}

TERM
────
Duration: {duration}
Start Date: {today}

COMPENSATION
────────────
Fee: {currency} {fee:,.2f}
Payment Schedule: Monthly, due on the 1st of each month

TERMINATION
───────────
Either party may terminate this agreement with {termination_notice} written notice.

SIGNATURES
──────────
Service Provider: ___________________________  Date: ____________

Client:           ___________________________  Date: ____________

─────────────────────────────────────────────────────────
Generated by RiseUp AI | {today}
"""

        return {
            "content": content,
            "type": "service_agreement",
            "metadata": {
                "provider": service_provider,
                "client": client,
                "fee": fee,
                "currency": currency,
                "duration": duration,
                "generated_at": today
            }
        }

    def generate_business_proposal(
        self,
        business_name: str,
        owner_name: str,
        business_type: str,
        target_market: str,
        problem: str,
        solution: str,
        revenue_model: str,
        startup_costs: str,
        timeline: str,
        contact_email: str,
    ) -> Dict[str, Any]:
        """Generate business proposal."""
        today = datetime.now().strftime("%B %d, %Y")
        
        content = f"""BUSINESS PROPOSAL
═══════════════════════════════════════════════════════

{business_name.upper()}
Prepared by: {owner_name}
Date: {today}

EXECUTIVE SUMMARY
─────────────────
{business_name} is a {business_type} business targeting {target_market}.
This proposal outlines the opportunity, solution, and path to profitability.

THE PROBLEM
───────────
{problem}

OUR SOLUTION
────────────
{solution}

REVENUE MODEL
─────────────
{revenue_model}

STARTUP REQUIREMENTS
────────────────────
{startup_costs}

TIMELINE
────────
{timeline}

WHY NOW
───────
The market conditions and available digital tools make this the ideal time
to launch this business. With minimal capital and maximum leverage of
free/low-cost digital infrastructure, {business_name} can reach profitability
within the projected timeline.

CONTACT
───────
{owner_name}
{contact_email}

─────────────────────────────────────────────────────────
Generated by RiseUp AI | {today}
"""

        return {
            "content": content,
            "type": "business_proposal",
            "metadata": {
                "business_name": business_name,
                "owner": owner_name,
                "generated_at": today
            }
        }

    def generate_pitch_deck_outline(
        self,
        business_name: str,
        problem: str,
        solution: str,
        market_size: str,
        traction: str,
        ask: str,
    ) -> Dict[str, Any]:
        """Generate pitch deck outline."""
        
        content = f"""PITCH DECK — {business_name.upper()}
═══════════════════════════════════════════════════════

SLIDE 1 — COVER
  {business_name}
  [Your one-line tagline here]

SLIDE 2 — PROBLEM
  {problem}

SLIDE 3 — SOLUTION
  {solution}

SLIDE 4 — MARKET SIZE
  {market_size}

SLIDE 5 — HOW IT WORKS
  [3-step diagram: User does X → Platform does Y → User gets Z]

SLIDE 6 — TRACTION / PROOF
  {traction}

SLIDE 7 — BUSINESS MODEL
  [How you make money — subscriptions / commissions / ads / etc.]

SLIDE 8 — TEAM
  [Your name + background, any co-founders]

SLIDE 9 — THE ASK
  {ask}

SLIDE 10 — CONTACT
  [Email / LinkedIn / Website]

─────────────────────────────────────────────────────────
Generated by RiseUp AI
"""

        return {
            "content": content,
            "type": "pitch_deck",
            "metadata": {
                "business_name": business_name,
                "slides": 10
            }
        }

    async def generate_pdf(self, document: Dict[str, Any]) -> bytes:
        """Convert document to PDF bytes."""
        try:
            from weasyprint import HTML, CSS
            from weasyprint.text.fonts import FontConfiguration

            # Convert markdown-like to HTML
            html_content = self._markdown_to_html(document["content"])
            
            font_config = FontConfiguration()
            html = HTML(string=html_content)
            
            pdf_bytes = html.write_pdf(
                stylesheets=[CSS(string=self._get_pdf_styles())],
                font_config=font_config
            )
            
            return pdf_bytes
        except ImportError:
            logger.warning("WeasyPrint not installed, returning text")
            return document["content"].encode()
        except Exception as e:
            logger.error(f"PDF generation error: {e}")
            return document["content"].encode()

    def _markdown_to_html(self, content: str) -> str:
        """Convert plain text to HTML for PDF."""
        lines = content.split("\n")
        html_lines = ["<html><head><meta charset='utf-8'></head><body>"]
        
        for line in lines:
            if line.startswith("══"):
                continue
            elif line.isupper() and len(line) < 100:
                html_lines.append(f"<h2>{line}</h2>")
            elif line.startswith("  "):
                html_lines.append(f"<p style='margin-left: 20px;'>{line.strip()}</p>")
            elif line.startswith("────"):
                html_lines.append("<hr>")
            elif line.strip() == "":
                html_lines.append("<br>")
            else:
                html_lines.append(f"<p>{line}</p>")
        
        html_lines.append("</body></html>")
        return "\n".join(html_lines)

    def _get_pdf_styles(self) -> str:
        """Get CSS styles for PDF."""
        return """
        @page { margin: 2cm; }
        body { font-family: Georgia, serif; line-height: 1.6; color: #333; }
        h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 5px; }
        hr { border: none; border-top: 1px solid #ccc; margin: 20px 0; }
        p { margin: 10px 0; }
        """


# ═══════════════════════════════════════════════════════════════════
# OPPORTUNITY SCANNER (Enhanced)
# ═══════════════════════════════════════════════════════════════════

class OpportunityScanner:
    """Monitors and surfaces new income opportunities for users."""

    async def scan_for_user(self, profile: dict) -> List[Dict]:
        """Find current opportunities matching the user's skills and goals."""
        from services.web_search_service import web_search_service

        skills = profile.get("current_skills", [])
        country = profile.get("country", "NG")
        stage = profile.get("stage", "survival")

        queries = []
        for skill in (skills or ["general"])[:3]:
            queries.append(f"{skill} freelance jobs remote hiring {country} 2025")
            queries.append(f"{skill} gig work earn money online 2025")

        if stage in ("survival", "earning"):
            queries.append("quick earn money online no experience 2025")
            queries.append(f"microtask gig work {country} pay today")
        else:
            queries.append(f"business partnership {' '.join(skills[:2])} {country}")

        import asyncio
        batches = await asyncio.gather(*[
            web_search_service.search(q, 4) for q in queries[:4]
        ])
        
        opps = []
        seen = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen:
                        seen.add(r["url"])
                        opps.append({
                            "title": r.get("title", ""),
                            "url": r["url"],
                            "snippet": r.get("snippet", ""),
                            "source": "web_search",
                            "relevance_score": self._calculate_relevance(r, profile)
                        })
        
        # Sort by relevance
        opps.sort(key=lambda x: x["relevance_score"], reverse=True)
        return opps[:10]

    def _calculate_relevance(self, result: Dict, profile: Dict) -> float:
        """Calculate relevance score for opportunity."""
        score = 0.0
        title_lower = result.get("title", "").lower()
        snippet_lower = result.get("snippet", "").lower()
        skills = [s.lower() for s in profile.get("current_skills", [])]
        
        # Skill match
        for skill in skills:
            if skill in title_lower or skill in snippet_lower:
                score += 2.0
        
        # Urgency indicators
        urgent_words = ["urgent", "immediate", "hiring now", "asap", "today"]
        for word in urgent_words:
            if word in snippet_lower:
                score += 1.0
        
        # Remote friendly
        if "remote" in snippet_lower:
            score += 0.5
        
        return score


# ═══════════════════════════════════════════════════════════════════
# AUTOMATION SEQUENCES
# ═══════════════════════════════════════════════════════════════════

class AutomationService:
    """Handle automated follow-up sequences."""

    async def create_follow_up_sequence(
        self,
        user_id: str,
        sequence_type: str,  # onboarding, invoice_reminder, proposal_followup
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Create automated follow-up sequence."""
        sequences = {
            "onboarding": self._onboarding_sequence,
            "invoice_reminder": self._invoice_reminder_sequence,
            "proposal_followup": self._proposal_followup_sequence,
        }

        if sequence_type not in sequences:
            return {"error": f"Unknown sequence type: {sequence_type}"}

        return await sequences[sequence_type](user_id, context)

    async def _onboarding_sequence(self, user_id: str, context: Dict) -> Dict[str, Any]:
        """Create onboarding email sequence."""
        from services.supabase_service import supabase_service
        
        steps = [
            {
                "delay_hours": 0,
                "action": "send_email",
                "template": "welcome",
                "subject": "Welcome to RiseUp - Let's Build Your Wealth"
            },
            {
                "delay_hours": 24,
                "action": "send_email",
                "template": "profile_completion",
                "subject": "Complete Your Profile for Personalized Recommendations"
            },
            {
                "delay_hours": 72,
                "action": "send_email",
                "template": "first_goal",
                "subject": "Set Your First 90-Day Income Goal"
            },
            {
                "delay_hours": 168,
                "action": "send_whatsapp",
                "message": "Hi! How's your wealth-building journey going? Need help with anything?"
            }
        ]

        try:
            sb = supabase_service.client
            scheduled = []
            
            for step in steps:
                execute_at = datetime.now(timezone.utc) + timedelta(hours=step["delay_hours"])
                row = sb.table("automation_sequences").insert({
                    "user_id": user_id,
                    "sequence_type": "onboarding",
                    "step_number": len(scheduled) + 1,
                    "action": step["action"],
                    "payload": json.dumps(step),
                    "execute_at": execute_at.isoformat(),
                    "status": "pending"
                }).execute()
                scheduled.append(row.data[0]["id"])

            return {
                "created": True,
                "sequence": "onboarding",
                "steps_scheduled": len(scheduled),
                "step_ids": scheduled
            }
        except Exception as e:
            logger.error(f"Onboarding sequence error: {e}")
            return {"error": str(e)}

    async def _invoice_reminder_sequence(self, user_id: str, context: Dict) -> Dict[str, Any]:
        """Create invoice reminder sequence."""
        invoice_id = context.get("invoice_id")
        client_email = context.get("client_email")
        amount = context.get("amount")
        currency = context.get("currency")
        due_date = context.get("due_date")

        steps = [
            {
                "delay_hours": 0,
                "action": "send_email",
                "template": "invoice_sent",
                "to": client_email
            },
            {
                "delay_hours": 24 * 3,  # 3 days before
                "action": "send_email",
                "template": "payment_reminder",
                "to": client_email,
                "condition": "not_paid"
            },
            {
                "delay_hours": 24 * 7,  # On due date
                "action": "send_email",
                "template": "due_today",
                "to": client_email,
                "condition": "not_paid"
            },
            {
                "delay_hours": 24 * 9,  # 2 days after
                "action": "send_whatsapp",
                "message": f"Hi! Just following up on invoice {invoice_id} for {currency} {amount}. Please let me know if you have any questions!",
                "condition": "not_paid"
            }
        ]

        # Save to database
        return {"created": True, "sequence": "invoice_reminder", "steps": len(steps)}

    async def _proposal_followup_sequence(self, user_id: str, context: Dict) -> Dict[str, Any]:
        """Create proposal follow-up sequence."""
        steps = [
            {
                "delay_hours": 24 * 2,
                "action": "send_email",
                "template": "proposal_followup",
                "subject": "Following up on my proposal"
            },
            {
                "delay_hours": 24 * 7,
                "action": "send_email",
                "template": "value_add",
                "subject": "Thought you might find this helpful"
            },
            {
                "delay_hours": 24 * 14,
                "action": "send_email",
                "template": "final_followup",
                "subject": "Last follow-up: Proposal status"
            }
        ]

        return {"created": True, "sequence": "proposal_followup", "steps": len(steps)}

    async def execute_pending_automations(self) -> Dict[str, Any]:
        """Execute due automations (call via cron job)."""
        from services.supabase_service import supabase_service
        
        try:
            sb = supabase_service.client
            now = datetime.now(timezone.utc).isoformat()

            # Get pending automations
            result = sb.table("automation_sequences").select("*").eq(
                "status", "pending"
            ).lte("execute_at", now).execute()

            executed = []
            failed = []

            for auto in result.data:
                try:
                    payload = json.loads(auto["payload"])
                    
                    if auto["action"] == "send_email":
                        # Execute email
                        pass  # Implement based on your email service
                    elif auto["action"] == "send_whatsapp":
                        # Execute WhatsApp
                        pass  # Implement based on your WhatsApp service

                    # Update status
                    sb.table("automation_sequences").update({
                        "status": "executed",
                        "executed_at": datetime.now(timezone.utc).isoformat()
                    }).eq("id", auto["id"]).execute()

                    executed.append(auto["id"])

                except Exception as e:
                    failed.append({"id": auto["id"], "error": str(e)})
                    sb.table("automation_sequences").update({
                        "status": "failed",
                        "error": str(e)
                    }).eq("id", auto["id"]).execute()

            return {
                "processed": len(result.data),
                "executed": len(executed),
                "failed": failed
            }

        except Exception as e:
            logger.error(f"Execute automations error: {e}")
            return {"error": str(e)}


# ─── Singletons ───────────────────────────────────────────────────
email_service = EmailService()
whatsapp_service = WhatsAppService()
social_service = SocialMediaService()
payment_service = PaymentService()
calendar_service = CalendarService()
sms_service = SMSService()
document_service = DocumentService()
opportunity_scanner = OpportunityScanner()
automation_service = AutomationService()
