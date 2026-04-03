// frontend/lib/widgets/ad_widgets.dart
// v2.0 — FIX: FeedAdCard now shows a real AdMob BannerAd.
//
// Facebook/YouTube ad pattern implemented:
//  1. Try to load a real AdMob BannerAd (320×50 standard)
//  2. While loading → show the RiseUp Premium promo card (same as before)
//  3. Once loaded  → replace promo card with real AdMob ad seamlessly
//  4. On load fail → stay on promo card permanently for that slot
//
// This gives you real ad revenue on every 4th feed slot while ensuring the
// feed never shows a blank gap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/app_constants.dart';
import '../services/api_service.dart';
import '../services/ad_service.dart';

// ── Ad Config ─────────────────────────────────────────────────────────────────
class AdConfig {
  static bool adsEnabled = true;
  static bool isPremium  = false;
  static int  feedAdFrequency = 5;

  static Future<void> load() async {
    try {
      final d = await api.get('/ads/config');
      adsEnabled       = d['ads_enabled'] == true;
      isPremium        = d['user_is_premium'] == true;
      feedAdFrequency  = (d['placements']?['feed']?['frequency'] as num?)?.toInt() ?? 5;
    } catch (_) {}
  }

  static bool get shouldShowAds => adsEnabled && !isPremium;
}

// ─────────────────────────────────────────────────────────────────────────────
// FEED AD CARD
//
// Shows a real AdMob BannerAd inline in the feed. While the AdMob ad is
// loading (or if it fails to load) a RiseUp Premium promo card is shown
// as the fallback — so the slot is never blank.
// ─────────────────────────────────────────────────────────────────────────────
class FeedAdCard extends StatefulWidget {
  final bool  isDark;
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
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  BannerAd? _bannerAd;
  bool      _adLoaded = false;

  @override
  void initState() {
    super.initState();
    if (AdConfig.shouldShowAds) _loadBanner();
    // Track impression
    api.post('/ads/impression', {'ad_id': 'feed_admob', 'placement': 'feed'})
        .catchError((_) => {});
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: const String.fromEnvironment('BANNER_AD_UNIT_ID'),
      size:     AdSize.banner,   // 320×50
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _adLoaded = true); },
        onAdFailedToLoad: (ad, _) { ad.dispose(); if (mounted) setState(() => _bannerAd = null); },
      ),
    )..load();
  }

  @override
  void dispose() { _bannerAd?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();

    // ── Real AdMob banner — shown once loaded ──────────────────────────────
    if (_adLoaded && _bannerAd != null) {
      return Container(
        color: widget.cardColor,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          // "Ad" label — required by AdMob policy
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4)),
                child: Text('Ad', style: TextStyle(fontSize: 9, color: widget.subColor, fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          // Actual AdMob widget
          SizedBox(
            width:  _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ]),
      );
    }

    // ── Promo card fallback — shown while AdMob loads or on load failure ───
    return _PromoCard(
      isDark:      widget.isDark,
      cardColor:   widget.cardColor,
      borderColor: widget.borderColor,
      textColor:   widget.textColor,
      subColor:    widget.subColor,
    );
  }
}

// ── Internal promo card (RiseUp Premium upsell) ───────────────────────────────
class _PromoCard extends StatelessWidget {
  final bool  isDark;
  final Color cardColor, borderColor, textColor, subColor;

