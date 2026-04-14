// frontend/lib/screens/explore/explore_screen.dart
// v4.0 — Facebook-style cache baked in (single file, no separate cache class)
//
// HOW THE CACHE WORKS (everything lives right here, no extra files):
//
//  static Map<String, List>     _cache      ← L1: in-memory, per app session
//  static Map<String, DateTime> _cacheTime  ← tracks when each key was saved
//
//  SharedPreferences (dart:convert + shared_preferences) ← L2: survives restarts
//
//  On initState:
//    1. setState(_applyAllCaches)   — instant render from L1 if same session
//    2. _warmFromDisk()             — restore L1 from SharedPrefs (~5-15ms)
//    3. Background refresh if stale — silent network call, no spinner
//
//  TTLs: Marketplace 10min · Leaderboard 5min · Groups 15min
//        Challenges 10min  · Creators 5min

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';

// ─── cache keys ───────────────────────────────────────────────────
const _kMarket     = 'explore_marketplace';
const _kLeaders    = 'explore_leaderboard';
const _kGroups     = 'explore_groups';
const _kChallenges = 'explore_challenges';
const _kCreators   = 'explore_creators';

const _kTtl = {
  _kMarket:     Duration(minutes: 10),
  _kLeaders:    Duration(minutes:  5),
  _kGroups:     Duration(minutes: 15),
  _kChallenges: Duration(minutes: 10),
  _kCreators:   Duration(minutes:  5),
};

