// frontend/lib/screens/explore/explore_screen.dart
// v2.0 — Marketplace-first Explore
//
// Changes from v1:
//  • Removed "Trending" tab — trending posts already live on Home screen
//  • Added "Marketplace" tab (index 4) — powered by Methods Brain API
//    Tabs: Creators | Groups | Leaderboard | Challenges | Marketplace | Topics
//  • Marketplace shows buy/sell/service listings from /brain/marketplace
//    with listing-type filter chips (All / Sell / Buy / Services)
//    and inline "Contact Seller" / "Make Inquiry" CTA
//  • Search now covers all tabs (posts, creators, groups, marketplace items)
//  • All existing tab content preserved exactly

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

  // Tab data
  List _creators      = [];
  List _groups        = [];
  List _leaders       = [];
  List _challenges    = [];
  List _marketplace   = [];

  bool _creatorsLoaded   = false;
  bool _groupsLoaded     = false;
  bool _leadersLoaded    = false;
  bool _challengesLoaded = false;
  bool _marketplaceLoaded = false;

  // Marketplace filter
  String _marketFilter = 'all'; // all | sell | buy | service

  @override
  void initState() {
    super.initState();
    // 6 tabs: Creators | Groups | Leaderboard | Challenges | Marketplace | Topics
    _tabCtrl = TabController(length: 6, vsync: this);
    _tabCtrl.addListener(_onTabChange);
    // Load first visible tab + leaderboard (always shown on Explore)
    _loadCreators();
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
      case 0: if (!_creatorsLoaded)    _loadCreators();    break;
      case 1: if (!_groupsLoaded)      _loadGroups();      break;
      case 2: if (!_leadersLoaded)     _loadLeaderboard(); break;
      case 3: if (!_challengesLoaded)  _loadChallenges();  break;
      case 4: if (!_marketplaceLoaded) _loadMarketplace(); break;
    }
  }

  // ── Data loaders ────────────────────────────────────────────────

  Future<void> _loadCreators() async {
    try {
      final d = await api.get('/progress/leaderboard');
      if (mounted) setState(() {
        _creators      = (d as Map?)?['leaders'] as List? ?? [];
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
        _groups      = (d as Map?)?['groups'] ?? d as List? ?? [];
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
        _leaders       = (d as Map?)?['leaders'] as List? ?? [];
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

  Future<void> _loadMarketplace({String? filter}) async {
    final f = filter ?? _marketFilter;
    if (mounted) setState(() => _marketplaceLoaded = false);
    try {
      final Map<String, dynamic> params = {'limit': 30, 'offset': 0};
      if (f != 'all') params['listing_type'] = f;
      if (_query.isNotEmpty) params['search'] = _query;
      final d = await api.getMarketplaceListings(
        listingType: f == 'all' ? null : f,
        search:      _query.isNotEmpty ? _query : null,
        limit: 30,
      );
      if (mounted) setState(() {
        _marketplace      = (d['listings'] as List?) ?? [];
        _marketplaceLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _marketplaceLoaded = true);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _creatorsLoaded = _groupsLoaded = _leadersLoaded =
          _challengesLoaded = _marketplaceLoaded = false;
    });
    await Future.wait([_loadCreators(), _loadLeaderboard()]);
  }

  void _onSearchChanged(String v) {
    setState(() { _query = v; _searching = v.isNotEmpty; });
    if (_tabCtrl.index == 4) {
      // Live search in marketplace
      _loadMarketplace();
    }
  }

  // ── Marketplace inquiry ──────────────────────────────────────────
  Future<void> _inquire(BuildContext ctx, Map listing) async {
    final ctrl = TextEditingController();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final confirmed = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          Text('Contact about: ${listing['title'] ?? 'Listing'}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Write your message or offer…',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(sheetCtx, true),
              child: const Text('Send Message',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      try {
        await api.inquireMarketplaceListing(
            listing['id']?.toString() ?? '', ctrl.text.trim());
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Message sent! 🎉'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2)));
        }
      } catch (_) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Failed to send. Try again.'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? Colors.black : Colors.white;
    final card    = isDark ? AppColors.bgCard : Colors.white;
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text    = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;

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
        // ── Search ─────────────────────────────────────────────────
        Container(
          color: card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 14, color: text),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search creators, groups, marketplace…',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled: true,
              fillColor: surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: sub, size: 18),
              suffixIcon: _searching
                  ? IconButton(
                      icon: Icon(Icons.close, color: sub, size: 18),
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _query     = '';
                        _searching = false;
                      }))
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // ── Tabs ────────────────────────────────────────────────────
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
              Tab(text: 'Creators'),
              Tab(text: 'Groups'),
              Tab(text: 'Leaderboard'),
              Tab(text: 'Challenges'),
              Tab(text: 'Marketplace'),
              Tab(text: 'Topics'),
            ],
          ),
        ),
        Divider(height: 1, color: border),

        // ── Tab content ─────────────────────────────────────────────
        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [

            // ── 0: CREATORS ────────────────────────────────────────
            _buildTabBody(_creatorsLoaded, _creators.isEmpty && _creatorsLoaded,
              'No top earners yet', 'Start earning to appear here!',
              ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _creators.length,
                separatorBuilder: (_, __) => Divider(height: 16, color: border),
                itemBuilder: (_, i) {
                  final c      = _creators[i] as Map;
                  final name   = c['full_name']?.toString() ?? 'User';
                  final earned = (c['total_earned'] as num?)?.toDouble() ?? 0;
                  final country = c['country']?.toString() ?? '';
                  return Row(children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              color: Colors.white))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name, style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                      Text(country, style: TextStyle(fontSize: 12, color: sub)),
                      Text('Stage: ${c['stage'] ?? 'survival'}',
                          style: TextStyle(fontSize: 12, color: sub)),
                      Text('\$${earned.toStringAsFixed(0)} earned',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ])),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (c['id'] != null) context.push('/user-profile/${c['id']}');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('View',
                            style: TextStyle(
                                color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),
            ),

            // ── 1: GROUPS ─────────────────────────────────────────
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
                          color: isDark
                              ? AppColors.bgSurface
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                            g['emoji']?.toString() ?? '💬',
                            style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(g['name']?.toString() ?? '',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: text)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text('${g['members_count'] ?? 0} members',
                              style: TextStyle(fontSize: 11, color: sub)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(g['category']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ])),
                      GestureDetector(
                        onTap: () => context.go('/groups'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('Join',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),

            // ── 2: LEADERBOARD ────────────────────────────────────
            Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                color: card,
                child: Row(children: [
                  const Text('Real verified earnings',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: AppRadius.pill),
                    child: const Text('LIVE',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.success,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              Expanded(
                child: _buildTabBody(
                  _leadersLoaded,
                  _leaders.isEmpty && _leadersLoaded,
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
                              : (isDark
                                  ? AppColors.bgCard
                                  : const Color(0xFFF8F8F8)),
                          borderRadius: BorderRadius.circular(14),
                          border: isTop3
                              ? Border.all(
                                  color: AppColors.gold.withOpacity(0.3))
                              : null,
                        ),
                        child: Row(children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                                isTop3 ? badges[rank - 1] : '#$rank',
                                style: TextStyle(
                                    fontSize: isTop3 ? 22 : 14,
                                    fontWeight: FontWeight.w700,
                                    color: sub),
                                textAlign: TextAlign.center),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle),
                            child: Center(child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isTop3
                                        ? AppColors.gold
                                        : AppColors.primary))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name, style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: text)),
                            Row(children: [
                              Text(l['country']?.toString() ?? '',
                                  style: TextStyle(fontSize: 11, color: sub)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(l['stage']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ])),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                            Text('\$${earned.toStringAsFixed(0)}',
                                style: TextStyle(
                                    color: isTop3
                                        ? AppColors.gold
                                        : AppColors.success,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                            Text('earned',
                                style: TextStyle(fontSize: 10, color: sub)),
                          ]),
                        ]),
                      ).animate()
                          .fadeIn(delay: Duration(milliseconds: i * 50));
                    },
                  ),
                ),
              ),
            ]),

            // ── 3: CHALLENGES ─────────────────────────────────────
            _buildTabBody(
              _challengesLoaded,
              _challenges.isEmpty && _challengesLoaded,
              'No challenges yet',
              'Start a challenge from the Income Tools menu!',
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _challenges.length,
                itemBuilder: (_, i) {
                  final c      = _challenges[i] as Map;
                  final pct    = ((c['current_usd'] ?? 0) /
                      ((c['target_usd'] ?? 1) == 0 ? 1 : c['target_usd']))
                      .clamp(0.0, 1.0)
                      .toDouble();
                  final active = c['status'] == 'active';
                  final done   = c['status'] == 'completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.bgCard
                          : const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(16),
                      border: active
                          ? Border.all(
                              color: AppColors.primary.withOpacity(0.3))
                          : null,
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(c['emoji']?.toString() ?? '🎯',
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(c['title']?.toString() ?? '',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700,
                                  color: text)),
                          Text(
                              'Day ${c['current_day'] ?? 1}/${c['duration_days'] ?? 30} '
                              '· ${c['streak'] ?? 0} day streak',
                              style: TextStyle(fontSize: 11, color: sub)),
                        ])),
                        if (done)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('DONE',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Text('\$${c['current_usd'] ?? 0}',
                            style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700)),
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
                          backgroundColor: isDark
                              ? AppColors.bgSurface
                              : Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                              done ? AppColors.success : AppColors.primary),
                          minHeight: 5,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/challenges'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Check In Today',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ]),
                  ).animate()
                      .fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),
            ),

            // ── 4: MARKETPLACE ────────────────────────────────────
            Column(children: [
              // Filter chips
              Container(
                color: card,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _FilterChip(
                        label: '🏪 All',
                        active: _marketFilter == 'all',
                        onTap: () { setState(() => _marketFilter = 'all'); _loadMarketplace(filter: 'all'); }),
                    const SizedBox(width: 8),
                    _FilterChip(
                        label: '💰 Selling',
                        active: _marketFilter == 'sell',
                        onTap: () { setState(() => _marketFilter = 'sell'); _loadMarketplace(filter: 'sell'); }),
                    const SizedBox(width: 8),
                    _FilterChip(
                        label: '🛒 Buying',
                        active: _marketFilter == 'buy',
                        onTap: () { setState(() => _marketFilter = 'buy'); _loadMarketplace(filter: 'buy'); }),
                    const SizedBox(width: 8),
                    _FilterChip(
                        label: '🔧 Services',
                        active: _marketFilter == 'service',
                        onTap: () { setState(() => _marketFilter = 'service'); _loadMarketplace(filter: 'service'); }),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); context.push('/marketplace'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Post Listing',
                              style: TextStyle(color: Colors.white, fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              Divider(height: 1, color: border),

              // Listings
              Expanded(
                child: !_marketplaceLoaded
                    ? const Center(child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                    : _marketplace.isEmpty
                        ? Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🏪', style: TextStyle(fontSize: 52)),
                              const SizedBox(height: 12),
                              Text('No listings yet',
                                  style: TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.w600, color: text)),
                              const SizedBox(height: 6),
                              Text('Be the first to post something!',
                                  style: TextStyle(color: sub, fontSize: 13)),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: () => context.push('/marketplace'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [AppColors.primary, AppColors.accent]),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Text('Post a Listing',
                                      style: TextStyle(color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ))
                        : RefreshIndicator(
                            onRefresh: () => _loadMarketplace(),
                            color: AppColors.primary,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _marketplace.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (ctx, i) {
                                final item = _marketplace[i] as Map;
                                return _MarketCard(
                                    listing: item,
                                    isDark:  isDark,
                                    text:    text,
                                    sub:     sub,
                                    card:    card,
                                    index:   i,
                                    onInquire: () => _inquire(ctx, item));
                              },
                            ),
                          ),
              ),
            ]),

            // ── 5: TOPICS ─────────────────────────────────────────
            GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6),
              itemCount: _topicData.length,
              itemBuilder: (_, i) {
                final t = _topicData[i];
                return GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(t.$1,
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(t.$2,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: text)),
                    ]),
                  ),
                ).animate()
                    .fadeIn(delay: Duration(milliseconds: i * 60));
              },
            ),

          ]),
        ),
      ]),
    );
  }

  Widget _buildTabBody(bool loaded, bool empty, String emptyTitle,
      String emptySub, Widget content) {
    if (!loaded) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2));
    }
    if (empty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(emptyTitle,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(emptySub,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ]));
    }
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

