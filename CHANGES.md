# RiseUp — Fix & Performance Package
Generated: 2026-03-24

## Files Changed

### Backend
| File | Change |
|------|--------|
| `backend/main.py` | Startup lifespan warms Supabase connections; added `/ping` keep-alive endpoint |
| `backend/middleware/security.py` | Avatar uploads (≤6MB) exempt from 512KB body limit; version header fixed to 2.0.0 |
| `backend/routers/auth.py` | Uses `get_supabase_anon()` singleton — no more new client per request |
| `backend/routers/posts.py` | Feed has `has_more` flag; enrichment loop is O(n) set lookup instead of O(n×m) |
| `backend/routers/progress.py` | Leaderboard returns `self_rank` + `self_entry` even outside top-50 |
| `backend/migrations/migration_008_performance_indexes.sql` | **NEW** — 12 critical indexes for posts, likes, saves, follows, profiles, notifications |

### CI/CD
| File | Change |
|------|--------|
| `.github/workflows/android.yml` | APK build now passes all 5 AdMob dart-defines (was missing 4) |

### Flutter
| File | Change |
|------|--------|
| `frontend/lib/services/api_service.dart` | In-memory TTL cache for profile/stats/roadmap/streak; connect timeout 15s; `DioException` mapped to readable errors |
| `frontend/lib/providers/app_providers.dart` | Removed `autoDispose` from stable providers (profile, stats, roadmap, models, subscription) |
| `frontend/lib/utils/connectivity_wrapper.dart` | Full offline overlay with pulse animation; "back online" toast |
| `frontend/lib/main.dart` | `ConnectivityWrapper` wired into `MaterialApp.router` builder |
| `frontend/lib/main_shell.dart` | `MainShell.refresh()` static method; cleaner nav icons (white on dark / grey on light) |
| `frontend/lib/config/router.dart` | Acknowledges keyed `MainShell` |
| `frontend/lib/widgets/app_widgets.dart` | Added `PostSkeleton`, `StatCardSkeleton`, `ProfileHeaderSkeleton` shimmer widgets |
| `frontend/lib/widgets/stage_badge.dart` | Removed duplicate exports |
| `frontend/lib/widgets/stat_card.dart` | Removed duplicate exports |
| `frontend/lib/widgets/task_preview_card.dart` | Removed duplicate exports |
| `frontend/lib/screens/profile/edit_profile_screen.dart` | Full redesign: icon-label-input rows, grouped cards, theme-aware colors |
| `frontend/lib/screens/home/home_screen.dart` | Shimmer skeletons instead of spinners; `_hasMore` prevents infinite scroll on empty pages |
| `frontend/lib/screens/dashboard/dashboard_screen.dart` | Shimmer stat card skeletons during load |
| `frontend/lib/screens/notifications/notifications_screen.dart` | Calls `MainShell.refresh()` after reading — badge updates instantly |

## How to Deploy

### 1. Run the new migration in Supabase SQL Editor
```
backend/migrations/migration_008_performance_indexes.sql
```

### 2. Deploy backend to Render
Push `backend/` to main — GitHub Actions will deploy automatically.

### 3. Add UptimeRobot keep-alive (free)
- URL: `https://your-render-url.onrender.com/ping`
- Interval: 10 minutes
- This prevents 30s cold-start delays on the free Render tier.

### 4. Build Flutter
```bash
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=... \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=ADMOB_APP_ID=... \
  --dart-define=ADMOB_REWARDED_UNIT=... \
  --dart-define=ADMOB_BANNER_UNIT=... \
  --dart-define=ADMOB_INTERSTITIAL_UNIT=... \
  --dart-define=ADMOB_APP_OPEN_UNIT=...
```
