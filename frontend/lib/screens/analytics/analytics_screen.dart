// frontend/lib/screens/analytics/analytics_screen.dart
// v4.0 — Every widget resolves Theme.of(context) independently. No color drilling.
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Theme helper ──────────────────────────────────────────────────────────
class _T {
  final bool   dark;
  final Color  bg, card, surface, border, text, sub;
  const _T({
    required this.dark,   required this.bg,
    required this.card,   required this.surface,
    required this.border, required this.text,
    required this.sub,
  });
  factory _T.of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return _T(
      dark:    dark,
      bg:      dark ? Colors.black        : Colors.white,
      card:    dark ? AppColors.bgCard    : Colors.white,
      surface: dark ? AppColors.bgSurface : Colors.grey.shade100,
      border:  dark ? AppColors.bgSurface : Colors.grey.shade200,
      text:    dark ? Colors.white        : Colors.black87,
      sub:     dark ? Colors.white54      : Colors.black54,
    );
  }
}

// ── Stage info ────────────────────────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const map = <String, Map<String, dynamic>>{
      'survival':  {'emoji':'🌱','label':'Survival Mode',
        'description':'Focus on immediate income',
        'color':Color(0xFFFF6B35),'target':'First \$500/month'},
      'earning':   {'emoji':'💰','label':'Earning',
        'description':'Building consistent income',
        'color':Color(0xFF43E97B),'target':'First \$2,000/month'},
      'stability': {'emoji':'⚡','label':'Stability',
        'description':'Steady foundation built',
        'color':Color(0xFF4FACFE),'target':'3-month emergency fund'},
      'growing':   {'emoji':'📈','label':'Growing',
        'description':'Expanding income streams',
        'color':Color(0xFF6C63FF),'target':'\$10K/month income'},
      'growth':    {'emoji':'📈','label':'Growing',
        'description':'Expanding income streams',
        'color':Color(0xFF6C63FF),'target':'\$10K/month income'},
      'wealth':    {'emoji':'👑','label':'Wealth Building',
        'description':'Multiplying assets',
        'color':Color(0xFFFFD700),'target':'First \$100K net worth'},
      'legacy':    {'emoji':'🏛️','label':'Legacy',
        'description':'Building lasting impact',
        'color':Color(0xFF9B59B6),'target':'Generational wealth'},
    };
    return map[stage.toLowerCase()] ?? map['survival']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with WidgetsBindingObserver {
  static const _kStats    = 'riseup_analytics_stats_v2';
  static const _kEarnings = 'riseup_analytics_earnings_v2';

  Map  _stats    = {};
  Map  _earnings = {};
  bool _loading    = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentRefresh();
  }

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sStr  = prefs.getString(_kStats);
      final eStr  = prefs.getString(_kEarnings);
      if (sStr != null) {
        final s = Map<String, dynamic>.from(jsonDecode(sStr) as Map);
        if (mounted) setState(() { _stats = s; _loading = false; });
      }
      if (eStr != null) {
        final e = Map<String, dynamic>.from(jsonDecode(eStr) as Map);
        if (mounted) setState(() => _earnings = e);
      }
    } catch (_) {}
  }

  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    await _fetchAndApply();
  }

  Future<void> _fetchAndApply() async {
    try {
      final results = await Future.wait([
        api.getStats(),
        api.getEarnings(),
      ]);
      final stats    = results[0] as Map;
      final earnings = results[1] as Map;
      if (mounted) setState(() {
        _stats      = stats;
        _earnings   = earnings;
        _loading    = false;
        _refreshing = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kStats,    jsonEncode(stats)),
        prefs.setString(_kEarnings, jsonEncode(earnings)),
      ]);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  List<double> _computeWeekly(List<Map> breakdown) {
    final now = DateTime.now();
    final ws  = DateTime(now.year, now.month,
        now.day - (now.weekday - 1));
    final out = List<double>.filled(7, 0.0);
    for (final e in breakdown) {
      final at = e['earned_at'] as String?;
      if (at == null) continue;
      try {
        final d    = DateTime.parse(at).toLocal();
        final day  = DateTime(d.year, d.month, d.day);
        final diff = day.difference(ws).inDays;
        if (diff >= 0 && diff < 7) {
          out[diff] += (e['amount'] as num).toDouble();
        }
      } catch (_) {}
    }
    return out;
  }

  Map<String, double> _computeBySource(List<Map> breakdown) {
    final out = <String, double>{};
    for (final e in breakdown) {
      final src = e['source_type'] as String? ?? 'other';
      out[src] = (out[src] ?? 0) + (e['amount'] as num).toDouble();
    }
    return out;
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _sourceName(String k) {
    const m = {
      'task':'Freelance Tasks','freelance':'Freelance',
      'skill':'Skills / Courses','investment':'Investments',
      'business':'Business','referral':'Referrals','other':'Other',
    };
    return m[k] ?? (k.isNotEmpty ? k[0].toUpperCase()+k.substring(1) : k);
  }

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);

    if (_loading && _stats.isEmpty) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Center(child: CircularProgressIndicator(
            color: AppColors.primary)),
      );
    }

    final profile     = _stats['profile']     as Map? ?? {};
    final tasksData   = _stats['tasks']        as Map? ?? {};
    final skillsData  = _stats['skills']       as Map? ?? {};
    final totalEarned = (_stats['total_earned'] ?? 0.0) as num;
    final currency    = profile['currency']?.toString() ?? '';
    final stage       = profile['stage']?.toString() ?? 'survival';
    final stageInfo   = StageInfo.get(stage);

    final breakdown  = (_earnings['breakdown'] as List?)?.cast<Map>() ?? [];
    final weekly     = _computeWeekly(breakdown);
    final bySource   = _computeBySource(breakdown);
    final hasWeekly  = weekly.any((v) => v > 0);
    final weekMax    = hasWeekly
        ? weekly.reduce((a, b) => a > b ? a : b) * 1.3 : 1.0;

    final sortedSrc = bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSrc     = sortedSrc.take(4).toList();
    final srcTotal   = bySource.values.fold(0.0, (s, v) => s + v);
    const srcColors  = [AppColors.primary, AppColors.accent,
                        AppColors.gold, AppColors.info];

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Analytics', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: t.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.primary.withOpacity(0.5)))),
            ),
          IconButton(
            icon: Icon(Iconsax.refresh, color: t.sub, size: 22),
            onPressed: _fetchAndApply,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAndApply,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stage card
              _StageCard(
                stageInfo:   stageInfo,
                currency:    currency,
                totalEarned: totalEarned.toDouble(),
                fmtFn:       _fmt,
              ).animate().fadeIn(),

              const SizedBox(height: 20),

              // Overview grid
              Text('Overview', style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700, color: t.text)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _StatTile('Tasks Completed',
                      '${tasksData['completed'] ?? 0}',
                      Iconsax.tick_circle, AppColors.success),
                  _StatTile('Active Tasks',
                      '${tasksData['active'] ?? 0}',
                      Iconsax.play_circle, AppColors.accent),
                  _StatTile('Skills Enrolled',
                      '${skillsData['enrolled'] ?? 0}',
                      Iconsax.book, AppColors.primary),
                  _StatTile('Skills Completed',
                      '${skillsData['completed'] ?? 0}',
                      Iconsax.medal, AppColors.gold),
                ],
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 24),

              // Weekly earnings
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Weekly Earnings', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: t.text)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: AppRadius.pill),
                    child: Text(
                      hasWeekly ? 'This week' : 'No data yet',
                      style: TextStyle(fontSize: 11,
                          color: hasWeekly ? AppColors.success : t.sub,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 200,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                decoration: BoxDecoration(
                    color: t.card, borderRadius: AppRadius.lg,
                    border: Border.all(color: t.border)),
                child: hasWeekly
                    ? BarChart(BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: weekMax,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => t.surface,
                            getTooltipItem: (g, gi, rod, ri) =>
                                BarTooltipItem(
                              '${currency.isNotEmpty ? '$currency ' : ''}'
                              '${_fmt(rod.toY)}',
                              TextStyle(fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                const days = ['Mon','Tue','Wed',
                                    'Thu','Fri','Sat','Sun'];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(days[v.toInt() % 7],
                                      style: TextStyle(
                                          fontSize: 10, color: t.sub)),
                                );
                              },
                            ),
                          ),
                          leftTitles:  const AxisTitles(sideTitles:
                              SideTitles(showTitles: false)),
                          topTitles:   const AxisTitles(sideTitles:
                              SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles:
                              SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) =>
                              FlLine(color: t.border, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: weekly.asMap().entries
                            .map((e) => BarChartGroupData(
                              x: e.key,
                              barRods: [BarChartRodData(
                                toY: e.value,
                                gradient: LinearGradient(
                                  colors: e.value > 0
                                      ? [AppColors.primary, AppColors.accent]
                                      : [t.border, t.border],
                                  begin: Alignment.bottomCenter,
                                  end:   Alignment.topCenter,
                                ),
                                width: 24,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              )],
                            )).toList(),
                      ))
                    : Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Iconsax.chart_2, size: 32, color: t.sub),
                          const SizedBox(height: 8),
                          Text('No earnings this week yet.',
                              style: TextStyle(fontSize: 12, color: t.sub)),
                        ])),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 24),

              // Income by source
              Text('Income by Source', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: t.card, borderRadius: AppRadius.lg,
                    border: Border.all(color: t.border)),
                child: bySource.isNotEmpty
                    ? Row(children: [
                        SizedBox(
                          width: 130, height: 130,
                          child: PieChart(PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 40,
                            sections: topSrc.asMap().entries.map((e) {
                              final pct = srcTotal > 0
                                  ? e.value.value / srcTotal * 100 : 0.0;
                              return PieChartSectionData(
                                value: e.value.value,
                                color: srcColors[e.key % srcColors.length],
                                title: '${pct.round()}%',
                                radius: 28,
                                titleStyle: const TextStyle(
                                    fontSize: 10, color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              );
                            }).toList(),
                          )),
                        ),
                        const SizedBox(width: 20),
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: topSrc.asMap().entries.map((e) {
                            final c   = srcColors[e.key % srcColors.length];
                            final pct = srcTotal > 0
                                ? (e.value.value / srcTotal * 100).round() : 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(children: [
                                Container(width: 10, height: 10,
                                    decoration: BoxDecoration(
                                        color: c, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_sourceName(e.value.key),
                                    style: TextStyle(
                                        fontSize: 11, color: t.sub),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                                Text('$pct%', style: TextStyle(
                                    fontSize: 11, color: c,
                                    fontWeight: FontWeight.w700)),
                              ]),
                            );
                          }).toList(),
                        )),
                      ])
                    : Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Iconsax.chart_1, size: 32, color: t.sub),
                          const SizedBox(height: 8),
                          Text('Log earnings to see\nyour income breakdown.',
                              style: TextStyle(
                                  fontSize: 12, color: t.sub),
                              textAlign: TextAlign.center),
                        ])),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────

