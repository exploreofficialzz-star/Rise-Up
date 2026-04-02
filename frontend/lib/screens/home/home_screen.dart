// frontend/lib/screens/home/home_screen.dart
// v5.1 — Video artifact fixes
//
// KEY CHANGES vs v5.0:
//  1. _VideoThumbnailState: removed VideoPlayerController-based thumbnail
//     entirely. On Android, using VideoPlayer to grab a first-frame causes
//     SurfaceTexture YUV artifacts (green/yellow lines) before color
//     conversion completes. Replaced with a clean static placeholder —
//     full video still plays in _FullScreenVideoPage on tap.
//  2. _FullScreenVideoPage: removed explicit `aspectRatio` from
//     ChewieController. Passing vp.value.aspectRatio for a portrait (9:16)
//     video caused Chewie to render into a wrongly-sized surface, producing
//     the same artifacts. Chewie auto-detects correctly without it.
//  3. _StatusVideoPlayer: deferred ctrl.play() to addPostFrameCallback so
//     the SurfaceTexture is fully bound to the Flutter texture registry
//     before playback starts, eliminating the initial frame artifact.

import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../../services/ad_manager.dart';
import '../../widgets/ad_widgets.dart';
import 'create_status_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Sound Service
// ══════════════════════════════════════════════════════════════════════════════
class SoundService {
  static void like()    {}
  static void comment() {}
  static void share()   {}
  static void save()    {}
  static void follow()  {}
  static void tap()     {}
}

// ══════════════════════════════════════════════════════════════════════════════
// Stage Info
// ══════════════════════════════════════════════════════════════════════════════
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const stages = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🆘', 'label': 'Survival', 'color': Color(0xFFE17055)},
      'earning':  {'emoji': '💪', 'label': 'Earning',  'color': Color(0xFF0984E3)},
      'growing':  {'emoji': '🚀', 'label': 'Growing',  'color': Color(0xFF00B894)},
      'wealth':   {'emoji': '💎', 'label': 'Wealth',   'color': Color(0xFF6C5CE7)},
    };
    return stages[stage] ?? stages['survival']!;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Post Model
// ══════════════════════════════════════════════════════════════════════════════
class PostModel {
  final String id, name, username, time, avatar, avatarUrl, tag;
  String content;
  final String? mediaUrl, mediaType, linkUrl, linkTitle;
  int likes, comments, shares;
  final bool verified, isPremiumPost;
  bool isLiked, isSaved, isFollowing;
  final String userId;

  PostModel({
    required this.id,
    required this.name,
    required this.username,
    required this.time,
    required this.avatar,
    this.avatarUrl = '',
    required this.tag,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.linkUrl,
    this.linkTitle,
    required this.likes,
    required this.comments,
    required this.shares,
    this.verified      = false,
    this.isPremiumPost = false,
    this.isLiked       = false,
    this.isSaved       = false,
    this.isFollowing   = false,
    this.userId        = '',
  });

  factory PostModel.fromApi(Map<String, dynamic> data) {
    final profile   = (data['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
    final createdAt = DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now();
    final diff      = DateTime.now().difference(createdAt);
    final String time;
    if (diff.inMinutes < 60)    time = '${diff.inMinutes}m ago';
    else if (diff.inHours < 24) time = '${diff.inHours}h ago';
    else                        time = '${diff.inDays}d ago';

    final fullName  = profile['full_name']?.toString() ?? 'User';
    final stage     = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final userId    = data['user_id']?.toString().isNotEmpty == true
        ? data['user_id'].toString()
        : profile['id']?.toString() ?? '';

    return PostModel(
      id:            data['id']?.toString() ?? '',
      name:          fullName,
      username:      '@${fullName.toLowerCase().replaceAll(' ', '')}',
      time:          time,
      avatar:        stageInfo['emoji'] as String,
      avatarUrl:     profile['avatar_url']?.toString() ?? '',
      tag:           data['tag']?.toString() ?? '💰 Wealth',
      content:       data['content']?.toString() ?? '',
      mediaUrl:      data['media_url']?.toString(),
      mediaType:     data['media_type']?.toString(),
      linkUrl:       data['link_url']?.toString(),
      linkTitle:     data['link_title']?.toString(),
      likes:         (data['likes_count'] as num?)?.toInt() ?? 0,
      comments:      (data['comments_count'] as num?)?.toInt() ?? 0,
      shares:        (data['shares_count'] as num?)?.toInt() ?? 0,
      verified:      profile['is_verified'] == true,
      isPremiumPost: profile['subscription_tier'] == 'premium',
      isLiked:       data['is_liked'] == true,
      isSaved:       data['is_saved'] == true,
      isFollowing:   data['is_following'] == true,
      userId:        userId,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shimmer skeleton helpers
// ══════════════════════════════════════════════════════════════════════════════
class _Shimmer extends StatelessWidget {
  const _Shimmer({this.width, required this.height, this.radius = 8, this.circle = false});
  final double? width;
  final double  height, radius;
  final bool    circle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    ).animate(onPlay: (c) => c.repeat())
     .shimmer(duration: 1200.ms,
              color: dark ? Colors.white10 : Colors.white70);
  }
}

class _PostCardSkeleton extends StatelessWidget {
  const _PostCardSkeleton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Container(
      color: isDark ? AppColors.bgCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _Shimmer(width: 44, height: 44, circle: true),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Shimmer(width: w * 0.35, height: 13),
            const SizedBox(height: 5),
            _Shimmer(width: w * 0.25, height: 11),
          ])),
          const _Shimmer(width: 60, height: 26, radius: 13),
        ]),
        const SizedBox(height: 14),
        const _Shimmer(height: 13),
        const SizedBox(height: 6),
        const _Shimmer(height: 13),
        const SizedBox(height: 6),
        _Shimmer(width: w * 0.55, height: 13),
        const SizedBox(height: 12),
        AspectRatio(aspectRatio: 16 / 9, child: _Shimmer(height: double.infinity, radius: 12)),
        const SizedBox(height: 14),
        Row(children: const [
          _Shimmer(width: 55, height: 18, radius: 9),
          SizedBox(width: 18),
          _Shimmer(width: 55, height: 18, radius: 9),
          SizedBox(width: 18),
          _Shimmer(width: 55, height: 18, radius: 9),
          Spacer(),
          _Shimmer(width: 22, height: 22, radius: 11),
        ]),
        const SizedBox(height: 12),
        Row(children: const [
          Expanded(child: _Shimmer(height: 36, radius: 10)),
          SizedBox(width: 8),
          Expanded(child: _Shimmer(height: 36, radius: 10)),
        ]),
      ]),
    );
  }
}

