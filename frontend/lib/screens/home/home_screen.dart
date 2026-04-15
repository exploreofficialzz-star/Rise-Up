// frontend/lib/screens/home/home_screen.dart
// v10.0 — Production Ready — Full Feature Pack
//
// FEATURES:
//  1. POST VIEWS           → 👁 view count on every post & status card
//  2. POST / STATUS SOUNDS → device DEFAULT tone via showLocalNotification()
//  3. IN-APP BANNERS       → slide-in OverlayEntry for likes/comments/shares/follows
//  4. STATUS REACTIONS     → ❤️ Love + 💬 DM reply in status viewer
//  5. VIDEO PRE-ROLL ADS   → interstitial before video for free users; premium skips
//  6. TRENDING ALGORITHM   → 🔥 engagement-scored tab
//  7. FOLLOWER POSTS NOTIF → 30-second poll + in-app banner
//  8. CACHE-FIRST + SHIMMER→ instant cached posts, skeleton while loading
//  9. DELETE / ADS CRASH   → ScaffoldMessenger.maybeOf + mounted guards everywhere
// 10. BACKGROUND POSTS     → backgroundColor hex → Facebook-style colored card
// + ALL v9.0 FEATURES PRESERVED

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../../services/ad_manager.dart';
import '../../services/notification_service.dart';
import '../../widgets/ad_widgets.dart';
import 'create_status_screen.dart';

import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:photo_view/photo_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sound Service
// ─────────────────────────────────────────────────────────────────────────────
class SoundService {
  static void tap()    => HapticFeedback.selectionClick();
  static void like()   => HapticFeedback.lightImpact();
  static void save()   => HapticFeedback.lightImpact();
  static void comment()=> HapticFeedback.mediumImpact();
  static void share()  => HapticFeedback.mediumImpact();
  static void follow() => HapticFeedback.heavyImpact();

  static Future<void> post() async {
    HapticFeedback.heavyImpact();
    try {
      notificationService.showLocalNotification(
        id: 1001,
        title: '🚀 Post shared!',
        body: 'Your post is now live in the community',
      );
    } catch (_) {}
  }

  static Future<void> statusPost() async {
    HapticFeedback.heavyImpact();
    try {
      notificationService.showLocalNotification(
        id: 1002,
        title: '📸 Status posted!',
        body: 'Your status is now visible to your followers',
      );
    } catch (_) {}
  }

  static Future<void> notification() async {
    HapticFeedback.mediumImpact();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage helper
// ─────────────────────────────────────────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const s = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🆘', 'label': 'Survival', 'color': Color(0xFFE17055)},
      'earning':  {'emoji': '💪', 'label': 'Earning',  'color': Color(0xFF0984E3)},
      'growing':  {'emoji': '🚀', 'label': 'Growing',  'color': Color(0xFF00B894)},
      'wealth':   {'emoji': '💎', 'label': 'Wealth',   'color': Color(0xFF6C5CE7)},
    };
    return s[stage] ?? s['survival']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Model
// ─────────────────────────────────────────────────────────────────────────────
class PostModel {
  final String  id, name, username, time, avatar, avatarUrl, tag;
  String        content;
  final String? mediaUrl, mediaType, linkUrl, linkTitle, backgroundColor;
  int  likes, comments, shares, viewsCount;
  final bool verified, isPremiumPost;
  bool isLiked, isSaved, isFollowing;
  final String userId;

  PostModel({
    required this.id,       required this.name,     required this.username,
    required this.time,     required this.avatar,   this.avatarUrl = '',
    required this.tag,      required this.content,
    this.mediaUrl,          this.mediaType,         this.linkUrl,
    this.linkTitle,         this.backgroundColor,
    required this.likes,    required this.comments, required this.shares,
    this.viewsCount    = 0,
    this.verified      = false,
    this.isPremiumPost = false,
    this.isLiked       = false,
    this.isSaved       = false,
    this.isFollowing   = false,
    this.userId        = '',
  });

  factory PostModel.fromApi(Map<String, dynamic> d) {
    final profile  = (d['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
    final created  = DateTime.tryParse(d['created_at']?.toString() ?? '') ?? DateTime.now();
    final diff     = DateTime.now().difference(created);
    final String t;
    if (diff.inMinutes < 1)       t = 'just now';
    else if (diff.inMinutes < 60) t = '${diff.inMinutes}m ago';
    else if (diff.inHours < 24)   t = '${diff.inHours}h ago';
    else if (diff.inDays < 7)     t = '${diff.inDays}d ago';
    else                          t = '${(diff.inDays / 7).floor()}w ago';

    final name      = profile['full_name']?.toString() ?? 'User';
    final stageInfo = StageInfo.get(profile['stage']?.toString() ?? 'survival');
    final userId    = d['user_id']?.toString().isNotEmpty == true
        ? d['user_id'].toString()
        : profile['id']?.toString() ?? '';

    String raw = d['content']?.toString() ?? '';
    if (raw == '🔗 Link post' || raw == 'Link post') raw = '';

    return PostModel(
      id:              d['id']?.toString() ?? '',
      name:            name,
      username:        '@${name.toLowerCase().replaceAll(' ', '')}',
      time:            t,
      avatar:          stageInfo['emoji'] as String,
      avatarUrl:       profile['avatar_url']?.toString() ?? '',
      tag:             d['tag']?.toString() ?? '💰 Wealth',
      content:         raw,
      mediaUrl:        d['media_url']?.toString(),
      mediaType:       d['media_type']?.toString(),
      linkUrl:         d['link_url']?.toString(),
      linkTitle:       d['link_title']?.toString(),
      backgroundColor: d['background_color']?.toString(),
      likes:       (d['likes_count']    as num?)?.toInt() ?? 0,
      comments:    (d['comments_count'] as num?)?.toInt() ?? 0,
      shares:      (d['shares_count']   as num?)?.toInt() ?? 0,
      viewsCount:  (d['views_count']    as num?)?.toInt() ?? 0,
      verified:      profile['is_verified']       == true,
      isPremiumPost: profile['subscription_tier'] == 'premium',
      isLiked:       d['is_liked']     == true,
      isSaved:       d['is_saved']     == true,
      isFollowing:   d['is_following'] == true,
      userId:        userId,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoPreloadManager
// ─────────────────────────────────────────────────────────────────────────────
final videoPreloadManager = _VideoPreloadManager();

class _PreloadEntry {
  final String url;
  VideoPlayerController? controller;
  bool isReady   = false;
  bool _disposed = false;
  _PreloadEntry(this.url);

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      if (_disposed) { c.dispose(); return; }
      await c.setVolume(0);
      await c.play();
      await Future.delayed(const Duration(milliseconds: 500));
      if (_disposed) { c.dispose(); return; }
      await c.pause();
      await c.seekTo(Duration.zero);
      if (_disposed) { c.dispose(); return; }
      controller = c;
      isReady    = true;
    } catch (_) {}
  }

  void dispose() {
    _disposed  = true;
    isReady    = false;
    controller?.dispose();
    controller = null;
  }
}

class _VideoPreloadManager {
  final LinkedHashMap<String, _PreloadEntry> _pool    = LinkedHashMap();
  final Set<String>                          _loading = {};
  static const int _maxReady = 4;

  void preload(String url) {
    if (kIsWeb || url.isEmpty || _pool.containsKey(url) || _loading.contains(url)) return;
    _loading.add(url);
    final entry = _PreloadEntry(url);
    entry.init().then((_) {
      _loading.remove(url);
      if (!entry.isReady) return;
      while (_pool.length >= _maxReady) {
        final oldest = _pool.keys.first;
        _pool[oldest]?.dispose();
        _pool.remove(oldest);
      }
      _pool[url] = entry;
    });
  }

  VideoPlayerController? claim(String url) {
    if (kIsWeb) return null;
    final entry = _pool[url];
    if (entry == null || !entry.isReady || entry.controller == null) return null;
    final c = entry.controller!;
    entry.controller = null;
    _pool.remove(url);
    return c;
  }

  bool isReady(String url) => !kIsWeb && (_pool[url]?.isReady == true);

  void disposeAll() {
    for (final e in _pool.values) e.dispose();
    _pool.clear();
    _loading.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer helpers
// ─────────────────────────────────────────────────────────────────────────────
class _Sh extends StatelessWidget {
  const _Sh({this.w, required this.h, this.r = 8, this.circle = false});
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
    ).animate(onPlay: (c) => c.repeat())
     .shimmer(duration: 1200.ms, color: dark ? Colors.white10 : Colors.white70);
  }
}

class _PostCardSkeleton extends StatelessWidget {
  const _PostCardSkeleton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    return Container(
      color: isDark ? AppColors.bgCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _Sh(w: 44, h: 44, circle: true),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Sh(w: w * .35, h: 13),
            const SizedBox(height: 5),
            _Sh(w: w * .25, h: 11),
          ])),
          const _Sh(w: 60, h: 26, r: 13),
        ]),
        const SizedBox(height: 14),
        const _Sh(h: 13),
        const SizedBox(height: 6),
        const _Sh(h: 13),
        const SizedBox(height: 6),
        _Sh(w: w * .55, h: 13),
        const SizedBox(height: 12),
        AspectRatio(aspectRatio: 16 / 9, child: _Sh(h: double.infinity, r: 12)),
        const SizedBox(height: 14),
        Row(children: const [
          _Sh(w: 72, h: 34, r: 17), SizedBox(width: 10),
          _Sh(w: 72, h: 34, r: 17), SizedBox(width: 10),
          _Sh(w: 72, h: 34, r: 17), Spacer(),
          _Sh(w: 34, h: 34, r: 17),
        ]),
        const SizedBox(height: 12),
        Row(children: const [
          Expanded(child: _Sh(h: 38, r: 10)),
          SizedBox(width: 8),
          Expanded(child: _Sh(h: 38, r: 10)),
        ]),
      ]),
    );
  }
}

class _StoriesSkel extends StatelessWidget {
  const _StoriesSkel({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext ctx) => Container(
        color: isDark ? AppColors.bgCard : Colors.white,
        height: 92,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: 5,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Column(children: [
              _Sh(w: 58, h: 58, circle: true),
              SizedBox(height: 5),
              _Sh(w: 42, h: 10, r: 5),
            ]),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// In-App Notification Banner
// ─────────────────────────────────────────────────────────────────────────────
class _NotifBannerManager {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String    title,
    required String    message,
    required Color     color,
    required IconData  icon,
    VoidCallback?      onTap,
  }) {
    _entry?.remove();
    _entry = null;
    _entry = OverlayEntry(
      builder: (_) => _InAppNotifBanner(
        title:     title,
        message:   message,
        color:     color,
        icon:      icon,
        onTap:     onTap ?? () {},
        onDismiss: () { _entry?.remove(); _entry = null; },
      ),
    );
    try { Overlay.of(context).insert(_entry!); } catch (_) {}
  }

  static void dismiss() { _entry?.remove(); _entry = null; }
}

class _InAppNotifBanner extends StatefulWidget {
  final String   title, message;
  final Color    color;
  final IconData icon;
  final VoidCallback onTap, onDismiss;

