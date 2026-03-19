// ─────────────────────────────────────────────────────────────
//  Mobile Ad Service — Android & iOS only (AdMob)
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../config/app_constants.dart';
import '../api_service.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  RewardedAd? _rewardedAd;
  bool _rewardedLoading = false;
  InterstitialAd? _interstitialAd;
  bool _interstitialLoading = false;
  int _interstitialCount = 0;
  static const int _interstitialFreq = 3;
  AppOpenAd? _appOpenAd;
  bool _appOpenLoading = false;
  DateTime? _appOpenLoadTime;

  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadRewardedAd();
    _loadInterstitialAd();
    _loadAppOpenAd();
  }

  // ── Rewarded ─────────────────────────────────────────────
  void _loadRewardedAd() {
    if (_rewardedLoading) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: kRewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) { _rewardedAd = ad; _rewardedLoading = false; },
        onAdFailedToLoad: (_) { _rewardedLoading = false; },
      ),
    );
  }

  @override
  bool get isRewardedReady => _rewardedAd != null;

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required Function onRewarded,
    required Function onDismissed,
  }) async {
    if (_rewardedAd == null) { _loadRewardedAd(); onDismissed(); return false; }
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose(); _rewardedAd = null; _loadRewardedAd(); onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose(); _rewardedAd = null; _loadRewardedAd(); onDismissed();
      },
    );
    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        try {
          await api.unlockViaAd(featureKey: featureKey, adUnitId: kRewardedAdUnit, hours: 1);
          onRewarded();
        } catch (_) { onDismissed(); }
      },
    );
    _rewardedAd = null;
    return true;
  }

  // ── Interstitial ─────────────────────────────────────────
  void _loadInterstitialAd() {
    if (_interstitialLoading) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: kInterstitialAdUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) { _interstitialAd = ad; _interstitialLoading = false; },
        onAdFailedToLoad: (_) { _interstitialLoading = false; },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfReady() async {
    _interstitialCount++;
    if (_interstitialCount % _interstitialFreq != 0) return;
    if (_interstitialAd == null) { _loadInterstitialAd(); return; }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose(); _interstitialAd = null; _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose(); _interstitialAd = null; _loadInterstitialAd();
      },
    );
    await _interstitialAd!.show();
    _interstitialAd = null;
  }

  // ── App Open ─────────────────────────────────────────────
  bool get _appOpenAvailable {
    if (_appOpenAd == null || _appOpenLoadTime == null) return false;
    return DateTime.now().difference(_appOpenLoadTime!).inHours < 4;
  }

  void _loadAppOpenAd() {
    if (_appOpenLoading) return;
    _appOpenLoading = true;
    AppOpenAd.load(
      adUnitId: kAppOpenAdUnit,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) { _appOpenAd = ad; _appOpenLoadTime = DateTime.now(); _appOpenLoading = false; },
        onAdFailedToLoad: (_) { _appOpenLoading = false; },
      ),
    );
  }

  @override
  Future<void> showAppOpenAdIfAvailable() async {
    if (!_appOpenAvailable) { _loadAppOpenAd(); return; }
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); _appOpenAd = null; _loadAppOpenAd(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _appOpenAd = null; _loadAppOpenAd(); },
    );
    await _appOpenAd!.show();
    _appOpenAd = null;
  }
}

final adService = AdService();

// ── Real Banner Widget (mobile only) ─────────────────────────
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  late BannerAd _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: kBannerAdUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (_, __) {},
      ),
    )..load();
  }

  @override
  void dispose() { _ad.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _ad.size.width.toDouble(),
      height: _ad.size.height.toDouble(),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border.symmetric(
          horizontal: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
        ),
      ),
      child: AdWidget(ad: _ad),
    );
  }
}
