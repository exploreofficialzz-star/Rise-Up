import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Models ────────────────────────────────────────────────────────
class WorkflowModel {
  final String id;
  final String title;
  final String goal;
  final String incomeType;
  final String status;
  final double totalRevenue;
  final String currency;
  final int progressPercent;
  final int viabilityScore;
  final String timeline;
  final double potentialMin;
  final double potentialMax;
  final String createdAt;

  WorkflowModel.fromJson(Map d)
      : id = d['id']?.toString() ?? '',
        title = d['title']?.toString() ?? '',
        goal = d['goal']?.toString() ?? '',
        incomeType = d['income_type']?.toString() ?? 'other',
        status = d['status']?.toString() ?? 'active',
        totalRevenue = (d['total_revenue'] as num?)?.toDouble() ?? 0.0,
        currency = d['currency']?.toString() ?? 'NGN',
        progressPercent = (d['progress_percent'] as num?)?.toInt() ?? 0,
        viabilityScore = (d['viability_score'] as num?)?.toInt() ?? 75,
        timeline = d['realistic_timeline']?.toString() ?? '',
        potentialMin = (d['potential_min'] as num?)?.toDouble() ?? 0.0,
        potentialMax = (d['potential_max'] as num?)?.toDouble() ?? 0.0,
        createdAt = d['created_at']?.toString() ?? '';
}

// ── Income Type Meta ──────────────────────────────────────────────
const _typeIcons = {
  'youtube': '▶️', 'freelance': '💻', 'ecommerce': '🛍️',
  'physical': '🏪', 'affiliate': '🔗', 'content': '✍️',
  'service': '🛠️', 'other': '💡',
};

const _typeColors = {
  'youtube': Color(0xFFFF0000),
  'freelance': Color(0xFF00B894),
  'ecommerce': Color(0xFFE67E22),
  'physical': Color(0xFF3498DB),
  'affiliate': Color(0xFF9B59B6),
  'content': Color(0xFFE91E63),
  'service': Color(0xFF1ABC9C),
  'other': Color(0xFF6C5CE7),
};

// ── Main Workflow Hub Screen ──────────────────────────────────────
class WorkflowHubScreen extends StatefulWidget {
  const WorkflowHubScreen({super.key});
  @override
  State<WorkflowHubScreen> createState() => _WorkflowHubScreenState();
}

class _WorkflowHubScreenState extends State<WorkflowHubScreen> {
  List<WorkflowModel> _workflows = [];
  bool _loading = true;
  double _totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/workflow/');
      final list = (data['workflows'] as List? ?? []);
      setState(() {
        _workflows = list.map((w) => WorkflowModel.fromJson(w)).toList();
        _totalRevenue = _workflows.fold(0.0, (s, w) => s + w.totalRevenue);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : Colors.white;
    final cardBg = isDark ? AppColors.bgCard : const Color(0xFFF8F8F8);

    return Scaffold(
      backgroundColor: bg,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            // ── Header ──────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: bg,
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
                              const Icon(Iconsax.flash, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text('Workflow Engine',
                                  style: AppTextStyles.h3.copyWith(color: Colors.white)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => context.push('/workflow/new'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: AppRadius.pill,
                                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Iconsax.add, color: Colors.white, size: 16),
                                      const SizedBox(width: 4),
                                      Text('New', style: AppTextStyles.label.copyWith(color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _statChip('${_workflows.length}', 'Workflows', Iconsax.task_square),
                              const SizedBox(width: 16),
                              _statChip(
                                _workflows.isEmpty ? '0' : '${_workflows.where((w) => w.status == 'active').length}',
                                'Active', Iconsax.flash_circle,
                              ),
                              const SizedBox(width: 16),
                              _statChip(
                                _totalRevenue > 0
                                    ? '${_workflows.isNotEmpty ? _workflows.first.currency : 'NGN'} ${_fmt(_totalRevenue)}'
                                    : '₦0',
                                'Earned', Iconsax.money_tick,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Empty state ─────────────────────────────────────
            if (!_loading && _workflows.isEmpty)
              SliverFillRemaining(
                child: _EmptyWorkflowState(onTap: () => context.push('/workflow/new')),
              ),

            // ── Loading ─────────────────────────────────────────
            if (_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _shimmerCard(cardBg),
                  childCount: 3,
                ),
              ),

            // ── Workflow Cards ───────────────────────────────────
            if (!_loading && _workflows.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Text('Your Income Workflows',
                      style: AppTextStyles.h4.copyWith(
                          color: isDark ? AppColors.textPrimary : Colors.black87)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _WorkflowCard(
                      workflow: _workflows[i],
                      onTap: () => context.push('/workflow/${_workflows[i].id}'),
                    ).animate().fadeIn(delay: (i * 80).ms).slideY(begin: 0.2, end: 0),
                    childCount: _workflows.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statChip(String value, String label, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _shimmerCard(Color bg) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      height: 120,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.lg),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Workflow Card ─────────────────────────────────────────────────
class _WorkflowCard extends StatelessWidget {
  final WorkflowModel workflow;
  final VoidCallback onTap;
  const _WorkflowCard({required this.workflow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.bgCard : const Color(0xFFF8F8F8);
    final typeColor = _typeColors[workflow.incomeType] ?? AppColors.primary;
    final emoji = _typeIcons[workflow.incomeType] ?? '💡';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: AppRadius.lg,
          border: Border.all(color: typeColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.15),
                    borderRadius: AppRadius.md,
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workflow.title,
                          style: AppTextStyles.h4.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.15),
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(workflow.incomeType.toUpperCase(),
                                style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Text(workflow.timeline,
                              style: AppTextStyles.caption.copyWith(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${workflow.currency} ${_fmtNum(workflow.totalRevenue)}',
                        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('earned', style: AppTextStyles.caption),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: workflow.progressPercent / 100,
                      backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(typeColor),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${workflow.progressPercent}%',
                    style: TextStyle(color: typeColor, fontWeight: FontWeight.w600, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Empty State ───────────────────────────────────────────────────
class _EmptyWorkflowState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyWorkflowState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: AppRadius.xl,
              ),
              child: const Center(child: Text('⚡', style: TextStyle(fontSize: 48))),
            ).animate().scale(),
            const SizedBox(height: 24),
            Text('No Workflows Yet',
                style: AppTextStyles.h3.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            Text(
              'Tell the AI your income goal.\nIt will research, plan, and execute the work with you.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Iconsax.flash, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Create My First Workflow',
                        style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
