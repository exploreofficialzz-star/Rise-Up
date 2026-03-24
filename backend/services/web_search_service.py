"""
RiseUp Web Search Service
─────────────────────────────────────────────────────────────────────
Gives the agent real-time access to the internet.

Primary:  Serper API  (Google results — serper.dev, ~$50/mo for 100k)
Fallback: Tavily AI   (tavily.com — built for AI agents, has free tier)
Last:     DuckDuckGo  (no key, free forever, weaker results)

Usage:
    results = await web_search_service.search("freelance writing jobs Nigeria 2025")
    results = await web_search_service.deep_search("how to start dropshipping Nigeria 2025", pages=3)
    page    = await web_search_service.fetch_page("https://upwork.com/...")
"""

import logging
import httpx
import json
from typing import List, Optional, Dict, Any

from config import settings

logger = logging.getLogger(__name__)

TIMEOUT  = 12
HEADERS  = {"User-Agent": "RiseUp-Agent/3.0 (AI Wealth Platform)"}


class WebSearchService:

    # ── Primary: Serper (Google) ──────────────────────────────────

    async def _serper_search(self, query: str, num: int = 8) -> List[Dict]:
        if not getattr(settings, "SERPER_API_KEY", None):
            return []
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                r = await client.post(
                    "https://google.serper.dev/search",
                    headers={"X-API-KEY": settings.SERPER_API_KEY, "Content-Type": "application/json"},
                    json={"q": query, "num": num, "gl": "us", "hl": "en"},
                )
                r.raise_for_status()
                data = r.json()
                results = []
                for item in data.get("organic", []):
                    results.append({
                        "title":   item.get("title", ""),
                        "url":     item.get("link", ""),
                        "snippet": item.get("snippet", ""),
                        "source":  "serper",
                    })
                # Also grab answer box / knowledge panel if present
                if data.get("answerBox"):
                    ab = data["answerBox"]
                    results.insert(0, {
                        "title":   ab.get("title", "Answer"),
                        "url":     ab.get("link", ""),
                        "snippet": ab.get("answer") or ab.get("snippet", ""),
                        "source":  "serper_answer_box",
                    })
                return results
        except Exception as e:
            logger.warning(f"Serper search failed: {e}")
            return []

    # ── Secondary: Tavily AI ──────────────────────────────────────

    async def _tavily_search(self, query: str, num: int = 8) -> List[Dict]:
        if not getattr(settings, "TAVILY_API_KEY", None):
            return []
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                r = await client.post(
                    "https://api.tavily.com/search",
                    json={
                        "api_key":        settings.TAVILY_API_KEY,
                        "query":          query,
                        "max_results":    num,
                        "search_depth":   "advanced",
                        "include_answer": True,
                    },
                )
                r.raise_for_status()
                data = r.json()
                results = []
                if data.get("answer"):
                    results.append({
                        "title":   "AI Answer",
                        "url":     "",
                        "snippet": data["answer"],
                        "source":  "tavily_answer",
                    })
                for item in data.get("results", []):
                    results.append({
                        "title":   item.get("title", ""),
                        "url":     item.get("url", ""),
                        "snippet": item.get("content", "")[:400],
                        "source":  "tavily",
                    })
                return results
        except Exception as e:
            logger.warning(f"Tavily search failed: {e}")
            return []

    # ── Fallback: DuckDuckGo ──────────────────────────────────────

    async def _ddg_search(self, query: str, num: int = 8) -> List[Dict]:
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT, headers=HEADERS) as client:
                r = await client.get(
                    "https://api.duckduckgo.com/",
                    params={"q": query, "format": "json", "no_html": "1", "skip_disambig": "1"},
                )
                data = r.json()
                results = []
                if data.get("AbstractText"):
                    results.append({
                        "title":   data.get("Heading", "Summary"),
                        "url":     data.get("AbstractURL", ""),
                        "snippet": data["AbstractText"][:400],
                        "source":  "ddg_abstract",
                    })
                for item in (data.get("RelatedTopics") or [])[:num]:
                    if isinstance(item, dict) and item.get("Text"):
                        results.append({
                            "title":   item.get("Text", "")[:60],
                            "url":     item.get("FirstURL", ""),
                            "snippet": item.get("Text", "")[:400],
                            "source":  "ddg",
                        })
                return results
        except Exception as e:
            logger.warning(f"DuckDuckGo search failed: {e}")
            return []

    # ── Public: Search ────────────────────────────────────────────

    async def search(self, query: str, num: int = 8) -> List[Dict]:
        """Search the web. Tries Serper → Tavily → DuckDuckGo."""
        results = await self._serper_search(query, num)
        if not results:
            results = await self._tavily_search(query, num)
        if not results:
            results = await self._ddg_search(query, num)

        logger.info(f"Web search '{query}': {len(results)} results")
        return results

    # ── Public: Deep Multi-Page Research ─────────────────────────

    async def deep_research(self, topic: str, sub_queries: Optional[List[str]] = None) -> Dict:
        """
        Run multiple searches around a topic and return consolidated findings.
        Automatically generates sub-queries if none provided.
        """
        import asyncio

        if not sub_queries:
            sub_queries = [
                topic,
                f"{topic} step by step guide",
                f"{topic} free tools resources",
                f"{topic} income earning potential 2025",
                f"{topic} Nigeria Africa beginners",
            ]

        tasks   = [self.search(q, num=5) for q in sub_queries[:5]]
        batches = await asyncio.gather(*tasks, return_exceptions=True)

        all_results = []
        seen_urls   = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen_urls:
                        seen_urls.add(r["url"])
                        all_results.append(r)

        return {
            "topic":        topic,
            "total_results": len(all_results),
            "results":      all_results[:20],
            "queries_run":  sub_queries[:5],
        }

    # ── Public: Fetch Full Page ───────────────────────────────────

    async def fetch_page(self, url: str, max_chars: int = 3000) -> str:
        """Fetch and return clean text content from a URL."""
        try:
            async with httpx.AsyncClient(
                timeout=15,
                headers=HEADERS,
                follow_redirects=True,
            ) as client:
                r = await client.get(url)
                r.raise_for_status()
                # Very basic HTML stripping
                text = r.text
                import re
                text = re.sub(r"<style[^>]*>.*?</style>", " ", text, flags=re.DOTALL)
                text = re.sub(r"<script[^>]*>.*?</script>", " ", text, flags=re.DOTALL)
                text = re.sub(r"<[^>]+>", " ", text)
                text = re.sub(r"\s+", " ", text).strip()
                return text[:max_chars]
        except Exception as e:
            return f"Could not fetch page: {e}"

    # ── Public: Find Jobs ─────────────────────────────────────────

    async def find_freelance_jobs(self, skill: str, country: str = "remote") -> List[Dict]:
        """Search for real freelance job postings in a skill area."""
        queries = [
            f"site:upwork.com/jobs {skill} freelance 2025",
            f"site:freelancer.com/jobs {skill}",
            f"{skill} freelance jobs remote hiring now 2025",
            f"{skill} contract project hiring LinkedIn Indeed",
        ]
        import asyncio
        batches = await asyncio.gather(*[self.search(q, num=5) for q in queries])
        jobs    = []
        seen    = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen and r["snippet"]:
                        seen.add(r["url"])
                        jobs.append({
                            "title":    r["title"],
                            "url":      r["url"],
                            "snippet":  r["snippet"],
                            "platform": _detect_platform(r["url"]),
                        })
        return jobs[:15]

    # ── Public: Find Partners / Collaborators ─────────────────────

    async def find_partners(self, niche: str, country: str) -> List[Dict]:
        """Find potential business partners and collaborators in a niche."""
        queries = [
            f"{niche} collaboration partner {country} 2025",
            f"{niche} business partnership opportunity Africa Nigeria",
            f"{niche} influencer creator collab open",
            f"looking for partner {niche} startup",
        ]
        import asyncio
        batches = await asyncio.gather(*[self.search(q, num=4) for q in queries])
        partners = []
        seen     = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen:
                        seen.add(r["url"])
                        partners.append(r)
        return partners[:12]

    # ── Public: Find Free Business Resources ─────────────────────

    async def find_free_resources(self, business_type: str) -> List[Dict]:
        """Find free tools, grants, and resources for a specific business type."""
        queries = [
            f"free tools to start {business_type} business 2025",
            f"{business_type} free resources startup no capital",
            f"free grants funding {business_type} Nigeria Africa",
            f"{business_type} free online course certification",
        ]
        import asyncio
        batches = await asyncio.gather(*[self.search(q, num=4) for q in queries])
        results = []
        seen    = set()
        for batch in batches:
            if isinstance(batch, list):
                for r in batch:
                    if r["url"] not in seen:
                        seen.add(r["url"])
                        results.append(r)
        return results[:15]


def _detect_platform(url: str) -> str:
    platforms = {
        "upwork":       "Upwork",
        "freelancer":   "Freelancer.com",
        "fiverr":       "Fiverr",
        "toptal":       "Toptal",
        "linkedin":     "LinkedIn",
        "indeed":       "Indeed",
        "remote.co":    "Remote.co",
        "twitter":      "Twitter/X",
        "instagram":    "Instagram",
        "youtube":      "YouTube",
    }
    url_lower = url.lower()
    for key, name in platforms.items():
        if key in url_lower:
            return name
    return "Web"


web_search_service = WebSearchService()
