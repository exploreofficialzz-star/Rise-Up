// ─────────────────────────────────────────────────────────────
//  Platform-conditional export
//  • Mobile (Android/iOS) → ads/ad_service_mobile.dart  (AdMob)
//  • Web                  → ads/ad_service_web.dart      (stubs)
// ─────────────────────────────────────────────────────────────
export 'ads/ad_service_mobile.dart'
    if (dart.library.html) 'ads/ad_service_web.dart';