// ─────────────────────────────────────────────────────────────────
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {

  // ══ L1 CACHE — static so it outlives widget rebuilds & tab switches ══
  static final Map<String, List>     _cache     = {};
  static final Map<String, DateTime> _cacheTime = {};

  bool _isCacheStale(String key) {
    final t = _cacheTime[key];
    if (t == null) return true;
    return DateTime.now().difference(t) > (_kTtl[key] ?? const Duration(minutes: 10));
  }

  void _writeCache(String key, List data) {
    _cache[key]     = data;
    _cacheTime[key] = DateTime.now();
    _saveToDisk(key, data); // fire-and-forget, never blocks UI
  }

  // ══ L2 DISK — SharedPreferences, survives app restarts ══════════
  Future<void> _saveToDisk(String key, List data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('ec_$key', jsonEncode(data));
      await p.setInt('ec_ts_$key', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {} // disk failure is silent — L1 still works fine
  }

  Future<void> _warmFromDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      bool restored = false;
      for (final key in _kTtl.keys) {
        if (_cache.containsKey(key)) continue; // already warm this session
        final raw  = p.getString('ec_$key');
        final tsMs = p.getInt('ec_ts_$key');
        if (raw == null || tsMs == null) continue;
        _cache[key]     = jsonDecode(raw) as List;
        _cacheTime[key] = DateTime.fromMillisecondsSinceEpoch(tsMs);
        restored = true;
      }
      if (restored && mounted) setState(_applyAllCaches);
    } catch (_) {}
  }

  void _applyAllCaches() {
    if (_cache[_kMarket]     != null) { _marketplace = _cache[_kMarket]!;     _marketplaceLoaded = true; }
    if (_cache[_kLeaders]    != null) { _leaders     = _cache[_kLeaders]!;    _leadersLoaded     = true; }
    if (_cache[_kGroups]     != null) { _groups      = _cache[_kGroups]!;     _groupsLoaded      = true; }
    if (_cache[_kChallenges] != null) { _challenges  = _cache[_kChallenges]!; _challengesLoaded  = true; }
    if (_cache[_kCreators]   != null) { _creators    = _cache[_kCreators]!;   _creatorsLoaded    = true; }
  }

  // ── Displayed data ────────────────────────────────────────────
  List _creators = [], _groups = [], _leaders = [], _challenges = [], _marketplace = [];
  bool _creatorsLoaded = false, _groupsLoaded = false, _leadersLoaded = false,
       _challengesLoaded = false, _marketplaceLoaded = false;

  // background refresh flags → tiny AppBar spinner, never blocks UI
  bool _creatorsRefreshing = false, _groupsRefreshing = false,
       _leadersRefreshing = false, _challengesRefreshing = false,
       _marketplaceRefreshing = false;

  bool get _anyRefreshing => _marketplaceRefreshing || _leadersRefreshing ||
      _groupsRefreshing || _challengesRefreshing || _creatorsRefreshing;

  late TabController _tabCtrl;
  final _searchCtrl  = TextEditingController();
  String _query      = '';
  bool   _searching  = false;
  String _mFilter    = 'all';

  // ─────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(_onTabChange);

    // 1. Instant render from L1 (same session, zero cost)
    setState(_applyAllCaches);

    // 2. Warm L1 from disk, then kick background refresh for visible tabs
    _warmFromDisk().then((_) {
      if (_isCacheStale(_kMarket))  _fetchMarketplace();
      if (_isCacheStale(_kLeaders)) _fetchLeaderboard();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabCtrl..removeListener(_onTabChange)..dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (!_tabCtrl.indexIsChanging) return;
    switch (_tabCtrl.index) {
      case 0: _loadOrRefresh(_kMarket,     _marketplaceLoaded, _fetchMarketplace); break;
      case 1: _loadOrRefresh(_kLeaders,    _leadersLoaded,     _fetchLeaderboard); break;
      case 2: _loadOrRefresh(_kGroups,     _groupsLoaded,      _fetchGroups);      break;
      case 3: _loadOrRefresh(_kChallenges, _challengesLoaded,  _fetchChallenges);  break;
      case 4: _loadOrRefresh(_kCreators,   _creatorsLoaded,    _fetchCreators);    break;
    }
  }

  void _loadOrRefresh(String key, bool loaded, Future<void> Function() fn) {
    if (!loaded || _isCacheStale(key)) fn();
  }

  // ─────────────────────────────────────────────────────────────
  // FETCHERS
  // ─────────────────────────────────────────────────────────────

  Future<void> _fetchMarketplace({bool force = false}) async {
    if (_marketplaceRefreshing) return;
    if (mounted) setState(() => _marketplaceRefreshing = true);
    try {
      final d = await api.getMarketplaceListings(
        listingType: _mFilter == 'all' ? null : _mFilter,
        search: _query.isNotEmpty ? _query : null, limit: 30,
      );
      final items = (d['listings'] as List?) ?? [];
      if (_mFilter == 'all' && _query.isEmpty) _writeCache(_kMarket, items);
      if (mounted) setState(() { _marketplace = items; _marketplaceLoaded = true; });
    } catch (_) {
      if (mounted && !_marketplaceLoaded) setState(() => _marketplaceLoaded = true);
    } finally {
      if (mounted) setState(() => _marketplaceRefreshing = false);
    }
  }

  Future<void> _fetchLeaderboard({bool force = false}) async {
    if (_leadersRefreshing) return;
    if (mounted) setState(() => _leadersRefreshing = true);
    try {
      final d = await api.get('/progress/leaderboard');
      final items = (d as Map?)?['leaders'] as List? ?? [];
      _writeCache(_kLeaders, items);
      if (mounted) setState(() { _leaders = items; _leadersLoaded = true; });
    } catch (_) {
      if (mounted && !_leadersLoaded) setState(() => _leadersLoaded = true);
    } finally {
      if (mounted) setState(() => _leadersRefreshing = false);
    }
  }

  Future<void> _fetchGroups({bool force = false}) async {
    if (_groupsRefreshing) return;
    if (mounted) setState(() => _groupsRefreshing = true);
    try {
      final d = await api.get('/community/groups');
      final items = ((d as Map?)?['groups'] ?? d) as List? ?? [];
      _writeCache(_kGroups, items);
      if (mounted) setState(() { _groups = items; _groupsLoaded = true; });
    } catch (_) {
      if (mounted && !_groupsLoaded) setState(() => _groupsLoaded = true);
    } finally {
      if (mounted) setState(() => _groupsRefreshing = false);
    }
  }

  Future<void> _fetchChallenges({bool force = false}) async {
    if (_challengesRefreshing) return;
    if (mounted) setState(() => _challengesRefreshing = true);
    try {
      final d = await api.get('/challenges/');
      final items = (d as Map?)?['challenges'] as List? ?? [];
      _writeCache(_kChallenges, items);
      if (mounted) setState(() { _challenges = items; _challengesLoaded = true; });
    } catch (_) {
      if (mounted && !_challengesLoaded) setState(() => _challengesLoaded = true);
    } finally {
      if (mounted) setState(() => _challengesRefreshing = false);
    }
  }

  Future<void> _fetchCreators({bool force = false}) async {
    if (_creatorsRefreshing) return;
    if (mounted) setState(() => _creatorsRefreshing = true);
    try {
      final d = await api.get('/progress/leaderboard');
      final items = (d as Map?)?['leaders'] as List? ?? [];
      _writeCache(_kCreators, items);
      if (mounted) setState(() { _creators = items; _creatorsLoaded = true; });
    } catch (_) {
      if (mounted && !_creatorsLoaded) setState(() => _creatorsLoaded = true);
    } finally {
      if (mounted) setState(() => _creatorsRefreshing = false);
    }
  }

  Future<void> _refreshAll() async {
    HapticFeedback.mediumImpact();
    _cache.clear(); _cacheTime.clear();
    await Future.wait([_fetchMarketplace(force: true), _fetchLeaderboard(force: true)]);
  }

  Future<void> _refreshCurrentTab() async {
    switch (_tabCtrl.index) {
      case 0: _cache.remove(_kMarket);     await _fetchMarketplace(force: true); break;
      case 1: _cache.remove(_kLeaders);    await _fetchLeaderboard(force: true); break;
      case 2: _cache.remove(_kGroups);     await _fetchGroups(force: true);      break;
      case 3: _cache.remove(_kChallenges); await _fetchChallenges(force: true);  break;
      case 4: _cache.remove(_kCreators);   await _fetchCreators(force: true);    break;
    }
  }

  void _onSearchChanged(String v) {
    setState(() { _query = v; _searching = v.isNotEmpty; });
    if (_tabCtrl.index == 0) _fetchMarketplace();
  }

  // ─────────────────────────────────────────────────────────────
  // INQUIRY SHEET
  // ─────────────────────────────────────────────────────────────

  Future<void> _inquire(BuildContext ctx, Map listing) async {
    final ctrl = TextEditingController();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final confirmed = await showModalBottomSheet<bool>(
      context: ctx, isScrollControlled: true,
      backgroundColor: isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (s) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(s).viewInsets.bottom,
            left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
          Text('Contact about: ${listing['title'] ?? 'Listing'}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          TextField(controller: ctrl, maxLines: 4, autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Write your message or offer…',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              filled: true, fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(s, true),
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
              content: Text('Message sent! 🎉'), backgroundColor: AppColors.success,
              duration: Duration(seconds: 2)));
          adManager.showInterstitial();
        }
      } catch (_) {
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Failed to send. Try again.'), backgroundColor: AppColors.error));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

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
      bottomNavigationBar: adManager.getStickyBanner(context),
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        title: Text('Explore',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
        actions: [
          // Tiny spinner — only shown during background refresh, never blocks UI
          if (_anyRefreshing)
            Padding(padding: const EdgeInsets.only(right: 4),
              child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: sub, strokeWidth: 1.5))),
          IconButton(icon: Icon(Iconsax.refresh, color: sub, size: 20),
              onPressed: _refreshAll),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: Column(children: [

        // ── Search ─────────────────────────────────────────────
        Container(color: card, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 14, color: text),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search creators, groups, marketplace…',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled: true, fillColor: surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: sub, size: 18),
              suffixIcon: _searching ? IconButton(
                  icon: Icon(Icons.close, color: sub, size: 18),
                  onPressed: () => setState(() {
                    _searchCtrl.clear(); _query = ''; _searching = false; })) : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // ── Tabs ───────────────────────────────────────────────
        Container(color: card,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: AppColors.primary, unselectedLabelColor: sub,
            indicatorColor: AppColors.primary, indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            isScrollable: true, tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Marketplace'), Tab(text: 'Leaderboard'),
              Tab(text: 'Groups'),      Tab(text: 'Challenges'),
              Tab(text: 'Creators'),
            ],
          ),
        ),
        Divider(height: 1, color: border),

        Expanded(child: TabBarView(controller: _tabCtrl, children: [

          // ════════════════════════════════════════════════════
          // 0: MARKETPLACE
          // ════════════════════════════════════════════════════
          Column(children: [
            Container(color: card, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip(label: '🏪 All',      active: _mFilter == 'all',
                      onTap: () { setState(() => _mFilter = 'all');     _fetchMarketplace(); }),
                  const SizedBox(width: 8),
                  _FilterChip(label: '💰 Selling',  active: _mFilter == 'sell',
                      onTap: () { setState(() => _mFilter = 'sell');    _fetchMarketplace(); }),
                  const SizedBox(width: 8),
                  _FilterChip(label: '🛒 Buying',   active: _mFilter == 'buy',
                      onTap: () { setState(() => _mFilter = 'buy');     _fetchMarketplace(); }),
                  const SizedBox(width: 8),
                  _FilterChip(label: '🔧 Services', active: _mFilter == 'service',
                      onTap: () { setState(() => _mFilter = 'service'); _fetchMarketplace(); }),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () { HapticFeedback.lightImpact(); context.push('/marketplace'); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, color: Colors.white, size: 14), SizedBox(width: 4),
                        Text('Post Listing', style: TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            Divider(height: 1, color: border),
            Expanded(child: !_marketplaceLoaded
              ? _ShimmerList(isDark: isDark)
              : _marketplace.isEmpty
                  ? _emptyState('🏪', 'No listings yet', 'Be the first to post something!',
                      action: GestureDetector(onTap: () => context.push('/marketplace'),
                          child: _gradientBtn('Post a Listing')))
                  : RefreshIndicator(
                      onRefresh: _refreshCurrentTab, color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: adManager.feedItemCount(_marketplace.length),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, vi) {
                          if (adManager.shouldShowFeedAd(vi)) return _InlineFeedAd(isDark: isDark);
                          final ri = adManager.realPostIndex(vi);
                          if (ri >= _marketplace.length) return const SizedBox.shrink();
                          final item = _marketplace[ri] as Map;
                          return _MarketCard(listing: item, isDark: isDark, text: text,
                              sub: sub, card: card, index: ri,
                              onInquire: () => _inquire(ctx, item));
                        },
                      ),
                    ),
            ),
          ]),

          // ════════════════════════════════════════════════════
          // 1: LEADERBOARD
          // ════════════════════════════════════════════════════
          Column(children: [
            Container(color: card, padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                const Text('Real verified earnings',
                    style: TextStyle(fontSize: 12, color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1),
                      borderRadius: AppRadius.pill),
                  child: const Text('LIVE', style: TextStyle(fontSize: 10,
                      color: AppColors.success, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Expanded(child: _buildTabBody(
              loaded: _leadersLoaded, empty: _leaders.isEmpty && _leadersLoaded,
              emptyTitle: 'No earners yet', emptySub: 'Start earning to appear here!',
              shimmer: _ShimmerList(isDark: isDark),
              child: RefreshIndicator(onRefresh: _refreshCurrentTab, color: AppColors.primary,
                child: ListView.builder(
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
                        border: isTop3
                            ? Border.all(color: AppColors.gold.withOpacity(0.3)) : null,
                      ),
                      child: Row(children: [
                        SizedBox(width: 36,
                          child: Text(isTop3 ? badges[rank - 1] : '#$rank',
                              style: TextStyle(fontSize: isTop3 ? 22 : 14,
                                  fontWeight: FontWeight.w700, color: sub),
                              textAlign: TextAlign.center)),
                        const SizedBox(width: 10),
                        _UserAvatar(user: l, size: 42, isTop3: isTop3),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name, style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w700, color: text)),
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
                              style: TextStyle(
                                  color: isTop3 ? AppColors.gold : AppColors.success,
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                          Text('earned', style: TextStyle(fontSize: 10, color: sub)),
                        ]),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                  },
                ),
              ),
            )),
          ]),

          // ════════════════════════════════════════════════════
          // 2: GROUPS
          // ════════════════════════════════════════════════════
          _buildTabBody(
            loaded: _groupsLoaded, empty: _groups.isEmpty && _groupsLoaded,
            emptyTitle: 'No groups yet', emptySub: 'Groups are coming soon!',
            shimmer: _ShimmerList(isDark: isDark),
            child: RefreshIndicator(onRefresh: _refreshCurrentTab, color: AppColors.primary,
              child: ListView.separated(
                padding: const EdgeInsets.all(16), itemCount: _groups.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: border),
                itemBuilder: (_, i) {
                  final g = _groups[i] as Map;
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Container(width: 48, height: 48,
                        decoration: BoxDecoration(
                            color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12)),
                        child: Center(child: Text(g['emoji']?.toString() ?? '💬',
                            style: const TextStyle(fontSize: 22)))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(g['name']?.toString() ?? '', style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: text)),
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
                                style: const TextStyle(fontSize: 9,
                                    color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ])),
                      GestureDetector(onTap: () => context.go('/groups'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('Join', style: TextStyle(color: Colors.white,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                        )),
                    ]),
                  );
                },
              ),
            ),
          ),

          // ════════════════════════════════════════════════════
          // 3: CHALLENGES
          // ════════════════════════════════════════════════════
          _buildTabBody(
            loaded: _challengesLoaded, empty: _challenges.isEmpty && _challengesLoaded,
            emptyTitle: 'No challenges yet',
            emptySub: 'Start a challenge from the Income Tools menu!',
            shimmer: _ShimmerList(isDark: isDark),
            child: RefreshIndicator(onRefresh: _refreshCurrentTab, color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: _challenges.length,
                itemBuilder: (_, i) {
                  final c   = _challenges[i] as Map;
                  final pct = ((c['current_usd'] ?? 0) /
                          ((c['target_usd'] ?? 1) == 0 ? 1 : c['target_usd']))
                      .clamp(0.0, 1.0).toDouble();
                  final active = c['status'] == 'active';
                  final done   = c['status'] == 'completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(16),
                      border: active ? Border.all(
                          color: AppColors.primary.withOpacity(0.3)) : null,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(c['emoji']?.toString() ?? '🎯',
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(c['title']?.toString() ?? '', style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                          Text('Day ${c['current_day'] ?? 1}/${c['duration_days'] ?? 30}'
                              ' · ${c['streak'] ?? 0} day streak',
                              style: TextStyle(fontSize: 11, color: sub)),
                        ])),
                        if (done) Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Text('DONE', style: TextStyle(fontSize: 10,
                              color: AppColors.success, fontWeight: FontWeight.w700)),
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
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: pct,
                          backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                              done ? AppColors.success : AppColors.primary),
                          minHeight: 5)),
                      if (active) ...[
                        const SizedBox(height: 10),
                        GestureDetector(onTap: () => context.push('/challenges'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(20)),
                            child: const Text('Check In Today', style: TextStyle(
                                color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                          )),
                      ],
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),
            ),
          ),

          // ════════════════════════════════════════════════════
          // 4: CREATORS
          // ════════════════════════════════════════════════════
          _buildTabBody(
            loaded: _creatorsLoaded, empty: _creators.isEmpty && _creatorsLoaded,
            emptyTitle: 'No top earners yet', emptySub: 'Start earning to appear here!',
            shimmer: _ShimmerList(isDark: isDark),
            child: RefreshIndicator(onRefresh: _refreshCurrentTab, color: AppColors.primary,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: adManager.feedItemCount(_creators.length),
                separatorBuilder: (_, __) => Divider(height: 16, color: border),
                itemBuilder: (_, vi) {
                  if (adManager.shouldShowFeedAd(vi)) return _InlineFeedAd(isDark: isDark);
                  final ri = adManager.realPostIndex(vi);
                  if (ri >= _creators.length) return const SizedBox.shrink();
                  final c      = _creators[ri] as Map;
                  final name   = c['full_name']?.toString() ?? 'User';
                  final earned = (c['total_earned'] as num?)?.toDouble() ?? 0;
                  return Row(children: [
                    _UserAvatar(user: c, size: 50),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name, style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: text)),
                      Text(c['country']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, color: sub)),
                      Text('Stage: ${c['stage'] ?? 'survival'}',
                          style: TextStyle(fontSize: 12, color: sub)),
                      Text('\$${earned.toStringAsFixed(0)} earned',
                          style: const TextStyle(fontSize: 11,
                              color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ])),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (c['id'] != null) context.push('/user-profile/${c['id']}');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('View', style: TextStyle(color: Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]).animate().fadeIn(delay: Duration(milliseconds: ri * 60));
                },
              ),
            ),
          ),

        ])),
      ]),
    );
  }

  // ── helpers ───────────────────────────────────────────────────

  Widget _buildTabBody({
    required bool loaded, required bool empty,
    required String emptyTitle, required String emptySub,
    required Widget child, Widget? shimmer,
  }) {
    if (!loaded) return shimmer ?? const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    if (empty)  return _emptyState('🔍', emptyTitle, emptySub);
    return child;
  }

  Widget _emptyState(String emoji, String title, String sub, {Widget? action}) =>
    Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(emoji, style: const TextStyle(fontSize: 52)),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(sub, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      if (action != null) ...[const SizedBox(height: 20), action],
    ]));

  Widget _gradientBtn(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
  );
}

