import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});
  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  Map _data = {};
  bool _loading = true;
  bool _checkingIn = false;
  List<String> _newAchievements = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getStreak();
      setState(() { _data = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _checkIn() async {
    setState(() => _checkingIn = true);
    try {
      final result = await api.checkIn();
      final achievements = (result['achievements_unlocked'] as List? ?? [])
          .where((a) => a != null)
          .map((a) => '${a['icon'] ?? '🏆'} ${a['title'] ?? ''}')
          .toList();

      await _load();
      setState(() {
        _checkingIn = false;
        _newAchievements = List<String>.from(achievements);
      });

      if (!mounted) return;
      final alreadyDone = result['already_checked_in'] == true;

      if (!alreadyDone) {
        // Show success overlay
        _showCheckInSuccess(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already checked in today! See you tomorrow 💪'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (_) {
      setState(() => _checkingIn = false);
    }
  }

  void _showCheckInSuccess(Map result) {
    final streak = result['current_streak'] ?? 0;
    final xp     = result['xp_earned'] ?? 10;
    final record = result['is_new_record'] == true;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔥', style: TextStyle(fontSize: 64))
                .animate().scale(begin: const Offset(0.5,0.5), duration: 500.ms, curve: Curves.elasticOut),
            const SizedBox(height: 16),
            Text(record ? '🎉 NEW RECORD!' : 'Check-In Complete!',
                style: AppTextStyles.h2.copyWith(color: AppColors.gold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '$streak-day streak! Keep it up!',
              style: AppTextStyles.h3, textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: AppRadius.pill,
              ),
              child: Text('+$xp XP earned',
                  style: AppTextStyles.h4.copyWith(color: AppColors.primary)),
            ),
            if (_newAchievements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Achievements Unlocked!', style: AppTextStyles.label),
              ..._newAchievements.map((a) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(a, style: AppTextStyles.body.copyWith(color: AppColors.gold)),
              )),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Let\'s Go! 🚀'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streak     = (_data['current_streak']  ?? 0) as int;
    final longest    = (_data['longest_streak']  ?? 0) as int;
    final totalCi    = (_data['total_check_ins'] ?? 0) as int;
    final xp         = (_data['xp_points']       ?? 0) as int;
    final level      = (_data['level']            ?? 1) as int;
    final xpToNext   = (_data['xp_to_next_level'] ?? 500) as int;
    final checkedToday = _data['checked_in_today'] == true;
    final recentDates  = (_data['recent_dates']   as List? ?? []).cast<String>();
    final xpInLevel    = xp % 500;
    final progress     = xpInLevel / 500.0;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Daily Streak', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Fire counter ──────────────────────────
                  _StreakHero(
                    streak: streak, checkedToday: checkedToday,
                    onCheckIn: _checkIn, checkingIn: _checkingIn,
                  ),
                  const SizedBox(height: 20),

                  // ── XP Level bar ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard, borderRadius: AppRadius.xl,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Level $level', style: AppTextStyles.h3.copyWith(color: AppColors.gold)),
                        Text('$xp XP total', style: AppTextStyles.bodySmall),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: AppColors.bgSurface,
                          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$xpToNext XP to Level ${level + 1}',
                          style: AppTextStyles.caption),
                    ]),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 16),

                  // ── Stats row ─────────────────────────────
                  Row(children: [
                    Expanded(child: _StatCard('🔥', 'Current', '$streak days',
                        color: AppColors.warning)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard('🏆', 'Best', '$longest days',
                        color: AppColors.gold)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard('✅', 'Total', '$totalCi days',
                        color: AppColors.success)),
                  ]),

                  const SizedBox(height: 20),

                  // ── 30-day calendar grid ──────────────────
                  Text('Last 30 Days', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  _CalendarGrid(recentDates: recentDates),

                  const SizedBox(height: 24),

                  // ── Streak milestones ─────────────────────
                  Text('Streak Milestones', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  ...[
                    (3,   '3-Day Streak',  '🔥', 30,   'streak_3'),
                    (7,   'Week Warrior',  '⚡', 100,  'streak_7'),
                    (14,  '2-Week Champ',  '🏅', 200,  'streak_14'),
                    (30,  'Iron Discipline','🏆', 500,  'streak_30'),
                    (100, 'Centurion',     '💎', 1000, 'streak_100'),
                  ].map((m) => _MilestoneRow(
                    days: m.$1, label: m.$2, icon: m.$3,
                    xp: m.$4, current: streak,
                  )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _StreakHero extends StatelessWidget {
  final int streak;
  final bool checkedToday, checkingIn;
  final VoidCallback onCheckIn;
  const _StreakHero({
    required this.streak, required this.checkedToday,
    required this.onCheckIn, required this.checkingIn,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: checkedToday
            ? [const Color(0xFF00B894), const Color(0xFF00787A)]
            : [const Color(0xFF2D1B69), const Color(0xFF4A3ABF)],
      ),
      borderRadius: AppRadius.xl,
      boxShadow: AppShadows.glow,
    ),
    child: Column(children: [
      Text(
        streak == 0 ? '😴' : '🔥',
        style: const TextStyle(fontSize: 64),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(0.95,0.95), end: const Offset(1.05,1.05), duration: 1500.ms),
      const SizedBox(height: 12),
      Text(
        '$streak',
        style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: Colors.white),
      ),
      Text('day${streak == 1 ? '' : 's'} streak',
          style: AppTextStyles.h3.copyWith(color: Colors.white70)),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: checkedToday || checkingIn ? null : onCheckIn,
          style: ElevatedButton.styleFrom(
            backgroundColor: checkedToday ? Colors.white24 : Colors.white,
            foregroundColor: checkedToday ? Colors.white : AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
          ),
          child: checkingIn
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : Text(
                  checkedToday ? '✅ Checked in today!' : '🔥 Check In Now (+10 XP)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    ]),
  ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95,0.95));
}

class _CalendarGrid extends StatelessWidget {
  final List<String> recentDates;
  const _CalendarGrid({required this.recentDates});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Build last 30 days
    final days = List.generate(30, (i) {
      final d = DateTime.now().subtract(Duration(days: 29 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: 30,
      itemBuilder: (_, i) {
        final day     = days[i];
        final checked = recentDates.contains(day);
        final isToday = day == today;
        return Container(
          decoration: BoxDecoration(
            color: checked
                ? AppColors.warning.withOpacity(0.85)
                : isToday
                    ? AppColors.primary.withOpacity(0.3)
                    : AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday ? AppColors.primary : Colors.transparent,
            ),
          ),
          child: Center(
            child: checked
                ? const Text('🔥', style: TextStyle(fontSize: 14))
                : Text(
                    day.substring(8), // DD
                    style: AppTextStyles.caption.copyWith(
                      color: isToday ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon, label, value;
  final Color color;
  const _StatCard(this.icon, this.label, this.value, {required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1), borderRadius: AppRadius.lg,
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 22)),
      const SizedBox(height: 4),
      Text(value, style: AppTextStyles.h4.copyWith(color: color)),
      Text(label, style: AppTextStyles.caption),
    ]),
  );
}

class _MilestoneRow extends StatelessWidget {
  final int days, xp, current;
  final String label, icon;
  const _MilestoneRow({
    required this.days, required this.label, required this.icon,
    required this.xp, required this.current,
  });
  @override
  Widget build(BuildContext context) {
    final reached = current >= days;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: reached ? AppColors.bgCard : AppColors.bgSurface,
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: reached ? AppColors.gold.withOpacity(0.4) : Colors.transparent,
        ),
      ),
      child: Row(children: [
        Text(reached ? icon : '🔒', style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTextStyles.h4.copyWith(
            color: reached ? AppColors.textPrimary : AppColors.textMuted,
          )),
          Text('$days-day streak · +$xp XP', style: AppTextStyles.caption),
        ])),
        if (reached)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: AppRadius.pill,
            ),
            child: Text('Earned!', style: AppTextStyles.caption.copyWith(color: AppColors.gold)),
          )
        else
          Text('${days - current}d away', style: AppTextStyles.caption),
      ]),
    );
  }
}
