// lib/services/ad_manager.dart
// ─────────────────────────────────────────────────────────────
//  RiseUp Ad Manager — PRODUCTION READY
//  Works on Android, iOS (full AdMob) and Web (all stubs).
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_service.dart';   // conditional export: mobile vs web

/// Global singleton.
final adManager = AdManager._();

class AdManager {
  AdManager._();

  // ── State ──────────────────────────────────────────────────
  bool _isPremium         = false;
  int  _agentUsesToday    = 0;
  int  _workflowCount     = 0;
  int  _adWatchesForSkill = 0;
  int  _premiumUsesLeft   = 3;

  // ── Limits ─────────────────────────────────────────────────
  static const int kFreeAgentDaily    = 3;
  static const int kFreeWorkflowMax   = 2;
  static const int kFeedAdFrequency   = 4;   // 1 ad per N posts
  static const int kSkillAdWatches    = 3;   // ads needed to unlock a skill

  // ── SharedPreferences keys ─────────────────────────────────
  static const _kPremiumUses  = 'ad_premium_uses';
  static const _kSkillWatches = 'ad_skill_watches';
  static const _kLastReset    = 'ad_last_reset_date';

  // ══════════════════════════════════════════════════════════
  //  GETTERS
  // ══════════════════════════════════════════════════════════

  bool get isPremium           => _isPremium;
  bool get canUseAgent         => _isPremium || _agentUsesToday    < kFreeAgentDaily;
  bool get canCreateWorkflow   => _isPremium || _workflowCount     < kFreeWorkflowMax;
  bool get canUsePremiumFeature=> _isPremium || _premiumUsesLeft   > 0;
  bool get canUseChallenge     => canUsePremiumFeature;
  bool get canUseSkill         => canUsePremiumFeature;

  int  get agentUsesRemaining  => _isPremium ? 999 : (kFreeAgentDaily  - _agentUsesToday).clamp(0, kFreeAgentDaily);
  int  get workflowsRemaining  => _isPremium ? 999 : (kFreeWorkflowMax - _workflowCount ).clamp(0, kFreeWorkflowMax);
  int  get premiumUsesRemaining=> _isPremium ? 999 : _premiumUsesLeft;
  int  get challengeUsesRemaining => premiumUsesRemaining;
  int  get skillUsesRemaining     => premiumUsesRemaining;

  // ══════════════════════════════════════════════════════════
  //  INITIALISATION
  // ══════════════════════════════════════════════════════════

  Future<void> initialize({required bool isPremium}) async {
    _isPremium = isPremium;
    if (!isPremium) {
      await adService.initialize();
      await _loadFromPrefs();
      await _checkDailyReset();
    }
  }

  void updatePremiumStatus(bool isPremium) => _isPremium = isPremium;

  // ══════════════════════════════════════════════════════════
  //  USAGE TRACKING
  // ══════════════════════════════════════════════════════════

  void recordAgentUse() {
    if (!_isPremium) _agentUsesToday++;
  }

  void setWorkflowCount(int count) => _workflowCount = count;

  void recordPremiumFeatureUse() {
    if (!_isPremium) {
      _premiumUsesLeft = (_premiumUsesLeft - 1).clamp(0, 999);
      _saveToPrefs();
    }
  }

  // ══════════════════════════════════════════════════════════
  //  FEED AD LOGIC
  // ══════════════════════════════════════════════════════════

  bool shouldShowFeedAd(int index) {
    if (_isPremium) return false;
    return (index + 1) % (kFeedAdFrequency + 1) == 0 && index > 0;
  }

  int realPostIndex(int visualIndex) {
    if (_isPremium) return visualIndex;
    return visualIndex - (visualIndex ~/ (kFeedAdFrequency + 1));
  }

  int feedItemCount(int postCount) {
    if (_isPremium) return postCount;
    return postCount + (postCount ~/ kFeedAdFrequency);
  }

  // ══════════════════════════════════════════════════════════
  //  REWARDED AD UNLOCKS
  // ══════════════════════════════════════════════════════════

