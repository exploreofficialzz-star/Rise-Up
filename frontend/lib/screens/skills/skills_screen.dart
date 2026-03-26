import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';
import '../../services/ad_service.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});
  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _modules = [];
  List _enrollments = [];
  bool _loading = true;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final modulesData = await api.getSkillModules();
      final enrollData = await api.getMyCourses();
      setState(() {
        _modules = modulesData['modules'] as List? ?? [];
        _isPremium = modulesData['is_premium'] ?? false;
        _enrollments = enrollData;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Skills & Courses', style: AppTextStyles.h3),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'All Courses (${_modules.length})'),
            Tab(text: 'My Learning (${_enrollments.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabs,
              children: [
                _ModuleGrid(
                    modules: _modules,
                    isPremium: _isPremium,
                    onRefresh: _load),
                _MyLearning(enrollments: _enrollments, onRefresh: _load),
              ],
            ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  final List modules;
  final bool isPremium;
  final Future<void> Function() onRefresh; // ← Fixed
  const _ModuleGrid(
      {required this.modules,
      required this.isPremium,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final int totalItems = modules.length + (modules.length ~/ 4);
    int moduleIndex = 0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: totalItems,
        itemBuilder: (_, i) {
          if ((i + 1) % 5 == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: BannerAdWidget()),
            );
          }
          if (moduleIndex >= modules.length) return const SizedBox.shrink();
          final idx = moduleIndex++;
          return _ModuleCard(
            module: modules[idx],
            isPremium: isPremium,
            onRefresh: onRefresh,
          )
              .animate()
              .fadeIn(delay: Duration(milliseconds: idx * 60))
              .slideY(begin: 0.1);
        },
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final Map module;
  final bool isPremium;
  final Future<void> Function() onRefresh; // ← Fixed
  const _ModuleCard(
      {required this.module,
      required this.isPremium,
      required this.onRefresh});

  bool get _isLocked => module['is_premium'] == true && !isPremium;

  Color get _categoryColor {
    switch (module['category']) {
      case 'digital_marketing':
        return AppColors.primary;
      case 'design':
        return AppColors.accent;
      case 'writing':
        return AppColors.gold;
      case 'video':
        return AppColors.error;
      case 'digital_products':
        return AppColors.success;
      case 'affiliate_marketing':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _enroll(BuildContext context) async {
    if (_isLocked) {
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.bgCard,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _UnlockModal(
          featureKey: FeatureKeys.premiumSkills,
          onUnlocked: onRefresh,
          onSubscribe: () => context.go('/payment'),
        ),
      );
      return;
    }

    try {
      await api.enrollSkill(module['id']);
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🎉 Enrolled! Start learning to earn more!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/skills/${module['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(
              color: _isLocked
                  ? AppColors.gold.withOpacity(0.2)
                  : AppColors.bgSurface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _categoryColor.withOpacity(0.15),
                    borderRadius: AppRadius.pill),
                child: Text(
                  _formatCategory(module['category']),
                  style: AppTextStyles.caption.copyWith(
                      color: _categoryColor, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (_isLocked)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.15),
                      borderRadius: AppRadius.pill),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium,
                          color: AppColors.gold, size: 12),
                      const SizedBox(width: 4),
                      Text('Premium',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              else
                Text('${module['duration_days']} days',
                    style: AppTextStyles.caption),
            ]),
            const SizedBox(height: 10),
            Text(module['title'] ?? '',
                style: AppTextStyles.h4.copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(module['description'] ?? '',
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.attach_money,
                  color: AppColors.success, size: 14),
              Text(module['income_potential'] ?? '',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.success)),
              const Spacer(),
              Text('${module['difficulty']}',
                  style: AppTextStyles.caption
                      .copyWith(color: _diffColor(module['difficulty']))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _enroll(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isLocked ? AppColors.gold : AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.md),
                ),
                child: Text(
                  _isLocked ? '🔒 Unlock & Enroll' : 'Enroll Now →',
                  style:
                      AppTextStyles.label.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCategory(String cat) => cat
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) =>
          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Color _diffColor(String? d) => d == 'beginner'
      ? AppColors.success
      : d == 'intermediate'
          ? AppColors.warning
          : AppColors.error;
}

class _MyLearning extends StatelessWidget {
  final List enrollments;
  final Future<void> Function() onRefresh; // ← Fixed
  const _MyLearning(
      {required this.enrollments, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (enrollments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.book, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('No courses yet', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text('Enroll in a skill to start earning while learning',
                style: AppTextStyles.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: enrollments.length,
        itemBuilder: (_, i) {
          final e = enrollments[i];
          final module = e['skill_modules'] as Map? ?? {};
          final progress = (e['progress_percent'] ?? 0) / 100.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.bgCard, borderRadius: AppRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(module['title'] ?? '',
                    style: AppTextStyles.h4.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    'Lesson ${e['current_lesson']} of ${(module['lessons'] as List?)?.length ?? '?'}',
                    style: AppTextStyles.bodySmall),
                const SizedBox(height: 12),
                LinearPercentIndicator(
                  lineHeight: 8,
                  percent: progress.clamp(0.0, 1.0),
                  backgroundColor: AppColors.bgSurface,
                  progressColor: progress >= 1.0
                      ? AppColors.success
                      : AppColors.primary,
                  barRadius: const Radius.circular(4),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${(progress * 100).toInt()}% complete',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.primary)),
                    if (e['status'] == 'completed')
                      Text('✅ Completed!',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.success))
                    else
                      Text('Earned: ₦${e['earnings_from_skill'] ?? 0}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.success)),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
        },
      ),
    );
  }
}

class _UnlockModal extends StatelessWidget {
  final String featureKey;
  final VoidCallback onUnlocked;
  final VoidCallback onSubscribe;
  const _UnlockModal(
      {required this.featureKey,
      required this.onUnlocked,
      required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔒', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('Premium Content',
              style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
              'This course requires Premium. Unlock it by watching a short ad or upgrading.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          GradientButton(
            text: '📺 Watch Ad to Unlock (1 hour)',
            onTap: () async {
              Navigator.pop(context);
              await adService.showRewardedAd(
                featureKey: featureKey,
                onRewarded: onUnlocked,
                onDismissed: () {},
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onSubscribe();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text(
                  '👑 Upgrade to Premium · \$15.99/mo',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