  const _InAppNotifBanner({
    required this.title,   required this.message,
    required this.color,   required this.icon,
    required this.onTap,   required this.onDismiss,
  });

  @override
  State<_InAppNotifBanner> createState() => _InAppNotifBannerState();
}

class _InAppNotifBannerState extends State<_InAppNotifBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset>   _slide;
  late Animation<double>   _fade;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 380), vsync: this);
    _slide = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _autoTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() { _autoTimer?.cancel(); _ctrl.dispose(); super.dispose(); }

  Future<void> _dismiss() async {
    _autoTimer?.cancel();
    if (mounted) await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext ctx) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTap: () { _dismiss(); widget.onTap(); },
              onVerticalDragEnd: (d) { if (d.velocity.pixelsPerSecond.dy < 0) _dismiss(); },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.color.withOpacity(0.4), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: widget.color.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Icon(widget.icon, color: widget.color, size: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.title,   style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(widget.message, style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 12, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: _dismiss, child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5), size: 16)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Screen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  late TabController _tab;
  Map<String, dynamic> _profile = {};
  DateTime? _lastPaused;
  static const _refreshGap = Duration(minutes: 5);

  // ── AI quota ──────────────────────────────────────────────────────────────
  int       _aiUsed     = 0;
  int       _adsWatched = 0;
  DateTime? _adLockout;
  static const int      _freeLimit = 3;
  static const int      _maxAds    = 5;
  static const Duration _lockDur   = Duration(hours: 4);

  // ── Notification badge + polling ──────────────────────────────────────────
  int    _notifCount          = 0;
  int    _lastSeenNotifCount  = 0;
  Timer? _notifTimer;

  // ── Session view tracker ──────────────────────────────────────────────────
  final Set<String> _viewedPosts = {};

  // ── Cache keys ────────────────────────────────────────────────────────────
  static const _kQ  = 'riseup_ai_quota_v1';
  static const _kP  = 'riseup_profile_cache_v1';
  static const _kF  = 'riseup_feed_for_you_v2';
  static const _kSt = 'riseup_status_cache_v1';
  static const _kFw = 'riseup_followed_users';

  // ── Status ────────────────────────────────────────────────────────────────
  List<dynamic> _statusUsers  = [];
  bool          _statusLoaded = false;

  // ── Feed state ────────────────────────────────────────────────────────────
  final _feeds   = <String, List<PostModel>>{'for_you': [], 'following': [], 'trending': []};
  final _loading = <String, bool>            {'for_you': false, 'following': false, 'trending': false};
  final _errors  = <String, String?>         {'for_you': null,  'following': null,  'trending': null};
  final _offsets = <String, int>             {'for_you': 0,     'following': 0,     'trending': 0};
  final _hasMore = <String, bool>            {'for_you': true,  'following': true,  'trending': true};
  final _tabs    = ['for_you', 'following', 'trending'];
  final GlobalKey<ScaffoldState> _sk = GlobalKey<ScaffoldState>();
  final Map<String, bool> _follows   = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (_tab.indexIsChanging) return;
        final t = _tabs[_tab.index];
        if (_feeds[t]!.isEmpty && _errors[t] == null) _loadFeed(t);
      });
    _restoreCache().then((_) => _refreshAll());
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    _notifTimer?.cancel();
    if (!kIsWeb) videoPreloadManager.disposeAll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _lastPaused = DateTime.now();
    } else if (s == AppLifecycleState.resumed && mounted) {
      if (_lastPaused == null || DateTime.now().difference(_lastPaused!) >= _refreshGap) {
        _lastPaused = null;
        _refreshAll();
      }
    }
  }

  // ── Cache restore ─────────────────────────────────────────────────────────
  Future<void> _restoreCache() async {
    try {
      final p = await SharedPreferences.getInstance();

      try {
        final r = p.getString(_kP);
        if (r != null && mounted) setState(() => _profile = Map<String, dynamic>.from(jsonDecode(r) as Map));
      } catch (_) {}

      try {
        final r = p.getString(_kSt);
        if (r != null && mounted) {
          setState(() { _statusUsers = (jsonDecode(r) as List?) ?? []; _statusLoaded = _statusUsers.isNotEmpty; });
        }
      } catch (_) {}

      try {
        final r = p.getString(_kF);
        if (r != null) {
          final posts = (jsonDecode(r) as List)
              .map((x) => PostModel.fromApi(Map<String, dynamic>.from(x as Map)))
              .toList();
          if (posts.isNotEmpty && mounted) {
            setState(() => _feeds['for_you'] = posts);
            if (!kIsWeb) _preloadFeedVideos(posts, startIdx: 0);
          }
        }
      } catch (_) {}

      try {
        final r = p.getString(_kQ);
        if (r != null) {
          final sv    = Map<String, dynamic>.from(jsonDecode(r) as Map);
          final today = DateTime.now().toIso8601String().substring(0, 10);
          if (sv['date'] == today && mounted) {
            setState(() {
              _aiUsed     = sv['used']    as int? ?? 0;
              _adsWatched = sv['ads']     as int? ?? 0;
              final ls    = sv['lockout'] as String?;
              _adLockout  = ls == null ? null : DateTime.tryParse(ls);
            });
          }
        }
      } catch (_) {}

      try {
        final fw = p.getStringList(_kFw) ?? [];
        if (mounted) setState(() { for (final u in fw) _follows[u] = true; });
      } catch (_) {}

    } catch (_) {}
  }

  // ── Parallel refresh ──────────────────────────────────────────────────────
  Future<void> _refreshAll() => Future.wait([
    _loadProfile(),
    _loadStatus(),
    _loadFeed('for_you', refresh: true),
    _loadNotifCount(),
  ]);

  // ── Notification count ────────────────────────────────────────────────────
  Future<void> _loadNotifCount() async {
    try {
      final d = await api.get('/notifications/unread-count');
      if (!mounted) return;
      setState(() => _notifCount = (d['count'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  // ── 30-second notification poll ──────────────────────────────────────────
  Future<void> _pollNotifications() async {
    try {
      final d     = await api.get('/notifications/unread-count');
      if (!mounted) return;
      final count = (d['count'] as num?)?.toInt() ?? 0;

      if (count > _lastSeenNotifCount) {
        try {
          final nd     = await api.get('/notifications/?limit=1');
          final notifs = (nd['notifications'] as List?) ?? [];
          if (notifs.isNotEmpty && mounted) {
            final n = notifs.first as Map;
            if (n['is_read'] != true) {
              _showInAppBanner(
                title:   n['title']?.toString()   ?? 'RiseUp',
                message: n['message']?.toString() ?? '',
                type:    n['type']?.toString()    ?? 'system',
                data:    (n['data'] as Map?)?.cast<String, dynamic>() ?? {},
              );
              SoundService.notification();
            }
          }
        } catch (_) {}
      }

      setState(() {
        _notifCount        = count;
        _lastSeenNotifCount = count;
      });
    } catch (_) {}
  }

  // ── In-app notification banner ─────────────────────────────────────────────
  void _showInAppBanner({
    required String title,
    required String message,
    required String type,
    Map<String, dynamic> data = const {},
  }) {
    if (!mounted) return;
    Color    color;
    IconData icon;
    switch (type) {
      case 'like':            color = Colors.red;          icon = Icons.favorite_rounded;      break;
      case 'comment':         color = AppColors.primary;   icon = Iconsax.message;             break;
      case 'follow':          color = AppColors.success;   icon = Iconsax.user_add;            break;
      case 'share':           color = Colors.blue;         icon = Iconsax.send_1;              break;
      case 'save':            color = AppColors.primary;   icon = Iconsax.archive_add;         break;
      case 'new_post':        color = AppColors.accent;    icon = Icons.post_add_rounded;      break;
      case 'status_reaction': color = Colors.pink;         icon = Icons.favorite_rounded;      break;
      case 'new_status':      color = AppColors.accent;    icon = Icons.auto_stories_rounded;  break;
      default:                color = AppColors.primary;   icon = Iconsax.notification;
    }

    final postId = data['post_id']?.toString();
    final route  = data['route']?.toString();

    _NotifBannerManager.show(
      context,
      title:   title,
      message: message,
      color:   color,
      icon:    icon,
      onTap: () {
        if (route != null && route.isNotEmpty) context.push(route);
        else if (postId != null) context.push('/comments/$postId');
      },
    );
  }

  // ── Record post view ──────────────────────────────────────────────────────
  Future<void> _handleView(String postId) async {
    if (postId.isEmpty || _viewedPosts.contains(postId)) return;
    _viewedPosts.add(postId);
    try { await api.post('/posts/$postId/view', {}); } catch (_) {}
  }

  Future<void> _saveQuota() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kQ, jsonEncode({
        'date':    DateTime.now().toIso8601String().substring(0, 10),
        'used':    _aiUsed,
        'ads':     _adsWatched,
        'lockout': _adLockout?.toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final d    = await api.getProfile();
      final prof = (d['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted && prof.isNotEmpty) {
        setState(() => _profile = prof);
        final p = await SharedPreferences.getInstance();
        await p.setString(_kP, jsonEncode(prof));
      }
    } catch (_) {}
  }

  Future<void> _loadStatus() async {
    try {
      final d     = await api.get('/posts/status/feed');
      final users = ((d as Map<String, dynamic>?)?['users'] as List?) ?? [];
      if (mounted) {
        setState(() { _statusUsers = users; _statusLoaded = true; });
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(_kSt, jsonEncode(users));
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadFeed(String tab, {bool refresh = false}) async {
    if (_loading[tab] == true) return;
    if (refresh) {
      _offsets[tab] = 0;
      _hasMore[tab] = true;
      if (mounted) setState(() => _errors[tab] = null);
    }
    if (!(_hasMore[tab] ?? true)) return;
    if (mounted) setState(() { _loading[tab] = true; _errors[tab] = null; });

    int    attempts = 0;
    Object? lastErr;
    List?   raws;

    while (attempts < 3) {
      attempts++;
      try {
        final d = await api.getFeed(tab: tab, limit: 20, offset: _offsets[tab]!);
        raws    = (d['posts'] as List?) ?? [];
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        if (attempts < 3) await Future.delayed(Duration(seconds: attempts));
      }
    }

    if (lastErr != null) {
      if (mounted) setState(() { _loading[tab] = false; _errors[tab] = _friendlyError(lastErr!); });
      return;
    }

    if (tab == 'for_you' && (_offsets[tab] == 0 || refresh)) _cacheRaw(raws!);

    final posts = raws!.map((x) => PostModel.fromApi(x as Map<String, dynamic>)).toList();

    if (mounted) {
      setState(() {
        for (final post in posts) {
          if (post.userId.isNotEmpty && _follows[post.userId] == null) {
            _follows[post.userId] = post.isFollowing;
          }
        }
        if (refresh) {
          _feeds[tab] = posts;
        } else {
          _feeds[tab] = [..._feeds[tab]!, ...posts];
        }
        _offsets[tab] = (_offsets[tab] ?? 0) + posts.length;
        _hasMore[tab] = posts.length == 20;
        _loading[tab] = false;
        _errors[tab]  = null;
      });
      if (!kIsWeb) _preloadFeedVideos(posts, startIdx: 0);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) return 'No internet connection. Pull down to retry.';
    if (s.contains('TimeoutException') || s.contains('timed out'))         return 'Connection timed out. Pull down to retry.';
    if (s.contains('401') || s.contains('Unauthorized'))                   return 'Session expired. Please log in again.';
    if (s.contains('403') || s.contains('Forbidden'))                      return 'Access denied. Please check your account.';
    if (s.contains('500') || s.contains('Internal Server'))                return 'Server error. Our team has been notified.';
    if (s.contains('404'))                                                  return 'Feed endpoint not found. Check API config.';
    final clean = s.replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
    return clean.length > 100 ? '${clean.substring(0, 100)}…' : clean;
  }

  void _preloadFeedVideos(List<PostModel> posts, {required int startIdx}) {
    if (kIsWeb) return;
    final end = min(startIdx + 5, posts.length);
    for (int i = startIdx; i < end; i++) {
      final post = posts[i];
      if (post.mediaType == 'video' && post.mediaUrl != null && post.mediaUrl!.isNotEmpty) {
        videoPreloadManager.preload(post.mediaUrl!);
      }
    }
  }

  Future<void> _cacheRaw(List<dynamic> raws) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kF, jsonEncode(raws.take(40).toList()));
    } catch (_) {}
  }

  Future<void> _saveFw() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kFw, _follows.entries.where((e) => e.value).map((e) => e.key).toList());
    } catch (_) {}
  }

  bool get _isPremium => (_profile['subscription_tier'] ?? 'free') == 'premium';
  int  get _aiLeft    => (_freeLimit - _aiUsed).clamp(0, _freeLimit);
  bool get _adLocked  {
    if (_adLockout == null) return false;
    if (DateTime.now().isAfter(_adLockout!)) { _adLockout = null; return false; }
    return true;
  }

  // ── Follow ────────────────────────────────────────────────────────────────
  Future<void> _handleFollow(String uid) async {
    if (uid.isEmpty) return;
    SoundService.follow();
    final prev = _follows[uid] ?? false;
    setState(() { _follows[uid] = !prev; _syncFw(uid, !prev); });
    try {
      final r = await api.toggleFollow(uid);
      final v = r['following'] == true;
      if (mounted) { setState(() { _follows[uid] = v; _syncFw(uid, v); }); await _saveFw(); }
    } catch (_) {
      if (mounted) setState(() { _follows[uid] = prev; _syncFw(uid, prev); });
    }
  }

  void _syncFw(String uid, bool v) {
    for (final t in _tabs) {
      for (final p in _feeds[t]!) {
        if (p.userId == uid) p.isFollowing = v;
      }
    }
  }

  // ── Share ─────────────────────────────────────────────────────────────────
  void _handleShare(PostModel post) {
    SoundService.share();
    setState(() => post.shares++);
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: dark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 4), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('Share Post', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: dark ? Colors.white : Colors.black87)),
        ),
        ListTile(
          leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.link_rounded, color: AppColors.primary, size: 20)),
          title: Text('Copy post link', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dark ? Colors.white : Colors.black87)),
          onTap: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: 'https://riseup.app/post/${post.id}'));
            _snack('Link copied', AppColors.success);
          },
        ),
        ListTile(
          leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.copy_rounded, color: Colors.blue, size: 20)),
          title: Text('Copy text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dark ? Colors.white : Colors.black87)),
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
    if (post.content.isNotEmpty) {
      api.recordInteractionSignal(action: 'share', postId: post.id, postContent: post.content);
    }
  }

  // ── AI ────────────────────────────────────────────────────────────────────
  Future<void> _handleAI(PostModel post, {required bool isPrivate}) async {
    if (_isPremium) { await _execAI(post, priv: isPrivate); return; }
    if (_aiUsed < _freeLimit) {
      if (!mounted) return;
      setState(() => _aiUsed++);
      await _saveQuota();
      if (mounted) await _execAI(post, priv: isPrivate);
      return;
    }
    if (_adLocked) { _showLockout(); return; }
    if (_adsWatched >= _maxAds) {
      if (!mounted) return;
      setState(() => _adLockout = DateTime.now().add(_lockDur));
      await _saveQuota();
      _showLockout();
      return;
    }
    final ok = await _showAdPrompt();
    if (!ok || !mounted) return;

    try {
      await adService.showRewardedAd(
        featureKey: 'post_ai',
        onRewarded: () async {
          if (!mounted) return;
          setState(() { _aiUsed = 0; _adsWatched++; });
          await _saveQuota();
          if (mounted) await _execAI(post, priv: isPrivate);
        },
        onDismissed: () {
          if (mounted) _snack('Watch the full ad to unlock AI.', AppColors.error);
        },
      );
    } catch (e) {
      if (mounted) _snack('Ad failed to load. Please try again.', AppColors.error);
    }
  }

  Future<void> _execAI(PostModel post, {required bool priv}) async {
    if (!mounted) return;
    if (priv) {
      context.push('/conversation/ai'
          '?name=${Uri.encodeComponent("RiseUp AI")}'
          '&avatar=${Uri.encodeComponent("AI")}&isAI=true'
          '&postContext=${Uri.encodeComponent(post.content)}'
          '&postAuthor=${Uri.encodeComponent(post.name)}');
    } else {
      await _postAIComment(post);
    }
  }

  Future<void> _postAIComment(PostModel post) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(SnackBar(
      content: Row(children: const [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('RiseUp AI is thinking…'),
      ]),
      backgroundColor: AppColors.primary,
      duration: const Duration(seconds: 120),
    ));

    final StringBuffer promptBuf = StringBuffer();
    promptBuf.write('A RiseUp community member posted: "${post.content}"');
    if (post.mediaUrl != null && post.mediaUrl!.isNotEmpty) {
      if (post.mediaType == 'image') {
        promptBuf.write('\n\nThe post includes an image at: ${post.mediaUrl}. Extract any visible text, prices, charts, or key information and incorporate that context into your wealth-building insight.');
      } else if (post.mediaType == 'video') {
        promptBuf.write('\n\nThe post includes a video at: ${post.mediaUrl}. Use the post content and metadata to provide video-context-aware wealth-building insights.');
      }
    }
    if (post.linkUrl != null && post.linkUrl!.isNotEmpty) {
      promptBuf.write('\n\nA link was also shared: ${post.linkUrl}');
      if (post.linkTitle != null && post.linkTitle!.isNotEmpty) {
        promptBuf.write(' (titled "${post.linkTitle}")');
      }
    }
    promptBuf.write('\n\nGive a concise (2–3 sentence) actionable wealth-building insight. Be specific and helpful.');

    String err = '';
    try {
      final res = await api.chat(message: promptBuf.toString(), mode: 'general');
      final txt = (res['content'] as String?)?.trim() ?? '';
      if (txt.isEmpty) throw Exception('Empty AI response');
      await api.addComment(post.id, 'RiseUp AI: $txt', isAI: true, isPinned: true);
      if (mounted) setState(() => post.comments++);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: const Text('AI insight pinned in comments!'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View', textColor: Colors.white,
          onPressed: () {
            if (mounted) context.push('/comments/${post.id}?content=${Uri.encodeComponent(post.content)}&author=${Uri.encodeComponent(post.name)}');
          },
        ),
      ));
      return;
    } on ApiException catch (e) {
      if (e.statusCode == 422)                          err = _parseValidationError(e.message);
      else if (e.statusCode == 429)                     err = 'AI rate limit reached. Please wait a moment.';
      else if (e.statusCode != null && e.statusCode! >= 500) err = 'AI is temporarily unavailable. Please try again.';
      else                                              err = e.message.isNotEmpty ? e.message : 'AI request failed.';
    } catch (e) {
      final s = e.toString();
      if (s.contains('[{') || s.contains('string_pattern_mismatch')) err = _parseValidationError(s);
      else if (s.contains('Timeout') || s.contains('Socket'))        err = 'Connection timed out. Check your network.';
      else { err = s.replaceAll('Exception: ', ''); if (err.length > 120) err = '${err.substring(0, 120)}…'; }
    }

    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(err.isEmpty ? 'AI request failed. Please try again.' : err),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 5),
    ));
  }

  String _parseValidationError(String raw) {
    try {
      final start = raw.indexOf('[{');
      final end   = raw.lastIndexOf('}]');
      if (start >= 0 && end > start) {
        final list  = jsonDecode(raw.substring(start, end + 2)) as List;
        if (list.isNotEmpty) {
          final first = list.first as Map;
          final loc   = (first['loc'] as List?)?.join(' → ') ?? '';
          final msg   = first['msg']?.toString() ?? '';
          if (loc.isNotEmpty && msg.isNotEmpty) return 'Invalid request ($loc): $msg';
        }
      }
    } catch (_) {}
    return 'AI request failed. Please try again.';
  }

  Future<bool> _showAdPrompt() async {
    if (!mounted) return false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: dark ? AppColors.bgCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Watch a short ad?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: dark ? Colors.white : Colors.black87)),
          content: Text(
            'You\'ve used your $_freeLimit free responses today.\n\nWatch a 30-second ad to unlock more.\n\n${_maxAds - _adsWatched} unlock(s) remaining today.',
            style: TextStyle(color: dark ? Colors.white60 : Colors.black54, height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Watch Ad', style: TextStyle(color: Colors.white)),
            ),
          ],
        )) ?? false;
  }

  void _showLockout() {
    if (!mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final diff = _adLockout != null ? _adLockout!.difference(DateTime.now()) : Duration.zero;
    final h    = diff.inHours;
    final m    = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final ts   = diff.isNegative ? 'shortly' : (h > 0 ? '${h}h ${m}m' : '${diff.inMinutes}m');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Daily Limit Reached'),
        content: Text('Resets in $ts or upgrade to Premium.', style: TextStyle(color: dark ? Colors.white60 : Colors.black54, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () { Navigator.pop(context); if (mounted) context.push('/premium'); },
            child: const Text('Go Premium', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _viewStatus(Map<String, dynamic> user) {
    if ((user['items'] as List? ?? []).isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusViewSheet(user: user, onReact: _handleStatusReact),
    );
  }

  Future<void> _handleStatusReact(String statusId, String reaction) async {
    try {
      await api.post('/posts/status/$statusId/react', {'reaction': reaction});
      SoundService.like();
    } catch (_) {}
  }

  void _snack(String msg, Color bg, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg, duration: duration));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final bg     = dark ? Colors.black : Colors.white;
    final card   = dark ? AppColors.bgCard : Colors.white;
    final border = dark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt    = dark ? Colors.white : Colors.black87;
    final sub    = dark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final ico    = dark ? Colors.white.withOpacity(0.7) : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      key: _sk,
      drawer: _AppDrawer(profile: _profile, isDark: dark),
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent, titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: ico, size: 24),
          onPressed: () { SoundService.tap(); _sk.currentState?.openDrawer(); },
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFFF6B00), Color(0xFFFFD700), Color(0xFF6C5CE7)],
            stops: [0.0, 0.4, 1.0],
          ).createShader(b),
          child: const Text('RiseUp', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
        ),
        centerTitle: true,
        actions: [
          if (!_isPremium)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('$_aiLeft left', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: ico, size: 22),
            tooltip: 'Search posts',
            onPressed: () { SoundService.tap(); Navigator.push(context, MaterialPageRoute(builder: (_) => _ContentSearchScreen(isDark: dark))); },
          ),
          Stack(children: [
            IconButton(
              icon: Icon(Icons.notifications_rounded, color: ico, size: 22),
              tooltip: 'Notifications',
              onPressed: () {
                SoundService.tap();
                if (mounted) setState(() { _notifCount = 0; _lastSeenNotifCount = 0; });
                context.go('/notifications');
              },
            ),
            if (_notifCount > 0)
              Positioned(
                right: 8, top: 8,
                child: IgnorePointer(child: Container(
                  width: 17, height: 17,
                  decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle, border: Border.all(color: card, width: 1.5)),
                  child: Center(child: Text(_notifCount > 9 ? '9+' : '$_notifCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))),
                )),
              ),
          ]),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: border)),
      ),
      body: Column(children: [
        // ── Stories ──────────────────────────────────────────────────────────
        Container(color: card, child: Column(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: !_statusLoaded
                ? _StoriesSkel(isDark: dark, key: const ValueKey('sk'))
                : SizedBox(
                    key: const ValueKey('r'),
                    height: 92,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _statusUsers.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _StoryAdd(
                            isDark: dark,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateStatusScreen()))
                                .then((_) => _loadStatus()),
                          );
                        }
                        final u = _statusUsers[i - 1] as Map<String, dynamic>;
                        return _StoryItem(user: u, isDark: dark, onTap: () => _viewStatus(u));
                      },
                    ),
                  ),
          ),
          Divider(height: 1, color: border),
        ])),
        // ── Tabs ──────────────────────────────────────────────────────────────
        Container(color: card, child: Column(children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary, unselectedLabelColor: sub,
            indicatorColor: AppColors.primary, indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [Tab(text: 'For You'), Tab(text: 'Following'), Tab(text: 'Trending')],
          ),
          Divider(height: 1, color: border),
        ])),
        // ── Feed ──────────────────────────────────────────────────────────────
        Expanded(child: TabBarView(
          controller: _tab,
          children: _tabs.map((tab) => _FeedTab(
            key: PageStorageKey(tab),
            tab: tab,
            posts: _feeds[tab]!,
            isLoading: _loading[tab] == true,
            hasMore: _hasMore[tab] ?? true,
            errorMsg: _errors[tab],
            isDark: dark, cardColor: card, borderColor: border, textColor: txt, subColor: sub,
            isPremium: _isPremium, aiRemaining: _aiLeft,
            needsAd: _aiLeft <= 0 && !_isPremium,
            currentUserId: _profile['id']?.toString() ?? '',
            followState: _follows,
            onLoadMore: () => _loadFeed(tab),
            onRefresh:  () => _loadFeed(tab, refresh: true),
            onAskAI:        (p) => _handleAI(p, isPrivate: false),
            onPrivateChat:  (p) => _handleAI(p, isPrivate: true),
            onFollow:       _handleFollow,
            onShare:        _handleShare,
            onPreloadVideos: _preloadFeedVideos,
            onView:          _handleView,
            onPostDeleted: (id) => Future.microtask(() {
              if (mounted) setState(() { for (final t in _tabs) _feeds[t]!.removeWhere((p) => p.id == id); });
            }),
            onLike: (p) async {
              SoundService.like();
              setState(() { p.isLiked = !p.isLiked; p.likes += p.isLiked ? 1 : -1; });
              try {
                final r = await api.toggleLike(p.id);
                if (mounted) setState(() => p.isLiked = r['liked'] == true);
                if (r['liked'] == true && p.content.isNotEmpty) {
                  api.recordInteractionSignal(action: 'like', postId: p.id, postContent: p.content);
                }
              } catch (_) {
                if (mounted) setState(() { p.isLiked = !p.isLiked; p.likes += p.isLiked ? 1 : -1; });
              }
            },
            onSave: (p) async {
              SoundService.save();
              setState(() => p.isSaved = !p.isSaved);
              try {
                final r = await api.toggleSave(p.id);
                if (mounted) setState(() => p.isSaved = r['saved'] == true);
                if (r['saved'] == true && p.content.isNotEmpty) {
                  api.recordInteractionSignal(action: 'save', postId: p.id, postContent: p.content);
                }
              } catch (_) {
                if (mounted) setState(() => p.isSaved = !p.isSaved);
              }
            },
            onComment: (p) {
              SoundService.comment();
              context.push('/comments/${p.id}?content=${Uri.encodeComponent(p.content)}&author=${Uri.encodeComponent(p.name)}');
            },
          )).toList(),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content Search Screen
// ─────────────────────────────────────────────────────────────────────────────
class _ContentSearchScreen extends StatefulWidget {
  final bool isDark;
  const _ContentSearchScreen({super.key, required this.isDark});
  @override
  State<_ContentSearchScreen> createState() => _ContentSearchScreenState();
}

class _ContentSearchScreenState extends State<_ContentSearchScreen> {
  final TextEditingController _ctrl  = TextEditingController();
  final FocusNode             _focus = FocusNode();
  List<PostModel> _results  = [];
  List<String>    _recent   = [];
  bool            _loading  = false;
  bool            _searched = false;
  Timer?          _debounce;
  static const _kRecent = 'riseup_search_recent_v1';

  @override
  void initState() {
    super.initState();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); _debounce?.cancel(); super.dispose(); }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => _recent = p.getStringList(_kRecent) ?? []);
    } catch (_) {}
  }

  Future<void> _saveRecent(String q) async {
    try {
      final p    = await SharedPreferences.getInstance();
      final list = [q, ..._recent.where((r) => r != q)].take(10).toList();
      await p.setStringList(_kRecent, list);
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _removeRecent(String q) async {
    try {
      final p    = await SharedPreferences.getInstance();
      final list = _recent.where((r) => r != q).toList();
      await p.setStringList(_kRecent, list);
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      if (mounted) setState(() { _results = []; _searched = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () => _search(val.trim()));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty || !mounted) return;
    setState(() { _loading = true; _searched = true; });
    await _saveRecent(q);
    try {
      final d     = await api.get('/posts/search?q=${Uri.encodeComponent(q)}&limit=30');
      final posts = ((d['posts'] as List?) ?? []).map((x) => PostModel.fromApi(x as Map<String, dynamic>)).toList();
      if (mounted) setState(() { _results = posts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _results = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final dark   = widget.isDark;
    final bg     = dark ? Colors.black : Colors.white;
    final card   = dark ? AppColors.bgCard : Colors.white;
    final border = dark ? AppColors.bgSurface : Colors.grey.shade200;
    final sub    = dark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final txt    = dark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: dark ? Colors.white70 : Colors.black54),
          onPressed: () => Navigator.pop(ctx),
        ),
        titleSpacing: 0,
        title: Container(
          height: 40, margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(color: dark ? AppColors.bgSurface : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
          child: TextField(
            controller: _ctrl, focusNode: _focus, onChanged: _onChanged,
            onSubmitted: (v) => _search(v.trim()),
            style: TextStyle(fontSize: 14, color: txt, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search posts, hashtags, people…',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: sub, size: 18),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(icon: Icon(Icons.close_rounded, color: sub, size: 16), onPressed: () {
                      _ctrl.clear();
                      if (mounted) setState(() { _results = []; _searched = false; });
                      _focus.requestFocus();
                    })
                  : null,
              filled: false, border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
          : !_searched
              ? _recentView(dark, sub, txt)
              : _results.isEmpty
                  ? _emptyView(sub)
                  : _resultsView(dark, card, border, txt, sub),
    );
  }

  Widget _recentView(bool dark, Color sub, Color txt) {
    if (_recent.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_rounded, size: 52, color: sub.withOpacity(0.4)),
        const SizedBox(height: 12),
        Text('Search posts, hashtags & people', style: TextStyle(color: sub, fontSize: 14)),
      ]));
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
        Text('Recent Searches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.8)),
        const Spacer(),
        GestureDetector(
          onTap: () async {
            try {
              final p = await SharedPreferences.getInstance();
              await p.remove(_kRecent);
              if (mounted) setState(() => _recent = []);
            } catch (_) {}
          },
          child: Text('Clear all', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ])),
      ..._recent.map((q) => ListTile(
        dense: true,
        leading: Icon(Icons.history_rounded, size: 18, color: sub),
        title: Text(q, style: TextStyle(fontSize: 13, color: dark ? Colors.white : Colors.black87)),
        trailing: IconButton(icon: Icon(Icons.close_rounded, size: 14, color: sub), onPressed: () => _removeRecent(q)),
        onTap: () { _ctrl.text = q; _search(q); },
      )),
    ]);
  }

  Widget _emptyView(Color sub) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('📭', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 12),
    Text('No results found', style: TextStyle(color: sub, fontSize: 14)),
    const SizedBox(height: 4),
    Text('Try different keywords', style: TextStyle(color: sub, fontSize: 12)),
  ]));

  Widget _resultsView(bool dark, Color card, Color border, Color txt, Color sub) {
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
      itemBuilder: (ctx, i) {
        final p = _results[i];
        return PostCard(
          key: ValueKey('search_${p.id}'),
          post: p, isDark: dark, cardColor: card, borderColor: border, textColor: txt, subColor: sub,
          onAskAI: (_) {}, onPrivateChat: (_) {}, onLike: (_) {}, onSave: (_) {}, onShare: (_) {},
          onComment: (post) => ctx.push('/comments/${post.id}?content=${Uri.encodeComponent(post.content)}&author=${Uri.encodeComponent(post.name)}'),
          onFollow: (_) {}, onPostDeleted: (_) {}, onView: (_) {},
          isPremium: false, aiRemaining: 0, isFollowing: p.isFollowing, currentUserId: '',
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed Tab
// ─────────────────────────────────────────────────────────────────────────────
class _FeedTab extends StatefulWidget {
  final String tab;
  final List<PostModel> posts;
  final bool isLoading, hasMore, isDark, isPremium, needsAd;
  final Color cardColor, borderColor, textColor, subColor;
  final int aiRemaining;
  final String currentUserId;
  final String? errorMsg;
  final Map<String, bool> followState;
  final VoidCallback onLoadMore, onRefresh;
  final Function(PostModel) onAskAI, onPrivateChat, onLike, onSave, onComment, onShare;
  final Function(String)    onFollow, onPostDeleted, onView;
  final void Function(List<PostModel> posts, {required int startIdx}) onPreloadVideos;

  const _FeedTab({
    super.key,
    required this.tab,           required this.posts,
    required this.isLoading,     required this.hasMore,
    required this.isDark,        required this.cardColor,
    required this.borderColor,   required this.textColor,
    required this.subColor,      required this.isPremium,
    required this.aiRemaining,   required this.needsAd,
    required this.currentUserId, required this.followState,
    required this.onLoadMore,    required this.onRefresh,
    required this.onAskAI,       required this.onPrivateChat,
    required this.onLike,        required this.onSave,
    required this.onComment,     required this.onShare,
    required this.onFollow,      required this.onPostDeleted,
    required this.onView,        required this.onPreloadVideos,
    this.errorMsg,
  });

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> with AutomaticKeepAliveClientMixin {
  final ScrollController _sc = ScrollController();
  bool _paginationFired  = false;
  int  _lastPreloadedIdx = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _sc.addListener(_onScroll); }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final pos = _sc.position;

    if (pos.pixels >= pos.maxScrollExtent * 0.7 && !_paginationFired && !widget.isLoading && widget.hasMore) {
      _paginationFired = true;
      widget.onLoadMore();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _paginationFired = false; });
    }

    if (!kIsWeb) {
      const estimatedItemH = 500.0;
      final visibleIdx     = max(0, (pos.pixels / estimatedItemH).floor());
      final preloadFrom    = visibleIdx + 1;
      if (preloadFrom > _lastPreloadedIdx && preloadFrom < widget.posts.length) {
        _lastPreloadedIdx = preloadFrom;
        widget.onPreloadVideos(widget.posts, startIdx: preloadFrom);
      }
    }
  }

  @override
  Widget build(BuildContext ctx) {
    super.build(ctx);
    final posts  = widget.posts;
    final border = widget.borderColor;

    if (widget.errorMsg != null && posts.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.cloud_off_rounded, size: 52, color: widget.subColor.withOpacity(0.5)),
        const SizedBox(height: 16),
        Text(widget.errorMsg!, textAlign: TextAlign.center, style: TextStyle(color: widget.subColor, fontSize: 14, height: 1.5)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
          label: const Text('Try Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          onPressed: widget.onRefresh,
        ),
      ])));
    }

    if (widget.isLoading && posts.isEmpty) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
        itemBuilder: (_, __) => _PostCardSkeleton(isDark: widget.isDark),
      );
    }

    if (posts.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No posts yet', style: TextStyle(color: widget.subColor, fontSize: 14)),
        const SizedBox(height: 8),
        GestureDetector(onTap: widget.onRefresh, child: const Text('Refresh', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
      ]));
    }

    final total = adManager.feedItemCount(posts.length) + 1;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: AppColors.primary,
      child: ListView.separated(
        controller: _sc,
        cacheExtent: 3000,
        padding: EdgeInsets.zero,
        itemCount: total,
        separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
        itemBuilder: (_, i) {
          if (i == total - 1) {
            if (widget.isLoading) return _PostCardSkeleton(isDark: widget.isDark);
            if (!widget.hasMore) return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("You're all caught up ✓", style: TextStyle(color: widget.subColor, fontSize: 13))));
            return const SizedBox(height: 40);
          }

          if (adManager.shouldShowFeedAd(i)) {
            return FeedAdCard(isDark: widget.isDark, cardColor: widget.cardColor, borderColor: border, textColor: widget.textColor, subColor: widget.subColor);
          }

          final pi = adManager.realPostIndex(i);
          if (pi >= posts.length) return const SizedBox.shrink();
          final post = posts[pi];
          final fol  = widget.followState[post.userId] ?? post.isFollowing;

          return PostCard(
            key: ValueKey('post_${post.id}'),
            post: post, isDark: widget.isDark, cardColor: widget.cardColor,
            borderColor: border, textColor: widget.textColor, subColor: widget.subColor,
            onAskAI: widget.onAskAI, onPrivateChat: widget.onPrivateChat,
            onLike: widget.onLike, onSave: widget.onSave,
            onComment: widget.onComment, onShare: widget.onShare,
            onFollow: widget.onFollow, onPostDeleted: widget.onPostDeleted,
            onView: widget.onView,
            isPremium: widget.isPremium, aiRemaining: widget.aiRemaining,
            needsAd: widget.needsAd, isFollowing: fol, currentUserId: widget.currentUserId,
          ).animate().fadeIn(
            delay:    Duration(milliseconds: (pi % 5) * 20),
            duration: const Duration(milliseconds: 200),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────────────────────
class PostCard extends StatefulWidget {
  final PostModel post;
  final bool isDark, isPremium, isFollowing, needsAd;
  final Color cardColor, borderColor, textColor, subColor;
  final Function(PostModel) onAskAI, onPrivateChat, onLike, onSave, onComment, onShare;
  final Function(String)    onFollow, onPostDeleted, onView;
  final int aiRemaining;
  final String currentUserId;

  const PostCard({
    super.key,
    required this.post,           required this.isDark,
    required this.cardColor,      required this.borderColor,
    required this.textColor,      required this.subColor,
    required this.onAskAI,        required this.onPrivateChat,
    required this.onLike,         required this.onSave,
    required this.onComment,      required this.onShare,
    required this.onFollow,       required this.onPostDeleted,
    required this.onView,
    required this.isPremium,      required this.aiRemaining,
    required this.isFollowing,    this.needsAd = false,
    this.currentUserId = '',
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _expanded  = false;
  bool _viewFired = false;
  static const int _collapseAt = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fireView());
  }

  void _fireView() {
    if (_viewFired) return;
    _viewFired = true;
    widget.onView(widget.post.id);
    if (mounted) setState(() => widget.post.viewsCount++);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  bool get _isOwn  => widget.post.userId.isNotEmpty && widget.post.userId == widget.currentUserId;
  bool get _isLong => widget.post.content.length > _collapseAt;

  String get _displayContent =>
      _expanded || !_isLong ? widget.post.content : '${widget.post.content.substring(0, _collapseAt)}…';

  Color? get _bgColor {
    final hex = widget.post.backgroundColor;
    if (hex == null || hex.isEmpty) return null;
    try { return Color(int.parse(hex.replaceAll('#', '0xFF'))); } catch (_) { return null; }
  }

  // Pre-roll ad before video for free users
  Future<void> _playVideo(BuildContext ctx, String url) async {
    if (!widget.isPremium && widget.post.mediaType == 'video') {
      final dur = await _getVideoDurationSeconds(url);
      if (dur >= 60) {
        try { await adService.forceShowInterstitial(); } catch (_) {}
      } else {
        try { await adService.showInterstitialIfReady(); } catch (_) {}
      }
    }
    if (!ctx.mounted) return;
    Navigator.push(ctx, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _VidFull(url: url)));
  }

  Future<int> _getVideoDurationSeconds(String url) async {
    if (kIsWeb) return 0;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      final dur = c.value.duration.inSeconds;
      await c.dispose();
      return dur;
    } catch (_) { return 0; }
  }

  void _edit() {
    final ctrl = TextEditingController(text: widget.post.content);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          Text('Edit Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: widget.isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl, maxLines: 5,
            style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "What's on your mind?",
              hintStyle: TextStyle(color: widget.subColor),
              filled: true,
              fillColor: widget.isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              final t = ctrl.text.trim();
              if (t.isEmpty || t == widget.post.content) { Navigator.pop(ctx); return; }
              Navigator.pop(ctx);
              try { await api.updatePost(widget.post.id, content: t); if (mounted) setState(() => widget.post.content = t); } catch (_) {}
            },
            child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  void _delete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Post?', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
        content: Text('This cannot be undone.', style: TextStyle(color: widget.isDark ? Colors.white60 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              final id        = widget.post.id;
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                await api.deletePost(id);
                if (mounted) widget.onPostDeleted(id);
              } catch (_) {
                messenger?.showSnackBar(const SnackBar(
                  content: Text('Failed to delete. Please try again.'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 2),
                ));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _options() {
    final p = widget.post;
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        if (_isOwn) ...[
          ListTile(
            leading: const Icon(Iconsax.edit, color: AppColors.primary),
            title: Text('Edit post', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _edit(); },
          ),
          ListTile(
            leading: const Icon(Iconsax.trash, color: AppColors.error),
            title: const Text('Delete post', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _delete(); },
          ),
          Divider(color: widget.borderColor, height: 1),
        ],
        ListTile(
          leading: Icon(Iconsax.copy, color: widget.isDark ? Colors.white70 : Colors.black54),
          title: Text('Copy text', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
          onTap: () { Clipboard.setData(ClipboardData(text: p.content)); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1))); },
        ),
        ListTile(
          leading: Icon(Iconsax.link, color: widget.isDark ? Colors.white70 : Colors.black54),
          title: Text('Copy post link', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
          onTap: () { Clipboard.setData(ClipboardData(text: 'https://riseup.app/post/${p.id}')); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1))); },
        ),
        ListTile(
          leading: Icon(Iconsax.share, color: widget.isDark ? Colors.white70 : Colors.black54),
          title: Text('Share to…', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
          onTap: () { Navigator.pop(ctx); widget.onShare(p); },
        ),
        if (!_isOwn)
          ListTile(
            leading: Icon(Iconsax.flag, color: widget.isDark ? Colors.white70 : Colors.black54),
            title: Text('Report post', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
            onTap: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.'), duration: Duration(seconds: 2))); },
          ),
        const SizedBox(height: 20),
      ])),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final p  = widget.post;
    final sw = MediaQuery.of(ctx).size.width;
    final bg = _bgColor;
    final bool isColoredPost = bg != null && (p.mediaUrl == null || p.mediaUrl!.isEmpty);

    return Container(
      color: widget.cardColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header ──────────────────────────────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () { SoundService.tap(); ctx.push('/user-profile/${p.userId}'); },
                child: _Avatar(url: p.avatarUrl, fallback: p.avatar, size: 44),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: GestureDetector(
                    onTap: () { SoundService.tap(); ctx.push('/user-profile/${p.userId}'); },
                    child: Text(p.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                  if (p.verified) ...[const SizedBox(width: 3), const Icon(Icons.verified_rounded, color: AppColors.primary, size: 14)],
                  if (p.isPremiumPost) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text('PRO', style: TextStyle(fontSize: 8, color: AppColors.gold, fontWeight: FontWeight.w700)))],
                ]),
                Text('${p.username} · ${p.time}', style: TextStyle(fontSize: 12, color: widget.subColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 6),
              if (p.userId.isNotEmpty && !_isOwn)
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
                      if (widget.isFollowing) ...[Icon(Icons.check_rounded, size: 11, color: widget.subColor.withOpacity(0.8)), const SizedBox(width: 3)],
                      Text(widget.isFollowing ? 'Following' : 'Follow', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: widget.isFollowing ? widget.subColor.withOpacity(0.8) : AppColors.primary)),
                    ]),
                  ),
                ),
              const SizedBox(width: 4),
              Flexible(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(p.tag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
              const SizedBox(width: 4),
              GestureDetector(onTap: _options, child: Icon(Icons.more_horiz, color: widget.subColor, size: 20)),
            ]),

            const SizedBox(height: 12),

            // ── Content ──────────────────────────────────────────────────────
            if (p.content.isNotEmpty) ...[
              if (isColoredPost)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 110),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text(p.content, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.55))),
                )
              else ...[
                _HTag(text: _displayContent, textColor: widget.isDark ? const Color(0xFFE8E8F0) : Colors.black87),
                if (_isLong) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'Read less' : 'Read more', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ],

            // ── Media ─────────────────────────────────────────────────────────
            if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostMedia(
                url: p.mediaUrl!, mediaType: p.mediaType ?? 'image',
                isDark: widget.isDark, sw: sw,
                linkUrl: p.linkUrl, linkTitle: p.linkTitle,
                isPremium: widget.isPremium,
                onPlayVideo: (url) => _playVideo(ctx, url),
              ),
            ],

            // ── Standalone link card ──────────────────────────────────────────
            if (p.linkUrl != null && p.linkUrl!.isNotEmpty && (p.mediaUrl == null || p.mediaUrl!.isEmpty)) ...[
              const SizedBox(height: 10),
              _LinkCard(url: p.linkUrl!, title: p.linkTitle, isDark: widget.isDark, sub: widget.subColor, txt: widget.textColor),
            ],

            SizedBox(height: (p.content.isNotEmpty || p.mediaUrl != null || p.linkUrl != null) ? 14 : 4),

            // ── Action row ────────────────────────────────────────────────────
            Row(children: [
              _ActBtn(
                icon:    p.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label:   _fmt(p.likes),
                color:   p.isLiked ? Colors.red : widget.subColor,
                bgColor: p.isLiked ? Colors.red.withOpacity(0.10) : widget.subColor.withOpacity(0.07),
                onTap: () => widget.onLike(p),
              ),
              const SizedBox(width: 8),
              _ActBtn(icon: Iconsax.message, label: _fmt(p.comments), color: widget.subColor, bgColor: widget.subColor.withOpacity(0.07), onTap: () => widget.onComment(p)),
              const SizedBox(width: 8),
              _ActBtn(icon: Iconsax.send_1, label: _fmt(p.shares), color: widget.subColor, bgColor: widget.subColor.withOpacity(0.07), onTap: () => widget.onShare(p)),
              const SizedBox(width: 8),
              // Views pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(color: widget.subColor.withOpacity(0.07), borderRadius: BorderRadius.circular(22)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.visibility_outlined, size: 14, color: widget.subColor),
                  const SizedBox(width: 4),
                  Text(_fmt(p.viewsCount), style: TextStyle(fontSize: 12, color: widget.subColor, fontWeight: FontWeight.w500)),
                ]),
              ),
              const Spacer(),
              Material(color: Colors.transparent, child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => widget.onSave(p),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.isSaved ? AppColors.primary.withOpacity(0.12) : widget.subColor.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(p.isSaved ? Iconsax.archive_tick : Iconsax.archive_add, color: p.isSaved ? AppColors.primary : widget.subColor, size: 20),
                ),
              )),
            ]),
            const SizedBox(height: 12),
          ]),
        ),

        // ── AI buttons ────────────────────────────────────────────────────────
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
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(widget.isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 0.8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 15),
                  const SizedBox(width: 6),
                  const Flexible(child: Text('Ask RiseUp AI', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (widget.needsAd) ...[const SizedBox(width: 4), Icon(Icons.ondemand_video_rounded, size: 13, color: AppColors.primary.withOpacity(0.7))],
                ]),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => widget.onPrivateChat(p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String url, fallback;
  final double size;
  const _Avatar({required this.url, required this.fallback, required this.size});
  @override
  Widget build(BuildContext ctx) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
    child: ClipOval(child: url.isNotEmpty
        ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, width: size, height: size, placeholder: (_, __) => _fb(), errorWidget: (_, __, ___) => _fb())
        : _fb()),
  );
  Widget _fb() => Container(color: AppColors.primary.withOpacity(0.15), child: Center(child: Text(fallback, style: const TextStyle(fontSize: 20))));
}

