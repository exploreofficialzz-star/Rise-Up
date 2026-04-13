"""
backend/services/task_router.py
APEX Task Router — Production v1.0

Maps any user task string → WorkflowTemplate containing:
  • start_url         — where the browser opens
  • goals             — ordered natural-language browser goals
  • user_questions    — questions to collect before starting
  • estimated_tokens  — token budget hint for UI
  • needs_browser     — whether Playwright is required
  • login_required    — whether the user must be logged in

Classification order:
  1. Fast keyword scan  (sub-millisecond)
  2. AI classification fallback (uses ai_service.mentor_chat)
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


# ═════════════════════════════════════════════════════════════════════════════
# WORKFLOW TEMPLATE
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class WorkflowTemplate:
    category:         str
    title:            str
    platform:         str
    start_url:        str
    goals:            List[str]
    user_questions:   List[Dict]
    estimated_tokens: int  = 200
    needs_browser:    bool = True
    login_required:   bool = True
    icon:             str  = "🤖"


# ═════════════════════════════════════════════════════════════════════════════
# TEMPLATE LIBRARY
# ═════════════════════════════════════════════════════════════════════════════

WORKFLOW_TEMPLATES: Dict[str, WorkflowTemplate] = {

    # ── Freelance platforms ──────────────────────────────────────────────────
    "freelance_fiverr_setup": WorkflowTemplate(
        category="freelance", title="Set up Fiverr profile & publish gig",
        platform="Fiverr", start_url="https://www.fiverr.com", icon="🟢",
        goals=[
            "Navigate to Fiverr and check login status",
            "If not logged in, guide user through signup or login",
            "Complete seller profile: photo, bio, languages, skills",
            "Create first gig: title, category, description, packages",
            "Upload gig thumbnail and samples",
            "Publish gig and confirm it is live",
        ],
        user_questions=[
            {"key": "has_account",  "question": "Do you already have a Fiverr account?", "type": "yes_no"},
            {"key": "email",        "question": "Which email for Fiverr?",                "type": "text", "if": "has_account==no"},
            {"key": "service",      "question": "What service will you sell?",            "type": "text"},
            {"key": "price",        "question": "Starting price (USD)?",                  "type": "number"},
            {"key": "description",  "question": "Describe your experience briefly:",      "type": "textarea"},
        ],
        estimated_tokens=320,
    ),

    "freelance_upwork_setup": WorkflowTemplate(
        category="freelance", title="Set up Upwork profile & apply to jobs",
        platform="Upwork", start_url="https://www.upwork.com", icon="🔵",
        goals=[
            "Navigate to Upwork and check login status",
            "Complete freelancer profile: title, overview, hourly rate, skills, portfolio",
            "Verify profile is at least 80% complete",
            "Search for jobs matching {skill} with budget above {min_budget}",
            "Apply to the top 3 matching jobs with personalised proposals",
        ],
        user_questions=[
            {"key": "has_account",   "question": "Do you have an Upwork account?",            "type": "yes_no"},
            {"key": "skill",         "question": "Main skill to search for?",                  "type": "text"},
            {"key": "hourly_rate",   "question": "Desired hourly rate (USD)?",                 "type": "number"},
            {"key": "min_budget",    "question": "Minimum job budget to apply for (USD)?",     "type": "number"},
            {"key": "portfolio_url", "question": "Portfolio URL (skip if none):",              "type": "text", "optional": True},
        ],
        estimated_tokens=400,
    ),

    "freelance_apply_jobs": WorkflowTemplate(
        category="freelance", title="Find and apply to freelance jobs",
        platform="Upwork / Freelancer", start_url="https://www.upwork.com/nx/find-work/", icon="📋",
        goals=[
            "Search for {skill} jobs on {platform} with budget above {budget_min}",
            "Filter by most recent and highest budget",
            "Read top 5 job postings and identify best matches",
            "Write a personalised proposal for the best match",
            "Submit the application",
        ],
        user_questions=[
            {"key": "platform",    "question": "Which platform: Upwork, Freelancer, or Fiverr?",
             "type": "choice", "options": ["Upwork", "Freelancer", "Fiverr"]},
            {"key": "skill",       "question": "What skill to search for?", "type": "text"},
            {"key": "budget_min",  "question": "Minimum budget you'll accept (USD):", "type": "number"},
        ],
        estimated_tokens=280,
    ),

    # ── Content creation ─────────────────────────────────────────────────────
    "content_youtube_setup": WorkflowTemplate(
        category="content", title="Set up YouTube channel for monetisation",
        platform="YouTube", start_url="https://www.youtube.com", icon="🎬",
        goals=[
            "Navigate to YouTube Studio and check login status",
            "Create or verify channel exists with name: {channel_name}",
            "Complete channel profile: description, tags, links, banner",
            "Enable monetisation settings if account is eligible",
            "Create a video description template optimised for SEO",
            "Schedule first upload reminder",
        ],
        user_questions=[
            {"key": "channel_name", "question": "What should your channel be called?", "type": "text"},
            {"key": "niche",        "question": "What topics will you cover?",          "type": "text"},
            {"key": "google_email", "question": "Google account email to use:",         "type": "text"},
        ],
        estimated_tokens=300,
    ),

    "content_tiktok_setup": WorkflowTemplate(
        category="content", title="Set up TikTok creator account",
        platform="TikTok", start_url="https://www.tiktok.com", icon="🎵",
        goals=[
            "Navigate to TikTok and check login status",
            "Switch to a Creator / Business account",
            "Optimise bio with keywords, location and link in bio",
            "Follow 10 accounts in the {niche} niche for algorithm seeding",
            "Research 5 trending sounds and hashtags for {niche}",
            "Draft first 3 video ideas with hooks",
        ],
        user_questions=[
            {"key": "niche",       "question": "What content niche are you targeting?",   "type": "text"},
            {"key": "has_account", "question": "Do you have a TikTok account already?",  "type": "yes_no"},
        ],
        estimated_tokens=250,
    ),

    # ── E-commerce ───────────────────────────────────────────────────────────
    "ecommerce_etsy_setup": WorkflowTemplate(
        category="ecommerce", title="Open and stock an Etsy shop",
        platform="Etsy", start_url="https://www.etsy.com/sell", icon="🛍️",
        goals=[
            "Navigate to Etsy seller hub and check login status",
            "Set shop name to {shop_name}, country and currency",
            "Create first 3 product listings with AI-written descriptions and pricing",
            "Configure shipping options for {country}",
            "Activate shop and confirm it is publicly visible",
        ],
        user_questions=[
            {"key": "shop_name", "question": "Etsy shop name?",                        "type": "text"},
            {"key": "product",   "question": "What will you sell?",                    "type": "text"},
            {"key": "price",     "question": "Starting price (USD)?",                  "type": "number"},
            {"key": "country",   "question": "Your country (for shipping setup):",     "type": "text"},
        ],
        estimated_tokens=350,
    ),

    "ecommerce_amazon_fba": WorkflowTemplate(
        category="ecommerce", title="Research products and list on Amazon",
        platform="Amazon Seller", start_url="https://sellercentral.amazon.com", icon="📦",
        goals=[
            "Log in to Amazon Seller Central",
            "Search Best Sellers in {category} and note top 10 products",
            "Analyse competition level and pricing range for each",
            "Identify the product with the best margin and low competition",
            "Draft an optimised product title, bullet points and description",
            "Create the listing draft ready for inventory upload",
        ],
        user_questions=[
            {"key": "category",    "question": "Which product category?",              "type": "text"},
            {"key": "budget",      "question": "Inventory budget (USD)?",              "type": "number"},
            {"key": "has_account", "question": "Do you have an Amazon Seller account?", "type": "yes_no"},
        ],
        estimated_tokens=400,
    ),

    "dropshipping_research": WorkflowTemplate(
        category="ecommerce", title="Find dropshipping products and set up store",
        platform="AliExpress / Shopify", start_url="https://www.aliexpress.com", icon="🚚",
        goals=[
            "Search AliExpress for trending products in {niche}",
            "Filter by 4+ star rating, 100+ orders, ePacket shipping",
            "Record top 5 products with costs, shipping times and supplier details",
            "Navigate to Shopify and start free trial store",
            "Import the best product and write an optimised store listing",
            "Set retail pricing at 3x cost",
        ],
        user_questions=[
            {"key": "niche",      "question": "What product niche?",                      "type": "text"},
            {"key": "budget",     "question": "Starting budget for store + ads (USD)?",   "type": "number"},
            {"key": "target_mkt", "question": "Target market country:",                   "type": "text"},
        ],
        estimated_tokens=380,
    ),

    # ── Job hunting ──────────────────────────────────────────────────────────
    "jobs_linkedin_apply": WorkflowTemplate(
        category="jobs", title="Apply to jobs on LinkedIn",
        platform="LinkedIn", start_url="https://www.linkedin.com/jobs/", icon="💼",
        goals=[
            "Navigate to LinkedIn and check login status",
            "Update profile headline and summary with {job_title} keywords",
            "Search for {job_title} jobs in {location}",
            "Filter by date posted: last 24 hours",
            "Apply via Easy Apply to the top 5 best-match positions",
            "Send connection requests to 3 hiring managers from the results",
        ],
        user_questions=[
            {"key": "job_title",  "question": "Job title you're looking for?",              "type": "text"},
            {"key": "location",   "question": "Location or 'Remote'?",                     "type": "text"},
            {"key": "experience", "question": "Years of experience in this field?",        "type": "number"},
        ],
        estimated_tokens=350,
    ),

    "jobs_remote_hunt": WorkflowTemplate(
        category="jobs", title="Find and apply to remote jobs",
        platform="We Work Remotely / Remote.co",
        start_url="https://weworkremotely.com", icon="🌍",
        goals=[
            "Search We Work Remotely for {skill} roles",
            "Also search remote.co and remoteok.com",
            "Compile the top 5 matching roles with salary ranges",
            "Draft tailored cover letters for each",
            "Submit applications on each platform",
        ],
        user_questions=[
            {"key": "skill",      "question": "Primary skill for remote work?",            "type": "text"},
            {"key": "salary_min", "question": "Minimum annual salary (USD)?",              "type": "number"},
        ],
        estimated_tokens=320,
    ),

    # ── Contacts / lead finding ───────────────────────────────────────────────
    "find_contacts": WorkflowTemplate(
        category="research", title="Find contacts, sellers or buyers",
        platform="Google / LinkedIn / Facebook",
        start_url="https://www.google.com", icon="📞",
        login_required=False,
        goals=[
            "Search Google for '{query}' with contact filters",
            "Search LinkedIn for {query} profiles and business pages",
            "Search Facebook groups for {query} sellers/buyers",
            "Compile up to 20 contacts with names, platforms and contact methods",
            "Score each contact by relevance",
        ],
        user_questions=[
            {"key": "query",    "question": "Who or what are you looking for?",            "type": "text"},
            {"key": "location", "question": "City, country or 'global'?",                 "type": "text"},
            {"key": "purpose",  "question": "Are you looking to buy, sell, or partner?",
             "type": "choice", "options": ["Buy", "Sell", "Partner", "Hire", "Other"]},
        ],
        estimated_tokens=220,
    ),

    # ── Trading / crypto ─────────────────────────────────────────────────────
    "trading_research": WorkflowTemplate(
        category="trading", title="Research trading opportunities",
        platform="Binance / Coinbase",
        start_url="https://www.binance.com", icon="📈",
        login_required=False,
        goals=[
            "Navigate to {platform} and view trending assets",
            "Check CoinMarketCap for top 24-hour gainers and losers",
            "Analyse the 7-day chart for the top 3 opportunities",
            "Check Fear & Greed index at alternative.me",
            "Summarise findings: entry price, target, stop loss for each",
        ],
        user_questions=[
            {"key": "platform",   "question": "Which exchange: Binance, Coinbase, or Kraken?",
             "type": "choice", "options": ["Binance", "Coinbase", "Kraken", "Other"]},
            {"key": "budget",     "question": "How much to invest (USD)?",                  "type": "number"},
            {"key": "risk",       "question": "Risk tolerance:",
             "type": "choice", "options": ["Low", "Medium", "High"]},
        ],
        estimated_tokens=350,
    ),

    # ── Social media growth ───────────────────────────────────────────────────
    "social_grow_account": WorkflowTemplate(
        category="social", title="Grow social account and find clients",
        platform="Instagram / Twitter / TikTok",
        start_url="https://www.instagram.com", icon="📱",
        goals=[
            "Navigate to {platform} and check login status",
            "Optimise profile bio with {niche} keywords and call to action",
            "Find top 20 accounts in {niche} and follow / engage",
            "Draft 7 days of content ideas with captions and hashtags",
            "Find 10 potential clients and draft DM outreach messages",
        ],
        user_questions=[
            {"key": "platform", "question": "Which platform?",
             "type": "choice", "options": ["Instagram", "Twitter", "TikTok", "LinkedIn"]},
            {"key": "niche",    "question": "Your niche or industry:",                     "type": "text"},
            {"key": "goal",     "question": "Goal: grow following or find clients?",
             "type": "choice", "options": ["Grow following", "Find clients", "Both"]},
        ],
        estimated_tokens=300,
    ),

    # ── Affiliate marketing ───────────────────────────────────────────────────
    "affiliate_setup": WorkflowTemplate(
        category="affiliate", title="Set up affiliate marketing income stream",
        platform="Amazon Associates / ClickBank",
        start_url="https://affiliate-program.amazon.com", icon="🔗",
        goals=[
            "Navigate to {platform} affiliate programme",
            "Check eligibility and begin registration if needed",
            "Search for top-converting products in {niche}",
            "Generate affiliate links for top 5 products",
            "Draft a promotional piece: blog post or social caption with links",
            "Save all links and content ready to publish",
        ],
        user_questions=[
            {"key": "niche",       "question": "What niche/topic to promote?",               "type": "text"},
            {"key": "platform",    "question": "Affiliate network?",
             "type": "choice", "options": ["Amazon Associates", "ClickBank", "ShareASale", "CJ Affiliate"]},
            {"key": "traffic_src", "question": "How will you drive traffic? (blog/social/email):", "type": "text"},
        ],
        estimated_tokens=280,
    ),

    # ── Business registration ────────────────────────────────────────────────
    "business_registration": WorkflowTemplate(
        category="business", title="Research and start business registration",
        platform="Government Registry",
        start_url="https://www.google.com", icon="🏢",
        login_required=False,
        goals=[
            "Search for '{biz_type} registration requirements in {country}'",
            "Navigate to the official government company registration portal",
            "Document required steps, fees and documents",
            "Start filling the online registration form with {biz_name}",
            "Save progress and list next physical steps",
        ],
        user_questions=[
            {"key": "country",   "question": "Which country?",                             "type": "text"},
            {"key": "biz_type",  "question": "Business type:",
             "type": "choice", "options": ["Sole Trader", "LLC", "Partnership", "Corporation"]},
            {"key": "biz_name",  "question": "Desired business name:",                     "type": "text"},
        ],
        estimated_tokens=250,
    ),

    # ── Tutoring ────────────────────────────────────────────────────────────
    "tutoring_setup": WorkflowTemplate(
        category="tutoring", title="List tutoring services on Preply / Tutor.com",
        platform="Preply", start_url="https://www.preply.com/en/become-a-tutor", icon="📚",
        goals=[
            "Navigate to Preply tutor application page",
            "Fill in subject: {subject}, level: {level}, rate: {rate}/hr",
            "Write an engaging tutor bio optimised for search",
            "Complete video introduction if prompted",
            "Submit application and confirm receipt",
        ],
        user_questions=[
            {"key": "subject",  "question": "What subject(s) will you tutor?",             "type": "text"},
            {"key": "level",    "question": "Student levels: primary / secondary / uni?",  "type": "text"},
            {"key": "rate",     "question": "Hourly rate (USD)?",                          "type": "number"},
            {"key": "language", "question": "Teaching language?",                          "type": "text"},
        ],
        estimated_tokens=280,
    ),

    # ── No-browser AI tasks ──────────────────────────────────────────────────
    "content_writing_service": WorkflowTemplate(
        category="content", title="Write and deliver content",
        platform="Direct delivery", start_url="", icon="✍️",
        needs_browser=False, login_required=False,
        goals=[
            "Research the topic thoroughly",
            "Write complete {content_type} of {word_count} words on: {topic}",
            "Format and review for quality",
            "Deliver to client",
        ],
        user_questions=[
            {"key": "content_type", "question": "Content type? (blog/article/copy/script)", "type": "text"},
            {"key": "topic",        "question": "Topic or title:",                          "type": "text"},
            {"key": "word_count",   "question": "Approximate word count:",                 "type": "number"},
            {"key": "audience",     "question": "Target audience:",                        "type": "text"},
        ],
        estimated_tokens=150,
    ),

    "coding_service": WorkflowTemplate(
        category="coding", title="Build and deliver a coding project",
        platform="GitHub / Direct", start_url="https://github.com", icon="💻",
        needs_browser=False,
        goals=[
            "Clarify all project requirements",
            "Design architecture for {project_type}",
            "Implement core features using {tech_stack}",
            "Write tests and documentation",
            "Package and deliver before {deadline}",
        ],
        user_questions=[
            {"key": "project_type", "question": "What to build? (website/API/bot/app/script)", "type": "text"},
            {"key": "tech_stack",   "question": "Preferred stack or language:",               "type": "text"},
            {"key": "deadline",     "question": "Client deadline:",                           "type": "text"},
        ],
        estimated_tokens=200,
        needs_browser=False,
    ),
}


# ═════════════════════════════════════════════════════════════════════════════
# KEYWORD → TEMPLATE MAP  (fast O(1) lookup)
# ═════════════════════════════════════════════════════════════════════════════

KEYWORD_MAP: Dict[str, str] = {
    # Fiverr
    "fiverr":                      "freelance_fiverr_setup",
    # Upwork
    "upwork":                      "freelance_upwork_setup",
    "apply to jobs":               "freelance_apply_jobs",
    "apply for jobs":              "freelance_apply_jobs",
    "job application":             "freelance_apply_jobs",
    "freelancer.com":              "freelance_apply_jobs",
    # YouTube
    "youtube":                     "content_youtube_setup",
    "yt channel":                  "content_youtube_setup",
    "youtube channel":             "content_youtube_setup",
    # TikTok
    "tiktok":                      "content_tiktok_setup",
    "tik tok":                     "content_tiktok_setup",
    # Etsy
    "etsy":                        "ecommerce_etsy_setup",
    # Amazon
    "amazon":                      "ecommerce_amazon_fba",
    " fba":                        "ecommerce_amazon_fba",
    # Dropshipping
    "dropship":                    "dropshipping_research",
    "aliexpress":                  "dropshipping_research",
    "shopify":                     "dropshipping_research",
    # LinkedIn jobs
    "linkedin":                    "jobs_linkedin_apply",
    # Remote jobs
    "remote job":                  "jobs_remote_hunt",
    "work remotely":               "jobs_remote_hunt",
    "remote work":                 "jobs_remote_hunt",
    # Contacts
    "find contact":                "find_contacts",
    "find seller":                 "find_contacts",
    "find buyer":                  "find_contacts",
    "phone number of":             "find_contacts",
    "contact of":                  "find_contacts",
    "who sells":                   "find_contacts",
    "vendors in":                  "find_contacts",
    "suppliers in":                "find_contacts",
    # Trading
    "crypto":                      "trading_research",
    "binance":                     "trading_research",
    "coinbase":                    "trading_research",
    "trading opportunity":         "trading_research",
    "buy bitcoin":                 "trading_research",
    "invest in crypto":            "trading_research",
    # Social
    "instagram":                   "social_grow_account",
    "grow my instagram":           "social_grow_account",
    "grow my twitter":             "social_grow_account",
    "grow my account":             "social_grow_account",
    # Affiliate
    "affiliate":                   "affiliate_setup",
    "clickbank":                   "affiliate_setup",
    # Business registration
    "register my business":        "business_registration",
    "register a company":          "business_registration",
    "incorporate":                 "business_registration",
    # Tutoring
    "tutor":                       "tutoring_setup",
    "preply":                      "tutoring_setup",
    "teach students":              "tutoring_setup",
    # Content writing
    "write a blog":                "content_writing_service",
    "write an article":            "content_writing_service",
    "write content":               "content_writing_service",
    "copywriting":                 "content_writing_service",
    # Coding
    "build a website":             "coding_service",
    "build an app":                "coding_service",
    "build a bot":                 "coding_service",
    "write a script":              "coding_service",
    "build an api":                "coding_service",
}


# ═════════════════════════════════════════════════════════════════════════════
# CLASSIFICATION
# ═════════════════════════════════════════════════════════════════════════════

async def classify_task(task: str, ai_service_ref=None) -> Optional[str]:
    """
    Return the best-matching template key for a task string.
    Returns None if no match found.
    """
    task_lower = task.lower()

    # ── Pass 1: exact keyword scan ────────────────────────────────────────
    for kw, key in KEYWORD_MAP.items():
        if kw in task_lower:
            return key

    # ── Pass 2: AI classification ─────────────────────────────────────────
    if ai_service_ref is None:
        return None
    try:
        keys_list = list(WORKFLOW_TEMPLATES.keys())
        prompt = (
            f'Classify this task into the best matching template key.\n\n'
            f'Available keys:\n{json.dumps(keys_list)}\n\n'
            f'Task: "{task}"\n\n'
            f'Return ONLY the single best key or "none" if nothing matches.'
        )
        result = await ai_service_ref.mentor_chat(
            messages=[{"role": "user", "content": prompt}],
            system_prompt="Classify tasks. Return ONLY a key string from the list or the word none.",
            max_tokens=20,
        )
        key = result.get("content", "").strip().strip('"').lower()
        if key in WORKFLOW_TEMPLATES:
            return key
    except Exception as e:
        logger.error("classify_task AI fallback error: %s", e)

    return None


def get_template(key: str) -> Optional[WorkflowTemplate]:
    return WORKFLOW_TEMPLATES.get(key)


def get_template_for_platform(platform: str) -> Optional[WorkflowTemplate]:
    p = platform.lower()
    for key, tpl in WORKFLOW_TEMPLATES.items():
        if p in tpl.platform.lower() or p in key:
            return tpl
    return None
