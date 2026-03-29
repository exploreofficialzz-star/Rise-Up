// frontend/lib/screens/skills/skill_lesson_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class SkillLessonScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> enrollment;
  const SkillLessonScreen({super.key, required this.enrollment});

  @override
  ConsumerState<SkillLessonScreen> createState() => _SkillLessonScreenState();
}

class _SkillLessonScreenState extends ConsumerState<SkillLessonScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await api.get('/skills/enrollment/${widget.enrollment['id']}');
      if (mounted) {
        setState(() {
          _detail = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeLesson(int lessonNumber, {double? earnings}) async {
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    try {
      final response = await api.post('/skills/progress', {
        'enrollment_id': widget.enrollment['id'],
        'lesson_completed': lessonNumber,
        'time_spent_minutes': 30, // Could track actual time
        'earnings_logged': earnings,
      });

      if (mounted) {
        final insights = response['insights'] as Map<String, dynamic>?;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['check_in']?['message'] ?? 'Progress saved!'),
            backgroundColor: AppColors.success,
          ),
        );

        if (insights?['milestone_message'] != null) {
          await Future.delayed(const Duration(milliseconds: 300));
          _showMilestoneDialog(insights!['milestone_message']);
        }

        if (response['challenge_status'] == 'completed') {
          _showCompletionDialog(response['completion']);
        }

        _loadDetail();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMilestoneDialog(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Keep Going!', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog(Map<String, dynamic>? completion) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎓', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(
              'SKILL MASTERED!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You\'ve completed ${widget.enrollment['skill_name']}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
              ),
            ),
            if (completion != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total Earned: \$${completion['total_earned_usd']?.toStringAsFixed(2) ?? '0.00'}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                    if (completion['streak_maintained'] == true)
                      Text(
                        '🔥 Perfect streak maintained!',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Amazing! 🎉',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchResource(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final enrollment = widget.enrollment;
    final skillPath = _detail?['skill_path'] as Map<String, dynamic>? ?? {};
    final curriculum = skillPath['curriculum'] as List? ?? [];
    final currentModuleIdx = (enrollment['current_module'] ?? 1) - 1;
    final currentLessonIdx = (enrollment['current_lesson'] ?? 1) - 1;

    // Get current lesson
    Map<String, dynamic>? currentLesson;
    if (currentModuleIdx < curriculum.length) {
      final module = curriculum[currentModuleIdx] as Map<String, dynamic>;
      final lessons = module['lessons'] as List? ?? [];
      if (currentLessonIdx < lessons.length) {
        currentLesson = lessons[currentLessonIdx] as Map<String, dynamic>;
      }
    }

    if (currentLesson == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, elevation: 0),
        body: Center(
          child: Text(
            'All lessons completed! 🎉',
            style: TextStyle(fontSize: 18, color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      );
    }

    final resources = currentLesson['resources'] as List? ?? [];
    final actionItems = currentLesson['action_items'] as List? ?? [];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              enrollment['skill_name'] ?? '',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Module ${currentModuleIdx + 1} • Lesson ${currentLessonIdx + 1}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress
          LinearProgressIndicator(
            value: (enrollment['progress_percent'] ?? 0) / 100,
            backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${enrollment['progress_percent']?.toStringAsFixed(0) ?? 0}% complete',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              Text(
                '${enrollment['streak_days'] ?? 0} day streak 🔥',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Lesson Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.15),
                  AppColors.accent.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        currentLesson['type']?.toString().toUpperCase() ?? 'LESSON',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(Iconsax.timer_1, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      '${currentLesson['time_minutes'] ?? 30} mins',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  currentLesson['title'] ?? '',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currentLesson['description'] ?? '',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1),
          const SizedBox(height: 24),

          // Resources
          if (resources.isNotEmpty) ...[
            Text(
              'Learning Resources',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...resources.asMap().entries.map((entry) {
              final resource = entry.value as Map<String, dynamic>;
              final type = resource['type'] as String? ?? 'article';
              
              IconData icon;
              Color color;
              switch (type) {
                case 'youtube':
                case 'video':
                  icon = Iconsax.video;
                  color = Colors.red;
                  break;
                case 'documentation':
                  icon = Iconsax.document;
                  color = Colors.blue;
                  break;
                case 'course':
                  icon = Iconsax.teacher;
                  color = AppColors.primary;
                  break;
                case 'tool':
                  icon = Iconsax.tool;
                  color = AppColors.success;
                  break;
                default:
                  icon = Iconsax.book_1;
                  color = AppColors.accent;
              }

              return GestureDetector(
                onTap: () => _launchResource(resource['url'] ?? ''),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resource['title'] ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${resource['source'] ?? 'Unknown'} • ${resource['language'] ?? 'en'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            if (resource['quality_rating'] != null)
                              Text(
                                'Level: ${resource['quality_rating']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Iconsax.export_3, size: 18, color: isDark ? Colors.white38 : Colors.black38),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: Duration(milliseconds: entry.key * 100));
            }),
            const SizedBox(height: 24),
          ],

          // Action Items
          if (actionItems.isNotEmpty) ...[
            Text(
              'Your Tasks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...actionItems.asMap().entries.map((entry) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.value.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),
          ],

          // Deliverable
          if (currentLesson['deliverable'] != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Iconsax.task, color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Deliverable',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentLesson['deliverable'],
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Earnings input
          Text(
            'Log Earnings (optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          _EarningsInput(
            onSubmit: (amount) => _completeLesson(
              (enrollment['current_lesson'] ?? 1),
              earnings: amount,
            ),
            isSubmitting: _submitting,
            currency: enrollment['currency_local'] ?? 'USD',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _EarningsInput extends StatefulWidget {
  final Function(double) onSubmit;
  final bool isSubmitting;
  final String currency;
  
  const _EarningsInput({
    required this.onSubmit,
    required this.isSubmitting,
    required this.currency,
  });

  @override
  State<_EarningsInput> createState() => _EarningsInputState();
}

class _EarningsInputState extends State<_EarningsInput> {
  final _ctrl = TextEditingController();
  bool _hasEarnings = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Amount earned this lesson (${widget.currency})',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Iconsax.wallet_3,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _hasEarnings = double.tryParse(v) != null && double.parse(v) > 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.isSubmitting
                ? null
                : () {
                    final amount = double.tryParse(_ctrl.text) ?? 0;
                    widget.onSubmit(amount);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasEarnings ? AppColors.success : AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: widget.isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _hasEarnings ? 'Complete & Log Earnings 💰' : 'Mark Complete',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
