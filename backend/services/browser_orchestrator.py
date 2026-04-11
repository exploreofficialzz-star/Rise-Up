"""
backend/services/browser_orchestrator.py
APEX Browser Orchestrator — v1.0

Playwright headless browser controlled by AI decision loop.
Screenshots streamed to frontend via SSE (stored in browser_events table).
Pauses automatically for CAPTCHA / 2FA / questions.

Install: pip install playwright && playwright install chromium
"""

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
        TimeoutError as PWTimeout,
    )
    _PW_AVAILABLE = True
except ImportError:
    _PW_AVAILABLE = False
    logger.warning(
        "Playwright not installed — browser automation disabled. "
        "Run: pip install playwright && playwright install chromium"
    )


# ══════════════════════════════════════════════════════════════════
# ENUMS & DATA CLASSES
# ══════════════════════════════════════════════════════════════════

class ActionType(str, Enum):
    NAVIGATE   = "navigate"
    CLICK      = "click"
    FILL       = "fill"
    SCROLL     = "scroll"
    WAIT       = "wait"
    SCREENSHOT = "screenshot"
    EXTRACT    = "extract"
    SELECT     = "select"
    PRESS_KEY  = "press_key"
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
class HumanRequest:
    input_type:  str
    message:     str
    field_label: Optional[str] = None
    options:     List[str]     = field(default_factory=list)


# ══════════════════════════════════════════════════════════════════
# CAPTCHA / 2FA DETECTION
# ══════════════════════════════════════════════════════════════════

_CAPTCHA_SIGNALS = [
    "captcha", "recaptcha", "hcaptcha", "cf-challenge",
    "challenge-form", "turnstile", "are you a robot",
    "verify you are human", "security check", "robot",
]
_TWO_FA_SIGNALS = [
    "verification code", "one-time", "otp", "sms code",
    "authenticator", "2-step", "two-step", "enter the code",
    "sent a code", "6-digit",
]


def _detect_human_required(page_text: str, page_html: str) -> Optional[HumanRequest]:
    combined = (page_text + page_html).lower()
    for sig in _CAPTCHA_SIGNALS:
        if sig in combined:
            return HumanRequest(
                input_type="captcha",
                message=(
                    "🔒 A CAPTCHA appeared. Please solve it and tap **Done — Continue**."
                ),
            )
    for sig in _TWO_FA_SIGNALS:
        if sig in combined:
            return HumanRequest(
                input_type="2fa",
                message="📱 Two-factor authentication required. Enter the code sent to your device.",
                field_label="Verification code",
            )
    return None


# ══════════════════════════════════════════════════════════════════
# BROWSER SESSION
# ══════════════════════════════════════════════════════════════════

