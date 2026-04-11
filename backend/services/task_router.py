"""
APEX Task Router — v1.0
═══════════════════════════════════════════════════════════
Maps any user task (from 10,000 income list) to a
structured WorkflowTemplate with:
  - platform URL (for browser orchestrator)
  - ordered goals (browser steps)
  - questions to ask user before starting
  - token cost estimate
  - category for routing

Intent classification: brain search first, then AI fallback.
"""

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


# ══════════════════════════════════════════════════════════════════
# WORKFLOW TEMPLATE
# ══════════════════════════════════════════════════════════════════

@dataclass
class WorkflowTemplate:
    category:          str
    title:             str
    platform:          str            # human-readable platform name
    start_url:         str            # where browser opens
    goals:             List[str]      # ordered browser automation goals
    user_questions:    List[Dict]     # questions to ask before starting
    estimated_tokens:  int = 200
    needs_browser:     bool = True
    login_required:    bool = True
    icon:              str = "🤖"


# ══════════════════════════════════════════════════════════════════
# TEMPLATE LIBRARY
# ══════════════════════════════════════════════════════════════════

WORKFLOW_TEMPLATES: Dict[str, WorkflowTemplate] = {

    # ── Freelancing ──────────────────────────────────────────────
    "freelance_fiverr_setup": WorkflowTemplate(
        category="freelance",
        title="Set up Fiverr profile & gigs",
        platform="Fiverr",
        start_url="https://www.fiverr.com",
        goals=[
            "Check if user is logged in or needs to sign up / log in",
            "Complete seller profile: photo, bio, skills, languages",
            "Create first gig: title, category, description, pricing",
            "Add gig images/portfolio if available",
            "Publish gig and verify it is live",
        ],
        user_questions=[
            {"key": "has_account",    "question": "Do you already have a Fiverr account?",                "type": "yes_no"},
            {"key": "email",          "question": "What email should I use for Fiverr?",                   "type": "text",    "if": "has_account==no"},
            {"key": "service",        "question": "What service do you want to sell on Fiverr?",           "type": "text"},
            {"key": "price",          "question": "What's your starting price (in USD)?",                  "type": "number"},
            {"key": "experience",     "question": "Briefly describe your experience with this service:",   "type": "textarea"},
        ],
        estimated_tokens=320,
        icon="🟢",
    ),

    "freelance_upwork_setup": WorkflowTemplate(
        category="freelance",
        title="Set up Upwork profile & apply to jobs",
        platform="Upwork",
        start_url="https://www.upwork.com",
        goals=[
            "Log in or create Upwork account",
            "Complete freelancer profile: title, overview, hourly rate, skills",
            "Add portfolio items",
            "Search for matching jobs using user's skills",
            "Apply to top 3 matching jobs with AI-written proposals",
        ],
        user_questions=[
            {"key": "has_account",  "question": "Do you have an Upwork account?",               "type": "yes_no"},
            {"key": "email",        "question": "Upwork account email:",                         "type": "text"},
            {"key": "skill",        "question": "What is your main skill for Upwork?",           "type": "text"},
            {"key": "hourly_rate",  "question": "What hourly rate do you want to charge (USD)?","type": "number"},
            {"key": "portfolio_url","question": "Any portfolio/work samples URL? (skip if none)","type": "text", "optional": True},
        ],
        estimated_tokens=400,
        icon="🔵",
    ),

    "freelance_apply_jobs": WorkflowTemplate(
        category="freelance",
        title="Apply to freelance jobs on chosen platform",
        platform="Upwork / Freelancer",
        start_url="https://www.upwork.com/nx/find-work/",
        goals=[
            "Search for jobs matching user's skills and rate",
            "Filter by budget and recency",
            "Read top 5 job descriptions",
            "Write personalised proposal for best match",
            "Submit application",
        ],
        user_questions=[
            {"key": "platform",   "question": "Which platform? Upwork, Freelancer, or Fiverr?", "type": "choice", "options": ["Upwork","Freelancer","Fiverr"]},
            {"key": "skill",      "question": "What skill should I search for?",                 "type": "text"},
            {"key": "budget_min", "question": "Minimum budget you'll accept (USD):",             "type": "number"},
        ],
        estimated_tokens=280,
        icon="📋",
    ),

    # ── Content Creation ─────────────────────────────────────────
    "content_youtube_setup": WorkflowTemplate(
        category="content",
        title="Set up YouTube channel for monetisation",
        platform="YouTube",
        start_url="https://www.youtube.com",
        goals=[
            "Log in to YouTube with user's Google account",
            "Create or verify channel exists",
            "Complete channel profile: name, description, tags, links",
            "Set up channel art using canva.com if needed",
            "Configure monetisation settings (enable if eligible)",
            "Create first video description and tags template",
        ],
        user_questions=[
            {"key": "channel_name",  "question": "What should your YouTube channel be called?",   "type": "text"},
            {"key": "niche",         "question": "What topics will you cover?",                    "type": "text"},
            {"key": "google_email",  "question": "Your Google email for YouTube:",                 "type": "text"},
        ],
        estimated_tokens=300,
        icon="🎬",
    ),

    "content_tiktok_setup": WorkflowTemplate(
        category="content",
        title="Set up TikTok creator profile",
        platform="TikTok",
        start_url="https://www.tiktok.com",
        goals=[
            "Log in or create TikTok account",
            "Switch to Creator account",
            "Optimise bio with keywords and link in bio",
            "Follow 10 accounts in user's niche for algorithm seeding",
            "Draft first 3 video ideas with trending sounds/hashtags",
        ],
        user_questions=[
            {"key": "niche",       "question": "What content niche are you targeting?",         "type": "text"},
            {"key": "has_account", "question": "Do you have a TikTok account already?",        "type": "yes_no"},
        ],
        estimated_tokens=250,
        icon="🎵",
    ),

    # ── E-commerce ───────────────────────────────────────────────
    "ecommerce_etsy_setup": WorkflowTemplate(
        category="ecommerce",
        title="Open and stock an Etsy shop",
        platform="Etsy",
        start_url="https://www.etsy.com/sell",
        goals=[
            "Create Etsy seller account or log in",
            "Set shop name, currency, and location",
            "Create first 3 product listings with AI-written descriptions",
            "Set pricing and shipping options",
            "Activate shop",
        ],
        user_questions=[
            {"key": "shop_name",   "question": "What do you want to name your Etsy shop?",      "type": "text"},
            {"key": "product",     "question": "What will you sell on Etsy?",                    "type": "text"},
            {"key": "price",       "question": "Starting price for your product (USD):",         "type": "number"},
            {"key": "country",     "question": "Your country for shipping setup:",               "type": "text"},
        ],
        estimated_tokens=350,
        icon="🛍️",
    ),

    "ecommerce_amazon_fba": WorkflowTemplate(
        category="ecommerce",
        title="Research products and list on Amazon",
        platform="Amazon Seller",
        start_url="https://sellercentral.amazon.com",
        goals=[
            "Log in to Amazon Seller Central",
            "Research top-selling products in user's chosen category",
            "Analyse competition and pricing",
            "Create product listing with AI-optimised title and bullets",
            "Set pricing strategy",
        ],
        user_questions=[
            {"key": "category",    "question": "Which product category interests you?",           "type": "text"},
            {"key": "budget",      "question": "Startup budget for inventory (USD):",             "type": "number"},
            {"key": "has_account", "question": "Do you have an Amazon Seller account?",          "type": "yes_no"},
        ],
        estimated_tokens=400,
        icon="📦",
    ),

    # ── Job Hunting ──────────────────────────────────────────────
    "jobs_linkedin_apply": WorkflowTemplate(
        category="jobs",
        title="Apply to jobs on LinkedIn",
        platform="LinkedIn",
        start_url="https://www.linkedin.com/jobs/",
        goals=[
            "Log in to LinkedIn",
            "Optimise LinkedIn profile headline and summary",
            "Search for jobs matching skills and location",
            "Apply to top 5 matches using Easy Apply",
            "Send connection requests to hiring managers",
        ],
        user_questions=[
            {"key": "job_title",   "question": "What job title are you looking for?",             "type": "text"},
            {"key": "location",    "question": "Job location or 'Remote':",                       "type": "text"},
            {"key": "experience",  "question": "Years of experience in this field:",              "type": "number"},
        ],
        estimated_tokens=350,
        icon="💼",
    ),

    "jobs_remote_hunt": WorkflowTemplate(
        category="jobs",
        title="Find and apply to remote jobs",
        platform="Remote.co / We Work Remotely",
        start_url="https://weworkremotely.com",
        goals=[
            "Search remote job boards for matching positions",
            "Shortlist top 5 opportunities",
            "Write tailored cover letters for each",
            "Submit applications",
        ],
        user_questions=[
            {"key": "skill",       "question": "Your primary skill for remote work:",             "type": "text"},
            {"key": "salary_min",  "question": "Minimum annual salary you'll accept (USD):",     "type": "number"},
        ],
        estimated_tokens=320,
        icon="🌍",
    ),

    # ── Tutoring ─────────────────────────────────────────────────
    "tutoring_setup": WorkflowTemplate(
        category="tutoring",
        title="List tutoring services on platforms",
        platform="Tutor.com / Preply",
        start_url="https://www.preply.com/en/become-a-tutor",
        goals=[
            "Create tutor profile on Preply",
            "Set subjects, availability, and hourly rate",
            "Write tutor bio optimised for search",
            "Complete verification steps",
            "Apply for first 3 student matches",
        ],
        user_questions=[
            {"key": "subject",     "question": "What subject(s) will you tutor?",                "type": "text"},
            {"key": "level",       "question": "Which student levels? (primary/secondary/uni)",  "type": "text"},
            {"key": "rate",        "question": "Hourly rate (USD):",                             "type": "number"},
            {"key": "language",    "question": "Teaching language:",                             "type": "text"},
        ],
        estimated_tokens=280,
        icon="📚",
    ),

    # ── Trading / Crypto ─────────────────────────────────────────
    "trading_research": WorkflowTemplate(
        category="trading",
        title="Research trading opportunities and set up account",
        platform="Binance / Coinbase",
        start_url="https://www.binance.com",
        goals=[
            "Navigate to chosen exchange",
            "Research top trending assets today",
            "Analyse price charts for user's budget range",
            "Set up account if needed (guide through KYC steps)",
            "Identify top 3 opportunities with entry/exit strategy",
        ],
        user_questions=[
            {"key": "platform",    "question": "Which exchange? Binance, Coinbase, or other?",  "type": "text"},
            {"key": "budget",      "question": "How much do you want to invest (USD)?",         "type": "number"},
            {"key": "risk",        "question": "Risk tolerance: Low / Medium / High?",          "type": "choice", "options": ["Low","Medium","High"]},
        ],
        estimated_tokens=350,
        icon="📈",
        login_required=False,
    ),

    # ── Social Media Management ──────────────────────────────────
    "social_grow_account": WorkflowTemplate(
        category="social",
        title="Grow social media account and attract clients",
        platform="Instagram / Twitter",
        start_url="https://www.instagram.com",
        goals=[
            "Log in to chosen platform",
            "Optimise profile for niche and discovery",
            "Create and schedule 7 days of content",
            "Follow and engage with 20 accounts in niche",
            "Find and DM 10 potential clients/collaborators",
        ],
        user_questions=[
            {"key": "platform",    "question": "Which platform? Instagram, Twitter, TikTok?",   "type": "choice", "options": ["Instagram","Twitter","TikTok","LinkedIn"]},
            {"key": "niche",       "question": "Your niche or industry:",                       "type": "text"},
            {"key": "goal",        "question": "Goal: grow following or find clients?",         "type": "choice", "options": ["Grow following","Find clients","Both"]},
        ],
        estimated_tokens=300,
        icon="📱",
    ),

    # ── Affiliate Marketing ──────────────────────────────────────
    "affiliate_setup": WorkflowTemplate(
        category="affiliate",
        title="Set up affiliate marketing income stream",
        platform="Amazon Associates / ClickBank",
        start_url="https://affiliate-program.amazon.com",
        goals=[
            "Sign up for affiliate programme",
            "Find high-converting products in user's niche",
            "Generate affiliate links",
            "Create promotional content (blog post or social content)",
            "Set up tracking dashboard",
        ],
        user_questions=[
            {"key": "niche",       "question": "What niche/topic will you promote?",            "type": "text"},
            {"key": "platform",    "question": "Affiliate network: Amazon, ClickBank, or ShareASale?", "type": "choice", "options": ["Amazon Associates","ClickBank","ShareASale","CJ Affiliate"]},
            {"key": "traffic_src", "question": "How will you drive traffic? (blog/social/email)","type": "text"},
        ],
        estimated_tokens=280,
        icon="🔗",
    ),

    # ── Business Registration ────────────────────────────────────
    "business_registration": WorkflowTemplate(
        category="business",
        title="Research and start business registration process",
        platform="Government / Company Registry",
        start_url="https://www.google.com",
        goals=[
            "Search for business registration requirements in user's country",
            "Find official government registration portal",
            "Navigate to registration page",
            "Document required steps and fees",
            "Fill in initial registration form if possible online",
        ],
        user_questions=[
            {"key": "country",     "question": "Which country are you registering in?",         "type": "text"},
            {"key": "biz_type",    "question": "Business type: Sole trader, LLC, or Partnership?","type": "choice", "options": ["Sole Trader","LLC","Partnership","Corporation"]},
            {"key": "biz_name",    "question": "Desired business name:",                        "type": "text"},
        ],
        estimated_tokens=250,
        icon="🏢",
        login_required=False,
    ),

    # ── Dropshipping ─────────────────────────────────────────────
    "dropshipping_research": WorkflowTemplate(
        category="ecommerce",
        title="Research dropshipping products and set up store",
        platform="AliExpress / Shopify",
        start_url="https://www.aliexpress.com",
        goals=[
            "Research trending products on AliExpress",
            "Analyse profit margins for top 5 products",
            "Find reliable suppliers with good ratings",
            "Draft product listings with AI copy",
            "Set up Shopify trial store with first products",
        ],
        user_questions=[
            {"key": "niche",       "question": "What product niche interests you?",             "type": "text"},
            {"key": "budget",      "question": "Starting budget for ads/store (USD):",          "type": "number"},
            {"key": "target_mkt",  "question": "Target market country:",                        "type": "text"},
        ],
        estimated_tokens=380,
        icon="🚚",
    ),

    # ── AI-only tasks (no browser needed) ───────────────────────
    "content_writing_service": WorkflowTemplate(
        category="content",
        title="Content writing service — write and deliver",
        platform="Email / Direct",
        start_url="",
        goals=[
            "Understand client requirements",
            "Research topic and outline",
            "Write complete article/content",
            "Format and deliver",
        ],
        user_questions=[
            {"key": "content_type","question": "What content to write? (blog/article/copy/script)","type": "text"},
            {"key": "topic",       "question": "Topic or title:",                                "type": "text"},
            {"key": "word_count",  "question": "Approximate word count:",                       "type": "number"},
            {"key": "audience",    "question": "Target audience:",                              "type": "text"},
        ],
        estimated_tokens=150,
        needs_browser=False,
        login_required=False,
        icon="✍️",
    ),

    # ── Coding Services ──────────────────────────────────────────
    "coding_service": WorkflowTemplate(
        category="coding",
        title="Build and deliver a coding project",
        platform="GitHub / Direct delivery",
        start_url="https://github.com",
        goals=[
            "Clarify project requirements",
            "Set up project structure",
            "Write code for core features",
            "Test and document",
            "Package and deliver to client",
        ],
        user_questions=[
            {"key": "project_type","question": "What needs to be built? (website/API/bot/script)","type": "text"},
            {"key": "tech_stack",  "question": "Preferred technology stack:",                   "type": "text"},
            {"key": "deadline",    "question": "Client deadline:",                              "type": "text"},
        ],
        estimated_tokens=200,
        needs_browser=False,
        icon="💻",
    ),
}


