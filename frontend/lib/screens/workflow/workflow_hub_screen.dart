// frontend/lib/screens/workflow/workflow_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';

// ═════════════════════════════════════════════════════════════════════════════
// RIVERPOD STATE MANAGEMENT
// ═════════════════════════════════════════════════════════════════════════════

final workflowHubProvider = StateNotifierProvider<WorkflowHubNotifier, WorkflowHubState>((ref) {
  return WorkflowHubNotifier(ref);
});

class WorkflowHubState {
  final List<WorkflowModel> workflows;
  final bool isLoading;
  final String? error;
  final String selectedFilter;
  final String searchQuery;

  WorkflowHubState({
    this.workflows = const [],
    this.isLoading = true,
    this.error,
    this.selectedFilter = 'all',
    this.searchQuery = '',
  });

  WorkflowHubState copyWith({
    List<WorkflowModel>? workflows,
    bool? isLoading,
    String? error,
    String? selectedFilter,
    String? searchQuery,
  }) {
    return WorkflowHubState(
      workflows: workflows ?? this.workflows,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  double get totalRevenue => workflows.fold(0.0, (sum, w) => sum + w.totalRevenue);
  int get activeCount => workflows.where((w) => w.status == 'active').length;
  int get completedCount => workflows.where((w) => w.progressPercent == 100).length;
  
  List<WorkflowModel> get filteredWorkflows {
    var filtered = workflows;
    
    // Filter by status
    if (selectedFilter != 'all') {
      filtered = filtered.where((w) {
        switch (selectedFilter) {
          case 'active':
            return w.status == 'active' && w.progressPercent < 100;
          case 'completed':
            return w.progressPercent == 100;
          case 'high_earners':
            return w.totalRevenue > 0;
          default:
            return true;
        }
      }).toList();
    }
    
    // Filter by search
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((w) =>
        w.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
        w.goal.toLowerCase().contains(searchQuery.toLowerCase()) ||
        w.incomeType.toLowerCase().contains(searchQuery.toLowerCase())
      ).toList();
    }
    
    return filtered;
  }
}

class WorkflowHubNotifier extends StateNotifier<WorkflowHubState> {
  final Ref ref;

  WorkflowHubNotifier(this.ref) : super(WorkflowHubState()) {
    loadWorkflows();
  }

  Future<void> loadWorkflows() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await api.get('/workflow/');
      final list = (data['workflows'] as List? ?? []);
      final workflows = list.map((w) => WorkflowModel.fromJson(w)).toList();
      state = state.copyWith(workflows: workflows, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load workflows: $e');
    }
  }

