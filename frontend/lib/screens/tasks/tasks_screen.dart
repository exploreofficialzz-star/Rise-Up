// frontend/lib/screens/tasks/tasks_screen.dart
// v2.0 — Full Light/Dark Theme Adaptive
//
// All colors now derived from Theme.of(context).brightness exactly like HomeScreen:
//   dark ? Colors.black      : Colors.white         → bg
//   dark ? AppColors.bgCard  : Colors.white         → card
//   dark ? AppColors.bgSurface : Colors.grey.shade200 → border
//   dark ? Colors.white      : Colors.black87        → text
//   dark ? Colors.white54    : Colors.black45        → sub text
// Every widget that previously used AppColors.bgDark / bgCard / bgSurface
// now reads from the theme at build-time. Zero hardcoded theme assumptions.

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
const int    _kFreeGenerationsPerDay   = 3;
const int    _kFreeTasksPerGeneration  = 5;
const int    _kPremiumTasksPerGeneration = 10;
const int    _kListAdFrequency         = 3;
const String _kPrefGenDate             = 'tasks_gen_date';
const String _kPrefGenCount            = 'tasks_gen_count';

// =============================================================================
// TasksScreen
// =============================================================================
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List _suggested = [], _active = [], _completed = [];
  bool _loading    = false;
  bool _generating = false;
  bool _isPremium  = false;

  Map<String, dynamic>? _profile;
  int _tabChanges    = 0;
  int _todayGenCount = 0;

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

  // ── Ad helpers ─────────────────────────────────────────────────────────────
  void _onTabChanged() {
    if (!_tabs.indexIsChanging) return;
    _tabChanges++;
    if (!_isPremium && _tabChanges % 2 == 0) {
      adService.showInterstitialIfReady();
    }
  }

  // ── Generation quota ────────────────────────────────────────────────────────
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
    final prefs    = await SharedPreferences.getInstance();
    final newCount = _todayGenCount + 1;
    await prefs.setInt(_kPrefGenCount, newCount);
    await prefs.setString(_kPrefGenDate, _todayString());
    if (mounted) setState(() => _todayGenCount = newCount);
  }

  bool   get _canGenerateFree      => _todayGenCount < _kFreeGenerationsPerDay;
  String     _todayString()        => DateTime.now().toIso8601String().split('T')[0];
  int    get _generationsRemaining => _isPremium
      ? 999
      : (_kFreeGenerationsPerDay - _todayGenCount).clamp(0, _kFreeGenerationsPerDay);

  // ── Data loading ────────────────────────────────────────────────────────────
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

  // ── Generate tasks ──────────────────────────────────────────────────────────
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
      if (!_isPremium && mounted) await adService.showInterstitialIfReady();
    } catch (e) {
      if (mounted) {
        final dark = Theme.of(context).brightness == Brightness.dark;
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

  // ── Task actions ────────────────────────────────────────────────────────────
  Future<void> _acceptTask(String id) async {
    await api.updateTask(id, status: 'in_progress');
    await _load();
    HapticFeedback.lightImpact();
    if (!_isPremium && mounted) await adService.showInterstitialIfReady();
  }

  Future<void> _completeTask(String id) async {
    double? earned;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.bgCard : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
    if (!_isPremium && mounted) await adService.forceShowInterstitial();
    if (mounted) await appReviewService.onTaskCompleted(context);
  }

  Future<void> _skipTask(String id) async {
    await api.skipTask(id);
    await _load();
  }

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

  void _showGenerateLimitSheet() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: dark ? AppColors.bgCard : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _GenerateLimitSheet(
        isDark: dark,
        onWatchAd: () async {
          Navigator.pop(ctx);
          final ok = await adService.showRewardedAd(
            featureKey: 'task_generate_extra',
            onRewarded: () async {
              if (!mounted) return;
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

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final bg     = dark ? Colors.black : Colors.white;
    final card   = dark ? AppColors.bgCard : Colors.white;
    final border = dark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt    = dark ? Colors.white : Colors.black87;
    final sub    = dark ? Colors.white.withOpacity(0.54) : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(dark, card, border, txt, sub),
      body: _buildBody(dark, card, border, txt, sub),
      floatingActionButton: _loading ? null : _buildFAB(dark, txt),
      bottomNavigationBar: _isPremium
          ? null
          : adService.getStickyBanner(context),
    );
  }

  PreferredSizeWidget _buildAppBar(
    bool dark, Color card, Color border, Color txt, Color sub,
  ) {
    return AppBar(
      backgroundColor: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Income Tasks',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: txt)),
          if (!_isPremium && _todayGenCount > 0)
            Text(
              '$_generationsRemaining generation${_generationsRemaining == 1 ? "" : "s"} left today',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
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
                  colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('PRO',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: sub),
          onPressed: _loading ? null : _load,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(49),
        child: Column(children: [
          TabBar(
            controller: _tabs,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            labelColor: AppColors.primary,
            unselectedLabelColor: sub,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: 'Suggested (${_suggested.length})'),
              Tab(text: 'Active (${_active.length})'),
              Tab(text: 'Done (${_completed.length})'),
            ],
          ),
          Divider(height: 1, color: border),
        ]),
      ),
    );
  }

  Widget _buildBody(
    bool dark, Color card, Color border, Color txt, Color sub,
  ) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        // ── Suggested ──────────────────────────────────────────────────────
        _TaskList(
          tasks:     _suggested,
          isPremium: _isPremium,
          isDark:    dark,
          cardColor: card,
          borderColor: border,
          textColor: txt,
          subColor:  sub,
          emptyIcon:     Iconsax.flash,
          emptyTitle:    _todayGenCount == 0
              ? 'Ready to build income?'
              : 'All tasks in progress',
          emptySubtitle: _todayGenCount == 0
              ? 'Generate AI-powered income tasks personalised to your skills and location.'
              : 'Accept more tasks from suggestions, or generate a fresh batch.',
          emptyAction: _GenerateButton(
            generating: _generating,
            onTap: _generating ? null : _generateTasks,
          ),
          onCardTap: _openTaskDetail,
          onAccept:  _acceptTask,
          onRefresh: _load,
        ),

        // ── Active ─────────────────────────────────────────────────────────
        _TaskList(
          tasks:     _active,
          isPremium: _isPremium,
          isDark:    dark,
          cardColor: card,
          borderColor: border,
          textColor: txt,
          subColor:  sub,
          emptyIcon:     Iconsax.play_circle,
          emptyTitle:    'No active tasks yet',
          emptySubtitle: 'Accept a suggested task to start earning.',
          onCardTap:  _openTaskDetail,
          onComplete: _completeTask,
          onRefresh:  _load,
        ),

        // ── Done ───────────────────────────────────────────────────────────
        _TaskList(
          tasks:     _completed,
          isPremium: _isPremium,
          isDark:    dark,
          cardColor: card,
          borderColor: border,
          textColor: txt,
          subColor:  sub,
          emptyIcon:     Iconsax.medal,
          emptyTitle:    'Your wins will appear here',
          emptySubtitle: 'Complete your first task — every earning is a step toward financial freedom.',
          isCompleted: true,
          onCardTap:   _openTaskDetail,
          onRefresh:   _load,
        ),
      ],
    );
  }

  Widget _buildFAB(bool dark, Color txt) {
    return FloatingActionButton.extended(
      onPressed: _generating ? null : _generateTasks,
      backgroundColor: _generating
          ? (dark ? AppColors.bgSurface : Colors.grey.shade300)
          : AppColors.primary,
      elevation: 4,
      icon: _generating
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : const Icon(Icons.add_rounded, color: Colors.white),
      label: Text(
        _generating
            ? 'Generating...'
            : _isPremium
                ? 'New Tasks'
                : 'New Tasks ($_generationsRemaining left)',
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

// =============================================================================
// Generate Button Widget
// =============================================================================
class _GenerateButton extends StatelessWidget {
  final bool         generating;
  final VoidCallback? onTap;
  const _GenerateButton({required this.generating, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          gradient: onTap != null
              ? const LinearGradient(colors: [AppColors.primary, AppColors.accent])
              : null,
          color: onTap == null ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(24),
        ),
        child: generating
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 10),
                Text('Generating...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ])
            : const Text('⚡ Generate My Tasks',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}

// =============================================================================
// _TaskList  — empty state + ad-injected list
// =============================================================================
class _TaskList extends StatelessWidget {
  final List   tasks;
  final bool   isPremium, isDark, isCompleted;
  final Color  cardColor, borderColor, textColor, subColor;
  final IconData emptyIcon;
  final String   emptyTitle, emptySubtitle;
  final Widget?  emptyAction;

  final void Function(Map task)   onCardTap;
  final void Function(String id)? onAccept;
  final void Function(String id)? onComplete;
  final Future<void> Function()   onRefresh;

  const _TaskList({
    required this.tasks,
    required this.isPremium,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
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

  int _totalVisualItems() {
    if (isPremium || tasks.isEmpty) return tasks.length;
    return tasks.length + (tasks.length ~/ _kListAdFrequency);
  }

  bool _isAdSlot(int i)  => !isPremium && (i + 1) % (_kListAdFrequency + 1) == 0;
  int  _realIndex(int i) => i - (i ~/ (_kListAdFrequency + 1));

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(emptyIcon, size: 40,
                  color: isDark ? Colors.white38 : Colors.black26),
            ),
            const SizedBox(height: 20),
            Text(emptyTitle,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(emptySubtitle,
                style: TextStyle(fontSize: 13, color: subColor, height: 1.5),
                textAlign: TextAlign.center),
            if (emptyAction != null) ...[
              const SizedBox(height: 28),
              emptyAction!,
            ],
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      backgroundColor: cardColor,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 12, 16, isPremium ? 100 : 160),
        itemCount: _totalVisualItems(),
        itemBuilder: (_, visualIndex) {
          if (_isAdSlot(visualIndex)) {
            return _InlineAdCard(
              key:        ValueKey('ad_$visualIndex'),
              isDark:     isDark,
              cardColor:  cardColor,
              borderColor: borderColor,
            );
          }
          final idx  = _realIndex(visualIndex);
          if (idx >= tasks.length) return const SizedBox.shrink();
          final task = tasks[idx] as Map;
          return _TaskCard(
            key:         ValueKey(task['id']),
            task:        task,
            isCompleted: isCompleted,
            isDark:      isDark,
            cardColor:   cardColor,
            borderColor: borderColor,
            textColor:   textColor,
            subColor:    subColor,
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

// =============================================================================
// _InlineAdCard
// =============================================================================
class _InlineAdCard extends StatelessWidget {
  final bool  isDark;
  final Color cardColor, borderColor;
  const _InlineAdCard({super.key, required this.isDark, required this.cardColor, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Sponsored',
                style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38)),
          ),
        ),
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: BannerAdWidget(),
        )),
      ]),
    );
  }
}

// =============================================================================
// _TaskCard
// =============================================================================
class _TaskCard extends StatelessWidget {
  final Map      task;
  final bool     isCompleted, isDark;
  final Color    cardColor, borderColor, textColor, subColor;
  final VoidCallback  onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onComplete;

  const _TaskCard({
    super.key,
    required this.task,
    required this.isCompleted,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
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
    final currency  = task['currency'] ?? 'NGN';
    if (actual != null && (actual as num) > 0) return 'Earned: $currency $actual';
    final potential = task['earning_potential'];
    if (potential is Map) {
      final min = potential['min'];
      final max = potential['max'];
      final cur = potential['currency'] ?? currency;
      if (min != null && max != null) return 'Potential: $cur $min–$max/mo';
    }
    final estimated = task['estimated_earnings'];
    if (estimated != null) return 'Potential: $currency $estimated';
    return 'Potential: varies';
  }

  @override
  Widget build(BuildContext context) {
    final steps = (task['action_steps'] as List?) ?? (task['steps'] as List?) ?? [];
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCompleted
                ? AppColors.success.withOpacity(0.25)
                : borderColor,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header row ────────────────────────────────────────────────────
          Row(children: [
            _CategoryBadge(label: task['category'] as String? ?? 'task', color: _categoryColor),
            if (task['difficulty'] != null) ...[
              const SizedBox(width: 6),
              Text(_difficultyLabel(task['difficulty'] as String?),
                  style: TextStyle(fontSize: 11, color: subColor)),
            ],
            const Spacer(),
            if (isCompleted)
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18)
            else
              Icon(Icons.chevron_right_rounded, color: subColor, size: 18),
          ]),

          const SizedBox(height: 10),

          // ── Title ─────────────────────────────────────────────────────────
          Text(
            task['title'] as String? ?? 'Income Task',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 4),

          // ── Description ───────────────────────────────────────────────────
          Text(
            task['description'] as String? ?? '',
            style: TextStyle(fontSize: 13, color: subColor, height: 1.45),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),

          // ── Earnings + platform ───────────────────────────────────────────
          Row(children: [
            const Icon(Icons.attach_money_rounded, color: AppColors.success, size: 14),
            const SizedBox(width: 3),
            Text(_earningsText(),
                style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
            if (task['platform'] != null) ...[
              const Spacer(),
              Icon(Iconsax.global, size: 12, color: subColor),
              const SizedBox(width: 4),
              Text(task['platform'] as String,
                  style: TextStyle(fontSize: 11, color: subColor)),
            ],
          ]),

          // ── Steps preview ─────────────────────────────────────────────────
          if (!isCompleted && steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StepsPreview(steps: steps.take(2).toList(), subColor: subColor),
          ],

          // ── Info chips ────────────────────────────────────────────────────
          if (task['time_to_first_earning'] != null || task['startup_cost'] != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (task['time_to_first_earning'] != null)
                _InfoChip(
                  icon: Icons.access_time_rounded,
                  label: task['time_to_first_earning'] as String,
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  subColor: subColor,
                ),
              if (task['startup_cost'] != null) ...[
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Start: ${task['startup_cost']}',
                  isDark: isDark,
                  surfaceColor: surfaceColor,
                  subColor: subColor,
                ),
              ],
            ]),
          ],

          // ── Action buttons ────────────────────────────────────────────────
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('View Details',
                    style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 8),
              if (onAccept != null)
                Expanded(child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Start ⚡',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                )),
              if (onComplete != null)
                Expanded(child: ElevatedButton(
                  onPressed: onComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Done ✓',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                )),
            ]),
          ],
        ]),
      ),
    );
  }
}

