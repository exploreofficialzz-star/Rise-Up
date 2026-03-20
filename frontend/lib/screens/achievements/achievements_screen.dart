import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  Map _data = {};
  bool _loading = true;
  late TabController _tab;

  static const _cats = ['all', 'tasks', 'earnings', 'streak', 'skills', 'community', 'referral', 'milestone'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _cats.length, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final data = await api.getAchievements();
      // Also trigger a background achievement check
      api.checkAchievements().catchError((_) {});
      setState(() { _data = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  List _filtered(String cat) {
    final all = (_data['achievements'] as List? ?? []);
    if (cat == 'all') return all;
    return all.where((a) => a['category'] == cat).toList();
  }

  @override
  Widget build(BuildContext context) {
    final xp       = (_data['xp_points'] ?? 0) as int;
    final level    = (_data['level'] ?? 1) as int;
    final unlocked = (_data['unlocked_count'] ?? 0) as int;
    final total    = (_data['total_count'] ?? 0) as int;
    final xpInLevel = xp % 500;
    final progress  = xpInLevel / 500.0;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Achievements', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _cats.map((c) => Tab(text: c[0].toUpperCase() + c.substring(1))).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // ── XP & Level bar ──────────────────────────
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2D1B69), Color(0xFF1A0E4F)],
                    ),
                    borderRadius: AppRadius.xl,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Level $level', style: AppTextStyles.h2.copyWith(color: AppColors.gold)),
                            Text('$xp XP total', style: AppTextStyles.bodySmall),
                          ]),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.2),
                              borderRadius: AppRadius.pill,
                              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                            ),
                            child: Text('🏆 $unlocked / $total badges',
                                style: AppTextStyles.label.copyWith(color: AppColors.primary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.bgSurface,
                          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$xpInLevel XP', style: AppTextStyles.caption),
                          Text('${500 - xpInLevel} XP to Level ${level + 1}',
                              style: AppTextStyles.caption),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2),

                // ── Achievement grid ─────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: _cats.map((cat) {
                      final items = _filtered(cat);
                      if (items.isEmpty) {
                        return Center(
                          child: Text('No achievements here yet',
                              style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) => _AchievementCard(
                          achievement: items[i],
                          index: i,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Map achievement;
  final int index;
  const _AchievementCard({required this.achievement, required this.index});

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement['unlocked'] == true;
    final isSecret = achievement['is_secret'] == true && !unlocked;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: unlocked ? AppColors.bgCard : AppColors.bgSurface,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: unlocked
                ? AppColors.gold.withOpacity(0.4)
                : AppColors.bgSurface,
            width: unlocked ? 1.5 : 1,
          ),
          boxShadow: unlocked ? [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.15),
              blurRadius: 12, spreadRadius: -2,
            )
          ] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Badge icon
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: unlocked
                    ? AppColors.gold.withOpacity(0.15)
                    : AppColors.bgDark,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isSecret
                    ? const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 24)
                    : Text(
                        achievement['icon'] ?? '🏆',
                        style: TextStyle(
                          fontSize: 28,
                          color: unlocked ? null : Colors.white.withOpacity(0.3),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                isSecret ? '???' : (achievement['title'] ?? ''),
                style: AppTextStyles.caption.copyWith(
                  color: unlocked ? AppColors.textPrimary : AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unlocked ? '✓ Unlocked' : '+${achievement['xp_reward'] ?? 0} XP',
              style: AppTextStyles.caption.copyWith(
                color: unlocked ? AppColors.success : AppColors.textMuted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ).animate(delay: Duration(milliseconds: index * 30)).fadeIn(duration: 300.ms).scale(begin: const Offset(0.85, 0.85)),
    );
  }

  void _showDetail(BuildContext context) {
    final unlocked = achievement['unlocked'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(achievement['icon'] ?? '🏆', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(achievement['title'] ?? '', style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(achievement['description'] ?? '',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: (unlocked ? AppColors.success : AppColors.primary).withOpacity(0.15),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                unlocked
                    ? '✅ Unlocked on ${achievement['unlocked_at']?.toString().split('T')[0] ?? ''}'
                    : '🔒 +${achievement['xp_reward']} XP when unlocked',
                style: AppTextStyles.label.copyWith(
                  color: unlocked ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
