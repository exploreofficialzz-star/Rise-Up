import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class IncomeMemoryScreen extends StatefulWidget {
  const IncomeMemoryScreen({super.key});
  @override
  State<IncomeMemoryScreen> createState() => _IncomeMemoryScreenState();
}

class _IncomeMemoryScreenState extends State<IncomeMemoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map _profile = {};
  Map _insights = {};
  Map _patterns = {};
  bool _loading = true;
  bool _loadingInsights = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/memory/profile'),
        api.get('/memory/streak-patterns'),
      ]);
      if (mounted) setState(() {
        _profile  = (results[0] as Map?) ?? {};
        _patterns = (results[1] as Map?) ?? {};
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInsights() async {
    setState(() => _loadingInsights = true);
    try {
      final data = await api.get('/memory/insights');
      if (mounted) setState(() {
        _insights = (data as Map?) ?? {};
        _loadingInsights = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingInsights = false);
    }
  }

  Future<void> _logEvent(String type, String title, double amount) async {
    await api.post('/memory/event', {
      'event_type': type,
      'title': title,
      'amount_usd': amount,
      'outcome': 'success',
    });
    _load();
  }

  void _showLogEventSheet() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedType = 'task_completed';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final types = [
      ('task_completed',  '✅', 'Task Completed'),
      ('income_earned',   '💰', 'Income Earned'),
      ('client_won',      '🤝', 'Client Won'),
      ('skill_learned',   '📚', 'Skill Learned'),
      ('obstacle_hit',    '⚠️', 'Obstacle Hit'),
    ];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) =>
        Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Log Income Event', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: types.map((t) => GestureDetector(
                  onTap: () => setS(() => selectedType = t.$1),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selectedType == t.$1 ? AppColors.primary : Colors.transparent,
                      borderRadius: AppRadius.pill,
                      border: Border.all(color: selectedType == t.$1
                          ? AppColors.primary : (isDark ? Colors.white24 : Colors.grey.shade300)),
                    ),
                    child: Text('${t.$2} ${t.$3}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: selectedType == t.$1 ? Colors.white : (isDark ? Colors.white : Colors.black87))),
                  ),
                )).toList()),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'What happened? (e.g. Completed logo for client)',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                  filled: true, fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl, keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Amount earned \$USD (0 if none)',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                  filled: true, fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;
                    Navigator.pop(context);
                    await _logEvent(selectedType, titleCtrl.text, double.tryParse(amountCtrl.text) ?? 0);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Event recorded to memory!'), backgroundColor: AppColors.success));
                  },
                  child: const Text('Record Event', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg   = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: text), onPressed: () => context.pop()),
        title: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Text('Income Memory', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 26),
              onPressed: _showLogEventSheet),
        ],
        bottom: TabBar(
          controller: _tabs, labelColor: AppColors.primary, unselectedLabelColor: sub,
          indicatorColor: AppColors.primary, indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'DNA Profile'), Tab(text: 'AI Insights'), Tab(text: 'Patterns')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(controller: _tabs, children: [
              _buildDNA(isDark, text, sub, card),
              _buildInsights(isDark, text, sub),
              _buildPatterns(isDark, text, sub),
            ]),
    );
  }

  Widget _buildDNA(bool isDark, Color text, Color sub, Color card) {
    if (_profile['has_memory'] != true) {
      return Center(child: Padding(padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
              borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 40)),
          const SizedBox(height: 20),
          Text('No Memory Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          Text('Complete tasks, log earnings, and win clients — your income DNA builds automatically.',
              textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 13, height: 1.5)),
          const SizedBox(height: 24),
          GestureDetector(onTap: _showLogEventSheet,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
              child: const Text('Log First Event', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
        ]),
      ));
    }

    final p = _profile;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Hero stats
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: AppRadius.lg,
        ),
        child: Column(children: [
          Row(children: [
            _dnaStatW('Total Earned', '\$${(p['total_earned_usd'] ?? 0).toString()}', Colors.white),
            _dnaStatW('Events', '${p['total_events'] ?? 0}', Colors.white),
            _dnaStatW('Completion', '${p['completion_rate_pct'] ?? 0}%', Colors.white),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: AppRadius.md),
            child: Row(children: [
              const Text('🧬', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Best Platform: ${p['best_platform'] ?? 'Not enough data yet'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Your Strongest Skill: ${p['best_skill'] ?? 'Keep logging to discover'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
            ]),
          ),
        ]),
      ).animate().fadeIn(),
      const SizedBox(height: 16),

      // Platform breakdown
      if ((p['platform_breakdown'] as Map? ?? {}).isNotEmpty) ...[
        _sectionHead('📊 PLATFORM PERFORMANCE', sub),
        ...(p['platform_breakdown'] as Map).entries.take(5).map((e) {
          final max = (p['platform_breakdown'] as Map).values.reduce((a, b) => a > b ? a : b);
          final pct = (e.value / max).clamp(0.0, 1.0).toDouble();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                borderRadius: AppRadius.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(e.key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                const Spacer(),
                Text('${e.value} events', style: TextStyle(fontSize: 11, color: sub)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct, minHeight: 5,
                    backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary))),
            ]),
          );
        }),
        const SizedBox(height: 16),
      ],

      // Skill breakdown
      if ((p['skill_breakdown'] as Map? ?? {}).isNotEmpty) ...[
        _sectionHead('🎯 SKILL USAGE', sub),
        Wrap(spacing: 8, runSpacing: 8,
          children: (p['skill_breakdown'] as Map).entries.take(6).map((e) {
            final colors = [AppColors.primary, AppColors.accent, AppColors.success,
                            AppColors.gold, AppColors.warning, AppColors.error];
            final idx = (p['skill_breakdown'] as Map).keys.toList().indexOf(e.key) % colors.length;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: colors[idx].withOpacity(0.1), borderRadius: AppRadius.pill,
                  border: Border.all(color: colors[idx].withOpacity(0.3))),
              child: Text('${e.key} · ${e.value}x',
                  style: TextStyle(fontSize: 12, color: colors[idx], fontWeight: FontWeight.w600)),
            );
          }).toList()),
        const SizedBox(height: 16),
      ],

      // Recent events
      if ((p['recent_events'] as List? ?? []).isNotEmpty) ...[
        _sectionHead('🕐 RECENT EVENTS', sub),
        ...(p['recent_events'] as List).take(5).map((e) {
          final ev = e as Map;
          final isSuccess = ev['outcome'] == 'success';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: AppRadius.md,
            ),
            child: Row(children: [
              Text(_eventEmoji(ev['event_type']?.toString() ?? ''), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ev['title']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                if (ev['platform'] != null)
                  Text(ev['platform'].toString(), style: TextStyle(fontSize: 11, color: sub)),
              ])),
              if ((ev['amount_usd'] ?? 0) > 0)
                Text('+\$${ev['amount_usd']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success)),
            ]),
          );
        }),
      ],
      const SizedBox(height: 40),
    ]);
  }

  Widget _buildInsights(bool isDark, Color text, Color sub) {
    final insights = _insights['insights'];
    if (insights == null || _insights.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🧠', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 14),
        Text('AI Income Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        Text('Your AI analyses your income patterns and gives personalized intelligence.',
            textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _loadInsights,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
              borderRadius: AppRadius.pill,
            ),
            child: _loadingInsights
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Unlock My Insights', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ]),
          ),
        ),
        if (_insights['ready'] == false) ...[
          const SizedBox(height: 12),
          Text('Complete at least 3 income events first', style: TextStyle(color: sub, fontSize: 12)),
        ],
      ]));
    }

    final insightsMap = insights as Map? ?? {};
    final insightCards = [
      ('🧬', 'Income Personality', insightsMap['personality_type'], const Color(0xFF6C5CE7)),
      ('⚡', 'Your Superpower', insightsMap['superpower'], AppColors.success),
      ('👁️', 'Blind Spot', insightsMap['blind_spot'], AppColors.warning),
      ('📊', 'Pattern Alert', insightsMap['pattern_alert'], AppColors.accent),
      ('🔑', 'Next Unlock', insightsMap['next_unlock'], AppColors.primary),
      ('🔁', 'Repeat This', insightsMap['past_wins_to_repeat'], AppColors.gold),
      ('🎯', 'This Week Focus', insightsMap['weekly_focus'], const Color(0xFFFF3CAC)),
      ('💪', 'Encouragement', insightsMap['encouragement'], AppColors.success),
    ];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
          borderRadius: AppRadius.lg,
        ),
        child: Row(children: [
          const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI analyzed your income history', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text('${_insights['events_analyzed'] ?? 0} events processed',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
        ]),
      ).animate().fadeIn(),
      const SizedBox(height: 16),
      ...insightCards.where((c) => c.$3 != null && c.$3.toString().isNotEmpty).map((c) =>
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: AppRadius.lg,
            border: Border.all(color: c.$4.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(c.$1, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(c.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: c.$4, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 6),
            Text(c.$3.toString(), style: TextStyle(fontSize: 13, color: text, height: 1.5)),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: insightCards.indexOf(c) * 60)),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _buildPatterns(bool isDark, Color text, Color sub) {
    final patterns = (_patterns['patterns'] as List?) ?? [];
    final bestDay  = _patterns['best_earning_day']?.toString();
    final rec      = _patterns['recommendation']?.toString();

    if (patterns.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('📅', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          Text('No patterns yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 6),
          Text('Log events over several days to see when you earn most.', textAlign: TextAlign.center,
              style: TextStyle(color: sub, fontSize: 13)),
        ]),
      ));
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (rec != null) Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.success.withOpacity(0.25))),
        child: Row(children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(rec, style: TextStyle(fontSize: 13, color: text, height: 1.4))),
        ]),
      ).animate().fadeIn(),
      const SizedBox(height: 16),
      _sectionHead('EARNINGS BY DAY OF WEEK', sub),
      ...patterns.map((p) {
        final day = p as Map;
        final maxEarned = patterns.map((d) => (d as Map)['earned'] ?? 0).reduce((a, b) => a > b ? a : b);
        final pct = maxEarned > 0 ? ((day['earned'] ?? 0) / maxEarned).clamp(0.0, 1.0).toDouble() : 0.0;
        final isBest = day['day'] == bestDay;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isBest ? AppColors.gold.withOpacity(0.08) : (isDark ? AppColors.bgCard : const Color(0xFFF8F8F8)),
            borderRadius: AppRadius.lg,
            border: Border.all(color: isBest ? AppColors.gold.withOpacity(0.4) : Colors.transparent),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(day['day']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: isBest ? AppColors.gold : text)),
              if (isBest) ...[const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: AppRadius.pill),
                  child: const Text('BEST DAY', style: TextStyle(fontSize: 9, color: AppColors.gold, fontWeight: FontWeight.w800)))],
              const Spacer(),
              Text('\$${(day['earned'] ?? 0).toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                      color: isBest ? AppColors.gold : AppColors.success)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct, minHeight: 6,
                  backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(isBest ? AppColors.gold : AppColors.primary))),
            const SizedBox(height: 4),
            Text('${day['completed'] ?? 0} tasks · ${day['count'] ?? 0} events',
                style: TextStyle(fontSize: 11, color: sub)),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: patterns.indexOf(p) * 60));
      }),
      const SizedBox(height: 40),
    ]);
  }

  Widget _dnaStatW(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
    ]),
  );

  Widget _sectionHead(String t, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1)),
  );

  String _eventEmoji(String type) {
    switch (type) {
      case 'task_completed': return '✅';
      case 'income_earned':  return '💰';
      case 'client_won':     return '🤝';
      case 'skill_learned':  return '📚';
      case 'obstacle_hit':   return '⚠️';
      default:               return '📝';
    }
  }
}