# ══════════════════════════════════════════════════════════════════
# INTENT CLASSIFIER
# ══════════════════════════════════════════════════════════════════

# Keyword → template key mapping for fast classification
KEYWORD_MAP: Dict[str, str] = {
    # Fiverr
    "fiverr":                "freelance_fiverr_setup",
    # Upwork
    "upwork":                "freelance_upwork_setup",
    "freelancer.com":        "freelance_apply_jobs",
    # Apply
    "apply":                 "freelance_apply_jobs",
    "job application":       "freelance_apply_jobs",
    # YouTube
    "youtube":               "content_youtube_setup",
    "yt channel":            "content_youtube_setup",
    # TikTok
    "tiktok":                "content_tiktok_setup",
    # Etsy
    "etsy":                  "ecommerce_etsy_setup",
    # Amazon
    "amazon":                "ecommerce_amazon_fba",
    "fba":                   "ecommerce_amazon_fba",
    # LinkedIn jobs
    "linkedin":              "jobs_linkedin_apply",
    # Remote jobs
    "remote job":            "jobs_remote_hunt",
    "work remotely":         "jobs_remote_hunt",
    # Tutoring
    "tutor":                 "tutoring_setup",
    "teach":                 "tutoring_setup",
    "preply":                "tutoring_setup",
    # Trading
    "trade":                 "trading_research",
    "crypto":                "trading_research",
    "binance":               "trading_research",
    "invest":                "trading_research",
    # Social
    "instagram":             "social_grow_account",
    "twitter":               "social_grow_account",
    "grow my account":       "social_grow_account",
    # Affiliate
    "affiliate":             "affiliate_setup",
    "clickbank":             "affiliate_setup",
    # Business registration
    "register":              "business_registration",
    "company":               "business_registration",
    "incorporate":           "business_registration",
    # Dropshipping
    "dropship":              "dropshipping_research",
    "aliexpress":            "dropshipping_research",
    # Content writing
    "write content":         "content_writing_service",
    "blog post":             "content_writing_service",
    "article":               "content_writing_service",
    "copywriting":           "content_writing_service",
    # Coding
    "build":                 "coding_service",
    "code":                  "coding_service",
    "website":               "coding_service",
    "app":                   "coding_service",
    "script":                "coding_service",
}


