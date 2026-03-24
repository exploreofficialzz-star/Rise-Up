# RiseUp — Update Package v3 (APEX + GrowthAI Merged)
Generated: 2026-03-24

## What's New in This Package

### GrowthAI Intelligence (extracted & merged)
Extracted from the Kimi GrowthAI backend and fully integrated into APEX:
- Multi-source live scraper (RemoteOK API, HackerNews Algolia, Reddit public JSON, 25-item curated hustle DB)
- AI opportunity scoring — every result gets a match score 0-100, risk level, action steps, time to first earning
- Market trend analyser — demand, pay ranges, competition, growth trajectory, outlook
- Daily action plan generator — time-blocked tasks, milestones, income targets
- Follow-up sequence builder — full message text, timing, handling rejections
- Earnings insight analyser — growth rate, trend, months to goal
- Wealth milestone checker — progress to next stage, gap, single best action
- Background scheduler — hourly scans, 6-hourly full scans, daily digest emails, weekly summaries

### New APEX Tools (7 added, total now 35)
intelligence category: scrape_live_opportunities, score_opportunity, analyze_market_trends,
create_daily_action_plan, create_follow_up_plan, track_earnings_insight, growth_milestone_check

### New API Endpoints
POST /api/v1/agent/opportunities/search  → Live multi-source opportunity search
GET  /api/v1/agent/opportunities/trending → Trending opportunities
POST /api/v1/agent/market-analysis        → Market trend analysis
POST /api/v1/agent/daily-plan             → Personalised daily action plan
POST /api/v1/agent/score-opportunity      → AI-score any opportunity
POST /api/v1/agent/follow-up-plan         → Follow-up sequence builder
POST /api/v1/agent/earnings-insight       → Earnings trend analysis
POST /api/v1/agent/milestone-check        → Wealth stage progress check

## File Placement

### Backend (all go into backend/ directory)
| File | Destination |
|------|------------|
| backend/main.py | backend/main.py (REPLACE — adds scheduler lifespan) |
| backend/config.py | backend/config.py (REPLACE — adds Reddit + feature flags) |
| backend/requirements.txt | backend/requirements.txt (REPLACE — adds new deps) |
| backend/routers/agent.py | backend/routers/agent.py (REPLACE — 35 tools + new endpoints) |
| backend/services/scraper_service.py | backend/services/scraper_service.py (NEW) |
| backend/services/scheduler_service.py | backend/services/scheduler_service.py (NEW) |

### Migrations (run in Supabase SQL Editor in order)
1. migration_006_agent_quota.sql
2. migration_007_agent_heavy.sql
3. migration_008_growthai.sql  ← NEW

### Frontend
| File | Destination |
|------|------------|
| frontend/lib/screens/agent/agent_screen.dart | REPLACE |
| frontend/lib/services/currency_service.dart | NEW/REPLACE |
| frontend/lib/services/api_service_stream.dart | NEW |
| frontend/lib/providers/app_providers.dart | REPLACE |

## New Environment Variables (add to Render)

```
# Reddit (optional — scraper works without these)
REDDIT_CLIENT_ID=...
REDDIT_CLIENT_SECRET=...

# Feature flags
ENABLE_BACKGROUND_SCAN=true
ENABLE_AI_SCORING=true

# Web Search (at least one)
SERPER_API_KEY=...
TAVILY_API_KEY=...

# Email
SENDGRID_API_KEY=...
```

## Deploy Order
1. Run migration_008_growthai.sql in Supabase
2. Push backend → Render redeploys
3. Replace frontend files → rebuild Flutter app
