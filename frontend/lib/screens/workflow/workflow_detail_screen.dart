import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Workflow Detail Screen ────────────────────────────────────────
// The full managed workflow tab — steps, tools, revenue, AI assist
class WorkflowDetailScreen extends StatefulWidget {
  final String workflowId;
  const WorkflowDetailScreen({super.key, required this.workflowId});
  @override
  State<WorkflowDetailScreen> createState() => _WorkflowDetailScreenState();
}

class _WorkflowDetailScreenState extends State<WorkflowDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map _workflow = {};
  List _steps = [];
  List _freeTools = [];
  List _paidTools = [];
  List _revenueLogs = [];
  bool _loading = true;
  double _totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/workflow/${widget.workflowId}');
      setState(() {
        _workflow = data['workflow'] as Map? ?? {};
        _steps = data['steps'] as List? ?? [];
        _freeTools = data['tools']?['free'] as List? ?? [];
        _paidTools = data['tools']?['paid_upgrades'] as List? ?? [];
        _revenueLogs = data['revenue_logs'] as List? ?? [];
        _totalRevenue = (_workflow['total_revenue'] as num?)?.toDouble() ?? 0.0;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStep(String stepId, String status) async {
    await api.patch('/workflow/${widget.workflowId}/step/$stepId', {'status': status});
    _load();
  }

  Future<void> _showLogRevenue() async {
    final amtCtrl = TextEditingController();
    final srcCtrl = TextEditingController();
    final currency = _workflow['currency']?.toString() ?? 'NGN';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogRevenueSheet(
        currency: currency,
        amtCtrl: amtCtrl,
        srcCtrl: srcCtrl,
        onLog: (amt, src) async {
          Navigator.pop(context);
          await api.post('/workflow/${widget.workflowId}/log-revenue', {
            'amount': amt,
            'currency': currency,
            'source': src,
          });
          _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ $currency ${amt.toStringAsFixed(0)} logged!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _aiAssistStep(Map step) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AIAssistSheet(
        workflowId: widget.workflowId,
        stepTitle: step['title']?.toString() ?? '',
        stepDescription: step['description']?.toString() ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeType = _workflow['income_type']?.toString() ?? 'other';
    final currency = _workflow['currency']?.toString() ?? 'NGN';
    final progress = (_workflow['progress_percent'] as num?)?.toInt() ?? 0;

    const typeColors = {
      'youtube': Color(0xFFFF0000), 'freelance': Color(0xFF00B894),
      'ecommerce': Color(0xFFE67E22), 'physical': Color(0xFF3498DB),
      'affiliate': Color(0xFF9B59B6), 'content': Color(0xFFE91E63),
      'service': Color(0xFF1ABC9C), 'other': Color(0xFF6C5CE7),
    };
    final typeColor = typeColors[incomeType] ?? AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: isDark ? AppColors.bgDark : Colors.white,
                  leading: IconButton(
                    icon: const Icon(Iconsax.arrow_left),
                    onPressed: () => context.pop(),
                  ),
                  actions: [
                    if ((_workflow['total_revenue'] ?? 0) > 0)
                      IconButton(
                        icon: const Icon(Iconsax.gallery, color: Colors.white),
                        tooltip: 'Generate Portfolio Case Study',
                        onPressed: () async {
                          final wfId = widget.workflowId;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✨ Generating portfolio case study...'), backgroundColor: AppColors.primary),
                          );
                          try {
                            await api.generatePortfolioFromWorkflow(wfId);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Added to your portfolio!'), backgroundColor: AppColors.success),
                            );
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
                            );
                          }
                        },
                      ),
                    IconButton(
                      icon: const Icon(Iconsax.add_circle),
                      onPressed: _showLogRevenue,
                      tooltip: 'Log Revenue',
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
                          padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _workflow['title']?.toString() ?? 'Workflow',
                                style: AppTextStyles.h2.copyWith(color: Colors.white, fontSize: 20),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _workflow['goal']?.toString() ?? '',
                                style: AppTextStyles.body.copyWith(color: Colors.white.withOpacity(0.8), fontSize: 12),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 16),
                              // Stats row
                              Row(
                                children: [
                                  _headerStat('$currency ${_fmtNum(_totalRevenue)}', 'Earned', AppColors.gold),
                                  const SizedBox(width: 24),
                                  _headerStat('$progress%', 'Progress', Colors.white),
                                  const SizedBox(width: 24),
                                  _headerStat(
                                    '${_steps.where((s) => s['status'] == 'done').length}/${_steps.length}',
                                    'Steps Done', Colors.white,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: AppRadius.pill,
                                child: LinearProgressIndicator(
                                  value: progress / 100,
                                  backgroundColor: Colors.white.withOpacity(0.3),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottom: TabBar(
                    controller: _tabs,
                    indicatorColor: typeColor,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: typeColor,
                    unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    tabs: const [
                      Tab(text: 'Steps'),
                      Tab(text: 'Tools'),
                      Tab(text: 'Revenue'),
                      Tab(text: 'AI Assist'),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabs,
                children: [
                  _StepsTab(steps: _steps, isDark: isDark, onUpdate: _updateStep, onAI: _aiAssistStep),
                  _ToolsTab(freeTools: _freeTools, paidTools: _paidTools, totalRevenue: _totalRevenue, isDark: isDark),
                  _RevenueTab(logs: _revenueLogs, total: _totalRevenue, currency: currency, isDark: isDark, onLog: _showLogRevenue),
                  _AIAssistTab(workflowId: widget.workflowId, steps: _steps, isDark: isDark),
                ],
              ),
            ),
    );
  }

  Widget _headerStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
      ],
    );
  }

  String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}

// ── Steps Tab ─────────────────────────────────────────────────────
class _StepsTab extends StatelessWidget {
  final List steps;
  final bool isDark;
  final Function(String, String) onUpdate;
  final Function(Map) onAI;
  const _StepsTab({required this.steps, required this.isDark, required this.onUpdate, required this.onAI});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Center(child: Text('No steps found'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final step = steps[i] as Map;
        final status = step['status']?.toString() ?? 'pending';
        final isAuto = step['step_type']?.toString() == 'automated';
        final isDone = status == 'done';

        return Container(
          decoration: BoxDecoration(
            color: isDark
                ? (isDone ? AppColors.bgCard : AppColors.bgSurface)
                : (isDone ? const Color(0xFFE8F5E9) : const Color(0xFFF8F8F8)),
            borderRadius: AppRadius.lg,
            border: isDone ? Border.all(color: AppColors.success.withOpacity(0.4)) : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onUpdate(
                  step['id']?.toString() ?? '',
                  isDone ? 'pending' : 'done',
                );
              },
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? AppColors.success : (isDark ? Colors.white30 : Colors.grey.shade400),
                    width: 2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Center(
                        child: Text('${step['order_index'] ?? i + 1}',
                            style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.grey,
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
              ),
            ),
            title: Text(
              step['title']?.toString() ?? '',
              style: AppTextStyles.label.copyWith(
                color: isDone
                    ? AppColors.success
                    : (isDark ? Colors.white : Colors.black87),
                decoration: isDone ? TextDecoration.lineThrough : null,
                fontSize: 13,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step['description']?.toString() ?? '',
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isAuto
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.warning.withOpacity(0.15),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        isAuto ? '🤖 AI' : '👤 You',
                        style: TextStyle(
                          color: isAuto ? AppColors.primary : AppColors.warning,
                          fontSize: 9, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${step['time_minutes'] ?? 30} min',
                        style: AppTextStyles.caption.copyWith(fontSize: 10)),
                  ],
                ),
              ],
            ),
            trailing: isAuto && !isDone
                ? GestureDetector(
                    onTap: () => onAI(step),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                        borderRadius: AppRadius.pill,
                      ),
                      child: const Text('Run AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  )
                : null,
          ),
        ).animate().fadeIn(delay: (i * 60).ms);
      },
    );
  }
}

