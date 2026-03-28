// ─────────────────────────────────────────────────────────────────
// RiseUp Ad System — PRODUCTION READY
// Enhanced with real AdMob integration + frequency capping
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../config/app_constants.dart';
import '../services/api_service.dart';
import '../services/ad_service.dart';

// ═════════════════════════════════════════════════════════════════
// AD CONFIG — Server-controlled with local fallback
// ═════════════════════════════════════════════════════════════════

class AdConfig {
  static bool adsEnabled = true;
  static bool isPremium = false;
  static int feedAdFrequency = 5;
  static int maxInterstitialsPerHour = 3;
  static int maxRewardedPerDay = 10;

  static Future<void> load() async {
    try {
      final data = await api.get('/ads/config');
      adsEnabled = data['ads_enabled'] == true;
      isPremium = data['user_is_premium'] == true;
      feedAdFrequency = (data['placements']?['feed']?['frequency'] as num?)?.toInt() ?? 5;
      maxInterstitialsPerHour = (data['placements']?['interstitial']?['max_per_hour'] as num?)?.toInt() ?? 3;
      maxRewardedPerDay = (data['placements']?['rewarded']?['max_per_day'] as num?)?.toInt() ?? 10;
    } catch (_) {
      // Use defaults on error
    }
  }

  static bool get shouldShowAds => adsEnabled && !isPremium;
}

// ═════════════════════════════════════════════════════════════════
// FEED AD CARD — Native-style promo (every N posts)
// ═════════════════════════════════════════════════════════════════

class FeedAdCard extends StatelessWidget {
  final bool isDark;
  final Color cardColor, borderColor, textColor, subColor;
  
