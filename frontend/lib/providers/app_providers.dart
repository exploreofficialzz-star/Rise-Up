// frontend/lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';

// ── Auth State ────────────────────────────────────────
// autoDispose OK — cheap check, needed fresh on every auth-gated load
final authStateProvider = FutureProvider<bool>((ref) async {
  return api.isAuthenticated();
});

// ── User Profile ──────────────────────────────────────
// NOT autoDispose — profile survives navigation; cache handles freshness
final profileProvider = FutureProvider<Map>((ref) async {
  final data = await api.getProfile();
  final profile = data['profile'] as Map? ?? {};
  final currencyCode = profile['currency']?.toString() ?? 'USD';
  currency.init(currencyCode);
  return profile;
});

// ── Currency (reactive) ───────────────────────────────
final currencyProvider = Provider<CurrencyService>((ref) {
  ref.watch(profileProvider);
  return currency;
});

final currencyCodeProvider = Provider<String>((ref) {
  final profile = ref.watch(profileProvider);
  return profile.when(
    data:    (p) => p['currency']?.toString() ?? 'USD',
    loading: () => 'USD',
    error:   (_, __) => 'USD',
  );
});

// ── Dashboard Stats ───────────────────────────────────
// NOT autoDispose — stats are expensive; survive navigation
final statsProvider = FutureProvider<Map>((ref) async {
  return api.getStats();
});

// ── Tasks ─────────────────────────────────────────────
// autoDispose OK — family provider, different per status key
final tasksProvider = FutureProvider.autoDispose.family<List, String?>((ref, status) async {
  return api.getTasks(status: status);
});

// ── Skill Modules ─────────────────────────────────────
// NOT autoDispose — rarely changes, keep alive
final skillModulesProvider = FutureProvider<Map>((ref) async {
  return api.getSkillModules();
});

final myCoursesProvider = FutureProvider.autoDispose<List>((ref) async {
  return api.getMyCourses();
});

// ── Roadmap ───────────────────────────────────────────
// NOT autoDispose — expensive AI-generated content
final roadmapProvider = FutureProvider<Map>((ref) async {
  return api.getRoadmap();
});

// ── Subscription ──────────────────────────────────────
// NOT autoDispose — critical for feature gating across screens
final subscriptionProvider = FutureProvider<Map>((ref) async {
  return api.getSubscriptionStatus();
});

// ── Earnings ──────────────────────────────────────────
final earningsProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getEarnings();
});

// ── Conversations ─────────────────────────────────────
final conversationsProvider = FutureProvider.autoDispose<List>((ref) async {
  final data = await api.getConversations();
  return (data['conversations'] as List?) ?? [];
});

// ── AI Models ─────────────────────────────────────────
// NOT autoDispose — static list, keep alive
final aiModelsProvider = FutureProvider<List>((ref) async {
  return api.getAvailableModels();
});

// ── Selected AI Model ─────────────────────────────────
final selectedModelProvider = StateProvider<String>((ref) => 'auto');

// ── Agent Quota ───────────────────────────────────────
final agentQuotaProvider = FutureProvider.autoDispose<Map>((ref) async {
  try {
    return await api.get('/agent/quota');
  } catch (_) {
    return {'runs_used': 0, 'runs_limit': 3, 'runs_remaining': 3};
  }
});

// ── Current Stage ─────────────────────────────────────
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

// ── Profile Refresh Helper ────────────────────────────
// Call ref.invalidate(profileProvider) to force a fresh fetch.
// The ApiService cache will also be busted automatically on updateProfile().