// ─────────────────────────────────────────────────────────────────
// SHIMMER — shown only on very first cold launch before any cache
// ─────────────────────────────────────────────────────────────────

class _ShimmerList extends StatefulWidget {
  final bool isDark;
  const _ShimmerList({required this.isDark});
  @override
  State<_ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<_ShimmerList>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) {
      final t = Tween<double>(begin: -1.5, end: 1.5)
          .evaluate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
      final base = widget.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEEEEEE);
      final hi   = widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
      return ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(begin: Alignment(t - 1, 0), end: Alignment(t, 0),
                colors: [base, hi, base]),
          ),
          child: Padding(padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(height: 12, width: 130,
                    decoration: BoxDecoration(color: base,
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 10, width: 80,
                    decoration: BoxDecoration(color: base,
                        borderRadius: BorderRadius.circular(6))),
              ])),
              Container(width: 52, height: 30,
                  decoration: BoxDecoration(color: base,
                      borderRadius: BorderRadius.circular(16))),
            ]),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────
// USER AVATAR — real uploaded image with initials fallback
// ─────────────────────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final Map user; final double size; final bool isTop3;
  const _UserAvatar({required this.user, required this.size, this.isTop3 = false});

  String? get _url {
    for (final k in const ['avatar_url','profile_picture','profile_image','avatar']) {
      final v = user[k]?.toString();
      if (v != null && v.isNotEmpty && v.startsWith('http')) return v;
    }
    return null;
  }

  String get _initials {
    final name = user['full_name']?.toString() ?? '';
    if (name.isEmpty) return '?';
    final p = name.trim().split(RegExp(r'\s+'));
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}'.toUpperCase() : p[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ph = _Initials(initials: _initials, size: size, isTop3: isTop3);
    final url = _url;
    if (url == null) return ph;
    return ClipOval(child: Image.network(url, width: size, height: size, fit: BoxFit.cover,
        loadingBuilder: (_, c, p) => p == null ? c : ph,
        errorBuilder: (_, __, ___) => ph));
  }
}

