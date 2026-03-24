// ─────────────────────────────────────────────────────────────
//  Web Ad Service — Google AdSense (injected via web/index.html)
//  Rewarded / Interstitial / AppOpen → no-op on web (AdSense
//  handles placements automatically via Auto Ads in index.html)
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  @override
  Future<void> initialize() async {
    // AdSense is injected in web/index.html — nothing to do here
  }

  @override
  bool get isRewardedReady => true; // web: always grant immediately

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required Function onRewarded,
    required Function onDismissed,
  }) async {
    // Web doesn't support rewarded ads — grant the reward immediately
    // so the UX is not blocked. Real monetisation comes from AdSense banners.
    onRewarded();
    return true;
  }

  @override
  Future<void> showInterstitialIfReady() async {
    // AdSense Auto Ads manages interstitials on web
  }

  @override
  Future<void> showAppOpenAdIfAvailable() async {
    // AdSense Auto Ads manages overlays on web
  }
}

final adService = AdService();

// ── Web BannerAdWidget ────────────────────────────────────────
// Real AdSense banners are in web/index.html (top + bottom).
// Return empty here to avoid double-showing ads inside the canvas.
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
