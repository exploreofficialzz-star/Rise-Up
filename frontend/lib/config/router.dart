// frontend/lib/config/router.dart
// v5.2 — Splash controls its own 2s timing; router no longer boots it early
//
// Root cause of splash never showing:
//  authService.initialize() completes BEFORE runApp(), so status is already
//  known on frame 1. v5.1's step-2 redirect immediately pushed to /home or
//  /login before the splash Scaffold ever painted.
//
// Fix: redirect returns null for /splash regardless of auth status.
//  splash_screen.dart v2.4 owns the 2s delay and calls context.go() itself.
//  Router only sends unknown-status navigations TO /splash (step 1).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_constants.dart';
import '../services/auth_service.dart';
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
import '../screens/methods/methods_brain_screen.dart';
import '../screens/marketplace/marketplace_screen.dart';
import '../main_shell.dart';

// Routes that never require authentication
const _publicRoutes = {
  '/splash',
  '/login',
  '/register',
  '/forgot-password',
  '/privacy',
  '/terms',
  '/onboarding',
};

bool _isPublic(String location) =>
    _publicRoutes.contains(location) ||
    location.startsWith('/verify-email');

final router = GoRouter(
  initialLocation: '/splash',
  refreshListenable: authService,

  // ── Global auth guard ────────────────────────────────────────────────
  redirect: (context, state) {
    final location = state.matchedLocation;
    final status   = authService.status;

    // ── 1. Auth still resolving → send everything to splash ───────────
    // initialize() typically completes in <5ms so this is momentary.
    if (status == AuthStatus.unknown) {
      return location == '/splash' ? null : '/splash';
    }

    // ── 2. On splash with known status → do NOT redirect ──────────────
    // splash_screen.dart v2.4 owns the 2-second delay and calls
    // context.go('/home') or context.go('/login') itself after it elapses.
    // If we redirect here the splash never renders even one frame.
    if (location == '/splash') {
      return null;
    }

    // ── 3. Unauthenticated on protected route → /login ─────────────────
    if (status == AuthStatus.unauthenticated && !_isPublic(location)) {
      return '/login';
    }

    // ── 4. Authenticated on login/register → skip to home ──────────────
    if (status == AuthStatus.authenticated &&
        (location == '/login' || location == '/register')) {
      return '/home';
    }

    // No redirect needed
    return null;
  },

  errorBuilder: (context, state) =>
      _ErrorPage(error: state.error?.toString()),

  routes: [
    // ── Public ──────────────────────────────────────────────────────────
    GoRoute(path: '/splash',          builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (_, s) => VerifyEmailScreen(
        email: s.uri.queryParameters['email'] ?? '',
      ),
    ),
    GoRoute(path: '/privacy',    builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/terms',      builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingChatScreen()),

    // ── Full-screen modals (outside shell so no bottom nav) ─────────────
    GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
    GoRoute(
      path: '/comments/:postId',
      builder: (_, s) => CommentsScreen(
        postId:      s.pathParameters['postId']!,
        postContent: s.uri.queryParameters['content'] ?? '',
        postAuthor:  s.uri.queryParameters['author']  ?? '',
      ),
    ),
    GoRoute(
      path: '/conversation/:userId',
      builder: (_, s) {
        final extra = s.extra as Map<String, String?>? ?? {};
        return ConversationScreen(
          userId:      s.pathParameters['userId']!,
          name:        s.uri.queryParameters['name']       ?? extra['name']       ?? 'User',
          avatar:      s.uri.queryParameters['avatar']     ?? extra['avatar']     ?? '🙂',
          isAI:        s.uri.queryParameters['isAI']       == 'true',
          postContext: s.uri.queryParameters['postContext'] ?? extra['postContext'],
          postAuthor:  s.uri.queryParameters['postAuthor']  ?? extra['postAuthor'],
        );
      },
    ),

    // ── Main shell (bottom nav) ─────────────────────────────────────────
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
          builder: (_, s) =>
              UserProfileScreen(userId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/edit-profile',  builder: (_, __) => const EditProfileScreen()),
        GoRoute(path: '/settings',      builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/live',          builder: (_, __) => const LiveScreen()),
        GoRoute(
          path: '/live-viewer/:id',
          builder: (_, s) => LiveViewerScreen(
            sessionId: s.pathParameters['id']!,
            host:      s.uri.queryParameters['host']  ?? '',
            title:     s.uri.queryParameters['title'] ?? '',
          ),
        ),
        GoRoute(path: '/groups', builder: (_, __) => const GroupsScreen()),
        GoRoute(
          path: '/group/:id',
          builder: (_, s) => GroupDetailScreen(
            groupId:   s.pathParameters['id']!,
            groupName: s.uri.queryParameters['name'] ?? '',
          ),
        ),
        GoRoute(
          path: '/chat',
          builder: (_, s) => ChatScreen(
            conversationId: s.uri.queryParameters['sessionId']
                ?? s.uri.queryParameters['conversationId'],
          ),
        ),
        GoRoute(path: '/create-status', builder: (_, __) => const CreateStatusScreen()),

        GoRoute(path: '/tasks',    builder: (_, __) => const TasksScreen()),
        GoRoute(path: '/skills',   builder: (_, __) => const SkillsScreen()),
        GoRoute(
          path: '/skills/:id',
          builder: (_, s) =>
              SkillDetailScreen(moduleId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/roadmap',      builder: (_, __) => const RoadmapScreen()),
        GoRoute(path: '/earnings',     builder: (_, __) => const EarningsScreen()),
        GoRoute(path: '/analytics',    builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
        GoRoute(path: '/goals',        builder: (_, __) => const GoalsScreen()),
        GoRoute(path: '/expenses',     builder: (_, __) => const ExpensesScreen()),
        GoRoute(path: '/referrals',    builder: (_, __) => const ReferralsScreen()),
        GoRoute(path: '/streak',       builder: (_, __) => const StreakScreen()),
        GoRoute(path: '/contracts',    builder: (_, __) => const ContractsScreen()),
        GoRoute(path: '/crm',          builder: (_, __) => const CrmScreen()),
        GoRoute(path: '/challenges',   builder: (_, __) => const ChallengesScreen()),
        GoRoute(path: '/portfolio',    builder: (_, __) => const PortfolioScreen()),
        GoRoute(path: '/memory',       builder: (_, __) => const IncomeMemoryScreen()),
        GoRoute(path: '/collaboration',builder: (_, __) => const CollaborationScreen()),

        GoRoute(path: '/workflow',     builder: (_, __) => const WorkflowHubScreen()),
        GoRoute(path: '/workflow/new', builder: (_, __) => const WorkflowResearchScreen()),
        GoRoute(
          path: '/workflow/:id',
          builder: (_, s) => WorkflowDetailScreen(
            workflowId: s.pathParameters['id']!,
          ),
        ),

        GoRoute(
          path: '/agent',
          builder: (_, s) {
            final extra = s.extra as Map<String, dynamic>? ?? {};
            return AgentScreen(
              workflowId: s.uri.queryParameters['workflowId']
                  ?? extra['workflowId']?.toString(),
              sessionId: s.uri.queryParameters['sessionId']
                  ?? extra['sessionId']?.toString(),
              handoffTask:      extra['handoffTask']?.toString(),
              handoffSessionId: extra['handoffSessionId']?.toString(),
              handoffTemplate:  extra['handoffTemplate'] as Map<String, dynamic>?,
              handoffQuestions: (extra['handoffQuestions'] as List?)
                  ?.cast<Map<String, dynamic>>(),
            );
          },
        ),

        GoRoute(path: '/pulse',       builder: (_, __) => const MarketPulseScreen()),
        GoRoute(path: '/methods',     builder: (_, __) => const MethodsBrainScreen()),
        GoRoute(path: '/marketplace', builder: (_, __) => const MarketplaceScreen()),
      ],
    ),
  ],
);

// ── Error page ─────────────────────────────────────────────────────────────
class _ErrorPage extends StatelessWidget {
  final String? error;
  const _ErrorPage({this.error});

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Page not found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ctx.go('/home'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}
