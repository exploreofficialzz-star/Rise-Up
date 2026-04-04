// frontend/lib/screens/profile/user_profile_screen.dart
// v3.0 — Cached, Instant-Load, Rich Feed (matches HomeScreen quality)
//
// ARCHITECTURE (mirrors profile_screen.dart v4.0):
//  · Per-user cache key  → riseup_user_profile_{userId}_v2
//  · _restoreCache()     → instantaneous display on first paint
//  · _silentRefresh()    → background fetch, no loading flash
//  · AutomaticKeepAliveClientMixin on _UserPostsTab → tab survives switching
//  · PostCard / PostModel from home_screen.dart → full rich feed
//  · Skeleton shimmer (_USh) for header + posts when no cache
//  · kIsWeb guard for ads and Platform.isAndroid

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart' show PostModel, PostCard, videoPreloadManager;

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer building block
// ─────────────────────────────────────────────────────────────────────────────
class _USh extends StatelessWidget {
  const _USh({this.w, required this.h, this.r = 8, this.circle = false});
  final double? w;
  final double  h, r;
  final bool    circle;

  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color:        dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
        borderRadius: circle ? null : BorderRadius.circular(r),
        shape:        circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          color: dark ? Colors.white10 : Colors.white70,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable SliverAppBar skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _UserHeaderSkeleton extends StatelessWidget {
  final bool  isDark;
  final Color card;
  final bool  isTablet;
  // FIX #2: added super.key so callers can pass key: ValueKey('sk')
  const _UserHeaderSkeleton({
    super.key,
    required this.isDark,
    required this.card,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext ctx) {
    final sw = MediaQuery.of(ctx).size.width;
    return Container(
      color:   card,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar + name row
        Row(children: [
          _USh(w: isTablet ? 100 : 80, h: isTablet ? 100 : 80, circle: true),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _USh(w: sw * .35, h: 16),
            const SizedBox(height: 6),
            const _USh(w: 80, h: 22, r: 12),
            const SizedBox(height: 6),
            _USh(w: sw * .28, h: 12),
          ])),
        ]),
        const SizedBox(height: 20),
        // Stats row
        Row(children: const [
          _StatS(), SizedBox(width: 20),
          _StatS(), SizedBox(width: 20),
          _StatS(),
        ]),
        const SizedBox(height: 16),
        // Follow / Message buttons
        Row(children: const [
          Expanded(child: _USh(h: 44, r: 12)),
          SizedBox(width: 10),
          Expanded(child: _USh(h: 44, r: 12)),
        ]),
        const SizedBox(height: 14),
        const _USh(h: 13),
        const SizedBox(height: 4),
        _USh(w: sw * .55, h: 13),
        const SizedBox(height: 10),
      ]),
    );
  }
}

