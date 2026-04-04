// frontend/lib/screens/profile/profile_screen.dart
// v4.1 — Production-ready: cached avatar, post-author patch, no "Your Name" flash
//
// FIXES vs v4.0:
//  · AppBar title suppressed until real data loads (no "Your Name" flash)
//  · Avatar uses CachedNetworkImage for instant repeat loads
//  · _patchPostAuthors() fills in real name + avatar on every post
//    where PostModel.name == 'User' / empty and userId matches current user
//  · NOTE: PostModel.name and PostModel.avatarUrl must be non-final (var)
//    in home_screen.dart for the patch to compile.

import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart' show PostModel, PostCard, videoPreloadManager;

// ─────────────────────────────────────────────────────────────────────────────
// Stage helper
// ─────────────────────────────────────────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const map = <String, Map<String, dynamic>>{
      'survival':  {'emoji': '🌱', 'label': 'Survival Mode', 'color': Color(0xFFFF6B35)},
      'earning':   {'emoji': '💰', 'label': 'Earning',        'color': Color(0xFF43E97B)},
      'stability': {'emoji': '⚡', 'label': 'Stability',      'color': Color(0xFF4FACFE)},
      'growing':   {'emoji': '📈', 'label': 'Growing',        'color': Color(0xFF6C63FF)},
      'growth':    {'emoji': '📈', 'label': 'Growing',        'color': Color(0xFF6C63FF)},
      'wealth':    {'emoji': '👑', 'label': 'Wealth',         'color': Color(0xFFFFD700)},
      'legacy':    {'emoji': '🏛️', 'label': 'Legacy',        'color': Color(0xFF9B59B6)},
    };
    return map[stage.toLowerCase()] ?? map['survival']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer building block
// ─────────────────────────────────────────────────────────────────────────────
class _PSh extends StatelessWidget {
  const _PSh({this.w, required this.h, this.r = 8, this.circle = false});
  final double? w;
  final double  h, r;
  final bool    circle;

  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(
      width:  w,
      height: h,
      decoration: BoxDecoration(
        color:        dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
        borderRadius: circle ? null : BorderRadius.circular(r),
        shape:        circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1200.ms,
                 color: dark ? Colors.white10 : Colors.white70);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile header skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileHeaderSkeleton extends StatelessWidget {
  final bool  isDark;
  final Color cardColor;
  final bool  isCompact;

  const _ProfileHeaderSkeleton({
    super.key,
    required this.isDark,
    required this.cardColor,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext ctx) {
    return Container(
      color:   cardColor,
      padding: EdgeInsets.all(isCompact ? 20 : 24),
      child: Column(
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (isCompact)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PSh(w: 76, h: 76, circle: true),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [_StatSkel(), _StatSkel(), _StatSkel()],
                ),
              ),
            ])
          else
            Column(children: [
              const _PSh(w: 100, h: 100, circle: true),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                _StatSkel(), SizedBox(width: 32),
                _StatSkel(), SizedBox(width: 32),
                _StatSkel(),
              ]),
            ]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: isCompact
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: const [
              _PSh(w: 110, h: 14),
              SizedBox(width: 8),
              _PSh(w: 80, h: 20, r: 10),
            ],
          ),
          const SizedBox(height: 10),
          const _PSh(h: 12),
          const SizedBox(height: 4),
          const _PSh(w: 200, h: 12),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: _PSh(h: 36, r: 10)),
            SizedBox(width: 8),
            Expanded(child: _PSh(h: 36, r: 10)),
            SizedBox(width: 8),
            _PSh(w: 58, h: 36, r: 10),
          ]),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: _PSh(h: 58, r: 10)),
            SizedBox(width: 8),
            Expanded(child: _PSh(h: 58, r: 10)),
            SizedBox(width: 8),
            Expanded(child: _PSh(h: 58, r: 10)),
            SizedBox(width: 8),
            Expanded(child: _PSh(h: 58, r: 10)),
          ]),
        ],
      ),
    );
  }
}

