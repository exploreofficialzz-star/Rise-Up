import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

// ── Auth State ────────────────────────────────────────
final authStateProvider = FutureProvider<bool>((ref) async {
  return api.isAuthenticated();
});

// ── User Profile  ──────────────────────────────────────
final profileProvider = FutureProvider.autoDispose<Map>((ref) async {
  final data = await api.getProfile();
  return data['profile'] as Map? ?? {};
});

// ── Dashboard Stats ───────────────────────────────────
final statsProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getStats();
});

// ── Tasks ─────────────────────────────────────────────
final tasksProvider = FutureProvider.autoDispose.family<List, String?>((ref, status) async {
  return api.getTasks(status: status);
});

// ── Skill Modules ─────────────────────────────────────
final skillModulesProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getSkillModules();
});

final myCoursesProvider = FutureProvider.autoDispose<List>((ref) async {
  return api.getMyCourses();
});

// ── Roadmap ───────────────────────────────────────────
final roadmapProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getRoadmap();
});

// ── Subscription ──────────────────────────────────────
final subscriptionProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getSubscriptionStatus();
});

// ── Earnings ──────────────────────────────────────────
final earningsProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getEarnings();
});

// ── Conversations ─────────────────────────────────────
final conversationsProvider = FutureProvider.autoDispose<List>((ref) async {
  return api.getConversations();
});

// ── AI Models ─────────────────────────────────────────
final aiModelsProvider = FutureProvider.autoDispose<List>((ref) async {
  return api.getAvailableModels();
});

// ── Selected AI Model ─────────────────────────────────
final selectedModelProvider = StateProvider<String>((ref) => 'auto');

// ── Current Stage Notifier ────────────────────────────
class StageNotifier extends StateNotifier<String> {
  StageNotifier() : super('survival');

  void updateStage(String stage) => state = stage;
}

final stageProvider = StateNotifierProvider<StageNotifier, String>((ref) {
  return StageNotifier();
});

// ── Onboarding Progress ───────────────────────────────
class OnboardingNotifier extends StateNotifier<Map<String, dynamic>> {
  OnboardingNotifier() : super({
    'step': 0,
    'totalSteps': 5,
    'isComplete': false,
    'conversationId': null,
  });

  void nextStep() => state = {...state, 'step': (state['step'] as int) + 1};
  void complete(String convId) => state = {...state, 'isComplete': true, 'conversationId': convId};
  void setConversationId(String id) => state = {...state, 'conversationId': id};
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, Map<String, dynamic>>((ref) {
  return OnboardingNotifier();
});
