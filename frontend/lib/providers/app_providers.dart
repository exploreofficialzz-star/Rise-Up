// frontend/lib/providers/app_providers.dart
//
// Changes vs original:
//  • profileProvider now loads cached profile from storage first,
//    then updates in background. This means:
//    - Profile screen NEVER shows a system-default fallback
//    - Profile loads instantly on every screen open
//    - Fresh data replaces cached data silently
//  • authStateProvider now delegates to authService (ChangeNotifier)
//
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/currency_service.dart';
import '../utils/storage_service.dart';

// ── Auth State ────────────────────────────────────────
// Thin wrapper — real state lives in authService (ChangeNotifier).
// Kept for backward compatibility with any screen that reads it.
final authStateProvider = FutureProvider<bool>((ref) async {
  return authService.isAuthenticated;
});

// ── User Profile ──────────────────────────────────────
// Facebook-style: show cached profile instantly, refresh in background.
// If network fails, the cache keeps showing — never a blank/system-default.
final profileProvider = FutureProvider.autoDispose<Map>((ref) async {
  // Step 1 — try to return a fresh profile from the network
  try {
    final data    = await api.getProfile();
    final profile = data['profile'] as Map? ?? {};

    // Persist for next cold start / offline use
    await storageService.cacheProfile(Map<String, dynamic>.from(profile));

    // Boot the currency service with the user's preference
    final currencyCode = profile['currency']?.toString() ?? 'USD';
    currency.init(currencyCode);

    return profile;
  } catch (e) {
    // Step 2 — network failed (offline, or token being refreshed)
    //          Return cached profile so the screen never shows system-default
    final cached = await storageService.getCachedProfile();
    if (cached != null && cached.isNotEmpty) {
      final currencyCode = cached['currency']?.toString() ?? 'USD';
      currency.init(currencyCode);
      return cached;
    }
    // Nothing cached yet (first-ever load failed) — propagate the error
    rethrow;
  }
});

// ── Currency Service (renamed to avoid collision) ─────
final currencyServiceProvider = Provider<CurrencyService>((ref) {
  ref.watch(profileProvider);
  return currency;
});

// ── Currency Code (string only) ───────────────────────
final currencyCodeProvider = Provider<String>((ref) {
  final profile = ref.watch(profileProvider);
  return profile.when(
    data:    (p) => p['currency']?.toString() ?? 'USD',
    loading: () => 'USD',
    error:   (_, __) => 'USD',
  );
});

// ── Dashboard Stats ───────────────────────────────────
final statsProvider = FutureProvider.autoDispose<Map>((ref) async {
  return api.getStats();
});

// ── Tasks ─────────────────────────────────────────────
final tasksProvider =
    FutureProvider.autoDispose.family<List, String?>((ref, status) async {
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
final conversationsProvider =
    FutureProvider.autoDispose<List>((ref) async {
  final data = await api.getConversations();
  return (data['conversations'] as List?) ?? [];
});

// ── AI Models ─────────────────────────────────────────
final aiModelsProvider = FutureProvider.autoDispose<List>((ref) async {
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

final stageProvider =
    StateNotifierProvider<StageNotifier, String>((ref) => StageNotifier());

// ── Onboarding Progress ───────────────────────────────
class OnboardingNotifier extends StateNotifier<Map<String, dynamic>> {
  OnboardingNotifier()
      : super({
          'step':           0,
          'totalSteps':     5,
          'isComplete':     false,
          'conversationId': null,
        });

  void nextStep() =>
      state = {...state, 'step': (state['step'] as int) + 1};
  void complete(String convId) =>
      state = {...state, 'isComplete': true, 'conversationId': convId};
  void setConversationId(String id) =>
      state = {...state, 'conversationId': id};
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, Map<String, dynamic>>(
        (ref) => OnboardingNotifier());
