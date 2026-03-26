import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;

  String _query     = '';
  bool   _searching = false;

  // All data comes from API
  List _trendingPosts = [];
  List _creators      = [];
  List _groups        = [];
  List _leaders       = [];
  List _challenges    = [];

  bool _postsLoaded      = false;
  bool _creatorsLoaded   = false;
  bool _groupsLoaded     = false;
  bool _leadersLoaded    = false;
  bool _challengesLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _tabCtrl.addListener(_onTabChange);
    _loadPosts();
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabCtrl.removeListener(_onTabChange);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (!_tabCtrl.indexIsChanging) return;
    switch (_tabCtrl.index) {
      case 1: if (!_creatorsLoaded)   _loadCreators();   break;
      case 2: if (!_groupsLoaded)     _loadGroups();     break;
      case 3: if (!_leadersLoaded)    _loadLeaderboard(); break;
      case 4: if (!_challengesLoaded) _loadChallenges(); break;
    }
  }

  Future<void> _loadPosts() async {
    try {
      final d = await api.getFeed(tab: 'trending', limit: 20, offset: 0);
      if (mounted) setState(() {
        _trendingPosts = d['posts'] as List? ?? [];
        _postsLoaded   = true;
      });
    } catch (_) {
      if (mounted) setState(() => _postsLoaded = true);
    }
  }

  Future<void> _loadCreators() async {
    try {
      final d = await api.get('/progress/leaderboard');
      if (mounted) setState(() {
        _creators       = (d as Map?)?['leaders'] as List? ?? [];
        _creatorsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _creatorsLoaded = true);
    }
  }

  Future<void> _loadGroups() async {
    try {
      final d = await api.get('/community/groups');
      if (mounted) setState(() {
        _groups       = (d as Map?)?['groups'] ?? d as List? ?? [];
        _groupsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _groupsLoaded = true);
    }
  }

  Future<void> _loadLeaderboard() async {
    try {
      final d = await api.get('/progress/leaderboard');
      if (mounted) setState(() {
        _leaders      = (d as Map?)?['leaders'] as List? ?? [];
        _leadersLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _leadersLoaded = true);
    }
  }

  Future<void> _loadChallenges() async {
    try {
      final d = await api.get('/challenges/');
      if (mounted) setState(() {
        _challenges      = (d as Map?)?['challenges'] as List? ?? [];
        _challengesLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _challengesLoaded = true);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _postsLoaded = _creatorsLoaded = _groupsLoaded =
          _leadersLoaded = _challengesLoaded = false;
    });
    await Future.wait([_loadPosts(), _loadLeaderboard()]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? Colors.black : Colors.white;
    final card     = isDark ? AppColors.bgCard : Colors.white;
    final surface  = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text     = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Explore',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.refresh, color: sub, size: 20),
            onPressed: _refreshAll,
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: Column(children: [
        // Search
        Container(
          color: card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 14, color: text),
            onChanged: (v) => setState(() { _query = v; _searching = v.isNotEmpty; }),
            decoration: InputDecoration(
              hintText: 'Search creators, topics, groups...',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled: true,
              fillColor: surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: sub, size: 18),
              suffixIcon: _searching
                  ? IconButton(
                      icon: Icon(Icons.close, color: sub, size: 18),
                      onPressed: () => setState(() { _searchCtrl.clear(); _query = ''; _searching = false; }))
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Tabs
        Container(
          color: card,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: AppColors.primary,
            unselectedLabelColor: sub,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Trending'),
              Tab(text: 'Creators'),
              Tab(text: 'Groups'),
              Tab(text: 'Leaderboard'),
              Tab(text: 'Challenges'),
              Tab(text: 'Topics'),
            ],
          ),
        ),
        Divider(height: 1, color: border),

        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [
            // TRENDING
            _buildTabBody(_postsLoaded, _trendingPosts.isEmpty && _postsLoaded,
              'No trending posts yet', 'Be the first to post something!',
              RefreshIndicator(
                onRefresh: _loadPosts,
                color: AppColors.primary,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _trendingPosts.length,
                  separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
                  itemBuilder: (_, i) {
                    final p = _trendingPosts[i] as Map;
                    return _PostCard(post: p, isDark: isDark, text: text, sub: sub, card: card, index: i);
                  },
                ),
              ),
            ),

            // CREATORS (from leaderboard)
            _buildTabBody(_creatorsLoaded, _creators.isEmpty && _creatorsLoaded,
              'No top earners yet', 'Start earning to appear here!',
              ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _creators.length,
                separatorBuilder: (_, __) => Divider(height: 16, color: border),
                itemBuilder: (_, i) {
                  final c    = _creators[i] as Map;
                  final name = c['full_name']?.toString() ?? 'User';
                  final earned = (c['total_earned'] as num?)?.toDouble() ?? 0;
                  final country = c['country']?.toString() ?? '';
                  return Row(children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                      Text(country, style: TextStyle(fontSize: 12, color: sub)),
                      Text('Stage: ${c['stage'] ?? 'survival'}',
                          style: TextStyle(fontSize: 12, color: sub)),
                      Text('\$${earned.toStringAsFixed(0)} earned',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ])),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (c['id'] != null) context.go('/user-profile/${c['id']}');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                        child: const Text('View',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),
            ),

            // GROUPS
            _buildTabBody(_groupsLoaded, _groups.isEmpty && _groupsLoaded,
              'No groups yet', 'Groups are coming soon!',
              ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: border),
                itemBuilder: (_, i) {
                  final g = _groups[i] as Map;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(g['emoji']?.toString() ?? '💬',
                            style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g['name']?.toString() ?? '',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text('${g['members_count'] ?? 0} members',
                              style: TextStyle(fontSize: 11, color: sub)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(g['category']?.toString() ?? '',
                                style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ])),
                      GestureDetector(
                        onTap: () => context.go('/groups'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                          child: const Text('Join',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),

            // LEADERBOARD
            Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                color: card,
                child: Row(children: [
                  const Text('Real verified earnings', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.pill),
                    child: const Text('LIVE', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              Expanded(
                child: _buildTabBody(_leadersLoaded, _leaders.isEmpty && _leadersLoaded,
                  'No earners yet', 'Start earning to appear here!',
                  ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _leaders.length,
                    itemBuilder: (_, i) {
                      final l      = _leaders[i] as Map;
                      final rank   = (l['rank'] as num?)?.toInt() ?? i + 1;
                      final isTop3 = rank <= 3;
                      final name   = l['full_name']?.toString() ?? 'User';
                      final earned = (l['total_earned'] as num?)?.toDouble() ?? 0;
                      final badges = ['🥇', '🥈', '🥉'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isTop3
                              ? AppColors.gold.withOpacity(isDark ? 0.12 : 0.06)
                              : (isDark ? AppColors.bgCard : const Color(0xFFF8F8F8)),
                          borderRadius: BorderRadius.circular(14),
                          border: isTop3 ? Border.all(color: AppColors.gold.withOpacity(0.3)) : null,
                        ),
                        child: Row(children: [
                          SizedBox(
                            width: 36,
                            child: Text(isTop3 ? badges[rank - 1] : '#$rank',
                                style: TextStyle(fontSize: isTop3 ? 22 : 14,
                                    fontWeight: FontWeight.w700, color: sub),
                                textAlign: TextAlign.center),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle),
                            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                                    color: isTop3 ? AppColors.gold : AppColors.primary))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                            Row(children: [
                              Text(l['country']?.toString() ?? '',
                                  style: TextStyle(fontSize: 11, color: sub)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(l['stage']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 9,
                                        color: AppColors.primary, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('\$${earned.toStringAsFixed(0)}',
                                style: TextStyle(color: isTop3 ? AppColors.gold : AppColors.success,
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            Text('earned', style: TextStyle(fontSize: 10, color: sub)),
                          ]),
                        ]),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                    },
                  ),
                ),
              ),
            ]),

            // CHALLENGES
            _buildTabBody(_challengesLoaded, _challenges.isEmpty && _challengesLoaded,
              'No challenges yet', 'Start a challenge from the Income Tools menu!',
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _challenges.length,
                itemBuilder: (_, i) {
                  final c       = _challenges[i] as Map;
                  final pct     = ((c['current_usd'] ?? 0) / ((c['target_usd'] ?? 1) == 0 ? 1 : c['target_usd'])).clamp(0.0, 1.0).toDouble();
                  final active  = c['status'] == 'active';
                  final done    = c['status'] == 'completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(16),
                      border: active ? Border.all(color: AppColors.primary.withOpacity(0.3)) : null,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(c['emoji']?.toString() ?? '🎯',
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['title']?.toString() ?? '',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                          Text('Day ${c['current_day'] ?? 1}/${c['duration_days'] ?? 30} '
                               '· ${c['streak'] ?? 0} day streak',
                              style: TextStyle(fontSize: 11, color: sub)),
                        ])),
                        if (done)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('DONE', style: TextStyle(
                                fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Text('\$${c['current_usd'] ?? 0}', style: const TextStyle(
                            color: AppColors.success, fontWeight: FontWeight.w700)),
                        Text(' / \$${c['target_usd'] ?? 0}',
                            style: TextStyle(color: sub, fontSize: 12)),
                        const Spacer(),
                        Text('${(pct * 100).toStringAsFixed(0)}%',
                            style: TextStyle(color: sub, fontSize: 12)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(done ? AppColors.success : AppColors.primary),
                          minHeight: 5,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.go('/challenges'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Check In Today',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),
            ),

            // TOPICS
            GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6),
              itemCount: _topicData.length,
              itemBuilder: (_, i) {
                final t = _topicData[i];
                return GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(t.$1, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(t.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                    ]),
                  ),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
              },
            ),
          ]),
        ),
      ]),
    );
  }

  // Helper to show loading, empty, or content
  Widget _buildTabBody(bool loaded, bool empty, String emptyTitle, String emptySub, Widget content) {
    if (!loaded) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    if (empty)   return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🔍', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(emptyTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(emptySub, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
    ]));
    return content;
  }

  static const _topicData = [
    ('💰', 'Wealth'),
    ('📈', 'Investing'),
    ('💼', 'Business'),
    ('🧠', 'Mindset'),
    ('⚡', 'Hustle'),
    ('🎯', 'Skills'),
    ('🏠', 'Real Estate'),
    ('💻', 'Tech'),
  ];
}

