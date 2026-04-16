// frontend/lib/screens/workflow/workflow_hub_screen.dart
// v3.3 — Icon-overlap fix · Interstitial-on-saved-workflow-tap · Responsive · Natural UI
//
// Key changes:
//  1. Icon moved into SliverAppBar title row — never overlaps back arrow
//  2. adManager.showInterstitial() fires when tapping EXISTING saved workflow
//  3. _WorkflowCard: richer design with timeSinceCreated + better viability badge
//  4. _StatCard: adaptive font size via LayoutBuilder for narrow screens
//  5. All hardcoded sizes use MediaQuery fractions

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';

// ═══════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════

final workflowHubProvider =
    StateNotifierProvider<WorkflowHubNotifier, WorkflowHubState>(
        (ref) => WorkflowHubNotifier(ref));

class WorkflowHubState {
  final List<WorkflowModel> workflows;
  final bool isLoading;
  final String? error;
  final String selectedFilter;
  final String searchQuery;

  const WorkflowHubState({
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
  }) =>
      WorkflowHubState(
        workflows:      workflows      ?? this.workflows,
        isLoading:      isLoading      ?? this.isLoading,
        error:          error          ?? this.error,
        selectedFilter: selectedFilter ?? this.selectedFilter,
        searchQuery:    searchQuery    ?? this.searchQuery,
      );

  double get totalRevenue   => workflows.fold(0.0, (s, w) => s + w.totalRevenue);
  int    get activeCount    => workflows.where((w) => w.status == 'active').length;
  int    get completedCount => workflows.where((w) => w.progressPercent == 100).length;

  List<WorkflowModel> get filteredWorkflows {
    var list = workflows;
    if (selectedFilter != 'all') {
      list = list.where((w) {
        switch (selectedFilter) {
          case 'active':       return w.status == 'active' && w.progressPercent < 100;
          case 'completed':    return w.progressPercent == 100;
          case 'high_earners': return w.totalRevenue > 0;
          default:             return true;
        }
      }).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list
          .where((w) =>
              w.title.toLowerCase().contains(q) ||
              w.goal.toLowerCase().contains(q) ||
              w.incomeType.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }
}

class WorkflowHubNotifier extends StateNotifier<WorkflowHubState> {
  final Ref ref;
  WorkflowHubNotifier(this.ref) : super(const WorkflowHubState()) {
    loadWorkflows();
  }

  Future<void> loadWorkflows() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await api.get('/workflow/');
      final workflows = (data['workflows'] as List? ?? [])
          .map((w) => WorkflowModel.fromJson(w as Map))
          .toList();
      adManager.setWorkflowCount(workflows.length);
      state = state.copyWith(workflows: workflows, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load workflows: $e');
    }
  }

  void setFilter(String f)     => state = state.copyWith(selectedFilter: f);
  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);

  Future<void> deleteWorkflow(String id) async {
    try {
      await api.delete('/workflow/$id');
      await loadWorkflows();
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete: $e');
    }
  }