class BrowserSession:

    def __init__(self, session_id: str):
        self.session_id  = session_id
        self._pw         = None
        self._browser: Optional["Browser"]        = None
        self._context: Optional["BrowserContext"] = None
        self.page:     Optional["Page"]           = None
        self.is_alive    = False
        self.current_url = ""
        self._human_event  = asyncio.Event()
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
                "--disable-infobars",
            ],
        )
        self._context = await self._browser.new_context(
            viewport={"width": 1280, "height": 800},
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            java_script_enabled=True,
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
            data = await self.page.screenshot(type="jpeg", quality=75, full_page=False)
            return base64.b64encode(data).decode()
        except Exception as e:
            logger.error("Screenshot error: %s", e)
            return ""

    async def page_text(self, max_chars: int = 8000) -> str:
        try:
            if not self.page:
                return ""
            text = await self.page.evaluate("() => document.body.innerText")
            return (text or "")[:max_chars]
        except Exception:
            return ""

    async def page_html_summary(self) -> str:
        try:
            if not self.page:
                return "{}"
            js = """() => {
                const inputs  = [...document.querySelectorAll('input,textarea,select')]
                    .slice(0,20)
                    .map(el => `[${el.type||el.tagName}] name="${el.name}" id="${el.id}" placeholder="${el.placeholder}"`);
                const buttons = [...document.querySelectorAll('button,a[href]')]
                    .slice(0,20)
                    .map(el => `[BTN] "${el.innerText.trim().slice(0,40)}" id="${el.id}"`);
                return JSON.stringify({
                    title: document.title,
                    url:   location.href,
                    inputs,
                    buttons
                });
            }"""
            raw = await self.page.evaluate(js)
            return raw or "{}"
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
                await page.click(action.selector or "", timeout=8_000)
                await asyncio.sleep(0.8)
                return {"ok": True}

            elif action.action == ActionType.FILL:
                await page.fill(action.selector or "", action.value or "", timeout=8_000)
                return {"ok": True}

            elif action.action == ActionType.SELECT:
                await page.select_option(action.selector or "", action.value or "", timeout=8_000)
                return {"ok": True}

            elif action.action == ActionType.PRESS_KEY:
                await page.keyboard.press(action.value or "Enter")
                await asyncio.sleep(0.5)
                return {"ok": True}

            elif action.action == ActionType.SCROLL:
                await page.evaluate("window.scrollBy(0, 600)")
                return {"ok": True}

            elif action.action == ActionType.WAIT:
                secs = float(action.value or "2")
                await asyncio.sleep(min(secs, 5))
                return {"ok": True}

            elif action.action == ActionType.EXTRACT:
                sel  = action.selector
                data = await page.evaluate(
                    f"() => [...document.querySelectorAll('{sel}')].slice(0,20).map(e=>e.innerText.trim())"
                ) if sel else []
                return {"ok": True, "data": data}

            elif action.action == ActionType.SCREENSHOT:
                return {"ok": True, "screenshot": await self.screenshot_b64()}

            elif action.action == ActionType.DONE:
                return {"ok": True, "done": True}

            return {"ok": False, "error": f"Unknown action: {action.action}"}

        except Exception as e:
            if _PW_AVAILABLE:
                try:
                    from playwright.async_api import TimeoutError as PWTimeout
                    if isinstance(e, PWTimeout):
                        return {"ok": False, "error": f"Timeout on {action.action}"}
                except Exception:
                    pass
            return {"ok": False, "error": str(e)}

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


# ══════════════════════════════════════════════════════════════════
# AI DECISION ENGINE
# ══════════════════════════════════════════════════════════════════

async def _ai_decide_next_action(
    task:          str,
    goal:          str,
    page_summary:  str,
    page_text:     str,
    history:       List[str],
    ai_service_ref,
) -> BrowserAction:
    history_str = "\n".join(history[-6:])
    prompt = f"""You are APEX browser automation AI. Control a web browser to complete this task.

OVERALL TASK: {task}
CURRENT GOAL: {goal}

BROWSER STATE:
{page_summary}

PAGE TEXT (first 2000 chars):
{page_text[:2000]}

RECENT ACTIONS:
{history_str}

Decide the SINGLE NEXT ACTION. Return ONLY valid JSON:
{{
  "action": "navigate|click|fill|select|scroll|wait|press_key|extract|done",
  "selector": "CSS selector or null",
  "value": "text to type / key / option value or null",
  "url": "full URL if navigating or null",
  "reason": "brief explanation"
}}

RULES:
- If task complete → action="done"
- Prefer id/name selectors over generic ones
- If CAPTCHA/2FA detected → action="done", reason="human_required"
- Fill forms one field at a time
"""
    try:
        result = await ai_service_ref.mentor_chat(
            messages=[{"role": "user", "content": prompt}],
            system_prompt="You control a browser. Return ONLY valid JSON for the next action.",
            max_tokens=300,
        )
        raw = result.get("content", "{}").strip()
        raw = re.sub(r"```[a-z]*\n?", "", raw).strip().rstrip("```").strip()
        data = json.loads(raw)
        return BrowserAction(
            action   = ActionType(data.get("action", "wait")),
            selector = data.get("selector"),
            value    = data.get("value"),
            url      = data.get("url"),
            reason   = data.get("reason", ""),
        )
    except Exception as e:
        logger.error("AI browser decision error: %s", e)
        return BrowserAction(action=ActionType.WAIT, reason="AI decision failed, waiting")


# ══════════════════════════════════════════════════════════════════
# ORCHESTRATOR
# ══════════════════════════════════════════════════════════════════

class BrowserOrchestrator:
    """Static class — one session dict shared across the process."""

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
        max_actions:     int = 40,
    ) -> AsyncGenerator[BrowserEvent, None]:

        sess = BrowserSession(session_id)
        cls._sessions[session_id] = sess

        try:
            yield BrowserEvent("browser_starting", {"message": "🌐 Starting browser..."})

            if not _PW_AVAILABLE:
                yield BrowserEvent("browser_error", {
                    "message": "Browser automation not available on this server.",
                    "fallback": "Using AI-only mode instead.",
                })
                return

            await sess.start()
            yield BrowserEvent("browser_ready", {"message": "Browser ready"})

            # Navigate to start URL
            tok = await token_deduct_fn("browser_navigate")
            if not tok["allowed"]:
                yield BrowserEvent("token_exhausted", tok)
                return

            await sess.execute_action(BrowserAction(ActionType.NAVIGATE, url=start_url))
            screenshot = await sess.screenshot_b64()
            yield BrowserEvent(
                "browser_action",
                {"action": "navigate", "url": start_url, "reason": "Opening platform"},
                screenshot_b64=screenshot,
            )

            action_history:  List[str] = []
            current_goal_idx = 0

            for i in range(max_actions):
                if not sess.is_alive:
                    break

                current_goal = goals[min(current_goal_idx, len(goals) - 1)] if goals else task
                page_summary = await sess.page_html_summary()
                page_text    = await sess.page_text()

                # Detect human required
                human_req = _detect_human_required(page_text, page_summary)
                if human_req:
                    screenshot = await sess.screenshot_b64()
                    yield BrowserEvent(
                        "human_required",
                        {
                            "input_type":  human_req.input_type,
                            "message":     human_req.message,
                            "field_label": human_req.field_label,
                            "options":     human_req.options,
                            "step":        i + 1,
                        },
                        screenshot_b64=screenshot,
                    )
                    answer = await sess.wait_for_human(timeout_secs=300)
                    if answer is None:
                        yield BrowserEvent("human_timeout", {"message": "No response received, stopping task."})
                        break
                    if human_req.input_type == "2fa" and answer != "captcha_done":
                        await sess.execute_action(BrowserAction(
                            ActionType.FILL,
                            selector="input[type='text'],input[name*='code'],input[name*='otp'],input[name*='token']",
                            value=answer,
                        ))
                        await sess.execute_action(BrowserAction(ActionType.PRESS_KEY, value="Enter"))
                    yield BrowserEvent("human_answered", {"input_type": human_req.input_type, "message": "✅ Continuing..."})
                    await asyncio.sleep(1.5)
                    continue

                # Deduct reasoning token
                tok = await token_deduct_fn("_reasoning_step")
                if not tok["allowed"]:
                    screenshot = await sess.screenshot_b64()
                    yield BrowserEvent("token_exhausted", {**tok}, screenshot_b64=screenshot)
                    break

                yield BrowserEvent("token_update", {
                    "remaining": tok.get("remaining", 0),
                    "cost":      tok.get("cost", 10),
                    "tool":      "_reasoning_step",
                })

                # AI decides next action
                next_action = await _ai_decide_next_action(
                    task=task, goal=current_goal,
                    page_summary=page_summary, page_text=page_text,
                    history=action_history, ai_service_ref=ai_service_ref,
                )

                # Deduct browser action token
                action_tool = "browser_navigate" if next_action.action == ActionType.NAVIGATE else "browser_action"
                tok2 = await token_deduct_fn(action_tool)
                if not tok2["allowed"]:
                    yield BrowserEvent("token_exhausted", tok2)
                    break

                yield BrowserEvent("token_update", {
                    "remaining": tok2.get("remaining", 0),
                    "cost":      tok2.get("cost", 10),
                    "tool":      action_tool,
                })

                if next_action.action == ActionType.DONE:
                    screenshot = await sess.screenshot_b64()
                    yield BrowserEvent(
                        "browser_done",
                        {"message": f"✅ {current_goal} — complete!", "url": sess.current_url},
                        screenshot_b64=screenshot,
                    )
                    current_goal_idx += 1
                    if current_goal_idx >= len(goals):
                        break
                    await asyncio.sleep(0.5)
                    continue

                result     = await sess.execute_action(next_action)
                screenshot = await sess.screenshot_b64()

                action_history.append(
                    f"[{i+1}] {next_action.action.value}: {next_action.reason} "
                    f"→ {'OK' if result.get('ok') else result.get('error','?')}"
                )

                yield BrowserEvent(
                    "browser_action",
                    {
                        "step":     i + 1,
                        "action":   next_action.action.value,
                        "reason":   next_action.reason,
                        "selector": next_action.selector,
                        "value":    (next_action.value or "")[:30] if next_action.value else None,
                        "url":      sess.current_url,
                        "ok":       result.get("ok", False),
                        "error":    result.get("error"),
                    },
                    screenshot_b64=screenshot,
                )

                await asyncio.sleep(1.0)

            # Session complete
            final_screenshot = await sess.screenshot_b64()
            yield BrowserEvent(
                "browser_session_complete",
                {
                    "url":           sess.current_url,
                    "actions_taken": len(action_history),
                    "message":       "Browser task completed",
                },
                screenshot_b64=final_screenshot,
            )

        except Exception as e:
            logger.error("BrowserOrchestrator.run error: %s", e)
            yield BrowserEvent("browser_error", {"message": str(e)})
        finally:
            await sess.stop()
            cls._sessions.pop(session_id, None)