class _StageCard extends StatelessWidget {
  final Map<String, dynamic> stageInfo;
  final String currency;
  final double totalEarned;
  final String Function(double) fmtFn;
  const _StageCard({
    required this.stageInfo, required this.currency,
    required this.totalEarned, required this.fmtFn,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    final c = stageInfo['color'] as Color;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.card,
        gradient: LinearGradient(
            colors: [c.withOpacity(0.1), t.card]),
        borderRadius: AppRadius.lg,
        border: Border.all(color: c.withOpacity(0.28)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${stageInfo['emoji']}',
                style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stageInfo['label'] as String,
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: c)),
              Text(stageInfo['description'] as String,
                  style: TextStyle(fontSize: 11, color: t.sub)),
            ])),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: AppRadius.pill,
              border: Border.all(color: c.withOpacity(0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Iconsax.flag, size: 11, color: c),
              const SizedBox(width: 5),
              Text('Next: ${stageInfo['target']}',
                  style: TextStyle(fontSize: 11, color: c,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ])),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (currency.isNotEmpty)
            Text(currency, style: TextStyle(
                fontSize: 11, color: t.sub)),
          Text(fmtFn(totalEarned), style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w800,
            color: AppColors.success, letterSpacing: -0.5,
          )),
          Text('total earned',
              style: TextStyle(fontSize: 11, color: t.sub)),
        ]),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    color;
  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.lg,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 22,
                fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: t.sub),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
