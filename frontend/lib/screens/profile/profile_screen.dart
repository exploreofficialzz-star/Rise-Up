import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map _profile = {};
  bool _loading = true;

  static const _posts = [
    ('💰', 'Just hit my first \$1K month freelancing. It\'s real, people. Pick a skill and go all in.', '2h ago', 234, '💰 Wealth'),
    ('💡', 'Reminder: Your network is your net worth. Invest in relationships as much as money.', '1d ago', 891, '🧠 Mindset'),
    ('🚀', 'Started with nothing. Now managing 3 income streams. Consistency > talent every time.', '3d ago', 1203, '⚡ Hustle'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await api.getProfile();
      if (mounted) setState(() { _profile = data['profile'] ?? {}; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final name = _profile['full_name']?.toString() ?? 'Your Name';
    final stage = _profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.setting_2, color: textColor, size: 22),
            onPressed: () => context.go('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // ── Profile header ────────────────────────
                Container(
                  color: cardColor,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          Stack(children: [
                            Container(
                              width: 76, height: 76,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [AppColors.primary, AppColors.accent]),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '👤',
                                  style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: AppColors.primary, shape: BoxShape.circle,
                                  border: Border.all(color: cardColor, width: 2),
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 12),
                              ),
                            ),
                          ]),
                          const SizedBox(width: 16),

                          // Stats
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _StatCol('Posts', '12', textColor, subColor),
                                _StatCol('Followers', '1.2K', textColor, subColor),
                                _StatCol('Following', '348', textColor, subColor),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Name + stage badge
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (stageInfo['color'] as Color).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${stageInfo['emoji']} ${stageInfo['label']}',
                                  style: TextStyle(fontSize: 10, color: stageInfo['color'] as Color, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text('Building wealth one step at a time 🚀',
                                style: TextStyle(fontSize: 13, color: subColor)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Iconsax.location, size: 12, color: subColor),
                              const SizedBox(width: 4),
                              Text('Worldwide 🌍', style: TextStyle(fontSize: 12, color: subColor)),
                            ]),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Edit profile + Share buttons
                      Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {},
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                              ),
                              child: Center(child: Text('Edit Profile',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {},
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                              ),
                              child: Center(child: Text('Share Profile',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),

                // ── Tabs ──────────────────────────────────
                Container(
                  color: cardColor,
                  child: TabBar(
                    controller: _tabCtrl,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: subColor,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    tabs: const [
                      Tab(icon: Icon(Iconsax.grid_1, size: 20)),
                      Tab(icon: Icon(Iconsax.heart, size: 20)),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),

                // ── Posts grid ───────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // My posts
                      ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _posts.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                        itemBuilder: (_, i) {
                          final p = _posts[i];
                          return Container(
                            color: cardColor,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(p.$5, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  Text(p.$3, style: TextStyle(fontSize: 11, color: subColor)),
                                ]),
                                const SizedBox(height: 8),
                                Text(p.$2, style: TextStyle(fontSize: 14, color: textColor, height: 1.5)),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Icon(Icons.favorite_border_rounded, size: 16, color: subColor),
                                  const SizedBox(width: 4),
                                  Text('${p.$4}', style: TextStyle(fontSize: 12, color: subColor)),
                                ]),
                              ],
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                        },
                      ),

                      // Liked posts
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Iconsax.heart, size: 48, color: subColor),
                            const SizedBox(height: 12),
                            Text('No liked posts yet', style: TextStyle(color: subColor, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String label, value;
  final Color textColor, subColor;
  const _StatCol(this.label, this.value, this.textColor, this.subColor);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: subColor)),
  ]);
}
