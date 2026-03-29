// frontend/lib/screens/skills/skills_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../config/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';

class SkillsScreen extends ConsumerStatefulWidget {
  const SkillsScreen({super.key});

  @override
  ConsumerState<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends ConsumerState<SkillsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<dynamic> _enrollments = [];
  List<dynamic> _discoverSkills = [];
  Map<String, dynamic> _limits = {};
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final myData = await api.get('/skills/my-courses');
      final discoverData = await api.get('/skills/discover');
      
      if (mounted) {
        setState(() {
          _enrollments = myData['enrollments'] as List? ?? [];
          _limits = myData['limits'] as Map<String, dynamic>? ?? {};
          _discoverSkills = discoverData['recommended_for_you'] as List? ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateSkillPath() async {
    final canEnroll = _limits['can_enroll_more'] ?? false;
    final remainingFree = _limits['remaining_free_slots'] ?? 0;
    
    if (!canEnroll && remainingFree <= 0) {
      _showLimitDialog();
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GenerateSkillSheet(),
    );

    if (result == null) return;

    setState(() => _generating = true);
    HapticFeedback.mediumImpact();

    try {
      final response = await api.post('/skills/generate-path', {
        'skill_name': result['skill'],
        'current_level': result['level'],
        'goal_description': result['goal'],
        'time_available_hours_week': result['hours'],
        'preferred_learning_style': result['style'],
      });

      if (mounted) {
        final preview = await _showSkillPreview(
          response['preview_id'],
          response['skill_path'],
          response['enrollment_status'],
        );
        
        if (preview == true) {
          await _enrollSkill(response['preview_id']);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<bool?> _showSkillPreview(
    String previewId,
    Map<String, dynamic> skillPath,
    Map<String, dynamic> status,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final curriculum = skillPath['curriculum'] as List? ?? [];
    final firstModule = curriculum.isNotEmpty ? curriculum[0] : null;
    final firstLesson = firstModule?['lessons']?.isNotEmpty == true 
        ? firstModule['lessons'][0] 
        : null;

    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.24) : Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Iconsax.book_1, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-Generated Path',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        skillPath['title'] ?? '',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Iconsax.wallet_3, color: AppColors.success, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Income Potential',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${skillPath['average_income_potential']?['monthly_usd'] ?? '?'}/month USD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.success,
                          ),
                        ),
                        if (skillPath['average_income_potential']?['local_monthly_estimate'] != null)
                          Text(
                            '≈ ${skillPath['average_income_potential']['local_monthly_estimate']} ${_limits['currency'] ?? 'USD'} locally',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statBox(
                  icon: Iconsax.clock,
                  value: '${skillPath['estimated_time_to_first_earning_days'] ?? '?'} days',
                  label: 'To first \$',
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _statBox(
                  icon: Iconsax.chart,
                  value: skillPath['success_probability'] ?? '70%',
                  label: 'Success rate',
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _statBox(
                  icon: Iconsax.book,
                  value: '${curriculum.length} modules',
                  label: 'Curriculum',
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (firstLesson != null) ...[
              Text(
                'Your First Lesson',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstLesson['title'] ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      firstLesson['description'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Iconsax.timer_1, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${firstLesson['time_minutes'] ?? 30} mins',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Iconsax.video, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          firstLesson['type'] ?? 'video',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            if (!(status['can_enroll_free'] ?? false)) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Iconsax.info_circle, color: AppColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status['requires_action'] == 'ad'
                            ? 'Watch an ad to unlock this skill (${status['ad_unlocks_remaining']} remaining)'
                            : 'Upgrade to Premium for unlimited skills',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (status['can_enroll_free'] ?? false)
                    ? () => Navigator.pop(context, true)
                    : () {
                        Navigator.pop(context);
                        if (status['requires_action'] == 'ad') {
                          _watchAdToEnroll(previewId);
                        } else {
                          context.push('/premium');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (status['can_enroll_free'] ?? false)
                      ? AppColors.primary
                      : AppColors.warning,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  (status['can_enroll_free'] ?? false)
                      ? 'Enroll Now 🚀'
                      : (status['requires_action'] == 'ad' ? 'Watch Ad to Enroll 📺' : 'Upgrade to Premium 👑'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox({
    required IconData icon,
    required String value,
    required String label,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _watchAdToEnroll(String previewId) async {
    final ok = await adManager.watchAdForSkill(context);
    if (ok && mounted) {
      await _enrollSkill(previewId, useAdUnlock: true);
    }
  }

  Future<void> _enrollSkill(String previewId, {bool useAdUnlock = false}) async {
    try {
      final response = await api.post('/skills/enroll', {
        'skill_path_id': previewId,
        'use_ad_unlock': useAdUnlock,
      });

      if (response['enrolled'] == true) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎓 ${response['message'] ?? 'Enrolled!'}'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        _showLimitDialogFromResponse(response);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.lock_1, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Skill Limit Reached',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Free users can enroll in 3 skills. Watch ads to unlock more, or upgrade to Premium for unlimited access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      adManager.watchAdForSkill(context).then((ok) {
                        if (ok && mounted) _generateSkillPath();
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Watch Ad',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/premium');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLimitDialogFromResponse(Map<String, dynamic> response) {
    final options = response['options'] as Map<String, dynamic>? ?? {};
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LimitOptionsSheet(
        canWatchAd: options['watch_ad'] ?? false,
        adUnlocksRemaining: options['ad_unlocks_remaining'] ?? 0,
        onWatchAd: () {
          Navigator.pop(context);
        },
        onUpgrade: () {
          Navigator.pop(context);
          context.push('/premium');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Iconsax.book, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'Skills',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: text,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'My Learning (${_enrollments.length})'),
            Tab(text: 'Discover'),
          ],
        ),
        actions: [
          if (!(_limits['is_premium'] ?? false))
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (_limits['remaining_free_slots'] ?? 0) > 0
                    ? AppColors.success.withOpacity(0.12)
                    : AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_limits['remaining_free_slots'] ?? 0}/3',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: (_limits['remaining_free_slots'] ?? 0) > 0
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabs,
              children: [
                _MyLearningTab(
                  enrollments: _enrollments,
                  onRefresh: _load,
                  onContinue: (enrollment) => _showLessonScreen(enrollment),
                ),
                _DiscoverTab(
                  recommendations: _discoverSkills,
                  onGenerateSkill: _generateSkillPath,
                  limits: _limits,
                ),
              ],
            ),
      floatingActionButton: _generating
          ? const FloatingActionButton(
              onPressed: null,
              backgroundColor: Colors.grey,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : FloatingActionButton.extended(
              onPressed: _generateSkillPath,
              backgroundColor: AppColors.primary,
              icon: const Icon(Iconsax.magicpen, color: Colors.white),
              label: const Text(
                'AI Generate Skill',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  void _showLessonScreen(Map<String, dynamic> enrollment) {
    context.push('/skills/lesson', extra: enrollment);
  }
}

class _MyLearningTab extends StatelessWidget {
  final List<dynamic> enrollments;
  final Future<void> Function() onRefresh;
  final Function(Map<String, dynamic>) onContinue;

  const _MyLearningTab({
    required this.enrollments,
    required this.onRefresh,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (enrollments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.book_1, size: 64, color: isDark ? Colors.white24 : Colors.black12),
            const SizedBox(height: 16),
            Text(
              'No skills yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Generate your first AI-powered skill path',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
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
          final progress = (e['progress_percent'] ?? 0) / 100.0;
          final isCompleted = e['status'] == 'completed';

          return GestureDetector(
            onTap: () => onContinue(e),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCompleted 
                      ? AppColors.success.withOpacity(0.3)
                      : AppColors.primary.withOpacity(0.1),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCompleted
                                ? [AppColors.success, AppColors.success.withOpacity(0.8)]
                                : [AppColors.primary, AppColors.accent],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isCompleted ? Iconsax.tick_circle : Iconsax.book,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e['skill_name'] ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isCompleted
                                  ? '✅ Completed'
                                  : 'Module ${e['current_module']} of ${e['total_modules']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCompleted ? AppColors.success : (isDark ? Colors.white54 : Colors.black45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (e['earnings_from_skill'] != null && e['earnings_from_skill'] > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '\$${e['earnings_from_skill'].toStringAsFixed(0)} earned',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        isCompleted ? AppColors.success : AppColors.primary,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(progress * 100).toInt()}% complete',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${e['streak_days'] ?? 0} day streak 🔥',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fade(delay: (i * 60).ms), // FIXED: proper closing parenthesis
          );
        },
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  final List<dynamic> recommendations;
  final VoidCallback onGenerateSkill;
  final Map<String, dynamic> limits;

  const _DiscoverTab({
    required this.recommendations,
    required this.onGenerateSkill,
    required this.limits,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GestureDetector(
          onTap: onGenerateSkill,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Iconsax.magicpen, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    if (!(limits['is_premium'] ?? false))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${limits['remaining_free_slots'] ?? 0} free left',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Generate AI Skill Path',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us what you want to learn. AI creates a personalized curriculum with global resources.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Iconsax.arrow_right_3, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to start',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
        
        const SizedBox(height: 24),
        
        if (recommendations.isNotEmpty) ...[
          Text(
            'Recommended for You',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          ...recommendations.asMap().entries.map((entry) {
            final rec = entry.value as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Iconsax.flash, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec['skill'] ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rec['reason'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Iconsax.arrow_right_3, color: isDark ? Colors.white38 : Colors.black38),
                ],
              ),
            ).animate().fadeIn(delay: (entry.key * 80).ms);
          }),
        ],
      ],
    );
  }
}

class _GenerateSkillSheet extends StatefulWidget {
  const _GenerateSkillSheet();

  @override
  State<_GenerateSkillSheet> createState() => _GenerateSkillSheetState();
}

class _GenerateSkillSheetState extends State<_GenerateSkillSheet> {
  final _skillCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  String _level = 'beginner';
  int _hoursPerWeek = 5;
  String? _learningStyle;

  @override
  void dispose() {
    _skillCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.24) : Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'What do you want to learn?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AI will create a personalized earning-focused curriculum',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _skillCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'e.g., Web Development, Graphic Design, Copywriting',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white.withOpacity(0.38) : Colors.black.withOpacity(0.38),
                ),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _goalCtrl,
              maxLines: 2,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'What do you want to achieve? (optional)',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white.withOpacity(0.38) : Colors.black.withOpacity(0.38),
                ),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Current Level',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: ['beginner', 'intermediate', 'advanced'].map((level) {
                final isSelected = _level == level;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _level = level),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        level[0].toUpperCase() + level.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black.withOpacity(0.7)), // FIXED: was Colors.black70
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hours per week',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _hoursPerWeek,
                            isExpanded: true,
                            dropdownColor: isDark ? AppColors.bgCard : Colors.white,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            items: [3, 5, 10, 15, 20, 40].map((h) {
                              return DropdownMenuItem(
                                value: h,
                                child: Text('$h hours'),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _hoursPerWeek = v ?? 5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Learning Style',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _learningStyle,
                            isExpanded: true,
                            hint: Text('Mixed', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
                            dropdownColor: isDark ? AppColors.bgCard : Colors.white,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            items: ['video', 'reading', 'hands_on', 'mixed'].map((s) {
                              return DropdownMenuItem(
                                value: s,
                                child: Text(s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ')),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _learningStyle = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _skillCtrl.text.length < 2
                    ? null
                    : () {
                        Navigator.pop(context, {
                          'skill': _skillCtrl.text,
                          'goal': _goalCtrl.text.isEmpty ? null : _goalCtrl.text,
                          'level': _level,
                          'hours': _hoursPerWeek,
                          'style': _learningStyle,
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Generate My Path ✨',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitOptionsSheet extends StatelessWidget {
  final bool canWatchAd;
  final int adUnlocksRemaining;
  final VoidCallback onWatchAd;
  final VoidCallback onUpgrade;

  const _LimitOptionsSheet({
    required this.canWatchAd,
    required this.adUnlocksRemaining,
    required this.onWatchAd,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.lock_1, size: 48, color: AppColors.warning),
          const SizedBox(height: 16),
          Text(
            'Skill Limit Reached',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Free users can enroll in 3 skills. ${canWatchAd ? 'Watch 3 ads to unlock one more skill slot.' : 'Upgrade for unlimited access.'}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
            ),
          ),
          if (canWatchAd) ...[
            const SizedBox(height: 8),
            Text(
              '$adUnlocksRemaining ad unlocks remaining',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (canWatchAd)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onWatchAd,
                icon: const Icon(Iconsax.video, color: Colors.white),
                label: const Text(
                  'Watch 3 Ads to Unlock',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onUpgrade,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Upgrade to Premium',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
