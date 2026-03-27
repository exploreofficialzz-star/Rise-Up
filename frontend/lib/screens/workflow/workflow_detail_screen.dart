// frontend/lib/screens/workflow/workflow_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// ── FIXED: Changed from iconsax to iconsax_flutter ──
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';

// ═════════════════════════════════════════════════════════════════════════════
// RIVERPOD STATE MANAGEMENT
// ═════════════════════════════════════════════════════════════════════════════

final workflowDetailProvider = StateNotifierProvider.family<WorkflowDetailNotifier, WorkflowDetailState, String>(
  (ref, workflowId) => WorkflowDetailNotifier(ref, workflowId),
);

class WorkflowDetailState {
  final String workflowId;
  final Map<String, dynamic> workflow;
  final List<dynamic> steps;
  final List<dynamic> freeTools;
  final List<dynamic> paidTools;
  final List<dynamic> revenueLogs;
  final bool isLoading;
  final String? error;
  final int selectedTab;

  WorkflowDetailState({
    required this.workflowId,
    this.workflow = const {},
    this.steps = const [],
    this.freeTools = const [],
    this.paidTools = const [],
    this.revenueLogs = const [],
    this.isLoading = true,
    this.error,
    this.selectedTab = 0,
  });

  WorkflowDetailState copyWith({
    Map<String, dynamic>? workflow,
    List<dynamic>? steps,
    List<dynamic>? freeTools,
    List<dynamic>? paidTools,
    List<dynamic>? revenueLogs,
    bool? isLoading,
    String? error,
    int? selectedTab,
  }) {
    return WorkflowDetailState(
      workflowId: workflowId,
      workflow: workflow ?? this.workflow,
      steps: steps ?? this.steps,
      freeTools: freeTools ?? this.freeTools,
      paidTools: paidTools ?? this.paidTools,
      revenueLogs: revenueLogs ?? this.revenueLogs,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      selectedTab: selectedTab ?? this.selectedTab,
    );
  }

  double get totalRevenue => (workflow['total_revenue'] as num?)?.toDouble() ?? 0.0;
  int get progressPercent => (workflow['progress_percent'] as num?)?.toInt() ?? 0;
  String get currency => workflow['currency']?.toString() ?? 'USD';
  String get language => workflow['language']?.toString() ?? 'en';
  String get region => workflow['region']?.toString() ?? 'global';
  String get timezone => workflow['timezone']?.toString() ?? 'UTC';
  String get incomeType => workflow['income_type']?.toString() ?? 'other';
  String get title => workflow['title']?.toString() ?? 'Workflow';
  String get goal => workflow['goal']?.toString() ?? '';
}

class WorkflowDetailNotifier extends StateNotifier<WorkflowDetailState> {
  final Ref ref;
  final String workflowId;

  WorkflowDetailNotifier(this.ref, this.workflowId) : super(WorkflowDetailState(workflowId: workflowId)) {
    loadWorkflow();
  }

