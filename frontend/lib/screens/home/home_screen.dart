// frontend/lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../../services/ad_manager.dart';
import '../../widgets/ad_widgets.dart';
import '../ai/post_ai_sheet.dart';
import 'create_status_screen.dart';

// ── Sound Service — production silent stubs ───────────
class SoundService {
  static void like()    {}
  static void comment() {}
  static void share()   {}
  static void save()    {}
  static void follow()  {}
  static void post()    {}
  static void success() {}
  static void tap()     {}
  static void refresh() {}
}

// ── Stage Info helper ──────────────────────────────────
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

// ── Post Model ────────────────────────────────────────
class PostModel {
  final String id;
  final String name;
  final String username;
  final String time;
  final String avatar;
  final String avatarUrl;   // ← real photo URL (may be empty)
  final String tag;
  final String content;
  final String? mediaUrl;   // ← image / video URL attached to post
  final String? mediaType;  // ← 'image' | 'video'
  int likes;
  int comments;
  int shares;
  final bool verified;
  final bool isPremiumPost;
  bool isLiked;
  bool isSaved;
  bool isFollowing;         // ← server-side follow state for this post author
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
    required this.likes,
    required this.comments,
    required this.shares,
    this.verified = false,
    this.isPremiumPost = false,
    this.isLiked = false,
    this.isSaved = false,
    this.isFollowing = false,
    this.userId = '',
  });

  factory PostModel.fromApi(Map<String, dynamic> data) {
    final profile = (data['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
    final createdAt =
        DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now();
    final diff = DateTime.now().difference(createdAt);
    final String time;
    if (diff.inMinutes < 60) {
      time = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      time = '${diff.inHours}h ago';
    } else {
      time = '${diff.inDays}d ago';
    }

    final fullName  = profile['full_name']?.toString() ?? 'User';
    final stage     = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);

    // FIX: use data['user_id'] as primary source — profile['id'] is a fallback
    final userId = data['user_id']?.toString().isNotEmpty == true
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
      likes:         (data['likes_count'] as num?)?.toInt() ?? 0,
      comments:      (data['comments_count'] as num?)?.toInt() ?? 0,
      shares:        (data['shares_count'] as num?)?.toInt() ?? 0,
      verified:      profile['is_verified'] == true,
      isPremiumPost: profile['subscription_tier'] == 'premium',
      isLiked:       data['is_liked'] == true,
      isSaved:       data['is_saved'] == true,
      // FIX: pre-populate follow state from API response
      isFollowing:   data['is_following'] == true,
      userId:        userId,
    );
  }
}

