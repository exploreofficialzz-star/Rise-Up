"""
backend/services/browser_orchestrator.py
APEX Browser Orchestrator — Production v1.0

Playwright headless browser driven by an AI decision loop.
Every action yields a BrowserEvent stored in `browser_events`
Supabase table and streamed to Flutter frontend via SSE.

Human-in-the-loop:
  CAPTCHA / 2FA detected → yields human_required event
  Frontend relays answer via POST /agent/browser/answer
  Execution resumes from where it paused

Install:  pip install playwright && playwright install chromium
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, AsyncGenerator, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

try:
    from playwright.async_api import (
        async_playwright,
        Browser,
        BrowserContext,
        Page,
    )
    _PW_AVAILABLE = True
except ImportError:
    _PW_AVAILABLE = False
    logger.warning(
        "Playwright not installed. "
        "Run: pip install playwright && playwright install chromium"
    )


# ═══════════════════════════════════════════════════════════════
# DATA CLASSES
# ═══════════════════════════════════════════════════════════════

class ActionType(str, Enum):
    NAVIGATE   = "navigate"
    CLICK      = "click"
    FILL       = "fill"
    SCROLL     = "scroll"
    WAIT       = "wait"
    PRESS_KEY  = "press_key"
    EXTRACT    = "extract"
    SELECT     = "select"
    DONE       = "done"


@dataclass
class BrowserAction:
    action:   ActionType
    selector: Optional[str] = None
    value:    Optional[str] = None
    url:      Optional[str] = None
    reason:   str           = ""


@dataclass
class BrowserEvent:
    type:           str
    data:           Dict[str, Any]
    screenshot_b64: Optional[str] = None


@dataclass
class _HumanReq:
    input_type:  str
    message:     str
    field_label: Optional[str] = None


# ═══════════════════════════════════════════════════════════════
# DETECTION PATTERNS
# ═══════════════════════════════════════════════════════════════

_CAPTCHA_SIGNALS = [
    "captcha", "recaptcha", "hcaptcha", "cf-challenge",
    "are you a robot", "verify you are human",
    "ddos-guard", "turnstile",
]
_TWO_FA_SIGNALS = [
    "verification code", "one-time", "otp", "2-step",
    "authenticator", "enter the code", "sent a code", "6-digit",
]


def _detect_human_required(text: str, html: str) -> Optional[_HumanReq]:
    combined = (text + html).lower()
    for sig in _CAPTCHA_SIGNALS:
        if sig in combined:
            return _HumanReq(
                input_type="captcha",
                message="A CAPTCHA appeared. Please solve it and tap Done.",
            )
    for sig in _TWO_FA_SIGNALS:
        if sig in combined:
            return _HumanReq(
                input_type="2fa",
                message="Two-factor authentication required. Enter the code sent to your device.",
                field_label="Verification code",
            )
    return None


# ═══════════════════════════════════════════════════════════════
# BROWSER SESSION
# ═══════════════════════════════════════════════════════════════

class BrowserSession:

    def __init__(self, session_id: str):
        self.session_id   = session_id
        self._pw          = None
        self._browser: Optional["Browser"]        = None
        self._context: Optional["BrowserContext"] = None
        self.page:     Optional["Page"]           = None
        self.is_alive     = False
        self.current_url  = ""
        self._human_event = asyncio.Event()
        self._human_answer: Optional[str] = None

    async def start(self):
        if not _PW_AVAILABLE:
            raise RuntimeError(
                "Playwright not installed. "
                "Run: pip install playwright && playwright install chromium"
            )
        self._pw      = await async_playwright().start()
        self._browser = await self._pw.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
            ],
        )
        self._context = await self._browser.new_context(
            viewport={"width": 1280, "height": 800},
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
        )
        await self._context.add_init_script(
            "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
        )
        self.page     = await self._context.new_page()
        self.is_alive = True

    async def stop(self):
        self.is_alive = False
        try:
            if self._browser:
                await self._browser.close()
            if self._pw:
                await self._pw.stop()
        except Exception:
            pass

    async def screenshot_b64(self) -> str:
        try:
            if not self.page:
                return ""
            raw = await self.page.screenshot(type="jpeg", quality=72, full_page=False)
            return base64.b64encode(raw).decode()
        except Exception as e:
            logger.error("screenshot error: %s", e)
            return ""

    async def page_text(self, max_chars: int = 6000) -> str:
        try:
            if not self.page:
                return ""
            text = await self.page.evaluate("() => document.body.innerText")
            return (text or "")[:max_chars]
        except Exception:
            return ""

    async def page_summary_json(self) -> str:
        try:
            if not self.page:
                return "{}"
            js = """() => {
                const inputs  = [...document.querySelectorAll('input,textarea,select')]
                    .slice(0,20)
                    .map(el => ({
                        tag: el.tagName, type: el.type||'',
                        name: el.name||'', id: el.id||'',
                        placeholder: el.placeholder||''
                    }));
                const buttons = [...document.querySelectorAll('button,a[href],input[type="submit"]')]
                    .slice(0,20)
                    .map(el => ({
                        tag: el.tagName,
                        text: (el.innerText||el.value||'').slice(0,50),
                        id: el.id||''
                    }));
                return JSON.stringify({
                    title: document.title,
                    url: location.href,
                    inputs, buttons,
                    headings: [...document.querySelectorAll('h1,h2')]
                        .slice(0,4).map(e=>e.innerText.slice(0,60))
                });
            }"""
            return await self.page.evaluate(js) or "{}"
        except Exception:
            return "{}"

    async def execute_action(self, action: BrowserAction) -> Dict[str, Any]:
        page = self.page
        if not page:
            return {"ok": False, "error": "No page"}
        try:
            if action.action == ActionType.NAVIGATE:
                await page.goto(action.url or "", wait_until="domcontentloaded", timeout=20_000)
                self.current_url = page.url
                return {"ok": True, "url": page.url}

            elif action.action == ActionType.CLICK:
                sel = action.selector or ""
                await page.wait_for_selector(sel, timeout=5_000)
                await page.click(sel, timeout=8_000)
                await asyncio.sleep(0.8)
                return {"ok": True}

            elif action.action == ActionType.FILL:
                sel = action.selector or ""
                await page.wait_for_selector(sel, timeout=5_000)
                await page.fill(sel, action.value or "", timeout=8_000)
                return {"ok": True}

            elif action.action == ActionType.SELECT:
                await page.select_option(action.selector or "", action.value or "", timeout=8_000)
                return {"ok": True}

            elif action.action == ActionType.PRESS_KEY:
                await page.keyboard.press(action.value or "Enter")
                await asyncio.sleep(0.6)
                return {"ok": True}

            elif action.action == ActionType.SCROLL:
                await page.evaluate("window.scrollBy(0, 600)")
                await asyncio.sleep(0.4)
                return {"ok": True}

            elif action.action == ActionType.WAIT:
                await asyncio.sleep(min(float(action.value or "2"), 5))
                return {"ok": True}

            elif action.action == ActionType.EXTRACT:
                sel  = action.selector
                data = await page.evaluate(
                    f"() => [...document.querySelectorAll('{sel}')].slice(0,30).map(e=>e.innerText.trim())"
                ) if sel else []
                return {"ok": True, "data": data}

            elif action.action == ActionType.DONE:
                return {"ok": True, "done": True}

            return {"ok": False, "error": f"Unknown: {action.action}"}

        except Exception as e:
            return {"ok": False, "error": str(e)[:200]}

    def provide_human_answer(self, answer: str):
        self._human_answer = answer
        self._human_event.set()

    async def wait_for_human(self, timeout_secs: float = 300.0) -> Optional[str]:
        self._human_event.clear()
        self._human_answer = None
        try:
            await asyncio.wait_for(self._human_event.wait(), timeout=timeout_secs)
            return self._human_answer
        except asyncio.TimeoutError:
            return None


# ═══════════════════════════════════════════════════════════════
# AI DECISION
# ═══════════════════════════════════════════════════════════════

async def _ai_next_action(
    *,
    task:          str,
    current_goal:  str,
    page_summary:  str,
    page_text:     str,
    history:       List[str],
    ai_service_ref,
) -> BrowserAction:
    history_str = "\n".join(history[-8:])
    prompt = f"""You control a real browser. Choose the SINGLE NEXT action.

