# RiseUp — Update Package
Generated: 2026-03-23

## What's in this package

### Backend Files
Place these files into your backend project directory:

| File | Destination |
|------|------------|
| backend/routers/agent.py | backend/routers/agent.py (REPLACE) |
| backend/routers/ads.py | backend/routers/ads.py (NEW — fixes startup crash) |
| backend/config.py | backend/config.py (REPLACE) |
| backend/services/web_search_service.py | backend/services/web_search_service.py (NEW) |
| backend/services/action_service.py | backend/services/action_service.py (NEW) |

### Database Migrations
Run these in order in your Supabase SQL Editor:

1. backend/migrations/migration_006_agent_quota.sql
2. backend/migrations/migration_007_agent_heavy.sql

### Frontend Files
Place these files into your Flutter project:

| File | Destination |
|------|------------|
| frontend/lib/screens/agent/agent_screen.dart | REPLACE existing |
| frontend/lib/services/currency_service.dart | NEW |
| frontend/lib/services/api_service_stream.dart | NEW |
| frontend/lib/providers/app_providers.dart | REPLACE existing |

---

## New Environment Variables (add to Render)

```
# Web Search (pick at least one)
SERPER_API_KEY=...        # serper.dev — free 2,500/month
TAVILY_API_KEY=...        # tavily.com — free 1,000/month

# Email Sending
SENDGRID_API_KEY=...      # sendgrid.com — free 100/day
EMAIL_FROM=agent@yourdomain.com

# Social Media (optional)
TWITTER_CLIENT_ID=...
TWITTER_CLIENT_SECRET=...
LINKEDIN_CLIENT_ID=...
LINKEDIN_CLIENT_SECRET=...
```

---

## Summary of Changes

### Bug Fix
- Added missing `ads.py` router — this was causing the "Exited with status 1" crash on Render

### APEX Agent (backend/routers/agent.py)
- Full ReAct reasoning loop (think → act → observe → repeat)
- 28 tools across 4 categories: thinking, research, action, document
- Live streaming via SSE (Server-Sent Events)
- Real web search (Serper/Tavily/DuckDuckGo)
- Email sending, social media posting
- Contract/invoice/proposal generation
- Partner and job finding
- Self-correction on tool failures
- Daily run quota (3 free / 25 premium)

### Web Search Service (backend/services/web_search_service.py)
- Serper API (Google results) → Tavily → DuckDuckGo fallback chain
- Deep multi-query research
- Live job board search
- Partner/collaborator finder
- Free resource finder

### Action Service (backend/services/action_service.py)
- Email via SendGrid or SMTP
- Twitter/X posting
- LinkedIn posting
- Scheduled post storage
- Document generation (contract, invoice, proposal, pitch deck)
- Opportunity scanner

### Currency Service (frontend/lib/services/currency_service.dart)
- 50+ currencies supported
- No hardcoded $ or NGN anywhere
- Reads from user profile automatically
- Compact formatter (1K, 50K, 1.2M)
- Dual display (USD + local currency)

### Agent Screen (frontend/lib/screens/agent/agent_screen.dart)
- Live streaming progress view
- 5 result tabs: Plan, Jobs, Docs, Outreach, Posts
- Direct action chips (find jobs, find partners, generate contract, etc.)
- Permission toggles for email/social posting
- Dynamic currency throughout
- All APEX features surfaced in the UI
