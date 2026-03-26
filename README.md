# RiseUp v3 — Size & Launch Icon Fix

## Files — copy to your repo:

| File in zip | Destination |
|---|---|
| `lib/screens/auth/splash_screen.dart` | `frontend/lib/screens/auth/splash_screen.dart` |
| `lib/screens/auth/login_screen.dart` | `frontend/lib/screens/auth/login_screen.dart` |
| `lib/screens/auth/register_screen.dart` | `frontend/lib/screens/auth/register_screen.dart` |
| `android/app/src/main/res/values/styles.xml` | `frontend/android/app/src/main/res/values/styles.xml` |
| `android/app/src/main/res/drawable/launch_background.xml` | `frontend/android/app/src/main/res/drawable/launch_background.xml` |

## What changed

1. **Splash logo** — 160×160 (was 110×110), bigger
2. **Splash RiseUp text** — font size 52 (was 40), bigger
3. **Logo + text closer** — gap reduced to 10px (was 16px)
4. **Login/Register logo** — 52×52 (was 40×40), bigger
5. **Login/Register RiseUp text** — font size 34 (was 26), bigger
6. **Android launch icon** — pure black background, no white icon shown
