import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/onboarding/onboarding_chat_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../screens/skills/skills_screen.dart';
import '../screens/skills/skill_detail_screen.dart';
import '../screens/roadmap/roadmap_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/earnings/earnings_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/community/community_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/achievements/achievements_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/referrals/referrals_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/streak/streak_screen.dart';
import '../main_shell.dart';

final router = GoRouter(
  initialLocation: kIsWeb ? '/login' : '/splash',
  errorBuilder: (context, state) =>
      _ErrorPage(error: state.error?.toString()),
  routes: [
    // ── Public routes ─────────────────────────────────
    GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen()),
    GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen()),
    GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen()),
    GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (_, s) => VerifyEmailScreen(
          email: s.uri.queryParameters['email'] ?? ''),
    ),
    GoRoute(
        path: '/privacy',
        builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(
        path: '/terms',
        builder: (_, __) => const TermsScreen()),
    GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingChatScreen()),

    // ── Main shell with bottom nav ─────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          MainShell(child: child),
      routes: [
        GoRoute(
            path: '/home',
            builder: (_, __) => const DashboardScreen()),
        GoRoute(
          path: '/chat',
          builder: (_, s) => ChatScreen(
            conversationId: s.uri.queryParameters['cid'],
            mode: s.uri.queryParameters['mode'] ?? 'general',
          ),
        ),
        GoRoute(
            path: '/tasks',
            builder: (_, __) => const TasksScreen()),
        GoRoute(
            path: '/skills',
            builder: (_, __) => const SkillsScreen()),
        GoRoute(
          path: '/skills/:id',
          builder: (_, s) => SkillDetailScreen(
              moduleId: s.pathParameters['id']!),
        ),
        GoRoute(
            path: '/roadmap',
            builder: (_, __) => const RoadmapScreen()),
        GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen()),
        GoRoute(
            path: '/earnings',
            builder: (_, __) => const EarningsScreen()),
        GoRoute(
            path: '/analytics',
            builder: (_, __) => const AnalyticsScreen()),
        GoRoute(
            path: '/community',
            builder: (_, __) => const CommunityScreen()),
        GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen()),
        GoRoute(
            path: '/achievements',
            builder: (_, __) => const AchievementsScreen()),
        GoRoute(
            path: '/goals',
            builder: (_, __) => const GoalsScreen()),
        GoRoute(
            path: '/expenses',
            builder: (_, __) => const ExpensesScreen()),
        GoRoute(
            path: '/referrals',
            builder: (_, __) => const ReferralsScreen()),
        GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen()),
        GoRoute(
            path: '/streak',
            builder: (_, __) => const StreakScreen()),
        GoRoute(
          path: '/payment',
          builder: (_, s) => PaymentScreen(
              plan: s.uri.queryParameters['plan'] ?? 'monthly'),
        ),
      ],
    ),
  ],
);

class _ErrorPage extends StatelessWidget {
  final String? error;
  const _ErrorPage({this.error});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text('Page not found',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'The page you\'re looking for doesn\'t exist.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
}