class _StatS extends StatelessWidget {
  const _StatS();
  @override
  Widget build(BuildContext _) => Column(children: const [
        _USh(w: 36, h: 16, r: 4),
        SizedBox(height: 4),
        _USh(w: 48, h: 11, r: 4),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Post card skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _UserPostSkeleton extends StatelessWidget {
  final bool isDark;
  const _UserPostSkeleton({required this.isDark});

  @override
  Widget build(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    return Container(
      color:   isDark ? AppColors.bgCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _USh(w: 44, h: 44, circle: true),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _USh(w: w * .35, h: 13),
            const SizedBox(height: 5),
            _USh(w: w * .25, h: 11),
          ])),
          const _USh(w: 60, h: 26, r: 13),
        ]),
        const SizedBox(height: 14),
        const _USh(h: 13),
        const SizedBox(height: 6),
        const _USh(h: 13),
        const SizedBox(height: 6),
        _USh(w: w * .55, h: 13),
        const SizedBox(height: 12),
        AspectRatio(aspectRatio: 16 / 9,
            child: _USh(h: double.infinity, r: 12)),
        const SizedBox(height: 14),
        Row(children: const [
          _USh(w: 55, h: 18, r: 9), SizedBox(width: 18),
          _USh(w: 55, h: 18, r: 9), SizedBox(width: 18),
          _USh(w: 55, h: 18, r: 9), Spacer(),
          _USh(w: 22, h: 22, r: 11),
        ]),
        const SizedBox(height: 12),
        Row(children: const [
          Expanded(child: _USh(h: 36, r: 10)),
          SizedBox(width: 8),
          Expanded(child: _USh(h: 36, r: 10)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UserProfileScreen
// ─────────────────────────────────────────────────────────────────────────────
class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {

  // Per-user cache keys (capped at last 15 profiles by TTL approach)
  String get _kProfile => 'riseup_user_profile_${widget.userId}_v2';
  String get _kPosts   => 'riseup_user_posts_${widget.userId}_v2';

  late TabController _tabs;

  Map<String, dynamic> _profile   = {};
  Map<String, dynamic> _stats     = {};
  List<PostModel>      _posts     = [];

  bool _loading    = true;   // true = no cache → shows skeleton
  bool _refreshing = false;  // silent background refresh

  bool _isFollowing   = false;
  bool _isOwnProfile  = false;
  bool _followLoading = false;
  bool _isPremium     = false;

  String            _currentUserId = '';
  Map<String, bool> _followState   = {};

  BannerAd? _bannerAd;
  bool      _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _restoreCache();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // ── Step 1: instant cache restore ─────────────────────────────────────
  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Profile
      final pStr = prefs.getString(_kProfile);
      if (pStr != null) {
        final d = Map<String, dynamic>.from(jsonDecode(pStr) as Map);
        if (mounted) {
          setState(() {
            _profile     = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
            _stats       = (d['stats']   as Map?)?.cast<String, dynamic>() ?? {};
            _isFollowing = d['is_following'] == true;
            _isPremium   = _profile['subscription_tier'] == 'premium';
            _loading     = false;
          });
        }
      }

      // Posts
      final postsStr = prefs.getString(_kPosts);
      if (postsStr != null) {
        final list = (jsonDecode(postsStr) as List)
            .map((x) => PostModel.fromApi(Map<String, dynamic>.from(x as Map)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() {
            _posts = list;
            final fw = <String, bool>{};
            for (final p in list) {
              if (p.userId.isNotEmpty) fw[p.userId] = p.isFollowing;
            }
            _followState = fw;
          });
          _preloadVideos(list);
        }
      }
    } catch (_) {}

    _loadAd();
  }

  // ── Step 2: silent background fetch ────────────────────────────────────
  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    if (mounted) setState(() => _refreshing = true);
    await _fetchAndApply();
  }

  Future<void> _pullRefresh() => _fetchAndApply();

  Future<void> _fetchAndApply() async {
    try {
      final myId       = await api.getUserId() ?? '';
      _currentUserId   = myId;
      _isOwnProfile    = myId == widget.userId;

      if (widget.userId.isEmpty) throw Exception('Invalid user ID');

      final results = await Future.wait([
        api.getUserProfile(widget.userId),
        api.getUserPosts(widget.userId),
      ]);

      final d      = results[0] as Map? ?? {};
      final prof   = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      final stats  = (d['stats']   as Map?)?.cast<String, dynamic>() ?? {};
      final posts  = ((results[1] as Map?)?['posts'] as List? ?? [])
          .map((x) => PostModel.fromApi(x as Map<String, dynamic>))
          .toList();

      final fw = <String, bool>{};
      for (final p in posts) {
        if (p.userId.isNotEmpty) fw[p.userId] = p.isFollowing;
      }

      if (mounted) {
        setState(() {
          _profile     = prof;
          _stats       = stats;
          _isFollowing = d['is_following'] == true;
          _posts       = posts;
          _followState = fw;
          _isPremium   = prof['subscription_tier'] == 'premium';
          _loading     = false;
          _refreshing  = false;
        });
        _preloadVideos(posts);
      }

      // Persist
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kProfile, jsonEncode({
          'profile':      prof,
          'stats':        stats,
          'is_following': d['is_following'],
        })),
        prefs.setString(_kPosts,
            jsonEncode((results[1] as Map?)?['posts']?.take(40).toList() ?? [])),
      ]);

      if (!_isPremium) _loadAd();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  void _preloadVideos(List<PostModel> posts) {
    for (int i = 0; i < posts.length && i < 5; i++) {
      final p = posts[i];
      if (p.mediaType == 'video' && (p.mediaUrl ?? '').isNotEmpty) {
        videoPreloadManager.preload(p.mediaUrl!);
      }
    }
  }

