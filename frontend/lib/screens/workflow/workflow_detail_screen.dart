// frontend/lib/screens/workflow/workflow_detail_screen.dart
// v3.3 — Expandable Steps · Inline AI Execution · Mentor AI · Save Outputs · Ad-wired

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../providers/locale_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STATE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

final workflowDetailProvider = StateNotifierProvider.family<
    WorkflowDetailNotifier, WorkflowDetailState, String>(
  (ref, id) => WorkflowDetailNotifier(ref, id),
);

class WorkflowDetailState {
  final String               workflowId;
  final Map<String, dynamic> workflow;
  final List<dynamic>        steps, freeTools, paidTools, revenueLogs;
  final bool                 isLoading;
  final String?              error;
  final int                  selectedTab;

  const WorkflowDetailState({
    required this.workflowId,
    this.workflow    = const {},
    this.steps       = const [],
    this.freeTools   = const [],
    this.paidTools   = const [],
    this.revenueLogs = const [],
    this.isLoading   = true,
    this.error,
    this.selectedTab = 0,
  });

  WorkflowDetailState copyWith({
    Map<String, dynamic>? workflow,
    List<dynamic>?        steps,
    List<dynamic>?        freeTools,
    List<dynamic>?        paidTools,
    List<dynamic>?        revenueLogs,
    bool?                 isLoading,
    String?               error,
    int?                  selectedTab,
  }) =>
      WorkflowDetailState(
        workflowId:  workflowId,
        workflow:    workflow    ?? this.workflow,
        steps:       steps       ?? this.steps,
        freeTools:   freeTools   ?? this.freeTools,
        paidTools:   paidTools   ?? this.paidTools,
        revenueLogs: revenueLogs ?? this.revenueLogs,
        isLoading:   isLoading   ?? this.isLoading,
        error:       error       ?? this.error,
        selectedTab: selectedTab ?? this.selectedTab,
      );

  double get totalRevenue    => (workflow['total_revenue']    as num?)?.toDouble() ?? 0.0;
  int    get progressPercent => (workflow['progress_percent'] as num?)?.toInt()    ?? 0;
  String get currency        => workflow['currency']?.toString()    ?? 'USD';
  String get language        => workflow['language']?.toString()    ?? 'en';
  String get region          => workflow['region']?.toString()      ?? 'global';
  String get timezone        => workflow['timezone']?.toString()    ?? 'UTC';
  String get incomeType      => workflow['income_type']?.toString() ?? 'other';
  String get title           => workflow['title']?.toString()       ?? 'Workflow';
  String get goal            => workflow['goal']?.toString()        ?? '';
}

class WorkflowDetailNotifier extends StateNotifier<WorkflowDetailState> {
  final Ref    _ref;
  final String workflowId;

  WorkflowDetailNotifier(this._ref, this.workflowId)
      : super(WorkflowDetailState(workflowId: workflowId)) {
    loadWorkflow();
  }

  Future<void> loadWorkflow() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data  = await api.get('/workflow/$workflowId');
      final steps = (data['steps'] as List? ?? []).map((s) {
        if (s is Map && s['tools'] is String) {
          final copy = Map<String, dynamic>.from(s as Map<String, dynamic>);
          try {
            copy['tools'] = jsonDecode(copy['tools'] as String);
          } catch (_) {
            copy['tools'] = [];
          }
          return copy;
        }
        return s;
      }).toList();