class _StoriesSkeleton extends StatelessWidget {
  const _StoriesSkeleton({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    color: isDark ? AppColors.bgCard : Colors.white,
    height: 92,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(right: 14),
        child: Column(children: [
          _Shimmer(width: 58, height: 58, circle: true),
          SizedBox(height: 5),
          _Shimmer(width: 42, height: 10, radius: 5),
        ]),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Home Screen
// ══════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  late TabController _tabCtrl;
  Map<String, dynamic> _profile = {};
  DateTime? _lastPausedAt;
  static const Duration _refreshThreshold = Duration(minutes: 5);

  // ── AI quota ──────────────────────────────────────────────────────────────
  int       _aiUsedToday     = 0;
  int       _adsWatchedToday = 0;
  DateTime? _adLockoutUntil;

  static const int      _dailyFreeLimit    = 3;
  static const int      _maxAdsPerDay      = 5;
  static const Duration _adLockoutDuration = Duration(hours: 4);

  // ── Prefs keys ────────────────────────────────────────────────────────────
  static const _kQuotaKey        = 'riseup_ai_quota_v1';
  static const _kProfileCacheKey = 'riseup_profile_cache_v1';
  static const _kFeedCacheKey    = 'riseup_feed_for_you_v2';
  static const _kFollowedKey     = 'riseup_followed_users';

  // ── Feed state ────────────────────────────────────────────────────────────
  List<dynamic>         _statusUsers  = [];
  bool                  _statusLoaded = false;

  final _feeds   = <String, List<PostModel>>{'for_you': [], 'following': [], 'trending': []};
  final _loading = <String, bool>    {'for_you': false, 'following': false, 'trending': false};
  final _offsets = <String, int>     {'for_you': 0,     'following': 0,     'trending': 0};
  final _hasMore = <String, bool>    {'for_you': true,  'following': true,  'trending': true};

  final _tabs = ['for_you', 'following', 'trending'];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, bool> _followState = {};

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      final tab = _tabs[_tabCtrl.index];
      if (_feeds[tab]!.isEmpty) _loadFeed(tab);
    });
    _restoreAllFromCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && mounted) {
      final away = _lastPausedAt == null ||
          DateTime.now().difference(_lastPausedAt!) >= _refreshThreshold;
      if (away) { _lastPausedAt = null; _refreshAll(); }
    }
  }

  Future<void> _restoreAllFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_kProfileCacheKey);
      if (raw != null && mounted) {
        setState(() => _profile = Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {}
    try {
      final raw = prefs.getString(_kFeedCacheKey);
      if (raw != null) {
        final rawList = jsonDecode(raw) as List;
        final posts   = rawList
            .map((p) => PostModel.fromApi(Map<String, dynamic>.from(p as Map)))
            .toList();
        if (posts.isNotEmpty && mounted) setState(() => _feeds['for_you'] = posts);
      }
    } catch (_) {}
    try {
      final raw = prefs.getString(_kQuotaKey);
      if (raw != null) {
        final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (saved['date'] == today && mounted) {
          setState(() {
            _aiUsedToday     = saved['used']    as int?    ?? 0;
            _adsWatchedToday = saved['ads']     as int?    ?? 0;
            final ls         = saved['lockout'] as String?;
            _adLockoutUntil  = ls == null ? null : DateTime.tryParse(ls);
          });
        }
      }
    } catch (_) {}
    try {
      final followed = prefs.getStringList(_kFollowedKey) ?? [];
      if (mounted) setState(() { for (final uid in followed) _followState[uid] = true; });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadProfile(),
      _loadStatus(),
      _loadFeed('for_you', refresh: true),
    ]);
  }

  Future<void> _saveAiQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQuotaKey, jsonEncode({
        'date':    DateTime.now().toIso8601String().substring(0, 10),
        'used':    _aiUsedToday,
        'ads':     _adsWatchedToday,
        'lockout': _adLockoutUntil?.toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final data    = await api.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted && profile.isNotEmpty) {
        setState(() => _profile = profile);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kProfileCacheKey, jsonEncode(profile));
      }
    } catch (_) {}
  }

  Future<void> _loadStatus() async {
    try {
      final data = await api.get('/posts/status/feed');
      if (mounted) setState(() {
        _statusUsers  = ((data as Map<String, dynamic>?)?['users'] as List?) ?? [];
        _statusLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadFeed(String tab, {bool refresh = false}) async {
    if (_loading[tab] == true) return;
    if (refresh) { _offsets[tab] = 0; _hasMore[tab] = true; }
    if (!(_hasMore[tab] ?? true)) return;
    if (mounted) setState(() => _loading[tab] = true);
    try {
      final data     = await api.getFeed(tab: tab, limit: 20, offset: _offsets[tab]!);
      final rawPosts = (data['posts'] as List?) ?? [];
      if (tab == 'for_you' && (_offsets[tab] == 0 || refresh)) _cacheFeedRaw(rawPosts);
      final posts = rawPosts
          .map((p) => PostModel.fromApi(p as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() {
        for (final post in posts) {
          if (post.userId.isNotEmpty && _followState[post.userId] == null) {
            _followState[post.userId] = post.isFollowing;
          }
        }
        _feeds[tab]  = refresh ? posts : [..._feeds[tab]!, ...posts];
        _offsets[tab] = (_offsets[tab] ?? 0) + posts.length;
        _hasMore[tab] = posts.length == 20;
        _loading[tab] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading[tab] = false);
    }
  }

  Future<void> _cacheFeedRaw(List<dynamic> rawPosts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFeedCacheKey, jsonEncode(rawPosts.take(40).toList()));
    } catch (_) {}
  }

  Future<void> _persistFollowState() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final followed = _followState.entries.where((e) => e.value).map((e) => e.key).toList();
      await prefs.setStringList(_kFollowedKey, followed);
    } catch (_) {}
  }

  bool get _isPremium   => (_profile['subscription_tier'] ?? 'free') == 'premium';
  int  get _aiRemaining => (_dailyFreeLimit - _aiUsedToday).clamp(0, _dailyFreeLimit);
  bool get _isAdLocked {
    if (_adLockoutUntil == null) return false;
    if (DateTime.now().isAfter(_adLockoutUntil!)) { _adLockoutUntil = null; return false; }
    return true;
  }

  Future<void> _handleFollow(String userId) async {
    if (userId.isEmpty) return;
    HapticFeedback.mediumImpact();
    SoundService.follow();
    final prev = _followState[userId] ?? false;
    setState(() { _followState[userId] = !prev; _syncFollowOnPosts(userId, !prev); });
    try {
      final res = await api.toggleFollow(userId);
      final val = res['following'] == true;
      if (mounted) {
        setState(() { _followState[userId] = val; _syncFollowOnPosts(userId, val); });
        await _persistFollowState();
      }
    } catch (_) {
      if (mounted) setState(() { _followState[userId] = prev; _syncFollowOnPosts(userId, prev); });
    }
  }

  void _syncFollowOnPosts(String userId, bool value) {
    for (final tab in _tabs) {
      for (final p in _feeds[tab]!) { if (p.userId == userId) p.isFollowing = value; }
    }
  }

  void _handleShare(PostModel post) {
    HapticFeedback.mediumImpact();
    SoundService.share();
    setState(() => post.shares++);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Share Post', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87))),
        ListTile(
          leading: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.link_rounded, color: AppColors.primary, size: 20)),
          title: Text('Copy post link', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: 'https://riseup.app/post/${post.id}'));
            _snack('Link copied', AppColors.success);
          },
        ),
        ListTile(
          leading: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.copy_rounded, color: Colors.blue, size: 20)),
          title: Text('Copy post text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: post.content));
            _snack('Text copied', AppColors.success);
          },
        ),
        const SizedBox(height: 12),
      ])),
    );
    api.sharePost(post.id).catchError((_) {
      if (mounted) setState(() => post.shares = (post.shares - 1).clamp(0, 999999));
    });
  }

  Future<void> _handleAiRequest(PostModel post, {required bool isPrivate}) async {
    SoundService.tap();
    if (_isPremium) { await _executeAiAction(post, isPrivate: isPrivate); return; }
    if (_aiUsedToday < _dailyFreeLimit) {
      setState(() => _aiUsedToday++);
      await _saveAiQuota();
      await _executeAiAction(post, isPrivate: isPrivate);
      return;
    }
    if (_isAdLocked) { _showLockoutDialog(); return; }
    if (_adsWatchedToday >= _maxAdsPerDay) {
      setState(() => _adLockoutUntil = DateTime.now().add(_adLockoutDuration));
      await _saveAiQuota();
      _showLockoutDialog();
      return;
    }
    final ok = await _showAdPrompt();
    if (!ok || !mounted) return;
    await adService.showRewardedAd(
      featureKey: 'post_ai',
      onRewarded: () async {
        setState(() { _aiUsedToday = 0; _adsWatchedToday++; });
        await _saveAiQuota();
        if (mounted) await _executeAiAction(post, isPrivate: isPrivate);
      },
      onDismissed: () {
        if (mounted) _snack('Watch the full ad to unlock AI.', AppColors.error);
      },
    );
  }

  Future<void> _executeAiAction(PostModel post, {required bool isPrivate}) async {
    if (isPrivate) {
      context.push(
        '/conversation/ai'
        '?name=${Uri.encodeComponent("RiseUp AI")}'
        '&avatar=${Uri.encodeComponent("AI")}'
        '&isAI=true'
        '&postContext=${Uri.encodeComponent(post.content)}'
        '&postAuthor=${Uri.encodeComponent(post.name)}',
      );
    } else {
      await _postAIComment(post);
    }
  }

  Future<void> _postAIComment(PostModel post) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: const [
        SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('RiseUp AI is thinking…'),
      ]),
      backgroundColor: AppColors.primary,
      duration: const Duration(seconds: 120),
    ));
    try {
      final res = await api.chat(
        message:
            'A RiseUp community member posted: "${post.content}"\n\n'
            'Give a short (2-3 sentence) actionable wealth-building insight '
            'or advice directly related to this post. Be specific and helpful.',
        mode: 'mentor',
      );
      final aiText = (res['content'] as String?)?.trim() ?? '';
      if (aiText.isEmpty) throw const ApiException('AI returned an empty response');
      await api.addComment(post.id, 'RiseUp AI: $aiText', isAI: true, isPinned: true);
      if (mounted) setState(() => post.comments++);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('AI insight pinned in comments!'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View', textColor: Colors.white,
          onPressed: () => context.push(
              '/comments/${post.id}'
              '?content=${Uri.encodeComponent(post.content)}'
              '&author=${Uri.encodeComponent(post.name)}'),
        ),
      ));
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) return;
      final msg = e.statusCode == 429
          ? 'AI rate limit reached — please wait a moment and try again.'
          : (e.statusCode == 503 || e.statusCode == 500)
              ? 'AI service temporarily unavailable. Try again shortly.'
              : e.message.isNotEmpty ? e.message : 'AI request failed. Please try again.';
      _snack(msg, AppColors.error, duration: const Duration(seconds: 4));
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', '').replaceAll('ApiException: ', ''),
          AppColors.error, duration: const Duration(seconds: 4));
    }
  }

  Future<bool> _showAdPrompt() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: isDark ? AppColors.bgCard : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Watch a short ad?', style: TextStyle(fontWeight: FontWeight.w700,
                fontSize: 18, color: isDark ? Colors.white : Colors.black87)),
            content: Text(
              'You have used your $_dailyFreeLimit free AI responses today.\n\n'
              'Watch a 30-second ad to unlock more, or upgrade to Premium.\n\n'
              '${_maxAdsPerDay - _adsWatchedToday} unlock(s) remaining today.',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, height: 1.5),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now', style: TextStyle(color: AppColors.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Watch Ad', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ?? false;
  }

  void _showLockoutDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final exp    = _adLockoutUntil;
    final diff   = exp != null ? exp.difference(DateTime.now()) : Duration.zero;
    final h      = diff.inHours;
    final m      = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final ts     = diff.isNegative ? 'shortly' : (h > 0 ? '${h}h ${m}m' : '${diff.inMinutes}m');
    showDialog(context: context,
        builder: (_) => AlertDialog(
          backgroundColor: isDark ? AppColors.bgCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Daily Limit Reached'),
          content: Text('All AI unlocks used for today.\n\nResets in $ts — or upgrade to Premium.',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () { Navigator.pop(context); context.push('/premium'); },
              child: const Text('Go Premium', style: TextStyle(color: Colors.white)),
            ),
          ],
        ));
  }

  void _viewStatus(Map<String, dynamic> user) {
    if ((user['items'] as List? ?? []).isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusViewSheet(user: user),
    );
  }

  void _snack(String msg, Color bg, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg, duration: duration));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white : Colors.black87;
    final subColor    = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final iconColor   = isDark ? Colors.white.withOpacity(0.7) : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      key: _scaffoldKey,
      drawer: _AppDrawer(profile: _profile, isDark: isDark),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0, surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: iconColor, size: 24),
          onPressed: () { HapticFeedback.lightImpact(); _scaffoldKey.currentState?.openDrawer(); },
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFFF6B00), Color(0xFFFFD700), Color(0xFF6C5CE7)],
            stops: [0.0, 0.4, 1.0],
          ).createShader(b),
          child: const Text('RiseUp', style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
        ),
        centerTitle: true,
        actions: [
          if (!_isPremium)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('$_aiRemaining left',
                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          IconButton(icon: Icon(Iconsax.search_normal, color: iconColor, size: 20),
              onPressed: () { HapticFeedback.lightImpact(); context.go('/explore'); }),
          IconButton(icon: Icon(Iconsax.notification, color: iconColor, size: 20),
              onPressed: () { HapticFeedback.lightImpact(); context.go('/notifications'); }),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: borderColor)),
      ),
      body: Column(children: [

        // ── Stories ────────────────────────────────────────────────────────
        Container(
          color: cardColor,
          child: Column(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: !_statusLoaded
                  ? _StoriesSkeleton(isDark: isDark, key: const ValueKey('sk'))
                  : SizedBox(
                      key: const ValueKey('real'),
                      height: 92,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _statusUsers.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) return _StoryAddButton(isDark: isDark,
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const CreateStatusScreen()))
                                  .then((_) => _loadStatus()));
                          final user = _statusUsers[i - 1] as Map<String, dynamic>;
                          return _StoryItem(user: user, isDark: isDark, onTap: () => _viewStatus(user));
                        },
                      ),
                    ),
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),

        // ── Tabs ──────────────────────────────────────────────────────────
        Container(
          color: cardColor,
          child: Column(children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'For You'), Tab(text: 'Following'), Tab(text: 'Trending')],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: _tabs.map((tab) => _FeedTabView(
              key: PageStorageKey(tab),
              tab: tab,
              posts: _feeds[tab]!,
              isLoading: _loading[tab] == true,
              hasMore: _hasMore[tab] ?? true,
              isDark: isDark,
              cardColor: cardColor,
              borderColor: borderColor,
              textColor: textColor,
              subColor: subColor,
              isPremium: _isPremium,
              aiRemaining: _aiRemaining,
              needsAd: _aiRemaining <= 0 && !_isPremium,
              currentUserId: _profile['id']?.toString() ?? '',
              followState: _followState,
              onLoadMore: () => _loadFeed(tab),
              onRefresh: () => _loadFeed(tab, refresh: true),
              onAskAI: (p) => _handleAiRequest(p, isPrivate: false),
              onPrivateChat: (p) => _handleAiRequest(p, isPrivate: true),
              onFollow: _handleFollow,
              onShare: _handleShare,
              onPostDeleted: (id) => setState(() {
                for (final t in _tabs) _feeds[t]!.removeWhere((p) => p.id == id);
              }),
              onLike: (p) async {
                HapticFeedback.mediumImpact();
                SoundService.like();
                setState(() { p.isLiked = !p.isLiked; p.likes += p.isLiked ? 1 : -1; });
                try {
                  final res = await api.toggleLike(p.id);
                  if (mounted) setState(() => p.isLiked = res['liked'] == true);
                } catch (_) {
                  if (mounted) setState(() { p.isLiked = !p.isLiked; p.likes += p.isLiked ? 1 : -1; });
                }
              },
              onSave: (p) async {
                HapticFeedback.mediumImpact();
                SoundService.save();
                setState(() => p.isSaved = !p.isSaved);
                try {
                  final res = await api.toggleSave(p.id);
                  if (mounted) setState(() => p.isSaved = res['saved'] == true);
                } catch (_) {
                  if (mounted) setState(() => p.isSaved = !p.isSaved);
                }
              },
              onComment: (p) {
                SoundService.comment();
                context.push('/comments/${p.id}'
                    '?content=${Uri.encodeComponent(p.content)}'
                    '&author=${Uri.encodeComponent(p.name)}');
              },
            )).toList(),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Feed Tab View
