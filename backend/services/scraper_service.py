"""
RiseUp Scraper Service — Multi-Source Opportunity Engine
─────────────────────────────────────────────────────────────────────
Extracted and adapted from GrowthAI backend + merged with APEX web search.

Sources:
  Jobs     → Indeed, LinkedIn, RemoteOK
  Freelance→ Upwork (via search), People Per Hour
  Hustles  → Reddit (beermoney, sidehustle, WorkOnline, forhire),
              HackerNews "Who is Hiring", Craigslist gigs,
              Curated side-hustle database (20+ proven hustles)
  All results → AI scored for match against user profile
"""

import asyncio
import hashlib
import json
import logging
import random
import re
from dataclasses import dataclass, asdict, field
from datetime import datetime
from typing import List, Optional, Dict, Any

import httpx
from bs4 import BeautifulSoup

from config import settings
from services.ai_service import ai_service

logger = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
    "DNT": "1",
}
TIMEOUT  = 15
MAX_RETRIES = 2


# ═══════════════════════════════════════════════════════════════════
# DATA MODEL
# ═══════════════════════════════════════════════════════════════════

@dataclass
class ScrapedOpportunity:
    id:            str
    title:         str
    description:   str
    opp_type:      str      # job | freelance | gig | hustle | side_hustle | passive_income
    source:        str
    source_url:    str
    company_name:  Optional[str]  = None
    location:      str            = "Remote"
    is_remote:     bool           = True
    pay_amount:    Optional[float] = None
    pay_period:    Optional[str]  = None   # hour | day | week | month | project
    required_skills: List[str]   = field(default_factory=list)
    posted_at:     Optional[str]  = None
    # AI-filled after scoring
    ai_match_score:  int          = 0
    ai_summary:      str          = ""
    ai_risk_level:   str          = "medium"
    ai_action_steps: List[str]   = field(default_factory=list)
    ai_time_to_earn: str          = ""


def _gen_id(url: str, title: str) -> str:
    return hashlib.md5(f"{url}{title}".encode()).hexdigest()[:16]


def _extract_pay(text: str):
    """Extract (amount, period) from salary text."""
    if not text:
        return None, None
    text = text.replace(",", "")
    m = re.search(r"\$?([\d]+(?:\.\d+)?)[kK]?\s*[-–]\s*\$?([\d]+(?:\.\d+)?)[kK]?", text)
    if m:
        lo = float(m.group(1)) * (1000 if 'k' in text.lower() else 1)
        hi = float(m.group(2)) * (1000 if 'k' in text.lower() else 1)
        avg = (lo + hi) / 2
        period = "year" if "year" in text.lower() or "yr" in text.lower() else (
                 "hour" if "hour" in text.lower() or "/hr" in text.lower() else "month")
        return avg, period
    m2 = re.search(r"\$?([\d]+(?:\.\d+)?)[kK]?", text)
    if m2:
        val = float(m2.group(1)) * (1000 if 'k' in text.lower() else 1)
        period = "year" if "year" in text.lower() else (
                 "hour" if "hour" in text.lower() or "/hr" in text.lower() else "month")
        return val, period
    return None, None


async def _fetch(url: str, *, timeout: int = TIMEOUT) -> Optional[str]:
    for attempt in range(MAX_RETRIES):
        try:
            await asyncio.sleep(random.uniform(0.5, 1.5))
            async with httpx.AsyncClient(
                headers=HEADERS, timeout=timeout,
                follow_redirects=True
            ) as client:
                r = await client.get(url)
                if r.status_code == 200:
                    return r.text
                if r.status_code == 429:
                    await asyncio.sleep(2 ** attempt)
        except Exception as e:
            logger.debug(f"Fetch error {url}: {e}")
    return None


# ═══════════════════════════════════════════════════════════════════
# JOB SCRAPERS
# ═══════════════════════════════════════════════════════════════════