async def classify_task(task: str, ai_service_ref=None) -> Optional[str]:
    """
    Classify a task string to a template key.
    1. Try keyword matching first (fast)
    2. Fallback to AI classification
    """
    task_lower = task.lower()

    # ── Keyword pass ─────────────────────────────────────────────
    for kw, template_key in KEYWORD_MAP.items():
        if kw in task_lower:
            return template_key

    # ── AI fallback ──────────────────────────────────────────────
    if ai_service_ref:
        try:
            keys_list = list(WORKFLOW_TEMPLATES.keys())
            prompt = f"""Classify this task into one of these categories:
{json.dumps(keys_list, indent=2)}

Task: "{task}"

Return ONLY the single best matching key from the list, or "none" if no match."""
            result = await ai_service_ref.mentor_chat(
                messages=[{"role": "user", "content": prompt}],
                system_prompt="You classify tasks. Return only the key string.",
                max_tokens=30,
            )
            key = result.get("content", "").strip().strip('"').strip()
            if key in WORKFLOW_TEMPLATES:
                return key
        except Exception as e:
            logger.error(f"AI task classification error: {e}")

    return None


def get_template(key: str) -> Optional[WorkflowTemplate]:
    return WORKFLOW_TEMPLATES.get(key)


def get_template_for_platform(platform: str) -> Optional[WorkflowTemplate]:
    platform_lower = platform.lower()
    for key, tpl in WORKFLOW_TEMPLATES.items():
        if platform_lower in tpl.platform.lower() or platform_lower in key:
            return tpl
    return None