// ══════════════════════════════════════════════════════════════════════════════
class _FeedTabView extends StatefulWidget {
  final String tab;
  final List<PostModel> posts;
  final bool isLoading, hasMore, isDark, isPremium, needsAd;
  final Color cardColor, borderColor, textColor, subColor;
  final int aiRemaining;
  final String currentUserId;
  final Map<String, bool> followState;
  final VoidCallback onLoadMore, onRefresh;
  final Function(PostModel) onAskAI, onPrivateChat, onLike, onSave, onComment, onShare;
  final Function(String) onFollow, onPostDeleted;

  const _FeedTabView({
    super.key,
    required this.tab,
    required this.posts,
    required this.isLoading,
    required this.hasMore,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
    required this.isPremium,
    required this.aiRemaining,
    required this.needsAd,
    required this.currentUserId,
    required this.followState,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onAskAI,
    required this.onPrivateChat,
    required this.onLike,
    required this.onSave,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onPostDeleted,
  });

  @override
  State<_FeedTabView> createState() => _FeedTabViewState();
}

class _FeedTabViewState extends State<_FeedTabView>
    with AutomaticKeepAliveClientMixin {

  final ScrollController _scrollCtrl = ScrollController();
  bool _prefetching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _scrollCtrl.addListener(_onScroll); }

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.7 &&
        !_prefetching && !widget.isLoading && widget.hasMore) {
      _prefetching = true;
      widget.onLoadMore();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _prefetching = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final posts    = widget.posts;
    final isDark   = widget.isDark;
    final subColor = widget.subColor;
    final border   = widget.borderColor;

    if (widget.isLoading && posts.isEmpty) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
        itemBuilder: (_, __) => _PostCardSkeleton(isDark: isDark),
      );
    }

    if (posts.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No posts yet', style: TextStyle(color: subColor, fontSize: 14)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.onRefresh,
          child: Text('Refresh', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ]));
    }

    final totalSlots = adManager.feedItemCount(posts.length) + 1;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: AppColors.primary,
      child: ListView.separated(
        controller: _scrollCtrl,
        cacheExtent: 1500,
        padding: EdgeInsets.zero,
        itemCount: totalSlots,
        separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
        itemBuilder: (_, i) {
          if (i == totalSlots - 1) {
            if (widget.isLoading) return _PostCardSkeleton(isDark: isDark);
            if (!widget.hasMore) {
              return Padding(padding: const EdgeInsets.all(20),
                  child: Center(child: Text("You're all caught up ✓",
                      style: TextStyle(color: subColor, fontSize: 13))));
            }
            return const SizedBox(height: 40);
          }
          if (adManager.shouldShowFeedAd(i)) {
            return FeedAdCard(isDark: isDark, cardColor: widget.cardColor,
                borderColor: border, textColor: widget.textColor, subColor: subColor);
          }
          final postIndex = adManager.realPostIndex(i);
          if (postIndex >= posts.length) return const SizedBox.shrink();
          final post      = posts[postIndex];
          final following = widget.followState[post.userId] ?? post.isFollowing;
          return PostCard(
            post: post, isDark: isDark, cardColor: widget.cardColor,
            borderColor: border, textColor: widget.textColor, subColor: subColor,
            onAskAI: widget.onAskAI, onPrivateChat: widget.onPrivateChat,
            onLike: widget.onLike, onSave: widget.onSave,
            onComment: widget.onComment, onShare: widget.onShare,
            onFollow: widget.onFollow, onPostDeleted: widget.onPostDeleted,
            isPremium: widget.isPremium, aiRemaining: widget.aiRemaining,
            needsAd: widget.needsAd, isFollowing: following,
            currentUserId: widget.currentUserId,
          ).animate().fadeIn(
            delay: Duration(milliseconds: (postIndex % 5) * 20),
            duration: const Duration(milliseconds: 200),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Post Card
// ══════════════════════════════════════════════════════════════════════════════
class PostCard extends StatefulWidget {
  final PostModel post;
  final bool isDark, isPremium, isFollowing, needsAd;
  final Color cardColor, borderColor, textColor, subColor;
  final Function(PostModel) onAskAI, onPrivateChat, onLike, onSave, onComment, onShare;
  final Function(String) onFollow, onPostDeleted;
  final int aiRemaining;
  final String currentUserId;

  const PostCard({
    super.key,
    required this.post,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
    required this.onAskAI,
    required this.onPrivateChat,
    required this.onLike,
    required this.onSave,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onPostDeleted,
    required this.isPremium,
    required this.aiRemaining,
    required this.isFollowing,
    this.needsAd = false,
    this.currentUserId = '',
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  bool get _isOwnPost =>
      widget.post.userId.isNotEmpty && widget.post.userId == widget.currentUserId;

  void _handleEdit() {
    final ctrl = TextEditingController(text: widget.post.content);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          Text('Edit Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: widget.isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl, maxLines: 5,
            style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "What's on your mind?", hintStyle: TextStyle(color: widget.subColor),
              filled: true,
              fillColor: widget.isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                final text = ctrl.text.trim();
                if (text.isEmpty || text == widget.post.content) { Navigator.pop(ctx); return; }
                Navigator.pop(ctx);
                try {
                  await api.updatePost(widget.post.id, content: text);
                  if (mounted) setState(() => widget.post.content = text);
                } catch (_) {}
              },
              child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  void _handleDelete() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Delete Post?', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
      content: Text('This cannot be undone.', style: TextStyle(color: widget.isDark ? Colors.white60 : Colors.black54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () async {
            Navigator.pop(context);
            try { await api.deletePost(widget.post.id); widget.onPostDeleted(widget.post.id); } catch (_) {}
          },
          child: const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  void _showOptions() {
    final p = widget.post;
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        if (_isOwnPost) ...[
          ListTile(
            leading: const Icon(Iconsax.edit, color: AppColors.primary),
            title: Text('Edit post', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _handleEdit(); },
          ),
          ListTile(
            leading: const Icon(Iconsax.trash, color: AppColors.error),
            title: const Text('Delete post', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _handleDelete(); },
          ),
          Divider(color: widget.borderColor, height: 1),
        ],
        ListTile(
          leading: Icon(Iconsax.copy, color: widget.isDark ? Colors.white70 : Colors.black54),
          title: Text('Copy text', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
          onTap: () { Clipboard.setData(ClipboardData(text: p.content)); Navigator.pop(ctx); },
        ),
        ListTile(
          leading: Icon(Iconsax.share, color: widget.isDark ? Colors.white70 : Colors.black54),
          title: Text('Share to…', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
          onTap: () { Navigator.pop(ctx); widget.onShare(p); },
        ),
        if (!_isOwnPost)
          ListTile(
            leading: Icon(Iconsax.flag, color: widget.isDark ? Colors.white70 : Colors.black54),
            title: Text('Report post', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
            onTap: () => Navigator.pop(ctx),
          ),
        const SizedBox(height: 20),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p  = widget.post;
    final sw = MediaQuery.of(context).size.width;

    return Container(
      color: widget.cardColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header ──────────────────────────────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => context.push('/user-profile/${p.userId}'),
                child: _CachedAvatar(url: p.avatarUrl, fallback: p.avatar, size: 44),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: GestureDetector(
                    onTap: () => context.push('/user-profile/${p.userId}'),
                    child: Text(p.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: widget.textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                  if (p.verified) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.verified_rounded, color: AppColors.primary, size: 14),
                  ],
                  if (p.isPremiumPost) ...[
                    const SizedBox(width: 4),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text('PRO', style: TextStyle(fontSize: 8, color: AppColors.gold, fontWeight: FontWeight.w700))),
                  ],
                ]),
                Text('${p.username} · ${p.time}',
                    style: TextStyle(fontSize: 12, color: widget.subColor),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 6),
              if (p.userId.isNotEmpty && !_isOwnPost)
                GestureDetector(
                  onTap: () => widget.onFollow(p.userId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.isFollowing ? widget.subColor.withOpacity(0.12) : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: widget.isFollowing ? widget.subColor.withOpacity(0.3) : AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.isFollowing) ...[
                        Icon(Icons.check_rounded, size: 11, color: widget.subColor.withOpacity(0.8)),
                        const SizedBox(width: 3),
                      ],
                      Text(widget.isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11,
                              color: widget.isFollowing ? widget.subColor.withOpacity(0.8) : AppColors.primary)),
                    ]),
                  ),
                ),
              const SizedBox(width: 4),
              Flexible(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(p.tag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
              const SizedBox(width: 4),
              GestureDetector(onTap: _showOptions,
                  child: Icon(Icons.more_horiz, color: widget.subColor, size: 20)),
            ]),

            const SizedBox(height: 12),

            _HashtagText(text: p.content,
                textColor: widget.isDark ? const Color(0xFFE8E8F0) : Colors.black87),

            if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostMedia(url: p.mediaUrl!, mediaType: p.mediaType ?? 'image',
                  isDark: widget.isDark, screenWidth: sw),
            ],

            if (p.linkUrl != null && p.linkUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostLinkCard(url: p.linkUrl!, title: p.linkTitle,
                  isDark: widget.isDark, subColor: widget.subColor, textColor: widget.textColor),
            ],

            const SizedBox(height: 14),

            Row(children: [
              _ActionBtn(
                icon:  p.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: _fmt(p.likes),
                color: p.isLiked ? Colors.red : widget.subColor,
                onTap: () => widget.onLike(p),
              ),
              const SizedBox(width: 18),
              _ActionBtn(icon: Iconsax.message, label: _fmt(p.comments),
                  color: widget.subColor, onTap: () => widget.onComment(p)),
              const SizedBox(width: 18),
              _ActionBtn(icon: Iconsax.send_1, label: _fmt(p.shares),
                  color: widget.subColor, onTap: () => widget.onShare(p)),
              const Spacer(),
              GestureDetector(
                onTap: () => widget.onSave(p),
                child: Icon(p.isSaved ? Iconsax.archive_tick : Iconsax.archive_add,
                    color: p.isSaved ? AppColors.primary : widget.subColor, size: 20),
              ),
            ]),
            const SizedBox(height: 12),
          ]),
        ),

        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: widget.borderColor, width: 0.8)),
            color: widget.isDark ? Colors.black.withOpacity(0.3) : Colors.grey.shade50,
          ),
          child: Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => widget.onAskAI(p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(widget.isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 0.8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 18, height: 18,
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(5)),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 10)),
                  const SizedBox(width: 6),
                  const Flexible(child: Text('Ask RiseUp AI',
                      style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (widget.needsAd) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.ondemand_video_rounded, size: 13, color: AppColors.primary.withOpacity(0.7)),
                  ],
                ]),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => widget.onPrivateChat(p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(widget.isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withOpacity(0.25), width: 0.8),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Iconsax.lock_1, color: AppColors.accent, size: 14),
                  SizedBox(width: 6),
                  Text('Chat Privately', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Cached Avatar
// ══════════════════════════════════════════════════════════════════════════════
class _CachedAvatar extends StatelessWidget {
  final String url, fallback;
  final double size;
  const _CachedAvatar({required this.url, required this.fallback, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
    child: ClipOval(
      child: url.isNotEmpty
          ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, width: size, height: size,
              placeholder: (_, __) => Container(color: AppColors.primary.withOpacity(0.1),
                  child: Center(child: Text(fallback, style: const TextStyle(fontSize: 20)))),
              errorWidget: (_, __, ___) => Center(child: Text(fallback, style: const TextStyle(fontSize: 20))))
          : Center(child: Text(fallback, style: const TextStyle(fontSize: 20))),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Hashtag Text
// ══════════════════════════════════════════════════════════════════════════════
class _HashtagText extends StatefulWidget {
  final String text;
  final Color  textColor;
  const _HashtagText({required this.text, required this.textColor});
  @override
  State<_HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<_HashtagText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() { for (final r in _recognizers) r.dispose(); super.dispose(); }

  List<InlineSpan> _buildSpans() {
    for (final r in _recognizers) r.dispose();
    _recognizers.clear();
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(#\w+)');
    int lastEnd = 0;
    for (final m in regex.allMatches(widget.text)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: widget.text.substring(lastEnd, m.start),
            style: TextStyle(color: widget.textColor, fontSize: 14.5, height: 1.6)));
      }
      final tag = m.group(0)!;
      final rec = TapGestureRecognizer()
        ..onTap = () { HapticFeedback.lightImpact(); context.push('/explore?q=${Uri.encodeComponent(tag)}'); };
      _recognizers.add(rec);
      spans.add(TextSpan(text: tag,
          style: const TextStyle(color: AppColors.primary, fontSize: 14.5, height: 1.6, fontWeight: FontWeight.w600),
          recognizer: rec));
      lastEnd = m.end;
    }
    if (lastEnd < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastEnd),
          style: TextStyle(color: widget.textColor, fontSize: 14.5, height: 1.6)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: _buildSpans()));
}

// ══════════════════════════════════════════════════════════════════════════════
// Post Media
// ══════════════════════════════════════════════════════════════════════════════
class _PostMedia extends StatelessWidget {
  final String url, mediaType;
  final bool   isDark;
  final double screenWidth;
  const _PostMedia({required this.url, required this.mediaType,
      required this.isDark, required this.screenWidth});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: mediaType == 'video'
        ? _VideoThumbnail(url: url, isDark: isDark)
        : _ImageThumbnail(url: url, isDark: isDark),
  );
}