// ── Tools Tab ─────────────────────────────────────────────────────
class _ToolsTab extends StatelessWidget {
  final List freeTools, paidTools;
  final double totalRevenue;
  final bool isDark;
  const _ToolsTab({required this.freeTools, required this.paidTools, required this.totalRevenue, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Free tools
        if (freeTools.isNotEmpty) ...[
          Row(
            children: [
              const Text('🆓', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Free Tools — Start Right Now',
                  style: AppTextStyles.h4.copyWith(
                      color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          ...freeTools.map((t) => _ToolCard(tool: t as Map, isFree: true, isDark: isDark)),
          const SizedBox(height: 24),
        ],

        // Paid upgrades
        if (paidTools.isNotEmpty) ...[
          Row(
            children: [
              const Text('🚀', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Upgrade When Ready',
                  style: AppTextStyles.h4.copyWith(
                      color: isDark ? Colors.white70 : Colors.black54, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Unlock these paid tools once you start earning',
              style: AppTextStyles.caption),
          const SizedBox(height: 12),
          ...paidTools.map((t) {
            final tool = t as Map;
            final unlockAt = (tool['unlock_at_revenue'] as num?)?.toDouble() ?? 0;
            final unlocked = totalRevenue >= unlockAt;
            return _ToolCard(
              tool: tool,
              isFree: false,
              isDark: isDark,
              unlocked: unlocked,
              unlockAt: unlockAt,
            );
          }),
        ],
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
  const _ToolCard({
    required this.tool, required this.isFree, required this.isDark,
    this.unlocked = true, this.unlockAt,
  });

  @override
  Widget build(BuildContext context) {
    final color = isFree ? AppColors.success : (unlocked ? AppColors.primary : AppColors.textMuted);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5))
            .withOpacity(isFree || unlocked ? 1.0 : 0.6),
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(isFree || unlocked ? 0.25 : 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppRadius.md),
            child: Center(
              child: Icon(
                isFree ? Iconsax.tick_circle : (unlocked ? Iconsax.unlock : Iconsax.lock),
                color: color, size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool['name']?.toString() ?? '',
                    style: AppTextStyles.label.copyWith(
                        color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                Text(tool['purpose']?.toString() ?? '',
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (!isFree && !unlocked && unlockAt != null)
                  Text('Unlock at ${_fmtNum(unlockAt!)} revenue',
                      style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (isFree)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15), borderRadius: AppRadius.pill,
              ),
              child: const Text('FREE', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          if (!isFree)
            Text('\$${tool['cost_monthly'] ?? 0}/mo',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  String _fmtNum(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Revenue Tab ───────────────────────────────────────────────────
class _RevenueTab extends StatelessWidget {
  final List logs;
  final double total;
  final String currency;
  final bool isDark;
  final VoidCallback onLog;
  const _RevenueTab({required this.logs, required this.total, required this.currency, required this.isDark, required this.onLog});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Total
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00B894), Color(0xFF00CEC9)]),
            borderRadius: AppRadius.lg,
          ),
          child: Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 40)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$currency ${_fmtNum(total)}',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    Text('Total earned from this workflow',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: AppRadius.pill,
                  ),
                  child: const Text('+ Log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),

        if (logs.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📊', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('No revenue logged yet',
                      style: AppTextStyles.h4.copyWith(color: isDark ? Colors.white : Colors.black87)),
                  Text('Start executing your workflow and log income here',
                      style: AppTextStyles.caption, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onLog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15), borderRadius: AppRadius.pill,
                      ),
                      child: const Text('Log First Income', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final log = logs[i] as Map;
                final date = DateTime.tryParse(log['created_at']?.toString() ?? '') ?? DateTime.now();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
                    borderRadius: AppRadius.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), shape: BoxShape.circle),
                        child: const Center(child: Text('💸', style: TextStyle(fontSize: 16))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(log['source']?.toString().isNotEmpty == true ? log['source'] : 'Revenue',
                                style: AppTextStyles.label.copyWith(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                            Text('${date.day}/${date.month}/${date.year}',
                                style: AppTextStyles.caption.copyWith(fontSize: 10)),
                          ],
                        ),
                      ),
                      Text('+${log['currency']} ${_fmtNum((log['amount'] as num?)?.toDouble() ?? 0)}',
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── AI Assist Tab ─────────────────────────────────────────────────
class _AIAssistTab extends StatefulWidget {
  final String workflowId;
  final List steps;
  final bool isDark;
  const _AIAssistTab({required this.workflowId, required this.steps, required this.isDark});
  @override
  State<_AIAssistTab> createState() => _AIAssistTabState();
}

class _AIAssistTabState extends State<_AIAssistTab> {
  Map? _selectedStep;
  final _questionCtrl = TextEditingController();
  String _aiOutput = '';
  bool _running = false;

  Future<void> _runAI() async {
    if (_selectedStep == null) return;
    setState(() { _running = true; _aiOutput = ''; });
    try {
      final question = _questionCtrl.text.trim();
      final params = <String, dynamic>{
        'step_title': _selectedStep!['title']?.toString() ?? '',
      };
      if (question.isNotEmpty) params['user_question'] = question;

      final result = await api.post(
        '/workflow/${widget.workflowId}/ai-assist',
        {},
        queryParams: params,
      );
      setState(() => _aiOutput = result['ai_output']?.toString() ?? '');
    } catch (e) {
      setState(() => _aiOutput = 'AI assist failed. Please try again.');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoSteps = widget.steps.where((s) => s['step_type'] == 'automated').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Text('🤖', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pick any step — AI will execute it for you. Get scripts, descriptions, plans — ready to use.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Text('Select a step:', style: AppTextStyles.h4.copyWith(
              color: widget.isDark ? Colors.white : Colors.black87, fontSize: 14)),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8, runSpacing: 8,
            children: widget.steps.map((step) {
              final s = step as Map;
              final selected = _selectedStep?['id'] == s['id'];
              return GestureDetector(
                onTap: () => setState(() => _selectedStep = s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: AppRadius.pill,
                    border: Border.all(color: selected ? AppColors.primary : AppColors.textMuted),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s['step_type'] == 'automated' ? '🤖 ' : '👤 ', style: const TextStyle(fontSize: 10)),
                      Text(s['title']?.toString() ?? '',
                          style: TextStyle(
                              color: selected ? Colors.white : AppColors.textSecondary,
                              fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          if (_selectedStep != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _questionCtrl,
              style: AppTextStyles.body.copyWith(color: widget.isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Optional: Give AI more context (e.g. "My YouTube channel is about budgeting for students")',
                hintStyle: AppTextStyles.caption,
                filled: true,
                fillColor: widget.isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
                border: OutlineInputBorder(borderRadius: AppRadius.lg, borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _running ? null : _runAI,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: _running
                        ? null
                        : const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                    color: _running ? AppColors.bgSurface : null,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_running)
                        const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                      else
                        const Icon(Iconsax.flash, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _running ? 'AI is working...' : 'Execute This Step with AI',
                        style: AppTextStyles.label.copyWith(
                          color: _running ? AppColors.textSecondary : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          if (_aiOutput.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('AI Output — Ready to Use', style: AppTextStyles.h4.copyWith(
                color: widget.isDark ? Colors.white : Colors.black87, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
                borderRadius: AppRadius.lg,
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: SelectableText(_aiOutput, style: AppTextStyles.body.copyWith(
                  color: widget.isDark ? AppColors.textPrimary : Colors.black87, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _aiOutput));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Copied to clipboard!'), backgroundColor: AppColors.success),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Iconsax.copy, color: AppColors.primary, size: 14),
                  const SizedBox(width: 4),
                  Text('Copy Output', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ── Log Revenue Sheet ─────────────────────────────────────────────
class _LogRevenueSheet extends StatelessWidget {
  final String currency;
  final TextEditingController amtCtrl, srcCtrl;
  final Function(double, String) onLog;
  const _LogRevenueSheet({
    required this.currency, required this.amtCtrl,
    required this.srcCtrl, required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
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
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: AppRadius.pill))),
          const SizedBox(height: 20),
          Text('Log Revenue', style: AppTextStyles.h3.copyWith(color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text('How much did you earn from this workflow?', style: AppTextStyles.caption),
          const SizedBox(height: 16),
          TextField(
            controller: amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body.copyWith(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              prefixText: '$currency  ',
              hintText: '0.00',
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
              border: OutlineInputBorder(borderRadius: AppRadius.lg, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: srcCtrl,
            style: AppTextStyles.body.copyWith(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Source (e.g. YouTube ads, first client)',
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
              border: OutlineInputBorder(borderRadius: AppRadius.lg, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amtCtrl.text) ?? 0;
                if (amt <= 0) return;
                onLog(amt, srcCtrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
              ),
              child: const Text('Log Income', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI Assist Bottom Sheet ────────────────────────────────────────
class _AIAssistSheet extends StatefulWidget {
  final String workflowId, stepTitle, stepDescription;
  const _AIAssistSheet({required this.workflowId, required this.stepTitle, required this.stepDescription});
  @override
  State<_AIAssistSheet> createState() => _AIAssistSheetState();
}

class _AIAssistSheetState extends State<_AIAssistSheet> {
  bool _running = true;
  String _output = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await api.post(
        '/workflow/${widget.workflowId}/ai-assist',
        {},
        queryParams: {'step_title': widget.stepTitle},
      );
      setState(() { _output = result['ai_output']?.toString() ?? ''; _running = false; });
    } catch (_) {
      setState(() { _output = 'Failed. Try again.'; _running = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: AppRadius.pill))),
          const SizedBox(height: 16),
          Text('🤖 AI: ${widget.stepTitle}', style: AppTextStyles.h4.copyWith(color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 16),
          Expanded(
            child: _running
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : SingleChildScrollView(child: SelectableText(_output, style: AppTextStyles.body.copyWith(
                    color: isDark ? AppColors.textPrimary : Colors.black87))),
          ),
          if (!_running && _output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _output));
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                          borderRadius: AppRadius.pill,
                        ),
                        child: const Center(child: Text('Copy & Use', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
