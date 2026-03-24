// ─────────────────────────────────────────────────────────────
//  Abstract interface — shared by mobile & web implementations
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

abstract class AdServiceBase {
  Future<void> initialize();
  Future<bool> showRewardedAd({
    required String featureKey,
    required Function onRewarded,
    required Function onDismissed,
  });
  Future<void> showInterstitialIfReady();
  Future<void> showAppOpenAdIfAvailable();
  bool get isRewardedReady;
}

// Placeholder banner — used on web (shows nothing but holds space cleanly)
class BannerAdPlaceholder extends StatelessWidget {
  final double height;
  const BannerAdPlaceholder({super.key, this.height = 0});
  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