      state = state.copyWith(
        workflow:    Map<String, dynamic>.from(data['workflow'] as Map? ?? {}),
        steps:       steps,
        freeTools:   data['tools']?['free']          as List? ?? [],
        paidTools:   data['tools']?['paid_upgrades'] as List? ?? [],
        revenueLogs: data['revenue_logs']             as List? ?? [],
        isLoading:   false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load workflow: $e');
    }
  }

  Future<void> updateStep(String stepId, String status) async {
    try {
      await api.patch('/workflow/$workflowId/step/$stepId', {'status': status});
      await loadWorkflow();
    } catch (e) {
      state = state.copyWith(error: 'Failed to update step: $e');
    }
  }

  Future<void> saveStepOutput(
      String stepId, String output, Map<String, dynamic> extracted) async {
    try {
      await api.post('/workflow/$workflowId/step/$stepId/save-output', {
        'output':    output,
        'extracted': extracted,
        'saved_at':  DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Step save (non-critical): $e');
    }
  }

  Future<void> logRevenue(
      double amount, String source, String? paymentMethod) async {
    try {
      await api.post('/workflow/$workflowId/log-revenue', {
        'amount':         amount,
        'currency':       state.currency,
        'source':         source,
        'payment_method': paymentMethod,
      });
      await loadWorkflow();
    } catch (e) {
      state = state.copyWith(error: 'Failed to log revenue: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAIAssist(String stepTitle,
      {String? userQuestion}) async {
    adManager.recordAgentUse();
    final params = <String, dynamic>{'step_title': stepTitle};
    if (userQuestion != null && userQuestion.isNotEmpty) {
      params['user_question'] = userQuestion;
    }
    return await api.post(
        '/workflow/$workflowId/ai-assist', {}, queryParams: params);
  }

  Future<Map<String, dynamic>> getMentorTip(
      String stepTitle, String stepOutput) async {
    try {
      return await api.post('/workflow/$workflowId/ai-assist', {}, queryParams: {
        'step_title':    stepTitle,
        'user_question': 'Based on what was just generated, what 2-3 specific '
            'actionable next steps should I take immediately?',
      });
    } catch (_) {
      return {'ai_output': ''};
    }
  }

  Future<void> generatePortfolio() async {
    try {
      await api.generatePortfolioFromWorkflow(workflowId);
    } catch (e) {
      state = state.copyWith(error: 'Failed: $e');
      rethrow;
    }
  }

  void setSelectedTab(int index) => state = state.copyWith(selectedTab: index);
  void clearError()              => state = state.copyWith(error: null);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

Color _incomeColor(String type) {
  const m = {
    'youtube':           Color(0xFFFF0000),
    'tiktok':            Color(0xFF69C9D0),
    'instagram':         Color(0xFFE1306C),
    'freelance':         Color(0xFF00B894),
    'ecommerce':         Color(0xFFE67E22),
    'dropshipping':      Color(0xFF3498DB),
    'affiliate':         Color(0xFF9B59B6),
    'content':           Color(0xFFE91E63),
    'saas':              Color(0xFF6C5CE7),
    'app_development':   Color(0xFF00CEC9),
    'online_courses':    Color(0xFFFD79A8),
    'digital_products':  Color(0xFF00B894),
    'print_on_demand':   Color(0xFFE17055),
    'virtual_assistant': Color(0xFF74B9FF),
    'translation':       Color(0xFF55A3FF),
    'physical':          Color(0xFF3498DB),
    'food_delivery':     Color(0xFF00B894),
    'ride_sharing':      Color(0xFFFDCB6E),
    'real_estate':       Color(0xFF00B894),
    'stock_trading':     Color(0xFF00CEC9),
    'crypto_trading':    Color(0xFFF39C12),
    'remote_job':        Color(0xFF6C5CE7),
    'other':             Color(0xFF6C5CE7),
  };
  return m[type] ?? AppColors.primary;
}

String _fmtNum(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class WorkflowDetailScreen extends ConsumerStatefulWidget {
  final String workflowId;
  const WorkflowDetailScreen({super.key, required this.workflowId});

  @override
  ConsumerState<WorkflowDetailScreen> createState() =>
      _WorkflowDetailScreenState();
}

class _WorkflowDetailScreenState extends ConsumerState<WorkflowDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) {
        ref
            .read(workflowDetailProvider(widget.workflowId).notifier)
            .setSelectedTab(_tabCtrl.index);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final state    = ref.watch(workflowDetailProvider(widget.workflowId));
    final notifier =
        ref.read(workflowDetailProvider(widget.workflowId).notifier);

    if (state.isLoading) return _LoadingScreen(isDark: isDark);
    if (state.error != null) {
      return _ErrorScreen(
          error: state.error!, onRetry: notifier.loadWorkflow, isDark: isDark);
    }

    final typeColor = _incomeColor(state.incomeType);

    return Scaffold(
      backgroundColor:     isDark ? AppColors.bgDark : const Color(0xFFF5F5F8),
      bottomNavigationBar: adManager.getStickyBanner(context),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _AppBarHeader(
            workflow:        state.workflow,
            totalRevenue:    state.totalRevenue,
            progressPercent: state.progressPercent,
            stepsDone:       state.steps
                .where((s) => (s as Map)['status'] == 'done')
                .length,
            totalSteps:      state.steps.length,
            currency:        state.currency,
            incomeType:      state.incomeType,
            typeColor:       typeColor,
            isDark:          isDark,
            onLogRevenue:    () => _showLogRevenue(context, state, notifier),
            onGenPortfolio:  () => _genPortfolio(context, notifier),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabDelegate(
                tabCtrl: _tabCtrl, typeColor: typeColor, isDark: isDark),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _StepsTab(
              steps:        state.steps,
              isDark:       isDark,
              workflowId:   widget.workflowId,
              region:       state.region,
              onUpdateStep: notifier.updateStep,
              onRunAI:      (step, q) =>
                  _runAIGated(context, notifier, step, q),
              onSaveOutput: notifier.saveStepOutput,
              onMentor:     (title, out) =>
                  notifier.getMentorTip(title, out),
            ),
            _ToolsTab(
              freeTools:    state.freeTools,
              paidTools:    state.paidTools,
              totalRevenue: state.totalRevenue,
              currency:     state.currency,
              isDark:       isDark,
            ),
            _RevenueTab(
              logs:         state.revenueLogs,
              total:        state.totalRevenue,
              currency:     state.currency,
              isDark:       isDark,
              timezone:     state.timezone,
              onLogRevenue: () => _showLogRevenue(context, state, notifier),
            ),
            _AIAssistTab(
              workflowId: widget.workflowId,
              steps:      state.steps,
              isDark:     isDark,
              onRunAI:    (step, q) =>
                  _runAIGated(context, notifier, step, q),
            ),
          ],
        ),
      ),
    );
  }

  // ── AD: check agent limit → rewarded gate → interstitial → run ─────────────
  Future<Map<String, dynamic>> _runAIGated(
    BuildContext ctx,
    WorkflowDetailNotifier n,
    Map step,
    String? q,
  ) async {
    if (!adManager.canUseAgent) {
      final ok = await adManager.watchAdForAgentUse(ctx);
      if (!ok) throw Exception('Watch an ad to unlock more AI uses today.');
    }
    await adManager.showInterstitial();
    return n.getAIAssist(step['title']?.toString() ?? '', userQuestion: q);
  }

  Future<void> _showLogRevenue(
    BuildContext ctx,
    WorkflowDetailState s,
    WorkflowDetailNotifier n,
  ) async {
    await showModalBottomSheet(
      context:            ctx,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _LogRevenueSheet(
        currency: s.currency,
        region:   s.region,
        onLog: (amt, src, pm) async {
          Navigator.pop(ctx);
          try {
            await n.logRevenue(amt, src, pm);
            if (ctx.mounted) {
              _snack(ctx,
                  '${s.currency} ${amt.toStringAsFixed(0)} logged!',
                  AppColors.success);
            }
          } catch (e) {
            if (ctx.mounted) _snack(ctx, 'Failed: $e', AppColors.error);
          }
        },
      ),
    );
  }

  Future<void> _genPortfolio(
      BuildContext ctx, WorkflowDetailNotifier n) async {
    _snack(ctx, 'Generating portfolio...', AppColors.primary);
    try {
      await n.generatePortfolio();
      if (ctx.mounted) _snack(ctx, 'Added to your portfolio!', AppColors.success);
    } catch (e) {
      if (ctx.mounted) _snack(ctx, 'Failed: $e', AppColors.error);
    }
  }

  void _snack(BuildContext ctx, String msg, Color color) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content:   Text(msg),
        backgroundColor: color,
        behavior:  SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
      ));
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOADING / ERROR SCREENS
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingScreen extends StatelessWidget {
  final bool isDark;
  const _LoadingScreen({required this.isDark});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : Colors.white,
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
}