  const FeedAdCard({
    super.key,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    // Track impression
    api.post('/ads/impression', {
      'ad_id': 'feed_promo',
      'placement': 'feed',
    }).catchError((_) => {});

    return Container(
      color: cardColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Sponsored',
                  style: TextStyle(
                    fontSize: 9,
                    color: subColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('💼', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unlock Your Full Earning Potential',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'RiseUp Premium — Unlimited AI + Zero Ads',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Join 50,000+ wealth builders. Unlimited AI, full Workflow Engine, and zero ads.',
            style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    api.post('/ads/action', {
                      'ad_id': 'feed_promo',
                      'placement': 'feed',
                      'action': 'click',
                    }).catchError((_) => {});
                    context.go('/premium');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'Get Premium — Ad-Free',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => api.post('/ads/action', {
                  'ad_id': 'feed_promo',
                  'placement': 'feed',
                  'action': 'dismiss',
                }).catchError((_) => {}),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Skip', style: TextStyle(color: subColor, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// SCREEN BANNER — Sticky bottom banner
// ═════════════════════════════════════════════════════════════════

class ScreenBannerAd extends StatelessWidget {
  final bool isDark;
  
  const ScreenBannerAd({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    api.post('/ads/impression', {
      'ad_id': 'screen_banner',
      'placement': 'screen_banner',
    }).catchError((_) => {});

    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () {
          api.post('/ads/action', {
            'ad_id': 'screen_banner',
            'placement': 'screen_banner',
            'action': 'click',
          }).catchError((_) => {});
          context.go('/premium');
        },
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Text('⭐', style: TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remove all ads — Go Premium',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  Text(
                    'Unlimited AI · Full Workflow · Ad-Free',
                    style: TextStyle(fontSize: 10, color: sub),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// REAL BANNER AD — AdMob Banner (Production)
// ═════════════════════════════════════════════════════════════════

class RealBannerAd extends StatefulWidget {
  final bool isDark;
  final EdgeInsetsGeometry padding;
  
  const RealBannerAd({
    super.key,
    required this.isDark,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<RealBannerAd> createState() => _RealBannerAdState();
}

class _RealBannerAdState extends State<RealBannerAd> {
  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    return Container(
      color: widget.isDark ? AppColors.bgCard : Colors.white,
      padding: widget.padding,
      child: adService.getBannerWidget(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// NATIVE AD WIDGET — AdMob Native (Production)
// ═════════════════════════════════════════════════════════════════

class NativeInlineAd extends StatefulWidget {
  final bool isDark;
  
  const NativeInlineAd({super.key, required this.isDark});

  @override
  State<NativeInlineAd> createState() => _NativeInlineAdState();
}

class _NativeInlineAdState extends State<NativeInlineAd> {
  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    final widget = adService.getNativeWidget();
    if (widget == null) return const SizedBox.shrink();

    return Container(
      color: widget.isDark ? AppColors.bgCard : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: widget,
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// INTERSTITIAL TRIGGER — Auto-show on navigation (with capping)
// ═════════════════════════════════════════════════════════════════

class InterstitialGate extends StatefulWidget {
  final Widget child;
  final String placement;
  
  const InterstitialGate({
    super.key,
    required this.child,
    this.placement = 'default',
  });

  @override
  State<InterstitialGate> createState() => _InterstitialGateState();
}

class _InterstitialGateState extends State<InterstitialGate> {
  @override
  void initState() {
    super.initState();
    _maybeShowAd();
  }

  Future<void> _maybeShowAd() async {
    if (!AdConfig.shouldShowAds) return;
    
    // Track and show via ad service (which has its own frequency capping)
    await adService.showInterstitialIfReady();
    
    // Track impression
    api.post('/ads/impression', {
      'ad_id': 'interstitial',
      'placement': widget.placement,
    }).catchError((_) => {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ═════════════════════════════════════════════════════════════════
// REWARDED AD BUTTON — Watch ad to unlock feature
// ═════════════════════════════════════════════════════════════════

class RewardedAdButton extends StatefulWidget {
  final String featureKey;
  final String featureName;
  final VoidCallback onRewarded;
  final bool isDark;
  
  const RewardedAdButton({
    super.key,
    required this.featureKey,
    required this.featureName,
    required this.onRewarded,
    required this.isDark,
  });

  @override
  State<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends State<RewardedAdButton> {
  bool _loading = false;

  Future<void> _watchAd() async {
    if (_loading) return;
    
    setState(() => _loading = true);
    
    final success = await adService.showRewardedAd(
      featureKey: widget.featureKey,
      onRewarded: () {
        if (mounted) {
          setState(() => _loading = false);
          widget.onRewarded();
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${widget.featureName} unlocked!'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      onDismissed: () {
        if (mounted) setState(() => _loading = false);
      },
    );

    if (!success && mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad not available. Try again later.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    return ElevatedButton.icon(
      onPressed: _loading ? null : _watchAd,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.success,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.play_circle_filled_rounded, color: Colors.white),
      label: Text(
        _loading ? 'Loading ad...' : 'Watch Ad — Unlock Free',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// FEATURE GATE SHEET — Bottom sheet for limit reached
// ═════════════════════════════════════════════════════════════════

class FeatureGateSheet extends StatefulWidget {
  final String feature;
  final String featureName;
  final VoidCallback onUnlocked;
  final bool isDark;
  
  const FeatureGateSheet({
    super.key,
    required this.feature,
    required this.featureName,
    required this.onUnlocked,
    required this.isDark,
  });

  static Future<void> show(
    BuildContext context, {
    required String feature,
    required String featureName,
    required VoidCallback onUnlocked,
    required bool isDark,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeatureGateSheet(
        feature: feature,
        featureName: featureName,
        onUnlocked: onUnlocked,
        isDark: isDark,
      ),
    );
  }

  @override
  State<FeatureGateSheet> createState() => _FeatureGateSheetState();
}

class _FeatureGateSheetState extends State<FeatureGateSheet> {
  bool _loading = false;

  Future<void> _watchAd() async {
    setState(() => _loading = true);
    
    await adService.showRewardedAd(
      featureKey: '${widget.feature}_rewarded',
      onRewarded: () {
        if (mounted) {
          Navigator.pop(context);
          widget.onUnlocked();
        }
      },
      onDismissed: () {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? AppColors.bgCard : Colors.white;
    final text = widget.isDark ? Colors.white : Colors.black87;
    final sub = widget.isDark ? Colors.white54 : Colors.black45;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🔒', style: TextStyle(fontSize: 32))),
            ),
            const SizedBox(height: 16),
            Text(
              'Daily Limit Reached',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve used all your free ${widget.featureName.toLowerCase()} today.\nWatch a short ad to unlock more, or upgrade.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: sub, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: RewardedAdButton(
                featureKey: widget.feature,
                featureName: widget.featureName,
                onRewarded: () {
                  Navigator.pop(context);
                  widget.onUnlocked();
                },
                isDark: widget.isDark,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  context.go('/premium');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      '⭐ Go Premium — Ad-Free + Unlimited',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Maybe later', style: TextStyle(color: sub, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// USAGE LIMIT BANNER — Warning near limit
// ═════════════════════════════════════════════════════════════════

class UsageLimitBanner extends StatelessWidget {
  final int remaining;
  final int total;
  final String featureName;
  final bool isDark;
  
  const UsageLimitBanner({
    super.key,
    required this.remaining,
    required this.total,
    required this.featureName,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds || remaining > total ~/ 2) {
      return const SizedBox.shrink();
    }

    final isLow = remaining <= 1;
    final color = isLow ? AppColors.error : AppColors.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(isLow ? '⚠️' : '💡', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isLow
                  ? '$remaining $featureName left today — watch an ad for more'
                  : '$remaining $featureName remaining today',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/premium'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// PREMIUM BANNER — Upsell for free users
// ═════════════════════════════════════════════════════════════════

class PremiumUpsellBanner extends StatelessWidget {
  final bool isDark;
  
  const PremiumUpsellBanner({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.accent.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Text('👑', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Go Premium',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    Text(
                      'Remove ads + unlimited features',
                      style: TextStyle(fontSize: 12, color: sub),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/premium'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Upgrade Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