async def scrape_remoteok(query: str = "", max_results: int = 20) -> List[ScrapedOpportunity]:
    """RemoteOK has a clean JSON API."""
    opps = []
    try:
        url = "https://remoteok.com/api"
        async with httpx.AsyncClient(headers={**HEADERS, "Accept": "application/json"},
                                      timeout=TIMEOUT) as client:
            r = await client.get(url)
            jobs = r.json()

        for job in jobs[1:]:  # first item is metadata
            if not isinstance(job, dict):
                continue
            title = job.get("position", "")
            if query and query.lower() not in (title + job.get("tags", "")).lower():
                continue
            skills = []
            raw_tags = job.get("tags")
            if isinstance(raw_tags, list):
                skills = raw_tags[:6]
            elif isinstance(raw_tags, str):
                skills = [t.strip() for t in raw_tags.split(",") if t.strip()][:6]

            opps.append(ScrapedOpportunity(
                id=_gen_id(job.get("url", ""), title),
                title=title,
                description=job.get("description", "")[:400],
                opp_type="job",
                source="remoteok",
                source_url=job.get("url", "https://remoteok.com"),
                company_name=job.get("company"),
                location="Remote",
                is_remote=True,
                pay_amount=job.get("salary_min"),
                pay_period="year",
                required_skills=skills,
                posted_at=job.get("date"),
            ))
            if len(opps) >= max_results:
                break
    except Exception as e:
        logger.warning(f"RemoteOK error: {e}")
    return opps


async def scrape_hackernews_hiring(max_results: int = 30) -> List[ScrapedOpportunity]:
    """Scrape HackerNews 'Who is Hiring' thread via the Algolia API."""
    opps = []
    try:
        url = "https://hn.algolia.com/api/v1/search_by_date?query=who+is+hiring&tags=story&hitsPerPage=1"
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            r  = await client.get(url)
            data = r.json()
            hits = data.get("hits", [])
            if not hits:
                return opps
            thread_id = hits[0]["objectID"]

            # Fetch top-level comments
            comments_url = f"https://hn.algolia.com/api/v1/search?tags=comment,story_{thread_id}&hitsPerPage={max_results}"
            r2 = await client.get(comments_url)
            comments = r2.json().get("hits", [])

        for c in comments:
            text = c.get("comment_text", "")
            if not text or len(text) < 30:
                continue
            soup  = BeautifulSoup(text, "html.parser")
            plain = soup.get_text(" ")
            lines = [l.strip() for l in plain.splitlines() if l.strip()]
            title = lines[0][:80] if lines else "HN Job"
            is_remote = "remote" in plain.lower()
            opps.append(ScrapedOpportunity(
                id=_gen_id(c.get("url", ""), title),
                title=title,
                description=plain[:400],
                opp_type="job",
                source="hackernews",
                source_url=c.get("url") or f"https://news.ycombinator.com/item?id={thread_id}",
                location="Remote" if is_remote else "Various",
                is_remote=is_remote,
            ))
    except Exception as e:
        logger.warning(f"HackerNews error: {e}")
    return opps


# ═══════════════════════════════════════════════════════════════════
# REDDIT SCRAPER (no auth — public JSON)
# ═══════════════════════════════════════════════════════════════════

_HUSTLE_SUBS = [
    "beermoney", "sidehustle", "WorkOnline",
    "forhire", "freelance", "PassiveIncome",
    "slavelabour", "Entrepreneur",
]

_SUB_TYPE_MAP = {
    "beermoney": "hustle",        "sidehustle": "side_hustle",
    "workonline": "job",          "forhire": "freelance",
    "freelance": "freelance",     "slavelabour": "gig",
    "passiveincome": "passive_income",
}