class _StatSkel extends StatelessWidget {
  const _StatSkel();
  @override
  Widget build(BuildContext ctx) => Column(children: const [
        _PSh(w: 38, h: 18, r: 4),
        SizedBox(height: 4),
        _PSh(w: 50, h: 11, r: 4),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Post card skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _ProfilePostSkeleton extends StatelessWidget {
  final bool isDark;
  const _ProfilePostSkeleton({required this.isDark});

  @override
  Widget build(BuildContext ctx) {
    final w  = MediaQuery.of(ctx).size.width;
    final bg = isDark ? AppColors.bgCard : Colors.white;
    return Container(
      color:   bg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _PSh(w: 44, h: 44, circle: true),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _PSh(w: w * .35, h: 13),
            const SizedBox(height: 5),
            _PSh(w: w * .25, h: 11),
          ])),
          const _PSh(w: 60, h: 26, r: 13),
        ]),
        const SizedBox(height: 14),
        const _PSh(h: 13),
        const SizedBox(height: 6),
        const _PSh(h: 13),
        const SizedBox(height: 6),
        _PSh(w: w * .55, h: 13),
        const SizedBox(height: 12),
        AspectRatio(aspectRatio: 16 / 9,
            child: _PSh(h: double.infinity, r: 12)),
        const SizedBox(height: 14),
        Row(children: const [
          _PSh(w: 55, h: 18, r: 9), SizedBox(width: 18),
          _PSh(w: 55, h: 18, r: 9), SizedBox(width: 18),
          _PSh(w: 55, h: 18, r: 9),
          Spacer(),
          _PSh(w: 22, h: 22, r: 11),
        ]),
        const SizedBox(height: 12),
        Row(children: const [
          Expanded(child: _PSh(h: 36, r: 10)),
          SizedBox(width: 8),
          Expanded(child: _PSh(h: 36, r: 10)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  static const _kProfile    = 'riseup_my_profile_v2';
  static const _kPosts      = 'riseup_my_posts_v2';
  static const _kLikedPosts = 'riseup_my_liked_v2';
  static const _kQuota      = 'riseup_ai_quota_v1';

  late TabController _tabCtrl;

  Map<String, dynamic> _profile    = {};
  List<PostModel>      _posts      = [];
  List<PostModel>      _likedPosts = [];

  bool _loading    = true;   // no cache yet → show skeleton
  bool _refreshing = false;  // background refresh spinner

  String            _currentUserId = '';
  Map<String, bool> _followState   = {};

  int  _aiUsed  = 0;
  static const int _freeLimit = 3;

  bool      _isPremium  = false;
  BannerAd? _bannerAd;
  bool      _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _restoreCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentRefresh();
  }

  // ── Step 1: instant cache restore ─────────────────────────────────────
  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Profile
      final pStr = prefs.getString(_kProfile);
      if (pStr != null) {
        final p = Map<String, dynamic>.from(jsonDecode(pStr) as Map);
        if (mounted) setState(() {
          _profile   = p;
          _isPremium = p['subscription_tier'] == 'premium' ||
                       p['is_premium'] == true;
          _loading   = false;
        });
      }

      // Posts
      final postsStr = prefs.getString(_kPosts);
      if (postsStr != null) {
        final list = (jsonDecode(postsStr) as List)
            .map((x) => PostModel.fromApi(Map<String, dynamic>.from(x as Map)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() => _posts = list);
          _patchPostAuthors(list, likedList: []);
          _preloadVideos(list);
        }
      }

      // Liked posts
      final likedStr = prefs.getString(_kLikedPosts);
      if (likedStr != null) {
        final list = (jsonDecode(likedStr) as List)
            .map((x) => PostModel.fromApi(Map<String, dynamic>.from(x as Map)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() => _likedPosts = list);
          _patchPostAuthors([], likedList: list);
        }
      }

      // AI quota
      final qStr = prefs.getString(_kQuota);
      if (qStr != null) {
        final sv    = Map<String, dynamic>.from(jsonDecode(qStr) as Map);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (sv['date'] == today && mounted) {
          setState(() => _aiUsed = sv['used'] as int? ?? 0);
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
      final userId = await api.getUserId() ?? '';
      if (userId.isEmpty) throw Exception('Not authenticated');
      _currentUserId = userId;

      final results = await Future.wait([
        api.getProfile(),
        api.getUserPosts(userId),
        api.getLikedPosts(userId),
      ]);

      // Profile merge
      final profileRes  = results[0] as Map? ?? {};
      final profileData =
          (profileRes['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      final statsData   =
          (profileRes['stats']   as Map?)?.cast<String, dynamic>() ?? {};
      final merged = <String, dynamic>{
        ...profileData,
        'followers_count': profileData['followers_count'] ??
            statsData['followers'] ??
            statsData['followers_count'] ??
            0,
        'following_count': profileData['following_count'] ??
            statsData['following'] ??
            statsData['following_count'] ??
            0,
      };

      final rawPosts = (results[1] as Map?)?['posts'] as List? ?? [];
      final rawLiked = (results[2] as Map?)?['posts'] as List? ?? [];

      final posts = rawPosts
          .map((x) => PostModel.fromApi(x as Map<String, dynamic>))
          .toList();
      final liked = rawLiked
          .map((x) => PostModel.fromApi(x as Map<String, dynamic>))
          .toList();

      // ── Patch author name/avatar before rendering ──────────────────────
      // This ensures posts that return 'User' / empty name show the real
      // profile data. Requires PostModel.name and PostModel.avatarUrl
      // to be non-final (var) in home_screen.dart.
      final patchedProfile = merged;
      _patchPostAuthors(posts, likedList: liked,
          overrideProfile: patchedProfile, overrideUserId: userId);

      // Follow state
      final fw = <String, bool>{};
      for (final p in [...posts, ...liked]) {
        if (p.userId.isNotEmpty) fw[p.userId] = p.isFollowing;
      }

      if (mounted) {
        setState(() {
          _profile     = merged;
          _posts       = posts;
          _likedPosts  = liked;
          _followState = fw;
          _isPremium   = merged['subscription_tier'] == 'premium' ||
                         merged['is_premium'] == true;
          _loading     = false;
          _refreshing  = false;
        });
        _preloadVideos(posts);
      }

      // Persist to cache
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kProfile,    jsonEncode(merged)),
        prefs.setString(_kPosts,      jsonEncode(rawPosts.take(40).toList())),
        prefs.setString(_kLikedPosts, jsonEncode(rawLiked.take(40).toList())),
      ]);

      if (!_isPremium) _loadAd();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  // ── Post author patch ──────────────────────────────────────────────────
  // Fills in the real name + avatar on posts whose author data came through
  // as 'User' / empty string (API join issue in PostModel.fromApi).
  // For own posts:  always patch with current user profile data.
  // For liked tab:  only patch posts belonging to the current user.
  void _patchPostAuthors(
    List<PostModel> myPosts, {
    required List<PostModel> likedList,
    Map<String, dynamic>?    overrideProfile,
    String?                  overrideUserId,
  }) {
    final prof   = overrideProfile ?? _profile;
    final uid    = overrideUserId  ?? _currentUserId;
    final myName = prof['full_name']?.toString() ?? '';
    final myAvt  = prof['avatar_url']?.toString() ?? '';
    if (myName.isEmpty) return;

    for (final p in myPosts) {
      // All posts in "my posts" tab belong to the current user
      if (_needsPatch(p)) {
        p.name      = myName;
        p.avatarUrl = myAvt;
      }
    }
    for (final p in likedList) {
      // Only patch own posts in the liked feed
      if (p.userId == uid && _needsPatch(p)) {
        p.name      = myName;
        p.avatarUrl = myAvt;
      }
    }
  }

  bool _needsPatch(PostModel p) =>
      p.name.isEmpty || p.name == 'User' || p.name == 'user';

  // ── Video preloading ────────────────────────────────────────────────────
  void _preloadVideos(List<PostModel> posts) {
    for (int i = 0; i < posts.length && i < 5; i++) {
      final p = posts[i];
      if (p.mediaType == 'video' && (p.mediaUrl ?? '').isNotEmpty) {
        videoPreloadManager.preload(p.mediaUrl!);
      }
    }
  }

  // ── Ad loading ─────────────────────────────────────────────────────────
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
            if (mounted) setState(() {
              _bannerAd   = ad as BannerAd;
              _isAdLoaded = true;
            });
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

  // ── Helpers ────────────────────────────────────────────────────────────
  String _fmt(dynamic n) {
    final v = (n as num?)?.toInt() ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) context.pop();
    else context.go('/home');
  }

  void _shareProfile() {
    final id   = _profile['id']?.toString() ?? '';
    final link = 'riseup.app/u/$id';
    Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Link copied: $link'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Post action callbacks ──────────────────────────────────────────────
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
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Share Post',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : Colors.black87)),
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.link_rounded,
                    color: AppColors.primary, size: 20)),
            title: Text('Copy post link',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(
                  text: 'https://riseup.app/post/${post.id}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Link copied'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 2)));
            },
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.copy_rounded,
                    color: Colors.blue, size: 20)),
            title: Text('Copy text',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: post.content));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 2)));
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    api.sharePost(post.id).catchError((_) {
      if (mounted) setState(() =>
          post.shares = (post.shares - 1).clamp(0, 999999));
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
    HapticFeedback.mediumImpact();
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
    for (final p in [..._posts, ..._likedPosts]) {
      if (p.userId == uid) p.isFollowing = v;
    }
  }

  void _onPostDeleted(String id) {
    if (!mounted) return;
    setState(() {
      _posts.removeWhere((p) => p.id == id);
      _likedPosts.removeWhere((p) => p.id == id);
    });
    SharedPreferences.getInstance().then((prefs) {
      final raw = _posts.map((p) => {
        'id': p.id, 'content': p.content, 'tag': p.tag,
        'media_url': p.mediaUrl, 'media_type': p.mediaType,
        'likes_count': p.likes, 'comments_count': p.comments,
        'is_liked': p.isLiked,
        'profiles': {'full_name': p.name, 'avatar_url': p.avatarUrl,
                     'id': p.userId},
      }).toList();
      prefs.setString(_kPosts, jsonEncode(raw));
    }).catchError((_) {});
  }

  int get _aiLeft => (_freeLimit - _aiUsed).clamp(0, _freeLimit);

  // ── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? Colors.black : Colors.white;
    final cardColor    = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor    = isDark ? Colors.white : Colors.black87;
    final subColor     = isDark ? Colors.white54 : Colors.black45;

    // ── FIX: only show the real name once it's loaded from cache/API.
    // Suppresses the "Your Name" flash on first paint.
    final hasProfile = _profile.isNotEmpty;
    final name       = hasProfile
        ? (_profile['full_name']?.toString() ?? '')
        : '';
    final stage      = _profile['stage']?.toString() ?? 'survival';
    final stageInfo  = StageInfo.get(stage);

    final sw        = MediaQuery.of(context).size.width;
    final isTablet  = sw > 600;
    final isDesktop = sw > 1024;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: textColor),
          onPressed: _goBack,
        ),
        // ── FIX: AnimatedSwitcher fades the name in once available
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: name.isNotEmpty
              ? Text(
                  name,
                  key: ValueKey(name),
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: textColor),
                )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.primary.withOpacity(0.55),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Iconsax.setting_2, color: textColor, size: 22),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(children: [
        // Banner ad (non-premium, mobile only)
        if (!_isPremium && _isAdLoaded && _bannerAd != null && !kIsWeb)
          Container(
            color:   cardColor,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(
              width:  _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child:  AdWidget(ad: _bannerAd!),
            )),
          ),
        Expanded(
          child: _buildContent(
            isDark: isDark, isTablet: isTablet, isDesktop: isDesktop,
            bgColor: bgColor, cardColor: cardColor, surfaceColor: surfaceColor,
            borderColor: borderColor, textColor: textColor, subColor: subColor,
            name: name, stage: stage, stageInfo: stageInfo,
          ),
        ),
      ]),
    );
  }

  Widget _buildContent({
    required bool isDark, required bool isTablet, required bool isDesktop,
    required Color bgColor, required Color cardColor, required Color surfaceColor,
    required Color borderColor, required Color textColor, required Color subColor,
    required String name, required String stage,
    required Map<String, dynamic> stageInfo,
  }) {
    // Tablet / Desktop two-column
    if (isTablet || isDesktop) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: isDesktop ? 380 : 320,
          decoration: BoxDecoration(
            color:  cardColor,
            border: Border(right: BorderSide(color: borderColor)),
          ),
          child: RefreshIndicator(
            onRefresh: _pullRefresh,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _loading
                    ? _ProfileHeaderSkeleton(
                        key: const ValueKey('sk'),
                        isDark: isDark, cardColor: cardColor, isCompact: false)
                    : _buildProfileHeader(
                        key: const ValueKey('hdr'),
                        isDark: isDark, cardColor: cardColor,
                        surfaceColor: surfaceColor, borderColor: borderColor,
                        textColor: textColor, subColor: subColor,
                        name: name, stage: stage, stageInfo: stageInfo,
                        isCompact: false),
              ),
            ),
          ),
        ),
        Expanded(
          child: _buildPostsSection(
            isDark: isDark, cardColor: cardColor,
            borderColor: borderColor, textColor: textColor, subColor: subColor,
          ),
        ),
      ]);
    }

    // Mobile single-column
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _loading
                  ? _ProfileHeaderSkeleton(
                      key: const ValueKey('sk'),
                      isDark: isDark, cardColor: cardColor, isCompact: true)
                  : _buildProfileHeader(
                      key: const ValueKey('hdr'),
                      isDark: isDark, cardColor: cardColor,
                      surfaceColor: surfaceColor, borderColor: borderColor,
                      textColor: textColor, subColor: subColor,
                      name: name, stage: stage, stageInfo: stageInfo,
                      isCompact: true),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: subColor,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(icon: Icon(Iconsax.grid_1, size: 20)),
                  Tab(icon: Icon(Iconsax.heart,   size: 20)),
                ],
              ),
              cardColor, borderColor,
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _ProfilePostsTab(
                  key: const PageStorageKey('my_posts'),
                  posts: _posts, isLoading: _loading, isLikedTab: false,
                  isDark: isDark, cardColor: cardColor,
                  borderColor: borderColor, textColor: textColor, subColor: subColor,
                  isPremium: _isPremium, aiRemaining: _aiLeft,
                  currentUserId: _currentUserId, followState: _followState,
                  onLike: _onLike, onSave: _onSave, onComment: _onComment,
                  onShare: _onShare, onAskAI: _onAskAI,
                  onPrivateChat: _onPrivateChat, onFollow: _onFollow,
                  onPostDeleted: _onPostDeleted,
                ),
                _ProfilePostsTab(
                  key: const PageStorageKey('liked_posts'),
                  posts: _likedPosts, isLoading: _loading, isLikedTab: true,
                  isDark: isDark, cardColor: cardColor,
                  borderColor: borderColor, textColor: textColor, subColor: subColor,
                  isPremium: _isPremium, aiRemaining: _aiLeft,
                  currentUserId: _currentUserId, followState: _followState,
                  onLike: _onLike, onSave: _onSave, onComment: _onComment,
                  onShare: _onShare, onAskAI: _onAskAI,
                  onPrivateChat: _onPrivateChat, onFollow: _onFollow,
                  onPostDeleted: _onPostDeleted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile header ─────────────────────────────────────────────────────
  Widget _buildProfileHeader({
    required bool isDark, required Color cardColor, required Color surfaceColor,
    required Color borderColor, required Color textColor, required Color subColor,
    required String name, required String stage,
    required Map<String, dynamic> stageInfo, required bool isCompact, Key? key,
  }) {
    final isPremium      = _profile['subscription_tier'] == 'premium' ||
                           _profile['is_premium'] == true;
    final followersCount = _profile['followers_count'] ?? 0;
    final followingCount = _profile['following_count'] ?? 0;

    return Container(
      key:     key,
      color:   cardColor,
      padding: EdgeInsets.all(isCompact ? 20 : 24),
      child: Column(
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // Avatar + stats
          if (isCompact)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildAvatar(name: name,
                  avatarUrl: _profile['avatar_url']?.toString(),
                  cardColor: cardColor, isCompact: true),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatCol(_fmt(_posts.length),  'Posts',     textColor, subColor),
                    _StatCol(_fmt(followersCount), 'Followers', textColor, subColor),
                    _StatCol(_fmt(followingCount), 'Following', textColor, subColor),
                  ],
                ),
              ),
            ])
          else
            Column(children: [
              _buildAvatar(name: name,
                  avatarUrl: _profile['avatar_url']?.toString(),
                  cardColor: cardColor, isCompact: false),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _StatCol(_fmt(_posts.length),  'Posts',     textColor, subColor),
                const SizedBox(width: 32),
                _StatCol(_fmt(followersCount), 'Followers', textColor, subColor),
                const SizedBox(width: 32),
                _StatCol(_fmt(followingCount), 'Following', textColor, subColor),
              ]),
            ]),

          const SizedBox(height: 16),

          // Name + badge
          if (isCompact)
            Row(children: [
              Flexible(
                child: Text(name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: textColor),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              _buildStageBadge(stageInfo),
              if (isPremium) ...[const SizedBox(width: 6), _buildPremiumBadge()],
            ])
          else
            Column(children: [
              Text(name,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: textColor)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _buildStageBadge(stageInfo),
                if (isPremium) ...[const SizedBox(width: 8), _buildPremiumBadge()],
              ]),
            ]),

          const SizedBox(height: 8),

          // Bio
          Text(
            _profile['bio']?.toString().isNotEmpty == true
                ? _profile['bio'].toString()
                : 'Building wealth one step at a time 🚀',
            style: TextStyle(fontSize: 13, color: subColor),
            textAlign: isCompact ? TextAlign.left : TextAlign.center,
          ),

          // Status
          if ((_profile['status']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_profile['status'].toString(),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.success,
                          fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ],

          // Country
          if ((_profile['country']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(Iconsax.location, size: 12, color: subColor),
                const SizedBox(width: 4),
                Text(_profile['country'].toString(),
                    style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Action buttons
          if (isCompact)
            Row(children: [
              Expanded(child: _buildActionButton('Edit Profile',
                  onTap: () => context.push('/edit-profile')
                      .then((_) => _silentRefresh()),
                  surfaceColor: surfaceColor, borderColor: borderColor,
                  textColor: textColor)),
              const SizedBox(width: 8),
              Expanded(child: _buildActionButton('Share Profile',
                  onTap: _shareProfile,
                  surfaceColor: surfaceColor, borderColor: borderColor,
                  textColor: textColor)),
              if (!isPremium) ...[
                const SizedBox(width: 8),
                _buildProButton(),
              ],
            ])
          else
            Column(children: [
              _buildActionButton('Edit Profile',
                  onTap: () => context.push('/edit-profile')
                      .then((_) => _silentRefresh()),
                  surfaceColor: surfaceColor, borderColor: borderColor,
                  textColor: textColor, isFullWidth: true),
              const SizedBox(height: 8),
              _buildActionButton('Share Profile',
                  onTap: _shareProfile,
                  surfaceColor: surfaceColor, borderColor: borderColor,
                  textColor: textColor, isFullWidth: true),
              if (!isPremium) ...[
                const SizedBox(height: 8),
                _buildProButton(isFullWidth: true),
              ],
            ]),

          const SizedBox(height: 16),

          // Feature tiles
          Row(children: [
            _ProfileFeatureTile('🎨', 'Portfolio', () => context.push('/portfolio')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('🏆', 'Challenges', () => context.push('/challenges')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('🧠', 'Memory', () => context.push('/memory')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('💼', 'CRM', () => context.push('/crm')),
          ]),
        ],
      ),
    );
  }

  // ── FIX: use CachedNetworkImage for instant repeat loads ────────────────
  Widget _buildAvatar({
    required String name, required String? avatarUrl,
    required Color cardColor, required bool isCompact,
  }) {
    final size    = isCompact ? 76.0 : 100.0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '👤';
    final fSz     = isCompact ? 32.0 : 40.0;

    Widget fallback = Center(
      child: Text(initial,
          style: TextStyle(fontSize: fSz, color: Colors.white,
              fontWeight: FontWeight.w700)),
    );

    return Stack(children: [
      Container(
        width: size, height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.accent]),
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl:    avatarUrl,
                  fit:         BoxFit.cover,
                  // Show gradient fallback while loading (no flash)
                  placeholder: (_, __) => fallback,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
      Positioned(
        bottom: 0, right: 0,
        child: GestureDetector(
          onTap: () => context.push('/edit-profile')
              .then((_) => _silentRefresh()),
          child: Container(
            width:  isCompact ? 22 : 28,
            height: isCompact ? 22 : 28,
            decoration: BoxDecoration(
              color:  AppColors.primary,
              shape:  BoxShape.circle,
              border: Border.all(color: cardColor, width: 2),
            ),
            child: Icon(Icons.camera_alt_rounded, color: Colors.white,
                size: isCompact ? 11 : 14),
          ),
        ),
      ),
    ]);
  }

  Widget _buildStageBadge(Map<String, dynamic> si) {
    final c = si['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text('${si['emoji']} ${si['label']}',
          style: TextStyle(fontSize: 10, color: c,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildPremiumBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.gold, AppColors.goldDark]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('⭐ PRO',
            style: TextStyle(color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.w700)),
      );

  Widget _buildActionButton(String label, {
    required VoidCallback onTap,
    required Color surfaceColor, required Color borderColor,
    required Color textColor, bool isFullWidth = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width:   isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:        surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: textColor)),
          ),
        ),
      );

  Widget _buildProButton({bool isFullWidth = false}) => GestureDetector(
        onTap: () => context.go('/premium'),
        child: Container(
          width:   isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.gold, AppColors.goldDark]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('⭐ Pro',
              style: TextStyle(color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _buildPostsSection({
    required bool isDark, required Color cardColor,
    required Color borderColor, required Color textColor, required Color subColor,
  }) =>
      Column(children: [
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
              Tab(icon: Icon(Iconsax.heart,   size: 20)),
            ],
          ),
        ),
        Divider(height: 1, color: borderColor),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _ProfilePostsTab(
                key: const PageStorageKey('my_posts_tablet'),
                posts: _posts, isLoading: _loading, isLikedTab: false,
                isDark: isDark, cardColor: cardColor,
                borderColor: borderColor, textColor: textColor, subColor: subColor,
                isPremium: _isPremium, aiRemaining: _aiLeft,
                currentUserId: _currentUserId, followState: _followState,
                onLike: _onLike, onSave: _onSave, onComment: _onComment,
                onShare: _onShare, onAskAI: _onAskAI,
                onPrivateChat: _onPrivateChat, onFollow: _onFollow,
                onPostDeleted: _onPostDeleted,
              ),
              _ProfilePostsTab(
                key: const PageStorageKey('liked_posts_tablet'),
                posts: _likedPosts, isLoading: _loading, isLikedTab: true,
                isDark: isDark, cardColor: cardColor,
                borderColor: borderColor, textColor: textColor, subColor: subColor,
                isPremium: _isPremium, aiRemaining: _aiLeft,
                currentUserId: _currentUserId, followState: _followState,
                onLike: _onLike, onSave: _onSave, onComment: _onComment,
                onShare: _onShare, onAskAI: _onAskAI,
                onPrivateChat: _onPrivateChat, onFollow: _onFollow,
                onPostDeleted: _onPostDeleted,
              ),
            ],
          ),
        ),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile posts tab  (AutomaticKeepAliveClientMixin)
