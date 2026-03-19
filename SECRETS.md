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
| `ADMOB_BANNER_UNIT` | AdMob → Ad units → Banner ad unit ID (shown on Dashboard & Skills) |
| `ADMOB_INTERSTITIAL_UNIT` | AdMob → Ad units → Interstitial ad unit ID (shown after task completion) |
| `ADMOB_APP_OPEN_UNIT` | AdMob → Ad units → App open ad unit ID (shown on app launch) |

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

---

## 🌐 Web Deployment

### GitHub Pages (free)
| Secret/Variable | Value |
|---|---|
| `WEB_DOMAIN` | Your custom domain e.g. `app.riseup.com` (optional) |

### Render Web Static Site
| Secret | Value |
|---|---|
| `RENDER_WEB_SERVICE_ID` | Render → Your web static service → ID (e.g. `srv-xxxxx`) |
| `SUPABASE_URL` | Same as backend |
| `SUPABASE_ANON_KEY` | Same as backend |
| `API_BASE_URL` | `https://riseup-api.onrender.com/api/v1` |

---

## 🍎 iOS Build Secrets (optional — add when ready for App Store)
| Secret | How to Get |
|---|---|
| `IOS_CERTIFICATE_BASE64` | In Xcode: export .p12 cert → `base64 -i cert.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password you set when exporting |
| `IOS_PROVISIONING_PROFILE_BASE64` | Download from Apple Dev portal → `base64 -i profile.mobileprovision` |

> **Note:** iOS builds work without signing on CI. You only need signing certs to submit to the App Store.

---

## 📋 Platform Summary
| Platform | Build | Deploy | Ads |
|---|---|---|---|
| Android | GitHub Actions → APK/AAB | GitHub Releases | AdMob (all 4 types) |
| iOS | GitHub Actions (macOS) → .app | GitHub Artifacts | AdMob (all 4 types) |
| Web | GitHub Actions → static | GitHub Pages / Render | Google AdSense (add to index.html) |

---

## 🌐 Google AdSense (Web Ads)

> AdMob works on Android & iOS. AdSense works on the **website**.

### How to set up AdSense:
1. Go to [adsense.google.com](https://adsense.google.com) → Sign up
2. Add your website URL (your GitHub Pages or Render URL)
3. Wait for Google to approve your site (usually 1–3 days)
4. Once approved, go to **Ads → Ad Units** → Create 2 units:
   - **Top Banner** (Leaderboard 728×90 / Responsive)
   - **Bottom Banner** (Anchor / Responsive)
5. Copy the **Publisher ID** and **Ad Slot IDs**

### Where to paste them:
**1. In `web/index.html`** — replace every `ca-pub-XXXXXXXXXXXXXXXX` with your Publisher ID and `XXXXXXXXXX` with your slot IDs

**2. Add as GitHub Secrets** (for the build to inject them):
| Secret | Value |
|---|---|
| `ADSENSE_PUBLISHER_ID` | e.g. `ca-pub-1234567890123456` |
| `ADSENSE_TOP_SLOT` | e.g. `1234567890` |
| `ADSENSE_BOTTOM_SLOT` | e.g. `0987654321` |

### What ads appear on the website:
| Ad Type | Where | Format |
|---|---|---|
| **Top Banner** | Fixed bar at top of page | 728×90 desktop / 320×50 mobile |
| **Bottom Banner** | Fixed bar at bottom | 728×90 desktop / 320×50 mobile |
| **Auto Ads** | Google picks best spots automatically | Various |
| **Sticky Overlay** | Mobile bottom overlay | Auto |

> **Note:** AdSense requires your site to have real content and traffic before approval. Test with the placeholder IDs first, then swap in real ones after approval.
