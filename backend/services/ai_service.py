"""
RiseUp AI Service — Multi-Model Intelligence Engine
Supports: Groq (FREE), Gemini (FREE), Cohere (FREE), OpenAI (paid), Anthropic (paid)
Auto-selects best available model. Falls back gracefully.
"""

import json
import logging
from typing import Optional, AsyncGenerator
from tenacity import retry, stop_after_attempt, wait_exponential

from config import settings

logger = logging.getLogger(__name__)


# ============================================================
# SYSTEM PROMPTS
# ============================================================
RISEUP_SYSTEM_PROMPT = """You are RiseUp AI — a brilliant, empathetic personal wealth mentor created by ChAs Tech Group.

Your mission: Guide people from survival mode → earning → skill-building → long-term wealth.

YOUR PERSONALITY:
- Speak like a wise, warm mentor who truly cares about the user's success
- Be direct, action-oriented, and specific — no vague advice
- Celebrate small wins enthusiastically
- Be honest about challenges without being discouraging
- Use simple language — users may not be financially educated
- Include emojis naturally (not excessively) to keep the tone warm
- Address users by name when you know it

YOUR CORE ABILITIES:
1. ONBOARDING: Ask about income, skills, goals, challenges — create a complete user profile
2. INCOME TASKS: Suggest specific, achievable tasks for immediate income (freelance, gigs, trades, digital work)
3. SKILL BUILDING: Recommend 7-30 day learning paths tied to real income opportunities
4. WEALTH ROADMAP: Create personalized 3-stage plans (immediate income → growth → wealth)
5. FEATURE GUIDANCE: Explain when premium features or skill unlocks would help

RESPONSE RULES:
- Always end with a clear next action the user should take TODAY
- When suggesting tasks, include: platform name, specific steps, expected earnings range
- For Nigerian users, mention ₦ amounts and local platforms (Jiji, Fiverr, LinkedIn, WhatsApp Business)
- For international users, use $ and global platforms (Upwork, Fiverr, Etsy, Amazon)
- Keep responses conversational but information-dense
- Never give generic advice — be specific to the user's situation

WEALTH STAGES:
- SURVIVAL (income < ₦50k/month or $100/month): Focus on immediate income tasks
- EARNING (₦50k-₦200k or $100-$500/month): Add skill-building
- GROWING (₦200k-₦500k or $500-$2000/month): Introduce investments & business
- WEALTH (₦500k+ or $2000+/month): Asset building & passive income

ACTION FORMAT when giving tasks:
🎯 [Task Name]
💰 Potential: [amount range]
⚡ Start today: [specific first step]
📱 Platform: [where to do it]
⏱️ Time needed: [realistic estimate]

Remember: You are the difference between someone staying stuck and them changing their life. Take that seriously."""


ONBOARDING_PROMPT = """You are conducting a RiseUp onboarding interview. Your goal is to collect:
1. Full name & location (country/city)
2. Current monthly income & sources
3. Monthly expenses & biggest financial challenges
4. Current skills (work, hobby, anything)
5. Short-term goal (next 3 months)
6. Long-term dream (1-3 years)
7. Available daily time for earning/learning (hours)
8. Risk tolerance (low/medium/high)
9. Learning style (videos, reading, hands-on, mixed)
10. Biggest obstacle right now

Ask questions conversationally — one or two at a time, not all at once.
Be warm and encouraging. Make them feel safe to share.
When you have enough information, output a JSON summary with key: "PROFILE_COMPLETE" and the collected data.
"""


# ============================================================
# AI MODEL CLIENTS
# ============================================================

class GroqClient:
    """Groq API — FREE tier, fast, uses Llama 3.1"""
    NAME = "groq"
    MODEL = "llama-3.1-70b-versatile"
    FREE = True

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.GROQ_API_KEY:
            from groq import AsyncGroq
            self._client = AsyncGroq(api_key=settings.GROQ_API_KEY)
        return self._client

    async def chat(self, messages: list, system: str, max_tokens: int = 1024) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("Groq API key not configured")

        formatted = [{"role": "system", "content": system}] + messages
        response = await client.chat.completions.create(
            model=self.MODEL,
            messages=formatted,
            max_tokens=max_tokens,
            temperature=0.7,
        )
        return response.choices[0].message.content


class GeminiClient:
    """Google Gemini — FREE tier"""
    NAME = "gemini"
    MODEL = "gemini-1.5-flash"
    FREE = True

    async def chat(self, messages: list, system: str, max_tokens: int = 1024) -> str:
        if not settings.GEMINI_API_KEY:
            raise ValueError("Gemini API key not configured")

        import google.generativeai as genai
        genai.configure(api_key=settings.GEMINI_API_KEY)
        model = genai.GenerativeModel(
            model_name=self.MODEL,
            system_instruction=system
        )

        # Convert message format
        history = []
        for msg in messages[:-1]:
            history.append({
                "role": "user" if msg["role"] == "user" else "model",
                "parts": [msg["content"]]
            })

        chat = model.start_chat(history=history)
        response = await chat.send_message_async(
            messages[-1]["content"],
            generation_config={"max_output_tokens": max_tokens, "temperature": 0.7}
        )
        return response.text