class _Initials extends StatelessWidget {
  final String initials; final double size; final bool isTop3;
  const _Initials({required this.initials, required this.size, this.isTop3 = false});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: isTop3
            ? const [Color(0xFFFFD700), Color(0xFFFF8C00)]
            : const [Color(0xFFFF6B00), Color(0xFF6C5CE7)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: Center(child: Text(initials, style: TextStyle(fontSize: size * 0.38,
        fontWeight: FontWeight.w800, color: Colors.white))),
  );
}

// ─────────────────────────────────────────────────────────────────
// INLINE FEED AD
// ─────────────────────────────────────────────────────────────────

class _InlineFeedAd extends StatelessWidget {
  final bool isDark;
  const _InlineFeedAd({required this.isDark});
  @override
  Widget build(BuildContext context) {
    final ad = adManager.getBannerWidget();
    if (ad is SizedBox) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard.withOpacity(0.6) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text('Sponsored', style: TextStyle(fontSize: 9, letterSpacing: 0.4,
                color: isDark ? Colors.white30 : Colors.black26))),
          ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: ad),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// MARKETPLACE CARD
// ─────────────────────────────────────────────────────────────────

class _MarketCard extends StatelessWidget {
  final Map listing; final bool isDark;
  final Color text, sub, card; final int index;
  final VoidCallback onInquire;
  const _MarketCard({required this.listing, required this.isDark,
      required this.text, required this.sub, required this.card,
      required this.index, required this.onInquire});

