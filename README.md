# 🚀 RiseUp — AI Wealth Mentor App

> **Owner:** ChAs Tech Group
> **Mission:** Guide people from survival mode → earning → skill-building → long-term wealth.

[![Deploy Backend](https://github.com/YOUR_ORG/riseup/actions/workflows/deploy-backend.yml/badge.svg)](https://github.com/YOUR_ORG/riseup/actions/workflows/deploy-backend.yml)
[![Build Android](https://github.com/YOUR_ORG/riseup/actions/workflows/build-android.yml/badge.svg)](https://github.com/YOUR_ORG/riseup/actions/workflows/build-android.yml)

---

## 📱 What is RiseUp?

RiseUp is a conversational AI-powered wealth-building platform. Users chat with an AI mentor that:

- **Analyzes their situation** (income, skills, obstacles, goals)
- **Assigns immediate income tasks** (freelance, gigs, digital work)
- **Teaches skills while they earn** (7–30 day micro-courses)
- **Builds a personalized wealth roadmap** (3-stage plan)
- **Adapts in real-time** as they progress

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter Android App                  │
│  Auth → Onboarding Chat → Dashboard → Tasks → Skills    │
│  → Roadmap → Payments → Profile                         │
└────────────────────┬────────────────────────────────────┘
                     │ HTTPS / REST
┌────────────────────▼────────────────────────────────────┐
│              FastAPI Backend (Render)                    │
│  /ai  /tasks  /skills  /payments  /progress  /auth      │
└──────┬──────────────────────────┬───────────────────────┘
       │                          │
┌──────▼──────┐          ┌────────▼────────┐
│  Supabase   │          │   AI Services   │
│  - Auth     │          │  Groq (FREE)    │
│  - Database │          │  Gemini (FREE)  │
│  - RLS      │          │  Cohere (FREE)  │
└─────────────┘          │  OpenAI (paid)  │
                         │  Anthropic(paid)│
                         └─────────────────┘
       │
┌──────▼──────────────────────────┐
│         External Services       │
│  Flutterwave (payments)         │
│  AdMob (rewarded ads)           │
│  Firebase FCM (push notifs)     │
└─────────────────────────────────┘
```

---

## 💰 AI Models Used

| Model | Provider | Cost | Use |
|---|---|---|---|
| **Llama 3.1 70B** | Groq | **FREE** | Primary (fast, smart) |
| **Gemini 1.5 Flash** | Google | **FREE** | Secondary fallback |
| **Command R** | Cohere | **FREE** | Tertiary fallback |
| GPT-4o Mini | OpenAI | Paid | Premium fallback |
| Claude Haiku | Anthropic | Paid | Premium fallback |

The backend **auto-selects** the best available model and gracefully falls back.

---

## 📁 Project Structure

```
riseup/
├── backend/                    # FastAPI Python backend
│   ├── main.py                 # App entry point
│   ├── config.py               # Environment settings
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .env.example
│   ├── routers/
│   │   ├── ai_agent.py         # 🤖 Core AI chat & task generation
│   │   ├── auth.py             # 🔐 Supabase auth
│   │   ├── tasks.py            # 📋 Income tasks
│   │   ├── skills.py           # 📚 Skill modules
│   │   ├── payments.py         # 💳 Flutterwave + AdMob
│   │   └── progress.py         # 📊 Stats & roadmap
│   ├── services/
│   │   ├── ai_service.py       # Multi-model AI engine
│   │   ├── supabase_service.py # Database layer
│   │   └── flutterwave_service.py
│   ├── models/
│   │   └── schemas.py          # Pydantic models
│   └── utils/
│       └── auth.py
│
├── frontend/                   # Flutter Android app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── main_shell.dart     # Bottom nav shell
│   │   ├── config/
│   │   │   ├── app_constants.dart  # Theme, colors, styles
│   │   │   └── router.dart         # GoRouter navigation
│   │   ├── services/
│   │   │   ├── api_service.dart    # Backend API client
│   │   │   └── ad_service.dart     # AdMob rewarded ads
│   │   ├── screens/
│   │   │   ├── auth/           # Splash, Login, Register
│   │   │   ├── onboarding/     # AI-guided interview
│   │   │   ├── dashboard/      # Home dashboard
│   │   │   ├── chat/           # Full AI chat interface
│   │   │   ├── tasks/          # Income tasks manager
│   │   │   ├── skills/         # Skill modules + progress
│   │   │   ├── roadmap/        # 3-stage wealth roadmap
│   │   │   ├── payment/        # Flutterwave subscription
│   │   │   └── profile/        # User profile & settings
│   │   └── widgets/            # Reusable UI components
│   ├── android/
│   │   ├── app/build.gradle
│   │   └── app/src/main/AndroidManifest.xml
│   └── pubspec.yaml
│
├── supabase/
│   ├── config.toml
│   └── migrations/
│       └── 001_initial_schema.sql  # Full DB schema
│
├── .github/workflows/
│   ├── deploy-backend.yml      # Auto-deploy to Render
│   ├── build-android.yml       # Build APK + AAB
│   ├── supabase-migrations.yml # Apply DB migrations
│   └── pr-checks.yml           # PR quality gates
│
├── render.yaml                 # Render deployment config
├── SECRETS.md                  # GitHub Secrets setup guide
└── README.md
```

---

## ⚡ Quick Start

### Prerequisites
- Python 3.11+
- Flutter 3.22+
- Supabase account (free)
- Groq API key (free)

### 1. Clone & Setup

```bash
git clone https://github.com/YOUR_ORG/riseup.git
cd riseup
```

### 2. Setup Database

1. Create a [Supabase project](https://supabase.com)
2. Go to **SQL Editor** → paste and run `supabase/migrations/001_initial_schema.sql`
3. Copy your `Project URL`, `anon key`, and `service_role key`

### 3. Run Backend Locally

```bash
cd backend
cp .env.example .env
# Edit .env with your keys

pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

API docs at: `http://localhost:8000/docs`

### 4. Run Flutter App

```bash
cd frontend
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=SUPABASE_URL=your_url \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

---

## 🚀 Deploy to Production

### Backend → Render

1. Go to [render.com](https://render.com) → New Web Service
2. Connect your GitHub repo
3. Set **Root Directory**: `backend`
4. Set **Build Command**: `pip install -r requirements.txt`
5. Set **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
6. Add all environment variables from `.env.example`
7. Click **Deploy**

OR use the included `render.yaml` (auto-detected by Render).

### Android → GitHub Actions

Push to `main` → GitHub Actions automatically:
1. ✅ Analyzes Flutter code
2. 🏗️ Builds release APK + AAB
3. 📦 Creates GitHub Release with downloadable files
4. 🌐 Deploys backend to Render

See `SECRETS.md` for required GitHub Secrets.

---

## 💳 Monetization

### Free Tier
- AI chat (limited)
- 3 income task suggestions
- Basic skill modules
- **Watch ads to unlock features temporarily**

### Premium — $15.99/month or $99.99/year
- Unlimited AI mentor chat
- Personalized wealth roadmap
- All skill modules
- Task booster (2x tasks)
- Investment tools
- Mentorship access
- Advanced analytics

---

## 🔑 Key Features

| Feature | Tech |
|---|---|
| AI Conversations | Groq/Gemini/Cohere/OpenAI/Anthropic |
| Authentication | Supabase Auth (JWT) |
| Database | Supabase PostgreSQL with RLS |
| Payments | Flutterwave (190+ countries) |
| Rewarded Ads | Google AdMob |
| Push Notifications | Firebase FCM |
| State Management | Riverpod |
| Navigation | GoRouter |
| HTTP Client | Dio with auto-refresh |
| Animations | flutter_animate |
| Charts | fl_chart |

---

## 📊 Database Tables

- `profiles` — User data, stage, wealth type, subscription
- `conversations` + `messages` — Chat history
- `tasks` — AI-generated income tasks
- `skill_modules` + `user_skill_enrollments` — Learning
- `roadmaps` + `milestones` — Wealth journey
- `payments` — Flutterwave transactions
- `feature_unlocks` — Ad & payment unlocks
- `earnings` — Income tracker
- `achievements` — Gamification
- `community_posts` — Social features
- `ad_views` — AdMob tracking

All tables have **Row Level Security (RLS)** — users only see their own data.

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing-feature`
5. Open a Pull Request

PR checks will automatically run Flutter analysis and Python linting.

---

## 📄 License

MIT License — ChAs Tech Group © 2025

---

*Built with ❤️ by ChAs Tech Group | Empowering the next generation of wealth builders*
