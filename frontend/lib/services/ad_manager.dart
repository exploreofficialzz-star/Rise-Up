// ─────────────────────────────────────────────────────────────────
// RiseUp Ad Manager — PRODUCTION READY
// Central controller for ALL ads across the app.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'ad_service.dart';
import 'api_service.dart';

// Global singleton
final adManager = AdManager._();

class AdManager {
  AdManager._();

  bool _isPremium = false;
  int _agentUsesToday = 0;
  int _workflowCount = 0;
  
  // Limits
  static const int kFreeAgentDaily = 3;
  static const int kFreeWorkflowMax = 2;
  static const int kFeedAdFrequency = 4;

  // Getters
  bool get isPremium => _isPremium;
  bool get canUseAgent => _isPremium || _agentUsesToday < kFreeAgentDaily;
  bool get canCreateWorkflow => _isPremium || _workflowCount < kFreeWorkflowMax;
  int get agentUsesRemaining => _isPremium ? 999 : (kFreeAgentDaily - _agentUsesToday).clamp(0, kFreeAgentDaily);
  int get workflowsRemaining => _isPremium ? 999 : (kFreeWorkflowMax - _workflowCount).clamp(0, kFreeWorkflowMax);

  // ═════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═════════════════════════════════════════════════════════════════

  Future<void> initialize({required bool isPremium}) async {
    _isPremium = isPremium;
    if (!isPremium) {
      await adService.initialize();
    }
  }

  void updatePremiumStatus(bool isPremium) {
    _isPremium = isPremium;
  }

  // ═════════════════════════════════════════════════════════════════
  // USAGE TRACKING
  // ═════════════════════════════════════════════════════════════════

  void recordAgentUse() {
    if (!_isPremium) _agentUsesToday++;
  }

  void setWorkflowCount(int count) {
    _workflowCount = count;
  }

  // ═════════════════════════════════════════════════════════════════
  // FEED AD LOGIC
  // ═════════════════════════════════════════════════════════════════

  bool shouldShowFeedAd(int index) {
    if (_isPremium) return false;
    return (index + 1) % (kFeedAdFrequency + 1) == 0 && index > 0;
  }

  int realPostIndex(int visualIndex) {
    if (_isPremium) return visualIndex;
    final adsBefore = visualIndex ~/ (kFeedAdFrequency + 1);
    return visualIndex - adsBefore;
  }

  int feedItemCount(int postCount) {
    if (_isPremium) return postCount;
    final adCount = postCount ~/ kFeedAdFrequency;
    return postCount + adCount;
  }

  // ═════════════════════════════════════════════════════════════════
  // REWARDED AD UNLOCKS
  // ═════════════════════════════════════════════════════════════════

  Future<bool> watchAdForAgentUse(BuildContext context) async {
    if (_isPremium) return true;
    
    return adService.showRewardedAd(
      featureKey: 'agent_extra_use',
      onRewarded: () {
        _agentUsesToday = (_agentUsesToday - 1).clamp(0, kFreeAgentDaily);
      },
      onDismissed: () {},
    );
  }

  Future<bool> watchAdForWorkflow(BuildContext context) async {
    if (_isPremium) return true;
    
    return adService.showRewardedAd(
      featureKey: 'workflow_extra',
      onRewarded: () {
        _workflowCount = (_workflowCount - 1).clamp(0, kFreeWorkflowMax);
      },
      onDismissed: () {},
    );
  }

  Future<bool> watchAdForFeature(
    BuildContext context, {
    required String featureKey,
    required String featureName,
  }) async {
    if (_isPremium) return true;
    
    return adService.showRewardedAd(
      featureKey: featureKey,
      onRewarded: () {},
      onDismissed: () {},
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // INTERSTITIAL ADS
  // ═════════════════════════════════════════════════════════════════

  Future<void> showInterstitial() async {
    if (_isPremium) return;
    await adService.showInterstitialIfReady();
  }

  Future<void> forceInterstitial() async {
    if (_isPremium) return;
    await adService.forceShowInterstitial();
  }

  // ═════════════════════════════════════════════════════════════════
  // BANNER ADS
  // ═════════════════════════════════════════════════════════════════

  Widget getBannerWidget() {
    if (_isPremium) return const SizedBox.shrink();
    return adService.getBannerWidget();
  }

  Widget getStickyBanner(BuildContext context) {
    if (_isPremium) return const SizedBox.shrink();
    return adService.getStickyBanner(context);
  }
}