class _ErrorScreen extends StatelessWidget {
  final String       error;
  final VoidCallback onRetry;
  final bool         isDark;
  const _ErrorScreen(
      {required this.error, required this.onRetry, required this.isDark});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Iconsax.warning_2, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Oops!',
                  style: AppTextStyles.h3.copyWith(
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Text(error,
                  style: AppTextStyles.body.copyWith(
                      color: isDark ? Colors.white70 : Colors.black54),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon:  const Icon(Iconsax.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.pill),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLIVER APP BAR HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _AppBarHeader extends StatelessWidget {
  final Map<String, dynamic> workflow;
  final double               totalRevenue;
  final int                  progressPercent, stepsDone, totalSteps;
  final String               currency, incomeType;
  final Color                typeColor;
  final bool                 isDark;
  final VoidCallback         onLogRevenue, onGenPortfolio;

  const _AppBarHeader({
    required this.workflow,
    required this.totalRevenue,
    required this.progressPercent,
    required this.stepsDone,
    required this.totalSteps,
    required this.currency,
    required this.incomeType,
    required this.typeColor,
    required this.isDark,
    required this.onLogRevenue,
    required this.onGenPortfolio,
  });

  @override
  Widget build(BuildContext context) => SliverAppBar(
        expandedHeight:  238,
        pinned:          true,
        backgroundColor: typeColor.withOpacity(0.9),
        leading: IconButton(
          icon:      const Icon(Iconsax.arrow_left, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (totalRevenue > 0)
            IconButton(
              icon:      const Icon(Iconsax.gallery, color: Colors.white),
              onPressed: onGenPortfolio,
            ),
          IconButton(
            icon:      const Icon(Iconsax.add_circle, color: Colors.white),
            onPressed: onLogRevenue,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Iconsax.more, color: Colors.white),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'analytics',
                  child: Row(children: [
                    Icon(Iconsax.chart, size: 16),
                    SizedBox(width: 8),
                    Text('Analytics'),
                  ])),
              PopupMenuItem(
                  value: 'share',
                  child: Row(children: [
                    Icon(Iconsax.share, size: 16),
                    SizedBox(width: 8),
                    Text('Share'),
                  ])),
            ],
            onSelected: (v) {
              if (v == 'analytics') {
                context.push('/workflow/${workflow['id']}/analytics');
              }
            },
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin:  Alignment.topLeft,
                end:    Alignment.bottomRight,
                colors: [typeColor.withOpacity(0.9), AppColors.primary],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:        Colors.white.withOpacity(0.2),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        incomeType.toUpperCase(),
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      workflow['title']?.toString() ?? 'Workflow',
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   21,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      workflow['goal']?.toString() ?? '',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      _HStat(
                          value: '$currency ${_fmtNum(totalRevenue)}',
                          label: 'Earned',
                          color: const Color(0xFFFFD700)),
                      const SizedBox(width: 24),
                      _HStat(
                          value: '$progressPercent%',
                          label: 'Progress',
                          color: Colors.white),
                      const SizedBox(width: 24),
                      _HStat(
                          value: '$stepsDone/$totalSteps',
                          label: 'Steps Done',
                          color: Colors.white),
                    ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: AppRadius.pill,
                      child: LinearProgressIndicator(
                        value: progressPercent / 100,
                        backgroundColor:
                            Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation(
                            Colors.white),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _HStat extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _HStat(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 14)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 10)),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB BAR DELEGATE
// ═══════════════════════════════════════════════════════════════════════════════

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabCtrl;
  final Color         typeColor;
  final bool          isDark;

  _TabDelegate(
      {required this.tabCtrl,
      required this.typeColor,
      required this.isDark});

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: isDark ? AppColors.bgDark : Colors.white,
        child: TabBar(
          controller:           tabCtrl,
          indicatorColor:       typeColor,
          indicatorSize:        TabBarIndicatorSize.label,
          labelColor:           typeColor,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 11),
          tabs: const [
            Tab(text: 'Steps',     icon: Icon(Iconsax.task,      size: 16)),
            Tab(text: 'Tools',     icon: Icon(Iconsax.setting_2, size: 16)),
            Tab(text: 'Revenue',   icon: Icon(Iconsax.money,     size: 16)),
            Tab(text: 'AI Assist', icon: Icon(Iconsax.cpu,       size: 16)),
          ],
        ),
      );

  @override double get maxExtent => 58;
  @override double get minExtent => 58;
  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) =>
      false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEPS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _StepsTab extends StatelessWidget {
  final List<dynamic>                                               steps;
  final bool                                                        isDark;
  final String                                                      workflowId, region;
  final Future<void> Function(String, String)                       onUpdateStep;
  final Future<Map<String, dynamic>> Function(Map, String?)         onRunAI;
  final Future<void> Function(String, String, Map<String, dynamic>) onSaveOutput;
  final Future<Map<String, dynamic>> Function(String, String)       onMentor;

  const _StepsTab({
    required this.steps,
    required this.isDark,
    required this.workflowId,
    required this.region,
    required this.onUpdateStep,
    required this.onRunAI,
    required this.onSaveOutput,
    required this.onMentor,
  });

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return Center(
        child: _Empty(
          icon:   Iconsax.task_square,
          title:  'No steps yet',
          sub:    'Your workflow steps will appear here',
          isDark: isDark,
        ),
      );
    }

