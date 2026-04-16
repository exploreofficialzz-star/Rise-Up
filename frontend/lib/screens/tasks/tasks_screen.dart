// frontend/lib/screens/tasks/tasks_screen.dart
//
// Production-ready Tasks Screen
// ─────────────────────────────────────────────────────────────────────────────
//  • All tasks are AI-generated — zero hardcoded text
//  • Free users: aggressive ad monetisation (banner sticky, inline every 3rd
//    card, interstitial on accept/complete/tab-switch, rewarded gate on
//    generate-limit and AI guidance)
//  • Premium users: zero ads, unlimited generation, instant AI guidance
//  • Tapping any task card opens TaskDetailSheet (steps, links, lessons,
//    contacts, AI mentor follow-up)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../../utils/app_review_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/ad_widgets.dart';
import 'task_detail_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const int _kFreeGenerationsPerDay = 3;
const int _kFreeTasksPerGeneration = 5;
const int _kPremiumTasksPerGeneration = 10;
const int _kListAdFrequency = 3; // 1 ad after every N real tasks
const String _kPrefGenDate  = 'tasks_gen_date';
const String _kPrefGenCount = 'tasks_gen_count';

// ═══════════════════════════════════════════════════════════════════════════════
// TasksScreen
// ═══════════════════════════════════════════════════════════════════════════════

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── State ──────────────────────────────────────────────────────────────────
  List _suggested = [], _active = [], _completed = [];
  bool _loading    = false;
  bool _generating = false;
  bool _isPremium  = false;

  Map<String, dynamic>? _profile;
  int  _tabChanges     = 0;
  int  _todayGenCount  = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _load();
    _loadGenCount();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  // ── Ad helpers (tab change) ────────────────────────────────────────────────

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) return;
    _tabChanges++;
    // Show interstitial every 2nd tab switch for free users
    if (!_isPremium && _tabChanges % 2 == 0) {
      adService.showInterstitialIfReady();
    }
  }

  // ── Generation quota ───────────────────────────────────────────────────────

  Future<void> _loadGenCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    if (prefs.getString(_kPrefGenDate) != today) {
      await prefs.setString(_kPrefGenDate, today);
      await prefs.setInt(_kPrefGenCount, 0);
      if (mounted) setState(() => _todayGenCount = 0);
    } else {
      final count = prefs.getInt(_kPrefGenCount) ?? 0;
      if (mounted) setState(() => _todayGenCount = count);
    }
  }

  Future<void> _incrementGenCount() async {
    final prefs = await SharedPreferences.getInstance();
    final newCount = (_todayGenCount + 1);
    await prefs.setInt(_kPrefGenCount, newCount);
    await prefs.setString(_kPrefGenDate, _todayString());
    if (mounted) setState(() => _todayGenCount = newCount);
  }

  bool get _canGenerateFree => _todayGenCount < _kFreeGenerationsPerDay;

  String _todayString() =>
      DateTime.now().toIso8601String().split('T')[0];

  int get _generationsRemaining =>
      _isPremium ? 999 : (_kFreeGenerationsPerDay - _todayGenCount).clamp(0, _kFreeGenerationsPerDay);

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getTasks(),
        api.getProfile().catchError((_) => <String, dynamic>{}),
      ]);

      final all     = results[0] as List;
      final profile = results[1] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _suggested = all.where((t) => t['status'] == 'suggested').toList();
        _active    = all.where((t) => t['status'] == 'in_progress').toList();
        _completed = all.where((t) => t['status'] == 'completed').toList();
        _isPremium = profile['subscription_tier'] == 'premium';
        _profile   = profile;
        _loading   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Generate tasks ─────────────────────────────────────────────────────────

  Future<void> _generateTasks() async {
    if (!_isPremium && !_canGenerateFree) {
      _showGenerateLimitSheet();
      return;
    }

    setState(() => _generating = true);
    try {
      await api.generateTasks(
        count: _isPremium ? _kPremiumTasksPerGeneration : _kFreeTasksPerGeneration,
      );
      if (!_isPremium) await _incrementGenCount();
      await _load();

      if (!_isPremium && mounted) {
        await adService.showInterstitialIfReady();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not generate tasks. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        setState(() => _generating = false);
      }
    }
  }

  // ── Task actions ───────────────────────────────────────────────────────────

  Future<void> _acceptTask(String id) async {
    await api.updateTask(id, status: 'in_progress');
    await _load();
    HapticFeedback.lightImpact();
    if (!_isPremium && mounted) {
      await adService.showInterstitialIfReady();
    }
  }

  Future<void> _completeTask(String id) async {
    double? earned;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EarningsModal(onSave: (v) => earned = v),
    );

    await api.updateTask(id, status: 'completed', earnings: earned);
    await _load();
    HapticFeedback.lightImpact();

    if (mounted && earned != null && earned! > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('🎉 Earning logged! You\'re building real wealth.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }

    // Force interstitial on completion — high value moment for free users
    if (!_isPremium && mounted) {
      await adService.forceShowInterstitial();
    }

    if (mounted) await appReviewService.onTaskCompleted(context);
  }

  Future<void> _skipTask(String id) async {
    await api.skipTask(id);
    await _load();
  }

  // ── Task detail ────────────────────────────────────────────────────────────

  void _openTaskDetail(Map task) {
    final status = task['status'] as String? ?? '';
    TaskDetailSheet.show(
      context,
      task: task,
      isPremium: _isPremium,
      onAccept:   status == 'suggested'   ? () => _acceptTask(task['id'] as String)   : null,
      onComplete: status == 'in_progress' ? () => _completeTask(task['id'] as String) : null,
      onSkip:     status == 'suggested'   ? () => _skipTask(task['id'] as String)      : null,
    );
  }

  // ── Generate-limit gate sheet ──────────────────────────────────────────────

  void _showGenerateLimitSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _GenerateLimitSheet(
        onWatchAd: () async {
          Navigator.pop(ctx);
          final ok = await adService.showRewardedAd(
            featureKey: 'task_generate_extra',
            onRewarded: () async {
              // Grant one extra generation
              final prefs = await SharedPreferences.getInstance();
              final count = (prefs.getInt(_kPrefGenCount) ?? _kFreeGenerationsPerDay) - 1;
              await prefs.setInt(_kPrefGenCount, count.clamp(0, _kFreeGenerationsPerDay));
              if (mounted) {
                setState(() => _todayGenCount = count.clamp(0, _kFreeGenerationsPerDay));
                _generateTasks();
              }
            },
            onDismissed: () {},
          );
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Ad not available right now. Try again shortly.'),
            ));
          }
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _loading ? null : _buildFAB(),
      // Sticky banner at the very bottom for free users
      bottomNavigationBar: _isPremium
          ? null
          : adService.getStickyBanner(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgDark,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Income Tasks', style: AppTextStyles.h3),
          if (!_isPremium && _todayGenCount > 0)
            Text(
              '$_generationsRemaining generation${_generationsRemaining == 1 ? "" : "s"} left today',
              style: AppTextStyles.caption.copyWith(color: AppColors.warning),
            ),
        ],
      ),
      actions: [
        if (_isPremium)
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: AppRadius.pill,
            ),
            child: Text('PRO', style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            )),
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
          onPressed: _loading ? null : _load,
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        labelStyle: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTextStyles.label,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          Tab(text: 'Suggested (${_suggested.length})'),
          Tab(text: 'Active (${_active.length})'),
          Tab(text: 'Done (${_completed.length})'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        // ── Suggested ──────────────────────────────────────────────────────
        _TaskList(
          tasks:      _suggested,
          isPremium:  _isPremium,
          emptyIcon:  Iconsax.flash,
          emptyTitle: _todayGenCount == 0
              ? 'Ready to build income?'
              : 'All tasks in progress',
          emptySubtitle: _todayGenCount == 0
              ? 'Generate AI-powered income tasks personalised to your skills and location.'
              : 'Accept more tasks from suggestions, or generate a fresh batch.',
          emptyAction: GradientButton(
            text:      _generating ? 'Generating...' : '⚡ Generate My Tasks',
            onTap:     _generating ? null : _generateTasks,
            isLoading: _generating,
          ),
          onCardTap: _openTaskDetail,
          onAccept:  _acceptTask,
          onRefresh: _load,
        ),

        // ── Active ─────────────────────────────────────────────────────────
        _TaskList(
          tasks:      _active,
          isPremium:  _isPremium,
          emptyIcon:  Iconsax.play_circle,
          emptyTitle: 'No active tasks yet',
          emptySubtitle: 'Accept a suggested task to start earning. Your AI mentor will guide you every step.',
          onCardTap:  _openTaskDetail,
          onComplete: _completeTask,
          onRefresh:  _load,
        ),

        // ── Done ───────────────────────────────────────────────────────────
        _TaskList(
          tasks:       _completed,
          isPremium:   _isPremium,
          emptyIcon:   Iconsax.medal,
          emptyTitle:  'Your wins will appear here',
          emptySubtitle: 'Complete your first task — every earning is a step toward financial freedom.',
          isCompleted: true,
          onCardTap:   _openTaskDetail,
          onRefresh:   _load,
        ),
      ],
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _generating ? null : _generateTasks,
      backgroundColor: _generating ? AppColors.bgSurface : AppColors.primary,
      elevation: 4,
      icon: _generating
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Icon(Icons.add_rounded, color: Colors.white),
      label: Text(
        _generating
            ? 'Generating...'
            : _isPremium
                ? 'New Tasks'
                : 'New Tasks ($_generationsRemaining left)',
        style: AppTextStyles.label.copyWith(
          color: Colors.white, fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _TaskList  — handles empty state + ad-injected list
// ═══════════════════════════════════════════════════════════════════════════════

class _TaskList extends StatelessWidget {
  final List   tasks;
  final bool   isPremium;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final Widget? emptyAction;
  final bool   isCompleted;

  // Callbacks
  final void Function(Map task)    onCardTap;
  final void Function(String id)?  onAccept;
  final void Function(String id)?  onComplete;
  final Future<void> Function()    onRefresh;

  const _TaskList({
    required this.tasks,
    required this.isPremium,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.emptyAction,
    this.isCompleted = false,
    required this.onCardTap,
    this.onAccept,
    this.onComplete,
    required this.onRefresh,
  });

  // ── Ad injection math ──────────────────────────────────────────────────────
  // For free users, inject an ad card after every N real tasks.
  // Visual layout: [task][task][task][AD][task][task][task][AD]...

  int get _taskCount => tasks.length;

  int _totalVisualItems() {
    if (isPremium || _taskCount == 0) return _taskCount;
    return _taskCount + (_taskCount ~/ _kListAdFrequency);
  }

  bool _isAdSlot(int visualIndex) {
    if (isPremium) return false;
    return (visualIndex + 1) % (_kListAdFrequency + 1) == 0;
  }

  int _realIndex(int visualIndex) {
    // Strip out ad slots to get real task index
    return visualIndex - (visualIndex ~/ (_kListAdFrequency + 1));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(emptyIcon, size: 40, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              Text(emptyTitle,
                  style: AppTextStyles.h4, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(emptySubtitle,
                  style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
              if (emptyAction != null) ...[
                const SizedBox(height: 28),
                emptyAction!,
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          16, 12, 16,
          // Extra bottom padding so last card clears FAB + banner
          isPremium ? 100 : 160,
        ),
        itemCount: _totalVisualItems(),
        itemBuilder: (_, visualIndex) {
          // ── Ad slot ────────────────────────────────────────────────────────
          if (_isAdSlot(visualIndex)) {
            return _InlineAdCard(key: ValueKey('ad_$visualIndex'));
          }

          // ── Task card ──────────────────────────────────────────────────────
          final idx  = _realIndex(visualIndex);
          if (idx >= tasks.length) return const SizedBox.shrink();
          final task = tasks[idx] as Map;

          return _TaskCard(
            key:         ValueKey(task['id']),
            task:        task,
            isCompleted: isCompleted,
            onTap:       () => onCardTap(task),
            onAccept:    onAccept  != null ? () => onAccept!(task['id'] as String)  : null,
            onComplete:  onComplete != null ? () => onComplete!(task['id'] as String) : null,
          )
            .animate()
            .fadeIn(delay: Duration(milliseconds: (idx * 50).clamp(0, 300)))
            .slideY(begin: 0.08, curve: Curves.easeOut);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _InlineAdCard  — compact inline ad injected into the task list
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineAdCard extends StatelessWidget {
  const _InlineAdCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.bgSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Sponsored" label
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Sponsored',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted)),
              ),
            ]),
          ),
          // Actual AdMob banner widget (falls back gracefully)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: BannerAdWidget(),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _TaskCard  — task preview card
// ═══════════════════════════════════════════════════════════════════════════════

class _TaskCard extends StatelessWidget {
  final Map      task;
  final bool     isCompleted;
  final VoidCallback  onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onComplete;

  const _TaskCard({
    super.key,
    required this.task,
    required this.isCompleted,
    required this.onTap,
    this.onAccept,
    this.onComplete,
  });

  Color get _categoryColor {
    switch (task['category'] as String? ?? '') {
      case 'freelance': return AppColors.primary;
      case 'content':   return AppColors.accent;
      case 'digital':   return AppColors.gold;
      case 'gig':       return AppColors.success;
      default:          return AppColors.info;
    }
  }

  String _difficultyLabel(String? d) {
    switch (d) {
      case 'easy':   return '🟢 Easy';
      case 'medium': return '🟡 Medium';
      case 'hard':   return '🔴 Hard';
      default:       return d ?? '';
    }
  }

  String _earningsText() {
    final actual    = task['actual_earnings'];
    final estimated = task['estimated_earnings'];
    final currency  = task['currency'] ?? 'NGN';

    if (actual != null && (actual as num) > 0) {
      return 'Earned: $currency $actual';
    }

    // earning_potential may be a map {min, max, currency, period}
    final potential = task['earning_potential'];
    if (potential is Map) {
      final min = potential['min'];
      final max = potential['max'];
      final cur = potential['currency'] ?? currency;
      if (min != null && max != null) {
        return 'Potential: $cur $min–$max/mo';
      }
    }

    if (estimated != null) {
      return 'Potential: $currency $estimated';
    }
    return 'Potential: varies';
  }

  @override
  Widget build(BuildContext context) {
    final steps = (task['action_steps'] as List?) ?? (task['steps'] as List?) ?? [];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: isCompleted
                ? AppColors.success.withOpacity(0.25)
                : AppColors.bgSurface,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────────
            Row(children: [
              _CategoryBadge(
                label: task['category'] as String? ?? 'task',
                color: _categoryColor,
              ),
              if (task['difficulty'] != null) ...[
                const SizedBox(width: 6),
                Text(_difficultyLabel(task['difficulty'] as String?),
                    style: AppTextStyles.caption),
              ],
              const Spacer(),
              if (isCompleted)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 18)
              else
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 18),
            ]),

            const SizedBox(height: 10),

            // ── Title ──────────────────────────────────────────────────────
            Text(
              task['title'] as String? ?? 'Income Task',
              style: AppTextStyles.h4.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),

            // ── Description ────────────────────────────────────────────────
            Text(
              task['description'] as String? ?? '',
              style: AppTextStyles.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            // ── Earnings + platform ────────────────────────────────────────
            Row(children: [
              const Icon(Icons.attach_money_rounded,
                  color: AppColors.success, size: 14),
              const SizedBox(width: 3),
              Text(_earningsText(),
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.success)),
              if (task['platform'] != null) ...[
                const Spacer(),
                const Icon(Iconsax.global, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(task['platform'] as String,
                    style: AppTextStyles.caption),
              ],
            ]),

            // ── Steps preview ──────────────────────────────────────────────
            if (!isCompleted && steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StepsPreview(steps: steps.take(2).toList()),
            ],

            // ── Time / startup cost chips ──────────────────────────────────
            if (task['time_to_first_earning'] != null ||
                task['startup_cost'] != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (task['time_to_first_earning'] != null)
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    label: task['time_to_first_earning'] as String,
                  ),
                if (task['startup_cost'] != null) ...[
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Start: ${task['startup_cost']}',
                  ),
                ],
              ]),
            ],

            // ── Action buttons ─────────────────────────────────────────────
            if (!isCompleted) ...[
              const SizedBox(height: 12),
              Row(children: [
                // "View Details" always visible — opens full detail sheet
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.bgSurface),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.md),
                    ),
                    child: Text('View Details',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 8),
                if (onAccept != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.md),
                        elevation: 0,
                      ),
                      child: Text('Start ⚡',
                          style: AppTextStyles.label
                              .copyWith(color: Colors.white)),
                    ),
                  ),
                if (onComplete != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.md),
                        elevation: 0,
                      ),
                      child: Text('Done ✓',
                          style: AppTextStyles.label
                              .copyWith(color: Colors.white)),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Small reusable sub-widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _CategoryBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const _CategoryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: AppTextStyles.caption
            .copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.sm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption),
      ]),
    );
  }
}