  const _PromoCard({
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cardColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4)),
            child: Text('Sponsored', style: TextStyle(fontSize: 9, color: subColor, fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                  borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('💼', style: TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Unlock Your Full Earning Potential',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
            Text('RiseUp Premium — Unlimited AI + Zero Ads',
                style: TextStyle(fontSize: 11, color: subColor)),
          ])),
        ]),
        const SizedBox(height: 10),
        Text('Join 50,000+ wealth builders. Unlimited AI, full Workflow Engine, and zero ads.',
            style: TextStyle(fontSize: 12, color: textColor, height: 1.4)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () {
              api.post('/ads/action', {'ad_id': 'feed_promo', 'placement': 'feed', 'action': 'click'})
                  .catchError((_) => {});
              context.go('/premium');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('Get Premium — Ad-Free',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)))),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => api.post('/ads/action', {'ad_id': 'feed_promo', 'action': 'dismiss'}).catchError((_) => {}),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
              decoration: BoxDecoration(
                  color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Skip', style: TextStyle(color: subColor, fontSize: 12))),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen banner — sticky bottom real AdMob banner
// ─────────────────────────────────────────────────────────────────────────────
class ScreenBannerAd extends StatefulWidget {
  final bool isDark;
  const ScreenBannerAd({super.key, required this.isDark});
  @override State<ScreenBannerAd> createState() => _ScreenBannerAdState();
}

class _ScreenBannerAdState extends State<ScreenBannerAd> {
  BannerAd? _ad; bool _loaded = false;
  @override void initState() { super.initState(); if (AdConfig.shouldShowAds) _load(); }
  void _load() {
    _ad = BannerAd(
      adUnitId: const String.fromEnvironment('BANNER_AD_UNIT_ID'),
      size: AdSize.banner, request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:       (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (ad, _) { ad.dispose(); },
      ),
    )..load();
  }
  @override void dispose() { _ad?.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) {
    if (!AdConfig.shouldShowAds || !_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      color: widget.isDark ? AppColors.bgCard : Colors.white,
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
      child: SafeArea(top: false, child: SizedBox(
        width: _ad!.size.width.toDouble(), height: _ad!.size.height.toDouble(),
        child: AdWidget(ad: _ad!))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rewarded Ad Button
// ─────────────────────────────────────────────────────────────────────────────
class RewardedAdButton extends StatefulWidget {
  final String featureKey, featureName;
  final VoidCallback onRewarded;
  final bool isDark;
  const RewardedAdButton({super.key, required this.featureKey, required this.featureName,
      required this.onRewarded, required this.isDark});
  @override State<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends State<RewardedAdButton> {
  bool _loading = false;
  Future<void> _watch() async {
    if (_loading) return;
    setState(() => _loading = true);
    final ok = await adService.showRewardedAd(
      featureKey: widget.featureKey,
      onRewarded: () {
        if (mounted) { setState(() => _loading = false); widget.onRewarded(); HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${widget.featureName} unlocked!'),
              backgroundColor: AppColors.success, duration: const Duration(seconds: 2))); }
      },
      onDismissed: () { if (mounted) setState(() => _loading = false); },
    );
    if (!ok && mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad not available. Try again later.'), backgroundColor: AppColors.error));
    }
  }
  @override Widget build(BuildContext ctx) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();
    return ElevatedButton.icon(
      onPressed: _loading ? null : _watch,
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      icon: _loading ? const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.play_circle_filled_rounded, color: Colors.white),
      label: Text(_loading ? 'Loading ad…' : 'Watch Ad — Unlock Free',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature Gate Sheet
// ─────────────────────────────────────────────────────────────────────────────
class FeatureGateSheet extends StatelessWidget {
  final String feature, featureName;
  final VoidCallback onUnlocked;
  final bool isDark;
  const FeatureGateSheet({super.key, required this.feature, required this.featureName,
      required this.onUnlocked, required this.isDark});

  static Future<void> show(BuildContext ctx, {required String feature, required String featureName,
      required VoidCallback onUnlocked, required bool isDark}) async {
    await showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => FeatureGateSheet(feature: feature, featureName: featureName,
            onUnlocked: onUnlocked, isDark: isDark));
  }

  @override Widget build(BuildContext ctx) {
    final bg   = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? Colors.white54 : Colors.black45;
    return Container(padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 20),
        Container(width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
            child: const Center(child: Text('🔒', style: TextStyle(fontSize: 32)))),
        const SizedBox(height: 16),
        Text('Daily Limit Reached', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        Text('You\'ve used all your free ${featureName.toLowerCase()} today.\nWatch a short ad or upgrade.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: RewardedAdButton(featureKey: feature, featureName: featureName,
            onRewarded: () { Navigator.pop(ctx); onUnlocked(); }, isDark: isDark)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: () { Navigator.pop(ctx); ctx.go('/premium'); },
          child: Container(padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(14)),
            child: const Center(child: Text('⭐ Go Premium — Ad-Free + Unlimited',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)))))),
        const SizedBox(height: 6),
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Maybe later', style: TextStyle(color: sub, fontSize: 13))),
      ])));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Usage Limit Banner
// ─────────────────────────────────────────────────────────────────────────────
class UsageLimitBanner extends StatelessWidget {
  final int remaining, total; final String featureName; final bool isDark;
  const UsageLimitBanner({super.key, required this.remaining, required this.total,
      required this.featureName, required this.isDark});
  @override Widget build(BuildContext ctx) {
    if (!AdConfig.shouldShowAds || remaining > total ~/ 2) return const SizedBox.shrink();
    final isLow = remaining <= 1;
    final color = isLow ? AppColors.error : AppColors.warning;
    return Container(margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(children: [
        Text(isLow ? '⚠️' : '💡', style: const TextStyle(fontSize: 16)), const SizedBox(width: 10),
        Expanded(child: Text(isLow
            ? '$remaining $featureName left today — watch an ad for more'
            : '$remaining $featureName remaining today',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        GestureDetector(onTap: () => ctx.go('/premium'),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: const Text('Upgrade', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
      ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Upsell Banner
// ─────────────────────────────────────────────────────────────────────────────
class PremiumUpsellBanner extends StatelessWidget {
  final bool isDark;
  const PremiumUpsellBanner({super.key, required this.isDark});
  @override Widget build(BuildContext ctx) {
    if (!AdConfig.shouldShowAds) return const SizedBox.shrink();
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? Colors.white54 : Colors.black45;
    return Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.1), AppColors.accent.withOpacity(0.1)]),
          borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withOpacity(0.3))),
      child: Column(children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), shape: BoxShape.circle),
              child: const Text('👑', style: TextStyle(fontSize: 24))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Go Premium', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
            Text('Remove ads + unlimited features', style: TextStyle(fontSize: 12, color: sub)),
          ])),
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => ctx.go('/premium'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Upgrade Now', style: TextStyle(fontWeight: FontWeight.w700)))),
      ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interstitial Gate
// ─────────────────────────────────────────────────────────────────────────────
class InterstitialGate extends StatefulWidget {
  final Widget child; final String placement;
  const InterstitialGate({super.key, required this.child, this.placement = 'default'});
  @override State<InterstitialGate> createState() => _InterstitialGateState();
}
class _InterstitialGateState extends State<InterstitialGate> {
  @override void initState() { super.initState(); _maybeShow(); }
  Future<void> _maybeShow() async {
    if (!AdConfig.shouldShowAds) return;
    await adService.showInterstitialIfReady();
    api.post('/ads/impression', {'ad_id': 'interstitial', 'placement': widget.placement}).catchError((_) => {});
  }
  @override Widget build(BuildContext ctx) => widget.child;
}
