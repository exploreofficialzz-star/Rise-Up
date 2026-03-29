// Add to your pubspec.yaml:
// dependencies:
//   shared_preferences: ^2.2.2

import 'package:shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────
// RiseUp Ad Manager — PRODUCTION READY (with SharedPreferences)
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_service.dart';
import 'api_service.dart';

// Global singleton
final adManager = AdManager._();

class AdManager {
  AdManager._();

  bool _isPremium = false;
  int _agentUsesToday = 0;
  int _workflowCount = 0;
  
  // Skill unlock tracking
  int _adWatchesForSkill = 0;
  int _requiredAdWatches = 3;
  
  // Premium feature tracking
  int _premiumUsesRemaining = 3; // Default daily limit

  // Limits
  static const int kFreeAgentDaily = 3;
  static const int kFreeWorkflowMax = 2;
  static const int kFeedAdFrequency = 4;

  // SharedPreferences keys
  static const String _keyPremiumUses = 'ad_premium_uses';
  static const String _keySkillWatches = 'ad_skill_watches';
  static const String _keyLastResetDate = 'ad_last_reset_date';

  // ═════════════════════════════════════════════════════════════════
  // GETTERS
  // ═════════════════════════════════════════════════════════════════

  bool get isPremium => _isPremium;
  bool get canUseAgent => _isPremium || _agentUsesToday < kFreeAgentDaily;
  bool get canCreateWorkflow => _isPremium || _workflowCount < kFreeWorkflowMax;
  int get agentUsesRemaining => _isPremium ? 999 : (kFreeAgentDaily - _agentUsesToday).clamp(0, kFreeAgentDaily);
  int get workflowsRemaining => _isPremium ? 999 : (kFreeWorkflowMax - _workflowCount).clamp(0, kFreeWorkflowMax);

  // Generic premium feature checking
  bool get canUsePremiumFeature => isPremium || _premiumUsesRemaining > 0;
  int get premiumUsesRemaining => _premiumUsesRemaining;

  // Challenge-specific (aliases for clarity)
  bool get canUseChallenge => canUsePremiumFeature;
  int get challengeUsesRemaining => _premiumUsesRemaining;

  // Skill-specific
  bool get canUseSkill => canUsePremiumFeature;
  int get skillUsesRemaining => _premiumUsesRemaining;

  // ═════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═════════════════════════════════════════════════════════════════

  Future<void> initialize({required bool isPremium}) async {
    _isPremium = isPremium;
    if (!isPremium) {
      await adService.initialize();
      await _loadFromPrefs();
      await _checkDailyReset();
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

  void recordPremiumFeatureUse() {
    if (!isPremium) {
      _premiumUsesRemaining = (_premiumUsesRemaining - 1).clamp(0, 999);
      _saveToPrefs();
    }
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

  /// Watch ad to unlock skill (requires multiple watches)
  Future<bool> watchAdForSkillUnlock(BuildContext context) async {
    final ok = await adService.showRewardedAd(
      featureKey: 'skill_unlock',
      onRewarded: () {
        _adWatchesForSkill++;
        _saveToPrefs();
      },
      onDismissed: () {},
    );
    
    if (ok && _adWatchesForSkill >= _requiredAdWatches) {
      _adWatchesForSkill = 0; // Reset
      await _saveToPrefs();
      return true; // Unlocked
    }
    
    // Show progress
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Watch ${_requiredAdWatches - _adWatchesForSkill} more ads to unlock'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    return false;
  }

  /// Watch ad for premium feature access (adds uses)
  Future<bool> watchAdForPremiumFeature(BuildContext context) async {
    return adService.showRewardedAd(
      featureKey: 'premium_feature',
      onRewarded: () {
        _premiumUsesRemaining++;
        _saveToPrefs();
      },
      onDismissed: () {},
    );
  }

  /// Alias for challenge feature
  Future<bool> watchAdForChallenge(BuildContext context) async {
    return await watchAdForPremiumFeature(context);
  }

  /// Alias for skill feature access
  Future<bool> watchAdForSkill(BuildContext context) async {
    return await watchAdForPremiumFeature(context);
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

  // ═════════════════════════════════════════════════════════════════
  // PERSISTENCE (SharedPreferences) — IMPLEMENTED
  // ═════════════════════════════════════════════════════════════════

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _premiumUsesRemaining = prefs.getInt(_keyPremiumUses) ?? 3;
    _adWatchesForSkill = prefs.getInt(_keySkillWatches) ?? 0;
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPremiumUses, _premiumUsesRemaining);
    await prefs.setInt(_keySkillWatches, _adWatchesForSkill);
  }

  // ═════════════════════════════════════════════════════════════════
  // DAILY RESET — IMPLEMENTED
  // ═════════════════════════════════════════════════════════════════

  Future<void> _checkDailyReset() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReset = prefs.getString(_keyLastResetDate);
    final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    
    if (lastReset != today) {
      // New day - reset limits
      resetDailyLimits();
      await prefs.setString(_keyLastResetDate, today);
    }
  }

  void resetDailyLimits() {
    _agentUsesToday = 0;
    _premiumUsesRemaining = 3;
    _saveToPrefs();
  }
}
