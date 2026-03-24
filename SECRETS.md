# RiseUp — Production Secrets & CI/CD Setup Guide
> ChAs Tech Group | All values marked `sync: false` must be set manually.

---

## 1. GitHub Actions Secrets

Go to: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

### 🔴 Required for ALL builds
| Secret | Description | Where to get it |
|--------|-------------|-----------------|
| `SUPABASE_URL` | Your Supabase project URL | Supabase Dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Supabase anonymous/public key | Supabase Dashboard → Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key (server-only) | Supabase Dashboard → Settings → API |
| `API_BASE_URL` | Deployed backend URL | `https://riseup-api.onrender.com/api/v1` |

### 🤖 AI Keys (at least ONE required)
| Secret | Free tier? | Where to get it |
|--------|-----------|-----------------|
| `GROQ_API_KEY` | ✅ Free | https://console.groq.com |
| `OPENROUTER_API_KEY` | ✅ Free tier | https://openrouter.ai/keys |
| `GEMINI_API_KEY` | ✅ Free | https://aistudio.google.com |
| `COHERE_API_KEY` | ✅ Free tier | https://dashboard.cohere.com |
| `OPENAI_API_KEY` | 💰 Paid | https://platform.openai.com |
| `ANTHROPIC_API_KEY` | 💰 Paid | https://console.anthropic.com |

### 💳 Payments (Flutterwave)
| Secret | Description | Where to get it |
|--------|-------------|-----------------|
| `FLUTTERWAVE_PUBLIC_KEY` | Public key | https://dashboard.flutterwave.com → Settings → API |
| `FLUTTERWAVE_SECRET_KEY` | Secret key | Same as above |
| `FLUTTERWAVE_ENCRYPTION_KEY` | Encryption key | Same as above |
| `FLUTTERWAVE_WEBHOOK_HASH` | Webhook hash for signature verification | Flutterwave → Settings → Webhooks |

### 📱 AdMob (Android & iOS)
| Secret | Description |
|--------|-------------|
| `ADMOB_APP_ID` | Your AdMob App ID — e.g. `ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX` |
| `ADMOB_REWARDED_AD_UNIT` | Rewarded ad unit ID |
| `ADMOB_BANNER_AD_UNIT` | Banner ad unit ID |
| `ADMOB_INTERSTITIAL_AD_UNIT` | Interstitial ad unit ID |
| `ADMOB_APP_OPEN_AD_UNIT` | App open ad unit ID |

> Get all from: https://apps.admob.com → Apps → Your App → Ad Units

### 🤖 Android Build Signing
| Secret | Description |
|--------|-------------|
| `KEYSTORE_BASE64` | Base64-encoded `.jks` keystore file |
| `KEY_ALIAS` | Key alias from your keystore |
| `KEY_PASSWORD` | Key password |
| `STORE_PASSWORD` | Keystore store password |
| `GOOGLE_SERVICES_JSON` | Base64-encoded `google-services.json` from Firebase |

**Generate & encode keystore:**
```bash
# 1. Generate keystore (run once, store safely)
keytool -genkey -v -keystore riseup-release.jks \
  -alias riseup -keyalg RSA -keysize 2048 -validity 10000

# 2. Base64 encode it for GitHub secret
base64 -w 0 riseup-release.jks

# 3. Base64 encode google-services.json
base64 -w 0 google-services.json
```

### 🍎 iOS Build Signing
| Secret | Description |
|--------|-------------|
| `IOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate |
| `IOS_CERTIFICATE_PASSWORD` | Certificate password |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Any random password for CI keychain (e.g. `openssl rand -base64 16`) |
| `IOS_EXPORT_OPTIONS_PLIST` | Base64-encoded ExportOptions.plist |
| `GOOGLE_SERVICE_INFO_PLIST` | Base64-encoded `GoogleService-Info.plist` from Firebase |

**Encode for GitHub:**
```bash
base64 -w 0 Certificates.p12
base64 -w 0 RiseUp_AppStore.mobileprovision
base64 -w 0 GoogleService-Info.plist
```

### 🚀 Render Deploy
| Secret | Description |
|--------|-------------|
| `RENDER_API_KEY` | Render API key | https://dashboard.render.com → Account → API Keys |
| `RENDER_SERVICE_ID` | Your backend service ID | Render Dashboard → Your service → URL contains the ID (`srv-XXXX`) |

### 🗄️ Supabase Migrations
| Secret | Description |
|--------|-------------|
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token | https://supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_ID` | Your project reference ID | Supabase Dashboard → Settings → General (`abcdefghijklmnop`) |
| `SUPABASE_DB_PASSWORD` | Database password | Set when creating project, resettable in Settings → Database |

---

## 2. Render Environment Variables

Go to: **Render Dashboard → riseup-api service → Environment**

All variables from `render.yaml` with `sync: false` must be added manually.
Use the same values as the GitHub secrets above.

Additionally set:
```
FRONTEND_URL = https://riseup-web.onrender.com   # or your custom domain
ALLOWED_ORIGINS = https://riseup-web.onrender.com,https://yourdomain.com
```

---

## 3. Supabase Setup Steps

1. Create project at https://supabase.com
2. Run migrations: `supabase db push` (or paste SQL from `supabase/migrations/` into SQL Editor)
3. Enable **Email Auth** in Authentication → Providers
4. Set **Site URL** in Authentication → URL Configuration to your frontend URL
5. Add redirect URL: `https://riseup-web.onrender.com/reset-password`
6. Enable **Row Level Security** — already set in migrations
7. Deploy edge functions: `supabase functions deploy check-subscriptions welcome-email`

---

## 4. AdSense (Web)

1. Sign up at https://adsense.google.com
2. Add your site and get approved
3. Replace `ca-pub-XXXXXXXXXXXXXXXX` in `frontend/web/index.html` with your Publisher ID
4. Replace `XXXXXXXXXX` ad slot IDs with your actual slot IDs

---

## 5. Quick Checklist Before Going Live

- [ ] Supabase migrations applied
- [ ] `SUPABASE_URL` + keys set on Render
- [ ] At least one AI key set (`GROQ_API_KEY` recommended — free)
- [ ] Flutterwave keys set on Render
- [ ] `ALLOWED_ORIGINS` set to your actual domain(s)
- [ ] `FRONTEND_URL` set to your actual frontend URL
- [ ] AdMob app IDs replaced in `app_constants.dart` (not test IDs)
- [ ] `google-services.json` replaced with real Firebase file
- [ ] `GoogleService-Info.plist` replaced with real Firebase file
- [ ] Android keystore generated and secrets added to GitHub
- [ ] `APP_SECRET_KEY` auto-generated by Render (`generateValue: true`)
