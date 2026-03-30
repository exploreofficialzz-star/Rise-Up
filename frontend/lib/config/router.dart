// frontend/lib/config/router.dart
// Fixed: conversation route passes postContext + postAuthor to ConversationScreen
// so "Chat Privately" from home_screen opens the AI mentor with post context.

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
import '../screens/dashboard/dashboard_screen.dart';
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
import '../screens/groups/group_detail_screen.dart';
import '../screens/live/live_viewer_screen.dart';
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
import '../screens/workflow/workflow_hub_screen.dart';
import '../screens/workflow/workflow_research_screen.dart';
import '../screens/workflow/workflow_detail_screen.dart';
import '../screens/collaboration/collaboration_screen.dart';
import '../screens/agent/agent_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/home/create_status_screen.dart';
import '../screens/market_pulse/market_pulse_screen.dart';
import '../screens/contracts/contracts_screen.dart';
import '../screens/memory/income_memory_screen.dart';
import '../screens/challenges/challenges_screen.dart';
import '../screens/crm/crm_screen.dart';
import '../screens/portfolio/portfolio_screen.dart';
import '../main_shell.dart';

final router = GoRouter(
  initialLocation: kIsWeb ? '/login' : '/splash',
  errorBuilder: (context, state) =>
      _ErrorPage(error: state.error?.toString()),
  routes: [
    // ── Public ────────────────────────────────────────────────────
    GoRoute(path: '/splash',          builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (_, s) => VerifyEmailScreen(
          email: s.uri.queryParameters['email'] ?? ''),
    ),
    GoRoute(path: '/privacy',   builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/terms',     builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/onboarding',builder: (_, __) => const OnboardingChatScreen()),

    // ── Full-screen modals ─────────────────────────────────────────
    GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
    GoRoute(
      path: '/comments/:postId',
      builder: (_, s) => CommentsScreen(
        postId:      s.pathParameters['postId'] ?? '',
        postContent: s.uri.queryParameters['content'] ?? '',
        postAuthor:  s.uri.queryParameters['author'] ?? '',
        postUserId:  s.uri.queryParameters['userId'],
      ),
    ),
    // FIX: conversation route now passes postContext + postAuthor.
    // These are set when the user taps "Chat Privately" on a post in
    // home_screen — the AI mentor receives them and auto-sends a
    // contextual opening message about the post.
    GoRoute(
      path: '/conversation/:userId',
      builder: (_, s) => ConversationScreen(
        userId:      s.pathParameters['userId'] ?? '',
        name:        s.uri.queryParameters['name'] ?? 'User',
        avatar:      s.uri.queryParameters['avatar'] ?? '👤',
        isAI:        s.uri.queryParameters['isAI'] == 'true',
        postContext: s.uri.queryParameters['postContext'],
        postAuthor:  s.uri.queryParameters['postAuthor'],
      ),
    ),

    // ── Main shell ─────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home',      builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/explore',   builder: (_, __) => const ExploreScreen()),
        GoRoute(path: '/create',    builder: (_, __) => const CreatePostScreen()),
        GoRoute(path: '/messages',  builder: (_, __) => const MessagesScreen()),
        GoRoute(path: '/profile',   builder: (_, __) => const ProfileScreen()),
        GoRoute(
          path: '/user-profile/:id',
          builder: (_, s) => UserProfileScreen(
              userId: s.pathParameters['id'] ?? ''),
        ),
        GoRoute(path: '/settings',      builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/live',          builder: (_, __) => const LiveScreen()),
        GoRoute(
          path: '/live-viewer/:id',
          builder: (_, s) => LiveViewerScreen(
            sessionId: s.pathParameters['id']!,
            host:  s.uri.queryParameters['host']  ?? 'Host',
            title: s.uri.queryParameters['title'] ?? 'Live Session',
          ),
        ),
        GoRoute(path: '/groups', builder: (_, __) => const GroupsScreen()),
        GoRoute(
          path: '/group/:id',
          builder: (_, s) => GroupDetailScreen(
            groupId:   s.pathParameters['id']!,
            groupName: s.uri.queryParameters['name'] ?? 'Group',
          ),
        ),

        // AI Chat (legacy — kept for backward compat with existing deep links)
        GoRoute(
          path: '/chat',
          builder: (_, s) => ChatScreen(
            conversationId: s.uri.queryParameters['cid'],
            mode:        s.uri.queryParameters['mode'] ?? 'general',
            postContext: s.uri.queryParameters['postContext'],
            postAuthor:  s.uri.queryParameters['postAuthor'],
          ),
        ),

        GoRoute(path: '/tasks',    builder: (_, __) => const TasksScreen()),
        GoRoute(path: '/skills',   builder: (_, __) => const SkillsScreen()),
        GoRoute(
          path: '/skills/:id',
          builder: (_, s) => SkillDetailScreen(moduleId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/roadmap',      builder: (_, __) => const RoadmapScreen()),
        GoRoute(path: '/earnings',     builder: (_, __) => const EarningsScreen()),
        GoRoute(path: '/analytics',    builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
        GoRoute(path: '/goals',        builder: (_, __) => const GoalsScreen()),
        GoRoute(path: '/expenses',     builder: (_, __) => const ExpensesScreen()),
        GoRoute(path: '/referrals',    builder: (_, __) => const ReferralsScreen()),
        GoRoute(path: '/streak',       builder: (_, __) => const StreakScreen()),
        GoRoute(
          path: '/payment',
          builder: (_, s) => PaymentScreen(
              plan: s.uri.queryParameters['plan'] ?? 'monthly'),
        ),

        GoRoute(path: '/workflow',     builder: (_, __) => const WorkflowHubScreen()),
        GoRoute(path: '/workflow/new', builder: (_, __) => const WorkflowResearchScreen()),
        GoRoute(
          path: '/workflow/:id',
          builder: (_, s) => WorkflowDetailScreen(
              workflowId: s.pathParameters['id']!),
        ),

        GoRoute(path: '/collaboration', builder: (_, __) => const CollaborationScreen()),

        GoRoute(path: '/agent', builder: (_, __) => const AgentScreen()),
        GoRoute(
          path: '/agent/:workflowId',
          builder: (_, s) => AgentScreen(
              workflowId: s.pathParameters['workflowId']),
        ),

        GoRoute(path: '/edit-profile',  builder: (_, __) => const EditProfileScreen()),
        GoRoute(path: '/create-status', builder: (_, __) => const CreateStatusScreen()),

        GoRoute(path: '/pulse',      builder: (_, __) => const MarketPulseScreen()),
        GoRoute(path: '/contracts',  builder: (_, __) => const ContractsScreen()),
        GoRoute(path: '/memory',     builder: (_, __) => const IncomeMemoryScreen()),
        GoRoute(path: '/challenges', builder: (_, __) => const ChallengesScreen()),
        GoRoute(path: '/crm',        builder: (_, __) => const CrmScreen()),
        GoRoute(path: '/portfolio',  builder: (_, __) => const PortfolioScreen()),
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
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('Page not found', style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("The page you're looking for doesn't exist.",
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: const Text('Go Home',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
    );
  }
}
