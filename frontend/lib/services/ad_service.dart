import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/app_constants.dart';
import 'api_service.dart';

class AdService {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    if (_isLoading) return;
    _isLoading = true;
    RewardedAd.load(
      adUnitId: kRewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (err) {
          _isLoading = false;
        },
      ),
    );
  }

  bool get isReady => _rewardedAd != null;

  Future<bool> showRewardedAd({
    required String featureKey,
    required Function onRewarded,
    required Function onDismissed,
  }) async {
    if (_rewardedAd == null) {
      _loadRewardedAd();
      onDismissed();
      return false;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        onDismissed();
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        try {
          await api.unlockViaAd(
            featureKey: featureKey,
            adUnitId: kRewardedAdUnit,
            hours: 1,
          );
          onRewarded();
        } catch (e) {
          onDismissed();
        }
      },
    );
    _rewardedAd = null;
    return true;
  }
}

final adService = AdService();
