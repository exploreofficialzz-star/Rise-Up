import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:share_plus/share_plus.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map _stats = {};
  List _tasks = [];
  bool _loading = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map _streak = {};

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.getStats(),
        api.getTasks(status: 'suggested'),
        api.getStreak(),
      ]);
      setState(() {
        _stats  = results[0] as Map;
        _tasks  = (results[1] as List).take(3).toList();
        _streak = results[2] as Map;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      key: _scaffoldKey,
      backgroundColor: AppColors.bgDark,
      drawer: _DashboardDrawer(profile: profile, isPremium: isPremium),
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
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white70, size: 24),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70, size: 24), onPressed: () => context.go('/notifications')),
                const SizedBox(width: 4),
              ],
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

                      const SizedBox(height: 12),

                      // ── Workflow Engine CTA ──────────────────
                      GestureDetector(
                        onTap: () => context.push('/workflow'),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Iconsax.flash, color: AppColors.success, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text('Workflow Engine', style: AppTextStyles.h4.copyWith(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                                        child: const Text('NEW', style: TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.w800)),
                                      ),
                                    ]),
                                    Text('AI researches & executes your income plan', style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white30 : Colors.black26, size: 14),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 250.ms),

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

// ── Dashboard Drawer ──────────────────────────────────
class _DashboardDrawer extends StatelessWidget {
  final Map profile;
  final bool isPremium;
  const _DashboardDrawer({required this.profile, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final border = AppColors.bgSurface;
    final name = profile['full_name']?.toString() ?? 'User';
    final stage = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);

    return Drawer(
      backgroundColor: Colors.black,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), shape: BoxShape.circle),
                  child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text('${stageInfo['emoji']} ${stageInfo['label']}',
                          style: TextStyle(fontSize: 10, color: stageInfo['color'] as Color, fontWeight: FontWeight.w600)),
                    ),
                    if (isPremium) ...[const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Text('⭐ Pro', style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w600)))],
                  ]),
                ])),
                IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Divider(color: border, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _DSec('INCOME TOOLS'),
                  _DIt(Icons.auto_awesome_rounded, 'Agentic AI', 'Execute ANY income task', onTap: () { Navigator.pop(context); context.push('/agent'); }, badge: 'HEAVY', badgeColor: AppColors.accent),
                  _DIt(Iconsax.flash, 'Workflow Engine', 'AI income execution', onTap: () { Navigator.pop(context); context.push('/workflow'); }, badge: 'NEW', badgeColor: AppColors.success),
                  _DIt(Iconsax.chart_3, 'Market Pulse', 'What pays right now', onTap: () { Navigator.pop(context); context.push('/pulse'); }, badge: '🔥', badgeColor: const Color(0xFFFF6B35)),
                  _DIt(Icons.emoji_events_rounded, 'Challenges', '30-day income sprints', onTap: () { Navigator.pop(context); context.push('/challenges'); }),
                  _DIt(Iconsax.briefcase, 'Client CRM', 'Track clients & deals', onTap: () { Navigator.pop(context); context.push('/crm'); }),
                  _DIt(Iconsax.gallery, 'Portfolio', 'Shareable showcase', onTap: () { Navigator.pop(context); context.push('/portfolio'); }),
                  _DIt(Iconsax.task_square, 'My Tasks', 'Daily income tasks', onTap: () { Navigator.pop(context); context.go('/tasks'); }),
                  _DIt(Iconsax.map_1, 'Wealth Roadmap', '3-stage plan', onTap: () { Navigator.pop(context); context.go('/roadmap'); }),
                  _DIt(Iconsax.book, 'Skills', 'Earn-while-learning', onTap: () { Navigator.pop(context); context.go('/skills'); }),
                  Divider(color: border, height: 1),
                  _DSec('SOCIAL'),
                  _DIt(Iconsax.home, 'Social Feed', 'Community posts', onTap: () { Navigator.pop(context); context.go('/home'); }),
                  _DIt(Iconsax.people, 'Collaboration', 'Build together', onTap: () { Navigator.pop(context); context.push('/collaboration'); }, badge: 'NEW', badgeColor: AppColors.primary),
                  _DIt(Iconsax.message, 'Messages', 'DMs & groups', onTap: () { Navigator.pop(context); context.go('/messages'); }),
                  _DIt(Icons.radio_button_checked_rounded, 'Go Live', 'Stream to community', onTap: () { Navigator.pop(context); context.go('/live'); }),
                  Divider(color: border, height: 1),
                  _DSec('FINANCE'),
                  _DIt(Iconsax.money_recive, 'Earnings', 'Income tracker', onTap: () { Navigator.pop(context); context.go('/earnings'); }),
                  _DIt(Iconsax.chart_2, 'Analytics', 'Growth stats', onTap: () { Navigator.pop(context); context.go('/analytics'); }),
                  _DIt(Iconsax.wallet_minus, 'Expenses', 'Budget tracking', onTap: () { Navigator.pop(context); context.go('/expenses'); }),
                  _DIt(Iconsax.flag, 'Goals', 'Targets', onTap: () { Navigator.pop(context); context.go('/goals'); }),
                  Divider(color: border, height: 1),
                  _DSec('ACCOUNT'),
                  _DIt(Iconsax.award, 'Achievements', 'Badges', onTap: () { Navigator.pop(context); context.go('/achievements'); }),
                  _DIt(Iconsax.user_tag, 'Referrals', 'Invite & earn', onTap: () { Navigator.pop(context); context.go('/referrals'); }),
                  _DIt(Iconsax.setting_2, 'Settings', 'Preferences', onTap: () { Navigator.pop(context); context.go('/settings'); }),
                ],
              ),
            ),
            if (!isPremium)
              Padding(
                padding: const EdgeInsets.all(14),
                child: GestureDetector(
                  onTap: () { Navigator.pop(context); context.push('/premium'); },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: const Row(children: [
                      Text('⭐', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Upgrade to Premium', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        Text('Unlimited AI + all features', style: TextStyle(fontSize: 11, color: Colors.white38)),
                      ])),
                      Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.primary),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DSec extends StatelessWidget {
  final String label;
  const _DSec(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
    child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 1.1)),
  );
}

class _DIt extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;
  const _DIt(this.icon, this.label, this.sub, {required this.onTap, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: Colors.white70),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                if (badge != null) ...[const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: (badgeColor ?? AppColors.primary).withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                    child: Text(badge!, style: TextStyle(fontSize: 9, color: badgeColor ?? AppColors.primary, fontWeight: FontWeight.w700)),
                  )],
              ]),
              Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ])),
            const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.white24),
          ]),
        ),
      ),
    );
  }
}
