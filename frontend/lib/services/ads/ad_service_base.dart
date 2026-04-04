// lib/services/ads/ad_service_base.dart
// ─────────────────────────────────────────────────────────────
//  AdServiceBase — Single contract that EVERY platform must
//  implement.  Adding a method here forces the compiler to
//  remind you to stub it on web too — no more runtime gaps.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

abstract class AdServiceBase {
  // ── Lifecycle ──────────────────────────────────────────────
  Future<void> initialize();

  // ── Rewarded ───────────────────────────────────────────────
  bool get isRewardedReady;

  Future<bool> showRewardedAd({
    required String featureKey,
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
  });

  // ── Interstitial ───────────────────────────────────────────
  Future<void> showInterstitialIfReady();

  /// Force-shows an interstitial regardless of cooldown.
  /// No-op on web (AdMob not supported).
  Future<void> forceShowInterstitial();

  // ── App Open ───────────────────────────────────────────────
  Future<void> showAppOpenAdIfAvailable();

  // ── Banner ─────────────────────────────────────────────────
  /// Inline banner widget (e.g. inside a list).
  Widget getBannerWidget();

  /// Sticky bottom banner widget (anchored to scaffold bottom).
  /// Returns [SizedBox.shrink] on web / premium users.
  Widget getStickyBanner(BuildContext context);

  // ── Native ─────────────────────────────────────────────────
  Widget? getNativeWidget();

  // ── Cleanup ────────────────────────────────────────────────
  void dispose();
}
