// frontend/lib/config/router.dart — RiseUp v3.0
// No bottom nav. Sidebar-driven. Home IS the app.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_constants.dart';
import '../services/auth_service.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/premium/premium_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/earnings/earnings_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/skills/skills_screen.dart';
import '../screens/skills/skill_detail_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../screens/memory/income_memory_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/onboarding/onboarding_chat_screen.dart';

const _publicRoutes = <String>{
  '/splash', '/login', '/register', '/forgot-password', '/privacy', '/terms',
};

bool _isPublic(String location) =>
    _publicRoutes.contains(location) || location.startsWith('/verify-email');

final router = GoRouter(
  initialLocation: '/splash',
  refreshListenable: authService,

  redirect: (context, state) {
    final location = state.matchedLocation;
    final status   = authService.status;
    if (status == AuthStatus.unknown)       return location == '/splash' ? null : '/splash';
    if (location == '/splash')              return null;
    if (status == AuthStatus.unauthenticated && !_isPublic(location)) return '/login';
    if (status == AuthStatus.authenticated &&
        (location == '/login' || location == '/register')) return '/home';
    return null;
  },

  errorBuilder: (context, state) => _ErrorPage(error: state.error?.toString()),

  routes: [
    // ── Auth ───────────────────────────────────────────────────────────────
    GoRoute(path: '/splash',          builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/verify-email',
        builder: (_, s) => VerifyEmailScreen(email: s.uri.queryParameters['email'] ?? '')),
    GoRoute(path: '/onboarding',      builder: (_, __) => const OnboardingChatScreen()),
    GoRoute(path: '/privacy',         builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/terms',           builder: (_, __) => const TermsScreen()),

    // ── Full-screen modals (no shell) ──────────────────────────────────────
    GoRoute(path: '/premium',         builder: (_, __) => const PremiumScreen()),
    GoRoute(path: '/payment',         builder: (_, __) => const PaymentScreen()),

    // ── Main app — Home IS the shell ───────────────────────────────────────
    GoRoute(
      path: '/home',
      builder: (_, s) => HomeScreen(
        openMissionId: s.uri.queryParameters['missionId'],
      ),
    ),

    // ── Sub-screens (pushed on top of home) ───────────────────────────────
    GoRoute(path: '/profile',         builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/edit-profile',    builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: '/notifications',   builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: '/settings',        builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/earnings',        builder: (_, __) => const EarningsScreen()),
    GoRoute(path: '/goals',           builder: (_, __) => const GoalsScreen()),
    GoRoute(path: '/skills',          builder: (_, __) => const SkillsScreen()),
    GoRoute(path: '/skills/:id',
        builder: (_, s) => SkillDetailScreen(moduleId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks',           builder: (_, __) => const TasksScreen()),
    GoRoute(path: '/memory',          builder: (_, __) => const IncomeMemoryScreen()),
  ],
);

class _ErrorPage extends StatelessWidget {
  final String? error;
  const _ErrorPage({this.error});
  @override
  Widget build(BuildContext ctx) => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 64, color: Colors.red),
      const SizedBox(height: 16),
      const Text('Page not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (error != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(error!, style: const TextStyle(color: Colors.grey, fontSize: 12))),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: () => ctx.go('/home'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Go Home')),
    ])),
  );
}
