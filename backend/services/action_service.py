"""
RiseUp Action Service
─────────────────────────────────────────────────────────────────────
Gives the agent the ability to take REAL ACTIONS in the world:
  • Send emails (SMTP / SendGrid)
  • Post to Twitter/X, LinkedIn
  • Generate downloadable contracts, invoices, proposals (PDF-ready text)
  • Schedule follow-up actions
  • Build platform profile content

These are the tools that turn the agent from a planner into a WORKER.
"""

import logging
import httpx
import json
import smtplib
import ssl
from email.mime.text    import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime            import datetime, timezone
from typing              import Optional, Dict, Any, List

from config import settings

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════
# EMAIL SERVICE
# ═══════════════════════════════════════════════════════════════════

class EmailService:
    """Send emails via SendGrid API or SMTP fallback."""

    async def send(
        self,
        to_email:    str,
        subject:     str,
        body_text:   str,
        body_html:   Optional[str] = None,
        from_name:   str = "RiseUp Agent",
        from_email:  Optional[str] = None,
        reply_to:    Optional[str] = None,
    ) -> Dict:
        """Send an email. Tries SendGrid first, then SMTP."""
        sender = from_email or getattr(settings, "EMAIL_FROM", "noreply@riseup.app")

        # Try SendGrid
        if getattr(settings, "SENDGRID_API_KEY", None):
            return await self._sendgrid(to_email, subject, body_text, body_html or body_text,
                                         sender, from_name, reply_to)

        # Try SMTP
        if getattr(settings, "SMTP_HOST", None):
            return self._smtp(to_email, subject, body_text, body_html, sender, from_name)

        logger.warning("No email provider configured. Email not sent.")
        return {"sent": False, "error": "No email provider configured",
                "preview": f"TO: {to_email}\nSUBJECT: {subject}\n\n{body_text[:300]}"}

    async def _sendgrid(self, to, subject, text, html, sender, from_name, reply_to) -> Dict:
        payload = {
            "personalizations": [{"to": [{"email": to}]}],
            "from":             {"email": sender, "name": from_name},
            "subject":          subject,
            "content": [
                {"type": "text/plain", "value": text},
                {"type": "text/html",  "value": html},
            ],
        }
        if reply_to:
            payload["reply_to"] = {"email": reply_to}

        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(
                "https://api.sendgrid.com/v3/mail/send",
                headers={"Authorization": f"Bearer {settings.SENDGRID_API_KEY}",
                         "Content-Type": "application/json"},
                json=payload,
            )
        if r.status_code in (200, 202):
            return {"sent": True, "provider": "sendgrid", "to": to, "subject": subject}
        return {"sent": False, "error": r.text, "provider": "sendgrid"}

    def _smtp(self, to, subject, text, html, sender, from_name) -> Dict:
        try:
            msg               = MIMEMultipart("alternative")
            msg["Subject"]    = subject
            msg["From"]       = f"{from_name} <{sender}>"
            msg["To"]         = to
            msg.attach(MIMEText(text, "plain"))
            if html:
                msg.attach(MIMEText(html, "html"))

            ctx = ssl.create_default_context()
            with smtplib.SMTP_SSL(settings.SMTP_HOST, int(getattr(settings, "SMTP_PORT", 465)), context=ctx) as server:
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                server.sendmail(sender, to, msg.as_string())
            return {"sent": True, "provider": "smtp", "to": to, "subject": subject}
        except Exception as e:
            return {"sent": False, "error": str(e), "provider": "smtp"}


# ═══════════════════════════════════════════════════════════════════
# SOCIAL MEDIA SERVICE
# ═══════════════════════════════════════════════════════════════════