async def scrape_reddit_hustles(max_results: int = 30) -> List[ScrapedOpportunity]:
    opps, seen = [], set()
    per_sub = max(3, max_results // len(_HUSTLE_SUBS))

    for sub in _HUSTLE_SUBS:
        try:
            url = f"https://www.reddit.com/r/{sub}/hot.json?limit={per_sub}"
            html = await _fetch(url)
            if not html:
                continue
            data  = json.loads(html)
            posts = data.get("data", {}).get("children", [])

            for p in posts:
                d = p.get("data", {})
                title = d.get("title", "")
                desc  = d.get("selftext", "")[:400]
                url_  = f"https://reddit.com{d.get('permalink', '')}"
                if url_ in seen or d.get("score", 0) < 5:
                    continue
                seen.add(url_)
                opp_type = _SUB_TYPE_MAP.get(sub.lower(), "side_hustle")
                opps.append(ScrapedOpportunity(
                    id=_gen_id(url_, title),
                    title=title,
                    description=desc,
                    opp_type=opp_type,
                    source=f"reddit_{sub}",
                    source_url=url_,
                    location="Remote",
                    is_remote=True,
                ))
        except Exception as e:
            logger.debug(f"Reddit {sub} error: {e}")

    return opps[:max_results]


# ═══════════════════════════════════════════════════════════════════
# CURATED SIDE HUSTLE DATABASE
# ═══════════════════════════════════════════════════════════════════

_CURATED_HUSTLES = [
    {"title": "Freelance Writer",            "desc": "Write articles, blog posts, content for websites.", "platforms": "Upwork, Fiverr, Textbroker",        "earnings": 1200, "type": "freelance"},
    {"title": "Virtual Assistant",           "desc": "Remote admin support for businesses & entrepreneurs.", "platforms": "Belay, Time Etc, Fancy Hands",    "earnings": 2000, "type": "job"},
    {"title": "Social Media Manager",        "desc": "Manage social accounts for small businesses.",       "platforms": "Upwork, Fiverr, LinkedIn",            "earnings": 1500, "type": "freelance"},
    {"title": "Graphic Designer",            "desc": "Create logos, graphics, and marketing materials.",   "platforms": "99designs, Fiverr, Upwork, Dribbble", "earnings": 2000, "type": "freelance"},
    {"title": "Video Editor",                "desc": "Edit videos for YouTubers, businesses, creators.",   "platforms": "Upwork, Fiverr, VideoPixie",           "earnings": 2200, "type": "freelance"},
    {"title": "Online Tutor",                "desc": "Teach students in various subjects online.",         "platforms": "VIPKid, Chegg, TutorMe, Wyzant",       "earnings": 1500, "type": "job"},
    {"title": "Transcriptionist",            "desc": "Convert audio/video to text. Good typing required.", "platforms": "Rev, TranscribeMe, GoTranscript",      "earnings": 500,  "type": "gig"},
    {"title": "Proofreader / Editor",        "desc": "Review documents for grammar and clarity.",          "platforms": "Scribendi, Upwork",                    "earnings": 1000, "type": "freelance"},
    {"title": "Voice Over Artist",           "desc": "Record voiceovers for videos and commercials.",      "platforms": "Voices.com, Voice123, Fiverr",         "earnings": 1500, "type": "freelance"},
    {"title": "Web Developer",               "desc": "Build and maintain websites for clients.",           "platforms": "Upwork, Toptal, Freelancer",           "earnings": 4000, "type": "freelance"},
    {"title": "SEO Specialist",              "desc": "Improve website rankings on Google.",                "platforms": "Upwork, LinkedIn, local businesses",   "earnings": 2500, "type": "freelance"},
    {"title": "Online Reseller",             "desc": "Buy items cheap, resell for profit online.",        "platforms": "eBay, Poshmark, Mercari, FB Marketplace","earnings": 600, "type": "hustle"},
    {"title": "Delivery Driver",             "desc": "Deliver food, groceries, or packages.",             "platforms": "DoorDash, Uber Eats, Instacart",        "earnings": 800,  "type": "gig"},
    {"title": "Pet Sitter / Dog Walker",     "desc": "Care for pets while owners are away.",              "platforms": "Rover, Wag, Care.com",                  "earnings": 600,  "type": "gig"},
    {"title": "Data Entry Specialist",       "desc": "Enter data into spreadsheets and databases.",       "platforms": "Clickworker, Amazon MTurk",              "earnings": 300,  "type": "gig"},
    {"title": "Bookkeeper",                  "desc": "Manage financial records for small businesses.",    "platforms": "Bench, Bookminders, Upwork",             "earnings": 2500, "type": "job"},
    {"title": "Resume Writer",               "desc": "Help job seekers improve resumes and LinkedIn.",    "platforms": "Talent Inc, Upwork",                    "earnings": 1000, "type": "freelance"},
    {"title": "Website Tester",              "desc": "Test websites and apps for usability issues.",      "platforms": "UserTesting, TryMyUI, UserFeel",         "earnings": 200,  "type": "hustle"},
    {"title": "Micro Task Worker",           "desc": "Complete small tasks: image tagging, verification.","platforms": "Amazon MTurk, Clickworker, Appen",      "earnings": 200,  "type": "gig"},
    {"title": "Customer Support Rep",        "desc": "Handle customer inquiries via chat or email.",      "platforms": "Amazon, Apple, Concentrix",              "earnings": 2000, "type": "job"},
    {"title": "Dropshipping Store Owner",    "desc": "Sell products online without holding inventory.",   "platforms": "Shopify, WooCommerce, AliExpress",       "earnings": 1500, "type": "hustle"},
    {"title": "Affiliate Marketer",          "desc": "Earn commissions promoting other people's products.","platforms": "Amazon Associates, ShareASale, CJ",    "earnings": 1000, "type": "passive_income"},
    {"title": "YouTube Content Creator",     "desc": "Build a channel and monetize through ads/sponsors.","platforms": "YouTube, Patreon, Sponsorships",        "earnings": 2000, "type": "side_hustle"},
    {"title": "Newsletter Writer",           "desc": "Build an email list and monetize with sponsors.",   "platforms": "Substack, ConvertKit, Beehiiv",          "earnings": 1000, "type": "side_hustle"},
    {"title": "Print-on-Demand Designer",    "desc": "Design merch — platform handles printing/shipping.","platforms": "Redbubble, Merch by Amazon, Printful",  "earnings": 500,  "type": "passive_income"},
]


def get_curated_hustles(max_results: int = 25) -> List[ScrapedOpportunity]:
    opps = []
    for h in _CURATED_HUSTLES[:max_results]:
        opps.append(ScrapedOpportunity(
            id=_gen_id(h["title"], h["title"]),
            title=h["title"],
            description=f"{h['desc']} Platforms: {h['platforms']}.",
            opp_type=h["type"],
            source="curated_database",
            source_url=f"https://www.google.com/search?q={h['title'].replace(' ', '+')}+how+to+start",
            location="Remote",
            is_remote=True,
            pay_amount=h["earnings"],
            pay_period="month",
        ))
    return opps


# ═══════════════════════════════════════════════════════════════════
# AI SCORING
# ═══════════════════════════════════════════════════════════════════

async def ai_score_opportunity(opp: ScrapedOpportunity, profile: dict) -> ScrapedOpportunity:
    """Score a single opportunity against user profile using AI."""
    try:
        system = """You are an opportunity analyst. Score this opportunity for the user.
Return ONLY valid JSON:
{
  "match_score": 0-100,
  "summary": "2-sentence personalised summary",
  "risk_level": "low|medium|high",
  "action_steps": ["Step 1", "Step 2", "Step 3"],
  "time_to_first_earning": "e.g. 1-2 weeks"
}"""
        msg = (
            f"Opportunity: {opp.title} — {opp.description[:200]}\n"
            f"Type: {opp.opp_type} | Source: {opp.source} | Pay: {opp.pay_amount} {opp.pay_period}\n\n"
            f"User profile: skills={profile.get('current_skills', [])}, "
            f"stage={profile.get('stage','survival')}, "
            f"country={profile.get('country','NG')}, "
            f"currency={profile.get('currency','USD')}\n\n"
            "Score this opportunity for this user."
        )
        result = await ai_service.chat(
            messages=[{"role": "user", "content": msg}],
            system=system,
            max_tokens=400,
        )
        raw = result["content"].strip().lstrip("```json").lstrip("```").rstrip("```").strip()
        data = json.loads(raw)
        opp.ai_match_score  = int(data.get("match_score", 50))
        opp.ai_summary      = data.get("summary", "")
        opp.ai_risk_level   = data.get("risk_level", "medium")
        opp.ai_action_steps = data.get("action_steps", [])
        opp.ai_time_to_earn = data.get("time_to_first_earning", "")
    except Exception as e:
        logger.debug(f"AI scoring error: {e}")
        opp.ai_match_score = 50
    return opp


# ═══════════════════════════════════════════════════════════════════
# MAIN ENGINE
# ═══════════════════════════════════════════════════════════════════

class ScraperEngine:
    """Orchestrates all scrapers + AI scoring."""

    async def find_opportunities(
        self,
        profile: dict,
        opp_types: List[str] = None,
        query: str = "",
        max_results: int = 30,
        score_with_ai: bool = True,
    ) -> List[Dict]:
        if not opp_types:
            opp_types = ["jobs", "hustles", "freelance"]

        tasks = []
        if "jobs" in opp_types:
            tasks.append(scrape_remoteok(query, max_results=15))
            tasks.append(scrape_hackernews_hiring(max_results=10))
        if "hustles" in opp_types or "freelance" in opp_types:
            tasks.append(scrape_reddit_hustles(max_results=20))

        batches = await asyncio.gather(*tasks, return_exceptions=True)
        all_opps: List[ScrapedOpportunity] = []
        for batch in batches:
            if isinstance(batch, list):
                all_opps.extend(batch)

        # Always add curated hustles as a baseline
        all_opps.extend(get_curated_hustles(15))

        # Deduplicate
        seen, unique = set(), []
        for o in all_opps:
            if o.id not in seen:
                seen.add(o.id)
                unique.append(o)

        # AI score top candidates
        if score_with_ai and unique:
            score_tasks = [ai_score_opportunity(o, profile) for o in unique[:20]]
            scored = await asyncio.gather(*score_tasks, return_exceptions=True)
            scored_opps = [o for o in scored if isinstance(o, ScrapedOpportunity)]
            # Merge scored back
            scored_ids = {o.id for o in scored_opps}
            final = scored_opps + [o for o in unique if o.id not in scored_ids]
        else:
            final = unique

        # Sort by match score
        final.sort(key=lambda o: o.ai_match_score, reverse=True)

        return [asdict(o) for o in final[:max_results]]

    async def get_trending(self, category: str = None, limit: int = 20) -> List[Dict]:
        """Return curated + live trending opportunities without heavy scraping."""
        opps = get_curated_hustles(limit)
        try:
            remote_jobs = await scrape_remoteok(max_results=10)
            if category in (None, "jobs"):
                opps = remote_jobs + opps
        except Exception:
            pass
        opps.sort(key=lambda o: o.pay_amount or 0, reverse=True)
        return [asdict(o) for o in opps[:limit]]

    async def scan_all(self) -> Dict:
        """Background scan across all sources."""
        jobs    = await scrape_remoteok(max_results=50)
        hn      = await scrape_hackernews_hiring(max_results=30)
        reddit  = await scrape_reddit_hustles(max_results=40)
        curated = get_curated_hustles(25)
        total   = len(jobs) + len(hn) + len(reddit) + len(curated)
        logger.info(f"Scan complete: {total} opportunities collected")
        return {
            "jobs":    len(jobs) + len(hn),
            "hustles": len(reddit) + len(curated),
            "total":   total,
        }


scraper_engine = ScraperEngine()
