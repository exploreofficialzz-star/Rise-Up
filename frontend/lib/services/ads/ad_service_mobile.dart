// ─────────────────────────────────────────────────────────────
//  Mobile Ad Service — Android & iOS only (AdMob)
//  PRODUCTION READY — Uses real Ad Units from environment
// ─────────────────────────────────────────────────────────────
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
  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  BannerAd? _bannerAd;
  NativeAd? _nativeAd;

  // ── Loading States ─────────────────────────────────────────
  bool _rewardedLoading = false;
  bool _interstitialLoading = false;
  bool _bannerLoading = false;
  bool _nativeLoading = false;

  // ── Frequency & Capping ────────────────────────────────────
  int _interstitialCount = 0;
  static const int _interstitialFreq = 3;
  DateTime? _lastInterstitialShown;
  static const Duration _interstitialCooldown = Duration(minutes: 2);

  int _rewardedCountToday = 0;
  static const int _maxRewardedPerDay = 10;

  // ── Ad Unit IDs from Environment ───────────────────────────
  String get _bannerAdUnit => const String.fromEnvironment('BANNER_AD_UNIT_ID');
  String get _interstitialAdUnit => const String.fromEnvironment('INTERSTITIAL_AD_UNIT_ID');
  String get _rewardedAdUnit => const String.fromEnvironment('REWARDED_AD_UNIT_ID');
  String get _nativeAdUnit => const String.fromEnvironment('NATIVE_AD_UNIT_ID');

  // ── Initialization ─────────────────────────────────────────
  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    
    // Preload all ad types
    _loadRewardedAd();
    _loadInterstitialAd();
    _loadBannerAd();
    _loadNativeAd();
  }

  // ═══════════════════════════════════════════════════════════
  // REWARDED ADS
  // ═══════════════════════════════════════════════════════════

  void _loadRewardedAd() {
    if (_rewardedLoading || _rewardedAd != null) return;
    if (_rewardedCountToday >= _maxRewardedPerDay) return;

    _rewardedLoading = true;
    
    RewardedAd.load(
      adUnitId: _rewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedLoading = false;
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          // Retry after delay
          Future.delayed(const Duration(minutes: 1), _loadRewardedAd);
        },
      ),
    );
  }

  @override
  bool get isRewardedReady => _rewardedAd != null && _rewardedCountToday < _maxRewardedPerDay;

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
  }) async {
    if (_rewardedAd == null) {
      _loadRewardedAd();
      onDismissed();
      return false;
    }

    if (_rewardedCountToday >= _maxRewardedPerDay) {
      onDismissed();
      return false;
    }

    final completer = Completer<bool>();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _rewardedCountToday++;
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        onDismissed();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        onDismissed();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        try {
          await api.unlockViaAd(
            featureKey: featureKey,
            adUnitId: _rewardedAdUnit,
            hours: 1,
          );
          onRewarded();
          if (!completer.isCompleted) completer.complete(true);
        } catch (_) {
          onDismissed();
          if (!completer.isCompleted) completer.complete(false);
        }
      },
    );

    _rewardedAd = null;
    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════
  // INTERSTITIAL ADS (with frequency capping)
  // ═══════════════════════════════════════════════════════════

  void _loadInterstitialAd() {
    if (_interstitialLoading || _interstitialAd != null) return;
    
    _interstitialLoading = true;
    
    InterstitialAd.load(
      adUnitId: _interstitialAdUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
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
    // Frequency check: only show every Nth call
    _interstitialCount++;
    if (_interstitialCount % _interstitialFreq != 0) return;

    // Cooldown check: minimum time between ads
    if (_lastInterstitialShown != null) {
      final timeSince = DateTime.now().difference(_lastInterstitialShown!);
      if (timeSince < _interstitialCooldown) return;
    }

    if (_interstitialAd == null) {
      _loadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _lastInterstitialShown = DateTime.now();
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );

    await _interstitialAd!.show();
    _interstitialAd = null;
  }

  // Force show interstitial (for specific placements like after task completion)
  Future<void> forceShowInterstitial() async {
    if (_interstitialAd == null) {
      _loadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );

    await _interstitialAd!.show();
    _interstitialAd = null;
  }

  // ═══════════════════════════════════════════════════════════
  // BANNER ADS (with auto-refresh)
  // ═══════════════════════════════════════════════════════════

  void _loadBannerAd() {
    if (_bannerLoading || _bannerAd != null) return;
    
    _bannerLoading = true;
    
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _bannerLoading = false;
        },
        onAdFailedToLoad: (_, error) {
          _bannerAd?.dispose();
          _bannerAd = null;
          _bannerLoading = false;
          Future.delayed(const Duration(minutes: 1), _loadBannerAd);
        },
      ),
    )..load();
  }

  Widget getBannerWidget() {
    if (_bannerAd == null) {
      _loadBannerAd();
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  // Sticky banner for bottom of screen
  Widget getStickyBanner(BuildContext context, {Color? backgroundColor}) {
    return Container(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SafeArea(
        top: false,
        child: getBannerWidget(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // NATIVE ADS (for inline content)
  // ═══════════════════════════════════════════════════════════

  void _loadNativeAd() {
    if (_nativeLoading || _nativeAd != null) return;
    
    _nativeLoading = true;
    
    _nativeAd = NativeAd(
      adUnitId: _nativeAdUnit,
      request: const AdRequest(),
      factoryId: 'riseup_native',
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _nativeLoading = false;
        },
        onAdFailedToLoad: (_, error) {
          _nativeAd?.dispose();
          _nativeAd = null;
          _nativeLoading = false;
          Future.delayed(const Duration(minutes: 1), _loadNativeAd);
        },
      ),
    )..load();
  }

  Widget? getNativeWidget() {
    if (_nativeAd == null) {
      _loadNativeAd();
      return null;
    }
    return AdWidget(ad: _nativeAd!);
  }

  // ═══════════════════════════════════════════════════════════
  // APP OPEN ADS — DISABLED (caused black screen issues)
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> showAppOpenAdIfAvailable() async {
    // DISABLED — App Open Ads caused black screen on startup
    // Do not use until Google fixes the issue
  }

  // ═══════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════

  void dispose() {
    _rewardedAd?.dispose();
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    _nativeAd?.dispose();
  }

  // Reset daily counters (call at midnight or app start)
  void resetDailyCounters() {
    _rewardedCountToday = 0;
  }

  // Preload all ads (call when app comes to foreground)
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

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _ad = BannerAd(
      adUnitId: const String.fromEnvironment('BANNER_AD_UNIT_ID'),
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (_, __) {
          if (mounted) setState(() => _loaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    
    return Container(
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
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

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _ad = NativeAd(
      adUnitId: const String.fromEnvironment('NATIVE_AD_UNIT_ID'),
      request: const AdRequest(),
      factoryId: widget.factoryId,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (_, __) {
          if (mounted) setState(() => _loaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return AdWidget(ad: _ad!);
  }
}