    final todo = steps.where((s) => (s as Map)['status'] != 'done').toList();
    final done = steps.where((s) => (s as Map)['status'] == 'done').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (todo.isNotEmpty) ...[
          _SecTitle('To Do (${todo.length})', isDark),
          const SizedBox(height: 10),
          ...todo.asMap().entries.map((e) => _StepCard(
                key:          ValueKey('todo_${(e.value as Map)['id']}'),
                step:         e.value as Map,
                index:        e.key,
                isDark:       isDark,
                onUpdate:     onUpdateStep,
                onRunAI:      onRunAI,
                onSaveOutput: onSaveOutput,
                onMentor:     onMentor,
              )),
        ],
        if (todo.isNotEmpty && done.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child:   adManager.getBannerWidget(),
          ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SecTitle('Completed (${done.length})', isDark),
          const SizedBox(height: 10),
          ...done.asMap().entries.map((e) => _StepCard(
                key:          ValueKey('done_${(e.value as Map)['id']}'),
                step:         e.value as Map,
                index:        e.key,
                isDark:       isDark,
                onUpdate:     onUpdateStep,
                onRunAI:      onRunAI,
                onSaveOutput: onSaveOutput,
                onMentor:     onMentor,
                isDone:       true,
              )),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEP CARD — expandable · inline AI · mentor tip · auto-save
// ═══════════════════════════════════════════════════════════════════════════════

class _StepCard extends StatefulWidget {
  final Map                                                         step;
  final int                                                         index;
  final bool                                                        isDark, isDone;
  final Future<void> Function(String, String)                       onUpdate;
  final Future<Map<String, dynamic>> Function(Map, String?)         onRunAI;
  final Future<void> Function(String, String, Map<String, dynamic>) onSaveOutput;
  final Future<Map<String, dynamic>> Function(String, String)       onMentor;

  const _StepCard({
    super.key,
    required this.step,
    required this.index,
    required this.isDark,
    required this.onUpdate,
    required this.onRunAI,
    required this.onSaveOutput,
    required this.onMentor,
    this.isDone = false,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  bool   _open       = false;
  bool   _aiRunning  = false;
  bool   _aiDone     = false;
  bool   _saved      = false;
  bool   _showMentor = false;
  String _aiOutput   = '';
  String _mentorTip  = '';

  final _questionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  Future<void> _runAI() async {
    if (_aiRunning) return;
    setState(() {
      _aiRunning = true;
      _aiOutput  = '';
      _aiDone    = false;
      _saved     = false;
    });
    try {
      final result = await widget.onRunAI(
        widget.step,
        _questionCtrl.text.trim().isEmpty
            ? null
            : _questionCtrl.text.trim(),
      );
      final out = result['ai_output']?.toString() ?? '';
      setState(() {
        _aiOutput  = out;
        _aiRunning = false;
        _aiDone    = true;
      });
      if (out.isNotEmpty) {
        final stepId    = widget.step['id']?.toString() ?? '';
        final extracted = _extract(out);
        await widget.onSaveOutput(stepId, out, extracted);
        if (mounted) setState(() => _saved = true);
      }
    } catch (e) {
      setState(() {
        _aiRunning = false;
        _aiOutput  = 'Error: $e';
      });
    }
  }

  Future<void> _loadMentor() async {
    if (_mentorTip.isNotEmpty) {
      setState(() => _showMentor = !_showMentor);
      return;
    }
    setState(() {
      _showMentor = true;
      _mentorTip  = '';
    });
    try {
      final r = await widget.onMentor(
          widget.step['title']?.toString() ?? '', _aiOutput);
      if (mounted) {
        setState(() => _mentorTip = r['ai_output']?.toString() ?? '');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _mentorTip = 'Could not load tip right now.');
      }
    }
  }

  Map<String, dynamic> _extract(String out) {
    final lines      = out.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final contacts   = <String>[];
    final links      = <String>[];
    final businesses = <String>[];
    final phoneRx    = RegExp(r'\+?[\d\s\-\(\)]{8,15}');
    final urlRx      = RegExp(r'https?://\S+');
    final bizRx      = RegExp(
        r'(?:company|business|shop|store|agency|ltd|inc|co\.)[:\s]+([^\n]+)',
        caseSensitive: false);

    for (final l in lines) {
      if (phoneRx.hasMatch(l)) contacts.add(l.trim());
      for (final m in urlRx.allMatches(l)) links.add(m.group(0)!);
      final bm = bizRx.firstMatch(l);
      if (bm != null) businesses.add(bm.group(1)?.trim() ?? '');
    }

    return {
      'contacts':   contacts.take(20).toList(),
      'links':      links.take(30).toList(),
      'businesses': businesses.take(20).toList(),
      'raw_lines':  lines.take(50).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final status     = widget.step['status']?.toString() ?? 'pending';
    final isAuto     = widget.step['step_type']?.toString() == 'automated';
    final stepId     = widget.step['id']?.toString() ?? '';
    final orderIndex = widget.step['order_index'] as int? ?? widget.index + 1;
    final tools      = widget.step['tools'] as List? ?? [];
    final isDark     = widget.isDark;

    Color sColor;
    switch (status) {
      case 'done':        sColor = AppColors.success; break;
      case 'in_progress': sColor = AppColors.warning; break;
      case 'blocked':     sColor = AppColors.error;   break;
      default:            sColor = isDark ? Colors.white30 : Colors.grey;
    }

    final cardBg = widget.isDone
        ? (isDark
            ? AppColors.bgCard.withOpacity(0.5)
            : const Color(0xFFF8F8F8))
        : (isDark ? AppColors.bgSurface : Colors.white);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        cardBg,
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: _open
              ? (isAuto ? AppColors.primary : AppColors.warning)
                  .withOpacity(0.4)
              : (widget.isDone
                  ? AppColors.success.withOpacity(0.2)
                  : (isDark
                      ? Colors.white10
                      : Colors.grey.shade200)),
        ),
        boxShadow: widget.isDone
            ? null
            : [
                BoxShadow(
                  color:      Colors.black.withOpacity(isDark ? 0.12 : 0.05),
                  blurRadius: 10,
                  offset:     const Offset(0, 3),
                ),
              ],
      ),
      child: Column(children: [
        // ── Collapsed header (always visible) ────────────────────────────
        InkWell(
          onTap:        _toggle,
          borderRadius: AppRadius.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Tap circle to toggle done/pending
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onUpdate(
                      stepId, status == 'done' ? 'pending' : 'done');
                },
                child: Container(
                  width:  34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: status == 'done'
                        ? AppColors.success
                        : Colors.transparent,
                    shape:  BoxShape.circle,
                    border: Border.all(color: sColor, width: 2),
                  ),
                  child: status == 'done'
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 17)
                      : Center(
                          child: Text(
                            '$orderIndex',
                            style: TextStyle(
                              color:      sColor,
                              fontSize:   12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.step['title']?.toString() ?? '',
                      style: TextStyle(
                        color: widget.isDone
                            ? (isDark ? Colors.white54 : Colors.black54)
                            : (isDark ? Colors.white : Colors.black87),
                        decoration: widget.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      _Badge(
                        isAuto ? '🤖 AI' : '👤 Manual',
                        isAuto ? AppColors.primary : AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      _Badge(
                        '${widget.step['time_minutes'] ?? 30} min',
                        AppColors.textSecondary,
                      ),
                      if (tools.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(
                          '${tools.length} tool${tools.length > 1 ? "s" : ""}',
                          AppColors.info,
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              AnimatedRotation(
                turns:    _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 260),
                child: Icon(
                  Iconsax.arrow_down,
                  color: isDark ? Colors.white38 : Colors.black26,
                  size:  16,
                ),
              ),
            ]),
          ),
        ),

        // ── Expanded content ─────────────────────────────────────────────
        SizeTransition(
          sizeFactor: _anim,
          child: Column(children: [
            Divider(
                height: 1,
                color:  isDark ? Colors.white10 : Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Full description
                  if ((widget.step['description']?.toString() ?? '')
                      .isNotEmpty) ...[
                    Text(
                      widget.step['description'].toString(),
                      style: TextStyle(
                        fontSize: 13,
                        color:    isDark ? Colors.white70 : Colors.black54,
                        height:   1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Tool chips
                  if (tools.isNotEmpty) ...[
                    Text(
                      'Tools needed:',
                      style: TextStyle(
                        fontSize:   11,
                        color:      isDark ? Colors.white38 : Colors.black38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing:    6,
                      runSpacing: 6,
                      children: tools.map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: AppRadius.pill,
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Iconsax.external_drive,
                              size: 10, color: AppColors.primary),
                          const SizedBox(width: 5),
                          Text(
                            t.toString(),
                            style: const TextStyle(
                              fontSize:   11,
                              color:      AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Manual step: status action buttons
                  if (!isAuto && !widget.isDone) ...[
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _ActBtn('✅ Mark Done', AppColors.success,
                          () => widget.onUpdate(stepId, 'done')),
                      _ActBtn('⏳ In Progress', AppColors.warning,
                          () => widget.onUpdate(stepId, 'in_progress')),
                      _ActBtn('🚫 Blocked', AppColors.error,
                          () => widget.onUpdate(stepId, 'blocked')),
                    ]),
                    const SizedBox(height: 10),
                  ],

                  // AI step: inline runner
                  if (isAuto && !widget.isDone) ...[
                    TextField(
                      controller: _questionCtrl,
                      style: TextStyle(
                        fontSize: 12,
                        color:    isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText:  'Optional: Add context for better results',
                        hintStyle: TextStyle(
                          color:    isDark ? Colors.white38 : Colors.black38,
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(Iconsax.message_text, size: 16),
                        filled:     true,
                        fillColor:  isDark
                            ? AppColors.bgDark
                            : const Color(0xFFF3F3F6),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.lg,
                          borderSide:   BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _aiRunning ? null : _runAI,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: _aiRunning
                                ? null
                                : const LinearGradient(colors: [
                                    Color(0xFF6C5CE7),
                                    Color(0xFF00CEC9),
                                  ]),
                            color:        _aiRunning
                                ? Colors.grey.shade400
                                : null,
                            borderRadius: AppRadius.pill,
                            boxShadow: _aiRunning
                                ? []
                                : [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.28),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: _aiRunning
                                ? [
                                    const SizedBox(
                                      width:  16,
                                      height: 16,
                                      child:  CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color:       Colors.white),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'AI is working...',
                                      style: TextStyle(
                                          color:      Colors.white,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ]
                                : [
                                    const Icon(Iconsax.flash,
                                        color: Colors.white, size: 15),
                                    const SizedBox(width: 7),
                                    const Text(
                                      'Run AI on This Step',
                                      style: TextStyle(
                                        color:      Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize:   13,
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // AI Output block
                  if (_aiOutput.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.bgDark
                            : const Color(0xFFF8F8FC),
                        borderRadius: AppRadius.lg,
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.auto_awesome,
                                color: AppColors.primary, size: 14),
                            const SizedBox(width: 6),
                            const Text(
                              'AI Output',
                              style: TextStyle(
                                color:      AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize:   12,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: _aiOutput));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text('✅ Copied!'),
                                  backgroundColor: AppColors.success,
                                  duration: Duration(seconds: 2),
                                ));
                              },
                              child: const Icon(Iconsax.copy,
                                  size: 15, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _runAI,
                              child: const Icon(Iconsax.refresh,
                                  size: 15, color: AppColors.textMuted),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          SelectableText(
                            _aiOutput,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white : Colors.black87,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Row(children: [
                      if (_saved) ...[
                        const Icon(Iconsax.tick_circle,
                            size: 12, color: AppColors.success),
                        const SizedBox(width: 5),
                        const Text('Saved',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.success)),
                      ],
                      const Spacer(),
                      if (_aiDone)
                        GestureDetector(
                          onTap: _loadMentor,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B59B6).withOpacity(0.1),
                              borderRadius: AppRadius.pill,
                              border: Border.all(
                                  color: const Color(0xFF9B59B6)
                                      .withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🧑‍🏫',
                                    style: TextStyle(fontSize: 11)),
                                SizedBox(width: 5),
                                Text(
                                  'Mentor Tip',
                                  style: TextStyle(
                                    color:      Color(0xFF9B59B6),
                                    fontSize:   11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ]),

                    if (_aiDone && !widget.isDone) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              widget.onUpdate(stepId, 'done'),
                          icon: const Icon(Iconsax.tick_circle,
                              size: 15, color: AppColors.success),
                          label: const Text(
                            'Mark Step Complete',
                            style: TextStyle(
                                color:      AppColors.success,
                                fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.success),
                            padding: const EdgeInsets.symmetric(
                                vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.pill),
                          ),
                        ),
                      ),
                    ],
                  ],

                  // Mentor tip panel
                  if (_showMentor) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B59B6).withOpacity(0.07),
                        borderRadius: AppRadius.lg,
                        border: Border.all(
                            color: const Color(0xFF9B59B6).withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Text('🧑‍🏫', style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            Text(
                              'Mentor AI',
                              style: TextStyle(
                                color:      Color(0xFF9B59B6),
                                fontWeight: FontWeight.w700,
                                fontSize:   12,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          _mentorTip.isEmpty
                              ? const Row(children: [
                                  SizedBox(
                                    width:  14,
                                    height: 14,
                                    child:  CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color:       Color(0xFF9B59B6),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Loading mentor tip...',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:    Color(0xFF9B59B6)),
                                  ),
                                ])
                              : Text(
                                  _mentorTip,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                    height: 1.5,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],

                ],
              ),
            ),
          ]),
        ),
      ]),
    ).animate().fadeIn(delay: (widget.index * 50).ms).slideY(begin: 0.06);
  }
}

// ── Shared small step widgets ─────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  final Color  color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.12),
          borderRadius: AppRadius.pill,
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );
}

class _ActBtn extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _ActBtn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.1),
            borderRadius: AppRadius.pill,
            border:       Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TOOLS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolsTab extends StatelessWidget {
  final List<dynamic> freeTools, paidTools;
  final double        totalRevenue;
  final String        currency;
  final bool          isDark;

  const _ToolsTab({
    required this.freeTools,
    required this.paidTools,
    required this.totalRevenue,
    required this.currency,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (freeTools.isNotEmpty) ...[
            _SecHdr(
              icon:   Iconsax.gift,
              title:  'Free Tools',
              sub:    'Start with these — no cost',
              color:  AppColors.success,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            ...freeTools.asMap().entries.map((e) => _ToolCard(
                  tool:         e.value as Map,
                  isFree:       true,
                  isDark:       isDark,
                  totalRevenue: totalRevenue,
                  index:        e.key,
                )),
          ],
          if (freeTools.isNotEmpty && paidTools.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child:   adManager.getBannerWidget(),
            ),
          if (paidTools.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SecHdr(
              icon:   Iconsax.crown,
              title:  'Upgrade When Ready',
              sub:    'Unlock as you earn more',
              color:  AppColors.warning,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            ...paidTools.asMap().entries.map((e) {
              final t   = e.value as Map;
              final ulk = (t['unlock_at_revenue'] as num?)?.toDouble() ?? 0;
              return _ToolCard(
                tool:         t,
                isFree:       false,
                isDark:       isDark,
                unlocked:     totalRevenue >= ulk,
                unlockAt:     ulk,
                currency:     currency,
                totalRevenue: totalRevenue,
                index:        e.key,
              );
            }),
          ],
          if (freeTools.isEmpty && paidTools.isEmpty)
            _Empty(
              icon:   Iconsax.setting_2,
              title:  'No tools yet',
              sub:    'Tools will appear as you progress',
              isDark: isDark,
            ),
        ],
      );
}

class _SecHdr extends StatelessWidget {
  final IconData icon;
  final String   title, sub;
  final Color    color;
  final bool     isDark;

  const _SecHdr({
    required this.icon,
    required this.title,
    required this.sub,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.12),
            borderRadius: AppRadius.md,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              style: TextStyle(
                fontSize:   15,
                fontWeight: FontWeight.w700,
                color:      isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color:    isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ]),
        ),
      ]);
}

class _ToolCard extends StatelessWidget {
  final Map     tool;
  final bool    isFree, isDark;
  final bool    unlocked;
  final double? unlockAt;
  final String? currency;
  final double  totalRevenue;
  final int     index;

  const _ToolCard({
    required this.tool,
    required this.isFree,
    required this.isDark,
    required this.totalRevenue,
    this.unlocked = true,
    this.unlockAt,
    this.currency,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final clr = isFree
        ? AppColors.success
        : (unlocked ? AppColors.primary : AppColors.textMuted);

    return Opacity(
      opacity: unlocked ? 1.0 : 0.6,
      child: Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        isDark ? AppColors.bgSurface : Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(color: clr.withOpacity(unlocked ? 0.25 : 0.1)),
        ),
        child: Row(children: [
          Container(
            width:  44,
            height: 44,
            decoration: BoxDecoration(
              color:        clr.withOpacity(0.12),
              borderRadius: AppRadius.md,
            ),
            child: Center(
              child: Icon(
                isFree
                    ? Iconsax.tick_circle
                    : (unlocked ? Iconsax.lock_slash : Iconsax.lock_1),
                color: clr,
                size:  22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool['name']?.toString() ?? '',
                  style: TextStyle(
                    color:      isDark ? Colors.white : Colors.black87,
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tool['purpose']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color:    isDark ? Colors.white54 : Colors.black45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isFree && !unlocked && unlockAt != null) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: (totalRevenue / (unlockAt ?? 1.0))
                        .clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor:      AlwaysStoppedAnimation(clr),
                    minHeight:       3,
                    borderRadius:    AppRadius.pill,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Unlock at $currency ${_fmtNum(unlockAt!)}',
                    style: TextStyle(
                        color: clr, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          if ((tool['url']?.toString() ?? '').isNotEmpty &&
              (isFree || unlocked))
            IconButton(
              icon:      const Icon(Iconsax.external_drive, size: 18),
              onPressed: () {},
            ),
        ]),
      ),
    ).animate().fadeIn(delay: (index * 70).ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REVENUE TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _RevenueTab extends StatelessWidget {
  final List<dynamic> logs;
  final double        total;
  final String        currency, timezone;
  final bool          isDark;
  final VoidCallback  onLogRevenue;

  const _RevenueTab({
    required this.logs,
    required this.total,
    required this.currency,
    required this.isDark,
    required this.timezone,
    required this.onLogRevenue,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final fmt    = NumberFormat.currency(
        locale: locale.toString(), symbol: currency, decimalDigits: 0);

    if (logs.isEmpty) {
      return _EmptyRevenue(
          currency: currency, isDark: isDark, onLog: onLogRevenue);
    }

    // Aggregate daily revenue for trend chart
    final daily = <String, double>{};
    for (final log in logs) {
      final day    = (log as Map)['created_at']
              ?.toString()
              .substring(0, 10) ??
          'x';
      final amount = (log['amount'] as num?)?.toDouble() ?? 0;
      daily[day]   = (daily[day] ?? 0) + amount;
    }
    final sortedDaily = Map.fromEntries(
        daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    final spots = sortedDaily.entries
        .toList()
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Total earnings card ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00B894), Color(0xFF00CEC9)],
              begin:  Alignment.topLeft,
              end:    Alignment.bottomRight,
            ),
            borderRadius: AppRadius.lg,
            boxShadow: [
              BoxShadow(
                color:      AppColors.success.withOpacity(0.3),
                blurRadius: 18,
                offset:     const Offset(0, 7),
              ),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Total Earnings',
                  style: TextStyle(
                    color:      Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  fmt.format(total),
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: const BoxDecoration(
                    color: Colors.white24, shape: BoxShape.circle),
                child: const Icon(Iconsax.wallet_3,
                    color: Colors.white, size: 26),
              ),
            ]),
            if (logs.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Iconsax.receipt_item,
                    color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${logs.length} transactions',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 20),
                const Icon(Iconsax.calculator,
                    color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${fmt.format(total / logs.length)} avg',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ]),
            ],
          ]),
        ).animate().fadeIn().slideY(begin: -0.08),

        // ── Revenue trend chart ─────────────────────────────────────────
        if (spots.length > 1) ...[
          const SizedBox(height: 22),
          Text('Revenue Trend',
              style: AppTextStyles.h4
                  .copyWith(color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 14),
          Container(
            height:  180,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.lg,
              border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: LineChart(LineChartData(
              gridData:   FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots:            spots,
                  isCurved:         true,
                  barWidth:         3,
                  isStrokeCapRound: true,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00B894), Color(0xFF00CEC9)]),
                  dotData: FlDotData(show: spots.length < 10),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00B894).withOpacity(0.28),
                        const Color(0xFF00CEC9).withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            )),
          ),
          const SizedBox(height: 22),
        ],

        // ── Recent transactions ─────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recent Transactions',
              style: AppTextStyles.h4
                  .copyWith(color: isDark ? Colors.white : Colors.black87)),
          TextButton.icon(
            onPressed: onLogRevenue,
            icon:  const Icon(Iconsax.add, size: 15),
            label: const Text('Add'),
          ),
        ]),
        const SizedBox(height: 10),

        ...logs.take(10).toList().asMap().entries.map((e) {
          final log  = e.value as Map;
          final date = DateTime.tryParse(
                  log['created_at']?.toString() ?? '') ??
              DateTime.now();
          final diff = DateTime.now().difference(date.toLocal());
          final dl   = diff.inDays == 0
              ? 'Today'
              : diff.inDays == 1
                  ? 'Yesterday'
                  : '${diff.inDays}d ago';

          return Container(
            margin:  const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.md,
              border: Border.all(
                  color:
                      isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Row(children: [
              Container(
                width:  42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                    child: Text('💸', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log['source']?.toString().isNotEmpty == true
                          ? log['source'].toString()
                          : 'Revenue',
                      style: TextStyle(
                        color:      isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(dl,
                        style: TextStyle(
                          fontSize: 11,
                          color:    isDark ? Colors.white54 : Colors.black45,
                        )),
                    if (log['payment_method'] != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        AppColors.primary.withOpacity(0.1),
                          borderRadius: AppRadius.pill,
                        ),
                        child: Text(
                          log['payment_method'].toString(),
                          style: const TextStyle(
                            color:      AppColors.primary,
                            fontSize:   9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '+${fmt.format((log['amount'] as num?)?.toDouble() ?? 0)}',
                style: const TextStyle(
                  color:      AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize:   14,
                ),
              ),
            ]),
          ).animate().fadeIn(delay: (e.key * 50).ms);
        }),
      ],
    );
  }
}

class _EmptyRevenue extends StatelessWidget {
  final String       currency;
  final bool         isDark;
  final VoidCallback onLog;

  const _EmptyRevenue({
    required this.currency,
    required this.isDark,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width:  100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('💰', style: TextStyle(fontSize: 48))),
            ),
            const SizedBox(height: 24),
            Text('Start Earning!',
                style: AppTextStyles.h3.copyWith(
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            Text(
              'Execute your workflow steps and log your income here. '
              'Track progress to unlock paid tools.',
              style: AppTextStyles.body.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onLog,
              icon:  const Icon(Iconsax.add_circle),
              label: const Text('Log First Income'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.pill),
              ),
            ),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI ASSIST TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _AIAssistTab extends StatefulWidget {
  final String       workflowId;
  final List<dynamic> steps;
  final bool         isDark;
  final Future<Map<String, dynamic>> Function(Map, String?) onRunAI;

  const _AIAssistTab({
    required this.workflowId,
    required this.steps,
    required this.isDark,
    required this.onRunAI,
  });

  @override
  State<_AIAssistTab> createState() => _AIAssistTabState();
}

class _AIAssistTabState extends State<_AIAssistTab> {
  Map?    _selectedStep;
  String  _aiOutput = '';
  bool    _running  = false;
  final   List<Map<String, dynamic>> _history = [];
  final   _questionCtrl = TextEditingController();

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header card ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.primary.withOpacity(0.2),
              AppColors.accent.withOpacity(0.15),
            ]),
            borderRadius: AppRadius.lg,
            border:
                Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  AppColors.primary.withOpacity(0.2),
                shape:  BoxShape.circle,
              ),
              child: const Text('🤖',
                  style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Execution Engine',
                    style: TextStyle(
                      color:      isDark ? Colors.white : Colors.black87,
                      fontSize:   16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select any step and AI will generate ready-to-use content, '
                    'scripts, or strategies.',
                    style: TextStyle(
                      fontSize: 11,
                      color:    isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),

        // ── AD usage banner ───────────────────────────────────────────────
        if (!adManager.isPremium) ...[
          const SizedBox(height: 12),
          _AIUsageBanner(isDark: isDark),
        ],
        const SizedBox(height: 20),

        // ── Step selector ─────────────────────────────────────────────────
        Text(
          'Select a step to execute:',
          style: TextStyle(
            fontSize:   14,
            fontWeight: FontWeight.w700,
            color:      isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing:    8,
          runSpacing: 8,
          children: widget.steps.map((step) {
            final s      = step as Map;
            final sel    = _selectedStep?['id'] == s['id'];
            final isAuto = s['step_type'] == 'automated';

            return GestureDetector(
              onTap: () => setState(() => _selectedStep = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.primary
                      : (isDark ? AppColors.bgSurface : Colors.white),
                  borderRadius: AppRadius.pill,
                  border: Border.all(
                    color: sel
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(isAuto ? '🤖' : '👤',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(
                    s['title']?.toString() ?? '',
                    style: TextStyle(
                      color: sel
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            );
          }).toList(),
        ),

        // ── Question field + execute button ───────────────────────────────
        if (_selectedStep != null) ...[
          const SizedBox(height: 20),
          TextField(
            controller: _questionCtrl,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText:  'Optional: Add context for better results',
              hintStyle: TextStyle(
                color:    isDark ? Colors.white38 : Colors.black38,
                fontSize: 12,
              ),
              filled:     true,
              fillColor:  isDark
                  ? AppColors.bgSurface
                  : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide:   BorderSide.none,
              ),
              prefixIcon: const Icon(Iconsax.message_text),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runAI,
              icon: _running
                  ? const SizedBox(
                      width:  18,
                      height: 18,
                      child:  CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Iconsax.flash),
              label: Text(_running ? 'AI is working...' : 'Execute with AI'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.pill),
                elevation:   6,
                shadowColor: AppColors.primary.withOpacity(0.4),
              ),
            ),
          ),
        ],

        // ── History ───────────────────────────────────────────────────────
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              'Recent Generations',
              style: TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w700,
                color:      isDark ? Colors.white : Colors.black87,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _history.clear()),
              child: const Text('Clear'),
            ),
          ]),
          const SizedBox(height: 8),
          ..._history.take(3).map((h) => GestureDetector(
                onTap: () =>
                    setState(() => _aiOutput = h['output'] as String),
                child: Container(
                  margin:  const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgSurface : Colors.white,
                    borderRadius: AppRadius.md,
                    border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:  AppColors.primary.withOpacity(0.1),
                        shape:  BoxShape.circle,
                      ),
                      child: const Icon(Iconsax.clock,
                          size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h['step_title'] as String,
                            style: TextStyle(
                              fontSize:   12,
                              fontWeight: FontWeight.w600,
                              color:      isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            (h['output'] as String).substring(
                                0,
                                (h['output'] as String).length > 55
                                    ? 55
                                    : (h['output'] as String).length),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Iconsax.arrow_right_3,
                        size: 14, color: AppColors.primary),
                  ]),
                ),
              )),
        ],

        // ── AI Output ─────────────────────────────────────────────────────
        if (_aiOutput.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Text(
                'AI Output',
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w700,
                  color:      isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFF00B894)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome,
                      color: Colors.white, size: 9),
                  SizedBox(width: 3),
                  Text(
                    'Brain Enhanced',
                    style: TextStyle(
                      color:      Colors.white,
                      fontSize:   8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
              ),
            ]),
            Row(children: [
              IconButton(
                icon:      const Icon(Iconsax.copy, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _aiOutput));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:         Text('Copied!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
              ),
              IconButton(
                icon:      const Icon(Iconsax.refresh, size: 20),
                onPressed: _runAI,
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.lg,
              border:
                  Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: SelectableText(
              _aiOutput,
              style: TextStyle(
                color:  isDark ? Colors.white : Colors.black87,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  Future<void> _runAI() async {
    if (_selectedStep == null) return;
    setState(() => _running = true);
    try {
      final result = await widget.onRunAI(
        _selectedStep!,
        _questionCtrl.text.trim().isEmpty
            ? null
            : _questionCtrl.text.trim(),
      );
      final out = result['ai_output']?.toString() ?? '';
      setState(() {
        _aiOutput = out;
        _running  = false;
        _history.insert(0, {
          'step_title': _selectedStep!['title'],
          'output':     out,
          'timestamp':  DateTime.now(),
        });
      });
    } catch (e) {
      setState(() {
        _running  = false;
        _aiOutput = 'Error: $e';
      });
    }
  }
}

// ── AD: daily usage banner shown inside AI Assist tab ────────────────────────

class _AIUsageBanner extends StatelessWidget {
  final bool isDark;
  const _AIUsageBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final remaining = adManager.agentUsesRemaining;
    final color     = remaining > 0 ? AppColors.primary : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.06),
        borderRadius: AppRadius.lg,
        border:       Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(
          remaining > 0 ? Iconsax.cpu : Iconsax.warning_2,
          color: color,
          size:  16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            remaining > 0
                ? '$remaining free AI run${remaining == 1 ? "" : "s"} left today'
                : 'Daily free AI runs used up',
            style: TextStyle(
              color:      isDark ? Colors.white : Colors.black87,
              fontSize:   12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (remaining == 0)
          GestureDetector(
            onTap: () async {
              final ok = await adManager.watchAdForAgentUse(context);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:         Text('✅ AI use unlocked!'),
                  backgroundColor: AppColors.success,
                ));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: AppRadius.pill,
                border:
                    Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Iconsax.play_circle,
                    color: AppColors.warning, size: 12),
                SizedBox(width: 4),
                Text(
                  'Watch Ad',
                  style: TextStyle(
                    color:      AppColors.warning,
                    fontSize:   10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOG REVENUE SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _LogRevenueSheet extends StatefulWidget {
  final String                          currency, region;
  final Function(double, String, String?) onLog;

  const _LogRevenueSheet({
    required this.currency,
    required this.region,
    required this.onLog,
  });

  @override
  State<_LogRevenueSheet> createState() => _LogRevenueSheetState();
}

class _LogRevenueSheetState extends State<_LogRevenueSheet> {
  final _amtCtrl = TextEditingController();
  final _srcCtrl = TextEditingController();
  String? _pm;

  static const _paymentMethods = <String, List<String>>{
    'global':         ['PayPal', 'Wise', 'Payoneer', 'Bank Transfer', 'Crypto'],
    'africa_west':    ['PayPal', 'Chipper Cash', 'Flutterwave', 'Paga', 'Bank Transfer'],
    'africa_east':    ['M-Pesa', 'PayPal', 'Flutterwave', 'Chipper Cash'],
    'south_asia':     ['PayPal', 'Razorpay', 'Paytm', 'UPI', 'bKash'],
    'southeast_asia': ['PayPal', 'PayMongo', 'Xendit', 'GrabPay'],
    'latin_america':  ['PayPal', 'Mercado Pago', 'Pix', 'Ualá'],
    'middle_east':    ['PayPal', 'Telr', 'Paymob', 'Fawry'],
  };

  List<String> get _methods =>
      _paymentMethods[widget.region] ?? _paymentMethods['global']!;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _srcCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left:   24,
        right:  24,
        top:    24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width:  36,
              height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey.shade400,
                borderRadius: AppRadius.pill,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Log Revenue',
            style: AppTextStyles.h3
                .copyWith(color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your earnings to unlock tools and see progress',
            style: TextStyle(
              fontSize: 12,
              color:    isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 20),

          // Amount field
          TextField(
            controller:  _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            style: TextStyle(
              color:      isDark ? Colors.white : Colors.black87,
              fontSize:   24,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixText: '${widget.currency}  ',
              prefixStyle: const TextStyle(
                color:      AppColors.primary,
                fontSize:   24,
                fontWeight: FontWeight.w800,
              ),
              hintText:  '0.00',
              filled:    true,
              fillColor: isDark
                  ? AppColors.bgSurface
                  : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide:   BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Source field
          TextField(
            controller: _srcCtrl,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText:   'Source (e.g. YouTube AdSense, Client payment)',
              prefixIcon: const Icon(Iconsax.tag),
              filled:     true,
              fillColor:  isDark
                  ? AppColors.bgSurface
                  : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide:   BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Payment method chips
          Text(
            'Payment Method',
            style: TextStyle(
              fontSize:   13,
              fontWeight: FontWeight.w600,
              color:      isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing:    8,
            runSpacing: 8,
            children: _methods.map((m) {
              final sel = _pm == m;
              return ChoiceChip(
                label: Text(m),
                selected: sel,
                onSelected: (v) =>
                    setState(() => _pm = v ? m : null),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: sel
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Log button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final amt = double.tryParse(_amtCtrl.text) ?? 0;
                if (amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:         Text('Please enter a valid amount'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                widget.onLog(amt, _srcCtrl.text.trim(), _pm);
              },
              icon:  const Icon(Iconsax.tick_circle),
              label: const Text('Log Income'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.pill),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SecTitle extends StatelessWidget {
  final String text;
  final bool   isDark;
  const _SecTitle(this.text, this.isDark);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize:   16,
          fontWeight: FontWeight.w700,
          color:      isDark ? Colors.white : Colors.black87,
        ),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String   title, sub;
  final bool     isDark;

  const _Empty({
    required this.icon,
    required this.title,
    required this.sub,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          icon,
          size:  64,
          color: isDark
              ? Colors.white.withOpacity(0.2)
              : Colors.grey.shade300,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize:   16,
            fontWeight: FontWeight.w600,
            color:      isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sub,
          style: TextStyle(
            fontSize: 13,
            color:    isDark ? Colors.white38 : Colors.black38,
          ),
          textAlign: TextAlign.center,
        ),
      ]);
}
