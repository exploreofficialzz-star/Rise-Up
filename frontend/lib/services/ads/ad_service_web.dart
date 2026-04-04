// lib/services/ads/ad_service_web.dart
// ─────────────────────────────────────────────────────────────
//  Web Ad Service — Complete no-op stubs.
//
//  AdMob / Google Mobile Ads SDK is NOT supported on Flutter Web.
//  Every method here is a safe, typed stub so dart2js never sees
//  an undefined symbol.  AdSense (if needed) → inject in index.html.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  // ── Singleton ──────────────────────────────────────────────
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  // ── Lifecycle ──────────────────────────────────────────────
  @override
  Future<void> initialize() async {}

  // ── Rewarded ───────────────────────────────────────────────
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

  // ── Interstitial ───────────────────────────────────────────
  @override
  Future<void> showInterstitialIfReady() async {}

  /// No-op on web — forceShowInterstitial needs native AdMob SDK.
  @override
  Future<void> forceShowInterstitial() async {}

  // ── App Open ───────────────────────────────────────────────
  @override
  Future<void> showAppOpenAdIfAvailable() async {}

  // ── Banner ─────────────────────────────────────────────────
  @override
  Widget getBannerWidget() => const SizedBox.shrink();

  /// No sticky banner on web — returns empty widget.
  @override
  Widget getStickyBanner(BuildContext context) => const SizedBox.shrink();

  // ── Native ─────────────────────────────────────────────────
  @override
  Widget? getNativeWidget() => null;

  // ── Cleanup ────────────────────────────────────────────────
  @override
  void dispose() {}
}

/// Global singleton — mirrors the mobile export so all call-sites
/// are identical across platforms.
final adService = AdService();
