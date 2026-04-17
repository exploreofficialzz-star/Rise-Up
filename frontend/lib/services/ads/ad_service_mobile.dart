// frontend/lib/services/ads/ad_service_mobile.dart
// v2.1 — REWARDED AD CRASH FIX
//
// ROOT CAUSE: `_rewardedAd` was nulled AFTER `show()` returned, not before.
// Platform callbacks (onDismissed) could fire on a disposed / stale ad object,
// crashing the app. Fix: take ownership of the ad reference FIRST, null the
// field immediately, then call show() inside try-catch.
//
// Other fixes:
//  - wrap show() in try-catch so a platform exception doesn't propagate
//  - `onAdFailedToShowFullScreenContent` now also completes the completer
//  - no more `_rewardedAd = null` line after `show()` (it's nulled up-front)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../config/app_constants.dart';
import '../api_service.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  // ── Ad Instances ─────────────────────────────────────────
  RewardedAd?     _rewardedAd;
  InterstitialAd? _interstitialAd;
  BannerAd?       _bannerAd;
  NativeAd?       _nativeAd;

  // ── Loading States ─────────────────────────────────────────
  bool _rewardedLoading     = false;
  bool _interstitialLoading = false;
  bool _bannerLoading       = false;
  bool _nativeLoading       = false;

  // Guard against double-init
  bool _initialized = false;

  // ── Frequency & Capping ────────────────────────────────────
  int _interstitialCount = 0;
  static const int _interstitialFreq = 3;
  DateTime? _lastInterstitialShown;
  static const Duration _interstitialCooldown = Duration(minutes: 2);

  int _rewardedCountToday = 0;
  static const int _maxRewardedPerDay = 10;

  // ── Ad Unit IDs from Environment ───────────────────────────
  String get _bannerAdUnit       => const String.fromEnvironment('BANNER_AD_UNIT_ID');
  String get _interstitialAdUnit => const String.fromEnvironment('INTERSTITIAL_AD_UNIT_ID');
  String get _rewardedAdUnit     => const String.fromEnvironment('REWARDED_AD_UNIT_ID');
  String get _nativeAdUnit       => const String.fromEnvironment('NATIVE_AD_UNIT_ID');

  // ── Initialization ─────────────────────────────────────────
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    _loadRewardedAd();
    _loadInterstitialAd();
    _loadBannerAd();
    _loadNativeAd();
  }

  // ═══════════════════════════════════════════════════════════
  // REWARDED ADS  ← MAIN FIX
  // ═══════════════════════════════════════════════════════════

  void _loadRewardedAd() {
    if (_rewardedAdUnit.isEmpty) return;
    if (_rewardedLoading || _rewardedAd != null) return;
    if (_rewardedCountToday >= _maxRewardedPerDay) return;

    _rewardedLoading = true;

    RewardedAd.load(
      adUnitId: _rewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd    = ad;
          _rewardedLoading = false;
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          Future.delayed(const Duration(minutes: 1), _loadRewardedAd);
        },
      ),
    );
  }

  @override
  bool get isRewardedReady =>
      _rewardedAd != null && _rewardedCountToday < _maxRewardedPerDay;

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
  }) async {
    // ── Guard: no ad available ──────────────────────────────
    if (_rewardedAd == null) {
      _loadRewardedAd();
      onDismissed();
      return false;
    }

    if (_rewardedCountToday >= _maxRewardedPerDay) {
      onDismissed();
      return false;
    }

    // ── KEY FIX: take ownership BEFORE show ─────────────────
    // Null the field immediately so no other call can touch this instance.
    final ad = _rewardedAd!;
    _rewardedAd = null;

    final completer = Completer<bool>();

    // ── Lifecycle callbacks ─────────────────────────────────
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _rewardedCountToday++;
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _loadRewardedAd(); // Preload next
        if (!completer.isCompleted) {
          onDismissed();
          completer.complete(false);
        }
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('[AdService] Rewarded failed to show: $error');
        failedAd.dispose();
        _loadRewardedAd();
        if (!completer.isCompleted) {
          onDismissed();
          completer.complete(false);
        }
      },
    );

    // ── Show — wrapped in try-catch ─────────────────────────
    try {
      await ad.show(
        onUserEarnedReward: (_, reward) async {
          // Notify backend (best-effort — don't block reward on failure)
          try {
            await api.unlockViaAd(
              featureKey: featureKey,
              adUnitId:   _rewardedAdUnit,
              hours:      1,
            );
          } catch (_) {
            debugPrint('[AdService] unlockViaAd failed — rewarding locally');
          }
          // Always reward the user
          onRewarded();
          if (!completer.isCompleted) completer.complete(true);
        },
      );
    } catch (e) {
      // show() itself threw (platform exception, bad state, etc.)
      debugPrint('[AdService] show() threw: $e');
      ad.dispose();
      _loadRewardedAd();
      if (!completer.isCompleted) {
        onDismissed();
        completer.complete(false);
      }
      return false;
    }

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════
  // INTERSTITIAL ADS
  // ═══════════════════════════════════════════════════════════

  void _loadInterstitialAd() {
    if (_interstitialAdUnit.isEmpty) return;
    if (_interstitialLoading || _interstitialAd != null) return;

    _interstitialLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd     = ad;
          _interstitialLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          Future.delayed(const Duration(minutes: 2), _loadInterstitialAd);
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfReady() async {
    _interstitialCount++;
    if (_interstitialCount % _interstitialFreq != 0) return;

    if (_lastInterstitialShown != null) {
      final since = DateTime.now().difference(_lastInterstitialShown!);
      if (since < _interstitialCooldown) return;
    }

    if (_interstitialAd == null) { _loadInterstitialAd(); return; }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _lastInterstitialShown = DateTime.now();
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );

    try { await _interstitialAd!.show(); } catch (_) {}
    _interstitialAd = null;
  }

  Future<void> forceShowInterstitial() async {
    if (_interstitialAd == null) { _loadInterstitialAd(); return; }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );

    try { await _interstitialAd!.show(); } catch (_) {}
    _interstitialAd = null;
  }

  // ═══════════════════════════════════════════════════════════
  // BANNER ADS
  // ═══════════════════════════════════════════════════════════

  void _loadBannerAd() {
    if (_bannerAdUnit.isEmpty) return;
    if (_bannerLoading || _bannerAd != null) return;

    _bannerLoading = true;
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnit,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:       (_) { _bannerLoading = false; },
        onAdFailedToLoad: (_, __) {
          _bannerAd?.dispose();
          _bannerAd = null;
          _bannerLoading = false;
          Future.delayed(const Duration(minutes: 1), _loadBannerAd);
        },
      ),
    )..load();
  }

  Widget getBannerWidget() {
    if (_bannerAd == null) { _loadBannerAd(); return const SizedBox.shrink(); }
    return Container(
      alignment: Alignment.center,
      width:  _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Widget getStickyBanner(BuildContext context, {Color? backgroundColor}) {
    return Container(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SafeArea(top: false, child: getBannerWidget()),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // NATIVE ADS
  // ═══════════════════════════════════════════════════════════

  void _loadNativeAd() {
    if (_nativeAdUnit.isEmpty) return;
    if (_nativeLoading || _nativeAd != null) return;

    _nativeLoading = true;
    _nativeAd = NativeAd(
      adUnitId:  _nativeAdUnit,
      request:   const AdRequest(),
      factoryId: 'riseup_native',
      listener: NativeAdListener(
        onAdLoaded:       (_) { _nativeLoading = false; },
        onAdFailedToLoad: (_, __) {
          _nativeAd?.dispose();
          _nativeAd = null;
          _nativeLoading = false;
          Future.delayed(const Duration(minutes: 1), _loadNativeAd);
        },
      ),
    )..load();
  }

  Widget? getNativeWidget() {
    if (_nativeAd == null) { _loadNativeAd(); return null; }
    return AdWidget(ad: _nativeAd!);
  }

  // ═══════════════════════════════════════════════════════════
  // APP OPEN — DISABLED
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> showAppOpenAdIfAvailable() async {}

  // ═══════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════

  void dispose() {
    _rewardedAd?.dispose();
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    _nativeAd?.dispose();
  }

  void resetDailyCounters() => _rewardedCountToday = 0;

  void preloadAds() {
    _loadRewardedAd();
    _loadInterstitialAd();
    _loadBannerAd();
    _loadNativeAd();
  }
}

final adService = AdService();

// ═══════════════════════════════════════════════════════════
// BANNER AD WIDGET (Production-Ready)
// ═══════════════════════════════════════════════════════════

class BannerAdWidget extends StatefulWidget {
  final AdSize size;
  const BannerAdWidget({super.key, this.size = AdSize.banner});
  @override State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool      _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    const unit = String.fromEnvironment('BANNER_AD_UNIT_ID');
    if (unit.isEmpty) return;
    _ad = BannerAd(
      adUnitId: unit,
      size:     widget.size,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:       (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (_, __) { if (mounted) setState(() => _loaded = false); },
      ),
    )..load();
  }

  @override void dispose() { _ad?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width:  _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// NATIVE AD WIDGET (Production-Ready)
// ═══════════════════════════════════════════════════════════

class NativeAdWidget extends StatefulWidget {
  final String factoryId;
  const NativeAdWidget({super.key, this.factoryId = 'riseup_native'});
  @override State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;
  bool      _loaded = false;

  @override void initState() { super.initState(); _loadAd(); }

  void _loadAd() {
    const unit = String.fromEnvironment('NATIVE_AD_UNIT_ID');
    if (unit.isEmpty) return;
    _ad = NativeAd(
      adUnitId:  unit,
      request:   const AdRequest(),
      factoryId: widget.factoryId,
      listener: NativeAdListener(
        onAdLoaded:       (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (_, __) { if (mounted) setState(() => _loaded = false); },
      ),
    )..load();
  }

  @override void dispose() { _ad?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return AdWidget(ad: _ad!);
  }
}