class _HTag extends StatefulWidget {
  final String text; final Color textColor;
  const _HTag({required this.text, required this.textColor});
  @override State<_HTag> createState() => _HTagState();
}

class _HTagState extends State<_HTag> {
  final List<TapGestureRecognizer> _r = [];
  @override void dispose() { for (final r in _r) r.dispose(); super.dispose(); }

  List<InlineSpan> _spans() {
    for (final r in _r) r.dispose(); _r.clear();
    final spans = <InlineSpan>[];
    final re = RegExp(r'(#\w+|@\w+)'); int last = 0;
    for (final m in re.allMatches(widget.text)) {
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start), style: TextStyle(color: widget.textColor, fontSize: 14.5, height: 1.6)));
      final token = m.group(0)!; final isHash = token.startsWith('#');
      final rec = TapGestureRecognizer()..onTap = () { HapticFeedback.lightImpact(); context.push('/explore?q=${Uri.encodeComponent(isHash ? token : token.substring(1))}'); };
      _r.add(rec);
      spans.add(TextSpan(text: token, style: TextStyle(color: isHash ? AppColors.primary : AppColors.accent, fontSize: 14.5, height: 1.6, fontWeight: FontWeight.w600), recognizer: rec));
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last), style: TextStyle(color: widget.textColor, fontSize: 14.5, height: 1.6)));
    return spans;
  }

  @override Widget build(BuildContext ctx) => Text.rich(TextSpan(children: _spans()));
}

