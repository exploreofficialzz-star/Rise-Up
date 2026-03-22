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
  Map _stats = {};
  List _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = await api.getUserId() ?? '';
      final results = await Future.wait([
        api.getProfile(),
        api.getUserPosts(userId),
      ]);
      if (mounted) {
        setState(() {
          _profile = (results[0] as Map)['profile'] ?? {};
          _posts = (results[1] as Map)['posts'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic n) {
    final num = n as int? ?? 0;
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return '$num';
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

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
    final isPremium = _profile['subscription_tier'] == 'premium';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(icon: Icon(Iconsax.setting_2, color: textColor, size: 22), onPressed: () => context.go('/settings')),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: borderColor)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: Column(children: [
                // ── Profile header ──────────────────────
                Container(
                  color: cardColor,
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Avatar
                      Stack(children: [
                        Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '👤',
                            style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w700),
                          )),
                        ),
                        Positioned(bottom: 0, right: 0, child: GestureDetector(
                          onTap: () {},
                          child: Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: cardColor, width: 2)),
                            child: const Icon(Icons.add, color: Colors.white, size: 12),
                          ),
                        )),
                      ]),
                      const SizedBox(width: 16),

                      // Stats
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatCol(_fmt(_posts.length), 'Posts', textColor, subColor),
                            _StatCol(_fmt(_profile['followers_count']), 'Followers', textColor, subColor),
                            _StatCol(_fmt(_profile['following_count']), 'Following', textColor, subColor),
                          ],
                        ),
                      ),
                    ]),

                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                            child: Text('${stageInfo['emoji']} ${stageInfo['label']}', style: TextStyle(fontSize: 10, color: stageInfo['color'] as Color, fontWeight: FontWeight.w600)),
                          ),
                          if (isPremium) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]), borderRadius: BorderRadius.circular(8)),
                              child: const Text('⭐ PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(_profile['bio']?.toString() ?? 'Building wealth one step at a time 🚀', style: TextStyle(fontSize: 13, color: subColor)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Iconsax.location, size: 12, color: subColor),
                          const SizedBox(width: 4),
                          Text(_profile['country']?.toString() ?? 'Worldwide 🌍', style: TextStyle(fontSize: 12, color: subColor)),
                        ]),
                      ]),
                    ),

                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
                          child: Center(child: Text('Edit Profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
                          child: Center(child: Text('Share Profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                        ),
                      )),
                      if (!isPremium) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => context.go('/premium'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]), borderRadius: BorderRadius.circular(10)),
                            child: const Text('⭐ Pro', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ]),
                  ]),
                ),

                // ── Tabs ────────────────────────────────
                Container(
                  color: cardColor,
                  child: TabBar(
                    controller: _tabCtrl,
                    labelColor: AppColors.primary, unselectedLabelColor: subColor,
                    indicatorColor: AppColors.primary, indicatorWeight: 2.5,
                    tabs: const [Tab(icon: Icon(Iconsax.grid_1, size: 20)), Tab(icon: Icon(Iconsax.heart, size: 20))],
                  ),
                ),
                Divider(height: 1, color: borderColor),

                // ── Posts ────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // My posts
                      _posts.isEmpty
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('📝', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text('No posts yet', style: TextStyle(color: subColor, fontSize: 14)),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => context.go('/create'),
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)), child: const Text('Create your first post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                              ),
                            ]))
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _posts.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                              itemBuilder: (_, i) {
                                final p = _posts[i];
                                return Container(
                                  color: cardColor,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Text(p['tag']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(_timeAgo(p['created_at']?.toString()), style: TextStyle(fontSize: 11, color: subColor)),
                                    ]),
                                    const SizedBox(height: 8),
                                    Text(p['content']?.toString() ?? '', style: TextStyle(fontSize: 14, color: textColor, height: 1.5)),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Icon(Icons.favorite_border_rounded, size: 16, color: subColor),
                                      const SizedBox(width: 4),
                                      Text('${p['likes_count'] ?? 0}', style: TextStyle(fontSize: 12, color: subColor)),
                                      const SizedBox(width: 16),
                                      Icon(Iconsax.message, size: 16, color: subColor),
                                      const SizedBox(width: 4),
                                      Text('${p['comments_count'] ?? 0}', style: TextStyle(fontSize: 12, color: subColor)),
                                    ]),
                                  ]),
                                ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                              },
                            ),

                      // Liked
                      Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Iconsax.heart, size: 48, color: subColor), const SizedBox(height: 12), Text('No liked posts yet', style: TextStyle(color: subColor, fontSize: 14))])),
                    ],
                  ),
                ),
              ]),
            ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String value, label;
  final Color textColor, subColor;
  const _StatCol(this.value, this.label, this.textColor, this.subColor);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: subColor)),
  ]);
}