class _ImageThumbnail extends StatelessWidget {
  final String url;
  final bool   isDark;
  const _ImageThumbnail({required this.url, required this.isDark});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(context,
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ImageViewerPage(url: url))),
    child: AspectRatio(
      aspectRatio: 4 / 3,
      child: Hero(
        tag: 'img_$url',
        child: CachedNetworkImage(
          imageUrl: url, fit: BoxFit.cover, width: double.infinity,
          placeholder: (_, __) => Container(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
            child: const Center(child: _Shimmer(height: double.infinity)),
          ),
          errorWidget: (_, __, ___) => Container(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
            child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36)),
          ),
        ),
      ),
    ),
  );
}

// ── v5.1 FIX: Removed VideoPlayerController-based thumbnail.
// Creating a VideoPlayerController just to grab a first frame causes Android
// SurfaceTexture YUV artifacts (green/yellow lines). The decoder hasn't
// finished color-space conversion before the VideoPlayer widget renders.
// Replaced with a clean static placeholder — full video plays in
// _FullScreenVideoPage on tap, which is where playback belongs anyway.
class _VideoThumbnail extends StatelessWidget {
  final String url;
  final bool   isDark;
  const _VideoThumbnail({required this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => _FullScreenVideoPage(url: url))),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
          child: Stack(alignment: Alignment.center, children: [
            // Clean placeholder gradient
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                      : [Colors.grey.shade200, Colors.grey.shade300],
                ),
              ),
            )),
            // Play button
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
            ),
            // "Tap to play" label
            Positioned(bottom: 10, right: 10, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text('Tap to play', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
              ]),
            )),
            // Video icon top-left
            Positioned(top: 10, left: 10, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                SizedBox(width: 3),
                Text('Video', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            )),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Full-Screen Video (Chewie)