// ─────────────────────────────────────────────────────────────────────────────
class _ProfilePostsTab extends StatefulWidget {
  final List<PostModel>      posts;
  final bool                 isLoading, isLikedTab, isDark, isPremium;
  final Color                cardColor, borderColor, textColor, subColor;
  final int                  aiRemaining;
  final String               currentUserId;
  final Map<String, bool>    followState;
  final Function(PostModel)  onLike, onSave, onComment, onShare,
                              onAskAI, onPrivateChat;
  final Function(String)     onFollow, onPostDeleted;

  const _ProfilePostsTab({
    super.key,
    required this.posts,         required this.isLoading,
    required this.isLikedTab,    required this.isDark,
    required this.cardColor,     required this.borderColor,
    required this.textColor,     required this.subColor,
    required this.isPremium,     required this.aiRemaining,
    required this.currentUserId, required this.followState,
    required this.onLike,        required this.onSave,
    required this.onComment,     required this.onShare,
    required this.onAskAI,       required this.onPrivateChat,
    required this.onFollow,      required this.onPostDeleted,
  });

  @override
  State<_ProfilePostsTab> createState() => _ProfilePostsTabState();
}

class _ProfilePostsTabState extends State<_ProfilePostsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _sc = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadAhead(0));
  }

  @override
  void didUpdateWidget(_ProfilePostsTab old) {
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

    // Skeleton
    if (widget.isLoading && widget.posts.isEmpty) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) =>
            Divider(height: 8, thickness: 8, color: widget.borderColor),
        itemBuilder: (_, __) =>
            _ProfilePostSkeleton(isDark: widget.isDark),
      );
    }

    // Empty state
    if (widget.posts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(widget.isLikedTab ? '❤️' : '📝',
              style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            widget.isLikedTab ? 'No liked posts yet' : 'No posts yet',
            style: TextStyle(color: widget.subColor, fontSize: 14),
          ),
          if (!widget.isLikedTab) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => ctx.go('/create'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Create your first post',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
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
class _StatCol extends StatelessWidget {
  final String value, label;
  final Color  textColor, subColor;
  const _StatCol(this.value, this.label, this.textColor, this.subColor);

  @override
  Widget build(BuildContext ctx) => Column(children: [
        Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                color: textColor)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: subColor)),
      ]);
}

class _ProfileFeatureTile extends StatelessWidget {
  final String       emoji, label;
  final VoidCallback onTap;
  const _ProfileFeatureTile(this.emoji, this.label, this.onTap);

  @override
  Widget build(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color  bg, border;
  const _TabBarDelegate(this.tabBar, this.bg, this.border);

  @override double get minExtent => tabBar.preferredSize.height + 1;
  @override double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext _, double __, bool ___) => Container(
        color: bg,
        child: Column(children: [tabBar, Divider(height: 1, color: border)]),
      );

  @override
  bool shouldRebuild(_TabBarDelegate o) => false;
}
