# 🔐 GitHub Secrets Setup Guide

## Overview
All sensitive configuration is stored in GitHub Secrets — never in code.

Go to: **GitHub Repo → Settings → Secrets and variables → Actions → New repository secret**

---

## 🔑 Required Secrets

### Supabase
| Secret Name | Where to Get |
|---|---|
| `SUPABASE_URL` | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API → anon/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard → Settings → API → service_role key |
| `SUPABASE_ACCESS_TOKEN` | [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) |
| `SUPABASE_PROJECT_ID` | Supabase Dashboard → Settings → General → Reference ID |
| `SUPABASE_DB_PASSWORD` | Set when creating project |

### AI Models (Add at least one FREE option)
| Secret Name | Where to Get | Cost |
|---|---|---|
| `GROQ_API_KEY` | [console.groq.com](https://console.groq.com) | **FREE** |
| `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com) | **FREE** |
| `COHERE_API_KEY` | [dashboard.cohere.com](https://dashboard.cohere.com) | **FREE** |
| `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com) | Paid |
| `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) | Paid |

### Render (Backend Hosting)
| Secret Name | Where to Get |
|---|---|
| `RENDER_API_KEY` | [dashboard.render.com/u/account#api-keys](https://dashboard.render.com/u/account#api-keys) |
| `RENDER_SERVICE_ID` | Render Dashboard → Your Service → URL contains the ID (e.g. `srv-xxxxx`) |
| `RENDER_API_URL` | Your Render API URL (e.g. `https://riseup-api.onrender.com`) |

### Flutterwave (Payments)
| Secret Name | Where to Get |
|---|---|
| `FLUTTERWAVE_PUBLIC_KEY` | [dashboard.flutterwave.com](https://dashboard.flutterwave.com) → Settings → API |
| `FLUTTERWAVE_SECRET_KEY` | Same as above |
| `FLUTTERWAVE_ENCRYPTION_KEY` | Same as above |
| `FLUTTERWAVE_WEBHOOK_HASH` | Set in Flutterwave dashboard when configuring webhooks |

### AdMob (Ads)
| Secret Name | Where to Get |
|---|---|
| `ADMOB_APP_ID` | [apps.admob.com](https://apps.admob.com) → App settings |
| `ADMOB_REWARDED_UNIT` | AdMob → Ad units → Rewarded ad unit ID |

### Flutter App Config
| Secret Name | Value |
|---|---|
| `API_BASE_URL` | Your Render URL + `/api/v1` e.g. `https://riseup-api.onrender.com/api/v1` |

### Android Signing (for release builds)
| Secret Name | How to Generate |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w 0 your-keystore.jks` |
| `ANDROID_KEY_ALIAS` | Alias you chose when creating keystore |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_STORE_PASSWORD` | Store password |

**Generate keystore:**
```bash
keytool -genkey -v \
  -keystore riseup-release.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias riseup \
  -dname "CN=RiseUp, OU=ChAs Tech Group, O=ChAs Tech Group, L=Lagos, ST=Lagos, C=NG"
```

### Firebase (Push Notifications - Optional)
| Secret Name | Where to Get |
|---|---|
| `GOOGLE_SERVICES_JSON` | Firebase Console → Project Settings → google-services.json → copy entire file content |

---

## 🚀 Setup Order

1. **Create Supabase project** → get URL, anon key, service role key
2. **Run migration** → paste `supabase/migrations/001_initial_schema.sql` in Supabase SQL Editor
3. **Get free AI keys** → Groq (recommended), Gemini, Cohere
4. **Deploy to Render** → connect GitHub repo, add env vars from `.env.example`
5. **Add GitHub Secrets** → all the above
6. **Push to main** → auto-deploy triggers!
7. **Get AdMob ID** → create app in AdMob console
8. **Get Flutterwave keys** → create account, add test keys first

---

## 💡 Minimum Required to Start

Just these 4 secrets get you running:
1. `SUPABASE_URL`
2. `SUPABASE_ANON_KEY`
3. `SUPABASE_SERVICE_ROLE_KEY`
4. `GROQ_API_KEY` (free)

Everything else is optional/can be added later.