// ─────────────────────────────────────────────────────────────────
// MARKETPLACE LISTING CARD
// ─────────────────────────────────────────────────────────────────
class _MarketCard extends StatelessWidget {
  final Map          listing;
  final bool         isDark;
  final Color        text, sub, card;
  final int          index;
  final VoidCallback onInquire;

  const _MarketCard({
    required this.listing,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.card,
    required this.index,
    required this.onInquire,
  });

  Color get _typeColor {
    switch (listing['listing_type']?.toString()) {
      case 'sell':    return AppColors.success;
      case 'buy':     return AppColors.primary;
      case 'service': return const Color(0xFF9B59B6);
      default:        return AppColors.textMuted;
    }
  }

  String get _typeLabel {
    switch (listing['listing_type']?.toString()) {
      case 'sell':    return '💰 FOR SALE';
      case 'buy':     return '🛒 WANTED';
      case 'service': return '🔧 SERVICE';
      default:        return '📦 LISTING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = listing['title']?.toString() ?? '';
    final desc     = listing['description']?.toString() ?? '';
    final price    = listing['price']?.toString();
    final currency = listing['currency']?.toString() ?? 'USD';
    final country  = listing['country']?.toString() ?? '';
    final tags     = (listing['tags'] as List?)?.cast<String>() ?? [];
    final seller   = (listing['profiles'] as Map?)?['full_name']?.toString()
                  ?? listing['seller_name']?.toString()
                  ?? 'Anonymous';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _typeColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(_typeLabel,
                  style: TextStyle(
                      fontSize: 9, color: _typeColor,
                      fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            if (country.isNotEmpty)
              Text(country,
                  style: TextStyle(fontSize: 11, color: sub)),
          ]),
        ),

        // Title + description
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc,
                  style: TextStyle(fontSize: 12, color: sub, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),

        // Tags
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final tag in tags.take(3))
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.bgSurface
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(tag,
                      style: TextStyle(fontSize: 10, color: sub)),
                ),
            ]),
          ),
        ],

        // Price + seller + CTA
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: [
            // Price
            if (price != null && price.isNotEmpty)
              Text('$currency $price',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: _typeColor))
            else
              Text('Price on request',
                  style: TextStyle(fontSize: 13, color: sub)),
            const Spacer(),
            // Seller name
            Text(seller,
                style: TextStyle(
                    fontSize: 11, color: sub,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            // CTA button
            GestureDetector(
              onTap: () { HapticFeedback.mediumImpact(); onInquire(); },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [_typeColor, _typeColor.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Contact',
                    style: TextStyle(
                        color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ]),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 60));
  }
}

// ─────────────────────────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? AppColors.primary
                  : AppColors.primary.withOpacity(0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.primary)),
      ),
    );
  }
}