class _LinkCard extends StatelessWidget {
  final String url; final String? title; final bool isDark; final Color sub, txt;
  const _LinkCard({required this.url, this.title, required this.isDark, required this.sub, required this.txt});
  String get _domain { try { return Uri.parse(url).host.replaceFirst('www.', ''); } catch (_) { return url; } }

  Future<void> _open(BuildContext ctx) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (kIsWeb) { try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {} return; }
    try { if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.inAppWebView); return; } } catch (_) {}
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: () => _open(ctx),
    child: Container(
      height: 68, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: isDark ? AppColors.bgSurface : Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.18))),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.language_rounded, color: AppColors.primary, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null && title!.isNotEmpty) Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: txt)),
          Text(_domain, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: sub)),
        ])),
        const SizedBox(width: 6),
        Icon(Icons.open_in_new_rounded, color: sub, size: 16),
      ]),
    ),
  );
}

class _ActBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color, bgColor; final VoidCallback onTap;
  const _ActBtn({required this.icon, required this.label, required this.color, required this.bgColor, required this.onTap});
  @override
  Widget build(BuildContext ctx) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      splashColor: color.withOpacity(0.15), highlightColor: color.withOpacity(0.08),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(22)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}

class _PostMedia extends StatelessWidget {
  final String url, mediaType; final bool isDark, isPremium; final double sw;
  final String? linkUrl, linkTitle;
  final Future<void> Function(String url) onPlayVideo;
  const _PostMedia({required this.url, required this.mediaType, required this.isDark, required this.sw, required this.onPlayVideo, this.linkUrl, this.linkTitle, this.isPremium = false});