TASK: {task}
CURRENT GOAL: {current_goal}

PAGE STATE:
{page_summary}

PAGE TEXT (2000 chars):
{page_text[:2000]}

HISTORY:
{history_str}

Return ONLY valid JSON:
{{
  "action":   "navigate|click|fill|select|scroll|wait|press_key|extract|done",
  "selector": "CSS selector or null",
  "value":    "text/key/option or null",
  "url":      "full URL if navigate else null",
  "reason":   "brief explanation"
}}

Rules:
- done = current goal achieved
- CAPTCHA/2FA seen → done with reason="human_required"
- Never repeat a failed action — try different selector or approach
- Prefer #id or [name=x] selectors
"""
    try:
        result = await ai_service_ref.mentor_chat(
            messages=[{"role": "user", "content": prompt}],
            system_prompt="Browser automation agent. Return ONLY valid JSON, no markdown.",
            max_tokens=200,
            temperature=0.1,
        )
        raw = result.get("content", "{}").strip()
        raw = re.sub(r"```[a-z]*\n?", "", raw).strip().rstrip("```").strip()
        data = json.loads(raw)
        try:
            action_type = ActionType(data.get("action", "wait"))
        except ValueError:
            action_type = ActionType.WAIT
        return BrowserAction(
            action   = action_type,
            selector = data.get("selector"),
            value    = data.get("value"),
            url      = data.get("url"),
            reason   = data.get("reason", ""),
        )
    except Exception as e:
        logger.error("AI browser decision error: %s", e)
        return BrowserAction(action=ActionType.WAIT, reason="AI error — waiting")


# ═══════════════════════════════════════════════════════════════
# ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════

class BrowserOrchestrator:

    _sessions: Dict[str, BrowserSession] = {}

    @classmethod
    def get_session(cls, session_id: str) -> Optional[BrowserSession]:
        return cls._sessions.get(session_id)

    @classmethod
    def provide_answer(cls, session_id: str, answer: str) -> bool:
        sess = cls._sessions.get(session_id)
        if sess:
            sess.provide_human_answer(answer)
            return True
        return False

    @classmethod
    async def run(
        cls,
        *,
        session_id:      str,
        task:            str,
        start_url:       str,
        goals:           List[str],
        ai_service_ref,
        token_deduct_fn: Callable,
        max_actions:     int = 45,
    ) -> AsyncGenerator[BrowserEvent, None]:

        sess = BrowserSession(session_id)
        cls._sessions[session_id] = sess

        try:
            yield BrowserEvent("browser_starting", {"message": "Starting browser..."})

            if not _PW_AVAILABLE:
                yield BrowserEvent("browser_error", {
                    "message": "Browser automation unavailable. Install playwright.",
                })
                return

            await sess.start()
            yield BrowserEvent("browser_ready", {"session_id": session_id})

            tok = await token_deduct_fn("browser_navigate")
            if not tok["allowed"]:
                yield BrowserEvent("token_exhausted", tok)
                return

            await sess.execute_action(BrowserAction(ActionType.NAVIGATE, url=start_url))
            sc = await sess.screenshot_b64()
            yield BrowserEvent(
                "browser_action",
                {"action": "navigate", "url": start_url, "reason": "Opening platform"},
                screenshot_b64=sc,
            )

            history: List[str] = []
            goal_idx = 0

            for step in range(max_actions):
                if not sess.is_alive:
                    break

                current_goal = goals[min(goal_idx, len(goals) - 1)] if goals else task
                page_summary = await sess.page_summary_json()
                page_text    = await sess.page_text()

                human_req = _detect_human_required(page_text, page_summary)
                if human_req:
                    sc = await sess.screenshot_b64()
                    yield BrowserEvent(
                        "human_required",
                        {
                            "step":         step + 1,
                            "input_type":   human_req.input_type,
                            "message":      human_req.message,
                            "field_label":  human_req.field_label,
                            "current_goal": current_goal,
                        },
                        screenshot_b64=sc,
                    )
                    answer = await sess.wait_for_human(timeout_secs=300)
                    if answer is None:
                        yield BrowserEvent("browser_error", {"message": "User timed out — session ended."})
                        break
                    if human_req.input_type == "2fa" and answer != "captcha_done":
                        await sess.execute_action(BrowserAction(
                            ActionType.FILL,
                            selector="input[type='text']:visible,input[name*='code']:visible",
                            value=answer,
                        ))
                        await sess.execute_action(BrowserAction(ActionType.PRESS_KEY, value="Enter"))
                    yield BrowserEvent("human_answered", {
                        "input_type": human_req.input_type,
                        "message":    "Continuing...",
                    })
                    await asyncio.sleep(1.5)
                    continue

                tok = await token_deduct_fn("_reasoning_step")
                if not tok["allowed"]:
                    sc = await sess.screenshot_b64()
                    yield BrowserEvent("token_exhausted", tok, screenshot_b64=sc)
                    break
                yield BrowserEvent("token_update", {
                    "remaining": tok.get("remaining", 0),
                    "cost":      tok.get("cost", 10),
                    "tool":      "_reasoning_step",
                })

                next_action = await _ai_next_action(
                    task=task, current_goal=current_goal,
                    page_summary=page_summary, page_text=page_text,
                    history=history, ai_service_ref=ai_service_ref,
                )

                tool_key = f"browser_{next_action.action.value}"
                tok2 = await token_deduct_fn(tool_key)
                if not tok2["allowed"]:
                    yield BrowserEvent("token_exhausted", tok2)
                    break
                yield BrowserEvent("token_update", {
                    "remaining": tok2.get("remaining", 0),
                    "cost":      tok2.get("cost", 10),
                    "tool":      tool_key,
                })

                if next_action.action == ActionType.DONE:
                    sc = await sess.screenshot_b64()
                    yield BrowserEvent(
                        "browser_done",
                        {
                            "goal":    current_goal,
                            "message": f"Completed: {current_goal}",
                            "url":     sess.current_url,
                        },
                        screenshot_b64=sc,
                    )
                    goal_idx += 1
                    if goal_idx >= len(goals):
                        break
                    await asyncio.sleep(0.5)
                    continue

                result = await sess.execute_action(next_action)
                sc     = await sess.screenshot_b64()

                history.append(
                    f"[{step+1}] {next_action.action.value} "
                    f"sel={next_action.selector} "
                    f"reason={next_action.reason} "
                    f"→ {'OK' if result.get('ok') else result.get('error','?')}"
                )

                yield BrowserEvent(
                    "browser_action",
                    {
                        "step":     step + 1,
                        "action":   next_action.action.value,
                        "reason":   next_action.reason,
                        "selector": next_action.selector,
                        "url":      sess.current_url,
                        "ok":       result.get("ok", False),
                        "error":    result.get("error"),
                        "goal":     current_goal,
                    },
                    screenshot_b64=sc,
                )

                await asyncio.sleep(1.0)

            final_sc = await sess.screenshot_b64()
            yield BrowserEvent(
                "browser_session_complete",
                {
                    "url":              sess.current_url,
                    "goals_completed":  goal_idx,
                    "total_goals":      len(goals),
                    "actions_taken":    len(history),
                    "message":          "Browser task complete",
                },
                screenshot_b64=final_sc,
            )

        except Exception as e:
            logger.error("BrowserOrchestrator fatal: %s", e, exc_info=True)
            yield BrowserEvent("browser_error", {"message": str(e)[:300]})
        finally:
            await sess.stop()
            cls._sessions.pop(session_id, None)