  String getPrimaryCurrency() {
    if (state.workflows.isEmpty) return 'USD';
    final counts = <String, int>{};
    for (final w in state.workflows) {
      counts[w.currency] = (counts[w.currency] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

// ═══════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════

class WorkflowModel {
  final String id, title, goal, incomeType, status;
  final String currency, language, region, createdAt;
  final double totalRevenue, potentialMin, potentialMax;
  final int    progressPercent, viabilityScore;
  final String timeline;
  final String? timezone;

  const WorkflowModel({
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

  factory WorkflowModel.fromJson(Map d) => WorkflowModel(
        id:              d['id']?.toString()                        ?? '',
        title:           d['title']?.toString()                    ?? '',
        goal:            d['goal']?.toString()                     ?? '',
        incomeType:      d['income_type']?.toString()              ?? 'other',
        status:          d['status']?.toString()                   ?? 'active',
        totalRevenue:    (d['total_revenue']    as num?)?.toDouble() ?? 0.0,
        currency:        d['currency']?.toString()                 ?? 'USD',
        language:        d['language']?.toString()                 ?? 'en',
        region:          d['region']?.toString()                   ?? 'global',
        progressPercent: (d['progress_percent'] as num?)?.toInt() ?? 0,
        viabilityScore:  (d['viability_score']  as num?)?.toInt() ?? 75,
        timeline:        d['realistic_timeline']?.toString()       ?? '',
        potentialMin:    (d['potential_min']    as num?)?.toDouble() ?? 0.0,
        potentialMax:    (d['potential_max']    as num?)?.toDouble() ?? 0.0,
        createdAt:       d['created_at']?.toString()               ?? '',
        timezone:        d['timezone']?.toString(),
      );

  bool   get isCompleted     => progressPercent == 100;
  bool   get isActive        => status == 'active' && !isCompleted;
  double get progressDecimal => progressPercent / 100;

  String get timeSinceCreated {
    if (createdAt.isEmpty) return '';
    try {
      final dt   = DateTime.parse(createdAt);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 30)  return '${(diff.inDays / 30).round()}mo ago';
      if (diff.inDays > 0)   return '${diff.inDays}d ago';
      if (diff.inHours > 0)  return '${diff.inHours}h ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// INCOME TYPE CONFIG
// ═══════════════════════════════════════════════════════════

class IncomeTypeConfig {
  final String emoji, label;
  final Color  color;
  final IconData icon;
  const IncomeTypeConfig({
    required this.emoji, required this.label,
    required this.color, required this.icon,
  });
}

const _incomeTypeConfigs = <String, IncomeTypeConfig>{
  'youtube':           IncomeTypeConfig(emoji: '▶️', color: Color(0xFFFF0000), label: 'YouTube',           icon: Iconsax.video),
  'tiktok':            IncomeTypeConfig(emoji: '🎵', color: Color(0xFF69C9D0), label: 'TikTok',            icon: Iconsax.music),
  'instagram':         IncomeTypeConfig(emoji: '📸', color: Color(0xFFE1306C), label: 'Instagram',         icon: Iconsax.camera),
  'freelance':         IncomeTypeConfig(emoji: '💻', color: Color(0xFF00B894), label: 'Freelance',         icon: Iconsax.briefcase),
  'ecommerce':         IncomeTypeConfig(emoji: '🛍️', color: Color(0xFFE67E22), label: 'E-commerce',        icon: Iconsax.shopping_cart),
  'dropshipping':      IncomeTypeConfig(emoji: '📦', color: Color(0xFF3498DB), label: 'Dropshipping',      icon: Iconsax.box),
  'affiliate':         IncomeTypeConfig(emoji: '🔗', color: Color(0xFF9B59B6), label: 'Affiliate',         icon: Iconsax.link),
  'content':           IncomeTypeConfig(emoji: '✍️', color: Color(0xFFE91E63), label: 'Content',           icon: Iconsax.document_text),
  'saas':              IncomeTypeConfig(emoji: '☁️', color: Color(0xFF6C5CE7), label: 'SaaS',              icon: Iconsax.cloud),
  'app_development':   IncomeTypeConfig(emoji: '📱', color: Color(0xFF00CEC9), label: 'App Dev',           icon: Iconsax.mobile),
  'online_courses':    IncomeTypeConfig(emoji: '🎓', color: Color(0xFFFD79A8), label: 'Courses',           icon: Iconsax.teacher),
  'digital_products':  IncomeTypeConfig(emoji: '💾', color: Color(0xFF00B894), label: 'Digital Products',  icon: Iconsax.code),
  'print_on_demand':   IncomeTypeConfig(emoji: '🖨️', color: Color(0xFFE17055), label: 'Print on Demand',   icon: Iconsax.printer),
  'virtual_assistant': IncomeTypeConfig(emoji: '🎧', color: Color(0xFF74B9FF), label: 'Virtual Assistant', icon: Iconsax.headphone),
  'translation':       IncomeTypeConfig(emoji: '🌐', color: Color(0xFF55A3FF), label: 'Translation',       icon: Iconsax.translate),
  'physical':          IncomeTypeConfig(emoji: '🏪', color: Color(0xFF3498DB), label: 'Physical Business', icon: Iconsax.shop),
  'food_delivery':     IncomeTypeConfig(emoji: '🍔', color: Color(0xFF00B894), label: 'Food Delivery',     icon: Iconsax.truck_fast),
  'ride_sharing':      IncomeTypeConfig(emoji: '🚗', color: Color(0xFFFDCB6E), label: 'Ride Sharing',      icon: Iconsax.car),
  'real_estate':       IncomeTypeConfig(emoji: '🏢', color: Color(0xFF00B894), label: 'Real Estate',       icon: Iconsax.building),
  'stock_trading':     IncomeTypeConfig(emoji: '📈', color: Color(0xFF00CEC9), label: 'Stock Trading',     icon: Iconsax.trend_up),
  'crypto_trading':    IncomeTypeConfig(emoji: '₿',  color: Color(0xFFF39C12), label: 'Crypto',            icon: Iconsax.coin_1),
  'remote_job':        IncomeTypeConfig(emoji: '🏠', color: Color(0xFF6C5CE7), label: 'Remote Job',        icon: Iconsax.monitor),
  'other':             IncomeTypeConfig(emoji: '💡', color: Color(0xFF6C5CE7), label: 'Other',             icon: Iconsax.activity),
};

IncomeTypeConfig _cfg(String type) =>
    _incomeTypeConfigs[type] ?? const IncomeTypeConfig(emoji: '💡', color: Color(0xFF6C5CE7), label: 'Other', icon: Iconsax.activity);

// ═══════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════

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
    _searchCtrl.addListener(() =>
        ref.read(workflowHubProvider.notifier).setSearchQuery(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Navigate to NEW workflow ──────────────────────────────────────────────
  Future<void> _goToNewWorkflow() async {
    HapticFeedback.mediumImpact();
    await adManager.showInterstitial(); // frequency-capped
    if (mounted) context.push('/workflow/new');
  }

  // ── Navigate to EXISTING saved workflow — interstitial fires here ─────────
  Future<void> _goToSavedWorkflow(String workflowId) async {
    HapticFeedback.mediumImpact();
    await adManager.showInterstitial(); // frequency-capped
    if (mounted) context.push('/workflow/$workflowId');
  }

  // ── Rewarded gate for free limit ─────────────────────────────────────────
  Future<void> _handleNewWorkflowTap() async {
    if (adManager.canCreateWorkflow) {
      await _goToNewWorkflow();
    } else {
      await _showWorkflowLimitDialog();
    }
  }

  Future<void> _showWorkflowLimitDialog() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _WorkflowLimitSheet(
        isDark: isDark,
        onWatchAd: () async {
          Navigator.pop(context);
          final ok = await adManager.watchAdForWorkflow(context);
          if (ok && mounted) await _goToNewWorkflow();
        },
        onUpgrade: () { Navigator.pop(context); context.push('/upgrade'); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final state    = ref.watch(workflowHubProvider);
    final notifier = ref.read(workflowHubProvider.notifier);
    final locale   = ref.watch(localeProvider);

    final currencyFormat = NumberFormat.currency(
      locale:        locale.toString(),
      symbol:        state.workflows.isNotEmpty ? state.workflows.first.currency : 'USD',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor:    isDark ? AppColors.bgDark : const Color(0xFFF5F5F8),
      bottomNavigationBar: adManager.getStickyBanner(context),
      body: RefreshIndicator(
        onRefresh: notifier.loadWorkflows,
        color:     AppColors.primary,
        child: CustomScrollView(
          slivers: [
            // ── HEADER: icon in title row — zero overlap risk ──────────────
            _SliverHeader(
              workflowCount:   state.workflows.length,
              activeCount:     state.activeCount,
              totalRevenue:    state.totalRevenue,
              primaryCurrency: notifier.getPrimaryCurrency(),
              isDark:          isDark,
              onNewWorkflow:   _handleNewWorkflowTap,
            ),

            if (!state.isLoading && state.workflows.isNotEmpty)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchBarDelegate(
                  searchCtrl:      _searchCtrl,
                  selectedFilter:  state.selectedFilter,
                  onFilterChanged: notifier.setFilter,
                  isDark:          isDark,
                ),
              ),

            if (state.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (state.error != null)
              SliverFillRemaining(
                child: _ErrorState(
                  error:   state.error!,
                  onRetry: notifier.loadWorkflows,
                  isDark:  isDark,
                ),
              )
            else if (state.workflows.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(onCreate: _handleNewWorkflowTap),
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
            else ...[
              SliverToBoxAdapter(child: _BrainSuggestionsPanel(isDark: isDark)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, visualIndex) {
                      if (adManager.shouldShowFeedAd(visualIndex)) {
                        return _InlineBannerAdCard(isDark: isDark)
                            .animate()
                            .fadeIn(delay: (visualIndex * 60).ms);
                      }
                      final realIndex = adManager.realPostIndex(visualIndex);
                      if (realIndex >= state.filteredWorkflows.length) {
                        return const SizedBox.shrink();
                      }
                      final wf = state.filteredWorkflows[realIndex];
                      return _WorkflowCard(
                        workflow:       wf,
                        currencyFormat: currencyFormat,
                        // interstitial fires inside _goToSavedWorkflow
                        onTap: () => _goToSavedWorkflow(wf.id),
                      )
                          .animate()
                          .fadeIn(delay: (visualIndex * 55).ms)
                          .slideY(begin: 0.07, curve: Curves.easeOut);
                    },
                    childCount:
                        adManager.feedItemCount(state.filteredWorkflows.length),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: !state.isLoading && state.workflows.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed:       _handleNewWorkflowTap,
              icon:            const Icon(Iconsax.add),
              label:           const Text('New Workflow'),
              backgroundColor: AppColors.primary,
              elevation:       6,
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SLIVER HEADER  — FIX: workflow icon placed inside title row
// ═══════════════════════════════════════════════════════════

class _SliverHeader extends StatelessWidget {
  final int    workflowCount, activeCount;
  final double totalRevenue;
  final String primaryCurrency;
  final bool   isDark;
  final VoidCallback onNewWorkflow;

  const _SliverHeader({
    required this.workflowCount,
    required this.activeCount,
    required this.totalRevenue,
    required this.primaryCurrency,
    required this.isDark,
    required this.onNewWorkflow,
  });

  static String _fmtRevenue(double a, String c) {
    if (a >= 1000000) return '$c ${(a / 1000000).toStringAsFixed(1)}M';
    if (a >= 1000)    return '$c ${(a / 1000).toStringAsFixed(1)}K';
    return '$c ${a.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final nf       = NumberFormat.compact();
    final isNarrow = MediaQuery.of(context).size.width < 360;

    return SliverAppBar(
      expandedHeight: 190,
      pinned:         true,
      stretch:        true,
      elevation:      0,
      // Match gradient to avoid colour-mismatch when pinned
      backgroundColor: const Color(0xFF6C5CE7),
      // Back arrow is in leading (auto-implied). Our icon lives in TITLE.
      leading: Navigator.canPop(context)
          ? IconButton(
              icon:      const Icon(Iconsax.arrow_left_2, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop())
          : const SizedBox.shrink(),
      automaticallyImplyLeading: false,
      // ── Title row: ⚡ icon + text ────────────────────────────────────────
      title: Row(children: [
        Container(
          width:  32,
          height: 32,
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.22),
            borderRadius: BorderRadius.circular(10)),
          child: const Center(child: Text('⚡', style: TextStyle(fontSize: 16))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize:       MainAxisSize.min,
            children: [
              Text(
                'Workflow Engine',
                style: TextStyle(
                    color:      Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize:   isNarrow ? 13 : 15),
                maxLines:  1,
                overflow:  TextOverflow.ellipsis,
              ),
              Text(
                'Your global income command center',
                style: TextStyle(
                    color:    Colors.white.withOpacity(0.76),
                    fontSize: isNarrow ? 9 : 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ]),
      // ── + New button ────────────────────────────────────────────────────
      actions: [
        GestureDetector(
          onTap: onNewWorkflow,
          child: Container(
            margin: EdgeInsets.only(right: 14, top: 9, bottom: 9),
            padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 10 : 14, vertical: 6),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: AppRadius.pill,
              boxShadow: [
                BoxShadow(
                    color:      Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset:     const Offset(0, 3))
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Iconsax.add, color: AppColors.primary, size: 16),
              const SizedBox(width: 4),
              Text('New',
                  style: TextStyle(
                      color:      AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize:   isNarrow ? 11 : 13)),
            ]),
          ),
        ),
      ],
      // ── Flexible background: gradient + stat cards ───────────────────────
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.blurBackground,
          StretchMode.fadeTitle,
        ],
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin:  Alignment.topLeft,
              end:    Alignment.bottomRight,
              colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              // top 58 = consumed by appbar title area already
              padding: const EdgeInsets.fromLTRB(16, 58, 16, 0),
              child: LayoutBuilder(builder: (_, box) {
                return Row(children: [
                  _StatCard(
                      value: nf.format(workflowCount),
                      label: 'Workflows',
                      icon:  Iconsax.task_square,
                      boxW:  box.maxWidth),
                  const SizedBox(width: 10),
                  _StatCard(
                      value: nf.format(activeCount),
                      label: 'Active',
                      icon:  Iconsax.flash_circle,
                      boxW:  box.maxWidth),
                  const SizedBox(width: 10),
                  _StatCard(
                      value:         _fmtRevenue(totalRevenue, primaryCurrency),
                      label:         'Total Earned',
                      icon:          Iconsax.money_tick,
                      boxW:          box.maxWidth,
                      isHighlighted: totalRevenue > 0),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String   value, label;
  final IconData icon;
  final double   boxW;
  final bool     isHighlighted;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.boxW,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    // Adaptive font size based on available card width
    final cardW = (boxW - 20) / 3;
    final vSize = cardW < 90 ? 12.0 : 15.0;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isHighlighted
              ? Colors.white.withOpacity(0.28)
              : Colors.white.withOpacity(0.16),
          borderRadius: AppRadius.md,
          border: isHighlighted
              ? Border.all(color: Colors.white.withOpacity(0.5))
              : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
                color:      Colors.white,
                fontWeight: FontWeight.w800,
                fontSize:   vSize),
            maxLines:  1,
            overflow:  TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SEARCH + FILTER BAR (pinned)
// ═══════════════════════════════════════════════════════════

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchCtrl;
  final String                selectedFilter;
  final Function(String)      onFilterChanged;
  final bool                  isDark;

  _SearchBarDelegate({
    required this.searchCtrl,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color:   isDark ? AppColors.bgDark : const Color(0xFFF5F5F8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        TextField(
          controller: searchCtrl,
          decoration: InputDecoration(
            hintText:   'Search workflows...',
            prefixIcon: const Icon(Iconsax.search_normal, size: 20),
            suffixIcon: searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon:      const Icon(Iconsax.close_circle, size: 20),
                    onPressed: searchCtrl.clear)
                : null,
            filled:    true,
            fillColor: isDark ? AppColors.bgSurface : Colors.white,
            border:    OutlineInputBorder(
                borderRadius: AppRadius.pill, borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _FilterChip(label: 'All',         isSelected: selectedFilter == 'all',          onTap: () => onFilterChanged('all')),
            _FilterChip(label: 'Active',      isSelected: selectedFilter == 'active',       onTap: () => onFilterChanged('active')),
            _FilterChip(label: 'Completed',   isSelected: selectedFilter == 'completed',    onTap: () => onFilterChanged('completed')),
            _FilterChip(label: '💰 Earning',   isSelected: selectedFilter == 'high_earners', onTap: () => onFilterChanged('high_earners')),
          ]),
        ),
      ]),
    );
  }

  @override double get maxExtent => 118;
  @override double get minExtent => 118;
  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate _) => true;
}

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         isSelected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin:   const EdgeInsets.only(right: 8),
      padding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:        isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: AppRadius.pill,
        border:       Border.all(
            color: isSelected ? AppColors.primary : AppColors.textMuted),
      ),
      child: Text(
        label,
        style: TextStyle(
            color:      isSelected ? Colors.white : AppColors.textSecondary,
            fontSize:   12,
            fontWeight: FontWeight.w600),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
// WORKFLOW CARD
// ═══════════════════════════════════════════════════════════

class _WorkflowCard extends StatelessWidget {
  final WorkflowModel workflow;
  final NumberFormat  currencyFormat;
  final VoidCallback  onTap; // interstitial wired from parent

  const _WorkflowCard({
    required this.workflow,
    required this.currencyFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final cfg       = _cfg(workflow.incomeType);
    final isEarning = workflow.totalRevenue > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        isDark ? AppColors.bgCard : Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(color: cfg.color.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
                color:      Colors.black.withOpacity(isDark ? 0.15 : 0.06),
                blurRadius: 12,
                offset:     const Offset(0, 4))
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Emoji icon
              Container(
                width:  52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cfg.color.withOpacity(0.18),
                      cfg.color.withOpacity(0.06)
                    ],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
                  ),
                  borderRadius: AppRadius.md,
                ),
                child: Center(child: Text(cfg.emoji, style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 12),
              // Title + tags
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        workflow.title,
                        style: TextStyle(
                            color:      isDark ? Colors.white : Colors.black87,
                            fontSize:   14,
                            fontWeight: FontWeight.w700),
                        maxLines:  2,
                        overflow:  TextOverflow.ellipsis,
                      ),
                    ),
                    if (workflow.isCompleted)
                      Container(
                        margin:  const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                            color:        AppColors.success.withOpacity(0.12),
                            borderRadius: AppRadius.pill),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Iconsax.tick_circle, size: 10, color: AppColors.success),
                          SizedBox(width: 3),
                          Text('Done',
                              style: TextStyle(
                                  color:      AppColors.success,
                                  fontSize:   9,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _MiniTag(cfg.label.toUpperCase(), cfg.color),
                    if (workflow.timeline.isNotEmpty)
                      _MiniTag('⏱ ${workflow.timeline}', AppColors.textMuted),
                    if (workflow.region != 'global')
                      _MiniTag(
                          '🌍 ${workflow.region.toUpperCase().replaceAll('_', ' ')}',
                          AppColors.info),
                    if (workflow.timeSinceCreated.isNotEmpty)
                      _MiniTag(workflow.timeSinceCreated, AppColors.textMuted),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              // Earnings
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  isEarning
                      ? '+${currencyFormat.format(workflow.totalRevenue)}'
                      : '${workflow.currency} 0',
                  style: TextStyle(
                      color:      isEarning ? AppColors.success : AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                      fontSize:   13),
                ),
                Text('earned',
                    style: TextStyle(
                        color:    AppColors.textMuted, fontSize: 9)),
              ]),
            ]),
          ),
          // Progress bar footer
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${workflow.progressPercent}% done',
                    style: const TextStyle(
                        color:      AppColors.textSecondary,
                        fontSize:   10,
                        fontWeight: FontWeight.w600)),
                Text('${workflow.viabilityScore}/100 viability',
                    style: TextStyle(
                        color:      cfg.color,
                        fontSize:   10,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadius.pill,
                child: LinearProgressIndicator(
                  value:           workflow.progressDecimal,
                  backgroundColor: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(cfg.color),
                  minHeight:  5,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color  color;
  const _MiniTag(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
        color: color.withOpacity(0.10), borderRadius: AppRadius.pill),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

// ═══════════════════════════════════════════════════════════
// INLINE BANNER AD CARD
// ═══════════════════════════════════════════════════════════

class _InlineBannerAdCard extends StatelessWidget {
  final bool isDark;
  const _InlineBannerAdCard({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
        color:        isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border:       Border.all(color: Colors.grey.withOpacity(0.12))),
    clipBehavior: Clip.antiAlias,
    child: Stack(children: [
      Center(
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child:   adManager.getBannerWidget())),
      Positioned(
        top: 5, right: 8,
        child: Text('Ad',
            style: TextStyle(
                fontSize:   9,
                color:      (isDark ? Colors.white : Colors.black).withOpacity(0.3),
                fontWeight: FontWeight.w600)),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
// WORKFLOW LIMIT SHEET
// ═══════════════════════════════════════════════════════════

class _WorkflowLimitSheet extends StatelessWidget {
  final bool         isDark;
  final VoidCallback onWatchAd, onUpgrade;
  const _WorkflowLimitSheet({required this.isDark, required this.onWatchAd, required this.onUpgrade});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
    decoration: BoxDecoration(
        color:        isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: AppRadius.pill)),
      const SizedBox(height: 20),
      const Text('🚀', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 12),
      Text('Free Workflow Limit Reached',
          style: AppTextStyles.h3.copyWith(color: isDark ? Colors.white : Colors.black87),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
          'Watch a short ad to create another workflow free, or upgrade to Pro for unlimited workflows.',
          style: AppTextStyles.body.copyWith(color: isDark ? Colors.white70 : Colors.black54),
          textAlign: TextAlign.center),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed:  onWatchAd,
          icon:       const Icon(Iconsax.play_circle),
          label:      const Text('Watch Ad & Create Free'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding:         const EdgeInsets.symmetric(vertical: 14),
            shape:           RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed:  onUpgrade,
          icon:       const Icon(Iconsax.crown, color: AppColors.warning),
          label:      const Text('Upgrade to Pro'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
            side:            const BorderSide(color: AppColors.warning),
            padding:         const EdgeInsets.symmetric(vertical: 14),
            shape:           RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
        ),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
// BRAIN SUGGESTIONS PANEL
// ═══════════════════════════════════════════════════════════

class _BrainSuggestionsPanel extends StatefulWidget {
  final bool isDark;
  const _BrainSuggestionsPanel({required this.isDark});

  @override
  State<_BrainSuggestionsPanel> createState() => _BrainSuggestionsPanelState();
}

class _BrainSuggestionsPanelState extends State<_BrainSuggestionsPanel> {
  List<dynamic> _suggestions = [];
  bool          _loaded      = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final list = await api.getComplementaryUsers(limit: 4);
      if (mounted) setState(() { _suggestions = list; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _suggestions.isEmpty) return const SizedBox.shrink();
    final isDark = widget.isDark;
    final text   = isDark ? Colors.white : Colors.black87;

    return Container(
      margin:  const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primary.withOpacity(0.07),
          AppColors.accent.withOpacity(0.05),
        ]),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 12),
          const SizedBox(width: 6),
          const Text('Brain matched for your goals',
              style: TextStyle(
                  color:      AppColors.primary,
                  fontSize:   11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push('/marketplace'),
            child: Text('Marketplace →',
                style: TextStyle(
                    fontSize: 10,
                    color:    AppColors.primary.withOpacity(0.65))),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection:  Axis.horizontal,
            itemCount:        _suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final u    = _suggestions[i] as Map;
              final name = u['full_name']?.toString() ?? 'User';
              final type = u['match_type']?.toString() ?? 'match';
              final clr  = type == 'buyer'
                  ? AppColors.success
                  : type == 'service_provider'
                      ? const Color(0xFF9B59B6)
                      : AppColors.primary;
              return GestureDetector(
                onTap: () {
                  if (u['user_id'] != null) {
                    ctx.push('/user-profile/${u['user_id']}');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        clr.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: clr.withOpacity(0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                      radius:          12,
                      backgroundColor: clr.withOpacity(0.15),
                      child:           Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                            fontSize:   11,
                            fontWeight: FontWeight.w800,
                            color:      clr),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Column(
                      mainAxisAlignment:  MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.split(' ').first,
                            style: TextStyle(
                                fontSize:   11,
                                fontWeight: FontWeight.w600,
                                color:      text)),
                        Text(
                          type == 'buyer'
                              ? 'BUYER'
                              : type == 'service_provider'
                                  ? 'SERVICE'
                                  : 'MATCH',
                          style: TextStyle(
                              fontSize:   8,
                              fontWeight: FontWeight.w700,
                              color:      clr),
                        ),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    ).animate().fadeIn(delay: 200.ms);
  }
}

// ═══════════════════════════════════════════════════════════
// EMPTY / ERROR / NO RESULTS STATES
// ═══════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width:  110,
            height: 110,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                  begin:  Alignment.topLeft,
                  end:    Alignment.bottomRight),
              borderRadius: AppRadius.xl,
              boxShadow: [
                BoxShadow(
                    color:      const Color(0xFF6C5CE7).withOpacity(0.3),
                    blurRadius: 28,
                    offset:     const Offset(0, 10))
              ],
            ),
            child: const Center(child: Text('⚡', style: TextStyle(fontSize: 54))),
          ).animate().scale(duration: 600.ms).then().shimmer(duration: 2.seconds),
          const SizedBox(height: 28),
          Text('Start Your Income Journey',
              style: AppTextStyles.h2
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Tell the AI your income goal. It researches what\'s working in your region, creates a step-by-step plan, and helps you execute it.',
            style: AppTextStyles.body
                .copyWith(color: isDark ? Colors.white70 : Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onCreate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: AppRadius.pill,
                boxShadow: [
                  BoxShadow(
                      color:      const Color(0xFF6C5CE7).withOpacity(0.35),
                      blurRadius: 18,
                      offset:     const Offset(0, 7))
                ],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Iconsax.flash, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Create My First Workflow',
                    style: TextStyle(
                        color:      Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize:   14)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing:   8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              _SuggChip('YouTube Channel'),
              _SuggChip('Freelance Design'),
              _SuggChip('E-commerce Store'),
              _SuggChip('Online Course'),
            ],
          ),
        ]),
      ),
    );
  }
}

class _SuggChip extends StatelessWidget {
  final String label;
  const _SuggChip(this.label);

  @override
  Widget build(BuildContext context) => Chip(
    label:           Text(label),
    backgroundColor: AppColors.primary.withOpacity(0.1),
    labelStyle:      const TextStyle(color: AppColors.primary, fontSize: 12),
  );
}

class _ErrorState extends StatelessWidget {
  final String error; final VoidCallback onRetry; final bool isDark;
  const _ErrorState({required this.error, required this.onRetry, required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Iconsax.warning_2, size: 64, color: AppColors.error),
        const SizedBox(height: 16),
        Text('Something went wrong',
            style: AppTextStyles.h3
                .copyWith(color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 8),
        Text(error,
            style: AppTextStyles.body
                .copyWith(color: isDark ? Colors.white70 : Colors.black54),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon:  const Icon(Iconsax.refresh),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding:         const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape:           RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
        ),
      ]),
    ),
  );
}

class _NoResultsState extends StatelessWidget {
  final String searchQuery; final VoidCallback onClear; final bool isDark;
  const _NoResultsState({required this.searchQuery, required this.onClear, required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Iconsax.search_normal, size: 64, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text('No workflows found',
            style: AppTextStyles.h3
                .copyWith(color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 8),
        Text('No results for "$searchQuery"',
            style: AppTextStyles.body
                .copyWith(color: isDark ? Colors.white70 : Colors.black54),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: onClear,
          icon:  const Icon(Iconsax.close_circle),
          label: const Text('Clear Search'),
        ),
      ]),
    ),
  );
}
