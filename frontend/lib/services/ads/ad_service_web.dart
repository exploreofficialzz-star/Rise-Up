// ─────────────────────────────────────────────────────────────
//  Web Ad Service — Stubs (AdMob not supported on web)
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  @override
  Future<void> initialize() async {
    // No ads on web
  }

  @override
  bool get isRewardedReady => false;

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
  }) async {
    onDismissed();
    return false;
  }

  @override
  Future<void> showInterstitialIfReady() async {
    // No-op on web
  }

  @override
  Future<void> showAppOpenAdIfAvailable() async {
    // No-op on web
  }

  Widget getBannerWidget() => const SizedBox.shrink();
  Widget? getNativeWidget() => null;
  void dispose() {}
}

final adService = AdService();
