# RiseUp — Complete Project Summary
## ChAs Tech Group

---

## 📦 What's In This Package

### Total: 90+ files across 4 layers

---

## 🗄️ DATABASE LAYER — Supabase

### Tables (13 total)
| Table | Purpose |
|-------|---------|
| `profiles` | Users, stage, wealth type, subscription, AI context |
| `conversations` | Chat sessions |
| `messages` | Every chat message with AI model used |
| `tasks` | AI-generated income tasks per user |
| `skill_modules` | Earn-while-learning courses (seeded) |
| `user_skill_enrollments` | User progress per course |
| `roadmaps` | 3-stage wealth roadmap per user |
| `milestones` | Individual roadmap checkpoints |
| `payments` | Flutterwave transactions |
| `feature_unlocks` | Ad/payment-based feature access |
| `earnings` | Every income logged |
| `achievements` | Gamification badges |
| `community_posts` | Social feed |
| `ad_views` | AdMob tracking |

### Security: All tables have Row Level Security — users only ever see their own data.

---

## 🐍 BACKEND — FastAPI (Python)

### API Routes (35+ endpoints)
```
POST   /api/v1/auth/signup
POST   /api/v1/auth/signin
POST   /api/v1/auth/refresh
POST   /api/v1/ai/chat              ← Core AI mentor
POST   /api/v1/ai/generate-tasks    ← Generate income tasks
POST   /api/v1/ai/generate-roadmap  ← Build wealth roadmap
GET    /api/v1/ai/conversations
GET    /api/v1/ai/models
GET    /api/v1/tasks/
PATCH  /api/v1/tasks/:id
GET    /api/v1/skills/modules
POST   /api/v1/skills/enroll
GET    /api/v1/skills/my-courses
PATCH  /api/v1/skills/progress
POST   /api/v1/payments/initiate    ← Flutterwave link
POST   /api/v1/payments/verify
POST   /api/v1/payments/webhook     ← Flutterwave webhook
POST   /api/v1/payments/ad-unlock   ← AdMob reward
GET    /api/v1/payments/check-access/:feature
GET    /api/v1/payments/subscription-status
GET    /api/v1/progress/stats
GET    /api/v1/progress/earnings
POST   /api/v1/progress/log-earning
GET    /api/v1/progress/roadmap
GET    /api/v1/progress/profile
PATCH  /api/v1/progress/profile
GET    /api/v1/community/posts
POST   /api/v1/community/posts
GET    /api/v1/community/leaderboard
```

### AI Intelligence
- **5 AI models** with automatic fallback
- **Free-first order**: Groq → Gemini → Cohere → OpenAI → Anthropic
- **Smart system prompts** injected with user context
- **4 prompt modes**: general, onboarding, task generation, roadmap
- **Structured extraction**: Onboarding auto-extracts profile as JSON
- **Wealth stage detection**: Automatic based on income level

---

## 📱 FRONTEND — Flutter Android

### Screens (13 screens)
| Screen | Purpose |
|--------|---------|
| `SplashScreen` | Launch animation, auth check |
| `LoginScreen` | Email/password login |
| `RegisterScreen` | Sign up with auto onboarding redirect |
| `OnboardingChatScreen` | AI-guided profile interview |
| `DashboardScreen` | Home with earnings, tasks, stats |
| `ChatScreen` | Full AI mentor chat with markdown |
| `TasksScreen` | Income tasks (Suggested/Active/Done tabs) |
| `SkillsScreen` | All courses + My learning tabs |
| `SkillDetailScreen` | Course lessons breakdown |
| `RoadmapScreen` | 3-stage wealth roadmap (access-gated) |
| `PaymentScreen` | Flutterwave subscription |
| `EarningsScreen` | Income tracker with manual logging |
| `AnalyticsScreen` | Charts, stats breakdown |
| `CommunityScreen` | Feed, Leaderboard, Challenges |
| `SettingsScreen` | Account, notifications, AI model picker |
| `ProfileScreen` | User profile and stats |

### Services
| Service | Purpose |
|---------|---------|
| `ApiService` | Full backend REST client (Dio + JWT refresh) |
| `AdService` | AdMob rewarded ads → feature unlock |
| `NotificationService` | Firebase FCM push notifications |

### State Management: Riverpod providers for all data

---

## ⚙️ CI/CD — GitHub Actions (5 workflows)

| Workflow | Trigger | Does |
|----------|---------|------|
| `deploy-backend.yml` | Push to main (backend/) | Tests + deploys to Render |
| `build-android.yml` | Push to main (frontend/) | Builds APK + AAB + GitHub Release |
| `supabase-migrations.yml` | Push to main (migrations/) | Applies DB migrations |
| `deploy-edge-functions.yml` | Push to main (functions/) | Deploys Supabase functions |
| `pr-checks.yml` | Any PR | Flutter analyze + Python lint + security scan |

---

## 💰 MONETIZATION FLOWS

### Free Tier
```
User → Watch Rewarded Ad (AdMob)
     → Backend unlocks feature for 1 hour
     → User gets: task booster / roadmap peek / skill unlock
```

### Premium ($15.99/mo or $99.99/yr)
```
User → Clicks Upgrade → Payment screen
     → Backend initiates Flutterwave payment
     → User redirected to payment page
     → On success: webhook fires → subscription activated
     → All features permanently unlocked
```

---

## 🤖 AI FLOW

```
User message
    ↓
API injects user context (stage, income, skills, goals)
    ↓
Try Groq (Llama 3.1 70B) — FREE, fast
    ↓ (if fails)
Try Gemini Flash — FREE
    ↓ (if fails)
Try Cohere Command R — FREE
    ↓ (if fails)
Try OpenAI GPT-4o Mini — paid
    ↓ (if fails)
Try Anthropic Claude Haiku — paid
    ↓
Response streamed back to Flutter
    ↓
Message saved to Supabase
    ↓
(If onboarding mode) → Profile extracted + tasks generated
```

---

## 🌍 GLOBAL SUPPORT

- **Currencies**: NGN, USD, GBP, EUR, GHS, KES, ZAR, CAD, AUD, INR
- **Payments**: Flutterwave (190+ countries, debit/credit)
- **Language**: English (multilingual ready)
- **Regions**: Nigeria-first, globally scalable

---

*ChAs Tech Group — Building the next generation of wealth builders 🚀*