  Future<void> loadWorkflow() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await api.get('/workflow/$workflowId');
      state = state.copyWith(
        workflow: Map<String, dynamic>.from(data['workflow'] as Map? ?? {}),
        steps: data['steps'] as List? ?? [],
        freeTools: data['tools']?['free'] as List? ?? [],
        paidTools: data['tools']?['paid_upgrades'] as List? ?? [],
        revenueLogs: data['revenue_logs'] as List? ?? [],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load workflow: $e');
    }
  }

  Future<void> updateStep(String stepId, String status) async {
    try {
      await api.patch('/workflow/$workflowId/step/$stepId', {'status': status});
      await loadWorkflow(); // Reload to get updated progress
    } catch (e) {
      state = state.copyWith(error: 'Failed to update step: $e');
    }
  }

  Future<void> logRevenue(double amount, String source, String? paymentMethod) async {
    try {
      await api.post('/workflow/$workflowId/log-revenue', {
        'amount': amount,
        'currency': state.currency,
        'source': source,
        'payment_method': paymentMethod,
      });
      await loadWorkflow();
    } catch (e) {
      state = state.copyWith(error: 'Failed to log revenue: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAIAssist(String stepTitle, {String? userQuestion}) async {
    final params = <String, dynamic>{'step_title': stepTitle};
    if (userQuestion != null && userQuestion.isNotEmpty) {
      params['user_question'] = userQuestion;
    }
    return await api.post('/workflow/$workflowId/ai-assist', {}, queryParams: params);
  }

  Future<void> generatePortfolio() async {
    try {
      await api.generatePortfolioFromWorkflow(workflowId);
    } catch (e) {
      state = state.copyWith(error: 'Failed to generate portfolio: $e');
      rethrow;
    }
  }

  void setSelectedTab(int index) {
    state = state.copyWith(selectedTab: index);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class WorkflowDetailScreen extends ConsumerStatefulWidget {
  final String workflowId;
  
  const WorkflowDetailScreen({super.key, required this.workflowId});

  @override
  ConsumerState<WorkflowDetailScreen> createState() => _WorkflowDetailScreenState();
}

class _WorkflowDetailScreenState extends ConsumerState<WorkflowDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      ref.read(workflowDetailProvider(widget.workflowId).notifier).setSelectedTab(_tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(workflowDetailProvider(widget.workflowId));
    final notifier = ref.read(workflowDetailProvider(widget.workflowId).notifier);

    if (state.isLoading) {
      return _LoadingScreen(isDark: isDark);
    }

    if (state.error != null) {
      return _ErrorScreen(
        error: state.error!,
        onRetry: notifier.loadWorkflow,
        isDark: isDark,
      );
    }

    final typeColor = _getIncomeTypeColor(state.incomeType);

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _SliverAppBarHeader(
            workflow: state.workflow,
            totalRevenue: state.totalRevenue,
            progressPercent: state.progressPercent,
            stepsDone: state.steps.where((s) => s['status'] == 'done').length,
            totalSteps: state.steps.length,
            currency: state.currency,
            incomeType: state.incomeType,
            typeColor: typeColor,
            isDark: isDark,
            onLogRevenue: () => _showLogRevenue(context, state, notifier),
            onGeneratePortfolio: () => _generatePortfolio(context, notifier),
          ),
          SliverPersistentHeader(
            delegate: _TabBarDelegate(
              tabController: _tabController,
              typeColor: typeColor,
              isDark: isDark,
            ),
            pinned: true,
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _StepsTab(
              steps: state.steps,
              isDark: isDark,
              onUpdateStep: notifier.updateStep,
              onAIAssist: (step) => _showAIAssist(context, state, step),
            ),
            _ToolsTab(
              freeTools: state.freeTools,
              paidTools: state.paidTools,
              totalRevenue: state.totalRevenue,
              currency: state.currency,
              isDark: isDark,
            ),
            _RevenueTab(
              logs: state.revenueLogs,
              total: state.totalRevenue,
              currency: state.currency,
              isDark: isDark,
              onLogRevenue: () => _showLogRevenue(context, state, notifier),
              timezone: state.timezone,
            ),
            _AIAssistTab(
              workflowId: widget.workflowId,
              steps: state.steps,
              isDark: isDark,
              onRunAI: (step, question) => notifier.getAIAssist(
                step['title']?.toString() ?? '',
                userQuestion: question,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getIncomeTypeColor(String type) {
    const colors = {
      'youtube': Color(0xFFFF0000),
      'tiktok': Color(0xFF000000),
      'instagram': Color(0xFFE1306C),
      'freelance': Color(0xFF00B894),
      'ecommerce': Color(0xFFE67E22),
      'dropshipping': Color(0xFF3498DB),
      'affiliate': Color(0xFF9B59B6),
      'content': Color(0xFFE91E63),
      'saas': Color(0xFF6C5CE7),
      'app_development': Color(0xFF00CEC9),
      'online_courses': Color(0xFFFD79A8),
      'digital_products': Color(0xFF00B894),
      'print_on_demand': Color(0xFFE17055),
      'virtual_assistant': Color(0xFF74B9FF),
      'translation': Color(0xFF55A3FF),
      'physical': Color(0xFF3498DB),
      'food_delivery': Color(0xFF00B894),
      'ride_sharing': Color(0xFFFDCB6E),
      'real_estate': Color(0xFF00B894),
      'stock_trading': Color(0xFF00CEC9),
      'crypto_trading': Color(0xFFF39C12),
      'remote_job': Color(0xFF6C5CE7),
      'other': Color(0xFF6C5CE7),
    };
    return colors[type] ?? AppColors.primary;
  }

  Future<void> _showLogRevenue(
    BuildContext context,
    WorkflowDetailState state,
    WorkflowDetailNotifier notifier,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogRevenueSheet(
        currency: state.currency,
        region: state.region,
        onLog: (amount, source, paymentMethod) async {
          Navigator.pop(context);
          try {
            await notifier.logRevenue(amount, source, paymentMethod);
            if (context.mounted) {
              _showSuccessSnackBar(context, '${state.currency} ${amount.toStringAsFixed(0)} logged!');
            }
          } catch (e) {
            if (context.mounted) {
              _showErrorSnackBar(context, 'Failed to log revenue: $e');
            }
          }
        },
      ),
    );
  }

  Future<void> _generatePortfolio(BuildContext context, WorkflowDetailNotifier notifier) async {
    _showLoadingSnackBar(context, 'Generating portfolio case study...');
    try {
      await notifier.generatePortfolio();
      if (context.mounted) {
        _showSuccessSnackBar(context, 'Added to your portfolio!');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  Future<void> _showAIAssist(
    BuildContext context,
    WorkflowDetailState state,
    Map step,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AIAssistSheet(
        stepTitle: step['title']?.toString() ?? '',
        stepDescription: step['description']?.toString() ?? '',
        workflowId: widget.workflowId,
        onRunAI: (question) async {
          final notifier = ref.read(workflowDetailProvider(widget.workflowId).notifier);
          return await notifier.getAIAssist(step['title']?.toString() ?? '', userQuestion: question);
        },
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Iconsax.tick_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Iconsax.warning_2, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
      ),
    );
  }

  void _showLoadingSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LOADING & ERROR SCREENS
// ═════════════════════════════════════════════════════════════════════════════

class _LoadingScreen extends StatelessWidget {
  final bool isDark;

  const _LoadingScreen({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Loading your workflow...',
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;

  const _ErrorScreen({
    required this.error,
    required this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Iconsax.warning_2, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Oops!',
                style: AppTextStyles.h3.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: AppTextStyles.body.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Iconsax.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SLIVER APP BAR HEADER
// ═════════════════════════════════════════════════════════════════════════════

class _SliverAppBarHeader extends StatelessWidget {
  final Map<String, dynamic> workflow;
  final double totalRevenue;
  final int progressPercent;
  final int stepsDone;
  final int totalSteps;
  final String currency;
  final String incomeType;
  final Color typeColor;
  final bool isDark;
  final VoidCallback onLogRevenue;
  final VoidCallback onGeneratePortfolio;

  const _SliverAppBarHeader({
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
    required this.onGeneratePortfolio,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      leading: IconButton(
        icon: const Icon(Iconsax.arrow_left),
        onPressed: () => context.pop(),
      ),
      actions: [
        if (totalRevenue > 0)
          IconButton(
            icon: const Icon(Iconsax.gallery, color: Colors.white),
            tooltip: 'Generate Portfolio Case Study',
            onPressed: onGeneratePortfolio,
          ),
        IconButton(
          icon: const Icon(Iconsax.add_circle, color: Colors.white),
          tooltip: 'Log Revenue',
          onPressed: onLogRevenue,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Iconsax.more, color: Colors.white),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'analytics',
              child: Row(
                children: [
                  Icon(Iconsax.chart, size: 16),
                  SizedBox(width: 8),
                  Text('View Analytics'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Iconsax.share, size: 16),
                  SizedBox(width: 8),
                  Text('Share Progress'),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'analytics') {
              context.push('/workflow/${workflow['id']}/analytics');
            }
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [typeColor.withOpacity(0.9), AppColors.primary],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Income type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _getIncomeTypeIcon(incomeType),
                        const SizedBox(width: 4),
                        Text(
                          incomeType.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Title
                  Text(
                    workflow['title']?.toString() ?? 'Workflow',
                    style: AppTextStyles.h2.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  
                  // Goal
                  Text(
                    workflow['goal']?.toString() ?? '',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  
                  // Stats row
                  Row(
                    children: [
                      _HeaderStat(
                        value: '$currency ${_formatNumber(totalRevenue)}',
                        label: 'Earned',
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 24),
                      _HeaderStat(
                        value: '$progressPercent%',
                        label: 'Progress',
                        color: Colors.white,
                      ),
                      const SizedBox(width: 24),
                      _HeaderStat(
                        value: '$stepsDone/$totalSteps',
                        label: 'Steps Done',
                        color: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Progress bar
                  ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: progressPercent / 100,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      minHeight: 6,
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

  Widget _getIncomeTypeIcon(String type) {
    final icons = {
      'youtube': Iconsax.video,
      'tiktok': Iconsax.music,
      'instagram': Iconsax.camera,
      'freelance': Iconsax.briefcase,
      'ecommerce': Iconsax.shopping_cart,
      'dropshipping': Iconsax.box,
      'affiliate': Iconsax.link,
      'content': Iconsax.document_text,
      'saas': Iconsax.cloud,
      'app_development': Iconsax.mobile,
      'online_courses': Iconsax.teacher,
      'digital_products': Iconsax.code,
      'print_on_demand': Iconsax.printer,
      'virtual_assistant': Iconsax.headphone,
      'translation': Iconsax.translate,
      'physical': Iconsax.shop,
      'food_delivery': Iconsax.truck_fast,
      'ride_sharing': Iconsax.car,
      'real_estate': Iconsax.building,
      'stock_trading': Iconsax.trend_up,
      // ── FIXED: Changed Iconsax.bitcoin to Iconsax.dollar_circle ──
      'crypto_trading': Iconsax.dollar_circle,
      'remote_job': Iconsax.monitor,
    };
    return Icon(icons[type] ?? Iconsax.activity, color: Colors.white, size: 12);
  }

  String _formatNumber(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _HeaderStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _HeaderStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB BAR DELEGATE
// ═════════════════════════════════════════════════════════════════════════════

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final Color typeColor;
  final bool isDark;

  _TabBarDelegate({
    required this.tabController,
    required this.typeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? AppColors.bgDark : Colors.white,
      child: TabBar(
        controller: tabController,
        indicatorColor: typeColor,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: typeColor,
        unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        tabs: const [
          Tab(text: 'Steps', icon: Icon(Iconsax.task, size: 18)),
          // ── FIXED: Changed Iconsax.tools to Iconsax.tool ──
          Tab(text: 'Tools', icon: Icon(Iconsax.tool, size: 18)),
          Tab(text: 'Revenue', icon: Icon(Iconsax.money, size: 18)),
          Tab(text: 'AI Assist', icon: Icon(Iconsax.cpu, size: 18)),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 56;

  @override
  double get minExtent => 56;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

// ═════════════════════════════════════════════════════════════════════════════
// STEPS TAB
// ═════════════════════════════════════════════════════════════════════════════

class _StepsTab extends StatelessWidget {
  final List<dynamic> steps;
  final bool isDark;
  final Function(String, String) onUpdateStep;
  final Function(Map) onAIAssist;

  const _StepsTab({
    required this.steps,
    required this.isDark,
    required this.onUpdateStep,
    required this.onAIAssist,
  });

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return _EmptyState(
        icon: Iconsax.task_square,
        title: 'No steps yet',
        subtitle: 'Your workflow steps will appear here',
        isDark: isDark,
      );
    }

    // Group steps by status
    final todoSteps = steps.where((s) => s['status'] != 'done').toList();
    final doneSteps = steps.where((s) => s['status'] == 'done').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (todoSteps.isNotEmpty) ...[
          _SectionTitle('To Do (${todoSteps.length})', isDark),
          const SizedBox(height: 12),
          ...todoSteps.asMap().entries.map((e) => _StepCard(
            step: e.value,
            index: e.key,
            isDark: isDark,
            onUpdate: onUpdateStep,
            onAI: onAIAssist,
          )),
        ],
        if (doneSteps.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle('Completed (${doneSteps.length})', isDark),
          const SizedBox(height: 12),
          ...doneSteps.asMap().entries.map((e) => _StepCard(
            step: e.value,
            index: e.key,
            isDark: isDark,
            onUpdate: onUpdateStep,
            onAI: onAIAssist,
            isDone: true,
          )),
        ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final Map step;
  final int index;
  final bool isDark;
  final Function(String, String) onUpdate;
  final Function(Map) onAI;
  final bool isDone;

  const _StepCard({
    required this.step,
    required this.index,
    required this.isDark,
    required this.onUpdate,
    required this.onAI,
    this.isDone = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = step['status']?.toString() ?? 'pending';
    final isAuto = step['step_type']?.toString() == 'automated';
    final stepId = step['id']?.toString() ?? '';
    final orderIndex = step['order_index'] as int? ?? index + 1;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'done':
        statusColor = AppColors.success;
        statusIcon = Iconsax.tick_circle;
        break;
      case 'in_progress':
        statusColor = AppColors.warning;
        statusIcon = Iconsax.timer;
        break;
      case 'blocked':
        statusColor = AppColors.error;
        statusIcon = Iconsax.warning_2;
        break;
      default:
        statusColor = isDark ? Colors.white30 : Colors.grey;
        // ── FIXED: Changed Iconsax.circle to Iconsax.record_circle ──
        statusIcon = Iconsax.record_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDone
            ? (isDark ? AppColors.bgCard.withOpacity(0.5) : const Color(0xFFF5F5F5))
            : (isDark ? AppColors.bgSurface : Colors.white),
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: isDone
              ? AppColors.success.withOpacity(0.3)
              : (isDark ? Colors.white12 : Colors.grey.shade200),
        ),
        boxShadow: isDone
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onUpdate(stepId, status == 'done' ? 'pending' : 'done');
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: status == 'done' ? AppColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor,
                    width: 2,
                  ),
                ),
                child: status == 'done'
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : Center(
                        child: Text(
                          '$orderIndex',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
            title: Text(
              step['title']?.toString() ?? '',
              style: AppTextStyles.label.copyWith(
                color: isDone
                    ? (isDark ? Colors.white54 : Colors.black54)
                    : (isDark ? Colors.white : Colors.black87),
                decoration: isDone ? TextDecoration.lineThrough : null,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  step['description']?.toString() ?? '',
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StepBadge(
                      text: isAuto ? '🤖 AI' : '👤 Manual',
                      color: isAuto ? AppColors.primary : AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    _StepBadge(
                      text: '${step['time_minutes'] ?? 30} min',
                      color: AppColors.textSecondary,
                    ),
                    if (step['tools'] != null && (step['tools'] as List).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _StepBadge(
                        text: '${(step['tools'] as List).length} tools',
                        color: AppColors.info,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: isAuto && !isDone
                ? GestureDetector(
                    onTap: () => onAI(step),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                        ),
                        borderRadius: AppRadius.pill,
                      ),
                      child: const Text(
                        'Run AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'mark_done') {
                        onUpdate(stepId, 'done');
                      } else if (value == 'mark_in_progress') {
                        onUpdate(stepId, 'in_progress');
                      } else if (value == 'mark_blocked') {
                        onUpdate(stepId, 'blocked');
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'mark_done', child: Text('✅ Mark Done')),
                      const PopupMenuItem(value: 'mark_in_progress', child: Text('⏳ In Progress')),
                      const PopupMenuItem(value: 'mark_blocked', child: Text('🚫 Blocked')),
                    ],
                  ),
          ),
          if (!isDone && step['tools'] != null && (step['tools'] as List).isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (step['tools'] as List).map((tool) {
                  return Chip(
                    label: Text(
                      tool.toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 60).ms).slideY(begin: 0.1);
  }
}

class _StepBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StepBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TOOLS TAB
// ═════════════════════════════════════════════════════════════════════════════

class _ToolsTab extends StatelessWidget {
  final List<dynamic> freeTools;
  final List<dynamic> paidTools;
  final double totalRevenue;
  final String currency;
  final bool isDark;

  const _ToolsTab({
    required this.freeTools,
    required this.paidTools,
    required this.totalRevenue,
    required this.currency,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Free Tools Section
        if (freeTools.isNotEmpty) ...[
          _SectionHeader(
            icon: Iconsax.gift,
            title: 'Free Tools',
            subtitle: 'Start with these — no cost',
            color: AppColors.success,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ...freeTools.asMap().entries.map((e) => _ToolCard(
            tool: e.value,
            isFree: true,
            isDark: isDark,
            index: e.key,
          )),
          const SizedBox(height: 24),
        ],

        // Paid Tools Section
        if (paidTools.isNotEmpty) ...[
          _SectionHeader(
            icon: Iconsax.crown,
            title: 'Upgrade When Ready',
            subtitle: 'Unlock as you earn more',
            color: AppColors.warning,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ...paidTools.asMap().entries.map((e) {
            final tool = e.value as Map;
            final unlockAt = (tool['unlock_at_revenue'] as num?)?.toDouble() ?? 0;
            final unlocked = totalRevenue >= unlockAt;
            
            return _ToolCard(
              tool: tool,
              isFree: false,
              isDark: isDark,
              unlocked: unlocked,
              unlockAt: unlockAt,
              currency: currency,
              index: e.key,
            );
          }),
        ],

        if (freeTools.isEmpty && paidTools.isEmpty)
          _EmptyState(
            icon: Iconsax.tool, // ── FIXED: Changed from Iconsax.tools ──
            title: 'No tools yet',
            subtitle: 'Tools will be added as you progress',
            isDark: isDark,
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDark;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: AppRadius.md,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.h4.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final Map tool;
  final bool isFree;
  final bool isDark;
  final bool unlocked;
  final double? unlockAt;
  final String? currency;
  final int index;

  const _ToolCard({
    required this.tool,
    required this.isFree,
    required this.isDark,
    this.unlocked = true,
    this.unlockAt,
    this.currency,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final color = isFree
        ? AppColors.success
        : (unlocked ? AppColors.primary : AppColors.textMuted);
    
    final regionAvailable = tool['region_available'] ?? true;
    final url = tool['url']?.toString() ?? '';

    return Opacity(
      opacity: unlocked ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgSurface : Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: color.withOpacity(unlocked ? 0.3 : 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: AppRadius.md,
              ),
              child: Center(
                child: Icon(
                  isFree
                      ? Iconsax.tick_circle
                      : (unlocked ? Iconsax.unlock : Iconsax.lock),
                  color: color,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tool['name']?.toString() ?? '',
                        style: AppTextStyles.label.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                        ),
                      ),
                      if (!regionAvailable) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: AppRadius.pill,
                          ),
                          child: const Text(
                            'Regional',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool['purpose']?.toString() ?? '',
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isFree && !unlocked && unlockAt != null) ...[
                    const SizedBox(height: 8),
                    // ── FIXED: Cast unlockAt to double and handle null properly ──
                    LinearProgressIndicator(
                      value: (totalRevenue / (unlockAt ?? 1.0)).clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 4,
                      borderRadius: AppRadius.pill,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Unlock at $currency ${_formatNumber(unlockAt!)} (current: $currency ${_formatNumber(totalRevenue)})',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (url.isNotEmpty && (isFree || unlocked))
              IconButton(
                icon: const Icon(Iconsax.external_drive, size: 20),
                onPressed: () {
                  // Open URL
                },
              ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (index * 80).ms);
  }

  double get totalRevenue => 0; // This would come from state

  String _formatNumber(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// REVENUE TAB (Enhanced with Charts)
// ═════════════════════════════════════════════════════════════════════════════

class _RevenueTab extends StatelessWidget {
  final List<dynamic> logs;
  final double total;
  final String currency;
  final bool isDark;
  final VoidCallback onLogRevenue;
  final String timezone;

  const _RevenueTab({
    required this.logs,
    required this.total,
    required this.currency,
    required this.isDark,
    required this.onLogRevenue,
    required this.timezone,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final currencyFormat = NumberFormat.currency(
      locale: locale.toString(),
      symbol: currency,
      decimalDigits: 0,
    );

    if (logs.isEmpty) {
      return _EmptyRevenueState(
        currency: currency,
        isDark: isDark,
        onLogRevenue: onLogRevenue,
      );
    }

    // Prepare chart data
    final dailyRevenue = _aggregateDailyRevenue(logs);
    // ── FIXED: Corrected FlSpot creation to use MapEntry properly ──
    final spots = dailyRevenue.entries.toList().asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value); // Use e.value.value for MapEntry
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Total Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00B894), Color(0xFF00CEC9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadius.lg,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Earnings',
                        style: AppTextStyles.label.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currencyFormat.format(total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Iconsax.wallet_3,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _RevenueStat(
                    icon: Iconsax.receipt_item,
                    value: '${logs.length}',
                    label: 'Transactions',
                  ),
                  const SizedBox(width: 24),
                  _RevenueStat(
                    icon: Iconsax.calculator,
                    value: currencyFormat.format(total / logs.length),
                    label: 'Avg/Transaction',
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: -0.1),

        const SizedBox(height: 24),

        // Chart
        if (spots.length > 1) ...[
          Text(
            'Revenue Trend',
            style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.lg,
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B894), Color(0xFF00CEC9)],
                    ),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: spots.length < 10),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00B894).withOpacity(0.3),
                          const Color(0xFF00CEC9).withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Recent Transactions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transactions',
              style: AppTextStyles.h4.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            TextButton.icon(
              onPressed: onLogRevenue,
              icon: const Icon(Iconsax.add, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        ...logs.take(10).toList().asMap().entries.map((e) {
          final log = e.value as Map;
          final date = DateTime.tryParse(log['created_at']?.toString() ?? '') ?? DateTime.now();
          final localDate = date.toLocal();
          
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.md,
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('💸', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log['source']?.toString().isNotEmpty == true
                            ? log['source'].toString()
                            : 'Revenue',
                        style: AppTextStyles.label.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(localDate, timezone),
                        style: AppTextStyles.caption.copyWith(fontSize: 11),
                      ),
                      if (log['payment_method'] != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: AppRadius.pill,
                          ),
                          child: Text(
                            log['payment_method'].toString(),
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '+${currencyFormat.format((log['amount'] as num?)?.toDouble() ?? 0)}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: (e.key * 50).ms);
        }),
      ],
    );
  }

  Map<String, double> _aggregateDailyRevenue(List<dynamic> logs) {
    final daily = <String, double>{};
    for (final log in logs) {
      final date = log['created_at']?.toString().substring(0, 10) ?? 'unknown';
      final amount = (log['amount'] as num?)?.toDouble() ?? 0;
      daily[date] = (daily[date] ?? 0) + amount;
    }
    return Map.fromEntries(
      daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  String _formatDate(DateTime date, String timezone) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    
    return DateFormat('MMM d, y').format(date);
  }
}

class _RevenueStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _RevenueStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyRevenueState extends StatelessWidget {
  final String currency;
  final bool isDark;
  final VoidCallback onLogRevenue;

  const _EmptyRevenueState({
    required this.currency,
    required this.isDark,
    required this.onLogRevenue,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('💰', style: TextStyle(fontSize: 48)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start Earning!',
              style: AppTextStyles.h3.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Execute your workflow steps and log your income here. Track your progress to unlock paid tools.',
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onLogRevenue,
              icon: const Icon(Iconsax.add_circle),
              label: const Text('Log First Income'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AI ASSIST TAB (Enhanced)
// ═════════════════════════════════════════════════════════════════════════════

class _AIAssistTab extends StatefulWidget {
  final String workflowId;
  final List<dynamic> steps;
  final bool isDark;
  final Future<Map<String, dynamic>> Function(String, String?) onRunAI;

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
  Map? _selectedStep;
  final _questionCtrl = TextEditingController();
  String _aiOutput = '';
  bool _running = false;
  List<Map<String, dynamic>> _history = [];

  @override
  Widget build(BuildContext context) {
    final autoSteps = widget.steps.where((s) => s['step_type'] == 'automated').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.2),
                AppColors.accent.withOpacity(0.2),
              ],
            ),
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Text('🤖', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Execution Engine',
                      style: AppTextStyles.label.copyWith(
                        color: widget.isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select any step and AI will generate ready-to-use content, scripts, or strategies specific to your workflow.',
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Step Selector
        Text(
          'Select a step to execute:',
          style: AppTextStyles.h4.copyWith(
            color: widget.isDark ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.steps.map((step) {
            final s = step as Map;
            final selected = _selectedStep?['id'] == s['id'];
            final isAuto = s['step_type'] == 'automated';

            return GestureDetector(
              onTap: () => setState(() => _selectedStep = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : (widget.isDark ? AppColors.bgSurface : Colors.white),
                  borderRadius: AppRadius.pill,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.textMuted,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAuto ? '🤖' : '👤',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s['title']?.toString() ?? '',
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        if (_selectedStep != null) ...[
          const SizedBox(height: 24),

          // Context Input
          TextField(
            controller: _questionCtrl,
            style: AppTextStyles.body.copyWith(
              color: widget.isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Optional: Add context for better results (e.g., "My audience is students in Nigeria")',
              hintStyle: AppTextStyles.caption,
              filled: true,
              fillColor: widget.isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Iconsax.message_text),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 16),

          // Run Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runAI,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Iconsax.flash),
              label: Text(_running ? 'AI is working...' : 'Execute with AI'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
                elevation: 8,
                shadowColor: AppColors.primary.withOpacity(0.4),
              ),
            ),
          ),

          // History
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Generations',
                  style: AppTextStyles.h4.copyWith(
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _history.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._history.take(3).map((h) => _HistoryItem(
              stepTitle: h['step_title'],
              preview: h['output'].toString().substring(0, (h['output'].toString().length > 50 ? 50 : h['output'].toString().length)),
              onTap: () => setState(() => _aiOutput = h['output']),
              isDark: widget.isDark,
            )),
          ],
        ],

        // Output
        if (_aiOutput.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI Output',
                style: AppTextStyles.h4.copyWith(
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Iconsax.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _aiOutput));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Iconsax.refresh, size: 20),
                    onPressed: _runAI,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.isDark ? AppColors.bgSurface : Colors.white,
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: SelectableText(
              _aiOutput,
              style: AppTextStyles.body.copyWith(
                color: widget.isDark ? Colors.white : Colors.black87,
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

    setState(() {
      _running = true;
    });

    try {
      final result = await widget.onRunAI(
        _selectedStep!['title']?.toString() ?? '',
        _questionCtrl.text.trim().isEmpty ? null : _questionCtrl.text.trim(),
      );

      final output = result['ai_output']?.toString() ?? '';
      
      setState(() {
        _aiOutput = output;
        _running = false;
        _history.insert(0, {
          'step_title': _selectedStep!['title'],
          'output': output,
          'timestamp': DateTime.now(),
        });
      });
    } catch (e) {
      setState(() {
        _running = false;
        _aiOutput = 'Error: $e';
      });
    }
  }
}

class _HistoryItem extends StatelessWidget {
  final String stepTitle;
  final String preview;
  final VoidCallback onTap;
  final bool isDark;

  const _HistoryItem({
    required this.stepTitle,
    required this.preview,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgSurface : Colors.white,
          borderRadius: AppRadius.md,
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.clock, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stepTitle,
                    style: AppTextStyles.label.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    preview,
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Iconsax.arrow_right_3, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LOG REVENUE SHEET (Enhanced with Payment Methods)
// ═════════════════════════════════════════════════════════════════════════════

class _LogRevenueSheet extends StatefulWidget {
  final String currency;
  final String region;
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
  String? _selectedPaymentMethod;

  final Map<String, List<String>> _paymentMethods = {
    'global': ['PayPal', 'Wise', 'Payoneer', 'Bank Transfer', 'Crypto'],
    'africa_west': ['PayPal', 'Chipper Cash', 'Flutterwave', 'Paga', 'Bank Transfer'],
    'africa_east': ['M-Pesa', 'PayPal', 'Flutterwave', 'Chipper Cash'],
    'south_asia': ['PayPal', 'Razorpay', 'Paytm', 'UPI', 'bKash'],
    'southeast_asia': ['PayPal', 'PayMongo', 'Xendit', 'GrabPay'],
    'latin_america': ['PayPal', 'Mercado Pago', 'Pix', 'Ualá'],
    'middle_east': ['PayPal', 'Telr', 'Paymob', 'Fawry'],
  };

  List<String> get _methods {
    return _paymentMethods[widget.region] ?? _paymentMethods['global']!;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: AppRadius.pill,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Log Revenue',
            style: AppTextStyles.h3.copyWith(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your earnings to unlock tools and see progress',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 20),

          // Amount
          TextField(
            controller: _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body.copyWith(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixText: '${widget.currency}  ',
              prefixStyle: TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              hintText: '0.00',
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Source
          TextField(
            controller: _srcCtrl,
            style: AppTextStyles.body.copyWith(
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Source (e.g., YouTube AdSense, Client payment)',
              prefixIcon: const Icon              hintText: 'Source (e.g., YouTube AdSense, Client payment)',
              prefixIcon: const Icon(Iconsax.tag),
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.lg,
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Payment Method
          Text(
            'Payment Method',
            style: AppTextStyles.label.copyWith(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _methods.map((method) {
              final selected = _selectedPaymentMethod == method;
              return ChoiceChip(
                label: Text(method),
                selected: selected,
                onSelected: (selected) {
                  setState(() {
                    _selectedPaymentMethod = selected ? method : null;
                  });
                },
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Submit
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final amt = double.tryParse(_amtCtrl.text) ?? 0;
                if (amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                widget.onLog(amt, _srcCtrl.text.trim(), _selectedPaymentMethod);
              },
              icon: const Icon(Iconsax.tick_circle),
              label: const Text('Log Income'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AI ASSIST SHEET (Enhanced)
// ═════════════════════════════════════════════════════════════════════════════

class _AIAssistSheet extends StatefulWidget {
  final String stepTitle;
  final String stepDescription;
  final String workflowId;
  final Future<Map<String, dynamic>> Function(String?) onRunAI;

  const _AIAssistSheet({
    required this.stepTitle,
    required this.stepDescription,
    required this.workflowId,
    required this.onRunAI,
  });

  @override
  State<_AIAssistSheet> createState() => _AIAssistSheetState();
}

class _AIAssistSheetState extends State<_AIAssistSheet> {
  bool _running = true;
  String _output = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _runAI();
  }

  Future<void> _runAI() async {
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final result = await widget.onRunAI(null);
      setState(() {
        _output = result['ai_output']?.toString() ?? '';
        _running = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: AppRadius.pill,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: AppRadius.md,
                ),
                child: const Text('🤖', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Execution',
                      style: AppTextStyles.h4.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      widget.stepTitle,
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_running)
                IconButton(
                  icon: const Icon(Iconsax.refresh),
                  onPressed: _runAI,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _running
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text(
                          'AI is generating your content...',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text(
                              'Something went wrong',
                              style: AppTextStyles.h4,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: AppTextStyles.caption,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _runAI,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.bgSurface : const Color(0xFFF8F8F8),
                            borderRadius: AppRadius.lg,
                          ),
                          child: SelectableText(
                            _output,
                            style: AppTextStyles.body.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
          ),
          if (!_running && _error == null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _output));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Copied to clipboard!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                    icon: const Icon(Iconsax.copy),
                    label: const Text('Copy & Use'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionTitle(this.text, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.h4.copyWith(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(
              color: isDark ? Colors.white54 : Colors.black38,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

