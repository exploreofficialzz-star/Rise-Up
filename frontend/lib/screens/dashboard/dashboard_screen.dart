// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/stage_badge.dart';
import '../../widgets/task_preview_card.dart';
import '../../widgets/gradient_button.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────
//  In-Memory Dashboard Cache  (TTL = 5 min, like FB/YouTube)
// ─────────────────────────────────────────────────────────────
class _DashboardCache {
  static Map?      _stats;
  static List?     _tasks;
  static Map?      _streak;
  static DateTime? _ts;
  static const _ttl = Duration(minutes: 5);

  static bool get valid =>
      _stats != null && _ts != null &&
      DateTime.now().difference(_ts!) < _ttl;

  static void save(Map s, List t, Map st) {
    _stats  = s; _tasks = t; _streak = st;
    _ts     = DateTime.now();
  }

  static void bust() { _stats = null; _ts = null; }
}

// ─────────────────────────────────────────────────────────────
//  DashboardScreen
// ─────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // keep scroll position + state

  Map  _stats  = {};
  List _tasks  = [];
  Map  _streak = {};
  bool _loading       = true;
  bool _networkError  = false;
  bool _refreshing    = false;
  final _scaffoldKey  = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _load(fromCache: true);
  }

  // ── Load (cache-first, then background refresh) ──────────
  Future<void> _load({bool fromCache = false, bool forceRefresh = false}) async {
    // 1. Serve from cache instantly
    if (fromCache && _DashboardCache.valid && !forceRefresh) {
      if (mounted) {
        setState(() {
          _stats   = _DashboardCache._stats!;
          _tasks   = _DashboardCache._tasks!;
          _streak  = _DashboardCache._streak!;
          _loading = false;
          _networkError = false;
        });
      }
      // Still do a silent background refresh
      _silentRefresh();
      return;
    }

    // 2. Full fetch
    if (!_refreshing) {
      setState(() { _refreshing = true; });
    }

    try {
      final results = await Future.wait([
        api.getStats(),
        api.getTasks(status: 'suggested'),
        api.getStreak(),
      ]).timeout(const Duration(seconds: 15));

      final stats  = results[0] as Map;
      final tasks  = (results[1] as List).take(3).toList();
      final streak = results[2] as Map;

      _DashboardCache.save(stats, tasks, streak);

      if (mounted) {
        setState(() {
          _stats  = stats;
          _tasks  = tasks;
          _streak = streak;
          _loading      = false;
          _refreshing   = false;
          _networkError = false;
        });
      }
    } on TimeoutException {
      _handleNetworkError();
    } catch (_) {
      _handleNetworkError();
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([
        api.getStats(),
        api.getTasks(status: 'suggested'),
        api.getStreak(),
      ]).timeout(const Duration(seconds: 20));

      final stats  = results[0] as Map;
      final tasks  = (results[1] as List).take(3).toList();
      final streak = results[2] as Map;
      _DashboardCache.save(stats, tasks, streak);

      if (mounted) {
        setState(() {
          _stats  = stats;
          _tasks  = tasks;
          _streak = streak;
        });
      }
    } catch (_) {/* silent – cached data stays */}
  }

  void _handleNetworkError() {
    if (mounted) {
      setState(() {
        _loading      = false;
        _refreshing   = false;
        // If we have cached data, show it silently; only show error if nothing cached
        _networkError = !_DashboardCache.valid;
        if (_DashboardCache.valid) {
          _stats  = _DashboardCache._stats!;
          _tasks  = _DashboardCache._tasks!;
          _streak = _DashboardCache._streak!;
        }
      });
    }
  }

  Future<void> _onRefresh() async {
    _DashboardCache.bust();
    await _load(forceRefresh: true);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final brightness = Theme.of(context).brightness;
    final isDark     = brightness == Brightness.dark;

    // ── Adaptive palette ──────────────────────────────────
    final bg        = isDark ? AppColors.bgDark        : const Color(0xFFF5F6FA);
    final bgCard    = isDark ? AppColors.bgCard        : Colors.white;
    final bgSurface = isDark ? AppColors.bgSurface     : const Color(0xFFEEF0F6);
    final txtPrimary  = isDark ? Colors.white            : const Color(0xFF0D0D1A);
    final txtSecond   = isDark ? Colors.white70          : const Color(0xFF5A5F7A);
    final txtMuted    = isDark ? Colors.white38          : const Color(0xFF9399B2);
    final divider   = isDark ? const Color(0xFF2A2A3E)  : const Color(0xFFE4E6F0);

    final profile    = _stats['profile'] as Map? ?? {};
    final name       = profile['full_name']?.toString().split(' ').first ?? 'Champion';
    final stage      = profile['stage']?.toString() ?? 'survival';
    final stageInfo  = StageInfo.get(stage);
    final totalEarned = (_stats['total_earned'] ?? 0.0) as num;
    final tasksData  = _stats['tasks']  as Map? ?? {};
    final skillsData = _stats['skills'] as Map? ?? {};
    final isPremium  = (_stats['subscription'] ?? 'free') == 'premium';
    final currency   = profile['currency']?.toString() ?? 'NGN';
    // Determine locale-formatted currency symbol
    final currencySymbol = _currencySymbol(currency);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: AppColors.bgDark,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white,
            ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bg,
        drawer: _DashboardDrawer(
          profile: profile,
          isPremium: isPremium,
          isDark: isDark,
          bgCard: bgCard,
          bgSurface: bgSurface,
          txtPrimary: txtPrimary,
          txtSecond: txtSecond,
          txtMuted: txtMuted,
          divider: divider,
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          backgroundColor: bgCard,
          child: _networkError
              ? _NetworkErrorView(
                  bg: bg,
                  txtPrimary: txtPrimary,
                  txtSecond: txtSecond,
                  onRetry: () => _load(forceRefresh: true),
                )
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── SliverAppBar ──────────────────────
                    _DashboardAppBar(
                      loading: _loading,
                      greeting: _greeting,
                      name: name,
                      stage: stage,
                      stageInfo: stageInfo,
                      isDark: isDark,
                      scaffoldKey: _scaffoldKey,
                      refreshing: _refreshing,
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _loading
                            ? _DashboardSkeleton(isDark: isDark, bgCard: bgCard, bgSurface: bgSurface)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  // ── Earnings Hero ──────
                                  _EarningsHero(
                                    total: totalEarned.toDouble(),
                                    currency: currency,
                                    currencySymbol: currencySymbol,
                                    stage: stage,
                                    stageInfo: stageInfo,
                                    isPremium: isPremium,
                                    isDark: isDark,
                                    bgCard: bgCard,
                                    txtPrimary: txtPrimary,
                                    txtSecond: txtSecond,
                                  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04),

                                  const SizedBox(height: 16),

                                  // ── Stats Row ──────────
                                  _StatsRow(
                                    tasksData: tasksData,
                                    skillsData: skillsData,
                                    isDark: isDark,
                                    bgCard: bgCard,
                                  ).animate().fadeIn(delay: 80.ms, duration: 350.ms),

                                  const SizedBox(height: 20),

                                  // ── Streak chip ────────
                                  if (_streak['current_streak'] != null &&
                                      (_streak['current_streak'] as int? ?? 0) > 0)
                                    _StreakBanner(
                                      streak: _streak,
                                      isDark: isDark,
                                      bgCard: bgCard,
                                      txtPrimary: txtPrimary,
                                    ).animate().fadeIn(delay: 120.ms).slideX(begin: -0.05),

                                  if (_streak['current_streak'] != null &&
                                      (_streak['current_streak'] as int? ?? 0) > 0)
                                    const SizedBox(height: 16),

                                  // ── AI Mentor CTA ──────
                                  _AiMentorCTA(isDark: isDark)
                                    .animate().fadeIn(delay: 160.ms, duration: 350.ms),

                                  const SizedBox(height: 20),

                                  // ── Income Tools ───────
                                  Text('Income Tools',
                                    style: AppTextStyles.h4.copyWith(color: txtPrimary),
                                  ),
                                  const SizedBox(height: 12),
                                  _IncomeToolsGrid(isDark: isDark, bgCard: bgCard)
                                    .animate().fadeIn(delay: 200.ms, duration: 350.ms),

                                  const SizedBox(height: 24),

                                  // ── Today's Tasks ──────
                                  _TasksSection(
                                    tasks: _tasks,
                                    isDark: isDark,
                                    bgCard: bgCard,
                                    bgSurface: bgSurface,
                                    txtPrimary: txtPrimary,
                                    txtSecond: txtSecond,
                                  ).animate().fadeIn(delay: 240.ms, duration: 350.ms),

                                  // ── Premium Upsell ─────
                                  if (!isPremium) ...[
                                    const SizedBox(height: 20),
                                    _PremiumBanner(isDark: isDark)
                                      .animate().fadeIn(delay: 280.ms),
                                  ],

                                  // ── Ad Banner (cross-platform) ──
                                  const SizedBox(height: 20),
                                  _CrossPlatformAdBanner(
                                    isPremium: isPremium,
                                    isDark: isDark,
                                    bgCard: bgCard,
                                    txtPrimary: txtPrimary,
                                    txtSecond: txtSecond,
                                    txtMuted: txtMuted,
                                  ).animate().fadeIn(delay: 320.ms),

                                  // safe area bottom padding
                                  SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static String _currencySymbol(String code) {
    const map = {
      'NGN': '₦', 'USD': '\$', 'EUR': '€', 'GBP': '£',
      'KES': 'KSh', 'GHS': '₵', 'ZAR': 'R', 'CAD': 'CA\$',
      'AUD': 'A\$', 'INR': '₹', 'BRL': 'R\$', 'MXN': 'MX\$',
      'JPY': '¥', 'CNY': '¥', 'EGP': 'E£', 'MAD': 'DH',
    };
    return map[code] ?? code;
  }
}

// ─────────────────────────────────────────────────────────────
//  Skeleton loader
// ─────────────────────────────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  final bool isDark;
  final Color bgCard, bgSurface;
  const _DashboardSkeleton({required this.isDark, required this.bgCard, required this.bgSurface});

  Widget _bone({double h = 16, double? w, double r = 8}) =>
    Container(
      height: h, width: w,
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(r),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
     .shimmer(duration: 1200.ms, color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero
        Container(
          height: 140, decoration: BoxDecoration(color: bgCard, borderRadius: AppRadius.xl),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _bone(h: 12, w: 140), const SizedBox(height: 14),
            _bone(h: 36, w: 180, r: 10), const SizedBox(height: 16),
            _bone(h: 12, w: 200),
          ]),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
         .shimmer(duration: 1400.ms, color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
        const SizedBox(height: 16),
        // Stats
        Row(children: List.generate(3, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 12 : 0),
            child: Container(
              height: 80, decoration: BoxDecoration(color: bgCard, borderRadius: AppRadius.lg),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .shimmer(duration: 1200.ms, delay: Duration(milliseconds: i * 80),
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ),
        ))),
        const SizedBox(height: 16),
        // Mentor CTA
        Container(
          height: 72,
          decoration: BoxDecoration(color: bgCard, borderRadius: AppRadius.lg),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
         .shimmer(duration: 1400.ms, color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Network error view
// ─────────────────────────────────────────────────────────────
class _NetworkErrorView extends StatelessWidget {
  final Color bg, txtPrimary, txtSecond;
  final VoidCallback onRetry;
  const _NetworkErrorView({
    required this.bg, required this.txtPrimary,
    required this.txtSecond, required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: txtSecond),
              const SizedBox(height: 16),
              Text('No connection', style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: txtPrimary)),
              const SizedBox(height: 8),
              Text(
                'Check your network and try again.\nYour cached data will appear once connected.',
                style: TextStyle(fontSize: 13, color: txtSecond, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SliverAppBar
// ─────────────────────────────────────────────────────────────
class _DashboardAppBar extends StatelessWidget {
  final bool loading, refreshing;
  final String greeting, name, stage;
  final Map stageInfo;
  final bool isDark;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const _DashboardAppBar({
    required this.loading, required this.refreshing, required this.greeting,
    required this.name, required this.stage, required this.stageInfo,
    required this.isDark, required this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    final topBg = isDark
        ? const Color(0xFF1A0E4F)
        : const Color(0xFFEBEEFF);
    final bottomBg = isDark ? AppColors.bgDark : const Color(0xFFF5F6FA);

    return SliverAppBar(
      expandedHeight: 170,
      pinned: true,
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.menu_rounded,
          color: isDark ? Colors.white70 : const Color(0xFF4A4F6A), size: 24),
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        if (refreshing)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white54 : AppColors.primary.withOpacity(0.6),
                ),
              ),
            ),
          ),
        IconButton(
          icon: Icon(Icons.notifications_none_rounded,
            color: isDark ? Colors.white70 : const Color(0xFF4A4F6A), size: 24),
          onPressed: () => context.go('/notifications'),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [topBg, bottomBg],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: loading
              ? const SizedBox()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$greeting,',
                              style: AppTextStyles.label.copyWith(
                                color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                              ),
                            ),
                            Text(name,
                              style: AppTextStyles.h2.copyWith(
                                color: isDark ? Colors.white : const Color(0xFF0D0D1A),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            StageBadge(stage: stage),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => context.go('/profile'),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primary.withOpacity(
                                    isDark ? 0.2 : 0.12),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: AppTextStyles.h4.copyWith(
                                    color: AppColors.primary,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Streak banner
// ─────────────────────────────────────────────────────────────
class _StreakBanner extends StatelessWidget {
  final Map streak;
  final bool isDark;
  final Color bgCard, txtPrimary;

  const _StreakBanner({
    required this.streak, required this.isDark,
    required this.bgCard, required this.txtPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final current = streak['current_streak'] as int? ?? 0;
    final longest = streak['longest_streak'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: const Color(0xFFFF6B35).withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$current-day streak!',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: txtPrimary,
                  ),
                ),
                Text('Best: $longest days · Keep going!',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF9399B2),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('+$current 🔥',
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: Color(0xFFFF6B35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Stats Row
// ─────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map tasksData, skillsData;
  final bool isDark;
  final Color bgCard;
  const _StatsRow({required this.tasksData, required this.skillsData,
      required this.isDark, required this.bgCard});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: StatCard(
          icon: Iconsax.task_square,
          label: 'Tasks Done',
          value: '${tasksData['completed'] ?? 0}',
          color: AppColors.accent,
        )),
        const SizedBox(width: 12),
        Expanded(child: StatCard(
          icon: Iconsax.book,
          label: 'Skills',
          value: '${skillsData['enrolled'] ?? 0}',
          color: AppColors.gold,
        )),
        const SizedBox(width: 12),
        Expanded(child: StatCard(
          icon: Iconsax.activity,
          label: 'Active',
          value: '${tasksData['active'] ?? 0}',
          color: AppColors.success,
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  AI Mentor CTA
// ─────────────────────────────────────────────────────────────
class _AiMentorCTA extends StatelessWidget {
  final bool isDark;
  const _AiMentorCTA({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/chat'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(isDark ? 0.20 : 0.10),
              AppColors.accent.withOpacity(isDark ? 0.10 : 0.06),
            ],
          ),
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: AppColors.primary.withOpacity(isDark ? 0.3 : 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 10, offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ask your AI Mentor',
                    style: AppTextStyles.h4.copyWith(
                      fontSize: 15,
                      color: isDark ? Colors.white : const Color(0xFF0D0D1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Get personalized income advice now',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.primary, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Income Tools Grid
// ─────────────────────────────────────────────────────────────
class _IncomeToolsGrid extends StatelessWidget {
  final bool isDark;
  final Color bgCard;
  const _IncomeToolsGrid({required this.isDark, required this.bgCard});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (Icons.auto_awesome_rounded, 'Agentic AI',  'Execute any task',   AppColors.accent,            '/agent',       'APEX'),
      (Iconsax.flash,              'Workflows',   'AI income plans',    AppColors.success,            '/workflow',    null),
      (Icons.trending_up_rounded,  'Market Pulse',"What pays now",      const Color(0xFFFF6B35),      '/pulse',       'LIVE'),
      (Icons.emoji_events_rounded, 'Challenges',  '30-day sprints',     const Color(0xFF6C5CE7),      '/challenges',  null),
      (Iconsax.briefcase,          'Client CRM',  'Track deals',        AppColors.primary,            '/crm',         null),
      (Iconsax.document_text,      'Contracts',   'AI contracts',       AppColors.gold,               '/contracts',   null),
      (Iconsax.gallery,            'Portfolio',   'Showcase work',      const Color(0xFFFF3CAC),      '/portfolio',   null),
      (Icons.psychology_rounded,   'Memory',      'Income DNA',         const Color(0xFF00B894),      '/memory',      null),
    ];

    return GridView.builder(
      itemCount: tiles.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (ctx, i) {
        final (icon, label, sub, color, route, badge) = tiles[i];
        return _FeatureTile(
          icon: icon, label: label, sub: sub,
          color: color, isDark: isDark,
          badge: badge,
          onTap: () => context.push(route),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Tasks Section
// ─────────────────────────────────────────────────────────────
class _TasksSection extends StatelessWidget {
  final List tasks;
  final bool isDark;
  final Color bgCard, bgSurface, txtPrimary, txtSecond;

  const _TasksSection({
    required this.tasks, required this.isDark,
    required this.bgCard, required this.bgSurface,
    required this.txtPrimary, required this.txtSecond,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isNotEmpty) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Today's Income Tasks",
                style: AppTextStyles.h4.copyWith(color: txtPrimary),
              ),
              GestureDetector(
                onTap: () => context.go('/tasks'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('See all',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tasks.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TaskPreviewCard(
              task: Map<String, dynamic>.from(e.value),
              onTap: () => context.go('/tasks'),
            ).animate().fadeIn(delay: Duration(milliseconds: 260 + e.key * 70)),
          )),
        ],
      );
    }

    // Empty state
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: bgSurface),
      ),
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 14),
          Text('Generate Your First Tasks',
            style: AppTextStyles.h4.copyWith(color: isDark ? Colors.white : const Color(0xFF0D0D1A)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text('Let AI find income opportunities tailored for you',
            style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? Colors.white54 : const Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          GradientButton(text: 'Generate Tasks 🎯', onTap: () => context.go('/tasks')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Cross-Platform Ad Banner  (no native SDK on web)
// ─────────────────────────────────────────────────────────────
class _CrossPlatformAdBanner extends StatelessWidget {
  final bool isPremium, isDark;
  final Color bgCard, txtPrimary, txtSecond, txtMuted;

  const _CrossPlatformAdBanner({
    required this.isPremium, required this.isDark,
    required this.bgCard, required this.txtPrimary,
    required this.txtSecond, required this.txtMuted,
  });

  @override
  Widget build(BuildContext context) {
    // Premium users see no ads
    if (isPremium) return const SizedBox.shrink();

    if (kIsWeb) {
      return _WebPromoBanner(isDark: isDark, bgCard: bgCard,
          txtPrimary: txtPrimary, txtSecond: txtSecond);
    }

    // Mobile: try native banner, gracefully fall back
    return _MobileAdBanner(isDark: isDark, bgCard: bgCard,
        txtPrimary: txtPrimary, txtSecond: txtSecond, txtMuted: txtMuted);
  }
}

// ── Web promo banner (styled, no SDK needed) ─────────────────
class _WebPromoBanner extends StatelessWidget {
  final bool isDark;
  final Color bgCard, txtPrimary, txtSecond;
  const _WebPromoBanner({required this.isDark, required this.bgCard,
      required this.txtPrimary, required this.txtSecond});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/payment'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(
              color: AppColors.gold.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(isDark ? 0.06 : 0.08),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Sponsored',
                      style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('Unlock Your Full Earning Potential',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: txtPrimary,
                    ),
                  ),
                  Text('Go Premium · All AI tools · \$15.99/mo',
                    style: TextStyle(fontSize: 11, color: txtSecond),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Upgrade',
                style: TextStyle(
                  color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mobile ad banner (tries native, falls back gracefully) ───
class _MobileAdBanner extends StatelessWidget {
  final bool isDark;
  final Color bgCard, txtPrimary, txtSecond, txtMuted;
  const _MobileAdBanner({required this.isDark, required this.bgCard,
      required this.txtPrimary, required this.txtSecond, required this.txtMuted});

  @override
  Widget build(BuildContext context) {
    // Attempt to use native ad widget, fall back to promo UI.
    // Replace the body of the try block with your native BannerAdWidget once
    // ad_service_mobile.dart exposes it properly.
    try {
      // Conditional: only attempt native ads on supported platforms
      // Uncomment when BannerAdWidget is confirmed available:
      // return const SizedBox(height: 60, child: BannerAdWidget());
      throw UnsupportedError('native-ads-fallback');
    } catch (_) {
      return _WebPromoBanner(isDark: isDark, bgCard: bgCard,
          txtPrimary: txtPrimary, txtSecond: txtSecond);
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  Earnings Hero
// ─────────────────────────────────────────────────────────────
class _EarningsHero extends StatelessWidget {
  final double total;
  final String currency, currencySymbol;
  final String stage;
  final Map stageInfo;
  final bool isPremium, isDark;
  final Color bgCard, txtPrimary, txtSecond;

  const _EarningsHero({
    required this.total, required this.currency, required this.currencySymbol,
    required this.stage, required this.stageInfo, required this.isPremium,
    required this.isDark, required this.bgCard,
    required this.txtPrimary, required this.txtSecond,
  });

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final stageColor = stageInfo['color'] as Color;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            stageColor.withOpacity(isDark ? 0.20 : 0.10),
            bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xl,
        border: Border.all(color: stageColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: stageColor.withOpacity(isDark ? 0.08 : 0.06),
            blurRadius: 16, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Earned via RiseUp',
                style: AppTextStyles.label.copyWith(
                  color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                ),
              ),
              if (isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.gold, AppColors.goldDark]),
                    borderRadius: AppRadius.pill,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text('Premium',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$currencySymbol ', style: AppTextStyles.h4.copyWith(
                color: stageColor, fontSize: 18,
              )),
              Text(_fmt(total),
                style: AppTextStyles.money.copyWith(
                  color: txtPrimary, fontSize: 36,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: stageColor.withOpacity(0.12),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stageInfo['emoji'] as String),
                    const SizedBox(width: 6),
                    Text(stageInfo['label'] as String,
                      style: AppTextStyles.caption.copyWith(
                        color: stageColor, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('Target: ${stageInfo['target']}',
                style: AppTextStyles.caption.copyWith(
                  color: isDark ? Colors.white38 : const Color(0xFF9399B2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Premium Banner
// ─────────────────────────────────────────────────────────────
class _PremiumBanner extends StatelessWidget {
  final bool isDark;
  const _PremiumBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/payment'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2D1B69), const Color(0xFF1A3A4F)]
                : [const Color(0xFFF5F0FF), const Color(0xFFEBF4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: AppColors.gold.withOpacity(isDark ? 0.3 : 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('👑', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upgrade to Premium',
                    style: AppTextStyles.h4.copyWith(color: AppColors.gold),
                  ),
                  const SizedBox(height: 2),
                  Text('Unlock AI roadmap, all skills & wealth tools · \$15.99/month',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.gold, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Dashboard Drawer
// ─────────────────────────────────────────────────────────────
class _DashboardDrawer extends StatelessWidget {
  final Map profile;
  final bool isPremium, isDark;
  final Color bgCard, bgSurface, txtPrimary, txtSecond, txtMuted, divider;

  const _DashboardDrawer({
    required this.profile, required this.isPremium, required this.isDark,
    required this.bgCard, required this.bgSurface,
    required this.txtPrimary, required this.txtSecond, required this.txtMuted,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    final name      = profile['full_name']?.toString() ?? 'User';
    final stage     = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final drawerBg  = isDark ? Colors.black : Colors.white;

    return Drawer(
      backgroundColor: drawerBg,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: AppColors.primary, fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: txtPrimary,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: (stageInfo['color'] as Color).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${stageInfo['emoji']} ${stageInfo['label']}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: stageInfo['color'] as Color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isPremium) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('⭐ Pro',
                                  style: TextStyle(
                                    fontSize: 10, color: AppColors.gold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: txtMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: divider, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _DSec('INCOME TOOLS', isDark: isDark),
                  _DIt(Icons.auto_awesome_rounded, 'Agentic AI',
                      'Execute ANY income task', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/agent'); },
                      badge: 'HEAVY', badgeColor: AppColors.accent),
                  _DIt(Iconsax.flash, 'Workflow Engine',
                      'AI income execution', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/workflow'); },
                      badge: 'NEW', badgeColor: AppColors.success),
                  _DIt(Iconsax.chart_3, 'Market Pulse',
                      'What pays right now', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/pulse'); },
                      badge: '🔥', badgeColor: const Color(0xFFFF6B35)),
                  _DIt(Icons.emoji_events_rounded, 'Challenges',
                      '30-day income sprints', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/challenges'); }),
                  _DIt(Iconsax.briefcase, 'Client CRM',
                      'Track clients & deals', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/crm'); }),
                  _DIt(Iconsax.document_text, 'Contracts & Invoices',
                      'AI contract writing', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/contracts'); }),
                  _DIt(Icons.psychology_rounded, 'Income Memory',
                      'Your income DNA', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/memory'); }),
                  _DIt(Iconsax.gallery, 'Portfolio',
                      'Shareable showcase', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/portfolio'); }),
                  _DIt(Iconsax.task_square, 'My Tasks',
                      'Daily income tasks', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/tasks'); }),
                  _DIt(Iconsax.map_1, 'Wealth Roadmap',
                      '3-stage plan', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/roadmap'); }),
                  _DIt(Iconsax.book, 'Skills',
                      'Earn-while-learning', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/skills'); }),
                  Divider(color: divider, height: 1),
                  _DSec('SOCIAL', isDark: isDark),
                  _DIt(Iconsax.home, 'Social Feed',
                      'Community posts', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/home'); }),
                  _DIt(Iconsax.people, 'Collaboration',
                      'Build together', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.push('/collaboration'); },
                      badge: 'NEW', badgeColor: AppColors.primary),
                  _DIt(Iconsax.message, 'Messages',
                      'DMs & groups', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/messages'); }),
                  _DIt(Icons.radio_button_checked_rounded, 'Go Live',
                      'Stream to community', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/live'); }),
                  Divider(color: divider, height: 1),
                  _DSec('FINANCE', isDark: isDark),
                  _DIt(Iconsax.money_recive, 'Earnings',
                      'Income tracker', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/earnings'); }),
                  _DIt(Iconsax.chart_2, 'Analytics',
                      'Growth stats', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/analytics'); }),
                  _DIt(Iconsax.wallet_minus, 'Expenses',
                      'Budget tracking', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/expenses'); }),
                  _DIt(Iconsax.flag, 'Goals',
                      'Targets', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/goals'); }),
                  Divider(color: divider, height: 1),
                  _DSec('ACCOUNT', isDark: isDark),
                  _DIt(Iconsax.award, 'Achievements',
                      'Badges', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/achievements'); }),
                  _DIt(Iconsax.user_tag, 'Referrals',
                      'Invite & earn', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/referrals'); }),
                  _DIt(Iconsax.setting_2, 'Settings',
                      'Preferences', isDark: isDark,
                      txtPrimary: txtPrimary, txtSecond: txtSecond, bgSurface: bgSurface,
                      onTap: () { Navigator.pop(context); context.go('/settings'); }),
                ],
              ),
            ),
            if (!isPremium)
              Padding(
                padding: const EdgeInsets.all(14),
                child: GestureDetector(
                  onTap: () { Navigator.pop(context); context.push('/premium'); },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Upgrade to Premium',
                                style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text('Unlimited AI + all features',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : const Color(0xFF9399B2),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 13, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Drawer helpers
// ─────────────────────────────────────────────────────────────
class _DSec extends StatelessWidget {
  final String label;
  final bool isDark;
  const _DSec(this.label, {required this.isDark});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
    child: Text(label,
      style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1,
        color: isDark ? Colors.white30 : const Color(0xFFB0B5CC),
      ),
    ),
  );
}

class _DIt extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  final bool isDark;
  final Color txtPrimary, txtSecond, bgSurface;
  final String? badge;
  final Color? badgeColor;

  const _DIt(this.icon, this.label, this.sub, {
    required this.onTap, required this.isDark,
    required this.txtPrimary, required this.txtSecond, required this.bgSurface,
    this.badge, this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        splashColor: AppColors.primary.withOpacity(0.06),
        highlightColor: AppColors.primary.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17,
                  color: isDark ? Colors.white70 : const Color(0xFF4A4F6A)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: txtPrimary,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? AppColors.primary)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(badge!,
                              style: TextStyle(
                                fontSize: 9,
                                color: badgeColor ?? AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(sub,
                      style: TextStyle(fontSize: 11, color: txtSecond),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                size: 15,
                color: isDark ? Colors.white24 : const Color(0xFFCDD0E0)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Feature Tile
// ─────────────────────────────────────────────────────────────
class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  final String? badge;
  const _FeatureTile({
    required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap, required this.isDark,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.10 : 0.07),
          borderRadius: AppRadius.lg,
          border: Border.all(color: color.withOpacity(isDark ? 0.22 : 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(label,
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0D0D1A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(badge!,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : const Color(0xFF9399B2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