// v5.1 FIX: removed explicit aspectRatio from ChewieController.
// Passing vp.value.aspectRatio for portrait (9:16) videos caused Chewie to
// render into a wrongly-sized surface → same SurfaceTexture artifacts.
// Chewie auto-detects aspect ratio correctly when not forced.
// ══════════════════════════════════════════════════════════════════════════════
class _FullScreenVideoPage extends StatefulWidget {
  final String url;
  const _FullScreenVideoPage({super.key, required this.url});
  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _vp;
  ChewieController?      _chewie;
  bool _ready = false, _err = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      final vp = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await vp.initialize();
      final ch = ChewieController(
        videoPlayerController: vp,
        autoPlay:        true,
        looping:         false,
        allowFullScreen: true,
        allowMuting:     true,
        showControls:    true,
        // v5.1: aspectRatio intentionally omitted — let Chewie auto-detect.
        // Forcing vp.value.aspectRatio caused portrait video artifacts.
        materialProgressColors: ChewieProgressColors(
          playedColor:    AppColors.primary,
          handleColor:    AppColors.primary,
          backgroundColor: Colors.grey.shade800,
          bufferedColor:  AppColors.primary.withOpacity(0.3),
        ),
        placeholder: const Center(child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2)),
      );
      if (!mounted) { vp.dispose(); ch.dispose(); return; }
      setState(() { _vp = vp; _chewie = ch; _ready = true; });
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void dispose() { _chewie?.dispose(); _vp?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black, elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text('Video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    body: Center(child: _err
        ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline_rounded, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text('Could not load video', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ])
        : _ready && _chewie != null
            ? Chewie(controller: _chewie!)
            : const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Image Viewer
// ══════════════════════════════════════════════════════════════════════════════
class _ImageViewerPage extends StatelessWidget {
  final String url;
  const _ImageViewerPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.black.withOpacity(0.4), elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(icon: const Icon(Icons.copy_rounded, color: Colors.white),
            onPressed: () { Clipboard.setData(ClipboardData(text: url)); }),
        IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ],
    ),
    body: PhotoView(
      imageProvider: CachedNetworkImageProvider(url),
      heroAttributes: PhotoViewHeroAttributes(tag: 'img_$url'),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      initialScale: PhotoViewComputedScale.contained,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64)),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Post Link Card