// ── Home Screen ───────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic> _profile = {};
  int _aiUsedToday = 0;
  static const int _dailyFreeLimit = 3;

  List<dynamic> _statusUsers = [];
  bool _statusLoaded = false;

  final _feeds = <String, List<PostModel>>{
    'for_you': [], 'following': [], 'trending': [],
  };
  final _loading = <String, bool>{
    'for_you': false, 'following': false, 'trending': false,
  };
  final _offsets = <String, int>{
    'for_you': 0, 'following': 0, 'trending': 0,
  };
  final _tabs = ['for_you', 'following', 'trending'];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // FIX: Map userId → isFollowing for O(1) lookup + correct toggle state
  final Map<String, bool> _followState = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        final tab = _tabs[_tabCtrl.index];
        if (_feeds[tab]!.isEmpty) _loadFeed(tab);
      }
    });
    _loadProfile();
    _loadStatus();
    _loadFeed('for_you');
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await api.getProfile();
      if (mounted) {
        setState(() =>
            _profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {});
      }
    } catch (_) {}
  }

  Future<void> _loadStatus() async {
    try {
      final data = await api.get('/posts/status/feed');
      if (mounted) {
        setState(() {
          _statusUsers = ((data as Map<String, dynamic>?)?['users'] as List?) ?? [];
          _statusLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadFeed(String tab, {bool refresh = false}) async {
    if (_loading[tab] == true) return;
    if (mounted) setState(() => _loading[tab] = true);
    if (refresh) _offsets[tab] = 0;

    try {
      final data = await api.getFeed(
        tab: tab, limit: 20, offset: _offsets[tab]!,
      );
      final posts = ((data['posts'] as List?) ?? [])
          .map((p) => PostModel.fromApi(p as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          // FIX: pre-populate follow state from every loaded post
          for (final post in posts) {
            if (post.userId.isNotEmpty && post.isFollowing) {
              _followState[post.userId] = true;
            } else if (post.userId.isNotEmpty &&
                !_followState.containsKey(post.userId)) {
              _followState[post.userId] = false;
            }
          }

          if (refresh) {
            _feeds[tab] = posts;
          } else {
            _feeds[tab] = [..._feeds[tab]!, ...posts];
          }
          _offsets[tab] = _offsets[tab]! + posts.length;
          _loading[tab] = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading[tab] = false);
    }
  }

  bool get _isPremium =>
      (_profile['subscription_tier'] ?? 'free') == 'premium';

  int get _aiRemaining =>
      (_dailyFreeLimit - _aiUsedToday).clamp(0, _dailyFreeLimit);

  // FIX: correct follow toggle — updates both _followState map and all feeds
  Future<void> _handleFollow(String userId) async {
    if (userId.isEmpty) return;
    HapticFeedback.mediumImpact();
    SoundService.follow();

    // Optimistic update immediately
    final wasFollowing = _followState[userId] ?? false;
    setState(() => _followState[userId] = !wasFollowing);

    try {
      final res = await api.toggleFollow(userId);
      if (mounted) {
        setState(() {
          _followState[userId] = res['following'] == true;
          // Also update isFollowing on all matching PostModel instances
          for (final tab in _tabs) {
            for (final post in _feeds[tab]!) {
              if (post.userId == userId) {
                post.isFollowing = _followState[userId]!;
              }
            }
          }
        });
      }
    } catch (_) {
      // Revert optimistic update on failure
      if (mounted) setState(() => _followState[userId] = wasFollowing);
    }
  }

  Future<void> _handleAiRequest(PostModel post,
      {required bool isPrivate}) async {
    SoundService.tap();
    if (_isPremium) {
      _openAi(post, isPrivate: isPrivate);
      return;
    }
    if (_aiUsedToday < _dailyFreeLimit) {
      setState(() => _aiUsedToday++);
      _openAi(post, isPrivate: isPrivate);
      return;
    }
    final confirmed = await _showAdPrompt();
    if (!confirmed) return;
    await adService.showRewardedAd(
      featureKey: 'post_ai',
      onRewarded: () {
        setState(() => _aiUsedToday = 0);
        _openAi(post, isPrivate: isPrivate);
      },
      onDismissed: () {},
    );
  }

  Future<bool> _showAdPrompt() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: isDark ? AppColors.bgCard : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Watch a short ad? 🎬',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            content: Text(
              'You\'ve used your 3 free AI responses today.\n\n'
              'Watch a 30-second ad to unlock more, or upgrade to '
              'Premium for unlimited access.',
              style: TextStyle(
                color: isDark
                    ? Colors.white.withOpacity(0.6)
                    : Colors.black54,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Watch Ad',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _openAi(PostModel post, {required bool isPrivate}) {
    if (isPrivate) {
      context.go(
        '/chat?mode=general'
        '&postContext=${Uri.encodeComponent(post.content)}'
        '&postAuthor=${Uri.encodeComponent(post.name)}',
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PostAiSheet(post: post),
      );
    }
  }

  void _viewStatus(Map<String, dynamic> user) {
    final items = user['items'] as List? ?? [];
    if (items.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusViewSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor    = isDark ? Colors.black : Colors.white;
    final cardColor  = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor  = isDark ? Colors.white : Colors.black87;
    final subColor   = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final iconColor  = isDark ? Colors.white.withOpacity(0.7) : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      key: _scaffoldKey,
      drawer: _AppDrawer(profile: _profile, isDark: isDark),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: iconColor, size: 24),
          onPressed: () {
            HapticFeedback.lightImpact();
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFF6B00), Color(0xFFFFD700), Color(0xFF6C5CE7)],
            stops: [0.0, 0.4, 1.0],
          ).createShader(bounds),
          child: const Text(
            'RiseUp',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isPremium)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '🤖 $_aiRemaining left',
                style: const TextStyle(
                  color: AppColors.primary, fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Iconsax.search_normal, color: iconColor, size: 20),
            onPressed: () { HapticFeedback.lightImpact(); context.go('/explore'); },
          ),
          IconButton(
            icon: Icon(Iconsax.notification, color: iconColor, size: 20),
            onPressed: () { HapticFeedback.lightImpact(); context.go('/notifications'); },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(
        children: [
          // ── Stories ─────────────────────────────────
          Container(
            color: cardColor,
            child: Column(
              children: [
                SizedBox(
                  height: 92,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _statusUsers.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return _StoryAddButton(
                          isDark: isDark,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CreateStatusScreen()),
                            ).then((_) => _loadStatus());
                          },
                        );
                      }
                      final user = _statusUsers[i - 1] as Map<String, dynamic>;
                      return _StoryItem(
                        user: user,
                        isDark: isDark,
                        onTap: () => _viewStatus(user),
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: borderColor),
              ],
            ),
          ),

          // ── Tabs ────────────────────────────────────
          Container(
            color: cardColor,
            child: Column(
              children: [
                TabBar(
                  controller: _tabCtrl,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: subColor,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'For You'),
                    Tab(text: 'Following'),
                    Tab(text: 'Trending'),
                  ],
                ),
                Divider(height: 1, color: borderColor),
              ],
            ),
          ),

          // ── Feed ────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: _tabs.map((tab) {
                final posts     = _feeds[tab]!;
                final isLoading = _loading[tab] == true;

                if (isLoading && posts.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (posts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('📭', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text('No posts yet',
                            style: TextStyle(color: subColor, fontSize: 14)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _loadFeed(tab, refresh: true),
                          child: Text('Refresh',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => _loadFeed(tab, refresh: true),
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: adManager.feedItemCount(posts.length) + 1,
                    separatorBuilder: (_, __) =>
                        Divider(height: 8, thickness: 8, color: borderColor),
                    itemBuilder: (_, i) {
                      final totalContent = adManager.feedItemCount(posts.length);

                      if (i == totalContent) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2)
                                : GestureDetector(
                                    onTap: () => _loadFeed(tab),
                                    child: Text('Load more',
                                        style: TextStyle(
                                            color: subColor, fontSize: 13)),
                                  ),
                          ),
                        );
                      }

                      if (adManager.shouldShowFeedAd(i)) {
                        return FeedAdCard(
                          isDark: isDark, cardColor: cardColor,
                          borderColor: borderColor, textColor: textColor,
                          subColor: subColor,
                        );
                      }

                      final postIndex = adManager.realPostIndex(i);
                      if (postIndex >= posts.length) return const SizedBox.shrink();

                      final post = posts[postIndex];
                      // FIX: read follow state from _followState map
                      final following = _followState[post.userId] ?? post.isFollowing;

                      return PostCard(
                        post: post,
                        isDark: isDark,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        subColor: subColor,
                        onAskAI: (p) => _handleAiRequest(p, isPrivate: false),
                        onPrivateChat: (p) => _handleAiRequest(p, isPrivate: true),
                        isPremium: _isPremium,
                        aiRemaining: _aiRemaining,
                        currentUserId: _profile['id']?.toString() ?? '',
                        isFollowing: following,
                        onLike: (p) async {
                          HapticFeedback.mediumImpact();
                          SoundService.like();
                          // Optimistic update
                          setState(() {
                            p.isLiked = !p.isLiked;
                            p.likes += p.isLiked ? 1 : -1;
                          });
                          try {
                            final res = await api.toggleLike(p.id);
                            if (mounted) {
                              setState(() {
                                p.isLiked = res['liked'] == true;
                              });
                            }
                          } catch (_) {
                            // Revert on failure
                            if (mounted) {
                              setState(() {
                                p.isLiked = !p.isLiked;
                                p.likes += p.isLiked ? 1 : -1;
                              });
                            }
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
                          context.go(
                            '/comments/${p.id}'
                            '?content=${Uri.encodeComponent(p.content)}'
                            '&author=${Uri.encodeComponent(p.name)}',
                          );
                        },
                        onShare: (p) async {
                          HapticFeedback.mediumImpact();
                          SoundService.share();
                          try { await api.sharePost(p.id); } catch (_) {}
                        },
                        onFollow: _handleFollow,
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Post Card ─────────────────────────────────────────
class PostCard extends StatefulWidget {
  final PostModel post;
  final bool isDark;
  final bool isPremium;
  final bool isFollowing;   // FIX: passed from parent, not derived from a Set
  final Color cardColor;
  final Color borderColor;
  final Color textColor;
  final Color subColor;
  final Function(PostModel) onAskAI;
  final Function(PostModel) onPrivateChat;
  final Function(PostModel) onLike;
  final Function(PostModel) onSave;
  final Function(PostModel) onComment;
  final Function(PostModel) onShare;
  final Function(String) onFollow;
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
    required this.isPremium,
    required this.aiRemaining,
    required this.isFollowing,
    this.currentUserId = '',
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  bool get _isOwnPost =>
      widget.post.userId.isNotEmpty &&
      widget.post.userId == widget.currentUserId;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;

    return Container(
      color: widget.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar — shows real photo if available, else emoji
                    GestureDetector(
                      onTap: () => context.go('/user-profile/${p.userId}'),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: p.avatarUrl.isNotEmpty
                              ? Image.network(
                                  p.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Text(p.avatar,
                                        style: const TextStyle(fontSize: 22)),
                                  ),
                                )
                              : Center(
                                  child: Text(p.avatar,
                                      style: const TextStyle(fontSize: 22)),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    context.go('/user-profile/${p.userId}'),
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: widget.textColor,
                                  ),
                                ),
                              ),
                              if (p.verified) ...[
                                const SizedBox(width: 3),
                                const Icon(Icons.verified_rounded,
                                    color: AppColors.primary, size: 14),
                              ],
                              if (p.isPremiumPost) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('⭐',
                                      style: TextStyle(fontSize: 9)),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              Text(p.username,
                                  style: TextStyle(
                                      fontSize: 12, color: widget.subColor)),
                              Text(' · ${p.time}',
                                  style: TextStyle(
                                      fontSize: 12, color: widget.subColor)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // FIX: Follow / Following button — always visible for other users
                    if (p.userId.isNotEmpty && !_isOwnPost) ...[
                      GestureDetector(
                        onTap: () => widget.onFollow(p.userId),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.isFollowing
                                ? widget.subColor.withOpacity(0.12)
                                : AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: widget.isFollowing
                                  ? widget.subColor.withOpacity(0.3)
                                  : AppColors.primary.withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.isFollowing) ...[
                                Icon(Icons.check_rounded,
                                    size: 11,
                                    color: widget.subColor.withOpacity(0.8)),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                widget.isFollowing ? 'Following' : 'Follow',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: widget.isFollowing
                                      ? widget.subColor.withOpacity(0.8)
                                      : AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.tag,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _showPostOptions,
                      child: Icon(Icons.more_horiz,
                          color: widget.subColor, size: 20),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Content text ─────────────────────────
                Text(
                  p.content,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: widget.isDark
                        ? const Color(0xFFE8E8F0)
                        : Colors.black87,
                    height: 1.6,
                    letterSpacing: 0.1,
                  ),
                ),

                // ── Media attachment (image or video) ────
                if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _PostMedia(
                    url: p.mediaUrl!,
                    mediaType: p.mediaType ?? 'image',
                    isDark: widget.isDark,
                  ),
                ],

                const SizedBox(height: 14),

                // ── Action Row ──────────────────────────
                Row(
                  children: [
                    _ActionBtn(
                      icon: p.isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: _fmt(p.likes),
                      color: p.isLiked ? Colors.red : widget.subColor,
                      onTap: () => widget.onLike(p),
                    ),
                    const SizedBox(width: 18),
                    _ActionBtn(
                      icon: Iconsax.message,
                      label: _fmt(p.comments),
                      color: widget.subColor,
                      onTap: () => widget.onComment(p),
                    ),
                    const SizedBox(width: 18),
                    _ActionBtn(
                      icon: Iconsax.send_1,
                      label: _fmt(p.shares),
                      color: widget.subColor,
                      onTap: () => widget.onShare(p),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => widget.onSave(p),
                      child: Icon(
                        p.isSaved
                            ? Iconsax.archive_tick
                            : Iconsax.archive_add,
                        color: p.isSaved
                            ? AppColors.primary
                            : widget.subColor,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── AI Action Buttons ────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: widget.borderColor, width: 0.8)),
              color: widget.isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onAskAI(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withOpacity(widget.isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25),
                            width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primary, AppColors.accent],
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Icon(Icons.auto_awesome,
                                color: Colors.white, size: 10),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.aiRemaining > 0 || widget.isPremium
                                ? 'Ask RiseUp AI'
                                : 'Ask RiseUp AI 📺',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onPrivateChat(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.accent
                            .withOpacity(widget.isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.25),
                            width: 0.8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Iconsax.lock_1,
                              color: AppColors.accent, size: 14),
                          SizedBox(width: 6),
                          Text('Chat Privately',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPostOptions() {
    final p = widget.post;
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.flag),
              title: const Text('Report post'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Iconsax.copy),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: p.content));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
            ListTile(
              leading: const Icon(Iconsax.share),
              title: const Text('Share to...'),
              onTap: () {
                widget.onShare(p);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Post Media Widget — images and videos ─────────────
class _PostMedia extends StatelessWidget {
  final String url;
  final String mediaType;
  final bool isDark;

  const _PostMedia({
    required this.url,
    required this.mediaType,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = mediaType == 'video';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: isVideo
          // Video: show thumbnail placeholder with play button
          // Replace with video_player widget when package is added
          ? Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 220,
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                  child: const Icon(Icons.videocam_rounded,
                      size: 48, color: Colors.white54),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ),
              ],
            )
          : Image.network(
              url,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: double.infinity,
                  height: 220,
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: double.infinity,
                height: 120,
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: Colors.white54, size: 36),
                ),
              ),
            ),
    );
  }
}

// ── Action Button ─────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      );
}

// ── App Drawer ────────────────────────────────────────
class _AppDrawer extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool isDark;
  const _AppDrawer({required this.profile, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg     = isDark ? Colors.black : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final sub    = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final name   = profile['full_name']?.toString() ?? 'User';
    final stage  = profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final isPremium = profile['subscription_tier'] == 'premium';
    final avatarUrl = profile['avatar_url']?.toString() ?? '';

    return Drawer(
      backgroundColor: bg,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile Header ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/profile');
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: avatarUrl.isNotEmpty
                            ? Image.network(avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ))
                            : Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: (stageInfo['color'] as Color)
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${stageInfo['emoji']} ${stageInfo['label']}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: stageInfo['color'] as Color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isPremium) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('⭐ Pro',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: sub, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: border, height: 1),

            // ── Nav Items ───────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _DSection('INCOME TOOLS', sub),
                  _DItem(Iconsax.chart, 'Dashboard', 'Earnings, stats & tasks', isDark,
                      onTap: () { Navigator.pop(context); context.go('/dashboard'); }),
                  _DItem(Icons.auto_awesome_rounded, 'Agentic AI', 'Execute ANY income task', isDark,
                      badge: 'HEAVY', badgeColor: AppColors.accent,
                      onTap: () { Navigator.pop(context); context.push('/agent'); }),
                  _DItem(Iconsax.flash, 'Workflow Engine', 'AI-powered income execution', isDark,
                      badge: 'NEW', badgeColor: AppColors.success,
                      onTap: () { Navigator.pop(context); context.push('/workflow'); }),
                  _DItem(Iconsax.chart_3, 'Market Pulse', 'What pays right now', isDark,
                      badge: '🔥 LIVE', badgeColor: const Color(0xFFFF6B35),
                      onTap: () { Navigator.pop(context); context.push('/pulse'); }),
                  _DItem(Icons.emoji_events_rounded, 'Challenges', '30-day income sprints', isDark,
                      onTap: () { Navigator.pop(context); context.push('/challenges'); }),
                  _DItem(Iconsax.briefcase, 'Client CRM', 'Track prospects & clients', isDark,
                      onTap: () { Navigator.pop(context); context.push('/crm'); }),
                  _DItem(Iconsax.document_text, 'Contracts & Invoices', 'Pro contract generation', isDark,
                      onTap: () { Navigator.pop(context); context.push('/contracts'); }),
                  _DItem(Icons.psychology_rounded, 'Income Memory', 'Your income DNA', isDark,
                      onTap: () { Navigator.pop(context); context.push('/memory'); }),
                  _DItem(Iconsax.gallery, 'My Portfolio', 'Shareable project showcase', isDark,
                      onTap: () { Navigator.pop(context); context.push('/portfolio'); }),
                  _DItem(Iconsax.task_square, 'My Tasks', 'Daily income tasks', isDark,
                      onTap: () { Navigator.pop(context); context.go('/tasks'); }),
                  _DItem(Iconsax.map_1, 'Wealth Roadmap', '3-stage wealth plan', isDark,
                      onTap: () { Navigator.pop(context); context.go('/roadmap'); }),
                  _DItem(Iconsax.book, 'Skills', 'Earn-while-learning', isDark,
                      onTap: () { Navigator.pop(context); context.go('/skills'); }),
                  Divider(color: border, height: 1),
                  _DSection('SOCIAL', sub),
                  _DItem(Iconsax.people, 'Collaboration', 'Build bigger goals together', isDark,
                      badge: 'NEW', badgeColor: AppColors.primary,
                      onTap: () { Navigator.pop(context); context.push('/collaboration'); }),
                  _DItem(Iconsax.message, 'Messages', 'DMs & group chats', isDark,
                      onTap: () { Navigator.pop(context); context.go('/messages'); }),
                  _DItem(Icons.radio_button_checked_rounded, 'Go Live', 'Stream to your community', isDark,
                      onTap: () { Navigator.pop(context); context.go('/live'); }),
                  _DItem(Iconsax.people, 'Groups', 'Wealth-building groups', isDark,
                      onTap: () { Navigator.pop(context); context.go('/groups'); }),
                  Divider(color: border, height: 1),
                  _DSection('FINANCE', sub),
                  _DItem(Iconsax.money_recive, 'Earnings', 'Income tracker', isDark,
                      onTap: () { Navigator.pop(context); context.go('/earnings'); }),
                  _DItem(Iconsax.chart_2, 'Analytics', 'Growth stats', isDark,
                      onTap: () { Navigator.pop(context); context.go('/analytics'); }),
                  _DItem(Iconsax.wallet_minus, 'Expenses', 'Budget tracking', isDark,
                      onTap: () { Navigator.pop(context); context.go('/expenses'); }),
                  _DItem(Iconsax.flag, 'Goals', 'Set & track targets', isDark,
                      onTap: () { Navigator.pop(context); context.go('/goals'); }),
                  Divider(color: border, height: 1),
                  _DSection('ACCOUNT', sub),
                  _DItem(Iconsax.award, 'Achievements', 'Badges & milestones', isDark,
                      onTap: () { Navigator.pop(context); context.go('/achievements'); }),
                  _DItem(Iconsax.user_tag, 'Referrals', 'Invite & earn', isDark,
                      onTap: () { Navigator.pop(context); context.go('/referrals'); }),
                  _DItem(Iconsax.setting_2, 'Settings', 'Account preferences', isDark,
                      onTap: () { Navigator.pop(context); context.go('/settings'); }),
                ],
              ),
            ),

            // ── Upgrade Banner ───────────────────────
            if (!isPremium)
              Padding(
                padding: const EdgeInsets.all(14),
                child: GestureDetector(
                  onTap: () { Navigator.pop(context); context.push('/premium'); },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withOpacity(isDark ? 0.12 : 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Upgrade to Premium',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary)),
                              Text('Unlimited AI + all features',
                                  style:
                                      TextStyle(fontSize: 11, color: sub)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 13, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DSection extends StatelessWidget {
  final String label;
  final Color color;
  const _DSection(this.label, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 1.1)),
      );
}

class _DItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool isDark;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _DItem(this.icon, this.label, this.sub, this.isDark,
      {required this.onTap, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    final textC = isDark ? Colors.white : Colors.black87;
    final subC  = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17,
                    color: isDark
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black54),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textC)),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? AppColors.primary)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(badge!,
                                style: TextStyle(
                                    fontSize: 9,
                                    color: badgeColor ?? AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    Text(sub, style: TextStyle(fontSize: 11, color: subC)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 15,
                  color: isDark
                      ? Colors.white.withOpacity(0.24)
                      : Colors.black.withOpacity(0.26)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Story Add Button ──────────────────────────────────
class _StoryAddButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _StoryAddButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.4), width: 1.5),
                ),
                child: const Center(
                    child: Icon(Icons.add, color: AppColors.primary, size: 24)),
              ),
              const SizedBox(height: 5),
              Text('You',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.white.withOpacity(0.6)
                          : Colors.black54,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ── Story Item ────────────────────────────────────────
class _StoryItem extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDark;
  final VoidCallback onTap;
  const _StoryItem({required this.user, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profile   = (user['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final name      = profile['full_name']?.toString() ?? 'User';
    final avatar    = profile['avatar_url']?.toString();
    final isOnline  = profile['is_online'] == true;
    final hasUnseen = user['has_unseen'] == true;
    final shortName = name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasUnseen
                        ? const LinearGradient(
                            colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: hasUnseen
                        ? null
                        : (isDark ? AppColors.bgSurface : Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      child: ClipOval(
                        child: avatar != null && avatar.isNotEmpty
                            ? Image.network(avatar,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _initials(name))
                            : _initials(name),
                      ),
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    bottom: 1, right: 1,
                    child: Container(
                      width: 13, height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 62,
              child: Text(
                shortName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white.withOpacity(0.6)
                        : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials(String name) => Container(
        color: AppColors.primary.withOpacity(0.15),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
        ),
      );
}

// ── Status Viewer Sheet ───────────────────────────────
class _StatusViewSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  const _StatusViewSheet({required this.user});

  @override
  State<_StatusViewSheet> createState() => _StatusViewSheetState();
}

class _StatusViewSheetState extends State<_StatusViewSheet> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _markViewed();
  }

  void _markViewed() {
    final items =
        (widget.user['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return;
    final id = items[_currentIndex]['id']?.toString();
    if (id == null) return;
    api.post('/posts/status/$id/view', {}).catchError((_) => <String, dynamic>{});
  }

  void _next() {
    final items = widget.user['items'] as List? ?? [];
    if (_currentIndex < items.length - 1) {
      setState(() { _currentIndex++; _markViewed(); });
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_currentIndex > 0) setState(() { _currentIndex--; _markViewed(); });
  }

  @override
  Widget build(BuildContext context) {
    final items =
        (widget.user['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final profile =
        (widget.user['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    if (items.isEmpty) return const SizedBox.shrink();

    final name   = profile['full_name']?.toString() ?? 'User';
    final avatar = profile['avatar_url']?.toString();
    final item   = items[_currentIndex];
    final media  = item['media_url']?.toString();
    final text   = item['content']?.toString() ?? '';
    final bg     = item['background_color']?.toString() ?? '#6C5CE7';
    final link   = item['link_url']?.toString();

    Color bgColor = AppColors.primary;
    try { bgColor = Color(int.parse(bg.replaceFirst('#', '0xFF'))); } catch (_) {}

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: media != null ? Colors.black : bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          if (media != null && item['media_type'] == 'image')
            Positioned.fill(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(media,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 48))),
              ),
            )
          else if (media == null && text.isNotEmpty)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.5)),
                ),
              ),
            ),

          // Progress bars
          Positioned(
            top: 12, left: 12, right: 12,
            child: Row(
              children: List.generate(
                items.length,
                (i) => Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Header
          Positioned(
            top: 24, left: 16, right: 16,
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.24)),
                  child: ClipOval(
                    child: avatar != null && avatar.isNotEmpty
                        ? Image.network(avatar,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                            ))
                        : Center(
                            child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text(
                        items.length == 1
                            ? '1 status'
                            : '${items.length} statuses',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          if (media != null && text.isNotEmpty)
            Positioned(
              bottom: 80, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(text,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),

          if (link != null)
            Positioned(
              bottom: 80, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.3))),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          item['link_title']?.toString() ?? link,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),

          // Tap navigation
          Row(
            children: [
              Expanded(child: GestureDetector(onTap: _prev)),
              Expanded(child: GestureDetector(onTap: _next)),
            ],
          ),
        ],
      ),
    );
  }
}
