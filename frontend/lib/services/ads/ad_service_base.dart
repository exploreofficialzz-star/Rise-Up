// ─────────────────────────────────────────────────────────────
//  Abstract interface — shared by mobile & web implementations
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

abstract class AdServiceBase {
  Future<void> initialize();
  
  Future<bool> showRewardedAd({
    required String featureKey,
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
  });
  
  Future<void> showInterstitialIfReady();
  Future<void> showAppOpenAdIfAvailable();
  
  bool get isRewardedReady;
}

// Placeholder widgets for web (shows nothing cleanly)
class BannerAdPlaceholder extends StatelessWidget {
  final double height;
  const BannerAdPlaceholder({super.key, this.height = 0});
  
  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

class NativeAdPlaceholder extends StatelessWidget {
  final double height;
  const NativeAdPlaceholder({super.key, this.height = 0});
  
  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