// POST CARD - renders a real post from API
class _PostCard extends StatelessWidget {
  final Map   post;
  final bool  isDark;
  final Color text, sub, card;
  final int   index;

  const _PostCard({required this.post, required this.isDark, required this.text,
      required this.sub, required this.card, required this.index});

  @override
  Widget build(BuildContext context) {
    final name    = post['author_name']?.toString() ?? post['full_name']?.toString() ?? 'User';
    final content = post['content']?.toString() ?? '';
    final likes   = (post['likes_count'] as num?)?.toInt() ?? 0;
    final tag     = post['tag']?.toString() ?? '';

    return Container(
      color: card,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppColors.primary))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
            Text(_timeAgo(post['created_at']?.toString()), style: TextStyle(fontSize: 11, color: sub)),
          ])),
          if (tag.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(tag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(content, style: TextStyle(fontSize: 14, color: text, height: 1.55)),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.favorite_border_rounded, color: sub, size: 18),
          const SizedBox(width: 4),
          Text(_fmt(likes), style: TextStyle(color: sub, fontSize: 12)),
          const SizedBox(width: 16),
          Icon(Iconsax.message, color: sub, size: 18),
          const SizedBox(width: 4),
          Text(_fmt((post['comments_count'] as num?)?.toInt() ?? 0),
              style: TextStyle(color: sub, fontSize: 12)),
        ]),
      ]),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 60));
  }

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt   = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24)  return '${diff.inHours}h ago';
      if (diff.inDays    < 7)   return '${diff.inDays}d ago';
      return '${diff.inDays ~/ 7}w ago';
    } catch (_) { return ''; }
  }
}