class _StepsPreview extends StatelessWidget {
  final List steps;
  const _StepsPreview({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps.asMap().entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.key + 1}.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  e.value.toString(),
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _GenerateLimitSheet
// ═══════════════════════════════════════════════════════════════════════════════

class _GenerateLimitSheet extends StatelessWidget {
  final VoidCallback onWatchAd;
  const _GenerateLimitSheet({required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
              )),
          const SizedBox(height: 24),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('⚡', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 16),
          Text('Daily Limit Reached',
              style: AppTextStyles.h4, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'You\'ve used your $_kFreeGenerationsPerDay free task generations today.\n'
            'Watch a short ad to unlock 1 more generation right now.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Watch ad CTA
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onWatchAd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
                elevation: 0,
              ),
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 20),
              label: Text('Watch Ad — Get 1 More Generation',
                  style: AppTextStyles.label
                      .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          // Upgrade CTA
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              text: '⭐ Go Premium — Unlimited Tasks',
              onTap: () {
                Navigator.pop(context);
                // Navigate to premium screen
                // context.go('/premium');
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Come back tomorrow',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _EarningsModal
// ═══════════════════════════════════════════════════════════════════════════════

class _EarningsModal extends StatefulWidget {
  final Function(double?) onSave;
  const _EarningsModal({required this.onSave});

  @override
  State<_EarningsModal> createState() => _EarningsModalState();
}

class _EarningsModalState extends State<_EarningsModal> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
              )),
          Text('🎉 Task complete! How much did you earn?',
              style: AppTextStyles.h4),
          const SizedBox(height: 6),
          Text('Log your earnings to track your wealth progress.',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Amount earned (optional)',
              prefixText: '₦ ',
              prefixStyle: AppTextStyles.body.copyWith(color: AppColors.success),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  widget.onSave(null);
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.bgSurface),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                ),
                child: const Text('Skip'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  widget.onSave(double.tryParse(_ctrl.text));
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                  elevation: 0,
                ),
                child: const Text('Log Earning 💰'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