  Future<bool> watchAdForAgentUse(BuildContext context) async {
    if (_isPremium) return true;
    return adService.showRewardedAd(
      featureKey: 'agent_extra_use',
      onRewarded: () => _agentUsesToday = (_agentUsesToday - 1).clamp(0, kFreeAgentDaily),
      onDismissed: () {},
    );
  }

  Future<bool> watchAdForWorkflow(BuildContext context) async {
    if (_isPremium) return true;
    return adService.showRewardedAd(
      featureKey: 'workflow_extra',
      onRewarded: () => _workflowCount = (_workflowCount - 1).clamp(0, kFreeWorkflowMax),
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

  /// Watch ads progressively to unlock a skill (requires [kSkillAdWatches] watches).
  Future<bool> watchAdForSkillUnlock(BuildContext context) async {
    final ok = await adService.showRewardedAd(
      featureKey: 'skill_unlock',
      onRewarded: () {
        _adWatchesForSkill++;
        _saveToPrefs();
      },
      onDismissed: () {},
    );

    if (ok && _adWatchesForSkill >= kSkillAdWatches) {
      _adWatchesForSkill = 0;
      await _saveToPrefs();
      return true; // fully unlocked
    }

    if (ok && context.mounted) {
      final remaining = kSkillAdWatches - _adWatchesForSkill;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Watch $remaining more ad${remaining == 1 ? "" : "s"} to unlock'),
        duration: const Duration(seconds: 2),
      ));
    }
    return false;
  }

  /// Watch one rewarded ad to gain extra premium-feature uses.
  Future<bool> watchAdForPremiumFeature(BuildContext context) async {
    return adService.showRewardedAd(
      featureKey: 'premium_feature',
      onRewarded: () {
        _premiumUsesLeft++;
        _saveToPrefs();
      },
      onDismissed: () {},
    );
  }

  Future<bool> watchAdForChallenge(BuildContext context) =>
      watchAdForPremiumFeature(context);

  Future<bool> watchAdForSkill(BuildContext context) =>
      watchAdForPremiumFeature(context);

  // ══════════════════════════════════════════════════════════
  //  INTERSTITIAL
  // ══════════════════════════════════════════════════════════

  /// Show interstitial if one is cached and ready.
  Future<void> showInterstitial() async {
    if (_isPremium) return;
    await adService.showInterstitialIfReady();
  }

  /// Force an interstitial (ignores cooldown on mobile).
  /// Web: no-op (stub handles it safely).
  Future<void> forceInterstitial() async {
    if (_isPremium) return;
    await adService.forceShowInterstitial();
  }

  // ══════════════════════════════════════════════════════════
  //  BANNER
  // ══════════════════════════════════════════════════════════

  /// Inline banner (e.g. inside a ListView).
  Widget getBannerWidget() {
    if (_isPremium) return const SizedBox.shrink();
    return adService.getBannerWidget();
  }

  /// Sticky bottom banner (anchored to scaffold).
  /// Web returns SizedBox.shrink() via the stub.
  Widget getStickyBanner(BuildContext context) {
    if (_isPremium) return const SizedBox.shrink();
    return adService.getStickyBanner(context);
  }

  // ══════════════════════════════════════════════════════════
  //  PERSISTENCE
  // ══════════════════════════════════════════════════════════

  Future<void> _loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _premiumUsesLeft   = p.getInt(_kPremiumUses)  ?? 3;
    _adWatchesForSkill = p.getInt(_kSkillWatches) ?? 0;
  }

  Future<void> _saveToPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPremiumUses,  _premiumUsesLeft);
    await p.setInt(_kSkillWatches, _adWatchesForSkill);
  }

  // ══════════════════════════════════════════════════════════
  //  DAILY RESET
  // ══════════════════════════════════════════════════════════

  Future<void> _checkDailyReset() async {
    final p     = await SharedPreferences.getInstance();
    final last  = p.getString(_kLastReset);
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (last != today) {
      resetDailyLimits();
      await p.setString(_kLastReset, today);
    }
  }

  void resetDailyLimits() {
    _agentUsesToday  = 0;
    _premiumUsesLeft = 3;
    _saveToPrefs();
  }
}
