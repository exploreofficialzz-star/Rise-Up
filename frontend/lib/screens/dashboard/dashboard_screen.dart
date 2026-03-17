import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/stage_badge.dart';
import '../../widgets/task_preview_card.dart';
import '../../widgets/gradient_button.dart';
import '../../services/ad_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map _stats = {};
  List _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await api.getStats();
      final tasksData = await api.getTasks(status: 'suggested');
      setState(() {
        _stats = stats;
        _tasks = (tasksData as List).take(3).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _stats['profile'] as Map? ?? {};
    final name = profile['full_name']?.toString().split(' ').first ?? 'Champion';
    final stage = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final totalEarned = (_stats['total_earned'] ?? 0.0) as num;
    final tasksData = _stats['tasks'] as Map? ?? {};
    final skillsData = _stats['skills'] as Map? ?? {};
    final isPremium = (_stats['subscription'] ?? 'free') == 'premium';
    final currency = profile['currency']?.toString() ?? 'NGN';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              backgroundColor: AppColors.bgDark,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A0E4F), AppColors.bgDark],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  child: _loading ? const SizedBox() : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$_greeting,', style: AppTextStyles.label),
                              Text(name, style: AppTextStyles.h2),
                            ],
                          ),
                          Row(
                            children: [
                              StageBadge(stage: stage),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => context.go('/profile'),
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.primary.withOpacity(0.2),
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                    style: AppTextStyles.h4.copyWith(color: AppColors.primary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    else ...[
                      // Earnings hero
                      _EarningsHero(
                        total: totalEarned.toDouble(),
                        currency: currency,
                        stage: stage,
                        stageInfo: stageInfo,
                        isPremium: isPremium,
                      ).animate().fadeIn(duration: 400.ms),

                      const SizedBox(height: 20),

                      // Stats row
                      Row(
                        children: [
                          Expanded(child: StatCard(
                            icon: Iconsax.task_square,
                            label: 'Tasks Done',
                            value: '${tasksData['completed'] ?? 0}',
                            color: AppColors.accent,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: StatCard(
                            icon: Iconsax.book,
                            label: 'Skills',
                            value: '${skillsData['enrolled'] ?? 0}',
                            color: AppColors.gold,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: StatCard(
                            icon: Iconsax.activity,
                            label: 'Active',
                            value: '${tasksData['active'] ?? 0}',
                            color: AppColors.success,
                          )),
                        ],
                      ).animate().fadeIn(delay: 100.ms),

                      const SizedBox(height: 24),

                      // AI Chat CTA
                      GestureDetector(
                        onTap: () => context.go('/chat'),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary.withOpacity(0.2), AppColors.accent.withOpacity(0.1)],
                            ),
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ask your AI Mentor', style: AppTextStyles.h4.copyWith(fontSize: 15)),
                                    Text('Get personalized income advice now', style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 16),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 200.ms),

                      const SizedBox(height: 24),

                      // Suggested Tasks
                      if (_tasks.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Today\'s Income Tasks', style: AppTextStyles.h4),
                            GestureDetector(
                              onTap: () => context.go('/tasks'),
                              child: Text('See all', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._tasks.asMap().entries.map((e) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TaskPreviewCard(task: Map<String, dynamic>.from(e.value), onTap: () => context.go('/tasks'))
                                .animate().fadeIn(delay: Duration(milliseconds: 300 + e.key * 80)),
                          ),
                        ),
                      ] else if (!_loading) ...[
                        // No tasks - generate
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.bgCard,
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: AppColors.bgSurface),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.rocket_launch_rounded, color: AppColors.primary, size: 40),
                              const SizedBox(height: 12),
                              Text('Generate Your First Tasks', style: AppTextStyles.h4, textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              Text('Let AI find income opportunities tailored for you', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              GradientButton(text: 'Generate Tasks 🎯', onTap: () => context.go('/tasks')),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],

                      // Premium upsell if free
                      if (!isPremium) ...[
                        const SizedBox(height: 24),
                        _PremiumBanner().animate().fadeIn(delay: 400.ms),
                      ],

                      // ── Banner Ad ──────────────────────────
                      const SizedBox(height: 24),
                      const Center(child: BannerAdWidget())
                          .animate().fadeIn(delay: 500.ms),

                      const SizedBox(height: 80),
                    ],
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

class _EarningsHero extends StatelessWidget {
  final double total;
  final String currency;
  final String stage;
  final Map stageInfo;
  final bool isPremium;
  const _EarningsHero({required this.total, required this.currency, required this.stage, required this.stageInfo, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (stageInfo['color'] as Color).withOpacity(0.2),
            AppColors.bgCard,
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xl,
        border: Border.all(color: (stageInfo['color'] as Color).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Earned via RiseUp', style: AppTextStyles.label),
              if (isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text('Premium', style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$currency ${_formatAmount(total)}',
            style: AppTextStyles.money,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (stageInfo['color'] as Color).withOpacity(0.15),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stageInfo['emoji'] as String),
                    const SizedBox(width: 6),
                    Text(stageInfo['label'] as String, style: AppTextStyles.caption.copyWith(color: stageInfo['color'] as Color, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('Target: ${stageInfo['target']}', style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}

class _PremiumBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/payment'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2D1B69), Color(0xFF1A3A4F)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Text('👑', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upgrade to Premium', style: AppTextStyles.h4.copyWith(color: AppColors.gold)),
                  Text('Unlock AI roadmap, all skills & wealth tools · \$15.99/month', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.gold, size: 16),
          ],
        ),
      ),
    );
  }
}