  Future<void> _loadAd() async {
    if (_isPremium || kIsWeb) return;
    try {
      final ad = BannerAd(
        adUnitId: Platform.isAndroid
            ? AppConstants.androidBannerAdUnitId
            : AppConstants.iosBannerAdUnitId,
        size:    AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() { _bannerAd = ad as BannerAd; _isAdLoaded = true; });
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) setState(() => _isAdLoaded = false);
          },
        ),
      );
      await ad.load();
    } catch (_) {}
  }

  // ── Follow / Message ────────────────────────────────────────────────────
  Future<void> _toggleFollow() async {
    if (_followLoading || _isOwnProfile) return;
    setState(() => _followLoading = true);
    try {
      final r = await api.toggleFollow(widget.userId);
      final following = r['following'] == true;
      if (mounted) {
        setState(() {
          _isFollowing   = following;
          _followLoading = false;
          final c = (_stats['followers'] as int? ?? 0);
          _stats  = {..._stats, 'followers': following ? c + 1 : (c - 1).clamp(0, 999999)};
        });
        HapticFeedback.lightImpact();
        _snack(following ? 'Now following' : 'Unfollowed', isError: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _followLoading = false);
        _snack('Failed to update', isError: true);
      }
    }
  }

  Future<void> _sendMessage() async {
    try {
      final r      = await api.getOrCreateConversation(widget.userId);
      final convId = r['conversation_id']?.toString() ?? r['id']?.toString();
      if (convId != null && mounted) {
        final name   = _profile['full_name']?.toString() ?? 'User';
        final avatar = _profile['avatar_url']?.toString() ?? '';
        context.push(
          '/conversation/$convId'
          '?name=${Uri.encodeComponent(name)}'
          '&avatar=${Uri.encodeComponent(avatar)}',
        );
      }
    } catch (_) {
      if (mounted) _snack('Could not open messages', isError: true);
    }
  }

  void _shareProfile() {
    Clipboard.setData(ClipboardData(
        text: 'riseup.app/u/${widget.userId}'));
    _snack('Link copied', isError: false);
  }

  // ── Post callbacks ──────────────────────────────────────────────────────
  Future<void> _onLike(PostModel post) async {
    HapticFeedback.mediumImpact();
    setState(() {
      post.isLiked = !post.isLiked;
      post.likes  += post.isLiked ? 1 : -1;
    });
    try {
      final r = await api.toggleLike(post.id);
      if (mounted) setState(() => post.isLiked = r['liked'] == true);
    } catch (_) {
      if (mounted) setState(() {
        post.isLiked = !post.isLiked;
        post.likes  += post.isLiked ? 1 : -1;
      });
    }
  }

  Future<void> _onSave(PostModel post) async {
    setState(() => post.isSaved = !post.isSaved);
    try {
      final r = await api.toggleSave(post.id);
      if (mounted) setState(() => post.isSaved = r['saved'] == true);
    } catch (_) {
      if (mounted) setState(() => post.isSaved = !post.isSaved);
    }
  }

  void _onComment(PostModel post) {
    context.push('/comments/${post.id}'
        '?content=${Uri.encodeComponent(post.content)}'
        '&author=${Uri.encodeComponent(post.name)}');
  }

  void _onShare(PostModel post) {
    HapticFeedback.mediumImpact();
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: dark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Share Post', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: dark ? Colors.white : Colors.black87)),
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.link_rounded, color: AppColors.primary, size: 20)),
            title: Text('Copy post link',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(
                  text: 'https://riseup.app/post/${post.id}'));
              _snack('Link copied', isError: false);
            },
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.copy_rounded, color: Colors.blue, size: 20)),
            title: Text('Copy text',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: post.content));
              _snack('Copied', isError: false);
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    api.sharePost(post.id).catchError((_) {
      if (mounted) setState(() => post.shares = (post.shares - 1).clamp(0, 999999));
    });
  }

  void _onAskAI(PostModel post) {
    context.push(
      '/conversation/ai'
      '?name=${Uri.encodeComponent("RiseUp AI")}'
      '&avatar=${Uri.encodeComponent("AI")}'
      '&isAI=true'
      '&postContext=${Uri.encodeComponent(post.content)}'
      '&postAuthor=${Uri.encodeComponent(post.name)}',
    );
  }

  void _onPrivateChat(PostModel post) {
    context.push(
      '/conversation/ai'
      '?name=${Uri.encodeComponent("RiseUp AI")}'
      '&avatar=${Uri.encodeComponent("AI")}'
      '&isAI=true'
      '&postContext=${Uri.encodeComponent(post.content)}',
    );
  }

  Future<void> _onFollow(String uid) async {
    if (uid.isEmpty) return;
    final prev = _followState[uid] ?? false;
    setState(() { _followState[uid] = !prev; _syncFollow(uid, !prev); });
    try {
      final r = await api.toggleFollow(uid);
      final v = r['following'] == true;
      if (mounted) setState(() { _followState[uid] = v; _syncFollow(uid, v); });
    } catch (_) {
      if (mounted) setState(() { _followState[uid] = prev; _syncFollow(uid, prev); });
    }
  }

  void _syncFollow(String uid, bool v) {
    for (final p in _posts) { if (p.userId == uid) p.isFollowing = v; }
  }

  void _onPostDeleted(String id) {
    if (!mounted) return;
    setState(() => _posts.removeWhere((p) => p.id == id));
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  String _fmt(dynamic n) {
    final c = (n as num?)?.toInt() ?? 0;
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000)    return '${(c / 1000).toStringAsFixed(1)}K';
    return '$c';
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt   = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours   < 24) return '${diff.inHours}h';
    if (diff.inDays    < 7 ) return '${diff.inDays}d';
    if (diff.inDays    < 30) return '${(diff.inDays / 7).floor()}w';
    return DateFormat.yMMMd().format(dt);
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    if (isError) HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle,
            color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: Duration(seconds: isError ? 3 : 2),
    ));
  }

  String _stageLabel(String stage) {
    const m = {
      'earning':   '💰 Earning',
      'growing':   '📈 Growing',
      'wealth':    '👑 Wealth',
      'survival':  '🌱 Survival',
      'stability': '⚡ Stability',
    };
    return m[stage] ?? '🌱 Survival';
  }

  // ── BUILD ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black : Colors.white;
    final card   = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt    = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white54 : Colors.black45;

    final name    = _profile['full_name']?.toString()    ?? 'User';
    final bio     = _profile['bio']?.toString()          ?? '';
    final status  = _profile['status']?.toString()       ?? '';
    final country = _profile['country']?.toString()      ?? '';
    final stage   = _profile['stage']?.toString()        ?? 'survival';
    final avatar  = _profile['avatar_url']?.toString();
    final earned  = (_profile['total_earned'] as num?)?.toDouble() ?? 0;
    final online  = _profile['is_online'] == true;
    final skills  = (_profile['current_skills'] as List?)?.cast<String>() ?? [];

    final sw       = MediaQuery.of(ctx).size.width;
    final isTablet = sw > 600;

    return Scaffold(
      backgroundColor: bg,
      body: RefreshIndicator(
        onRefresh: _pullRefresh,
        color: AppColors.primary,
        child: CustomScrollView(slivers: [

          // ── Banner ad ─────────────────────────────────────────────────
          if (!_isPremium && _isAdLoaded && _bannerAd != null && !kIsWeb)
            SliverToBoxAdapter(
              child: Container(
                color:   card,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(child: SizedBox(
                  width:  _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child:  AdWidget(ad: _bannerAd!),
                )),
              ),
            ),

          // ── Hero SliverAppBar ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: isTablet ? 320 : 280,
            pinned: true,
            backgroundColor: card,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: txt),
              onPressed: () {
                if (Navigator.of(ctx).canPop()) ctx.pop();
                else ctx.go('/home');
              },
            ),
            actions: [
              // Tiny spinner during silent refresh
              if (_refreshing)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(child: SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.primary.withOpacity(0.55),
                      ))),
                ),
              IconButton(
                icon: Icon(Icons.ios_share_rounded, color: txt, size: 20),
                onPressed: _shareProfile,
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: txt, size: 20),
                onPressed: () => _showMoreSheet(isDark, txt, sub),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _loading
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4)),
                            (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFD0D0D0)),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                _USh(w: isTablet ? 100 : 80,
                                     h: isTablet ? 100 : 80, circle: true),
                                const SizedBox(width: 16),
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                  _USh(w: 140, h: 16),
                                  SizedBox(height: 6),
                                  _USh(w: 80, h: 22, r: 12),
                                  SizedBox(height: 6),
                                  _USh(w: 100, h: 12),
                                ])),
                              ]),
                              const SizedBox(height: 20),
                              Row(children: const [
                                _StatS(), SizedBox(width: 20),
                                _StatS(), SizedBox(width: 20),
                                _StatS(),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.8),
                            AppColors.accent.withOpacity(0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Stack(children: [
                                  Hero(
                                    tag: 'avatar-${widget.userId}',
                                    child: Container(
                                      width:  isTablet ? 100 : 80,
                                      height: isTablet ? 100 : 80,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 3),
                                        boxShadow: [BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )],
                                      ),
                                      child: ClipOval(
                                        child: avatar != null && avatar.isNotEmpty
                                            // FIX #1: errorBuilder → errorWidget
                                            // (cached_network_image 3.4.x uses errorWidget,
                                            //  not errorBuilder)
                                            ? CachedNetworkImage(
                                                imageUrl: avatar,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) =>
                                                    _avatarFallback(name))
                                            : _avatarFallback(name),
                                      ),
                                    ),
                                  ),
                                  if (online)
                                    Positioned(
                                      bottom: 2, right: 2,
                                      child: Container(
                                        width: 18, height: 18,
                                        decoration: BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                ]),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Flexible(
                                        child: Text(name,
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(_stageLabel(stage),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ]),
                                    const SizedBox(height: 4),
                                    if (status.isNotEmpty)
                                      Text(status,
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    if (country.isNotEmpty)
                                      Row(children: [
                                        const Icon(Iconsax.location,
                                            size: 12, color: Colors.white60),
                                        const SizedBox(width: 4),
                                        Text(country,
                                            style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11)),
                                      ]),
                                  ]),
                                ),
                              ]),
                              const SizedBox(height: 16),
                              Row(children: [
                                _StatChip(_fmt(_stats['posts']),
                                    'Posts', Colors.white),
                                const SizedBox(width: 20),
                                _StatChip(_fmt(_stats['followers']),
                                    'Followers', Colors.white),
                                const SizedBox(width: 20),
                                _StatChip(_fmt(_stats['following']),
                                    'Following', Colors.white),
                                const Spacer(),
                                if (earned > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppColors.gold.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                      const Icon(Iconsax.dollar_circle,
                                          size: 12, color: AppColors.gold),
                                      const SizedBox(width: 4),
                                      Text('${_fmt(earned.toInt())} earned',
                                          style: const TextStyle(
                                              color: AppColors.gold, fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // ── Profile body ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _loading
                  ? _UserHeaderSkeleton(
                      key: const ValueKey('sk'),
                      isDark: isDark, card: card, isTablet: isTablet)
                  : _buildProfileBody(
                      key: const ValueKey('body'),
                      isDark: isDark, card: card, border: border,
                      txt: txt, sub: sub, bio: bio, skills: skills),
            ),
          ),

          // ── Upgrade banner ─────────────────────────────────────────────
          if (!_isPremium)
            SliverToBoxAdapter(
              child: Container(
                color:   card,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: _buildUpgradeBanner(),
              ),
            ),

          // ── Tab bar ────────────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabDelegate(
              TabBar(
                controller: _tabs,
                labelColor: AppColors.primary,
                unselectedLabelColor: sub,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(icon: Icon(Iconsax.grid_1, size: 20)),
                  Tab(icon: Icon(Iconsax.heart, size: 20)),
                ],
              ),
              card, border,
            ),
          ),

          // ── Posts / Liked ──────────────────────────────────────────────
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabs,
              children: [
                _UserPostsTab(
                  key: PageStorageKey('posts_${widget.userId}'),
                  posts: _posts, isLoading: _loading,
                  isDark: isDark, cardColor: card,
                  borderColor: border, textColor: txt, subColor: sub,
                  isPremium: _isPremium, aiRemaining: 3,
                  currentUserId: _currentUserId,
                  followState: _followState,
                  onLike: _onLike, onSave: _onSave, onComment: _onComment,
                  onShare: _onShare, onAskAI: _onAskAI,
                  onPrivateChat: _onPrivateChat, onFollow: _onFollow,
                  onPostDeleted: _onPostDeleted,
                ),
                // Liked posts private for other users
                Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Text('❤️',
                        style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('Liked posts are private',
                        style: TextStyle(color: sub, fontSize: 14)),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildProfileBody({
    required bool isDark, required Color card, required Color border,
    required Color txt, required Color sub,
    required String bio, required List<String> skills, Key? key,
  }) =>
      Container(
        key:     key,
        color:   card,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Follow / Message / Edit buttons
          if (!_isOwnProfile)
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _toggleFollow,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color:        _isFollowing ? Colors.transparent : AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      border: _isFollowing
                          ? Border.all(color: isDark
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300)
                          : null,
                    ),
                    child: Center(
                      child: _followLoading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                _isFollowing
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                color: _isFollowing
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isFollowing ? 'Following' : 'Follow',
                                style: TextStyle(
                                  color: _isFollowing
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 13,
                                ),
                              ),
                            ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.12)
                              : Colors.grey.shade300),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Iconsax.message, size: 16,
                          color: isDark ? Colors.white : Colors.black87),
                      const SizedBox(width: 5),
                      Text('Message',
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ])
          else
            GestureDetector(
              onTap: () => context.push('/edit-profile'),
              child: Container(
                width:   double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.grey.shade300),
                ),
                child: const Center(
                  child: Text('Edit Profile',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),

          const SizedBox(height: 14),

          if (bio.isNotEmpty) ...[
            _BioText(bio: bio, textColor: txt),
            const SizedBox(height: 10),
          ],

          if (skills.isNotEmpty) ...[
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: skills.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(skills[i],
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
        ]),
      );

  Widget _buildUpgradeBanner() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.workspace_premium,
                color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Remove Ads & Unlock Features',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
              Text('Upgrade to Pro for an ad-free experience',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
          ElevatedButton(
            onPressed: () => context.go('/premium'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Upgrade', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _avatarFallback(String n) => Container(
        color: AppColors.primary.withOpacity(0.15),
        child: Center(
          child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
      );

  void _showMoreSheet(bool isDark, Color txt, Color sub) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 20),
          _moreOpt(Icons.ios_share_rounded, 'Share Profile', sub,
              _shareProfile),
          if (!_isOwnProfile) ...[
            _moreOpt(Icons.block_rounded, 'Block User', Colors.red, () {
              Navigator.pop(context);
              _showBlockDlg();
            }),
            _moreOpt(Icons.flag_rounded, 'Report User', Colors.orange, () {
              Navigator.pop(context);
              _showReportSheet();
            }),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _moreOpt(IconData icon, String label, Color color,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(14),
          margin:  const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
      );

  void _showBlockDlg() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Block User?'),
          content: const Text(
              "You won't see posts or messages from this user."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _snack('User blocked', isError: false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Block',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  void _showReportSheet() {
    final reasons = [
      'Spam', 'Harassment',
      'Inappropriate content', 'Fake account', 'Other',
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Report User',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ...reasons.map((r) => ListTile(
              title: Text(r),
              onTap: () {
                Navigator.pop(context);
                _snack('Report submitted', isError: false);
              },
            )),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User posts tab  (AutomaticKeepAliveClientMixin)
// ─────────────────────────────────────────────────────────────────────────────
class _UserPostsTab extends StatefulWidget {
  final List<PostModel>     posts;
  final bool                isLoading, isDark, isPremium;
  final Color               cardColor, borderColor, textColor, subColor;
  final int                 aiRemaining;
  final String              currentUserId;
  final Map<String, bool>   followState;
  final Function(PostModel) onLike, onSave, onComment, onShare,
                             onAskAI, onPrivateChat;
  final Function(String)    onFollow, onPostDeleted;

  const _UserPostsTab({
    super.key,
    required this.posts,         required this.isLoading,
    required this.isDark,        required this.cardColor,
    required this.borderColor,   required this.textColor,
    required this.subColor,      required this.isPremium,
    required this.aiRemaining,   required this.currentUserId,
    required this.followState,   required this.onLike,
    required this.onSave,        required this.onComment,
    required this.onShare,       required this.onAskAI,
    required this.onPrivateChat, required this.onFollow,
    required this.onPostDeleted,
  });

  @override
  State<_UserPostsTab> createState() => _UserPostsTabState();
}

class _UserPostsTabState extends State<_UserPostsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _sc = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preloadAhead(0));
  }

  @override
  void didUpdateWidget(_UserPostsTab old) {
    super.didUpdateWidget(old);
    if (old.posts.length != widget.posts.length) _preloadAhead(0);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    const estH = 480.0;
    final idx  = (_sc.position.pixels / estH).floor();
    _preloadAhead(idx + 1);
  }

  void _preloadAhead(int from) {
    final end = (from + 4).clamp(0, widget.posts.length);
    for (int i = from; i < end; i++) {
      final p = widget.posts[i];
      if (p.mediaType == 'video' && (p.mediaUrl ?? '').isNotEmpty) {
        videoPreloadManager.preload(p.mediaUrl!);
      }
    }
  }

  @override
  Widget build(BuildContext ctx) {
    super.build(ctx);

    if (widget.isLoading && widget.posts.isEmpty) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) =>
            Divider(height: 8, thickness: 8, color: widget.borderColor),
        itemBuilder: (_, __) =>
            _UserPostSkeleton(isDark: widget.isDark),
      );
    }

    if (widget.posts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('📝', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No posts yet',
              style: TextStyle(color: widget.subColor, fontSize: 14)),
        ]),
      );
    }

    return ListView.separated(
      controller:  _sc,
      cacheExtent: 2000,
      padding:     EdgeInsets.zero,
      physics:     const AlwaysScrollableScrollPhysics(),
      itemCount:   widget.posts.length,
      separatorBuilder: (_, __) =>
          Divider(height: 8, thickness: 8, color: widget.borderColor),
      itemBuilder: (_, i) {
        final post = widget.posts[i];
        return PostCard(
          key:           ValueKey(post.id),
          post:          post,
          isDark:        widget.isDark,
          cardColor:     widget.cardColor,
          borderColor:   widget.borderColor,
          textColor:     widget.textColor,
          subColor:      widget.subColor,
          onAskAI:       widget.onAskAI,
          onPrivateChat: widget.onPrivateChat,
          onLike:        widget.onLike,
          onSave:        widget.onSave,
          onComment:     widget.onComment,
          onShare:       widget.onShare,
          onFollow:      widget.onFollow,
          onPostDeleted: widget.onPostDeleted,
          isPremium:     widget.isPremium,
          aiRemaining:   widget.aiRemaining,
          isFollowing:   widget.followState[post.userId] ?? post.isFollowing,
          currentUserId: widget.currentUserId,
          needsAd:       false,
        ).animate().fadeIn(
          delay:    Duration(milliseconds: (i % 5) * 20),
          duration: const Duration(milliseconds: 200),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _StatChip(this.value, this.label, this.color);

  @override
  Widget build(BuildContext _) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
      ]);
}