class SocialMediaService:
    """Post content to Twitter/X and LinkedIn on behalf of the user."""

    async def post_twitter(self, text: str, user_tokens: Dict) -> Dict:
        """
        Post a tweet using the user's OAuth2 tokens.
        user_tokens = {"access_token": "...", "token_type": "bearer"}
        """
        access_token = user_tokens.get("access_token") or \
                       getattr(settings, "TWITTER_ACCESS_TOKEN", None)
        if not access_token:
            return {"posted": False, "error": "Twitter access token not configured",
                    "preview": text[:280], "platform": "twitter"}
        try:
            async with httpx.AsyncClient(timeout=12) as client:
                r = await client.post(
                    "https://api.twitter.com/2/tweets",
                    headers={"Authorization": f"Bearer {access_token}",
                             "Content-Type": "application/json"},
                    json={"text": text[:280]},
                )
            data = r.json()
            if r.status_code == 201:
                tweet_id = data.get("data", {}).get("id", "")
                return {
                    "posted":     True,
                    "platform":   "twitter",
                    "post_id":    tweet_id,
                    "url":        f"https://twitter.com/i/web/status/{tweet_id}",
                    "preview":    text[:280],
                }
            return {"posted": False, "error": data, "platform": "twitter", "preview": text[:280]}
        except Exception as e:
            return {"posted": False, "error": str(e), "platform": "twitter", "preview": text[:280]}

    async def post_linkedin(self, text: str, user_tokens: Dict) -> Dict:
        """
        Post to LinkedIn using the user's OAuth2 token.
        user_tokens = {"access_token": "...", "person_urn": "urn:li:person:xxxx"}
        """
        access_token = user_tokens.get("access_token") or \
                       getattr(settings, "LINKEDIN_ACCESS_TOKEN", None)
        person_urn   = user_tokens.get("person_urn") or \
                       getattr(settings, "LINKEDIN_PERSON_URN", None)
        if not access_token or not person_urn:
            return {"posted": False, "error": "LinkedIn credentials not configured",
                    "preview": text[:700], "platform": "linkedin"}
        try:
            payload = {
                "author":     person_urn,
                "lifecycleState": "PUBLISHED",
                "specificContent": {
                    "com.linkedin.ugc.ShareContent": {
                        "shareCommentary": {"text": text[:700]},
                        "shareMediaCategory": "NONE",
                    }
                },
                "visibility": {"com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"},
            }
            async with httpx.AsyncClient(timeout=12) as client:
                r = await client.post(
                    "https://api.linkedin.com/v2/ugcPosts",
                    headers={"Authorization": f"Bearer {access_token}",
                             "Content-Type":  "application/json",
                             "X-Restli-Protocol-Version": "2.0.0"},
                    json=payload,
                )
            if r.status_code == 201:
                post_id = r.headers.get("x-restli-id", "")
                return {"posted": True, "platform": "linkedin", "post_id": post_id,
                        "preview": text[:700]}
            return {"posted": False, "error": r.text, "platform": "linkedin", "preview": text[:700]}
        except Exception as e:
            return {"posted": False, "error": str(e), "platform": "linkedin", "preview": text[:700]}

    async def schedule_post(self, platform: str, text: str, schedule_at: str,
                             user_id: str) -> Dict:
        """Save a scheduled post to the database for later execution."""
        from services.supabase_service import supabase_service
        try:
            sb  = supabase_service.client
            row = sb.table("scheduled_posts").insert({
                "user_id":      user_id,
                "platform":     platform,
                "content":      text,
                "schedule_at":  schedule_at,
                "status":       "pending",
            }).execute()
            return {"scheduled": True, "platform": platform,
                    "schedule_at": schedule_at,
                    "post_id": row.data[0]["id"] if row.data else None}
        except Exception as e:
            return {"scheduled": False, "error": str(e)}


# ═══════════════════════════════════════════════════════════════════
# DOCUMENT GENERATOR
# ═══════════════════════════════════════════════════════════════════

