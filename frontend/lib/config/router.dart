import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_constants.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/onboarding/onboarding_chat_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/create/create_post_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/comments/comments_screen.dart';
import '../screens/premium/premium_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/messages/conversation_screen.dart';
import '../screens/live/live_screen.dart';
import '../screens/groups/groups_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../screens/skills/skills_screen.dart';
import '../screens/skills/skill_detail_screen.dart';
import '../screens/roadmap/roadmap_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/earnings/earnings_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/achievements/achievements_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/referrals/referrals_screen.dart';
import '../screens/streak/streak_screen.dart';
import '../main_shell.dart';

final router = GoRouter(
  initialLocation: kIsWeb ? '/login' : '/splash',
  errorBuilder: (context, state) => _ErrorPage(error: state.error?.toString()),
  routes: [
    // ── Public ────────────────────────────────────────
    GoRoute(path: '/splash',          builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/verify-email',    builder: (_, s) => VerifyEmailScreen(email: s.uri.queryParameters['email'] ?? '')),
    GoRoute(path: '/privacy',         builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/terms',           builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/onboarding',      builder: (_, __) => const OnboardingChatScreen()),

    // ── Full screen modals ────────────────────────────
    GoRoute(path: '/premium',         builder: (_, __) => const PremiumScreen()),
    GoRoute(
      path: '/comments/:postId',
      builder: (_, s) => CommentsScreen(
        postId: s.pathParameters['postId'] ?? '',
        postContent: s.uri.queryParameters['content'] ?? '',
        postAuthor: s.uri.queryParameters['author'] ?? '',
      ),
    ),
    GoRoute(
      path: '/conversation/:userId',
      builder: (_, s) => ConversationScreen(
        userId: s.pathParameters['userId'] ?? '',
        name: s.uri.queryParameters['name'] ?? 'User',
        avatar: s.uri.queryParameters['avatar'] ?? '👤',
        isAI: s.uri.queryParameters['isAI'] == 'true',
      ),
    ),

    // ── Main shell ────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home',          builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/explore',       builder: (_, __) => const ExploreScreen()),
        GoRoute(path: '/create',        builder: (_, __) => const CreatePostScreen()),
        GoRoute(path: '/messages',      builder: (_, __) => const MessagesScreen()),
        GoRoute(path: '/profile',       builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/settings',      builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/live',          builder: (_, __) => const LiveScreen()),
        GoRoute(path: '/groups',        builder: (_, __) => const GroupsScreen()),

        // AI Chat
        GoRoute(
          path: '/chat',
          builder: (_, s) => ChatScreen(
            conversationId: s.uri.queryParameters['cid'],
            mode: s.uri.queryParameters['mode'] ?? 'general',
            postContext: s.uri.queryParameters['postContext'],
            postAuthor: s.uri.queryParameters['postAuthor'],
          ),
        ),

        // Other screens
        GoRoute(path: '/tasks',        builder: (_, __) => const TasksScreen()),
        GoRoute(path: '/skills',       builder: (_, __) => const SkillsScreen()),
        GoRoute(path: '/skills/:id',   builder: (_, s) => SkillDetailScreen(moduleId: s.pathParameters['id']!)),
        GoRoute(path: '/roadmap',      builder: (_, __) => const RoadmapScreen()),
        GoRoute(path: '/earnings',     builder: (_, __) => const EarningsScreen()),
        GoRoute(path: '/analytics',    builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
        GoRoute(path: '/goals',        builder: (_, __) => const GoalsScreen()),
        GoRoute(path: '/expenses',     builder: (_, __) => const ExpensesScreen()),
        GoRoute(path: '/referrals',    builder: (_, __) => const ReferralsScreen()),
        GoRoute(path: '/streak',       builder: (_, __) => const StreakScreen()),
        GoRoute(path: '/payment',      builder: (_, s) => PaymentScreen(plan: s.uri.queryParameters['plan'] ?? 'monthly')),
      ],
    ),
  ],
);

class _ErrorPage extends StatelessWidget {
  final String? error;
  const _ErrorPage({this.error});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🔍', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text('Page not found', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('The page you\'re looking for doesn\'t exist.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => context.go('/home'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Go Home', style: TextStyle(color: Colors.white)),
        ),
      ])),
    );
  }
}