  @override
  Widget build(BuildContext ctx) {
    final hasLink = linkUrl != null && linkUrl!.isNotEmpty;
    Widget media;
    if (mediaType == 'video') {
      media = kIsWeb ? _WebVideoPlaceholder(url: url, isDark: isDark) : _VidThumb(url: url, isDark: isDark, onPlay: () => onPlayVideo(url));
    } else {
      media = _ImgThumb(url: url, isDark: isDark);
    }
    if (!hasLink) return ClipRRect(borderRadius: BorderRadius.circular(12), child: media);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        mediaType == 'video'
            ? (kIsWeb ? _WebVideoPlaceholder(url: url, isDark: isDark) : _VidThumb(url: url, isDark: isDark, onPlay: () => onPlayVideo(url)))
            : _ImgThumb(url: url, isDark: isDark),
        Positioned(bottom: 0, left: 0, right: 0, child: _MediaLinkOverlay(url: linkUrl!, title: linkTitle)),
      ]),
    );
  }
}

class _MediaLinkOverlay extends StatelessWidget {
  final String url; final String? title;
  const _MediaLinkOverlay({required this.url, this.title});
  String get _domain { try { return Uri.parse(url).host.replaceFirst('www.', ''); } catch (_) { return url; } }

  Future<void> _open(BuildContext ctx) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (kIsWeb) { try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {} return; }
    try { if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.inAppWebView); return; } } catch (_) {}
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: () => _open(ctx),
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.82)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.language_rounded, color: Colors.white, size: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (title != null && title!.isNotEmpty) Text(title!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(_domain, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.4))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Open', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            SizedBox(width: 3),
            Icon(Icons.open_in_new_rounded, color: Colors.white, size: 10),
          ]),
        ),
      ]),
    ),
  );
}

