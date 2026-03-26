# 🚀 RiseUp Deployment Guide
## ChAs Tech Group — Complete Step-by-Step

---

## PHASE 1 — Supabase Setup (15 min)

### Step 1: Create Supabase Project
1. Go to [supabase.com](https://supabase.com) → Sign up free
2. Click **New Project**
3. Name: `riseup-prod`, choose a strong DB password, pick nearest region
4. Wait for project to initialize (~2 min)

### Step 2: Run Database Migrations
1. In Supabase Dashboard → **SQL Editor** → **New Query**
2. Open `supabase/migrations/001_initial_schema.sql`
3. **Paste entire file** → Click **Run**
4. Open `supabase/migrations/002_rpc_functions.sql`
5. **Paste entire file** → Click **Run**
6. Verify: go to **Table Editor** — you should see all tables

### Step 3: Copy Supabase Keys
Go to **Settings → API** and save these:
- `Project URL` → this is your `SUPABASE_URL`
- `anon / public` key → `SUPABASE_ANON_KEY`
- `service_role` key → `SUPABASE_SERVICE_ROLE_KEY` **(keep secret!)**

---

## PHASE 2 — Get Free AI Keys (10 min)

### Groq (Primary — Fastest, Free)
1. Go to [console.groq.com](https://console.groq.com)
2. Sign up → **API Keys** → **Create API Key**
3. Copy key → `GROQ_API_KEY`

### Google Gemini (Secondary — Free)
1. Go to [aistudio.google.com](https://aistudio.google.com)
2. Sign in → **Get API Key** → **Create API Key**
3. Copy key → `GEMINI_API_KEY`

### Cohere (Tertiary — Free)
1. Go to [dashboard.cohere.com](https://dashboard.cohere.com)
2. Sign up → **API Keys** → copy trial key
3. Copy key → `COHERE_API_KEY`

> **You only NEED one key.** Groq alone is enough to start.

---

## PHASE 3 — Flutterwave Setup (10 min)

1. Go to [dashboard.flutterwave.com](https://dashboard.flutterwave.com) → Sign up
2. Complete business verification (can use **Test Mode** to start)
3. Go to **Settings → API** → copy:
   - `Public Key` → `FLUTTERWAVE_PUBLIC_KEY`
   - `Secret Key` → `FLUTTERWAVE_SECRET_KEY`
   - `Encryption Key` → `FLUTTERWAVE_ENCRYPTION_KEY`
4. Go to **Settings → Webhooks** → Add webhook:
   - URL: `https://your-render-url.onrender.com/api/v1/payments/webhook`
   - Secret Hash: choose a random string → `FLUTTERWAVE_WEBHOOK_HASH`

---

## PHASE 4 — AdMob Setup (10 min)

1. Go to [apps.admob.com](https://apps.admob.com) → Sign up
2. **Add App** → Android → Enter "RiseUp" → **Add**
3. Copy **App ID** (format: `ca-app-pub-xxxxxxxx~xxxxxxxxxx`) → `ADMOB_APP_ID`
4. **Create Ad Unit** → Rewarded → Name "Task Unlock"
5. Copy **Ad Unit ID** (format: `ca-app-pub-xxxxxxxx/xxxxxxxxxx`) → `ADMOB_REWARDED_UNIT`

> Use test IDs during development:
> - App ID: `ca-app-pub-3940256099942544~3347511713`
> - Rewarded: `ca-app-pub-3940256099942544/5224354917`

---

## PHASE 5 — Firebase Setup (for push notifications, 10 min)

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. **Create Project** → name "riseup-prod"
3. **Add Android App** → Package: `com.chastech.riseup`
4. Download `google-services.json`
5. Copy entire file content → `GOOGLE_SERVICES_JSON` GitHub Secret

---

## PHASE 6 — Deploy Backend to Render (10 min)

### Option A: Auto-deploy with render.yaml (Recommended)
1. Push your code to GitHub
2. Go to [render.com](https://render.com) → **New → Blueprint**
3. Connect your GitHub repo → Render detects `render.yaml`
4. Add all environment variables
5. Click **Apply** → deployment starts automatically

### Option B: Manual Render setup
1. [render.com](https://render.com) → **New → Web Service**
2. Connect GitHub repo
3. Settings:
   - **Name**: `riseup-api`
   - **Root Directory**: `backend`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT --workers 2`
4. **Environment Variables** — Add ALL from `.env.example`
5. Click **Create Web Service**

### Verify deployment
- Visit: `https://riseup-api.onrender.com/`
- Visit: `https://riseup-api.onrender.com/health`
- Visit: `https://riseup-api.onrender.com/docs` (API documentation)

---

## PHASE 7 — GitHub Secrets (10 min)

Go to **GitHub Repo → Settings → Secrets and variables → Actions**

Add these secrets (see `SECRETS.md` for full list):

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | From Phase 1 |
| `SUPABASE_ANON_KEY` | From Phase 1 |
| `SUPABASE_SERVICE_ROLE_KEY` | From Phase 1 |
| `GROQ_API_KEY` | From Phase 2 |
| `GEMINI_API_KEY` | From Phase 2 |
| `FLUTTERWAVE_PUBLIC_KEY` | From Phase 3 |
| `FLUTTERWAVE_SECRET_KEY` | From Phase 3 |
| `FLUTTERWAVE_WEBHOOK_HASH` | From Phase 3 |
| `ADMOB_APP_ID` | From Phase 4 |
| `ADMOB_REWARDED_UNIT` | From Phase 4 |
| `GOOGLE_SERVICES_JSON` | From Phase 5 |
| `RENDER_API_KEY` | Render Dashboard → Account → API Keys |
| `RENDER_SERVICE_ID` | From Render service URL (srv-xxxxx) |
| `RENDER_API_URL` | `https://riseup-api.onrender.com` |
| `API_BASE_URL` | `https://riseup-api.onrender.com/api/v1` |

---

## PHASE 8 — Android Signing (5 min)

Generate a release keystore (do this ONCE — back it up!):

```bash
keytool -genkey -v \
  -keystore riseup-release.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias riseup \
  -dname "CN=RiseUp, OU=ChAs Tech, O=ChAs Tech Group, L=Lagos, ST=Lagos, C=NG"
```

Then add to GitHub Secrets:
```bash
# On Mac/Linux:
base64 -w 0 riseup-release.jks
# Copy the output → ANDROID_KEYSTORE_BASE64

# ANDROID_KEY_ALIAS = riseup
# ANDROID_KEY_PASSWORD = (password you chose)
# ANDROID_STORE_PASSWORD = (password you chose)
```

---

## PHASE 9 — First Deploy!

```bash
git add .
git commit -m "feat: initial RiseUp release 🚀"
git push origin main
```

GitHub Actions will automatically:
1. ✅ Run backend tests
2. 🌐 Deploy backend to Render
3. 🏗️ Build Android APK + AAB
4. 📦 Create GitHub Release with download links

Check progress in: **GitHub → Actions tab**

---

## PHASE 10 — Local Development

```bash
# Run setup script
chmod +x setup.sh && ./setup.sh

# Start backend (separate terminal)
cd backend
cp .env.example .env
# Edit .env with your keys
uvicorn main:app --reload --port 8000

# Run Flutter (separate terminal)
cd frontend
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ADMOB_APP_ID=ca-app-pub-3940256099942544~3347511713

# Docker compose (runs everything together)
cp backend/.env.example backend/.env  # fill in your keys
docker-compose up
```

---

## ✅ Checklist

- [ ] Supabase project created
- [ ] Both SQL migrations run
- [ ] At least 1 free AI key added (Groq recommended)
- [ ] Backend deployed to Render and health check passes
- [ ] GitHub Secrets all configured
- [ ] Android keystore generated and backed up
- [ ] First push to main triggered successful GitHub Actions
- [ ] APK downloaded and tested on physical device
- [ ] Flutterwave webhook URL configured
- [ ] AdMob app created (can use test IDs initially)

---

## 🆘 Troubleshooting

**Backend won't start on Render:**
- Check environment variables are all set
- Check Render logs for Python errors
- Verify `SUPABASE_URL` doesn't have trailing slash

**Flutter build fails:**
- Run `flutter clean && flutter pub get` first
- Ensure Java 17 is set: `export JAVA_HOME=$(/usr/libexec/java_home -v17)`
- Check `ADMOB_APP_ID` is set in secrets

**AI not responding:**
- Verify at least one AI key is set
- Check `/health` endpoint shows available models
- Groq free tier has rate limits — add Gemini as backup

**Payments not working:**
- Use Flutterwave test mode first
- Verify webhook URL is correct in Flutterwave dashboard
- Check `FLUTTERWAVE_WEBHOOK_HASH` matches dashboard setting

---

*Built by ChAs Tech Group — Let's rise together! 🚀*