// =============================================================================
// Small reusable sub-widgets
// =============================================================================
class _CategoryBadge extends StatelessWidget {
  final String label; final Color color;
  const _CategoryBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon; final String label;
  final bool isDark; final Color surfaceColor, subColor;
  const _InfoChip({required this.icon, required this.label, required this.isDark, required this.surfaceColor, required this.subColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: subColor),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, color: subColor)),
    ]),
  );
}

class _StepsPreview extends StatelessWidget {
  final List steps; final Color subColor;
  const _StepsPreview({required this.steps, required this.subColor});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: steps.asMap().entries.map((e) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${e.key + 1}.',
            style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Expanded(child: Text(e.value.toString(),
            style: TextStyle(fontSize: 11, color: subColor),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    )).toList(),
  );
}

// =============================================================================
// _GenerateLimitSheet
// =============================================================================
class _GenerateLimitSheet extends StatelessWidget {
  final bool isDark;
  final VoidCallback onWatchAd;
  const _GenerateLimitSheet({required this.isDark, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    final txt = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: isDark ? AppColors.bgSurface : Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 24),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), shape: BoxShape.circle),
          child: const Center(child: Text('⚡', style: TextStyle(fontSize: 36))),
        ),
        const SizedBox(height: 16),
        Text('Daily Limit Reached', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: txt), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'You\'ve used your $_kFreeGenerationsPerDay free task generations today.\nWatch a short ad to unlock 1 more generation right now.',
          style: TextStyle(fontSize: 13, color: sub, height: 1.5), textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: onWatchAd,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
          icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
          label: const Text('Watch Ad — Get 1 More Generation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: GradientButton(text: '⭐ Go Premium — Unlimited Tasks', onTap: () => Navigator.pop(context))),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Come back tomorrow', style: TextStyle(fontSize: 12, color: sub)),
        ),
      ]),
    );
  }
}