class _WebVideoPlaceholder extends StatelessWidget {
  final String url; final bool isDark;
  const _WebVideoPlaceholder({required this.url, required this.isDark});
  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: () async { try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {} },
    child: AspectRatio(aspectRatio: 16 / 9, child: Container(
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.6), width: 2)), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40)),
        const SizedBox(height: 10),
        Text('Tap to open video', style: TextStyle(color: isDark ? Colors.white60 : Colors.black45, fontSize: 12)),
      ]),
    )),
  );
}

class _ImgThumb extends StatelessWidget {
  final String url; final bool isDark;
  const _ImgThumb({required this.url, required this.isDark});
  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ImgView(url: url))),
    child: AspectRatio(aspectRatio: 4 / 3, child: Hero(tag: 'img_$url', child: CachedNetworkImage(
      imageUrl: url, fit: BoxFit.cover, width: double.infinity,
      placeholder: (_, __) => Container(color: isDark ? Colors.grey.shade900 : Colors.grey.shade200),
      errorWidget: (_, __, ___) => Container(color: isDark ? Colors.grey.shade900 : Colors.grey.shade200, child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36))),
    ))),
  );
}

class _VidThumb extends StatefulWidget {
  final String url; final bool isDark; final VoidCallback onPlay;
  const _VidThumb({required this.url, required this.isDark, required this.onPlay});
  @override State<_VidThumb> createState() => _VidThumbState();
}

