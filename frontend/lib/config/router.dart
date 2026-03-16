import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
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
import 'main_shell.dart';

final router = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) async {
    final isAuth = await api.isAuthenticated();
    final path = state.uri.path;
    if (!isAuth && path != '/login' && path != '/register' && path != '/splash') {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingChatScreen()),

    // Main shell with bottom nav
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/chat', builder: (_, s) => ChatScreen(
          conversationId: s.uri.queryParameters['cid'],
          mode: s.uri.queryParameters['mode'] ?? 'general',
        )),
        GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
        GoRoute(path: '/skills', builder: (_, __) => const SkillsScreen()),
        GoRoute(
          path: '/skills/:id',
          builder: (_, s) => SkillDetailScreen(moduleId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/roadmap', builder: (_, __) => const RoadmapScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/earnings', builder: (_, __) => const EarningsScreen()),
        GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/community', builder: (_, __) => const CommunityScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/payment',
          builder: (_, s) => PaymentScreen(plan: s.uri.queryParameters['plan'] ?? 'monthly'),
        ),
      ],
    ),
  ],
);