// ══════════════════════════════════════════════════════════════════════════════
class _PostLinkCard extends StatelessWidget {
  final String url;
  final String? title;
  final bool isDark;
  final Color subColor, textColor;
  const _PostLinkCard({required this.url, this.title, required this.isDark,
      required this.subColor, required this.textColor});

  String get _domain { try { return Uri.parse(url).host; } catch (_) { return url; } }

  Future<void> _open(BuildContext ctx) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) { try { await launchUrl(uri, mode: LaunchMode.inAppWebView); } catch (_) {} }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _open(context),
    child: Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.language_rounded, color: AppColors.primary, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null && title!.isNotEmpty)
            Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
          Text(_domain, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: subColor)),
        ])),
        const SizedBox(width: 6),
        Icon(Icons.open_in_new_rounded, color: subColor, size: 16),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Action Button
// ══════════════════════════════════════════════════════════════════════════════
class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// App Drawer
// ══════════════════════════════════════════════════════════════════════════════
class _AppDrawer extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool isDark;
  const _AppDrawer({required this.profile, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg        = isDark ? Colors.black : Colors.white;
    final border    = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final sub       = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final name      = profile['full_name']?.toString() ?? 'User';
    final stage     = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final isPremium = profile['subscription_tier'] == 'premium';
    final avatarUrl = profile['avatar_url']?.toString() ?? '';

    return Drawer(
      backgroundColor: bg,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            GestureDetector(
              onTap: () { Navigator.pop(context); context.go('/profile'); },
              child: _CachedAvatar(url: avatarUrl,
                  fallback: name.isNotEmpty ? name[0].toUpperCase() : 'U', size: 48),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('${stageInfo['emoji']} ${stageInfo['label']}',
                        style: TextStyle(fontSize: 10, color: stageInfo['color'] as Color, fontWeight: FontWeight.w600))),
                if (isPremium) ...[
                  const SizedBox(width: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Text('PRO', style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700))),
                ],
              ]),
            ])),
            IconButton(icon: Icon(Icons.close_rounded, color: sub, size: 20),
                onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
        Divider(color: border, height: 1),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          _DSection('INCOME TOOLS', sub),
          _DItem(Iconsax.chart,              'Dashboard',           'Earnings, stats & tasks',       isDark, onTap: () { Navigator.pop(context); context.go('/dashboard'); }),
          _DItem(Icons.auto_awesome_rounded, 'Agentic AI',          'Execute ANY income task',       isDark, badge: 'HEAVY', badgeColor: AppColors.accent, onTap: () { Navigator.pop(context); context.push('/agent'); }),
          _DItem(Iconsax.flash,              'Workflow Engine',     'AI-powered income execution',   isDark, badge: 'NEW', badgeColor: AppColors.success, onTap: () { Navigator.pop(context); context.push('/workflow'); }),
          _DItem(Iconsax.chart_3,            'Market Pulse',        'What pays right now',           isDark, badge: 'LIVE', badgeColor: const Color(0xFFFF6B35), onTap: () { Navigator.pop(context); context.push('/pulse'); }),
          _DItem(Icons.emoji_events_rounded, 'Challenges',          '30-day income sprints',         isDark, onTap: () { Navigator.pop(context); context.push('/challenges'); }),
          _DItem(Iconsax.briefcase,          'Client CRM',          'Track prospects & clients',     isDark, onTap: () { Navigator.pop(context); context.push('/crm'); }),
          _DItem(Iconsax.document_text,      'Contracts & Invoices','Pro contract generation',       isDark, onTap: () { Navigator.pop(context); context.push('/contracts'); }),
          _DItem(Icons.psychology_rounded,   'Income Memory',       'Your income DNA',               isDark, onTap: () { Navigator.pop(context); context.push('/memory'); }),
          _DItem(Iconsax.gallery,            'My Portfolio',        'Shareable project showcase',    isDark, onTap: () { Navigator.pop(context); context.push('/portfolio'); }),
          _DItem(Iconsax.task_square,        'My Tasks',            'Daily income tasks',            isDark, onTap: () { Navigator.pop(context); context.go('/tasks'); }),
          _DItem(Iconsax.map_1,              'Wealth Roadmap',      '3-stage wealth plan',           isDark, onTap: () { Navigator.pop(context); context.go('/roadmap'); }),
          _DItem(Iconsax.book,               'Skills',              'Earn-while-learning',           isDark, onTap: () { Navigator.pop(context); context.go('/skills'); }),
          Divider(color: border, height: 1),
          _DSection('SOCIAL', sub),
          _DItem(Iconsax.people,                     'Collaboration', 'Build bigger goals together', isDark, badge: 'NEW', badgeColor: AppColors.primary, onTap: () { Navigator.pop(context); context.push('/collaboration'); }),
          _DItem(Iconsax.message,                    'Messages',      'DMs & group chats',           isDark, onTap: () { Navigator.pop(context); context.go('/messages'); }),
          _DItem(Icons.radio_button_checked_rounded, 'Go Live',       'Stream to your community',    isDark, onTap: () { Navigator.pop(context); context.go('/live'); }),
          _DItem(Iconsax.people,                     'Groups',        'Wealth-building groups',      isDark, onTap: () { Navigator.pop(context); context.go('/groups'); }),
          Divider(color: border, height: 1),
          _DSection('FINANCE', sub),
          _DItem(Iconsax.money_recive, 'Earnings',  'Income tracker',     isDark, onTap: () { Navigator.pop(context); context.go('/earnings'); }),
          _DItem(Iconsax.chart_2,      'Analytics', 'Growth stats',        isDark, onTap: () { Navigator.pop(context); context.go('/analytics'); }),
          _DItem(Iconsax.wallet_minus, 'Expenses',  'Budget tracking',     isDark, onTap: () { Navigator.pop(context); context.go('/expenses'); }),
          _DItem(Iconsax.flag,         'Goals',     'Set & track targets', isDark, onTap: () { Navigator.pop(context); context.go('/goals'); }),
          Divider(color: border, height: 1),
          _DSection('ACCOUNT', sub),
          _DItem(Iconsax.award,     'Achievements', 'Badges & milestones', isDark, onTap: () { Navigator.pop(context); context.go('/achievements'); }),
          _DItem(Iconsax.user_tag,  'Referrals',    'Invite & earn',       isDark, onTap: () { Navigator.pop(context); context.go('/referrals'); }),
          _DItem(Iconsax.setting_2, 'Settings',     'Account preferences', isDark, onTap: () { Navigator.pop(context); context.go('/settings'); }),
        ])),
        if (!isPremium)
          Padding(padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: () { Navigator.pop(context); context.push('/premium'); },
              child: Container(padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const SizedBox(width: 2),
                  const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Upgrade to Premium', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    Text('Unlimited AI + all features', style: TextStyle(fontSize: 11, color: sub)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.primary),
                ]),
              ),
            ),
          ),
      ])),
    );
  }
}