// =============================================================================
// _EarningsModal
// =============================================================================
class _EarningsModal extends StatefulWidget {
  final Function(double?) onSave;
  const _EarningsModal({required this.onSave});
  @override
  State<_EarningsModal> createState() => _EarningsModalState();
}

class _EarningsModalState extends State<_EarningsModal> {
  final _ctrl = TextEditingController();
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final txt    = dark ? Colors.white : Colors.black87;
    final sub    = dark ? Colors.white54 : Colors.black45;
    final surf   = dark ? AppColors.bgSurface : Colors.grey.shade100;
    final border = dark ? AppColors.bgSurface : Colors.grey.shade300;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: dark ? AppColors.bgSurface : Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
        Text('🎉 Task complete! How much did you earn?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: txt)),
        const SizedBox(height: 6),
        Text('Log your earnings to track your wealth progress.', style: TextStyle(fontSize: 13, color: sub)),
        const SizedBox(height: 20),
        TextField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: TextStyle(fontSize: 15, color: txt),
          decoration: InputDecoration(
            hintText: 'Amount earned (optional)',
            hintStyle: TextStyle(color: sub),
            prefixText: '₦ ',
            prefixStyle: const TextStyle(color: AppColors.success, fontSize: 15),
            filled: true,
            fillColor: surf,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () { widget.onSave(null); Navigator.pop(context); },
            style: OutlinedButton.styleFrom(side: BorderSide(color: border), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Skip', style: TextStyle(color: sub)),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () { widget.onSave(double.tryParse(_ctrl.text)); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: const Text('Log Earning 💰', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        ]),
      ]),
    );
  }
}