  void setFilter(String filter) {
    state = state.copyWith(selectedFilter: filter);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> deleteWorkflow(String id) async {
    try {
      // Assuming there's a delete endpoint
      await api.delete('/workflow/$id');
      await loadWorkflows();
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete workflow: $e');
    }
  }

  String getPrimaryCurrency() {
    if (state.workflows.isEmpty) return 'USD';
    // Get most common currency or first one
    final currencyCounts = <String, int>{};
    for (final w in state.workflows) {
      currencyCounts[w.currency] = (currencyCounts[w.currency] ?? 0) + 1;
    }
    return currencyCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ENHANCED MODELS
// ═════════════════════════════════════════════════════════════════════════════

class WorkflowModel {
  final String id;
  final String title;
  final String goal;
  final String incomeType;
  final String status;
  final double totalRevenue;
  final String currency;
  final String language;
  final String region;
  final int progressPercent;
  final int viabilityScore;
  final String timeline;
  final double potentialMin;
  final double potentialMax;
  final String createdAt;
  final String? timezone;

  WorkflowModel({
    required this.id,
    required this.title,
    required this.goal,
    required this.incomeType,
    required this.status,
    required this.totalRevenue,
    required this.currency,
    required this.language,
    required this.region,
    required this.progressPercent,
    required this.viabilityScore,
    required this.timeline,
    required this.potentialMin,
    required this.potentialMax,
    required this.createdAt,
    this.timezone,
  });

  factory WorkflowModel.fromJson(Map d) {
    return WorkflowModel(
      id: d['id']?.toString() ?? '',
      title: d['title']?.toString() ?? '',
      goal: d['goal']?.toString() ?? '',
      incomeType: d['income_type']?.toString() ?? 'other',
      status: d['status']?.toString() ?? 'active',
      totalRevenue: (d['total_revenue'] as num?)?.toDouble() ?? 0.0,
      currency: d['currency']?.toString() ?? 'USD',
      language: d['language']?.toString() ?? 'en',
      region: d['region']?.toString() ?? 'global',
      progressPercent: (d['progress_percent'] as num?)?.toInt() ?? 0,
      viabilityScore: (d['viability_score'] as num?)?.toInt() ?? 75,
      timeline: d['realistic_timeline']?.toString() ?? '',
      potentialMin: (d['potential_min'] as num?)?.toDouble() ?? 0.0,
      potentialMax: (d['potential_max'] as num?)?.toDouble() ?? 0.0,
      createdAt: d['created_at']?.toString() ?? '',
      timezone: d['timezone']?.toString(),
    );
  }

  bool get isCompleted => progressPercent == 100;
  bool get isActive => status == 'active' && !isCompleted;
  double get progressDecimal => progressPercent / 100;
}

// ═════════════════════════════════════════════════════════════════════════════
// INCOME TYPE CONFIGURATION (Global)
// ═════════════════════════════════════════════════════════════════════════════

class IncomeTypeConfig {
  final String emoji;
  final Color color;
  final String label;
  final IconData icon;

  const IncomeTypeConfig({
    required this.emoji,
    required this.color,
    required this.label,
    required this.icon,
  });
}

final incomeTypeConfigs = {
  'youtube': IncomeTypeConfig(
    emoji: '▶️',
    color: const Color(0xFFFF0000),
    label: 'YouTube',
    icon: Iconsax.video,
  ),
  'tiktok': IncomeTypeConfig(
    emoji: '🎵',
    color: const Color(0xFF000000),
    label: 'TikTok',
    icon: Iconsax.music,
  ),
  'instagram': IncomeTypeConfig(
    emoji: '📸',
    color: const Color(0xFFE1306C),
    label: 'Instagram',
    icon: Iconsax.camera,
  ),
  'freelance': IncomeTypeConfig(
    emoji: '💻',
    color: const Color(0xFF00B894),
    label: 'Freelance',
    icon: Iconsax.briefcase,
  ),
  'ecommerce': IncomeTypeConfig(
    emoji: '🛍️',
    color: const Color(0xFFE67E22),
    label: 'E-commerce',
    icon: Iconsax.shopping_cart,
  ),
  'dropshipping': IncomeTypeConfig(
    emoji: '📦',
    color: const Color(0xFF3498DB),
    label: 'Dropshipping',
    icon: Iconsax.box,
  ),
  'affiliate': IncomeTypeConfig(
    emoji: '🔗',
    color: const Color(0xFF9B59B6),
    label: 'Affiliate',
    icon: Iconsax.link,
  ),
  'content': IncomeTypeConfig(
    emoji: '✍️',
    color: const Color(0xFFE91E63),
    label: 'Content',
    icon: Iconsax.document_text,
  ),
  'saas': IncomeTypeConfig(
    emoji: '☁️',
    color: const Color(0xFF6C5CE7),
    label: 'SaaS',
    icon: Iconsax.cloud,
  ),
  'app_development': IncomeTypeConfig(
    emoji: '📱',
    color: const Color(0xFF00CEC9),
    label: 'App Dev',
    icon: Iconsax.mobile,
  ),
  'online_courses': IncomeTypeConfig(
    emoji: '🎓',
    color: const Color(0xFFFD79A8),
    label: 'Courses',
    icon: Iconsax.teacher,
  ),
  'digital_products': IncomeTypeConfig(
    emoji: '💾',
    color: const Color(0xFF00B894),
    label: 'Digital Products',
    icon: Iconsax.code,
  ),
  'print_on_demand': IncomeTypeConfig(
    emoji: '🖨️',
    color: const Color(0xFFE17055),
    label: 'Print on Demand',
    icon: Iconsax.printer,
  ),
  'virtual_assistant': IncomeTypeConfig(
    emoji: '🎧',
    color: const Color(0xFF74B9FF),
    label: 'Virtual Assistant',
    icon: Iconsax.headphone,
  ),
  'translation': IncomeTypeConfig(
    emoji: '🌐',
    color: const Color(0xFF55A3FF),
    label: 'Translation',
    icon: Iconsax.translate,
  ),
  'physical': IncomeTypeConfig(
    emoji: '🏪',
    color: const Color(0xFF3498DB),
    label: 'Physical Business',
    icon: Iconsax.shop,
  ),
  'food_delivery': IncomeTypeConfig(
    emoji: '🍔',
    color: const Color(0xFF00B894),
    label: 'Food Delivery',
    icon: Iconsax.truck_fast,
  ),
  'ride_sharing': IncomeTypeConfig(
    emoji: '🚗',
    color: const Color(0xFFFDCB6E),
    label: 'Ride Sharing',
    icon: Iconsax.car,
  ),
  'real_estate': IncomeTypeConfig(
    emoji: '🏢',
    color: const Color(0xFF00B894),
    label: 'Real Estate',
    icon: Iconsax.building,
  ),
  'stock_trading': IncomeTypeConfig(
    emoji: '📈',
    color: const Color(0xFF00CEC9),
    label: 'Stock Trading',
    icon: Iconsax.trend_up,
  ),
  'crypto_trading': IncomeTypeConfig(
    emoji: '₿',
    color: const Color(0xFFF39C12),
    label: 'Crypto Trading',
    icon: Iconsax.bitcoin,
  ),
  'remote_job': IncomeTypeConfig(
    emoji: '🏠',
    color: const Color(0xFF6C5CE7),
    label: 'Remote Job',
    icon: Iconsax.monitor,
  ),
  'other': IncomeTypeConfig(
    emoji: '💡',
    color: const Color(0xFF6C5CE7),
    label: 'Other',
    icon: Iconsax.activity,
  ),
};

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class WorkflowHubScreen extends ConsumerStatefulWidget {
  const WorkflowHubScreen({super.key});

  @override
  ConsumerState<WorkflowHubScreen> createState() => _WorkflowHubScreenState();
}

class _WorkflowHubScreenState extends ConsumerState<WorkflowHubScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(workflowHubProvider.notifier).setSearchQuery(_searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(workflowHubProvider);
    final notifier = ref.read(workflowHubProvider.notifier);
    final locale = ref.watch(localeProvider);
    
    final currencyFormat = NumberFormat.currency(
      locale: locale.toString(),
      symbol: state.workflows.isNotEmpty ? state.workflows.first.currency : 'USD',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: RefreshIndicator(
        onRefresh: notifier.loadWorkflows,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            // Header with gradient
            _SliverHeader(
              workflowCount: state.workflows.length,
              activeCount: state.activeCount,
              totalRevenue: state.totalRevenue,
              primaryCurrency: notifier.getPrimaryCurrency(),
              isDark: isDark,
              onNewWorkflow: () => context.push('/workflow/new'),
            ),

            // Search and Filter Bar
            if (!state.isLoading && state.workflows.isNotEmpty)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchBarDelegate(
                  searchCtrl: _searchCtrl,
                  selectedFilter: state.selectedFilter,
                  onFilterChanged: notifier.setFilter,
                  isDark: isDark,
                ),
              ),

            // Content
            if (state.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (state.error != null)
              SliverFillRemaining(
                child: _ErrorState(
                  error: state.error!,
                  onRetry: notifier.loadWorkflows,
                  isDark: isDark,
                ),
              )
            else if (state.workflows.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(onCreate: () => context.push('/workflow/new')),
              )
            else if (state.filteredWorkflows.isEmpty)
              SliverFillRemaining(
                child: _NoResultsState(
                  searchQuery: state.searchQuery,
                  onClear: () {
                    _searchCtrl.clear();
                    notifier.setSearchQuery('');
                  },
                  isDark: isDark,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _WorkflowCard(
                      workflow: state.filteredWorkflows[i],
                      currencyFormat: currencyFormat,
                      onTap: () => context.push('/workflow/${state.filteredWorkflows[i].id}'),
                    ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.1),
                    childCount: state.filteredWorkflows.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: !state.isLoading && state.workflows.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/workflow/new'),
              icon: const Icon(Iconsax.add),
              label: const Text('New Workflow'),
              backgroundColor: AppColors.primary,
            )
          : null,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SLIVER HEADER
// ═════════════════════════════════════════════════════════════════════════════

class _SliverHeader extends StatelessWidget {
  final int workflowCount;
  final int activeCount;
  final double totalRevenue;
  final String primaryCurrency;
  final bool isDark;
  final VoidCallback onNewWorkflow;

  const _SliverHeader({
    required this.workflowCount,
    required this.activeCount,
    required this.totalRevenue,
    required this.primaryCurrency,
    required this.isDark,
    required this.onNewWorkflow,
  });

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.compact();

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: AppRadius.md,
                        ),
                        child: const Icon(Iconsax.flash, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Workflow Engine',
                              style: AppTextStyles.h3.copyWith(color: Colors.white),
                            ),
                            Text(
                              'Your global income command center',
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: onNewWorkflow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: AppRadius.pill,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Iconsax.add, color: AppColors.primary, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'New',
                                style: AppTextStyles.label.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _StatCard(
                        value: numberFormat.format(workflowCount),
                        label: 'Workflows',
                        icon: Iconsax.task_square,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        value: numberFormat.format(activeCount),
                        label: 'Active',
                        icon: Iconsax.flash_circle,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        value: _formatRevenue(totalRevenue, primaryCurrency),
                        label: 'Total Earned',
                        icon: Iconsax.money_tick,
                        isHighlighted: totalRevenue > 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRevenue(double amount, String currency) {
    if (amount >= 1000000) {
      return '${currency} ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${currency} ${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '${currency} ${amount.toStringAsFixed(0)}';
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool isHighlighted;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlighted
              ? Colors.white.withOpacity(0.25)
              : Colors.white.withOpacity(0.15),
          borderRadius: AppRadius.md,
          border: isHighlighted
              ? Border.all(color: Colors.white.withOpacity(0.5))
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SEARCH BAR DELEGATE
// ═════════════════════════════════════════════════════════════════════════════

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchCtrl;
  final String selectedFilter;
  final Function(String) onFilterChanged;
  final bool isDark;

  _SearchBarDelegate({
    required this.searchCtrl,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? AppColors.bgDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          // Search Field
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search workflows...',
              prefixIcon: const Icon(Iconsax.search_normal, size: 20),
              suffixIcon: searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Iconsax.close_circle, size: 20),
                      onPressed: searchCtrl.clear,
                    )
                  : null,
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: AppRadius.pill,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: selectedFilter == 'all',
                  onTap: () => onFilterChanged('all'),
                ),
                _FilterChip(
                  label: 'Active',
                  isSelected: selectedFilter == 'active',
                  onTap: () => onFilterChanged('active'),
                ),
                _FilterChip(
                  label: 'Completed',
                  isSelected: selectedFilter == 'completed',
                  onTap: () => onFilterChanged('completed'),
                ),
                _FilterChip(
                  label: 'Earning',
                  isSelected: selectedFilter == 'high_earners',
                  onTap: () => onFilterChanged('high_earners'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 120;

  @override
  double get minExtent => 120;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WORKFLOW CARD (Enhanced)
// ═════════════════════════════════════════════════════════════════════════════

class _WorkflowCard extends StatelessWidget {
  final WorkflowModel workflow;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  const _WorkflowCard({
    required this.workflow,
    required this.currencyFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = incomeTypeConfigs[workflow.incomeType] ?? incomeTypeConfigs['other']!;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: config.color.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [config.color.withOpacity(0.2), config.color.withOpacity(0.1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: AppRadius.md,
                    ),
                    child: Center(
                      child: Text(
                        config.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                workflow.title,
                                style: AppTextStyles.h4.copyWith(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (workflow.isCompleted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.15),
                                  borderRadius: AppRadius.pill,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Iconsax.tick_circle, size: 12, color: AppColors.success),
                                    SizedBox(width: 4),
                                    Text(
                                      'Done',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: config.color.withOpacity(0.15),
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                config.label.toUpperCase(),
                                style: TextStyle(
                                  color: config.color,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Iconsax.clock, size: 12, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              workflow.timeline,
                              style: AppTextStyles.caption.copyWith(fontSize: 10),
                            ),
                            if (workflow.region != 'global') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withOpacity(0.1),
                                  borderRadius: AppRadius.pill,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Iconsax.global, size: 10, color: AppColors.info),
                                    const SizedBox(width: 2),
                                    Text(
                                      workflow.region.toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.info,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Revenue
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currencyFormat.format(workflow.totalRevenue),
                        style: TextStyle(
                          color: workflow.totalRevenue > 0 ? AppColors.success : AppColors.textMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'earned',
                        style: AppTextStyles.caption.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Progress bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${workflow.progressPercent}% complete',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${workflow.viabilityScore}/100 viability',
                        style: TextStyle(
                          color: config.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: workflow.progressDecimal,
                      backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(config.color),
                      minHeight: 6,
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

// ═════════════════════════════════════════════════════════════════════════════
// EMPTY, ERROR, AND NO RESULTS STATES
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadius.xl,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Text('⚡', style: TextStyle(fontSize: 60)),
              ),
            ).animate().scale(duration: 600.ms).then().shimmer(duration: 2.seconds),
            const SizedBox(height: 32),
            Text(
              'Start Your Income Journey',
              style: AppTextStyles.h2.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Tell the AI your income goal. It will research what\'s working in your region, create a step-by-step plan, and help you execute it.',
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: onCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                  ),
                  borderRadius: AppRadius.pill,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C5CE7).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Iconsax.flash, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Create My First Workflow',
                      style: AppTextStyles.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Quick suggestions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip('YouTube Channel'),
                _SuggestionChip('Freelance Design'),
                _SuggestionChip('E-commerce Store'),
                _SuggestionChip('Online Course'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;

  const _SuggestionChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: AppColors.primary.withOpacity(0.1),
      labelStyle: TextStyle(
        color: AppColors.primary,
        fontSize: 12,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;

  const _ErrorState({
    required this.error,
    required this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.warning_2, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Oops! Something went wrong',
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
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String searchQuery;
  final VoidCallback onClear;
  final bool isDark;

  const _NoResultsState({
    required this.searchQuery,
    required this.onClear,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.search_normal, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No workflows found',
              style: AppTextStyles.h3.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No results for "$searchQuery"',
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Iconsax.close_circle),
              label: const Text('Clear Search'),
            ),
          ],
        ),
      ),
    );
  }
}