class _DSection extends StatelessWidget {
  final String label; final Color color;
  const _DSection(this.label, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.1)),
  );
}

class _DItem extends StatelessWidget {
  final IconData icon; final String label, sub; final bool isDark;
  final VoidCallback onTap; final String? badge; final Color? badgeColor;
  const _DItem(this.icon, this.label, this.sub, this.isDark,
      {required this.onTap, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    final tc = isDark ? Colors.white : Colors.black87;
    final sc = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    return Material(color: Colors.transparent, child: InkWell(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tc)),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: (badgeColor ?? AppColors.primary).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(badge!, style: TextStyle(fontSize: 9, color: badgeColor ?? AppColors.primary, fontWeight: FontWeight.w700))),
              ],
            ]),
            Text(sub, style: TextStyle(fontSize: 11, color: sc)),
          ])),
          Icon(Icons.chevron_right_rounded, size: 15, color: isDark ? Colors.white.withOpacity(0.24) : Colors.black.withOpacity(0.26)),
        ]),
      ),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Story Widgets
// ══════════════════════════════════════════════════════════════════════════════
class _StoryAddButton extends StatelessWidget {
  final bool isDark; final VoidCallback onTap;
  const _StoryAddButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: GestureDetector(onTap: onTap, child: Column(children: [
      Container(width: 58, height: 58,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
              border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5)),
          child: const Center(child: Icon(Icons.add, color: AppColors.primary, size: 24))),
      const SizedBox(height: 5),
      Text('You', style: TextStyle(fontSize: 11,
          color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54, fontWeight: FontWeight.w600)),
    ])),
  );
}