class _BioText extends StatelessWidget {
  final String bio;
  final Color  textColor;
  const _BioText({required this.bio, required this.textColor});

  @override
  Widget build(BuildContext ctx) {
    final urlRe  = RegExp(r'https?://\S+|www\.\S+');
    final matches = urlRe.allMatches(bio);
    if (matches.isEmpty) {
      return Text(bio,
          style: TextStyle(fontSize: 13, color: textColor, height: 1.5));
    }
    final spans = <TextSpan>[];
    int last    = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(
            text:  bio.substring(last, m.start),
            style: TextStyle(
                fontSize: 13, color: textColor, height: 1.5)));
      }
      spans.add(TextSpan(
          text:  bio.substring(m.start, m.end),
          style: const TextStyle(
              fontSize: 13, color: AppColors.primary,
              height: 1.5,
              decoration: TextDecoration.underline)));
      last = m.end;
    }
    if (last < bio.length) {
      spans.add(TextSpan(
          text:  bio.substring(last),
          style: TextStyle(
              fontSize: 13, color: textColor, height: 1.5)));
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color  bg, border;
  const _TabDelegate(this.tabBar, this.bg, this.border);

  @override double get minExtent => tabBar.preferredSize.height + 1;
  @override double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext _, double __, bool ___) => Container(
        color: bg,
        child: Column(children: [tabBar, Divider(height: 1, color: border)]),
      );

  @override
  bool shouldRebuild(_TabDelegate o) => false;
}