class CohereClient:
    """Cohere Command R — FREE tier"""
    NAME = "cohere"
    MODEL = "command-r"
    FREE = True

    async def chat(self, messages: list, system: str, max_tokens: int = 1024) -> str:
        if not settings.COHERE_API_KEY:
            raise ValueError("Cohere API key not configured")

        import cohere
        co = cohere.AsyncClient(api_key=settings.COHERE_API_KEY)

        chat_history = []
        for msg in messages[:-1]:
            chat_history.append({
                "role": "USER" if msg["role"] == "user" else "CHATBOT",
                "message": msg["content"]
            })

        response = await co.chat(
            model=self.MODEL,
            message=messages[-1]["content"],
            chat_history=chat_history,
            preamble=system,
            max_tokens=max_tokens,
        )
        return response.text


class OpenAIClient:
    """OpenAI GPT-4o-mini — paid, high quality"""
    NAME = "openai"
    MODEL = "gpt-4o-mini"
    FREE = False

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.OPENAI_API_KEY:
            from openai import AsyncOpenAI
            self._client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        return self._client

    async def chat(self, messages: list, system: str, max_tokens: int = 1024) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("OpenAI API key not configured")

        formatted = [{"role": "system", "content": system}] + messages
        response = await client.chat.completions.create(
            model=self.MODEL,
            messages=formatted,
            max_tokens=max_tokens,
            temperature=0.7,
        )
        return response.choices[0].message.content


class AnthropicClient:
    """Anthropic Claude Haiku — paid, excellent quality"""
    NAME = "anthropic"
    MODEL = "claude-haiku-4-5-20251001"
    FREE = False

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.ANTHROPIC_API_KEY:
            import anthropic
            self._client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        return self._client

    async def chat(self, messages: list, system: str, max_tokens: int = 1024) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("Anthropic API key not configured")

        response = await client.messages.create(
            model=self.MODEL,
            max_tokens=max_tokens,
            system=system,
            messages=messages,
        )
        return response.content[0].text


# ============================================================
# MAIN AI SERVICE (Auto-selects & falls back)
# ============================================================