class DocumentService:
    """Generate professional documents: contracts, invoices, proposals, business plans."""

    def generate_freelance_contract(
        self,
        client_name:    str,
        freelancer_name: str,
        project_title:  str,
        deliverables:   List[str],
        amount:         float,
        currency:       str,
        deadline:       str,
        payment_terms:  str = "50% upfront, 50% on delivery",
    ) -> str:
        """Generate a simple but legally structured freelance contract."""
        today = datetime.now().strftime("%B %d, %Y")
        deliverables_text = "\n".join(f"  {i+1}. {d}" for i, d in enumerate(deliverables))
        return f"""FREELANCE SERVICE AGREEMENT
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
6. GOVERNING LAW: This agreement shall be governed by applicable local laws.
7. DISPUTE RESOLUTION: Disputes shall first be attempted to be resolved through mediation.

ACCEPTANCE
──────────
By proceeding with this project, both parties agree to the terms above.

Client Signature: ___________________________  Date: ____________

Freelancer Signature: ______________________  Date: ____________

─────────────────────────────────────────────────────────
Generated by RiseUp Agent | {today}
"""

    def generate_invoice(
        self,
        client_name:     str,
        freelancer_name: str,
        freelancer_email: str,
        items:           List[Dict],
        currency:        str,
        invoice_number:  str = None,
        due_date:        str = None,
    ) -> str:
        today      = datetime.now().strftime("%B %d, %Y")
        inv_num    = invoice_number or f"INV-{datetime.now().strftime('%Y%m%d%H%M')}"
        due        = due_date or "Net 7 days"
        total      = sum(i.get("amount", 0) for i in items)
        items_text = "\n".join(
            f"  {i.get('description',''):<45} {currency} {i.get('amount', 0):>10,.2f}"
            for i in items
        )
        return f"""INVOICE
═══════════════════════════════════════════════════════

Invoice #:  {inv_num}
Date:       {today}
Due:        {due}

FROM
────
{freelancer_name}
{freelancer_email}

TO
──
{client_name}

ITEMS
─────
{"Description":<45} {"Amount":>15}
{"─"*60}
{items_text}
{"─"*60}
{"TOTAL":<45} {currency} {total:>10,.2f}

PAYMENT INSTRUCTIONS
────────────────────
Please transfer to the account/wallet details provided separately.
Reference your invoice number {inv_num} in the payment description.

Thank you for your business!

─────────────────────────────────────────────────────────
Generated by RiseUp Agent | {today}
"""

    def generate_business_proposal(
        self,
        business_name:  str,
        owner_name:     str,
        business_type:  str,
        target_market:  str,
        problem:        str,
        solution:       str,
        revenue_model:  str,
        startup_costs:  str,
        timeline:       str,
        contact_email:  str,
    ) -> str:
        today = datetime.now().strftime("%B %d, %Y")
        return f"""BUSINESS PROPOSAL
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
─────────────────────
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
Generated by RiseUp Agent | {today}
"""

    def generate_pitch_deck_outline(
        self,
        business_name:  str,
        problem:        str,
        solution:       str,
        market_size:    str,
        traction:       str,
        ask:            str,
    ) -> str:
        return f"""PITCH DECK — {business_name.upper()}
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
Generated by RiseUp Agent
"""


# ═══════════════════════════════════════════════════════════════════
# OPPORTUNITY SCANNER
# ═══════════════════════════════════════════════════════════════════

class OpportunityScanner:
    """Monitors and surfaces new income opportunities for users."""

    async def scan_for_user(self, profile: dict) -> List[Dict]:
        """Find current opportunities matching the user's skills and goals."""
        from services.web_search_service import web_search_service

        skills  = profile.get("current_skills", [])
        country = profile.get("country", "NG")
        stage   = profile.get("stage", "survival")

        # Build targeted queries based on their actual skills
        queries = []
        for skill in (skills or ["general"])[:3]:
            queries.append(f"{skill} freelance jobs remote hiring {country} 2025")
            queries.append(f"{skill} gig work earn money online 2025")

        if stage in ("survival", "earning"):
            queries.append("quick earn money online no experience 2025")
            queries.append(f"microtask gig work {country} pay today")
        else:
            queries.append(f"business partnership {' '.join(skills[:2])} Nigeria")

        import asyncio
        batches = await asyncio.gather(*[web_search_service.search(q, 4) for q in queries[:4]])
        opps    = []
        seen    = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen:
                        seen.add(r["url"])
                        opps.append(r)
        return opps[:10]


# ─── Singletons ───────────────────────────────────────────────────
email_service     = EmailService()
social_service    = SocialMediaService()
document_service  = DocumentService()
opportunity_scanner = OpportunityScanner()