  Color get _tc { switch (listing['listing_type']?.toString()) {
    case 'sell': return AppColors.success; case 'buy': return AppColors.primary;
    case 'service': return const Color(0xFF9B59B6); default: return AppColors.textMuted; }}

  String get _tl { switch (listing['listing_type']?.toString()) {
    case 'sell': return '💰 FOR SALE'; case 'buy': return '🛒 WANTED';
    case 'service': return '🔧 SERVICE'; default: return '📦 LISTING'; }}

  @override
  Widget build(BuildContext context) {
    final title    = listing['title']?.toString() ?? '';
    final desc     = listing['description']?.toString() ?? '';
    final price    = listing['price']?.toString();
    final currency = listing['currency']?.toString() ?? 'USD';
    final country  = listing['country']?.toString() ?? '';
    final tags     = (listing['tags'] as List?)?.cast<String>() ?? [];
    final seller   = (listing['profiles'] as Map?)?['full_name']?.toString()
                  ?? listing['seller_name']?.toString() ?? 'Anonymous';
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _tc.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _tc.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(_tl, style: TextStyle(fontSize: 9, color: _tc,
                  fontWeight: FontWeight.w700))),
            const Spacer(),
            if (country.isNotEmpty) Text(country, style: TextStyle(fontSize: 11, color: sub)),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 12, color: sub, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis)],
          ])),
        if (tags.isNotEmpty) ...[const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final tag in tags.take(3))
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(tag, style: TextStyle(fontSize: 10, color: sub))),
            ]))],
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: [
            if (price != null && price.isNotEmpty)
              Text('$currency $price', style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: _tc))
            else Text('Price on request', style: TextStyle(fontSize: 13, color: sub)),
            const Spacer(),
            Text(seller, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () { HapticFeedback.mediumImpact(); onInquire(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_tc, _tc.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(20)),
                child: const Text('Contact', style: TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w700)),
              )),
          ])),
      ]),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 60));
  }
}

// ─────────────────────────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? AppColors.primary : AppColors.primary.withOpacity(0.2))),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.primary)),
    ),
  );
}
