import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map _stats = {};
  Map _earnings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await api.getStats();
      final earnings = await api.getEarnings();
      setState(() {
        _stats = stats;
        _earnings = earnings;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));

    final profile = _stats['profile'] as Map? ?? {};
    final tasksData = _stats['tasks'] as Map? ?? {};
    final skillsData = _stats['skills'] as Map? ?? {};
    final totalEarned = (_stats['total_earned'] ?? 0.0) as num;
    final currency = profile['currency']?.toString() ?? 'NGN';
    final stage = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);

    // Sample weekly earnings for chart (replace with real data)
    final weeklyData = [12000.0, 18500.0, 9000.0, 25000.0, 15000.0, 31000.0, 22000.0];

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Analytics', style: AppTextStyles.h3),
        actions: [
          IconButton(icon: const Icon(Iconsax.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stage progress card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    (stageInfo['color'] as Color).withOpacity(0.2),
                    AppColors.bgCard,
                  ]),
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: (stageInfo['color'] as Color).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${stageInfo['emoji']}', style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stageInfo['label'] as String, style: AppTextStyles.h4.copyWith(color: stageInfo['color'] as Color)),
                            Text(stageInfo['description'] as String, style: AppTextStyles.caption),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          '$currency ${_formatNum(totalEarned.toDouble())}',
                          style: AppTextStyles.h3.copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Next milestone: ${stageInfo['target']}', style: AppTextStyles.caption.copyWith(color: (stageInfo['color'] as Color))),
                  ],
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 20),

              // Quick stats grid
              Text('Overview', style: AppTextStyles.h4),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _StatTile('Tasks Completed', '${tasksData['completed'] ?? 0}', Iconsax.tick_circle, AppColors.success),
                  _StatTile('Active Tasks', '${tasksData['active'] ?? 0}', Iconsax.play_circle, AppColors.accent),
                  _StatTile('Skills Enrolled', '${skillsData['enrolled'] ?? 0}', Iconsax.book, AppColors.primary),
                  _StatTile('Skills Completed', '${skillsData['completed'] ?? 0}', Iconsax.medal, AppColors.gold),
                ],
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 24),

              // Earnings chart
              Text('Weekly Earnings', style: AppTextStyles.h4),
              const SizedBox(height: 6),
              Text('Last 7 days (sample)', style: AppTextStyles.caption),
              const SizedBox(height: 14),
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: weeklyData.reduce((a, b) => a > b ? a : b) * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: AppColors.bgSurface,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                          '₦${_formatNum(rod.toY)}',
                          AppTextStyles.caption.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            return Text(days[v.toInt() % 7], style: AppTextStyles.caption);
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: AppColors.bgSurface, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: weeklyData.asMap().entries.map((e) => BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 24,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ],
                    )).toList(),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 24),

              // Income breakdown donut
              Text('Income by Source', style: AppTextStyles.h4),
              const SizedBox(height: 12),
              Container(
                height: 180,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 45,
                          sections: [
                            PieChartSectionData(value: 45, color: AppColors.primary, title: '45%', radius: 30, titleStyle: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                            PieChartSectionData(value: 30, color: AppColors.accent, title: '30%', radius: 30, titleStyle: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                            PieChartSectionData(value: 25, color: AppColors.gold, title: '25%', radius: 30, titleStyle: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendItem('Freelance Tasks', AppColors.primary),
                          const SizedBox(height: 10),
                          _LegendItem('Skills / Courses', AppColors.accent),
                          const SizedBox(height: 10),
                          _LegendItem('Other Income', AppColors.gold),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const Spacer(),
              Text(value, style: AppTextStyles.h3.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTextStyles.caption)),
      ],
    );
  }
}
