# RiseUp Social — Full Update Package v2

## Files in this zip

### Copy these to your repo:

| File in zip | Destination in repo |
|---|---|
| `assets/images/riseup_logo.png` | `frontend/assets/images/riseup_logo.png` |
| `lib/widgets/app_text_field.dart` | `frontend/lib/widgets/app_text_field.dart` |
| `lib/screens/auth/splash_screen.dart` | `frontend/lib/screens/auth/splash_screen.dart` |
| `lib/screens/auth/login_screen.dart` | `frontend/lib/screens/auth/login_screen.dart` |
| `lib/screens/auth/register_screen.dart` | `frontend/lib/screens/auth/register_screen.dart` |
| `lib/screens/home/home_screen.dart` | `frontend/lib/screens/home/home_screen.dart` |
| `lib/screens/ai/post_ai_sheet.dart` | `frontend/lib/screens/ai/post_ai_sheet.dart` |
| `lib/screens/chat/chat_screen.dart` | `frontend/lib/screens/chat/chat_screen.dart` |
| `lib/main_shell.dart` | `frontend/lib/main_shell.dart` |
| `lib/config/router.dart` | `frontend/lib/config/router.dart` |

---

## IMPORTANT — Update pubspec.yaml

In `frontend/pubspec.yaml` find the assets section and add the png:

```yaml
  assets:
    - assets/images/
    - assets/images/riseup_logo.png
    - assets/animations/
    - assets/icons/
```

---

## What changed in this update

1. **Logo** — Transparent PNG (no black background)
2. **Input text color** — White in dark theme, black in light theme
3. **Navigation** — After login always goes to Home feed (not AI chat)
4. **Home AppBar** — Left side now has Message + Task buttons
5. **Splash** — Uses new transparent logo PNG
6. **Login/Register** — Logo shows without card container, clean design