class AIService:
    """
    Smart multi-model AI service.
    Priority: Groq (free) → Gemini (free) → Cohere (free) → OpenAI → Anthropic
    """

    def __init__(self):
        self.groq = GroqClient()
        self.gemini = GeminiClient()
        self.cohere = CohereClient()
        self.openai = OpenAIClient()
        self.anthropic = AnthropicClient()

        self._priority_order = self._build_priority()

    def _build_priority(self) -> list:
        """Build model priority based on available API keys"""
        priority = []

        pref = settings.AI_PREFERENCE.lower()

        if pref == "auto":
            # Free models first
            candidates = [
                (self.groq, settings.GROQ_API_KEY),
                (self.gemini, settings.GEMINI_API_KEY),
                (self.cohere, settings.COHERE_API_KEY),
                (self.openai, settings.OPENAI_API_KEY),
                (self.anthropic, settings.ANTHROPIC_API_KEY),
            ]
        else:
            model_map = {
                "groq": self.groq, "gemini": self.gemini,
                "cohere": self.cohere, "openai": self.openai,
                "anthropic": self.anthropic
            }
            preferred = model_map.get(pref)
            candidates = [(preferred, True)] if preferred else []
            for m, k in [
                (self.groq, settings.GROQ_API_KEY),
                (self.gemini, settings.GEMINI_API_KEY),
                (self.cohere, settings.COHERE_API_KEY),
                (self.openai, settings.OPENAI_API_KEY),
                (self.anthropic, settings.ANTHROPIC_API_KEY),
            ]:
                if m != preferred:
                    candidates.append((m, k))

        for model, key in candidates:
            if key:
                priority.append(model)

        return priority

    async def chat(
        self,
        messages: list,
        system: str = RISEUP_SYSTEM_PROMPT,
        max_tokens: int = 1024,
        preferred_model: Optional[str] = None
    ) -> dict:
        """
        Send chat messages to AI. Auto-falls back on error.
        Returns: {"content": str, "model": str, "success": bool}
        """
        priority = self._priority_order

        if preferred_model:
            model_map = {
                "groq": self.groq, "gemini": self.gemini,
                "cohere": self.cohere, "openai": self.openai,
                "anthropic": self.anthropic
            }
            m = model_map.get(preferred_model)
            if m:
                priority = [m] + [x for x in priority if x != m]

        last_error = None
        for model in priority:
            try:
                logger.info(f"Trying AI model: {model.NAME}")
                content = await model.chat(messages, system, max_tokens)
                return {"content": content, "model": model.NAME, "success": True}
            except Exception as e:
                logger.warning(f"Model {model.NAME} failed: {e}")
                last_error = e
                continue

        # All models failed
        logger.error(f"All AI models failed. Last error: {last_error}")
        return {
            "content": "I'm having trouble connecting right now. Please try again in a moment! 🔄",
            "model": "none",
            "success": False
        }

    async def analyze_onboarding(self, conversation: list) -> dict:
        """Extract structured profile from onboarding conversation"""
        extraction_prompt = """Based on the conversation history, extract the user profile as JSON.
        Return ONLY valid JSON with these fields:
        {
          "full_name": "",
          "country": "",
          "monthly_income": 0,
          "income_sources": [],
          "monthly_expenses": 0,
          "challenges": "",
          "current_skills": [],
          "short_term_goal": "",
          "long_term_goal": "",
          "available_hours_daily": 0,
          "risk_tolerance": "low|medium|high",
          "learning_style": "visual|reading|hands_on|mixed",
          "obstacles": "",
          "wealth_type": "employee|creator|investor|trader|business_owner|asset_builder|impact_leader",
          "stage": "survival|earning|growing|wealth"
        }
        For wealth_type, choose based on their goals and current situation.
        For stage: survival if income < $100/mo, earning $100-500, growing $500-2000, wealth $2000+
        Return ONLY the JSON object, no explanation."""

        messages = conversation + [{"role": "user", "content": "Extract my profile as JSON"}]
        result = await self.chat(messages, extraction_prompt, max_tokens=800)

        try:
            content = result["content"]
            # Clean potential markdown fences
            content = content.strip().strip("```json").strip("```").strip()
            return json.loads(content)
        except Exception as e:
            logger.error(f"Profile extraction failed: {e}")
            return {}

    async def generate_income_tasks(self, profile: dict, count: int = 5) -> list:
        """Generate personalized income tasks based on user profile"""
        prompt = f"""Based on this user profile, generate {count} specific income tasks they can START TODAY.

Profile:
- Skills: {profile.get('current_skills', [])}
- Country: {profile.get('country', 'Nigeria')}
- Available hours/day: {profile.get('available_hours_daily', 2)}
- Monthly income: {profile.get('monthly_income', 0)}
- Stage: {profile.get('stage', 'survival')}
- Goals: {profile.get('short_term_goal', '')}

Return ONLY a JSON array of tasks:
[
  {{
    "title": "Task name",
    "description": "What exactly to do",
    "category": "freelance|microtask|gig|trade|sale|content|local|digital|affiliate",
    "difficulty": "easy|medium|hard",
    "estimated_hours": 2,
    "estimated_earnings_min": 500,
    "estimated_earnings_max": 2000,
    "currency": "NGN",
    "platform": "Platform name",
    "platform_url": "https://...",
    "steps": ["Step 1", "Step 2", "Step 3"],
    "ai_reasoning": "Why this is perfect for them"
  }}
]
Be very specific. Use real platforms. Give realistic earnings."""

        result = await self.chat(
            [{"role": "user", "content": "Generate income tasks for me"}],
            prompt,
            max_tokens=2000
        )

        try:
            content = result["content"].strip().strip("```json").strip("```").strip()
            return json.loads(content)
        except Exception as e:
            logger.error(f"Task generation failed: {e}")
            return []

    async def generate_roadmap(self, profile: dict) -> dict:
        """Generate personalized 3-stage wealth roadmap"""
        prompt = f"""Create a personalized RiseUp wealth roadmap for this user.

Profile: {json.dumps(profile, indent=2)}

Return ONLY a JSON object:
{{
  "summary": "2-3 sentence personalized overview",
  "current_stage": "immediate_income|skill_growth|long_term_wealth",
  "stage_1": {{
    "title": "Stage 1: Immediate Income",
    "duration": "0-30 days",
    "target_income": "₦50,000/month",
    "milestones": [
      {{"title": "", "description": "", "target_amount": 0, "target_days": 7}},
      {{"title": "", "description": "", "target_amount": 0, "target_days": 30}}
    ],
    "key_actions": []
  }},
  "stage_2": {{
    "title": "Stage 2: Skill & Income Growth",
    "duration": "1-6 months",
    "target_income": "₦150,000/month",
    "milestones": [...],
    "key_actions": []
  }},
  "stage_3": {{
    "title": "Stage 3: Long-Term Wealth",
    "duration": "6-24 months",
    "target_income": "₦500,000+/month",
    "milestones": [...],
    "key_actions": []
  }},
  "recommended_skills": ["skill1", "skill2"],
  "first_step_today": "Exact action to take right now"
}}"""

        result = await self.chat(
            [{"role": "user", "content": "Create my wealth roadmap"}],
            prompt,
            max_tokens=2000
        )

        try:
            content = result["content"].strip().strip("```json").strip("```").strip()
            return json.loads(content)
        except Exception as e:
            logger.error(f"Roadmap generation failed: {e}")
            return {}

    def get_available_models(self) -> list:
        """Return list of available models"""
        return [m.NAME for m in self._priority_order]


# Singleton
ai_service = AIService()