class _VidThumbState extends State<_VidThumb> {
  VideoPlayerController? _c; bool _ready = false; bool _err = false;
  @override void initState() { super.initState(); if (!kIsWeb) _init(); }

  Future<void> _init() async {
    final preloaded = videoPreloadManager.claim(widget.url);
    if (preloaded != null) { if (!mounted) { preloaded.dispose(); return; } setState(() { _c = preloaded; _ready = true; }); return; }
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize(); if (!mounted) { c.dispose(); return; }
      await c.setVolume(0); await c.play(); await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) { c.dispose(); return; } await c.pause(); await c.seekTo(Duration.zero);
      if (!mounted) { c.dispose(); return; } setState(() { _c = c; _ready = true; });
    } catch (_) { if (mounted) setState(() => _err = true); }
  }

  @override void dispose() { _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext ctx) {
    final ratio = (_ready && _c != null && _c!.value.aspectRatio > 0) ? _c!.value.aspectRatio.clamp(0.5, 2.0) : 16 / 9;
    return GestureDetector(
      onTap: widget.onPlay,
      child: AspectRatio(aspectRatio: ratio, child: Stack(children: [
        if (_err) Positioned.fill(child: Container(color: widget.isDark ? Colors.grey.shade900 : Colors.grey.shade200, child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36))))
        else if (_ready && _c != null) Positioned.fill(child: VideoPlayer(_c!))
        else Positioned.fill(child: Container(color: widget.isDark ? Colors.grey.shade900 : Colors.grey.shade200, child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))))),
        Positioned.fill(child: Center(child: Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.6), width: 2)), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)))),
        Positioned(bottom: 10, right: 10, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 12), SizedBox(width: 4), Text('Tap to play', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500))]),
        )),
      ])),
    );
  }
}

class _VidFull extends StatefulWidget {
  final String url;
  const _VidFull({super.key, required this.url});
  @override State<_VidFull> createState() => _VidFullState();
}

class _VidFullState extends State<_VidFull> {
  VideoPlayerController? _vp; ChewieController? _ch; bool _ready = false; bool _err = false;
  @override void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    if (kIsWeb) { try { await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication); } catch (_) {} if (mounted) Navigator.pop(context); return; }
    try {
      final vp = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await vp.initialize();
      final ch = ChewieController(
        videoPlayerController: vp, autoPlay: true, looping: false,
        allowFullScreen: true, allowMuting: true, showControls: true, aspectRatio: vp.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(playedColor: AppColors.primary, handleColor: AppColors.primary, backgroundColor: Colors.grey.shade800, bufferedColor: AppColors.primary.withOpacity(0.3)),
        placeholder: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      );
      if (!mounted) { vp.dispose(); ch.dispose(); return; }
      setState(() { _vp = vp; _ch = ch; _ready = true; });
    } catch (_) { if (mounted) setState(() => _err = true); }
  }

  @override void dispose() { _ch?.dispose(); _vp?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, elevation: 0, iconTheme: const IconThemeData(color: Colors.white), title: const Text('Video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
    body: Center(child: _err
        ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.error_outline_rounded, color: Colors.white54, size: 64), SizedBox(height: 16), Text('Could not load video', style: TextStyle(color: Colors.white70, fontSize: 16))])
        : _ready && _ch != null ? Chewie(controller: _ch!) : const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
  );
}

class _ImgView extends StatelessWidget {
  final String url;
  const _ImgView({super.key, required this.url});
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: Colors.black, extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.black.withOpacity(0.4), elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(icon: const Icon(Icons.copy_rounded, color: Colors.white), onPressed: () => Clipboard.setData(ClipboardData(text: url))),
        IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
      ],
    ),
    body: PhotoView(
      imageProvider: CachedNetworkImageProvider(url),
      heroAttributes: PhotoViewHeroAttributes(tag: 'img_$url'),
      minScale: PhotoViewComputedScale.contained, maxScale: PhotoViewComputedScale.covered * 4,
      initialScale: PhotoViewComputedScale.contained,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Story row widgets
// ─────────────────────────────────────────────────────────────────────────────
class _StoryAdd extends StatelessWidget {
  final bool isDark; final VoidCallback onTap;
  const _StoryAdd({required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: GestureDetector(onTap: onTap, child: Column(children: [
      Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? AppColors.bgSurface : Colors.grey.shade200, border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5)), child: const Center(child: Icon(Icons.add, color: AppColors.primary, size: 24))),
      const SizedBox(height: 5),
      Text('You', style: TextStyle(fontSize: 11, color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54, fontWeight: FontWeight.w600)),
    ])),
  );
}

class _StoryItem extends StatelessWidget {
  final Map<String, dynamic> user; final bool isDark; final VoidCallback onTap;
  const _StoryItem({required this.user, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext ctx) {
    final prof   = (user['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final name   = prof['full_name']?.toString() ?? 'User';
    final av     = prof['avatar_url']?.toString() ?? '';
    final on     = prof['is_online']  == true;
    final unseen = user['has_unseen'] == true;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(onTap: onTap, child: Column(children: [
        Stack(children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: unseen ? const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: unseen ? null : (isDark ? AppColors.bgSurface : Colors.grey.shade300),
            ),
            child: Padding(padding: const EdgeInsets.all(2.5), child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.black : Colors.white),
              child: ClipOval(child: av.isNotEmpty ? CachedNetworkImage(imageUrl: av, fit: BoxFit.cover, width: 53, height: 53, errorWidget: (_, __, ___) => _ini(name)) : _ini(name)),
            )),
          ),
          if (on) Positioned(bottom: 1, right: 1, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: isDark ? Colors.black : Colors.white, width: 2)))),
        ]),
        const SizedBox(height: 5),
        SizedBox(width: 62, child: Text(name.split(' ').first, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54))),
      ])),
    );
  }
  Widget _ini(String n) => Container(color: AppColors.primary.withOpacity(0.15), child: Center(child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary))));
}

// ─────────────────────────────────────────────────────────────────────────────
// Status viewer — v10.0: ❤️ React + 💬 DM reply + 👁 views
// ─────────────────────────────────────────────────────────────────────────────
class _StatusViewSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final Future<void> Function(String statusId, String reaction) onReact;
  const _StatusViewSheet({required this.user, required this.onReact});
  @override State<_StatusViewSheet> createState() => _StatusViewSheetState();
}

class _StatusViewSheetState extends State<_StatusViewSheet> {
  int _idx = 0;
  @override void initState() { super.initState(); _markViewed(); }

  void _markViewed() {
    final items = _items;
    if (items.isEmpty) return;
    final id = items[_idx]['id']?.toString();
    if (id != null) api.post('/posts/status/$id/view', {}).catchError((_) => <String, dynamic>{});
  }

