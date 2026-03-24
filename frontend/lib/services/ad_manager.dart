// ─────────────────────────────────────────────────────────────────
// RiseUp Ad Manager
// Central controller for ALL ads across the app.
//
// Rules:
// - Premium users: ZERO ads, ZERO limits
// - Free users: ads in feed (every 4 posts), banner on agent/workflow
//   + usage limits on agent (3/day) and workflow (2 active)
// - Rewarded ads: unlock extra AI uses, agent runs, features
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
  static const int kFreeAgentDaily = 3;
  static const int kFreeWorkflowMax = 2;
  static const int kFeedAdFrequency = 4; // Ad after every N posts

  bool get isPremium => _isPremium;
  bool get canUseAgent => _isPremium || _agentUsesToday < kFreeAgentDaily;
  bool get canCreateWorkflow => _isPremium || _workflowCount < kFreeWorkflowMax;
  int get agentUsesRemaining => _isPremium ? 999 : (kFreeAgentDaily - _agentUsesToday).clamp(0, kFreeAgentDaily);
  int get workflowsRemaining => _isPremium ? 999 : (kFreeWorkflowMax - _workflowCount).clamp(0, kFreeWorkflowMax);

  Future<void> initialize({required bool isPremium}) async {
    _isPremium = isPremium;
    if (!isPremium) {
      await adService.initialize();
    }
  }

  void updatePremiumStatus(bool isPremium) {
    _isPremium = isPremium;
  }

  void recordAgentUse() {
    if (!_isPremium) _agentUsesToday++;
  }

  void setWorkflowCount(int count) {
    _workflowCount = count;
  }

  // ── Feed: insert ad widget at correct index ──────────────────
  // Call this in your ListView itemBuilder
  // Returns true if this index should show an ad
  bool shouldShowFeedAd(int index) {
    if (_isPremium) return false;
    // Show ad at index 4, 9, 14, 19... (every kFeedAdFrequency posts, 0-indexed)
    return (index + 1) % (kFeedAdFrequency + 1) == 0 && index > 0;
  }

  // Real item index accounting for inserted ads
  // Pass the visual list index, get the real post data index
  int realPostIndex(int visualIndex) {
    if (_isPremium) return visualIndex;
    // Every (kFeedAdFrequency + 1) items, one is an ad
    final adsBefore = visualIndex ~/ (kFeedAdFrequency + 1);
    return visualIndex - adsBefore;
  }

  // Total item count including ads
  int feedItemCount(int postCount) {
    if (_isPremium) return postCount;
    final adCount = postCount ~/ kFeedAdFrequency;
    return postCount + adCount;
  }

  // ── Show rewarded ad for more agent uses ─────────────────────
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

  // ── Show rewarded ad for workflow creation ────────────────────
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
}