class _StoryItem extends StatelessWidget {
  final Map<String, dynamic> user; final bool isDark; final VoidCallback onTap;
  const _StoryItem({required this.user, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profile   = (user['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final name      = profile['full_name']?.toString() ?? 'User';
    final avatar    = profile['avatar_url']?.toString() ?? '';
    final isOnline  = profile['is_online'] == true;
    final hasUnseen = user['has_unseen'] == true;
    final shortName = name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(onTap: onTap, child: Column(children: [
        Stack(children: [
          Container(width: 58, height: 58,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: hasUnseen ? const LinearGradient(
                  colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: hasUnseen ? null : (isDark ? AppColors.bgSurface : Colors.grey.shade300),
            ),
            child: Padding(padding: const EdgeInsets.all(2.5),
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle,
                  color: isDark ? Colors.black : Colors.white),
                child: ClipOval(child: avatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover, width: 53, height: 53,
                        errorWidget: (_, __, ___) => _initials(name))
                    : _initials(name)),
              ),
            ),
          ),
          if (isOnline) Positioned(bottom: 1, right: 1, child: Container(
            width: 13, height: 13,
            decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle,
                border: Border.all(color: isDark ? Colors.black : Colors.white, width: 2)),
          )),
        ]),
        const SizedBox(height: 5),
        SizedBox(width: 62, child: Text(shortName, textAlign: TextAlign.center, maxLines: 1,
            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11,
                color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54))),
      ])),
    );
  }

  Widget _initials(String n) => Container(color: AppColors.primary.withOpacity(0.15),
      child: Center(child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary))));
}

// ══════════════════════════════════════════════════════════════════════════════
// Status View Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _StatusViewSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  const _StatusViewSheet({required this.user});
  @override
  State<_StatusViewSheet> createState() => _StatusViewSheetState();
}

class _StatusViewSheetState extends State<_StatusViewSheet> {
  int _idx = 0;

  @override
  void initState() { super.initState(); _markViewed(); }

  void _markViewed() {
    final items = (widget.user['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return;
    final id = items[_idx]['id']?.toString();
    if (id != null) api.post('/posts/status/$id/view', {}).catchError((_) => <String, dynamic>{});
  }

  void _next() {
    final items = widget.user['items'] as List? ?? [];
    if (_idx < items.length - 1) { setState(() { _idx++; _markViewed(); }); }
    else { Navigator.pop(context); }
  }

  void _prev() { if (_idx > 0) setState(() { _idx--; _markViewed(); }); }

  Future<void> _openLink(String link) async {
    final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) { try { await launchUrl(uri, mode: LaunchMode.inAppWebView); } catch (_) {} }
  }

  @override
  Widget build(BuildContext context) {
    final items   = (widget.user['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final profile = (widget.user['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    if (items.isEmpty) return const SizedBox.shrink();

    final sz    = MediaQuery.of(context).size;
    final h     = sz.height * 0.92;
    final sw    = sz.width;

    final name  = profile['full_name']?.toString() ?? 'User';
    final avatar= profile['avatar_url']?.toString() ?? '';
    final item  = items[_idx];
    final media = item['media_url']?.toString();
    final mType = item['media_type']?.toString() ?? 'image';
    final text  = item['content']?.toString() ?? '';
    final bg    = item['background_color']?.toString() ?? '#6C5CE7';
    final link  = item['link_url']?.toString();
    final lTitle= item['link_title']?.toString();

    Color bgColor = AppColors.primary;
    try { bgColor = Color(int.parse(bg.replaceFirst('#', '0xFF'))); } catch (_) {}

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: media != null ? Colors.black : bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(children: [

        // 1 — Background
        if (media != null && mType == 'image')
          Positioned.fill(child: GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ImageViewerPage(url: media))),
            child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: CachedNetworkImage(imageUrl: media, fit: BoxFit.cover, width: sw, height: h,
                  errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)))),
          ))
        else if (media != null && mType == 'video')
          Positioned.fill(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: _StatusVideoPlayer(url: media)))
        else if (text.isNotEmpty)
          Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(32),
              child: Text(text, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, height: 1.5))))),

        // 2 — Progress bar
        Positioned(top: 12, left: 12, right: 12,
          child: Row(children: List.generate(items.length, (i) => Expanded(child: Container(
            height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i <= _idx ? Colors.white : Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ))))),

        // 3 — Caption overlay
        if (media != null && text.isNotEmpty)
          Positioned(bottom: link != null ? 150 : 90, left: 0, right: 0,
            child: Container(color: Colors.black.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(text, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.5)))),

        // 4 — Navigation strips
        Positioned(top: 0, bottom: 0, left: 0, width: sw * 0.3,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _prev,
              child: const ColoredBox(color: Colors.transparent))),
        Positioned(top: 0, bottom: 0, right: 0, width: sw * 0.3,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _next,
              child: const ColoredBox(color: Colors.transparent))),

        // 5 — Link card
        if (link != null)
          Positioned(bottom: 80, left: 16, right: 16,
            child: GestureDetector(onTap: () => _openLink(link),
              child: Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.link_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (lTitle != null && lTitle.isNotEmpty)
                      Text(lTitle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(link, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 16),
                ]),
              ),
            )),

        // 6 — Header
        Positioned(top: 24, left: 16, right: 16,
          child: Row(children: [
            _CachedAvatar(url: avatar, fallback: name.isNotEmpty ? name[0].toUpperCase() : '?', size: 36),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(items.length == 1 ? '1 status' : '${items.length} statuses',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
      ]),
    );
  }
}

// ── Inline status video player
// v5.1 FIX: deferred ctrl.play() to addPostFrameCallback so the SurfaceTexture
// is fully registered with the Flutter texture registry before playback starts.
// Calling play() immediately after initialize() caused the initial frame to
// render with raw YUV data → green/yellow artifact lines on Android.
class _StatusVideoPlayer extends StatefulWidget {
  final String url;
  const _StatusVideoPlayer({super.key, required this.url});
  @override
  State<_StatusVideoPlayer> createState() => _StatusVideoPlayerState();
}

class _StatusVideoPlayerState extends State<_StatusVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false, _err = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _ready = true; });
      // v5.1 FIX: defer play() until after the VideoPlayer widget has been
      // rendered and its SurfaceTexture is fully bound. This prevents the
      // green/yellow artifact that appears when play() is called before the
      // texture registry completes the binding on Android.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl != null) _ctrl!.play();
      });
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_err) return const Center(child: Icon(Icons.error_outline, color: Colors.white54, size: 48));
    if (!_ready || _ctrl == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));

    return GestureDetector(
      onTap: () { _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play(); setState(() {}); },
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(child: FittedBox(fit: BoxFit.cover,
            child: SizedBox(width: _ctrl!.value.size.width, height: _ctrl!.value.size.height,
                child: VideoPlayer(_ctrl!)))),
        if (!_ctrl!.value.isPlaying)
          Container(width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
        Positioned(bottom: 0, left: 0, right: 0,
          child: VideoProgressIndicator(_ctrl!, allowScrubbing: true,
            colors: VideoProgressColors(playedColor: AppColors.primary,
                bufferedColor: AppColors.primary.withOpacity(0.3), backgroundColor: Colors.white24))),
      ]),
    );
  }
}