  List<Map<String, dynamic>> get _items => (widget.user['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  Map<String, dynamic> get _profile => (widget.user['profile'] as Map?)?.cast<String, dynamic>() ?? {};

  void _next() { if (_idx < _items.length - 1) { setState(() { _idx++; _markViewed(); }); } else { Navigator.pop(context); } }
  void _prev() { if (_idx > 0) setState(() { _idx--; _markViewed(); }); }

  Future<void> _openLink(String link) async {
    final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
    if (kIsWeb) { try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {} return; }
    try { if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.inAppWebView); return; } } catch (_) {}
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext ctx) {
    final items = _items;
    final prof  = _profile;
    if (items.isEmpty) return const SizedBox.shrink();
    final sz       = MediaQuery.of(ctx).size;
    final h        = sz.height * 0.92;
    final sw       = sz.width;
    final name     = prof['full_name']?.toString() ?? 'User';
    final av       = prof['avatar_url']?.toString() ?? '';
    final item     = items[_idx];
    final media    = item['media_url']?.toString();
    final mType    = item['media_type']?.toString() ?? 'image';
    final text     = item['content']?.toString() ?? '';
    final bg       = item['background_color']?.toString() ?? '#6C5CE7';
    final link     = item['link_url']?.toString();
    final ltitle   = item['link_title']?.toString();
    final views    = (item['views_count'] as num?)?.toInt() ?? 0;
    final statusId = item['id']?.toString() ?? '';

    Color bgc = AppColors.primary;
    try { bgc = Color(int.parse(bg.replaceFirst('#', '0xFF'))); } catch (_) {}

    return Container(
      height: h,
      decoration: BoxDecoration(color: media != null ? Colors.black : bgc, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Stack(children: [

        // Background
        if (media != null && mType == 'image')
          Positioned.fill(child: GestureDetector(
            onTap: () => Navigator.push(ctx, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ImgView(url: media))),
            child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: CachedNetworkImage(imageUrl: media, fit: BoxFit.cover, width: sw, height: h, errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)))),
          ))
        else if (media != null && mType == 'video')
          Positioned.fill(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: kIsWeb ? _WebVideoPlaceholder(url: media, isDark: true) : _StatusVid(key: ValueKey('${_idx}_$media'), url: media)))
        else if (text.isNotEmpty)
          Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, height: 1.5))))),

        // Progress bar
        Positioned(top: 12, left: 12, right: 12, child: Row(children: List.generate(items.length, (i) => Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: i <= _idx ? Colors.white : Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2))))))),

        // Caption overlay on media
        if (media != null && text.isNotEmpty)
          Positioned(bottom: link != null ? 200 : 140, left: 0, right: 0, child: Container(color: Colors.black.withOpacity(0.5), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.5)))),

        // Navigation zones
        Positioned(top: 0, bottom: 0, left: 0, width: sw * 0.3, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _prev, child: const ColoredBox(color: Colors.transparent))),
        Positioned(top: 0, bottom: 0, right: 0, width: sw * 0.3, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _next, child: const ColoredBox(color: Colors.transparent))),

        // Link card
        if (link != null)
          Positioned(bottom: 130, left: 16, right: 16, child: GestureDetector(
            onTap: () => _openLink(link),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.link_rounded, color: Colors.white, size: 18), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (ltitle != null && ltitle.isNotEmpty) Text(ltitle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(link, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 16),
              ]),
            ),
          )),

        // ── v10.0 Bottom bar: ❤️ React + 💬 Reply + 👁 Views ──────────────
        Positioned(bottom: 0, left: 0, right: 0, child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.72), Colors.transparent])),
          child: Row(children: [
            GestureDetector(
              onTap: () async {
                SoundService.like();
                await widget.onReact(statusId, '❤️');
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('❤️ Reacted!'), duration: Duration(seconds: 1)));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('❤️', style: TextStyle(fontSize: 18)), SizedBox(width: 6), Text('Love', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))]),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                final userId = prof['id']?.toString() ?? '';
                if (userId.isNotEmpty) { Navigator.pop(ctx); ctx.push('/conversation/$userId?name=${Uri.encodeComponent(name)}'); }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Iconsax.message, color: Colors.white, size: 17), SizedBox(width: 6), Text('Reply', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))]),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.visibility_outlined, color: Colors.white70, size: 14),
                const SizedBox(width: 5),
                Text('$views', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        )),

        // Header
        Positioned(top: 24, left: 16, right: 16, child: Row(children: [
          _Avatar(url: av, fallback: name.isNotEmpty ? name[0].toUpperCase() : '?', size: 36),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(items.length == 1 ? '1 status' : '${items.length} statuses', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status video player
// ─────────────────────────────────────────────────────────────────────────────
class _StatusVid extends StatefulWidget {
  final String url;
  const _StatusVid({super.key, required this.url});
  @override State<_StatusVid> createState() => _StatusVidState();
}

class _StatusVidState extends State<_StatusVid> {
  VideoPlayerController? _c; bool _ready = false; bool _err = false;
  @override void initState() { super.initState(); if (!kIsWeb) _init(); }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize(); if (!mounted) { c.dispose(); return; }
      await c.setVolume(0); await c.play(); await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) { c.dispose(); return; } await c.pause(); await c.seekTo(Duration.zero);
      await c.setVolume(1); await c.setLooping(true); await c.play();
      if (!mounted) { c.dispose(); return; } setState(() { _c = c; _ready = true; });
    } catch (_) { if (mounted) setState(() => _err = true); }
  }

  @override void dispose() { _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext ctx) {
    if (_err)             return const Center(child: Icon(Icons.error_outline, color: Colors.white54, size: 48));
    if (!_ready || _c == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    return GestureDetector(
      onTap: () { _c!.value.isPlaying ? _c!.pause() : _c!.play(); setState(() {}); },
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _c!.value.size.width, height: _c!.value.size.height, child: VideoPlayer(_c!)))),
        if (!_c!.value.isPlaying) Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
        Positioned(bottom: 0, left: 0, right: 0, child: VideoProgressIndicator(_c!, allowScrubbing: true, colors: VideoProgressColors(playedColor: AppColors.primary, bufferedColor: AppColors.primary.withOpacity(0.3), backgroundColor: Colors.white24))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Drawer
// ─────────────────────────────────────────────────────────────────────────────
class _AppDrawer extends StatelessWidget {
  final Map<String, dynamic> profile; final bool isDark;
  const _AppDrawer({required this.profile, required this.isDark});

  @override
  Widget build(BuildContext ctx) {
    final bg    = isDark ? Colors.black : Colors.white;
    final bdr   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final sub   = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final name  = profile['full_name']?.toString() ?? 'User';
    final si    = StageInfo.get(profile['stage']?.toString() ?? 'survival');
    final isPro = profile['subscription_tier'] == 'premium';
    final av    = profile['avatar_url']?.toString() ?? '';

    return Drawer(
      backgroundColor: bg,
      width: MediaQuery.of(ctx).size.width * 0.82,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            GestureDetector(onTap: () { Navigator.pop(ctx); ctx.go('/profile'); }, child: _Avatar(url: av, fallback: name.isNotEmpty ? name[0].toUpperCase() : 'U', size: 48)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: (si['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text('${si['emoji']} ${si['label']}', style: TextStyle(fontSize: 10, color: si['color'] as Color, fontWeight: FontWeight.w600))),
                if (isPro) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Text('PRO', style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700)))],
              ]),
            ])),
            IconButton(icon: Icon(Icons.close_rounded, color: sub, size: 20), onPressed: () => Navigator.of(ctx).pop()),
          ]),
        ),
        Divider(color: bdr, height: 1),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          _DS('INCOME TOOLS', sub),
          _DI(Iconsax.chart, 'Dashboard',        'Earnings, stats & tasks',       isDark, onTap: () { Navigator.pop(ctx); ctx.go('/dashboard'); }),
          _DI(Icons.auto_awesome_rounded, 'Agentic AI', 'Execute ANY income task', isDark, badge: 'HEAVY', bc: AppColors.accent, onTap: () { Navigator.pop(ctx); ctx.push('/agent'); }),
          _DI(Iconsax.flash, 'Workflow Engine',  'AI-powered income execution',   isDark, badge: 'NEW', bc: AppColors.success, onTap: () { Navigator.pop(ctx); ctx.push('/workflow'); }),
          _DI(Iconsax.chart_3, 'Market Pulse',   'What pays right now',           isDark, badge: 'LIVE', bc: const Color(0xFFFF6B35), onTap: () { Navigator.pop(ctx); ctx.push('/pulse'); }),
          _DI(Icons.emoji_events_rounded, 'Challenges', '30-day income sprints',  isDark, onTap: () { Navigator.pop(ctx); ctx.push('/challenges'); }),
          _DI(Iconsax.briefcase, 'Client CRM',   'Track prospects & clients',     isDark, onTap: () { Navigator.pop(ctx); ctx.push('/crm'); }),
          _DI(Iconsax.document_text, 'Contracts & Invoices', 'Pro contract generation', isDark, onTap: () { Navigator.pop(ctx); ctx.push('/contracts'); }),
          _DI(Icons.psychology_rounded, 'Income Memory', 'Your income DNA',       isDark, onTap: () { Navigator.pop(ctx); ctx.push('/memory'); }),
          _DI(Iconsax.gallery, 'My Portfolio',   'Shareable project showcase',    isDark, onTap: () { Navigator.pop(ctx); ctx.push('/portfolio'); }),
          _DI(Iconsax.task_square, 'My Tasks',   'Daily income tasks',            isDark, onTap: () { Navigator.pop(ctx); ctx.go('/tasks'); }),
          _DI(Iconsax.map_1, 'Wealth Roadmap',   '3-stage wealth plan',           isDark, onTap: () { Navigator.pop(ctx); ctx.go('/roadmap'); }),
          _DI(Iconsax.book, 'Skills',             'Earn-while-learning',           isDark, onTap: () { Navigator.pop(ctx); ctx.go('/skills'); }),
          Divider(color: bdr, height: 1),
          _DS('SOCIAL', sub),
          _DI(Iconsax.people, 'Collaboration',   'Build bigger goals together',   isDark, badge: 'NEW', bc: AppColors.primary, onTap: () { Navigator.pop(ctx); ctx.push('/collaboration'); }),
          _DI(Iconsax.message, 'Messages',       'DMs & group chats',             isDark, onTap: () { Navigator.pop(ctx); ctx.go('/messages'); }),
          _DI(Icons.radio_button_checked_rounded, 'Go Live', 'Stream to your community', isDark, onTap: () { Navigator.pop(ctx); ctx.go('/live'); }),
          _DI(Iconsax.people, 'Groups',          'Wealth-building groups',        isDark, onTap: () { Navigator.pop(ctx); ctx.go('/groups'); }),
          Divider(color: bdr, height: 1),
          _DS('FINANCE', sub),
          _DI(Iconsax.money_recive, 'Earnings',  'Income tracker',                isDark, onTap: () { Navigator.pop(ctx); ctx.go('/earnings'); }),
          _DI(Iconsax.chart_2, 'Analytics',      'Growth stats',                  isDark, onTap: () { Navigator.pop(ctx); ctx.go('/analytics'); }),
          _DI(Iconsax.wallet_minus, 'Expenses',  'Budget tracking',               isDark, onTap: () { Navigator.pop(ctx); ctx.go('/expenses'); }),
          _DI(Iconsax.flag, 'Goals',             'Set & track targets',           isDark, onTap: () { Navigator.pop(ctx); ctx.go('/goals'); }),
          Divider(color: bdr, height: 1),
          _DS('ACCOUNT', sub),
          _DI(Iconsax.award, 'Achievements',     'Badges & milestones',           isDark, onTap: () { Navigator.pop(ctx); ctx.go('/achievements'); }),
          _DI(Iconsax.user_tag, 'Referrals',     'Invite & earn',                 isDark, onTap: () { Navigator.pop(ctx); ctx.go('/referrals'); }),
          _DI(Iconsax.setting_2, 'Settings',     'Account preferences',           isDark, onTap: () { Navigator.pop(ctx); ctx.go('/settings'); }),
        ])),
        if (!isPro)
          Padding(
            padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: () { Navigator.pop(ctx); ctx.push('/premium'); },
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(isDark ? 0.12 : 0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.25))),
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

class _DS extends StatelessWidget {
  final String l; final Color c;
  const _DS(this.l, this.c);
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
    child: Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c, letterSpacing: 1.1)),
  );
}

class _DI extends StatelessWidget {
  final IconData icon; final String label, sub; final bool isDark;
  final VoidCallback onTap; final String? badge; final Color? bc;
  const _DI(this.icon, this.label, this.sub, this.isDark, {required this.onTap, this.badge, this.bc});

  @override
  Widget build(BuildContext ctx) {
    final tc = isDark ? Colors.white : Colors.black87;
    final sc = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    return Material(color: Colors.transparent, child: InkWell(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: isDark ? AppColors.bgSurface : Colors.grey.shade100, borderRadius: BorderRadius.circular(9)), child: Icon(icon, size: 17, color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tc)),
            if (badge != null) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: (bc ?? AppColors.primary).withOpacity(0.15), borderRadius: BorderRadius.circular(5)), child: Text(badge!, style: TextStyle(fontSize: 9, color: bc ?? AppColors.primary, fontWeight: FontWeight.w700)))],
          ]),
          Text(sub, style: TextStyle(fontSize: 11, color: sc)),
        ])),
        Icon(Icons.chevron_right_rounded, size: 15, color: isDark ? Colors.white.withOpacity(0.24) : Colors.black.withOpacity(0.26)),
      ])),
    ));
  }
}
