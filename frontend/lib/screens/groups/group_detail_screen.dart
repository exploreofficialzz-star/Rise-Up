// frontend/lib/screens/groups/group_detail_screen.dart

import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../widgets/ad_widgets.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;

  // ── Cache keys ─────────────────────────────────────────────────────────────
  String get _kGroup   => 'riseup_group_${widget.groupId}_v1';
  String get _kPosts   => 'riseup_gposts_${widget.groupId}_v1';
  String get _kMembers => 'riseup_gmembers_${widget.groupId}_v1';

  // ── Data ───────────────────────────────────────────────────────────────────
  Map  _group   = {};
  List _posts   = [];
  List _members = [];

  // ── State ──────────────────────────────────────────────────────────────────
  bool _loadingGroup   = true;
  bool _loadingPosts   = true;
  bool _loadingMembers = false;
  bool _groupError     = false;
  bool _postsError     = false;
  bool _joined         = false;
  bool _posting        = false;

  // ── Optimistic like state ──────────────────────────────────────────────────
  final Set<String>      _likedPosts = {};
  final Map<String, int> _likeCounts = {};

  // ── Composer ───────────────────────────────────────────────────────────────
  final _postCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _restoreCache();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _postCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.index == 1 && _members.isEmpty && !_loadingMembers) {
      _loadMembers();
    }
  }

  // ── Cache restore (instant) ────────────────────────────────────────────────

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Group
      final gRaw = prefs.getString(_kGroup);
      if (gRaw != null && mounted) {
        final g = Map<dynamic, dynamic>.from(jsonDecode(gRaw) as Map);
        setState(() {
          _group        = g;
          _joined       = g['is_joined'] == true || g['is_member'] == true;
          _loadingGroup = false;
        });
      }

      // Posts
      final pRaw = prefs.getString(_kPosts);
      if (pRaw != null && mounted) {
        final posts = (jsonDecode(pRaw) as List).cast<Map>();
        _seedLikeState(posts);
        setState(() { _posts = posts; _loadingPosts = false; });
      }

      // Members (optional restore)
      final mRaw = prefs.getString(_kMembers);
      if (mRaw != null && mounted) {
        setState(() =>
            _members = (jsonDecode(mRaw) as List).cast<Map>());
      }
    } catch (_) {}
  }

  // ── Background refresh ─────────────────────────────────────────────────────

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    await Future.wait([_loadGroup(), _loadPosts()]);
  }

  Future<void> _refresh() async {
    await Future.wait([_loadGroup(), _loadPosts()]);
  }

  // ── Load group ─────────────────────────────────────────────────────────────

  Future<void> _loadGroup() async {
    if (!mounted) return;
    if (_group.isEmpty) setState(() { _loadingGroup = true; _groupError = false; });
    try {
      final data  = await api.get('/groups/${widget.groupId}');
      final group = data['group'] as Map? ?? data;
      if (mounted) {
        setState(() {
          _group        = group;
          _joined       = group['is_joined'] == true || group['is_member'] == true;
          _loadingGroup = false;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kGroup, jsonEncode(group));
      }
    } catch (_) {
      if (mounted && _group.isEmpty) {
        setState(() { _loadingGroup = false; _groupError = true; });
      }
    }
  }

  // ── Load posts ─────────────────────────────────────────────────────────────

  Future<void> _loadPosts() async {
    if (!mounted) return;
    if (_posts.isEmpty) setState(() { _loadingPosts = true; _postsError = false; });
    try {
      final data  = await api.get('/groups/${widget.groupId}/posts');
      final posts = (data['posts'] as List? ?? []).cast<Map>();
      _seedLikeState(posts);
      if (mounted) {
        setState(() { _posts = posts; _loadingPosts = false; });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kPosts, jsonEncode(posts));
      }
    } catch (_) {
      if (mounted && _posts.isEmpty) {
        setState(() { _loadingPosts = false; _postsError = true; });
      }
    }
  }

  // ── Load members ───────────────────────────────────────────────────────────

  Future<void> _loadMembers() async {
    if (!mounted) return;
    setState(() => _loadingMembers = true);
    try {
      final data    = await api.get('/groups/${widget.groupId}/members');
      final members = (data['members'] as List? ?? []).cast<Map>();
      if (mounted) {
        setState(() { _members = members; _loadingMembers = false; });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kMembers, jsonEncode(members));
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _seedLikeState(List posts) {
    for (final p in posts) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _likeCounts[id] = (p['likes_count'] as int?) ?? (p['likes'] as int?) ?? 0;
      if (p['is_liked'] == true) _likedPosts.add(id);
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _toggleJoin() async {
    final wasJoined = _joined;
    HapticFeedback.lightImpact();
    setState(() => _joined = !wasJoined);
    try {
      final res = await api.toggleGroup(widget.groupId);
      if (mounted) setState(() => _joined = res['joined'] == true);
    } catch (_) {
      if (mounted) {
        setState(() => _joined = wasJoined);
        _showErrorSnack('Could not update membership. Please try again.');
      }
    }
  }

  Future<void> _toggleLike(Map post) async {
    final id = post['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final wasLiked  = _likedPosts.contains(id);
    final prevCount = _likeCounts[id] ?? 0;

    HapticFeedback.lightImpact();
    setState(() {
      if (wasLiked) {
        _likedPosts.remove(id);
        _likeCounts[id] = (prevCount - 1).clamp(0, 999999);
      } else {
        _likedPosts.add(id);
        _likeCounts[id] = prevCount + 1;
      }
    });

    try {
      await api.post('/groups/${widget.groupId}/posts/$id/like', {});
    } catch (_) {
      if (mounted) {
        setState(() {
          if (wasLiked) { _likedPosts.add(id); } else { _likedPosts.remove(id); }
          _likeCounts[id] = prevCount;
        });
        _showErrorSnack('Could not like post. Please try again.');
      }
    }
  }

  Future<void> _submitPost(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    setState(() => _posting = true);
    try {
      await api.post('/groups/${widget.groupId}/posts', {
        'content': trimmed,
        'group_id': widget.groupId,
      });
      _postCtrl.clear();
      if (mounted) Navigator.pop(context);
      await _loadPosts();
      if (mounted) {
        HapticFeedback.lightImpact();
        _showSuccessSnack('✅ Post shared with the group!');
        unawaited(adManager.showInterstitial());
      }
    } catch (_) {
      if (mounted) _showErrorSnack('Failed to post. Please try again.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccessSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  List _withAdSlots(List real) {
    if (adManager.isPremium) return real;
    final out = <dynamic>[];
    for (int i = 0; i < real.length; i++) {
      out.add(real[i]);
      if ((i + 1) % 5 == 0 && i + 1 < real.length) out.add({'_isAd': true});
    }
    return out;
  }

  void _navigateToUserProfile(String? userId) {
    if (userId == null || userId.isEmpty) return;
    context.push('/user/$userId');
  }

  // ── User avatar widget ─────────────────────────────────────────────────────
  // Shows real avatar photo when available; falls back to gradient + initial.

  Widget _buildUserAvatar({
    required String? avatarUrl,
    required String  name,
    required double  size,
  }) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fSize   = size * 0.38;

    Widget fallback = Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initial,
            style: TextStyle(
                fontSize: fSize,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      ),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl:    avatarUrl,
        width:       size,
        height:      size,
        fit:         BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  int    get _memberCount => _group['member_count'] as int? ?? _group['members_count'] as int? ?? 0;
  String get _emoji       => _group['emoji']?.toString() ?? '💬';
  String get _description => _group['description']?.toString() ?? '';
  String get _tag         =>
      _group['topic']?.toString() ??
      _group['tag']?.toString() ??
      _group['category']?.toString() ??
      '';

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? Colors.black        : Colors.white;
    final card     = isDark ? AppColors.bgCard    : Colors.white;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text     = isDark ? Colors.white        : Colors.black87;
    final sub      = isDark ? Colors.white54      : Colors.black45;
    final surface  = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/groups');
            }
          },
        ),
        title: Row(children: [
          Text(_loadingGroup ? '💬' : _emoji,
              style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.groupName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          GestureDetector(
            onTap: _toggleJoin,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _joined ? Colors.transparent : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                border: _joined
                    ? Border.all(
                        color: isDark
                            ? Colors.white24
                            : Colors.grey.shade300)
                    : null,
              ),
              child: Text(
                _joined ? 'Joined ✓' : 'Join',
                style: TextStyle(
                    color: _joined ? sub : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                const Tab(text: 'Posts'),
                Tab(text: _memberCount > 0
                    ? 'Members ($_memberCount)'
                    : 'Members'),
                const Tab(text: 'About'),
              ],
            ),
            Divider(height: 1, color: border),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildPostsTab(isDark, bg, card, border, text, sub, surface),
              _buildMembersTab(isDark, card, border, text, sub),
              _buildAboutTab(isDark, card, text, sub),
            ],
          ),
        ),
        if (!adManager.isPremium) ScreenBannerAd(isDark: isDark),
      ]),
    );
  }

  // ── Posts tab ──────────────────────────────────────────────────────────────

  Widget _buildPostsTab(bool isDark, Color bg, Color card, Color border,
      Color text, Color sub, Color surface) {
    return Column(children: [
      if (_joined) _buildComposer(card, surface, sub, isDark, border, text),
      Divider(height: 1, color: border),
      Expanded(
        child: _loadingPosts && _posts.isEmpty
            ? _buildPostSkeleton(isDark, card, border)
            : _postsError
                ? _buildPostsError(text, sub)
                : _posts.isEmpty
                    ? _buildEmptyPosts(sub)
                    : _buildPostList(isDark, card, border, text, sub),
      ),
    ]);
  }

  Widget _buildComposer(Color card, Color surface, Color sub, bool isDark,
      Color border, Color text) {
    return Container(
      color: card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '✍️',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () =>
                _showPostSheet(context, isDark, border, text, sub),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Share something with the group...',
                  style: TextStyle(color: sub, fontSize: 13)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPostSkeleton(bool isDark, Color card, Color border) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 4,
      separatorBuilder: (_, __) =>
          Divider(height: 8, thickness: 8, color: border),
      itemBuilder: (_, __) => Container(
        height: 110,
        color: card,
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                  height: 12,
                  width: 120,
                  color: isDark
                      ? Colors.white10
                      : Colors.grey.shade200),
              const SizedBox(height: 8),
              Container(
                  height: 10,
                  color: isDark
                      ? Colors.white10
                      : Colors.grey.shade200),
              const SizedBox(height: 4),
              Container(
                  height: 10,
                  width: 200,
                  color: isDark
                      ? Colors.white10
                      : Colors.grey.shade200),
            ]),
          ),
        ]),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(
              duration: 1200.ms,
              color: isDark ? Colors.white10 : Colors.grey.shade100),
    );
  }

  Widget _buildPostsError(Color text, Color sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('⚠️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Could not load posts',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: text)),
          const SizedBox(height: 8),
          Text('Check your connection and try again.',
              style: TextStyle(color: sub, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _loadPosts,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 11),
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyPosts(Color sub) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_emoji, style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No posts yet in this group',
            style: TextStyle(color: sub, fontSize: 14)),
        if (_joined) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final isDark =
                  Theme.of(context).brightness == Brightness.dark;
              _showPostSheet(
                context,
                isDark,
                isDark ? AppColors.bgSurface : Colors.grey.shade200,
                isDark ? Colors.white : Colors.black87,
                isDark ? Colors.white54 : Colors.black45,
              );
            },
            child: Text('Be the first to post!',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text('Join the group to start posting.',
              style: TextStyle(color: sub, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _buildPostList(
      bool isDark, Color card, Color border, Color text, Color sub) {
    final items = _withAdSlots(_posts);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            Divider(height: 8, thickness: 8, color: border),
        itemBuilder: (_, i) {
          final item = items[i];

          if (item is Map && item['_isAd'] == true) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FeedAdCard(
                isDark: isDark,
                cardColor: card,
                borderColor: border,
                textColor: text,
                subColor: sub,
              ),
            );
          }

          final post     = item as Map;
          final id       = post['id']?.toString() ?? '';
          final liked    = _likedPosts.contains(id);
          final likes    = _likeCounts[id] ?? (post['likes_count'] as int?) ?? (post['likes'] as int?) ?? 0;
          final comments = (post['comments_count'] as int?) ?? (post['comments'] as int?) ?? 0;
          final authorName = post['author_name']?.toString() ?? post['name']?.toString() ?? 'Member';
          final authorId   = post['author_id']?.toString() ?? post['user_id']?.toString() ?? '';
          final avatarUrl  = post['avatar_url']?.toString();

          return Container(
            color: card,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Author row ────────────────────────────────────────
                Row(children: [
                  // Tappable avatar
                  GestureDetector(
                    onTap: () => _navigateToUserProfile(authorId),
                    child: _buildUserAvatar(
                        avatarUrl: avatarUrl,
                        name: authorName,
                        size: 40),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _navigateToUserProfile(authorId),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(authorName,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: text)),
                        Text(
                          _formatTimestamp(
                              post['created_at']?.toString() ?? ''),
                          style: TextStyle(fontSize: 11, color: sub),
                        ),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                // ── Content ───────────────────────────────────────────
                Text(post['content']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: 14, color: text, height: 1.55)),
                const SizedBox(height: 6),

                // ── Reactions — Material + InkWell for instant feedback
                Row(children: [
                  // Like button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleLike(post),
                      borderRadius: BorderRadius.circular(20),
                      splashColor:
                          AppColors.error.withOpacity(0.15),
                      highlightColor:
                          AppColors.error.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          AnimatedSwitcher(
                            duration:
                                const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(
                                    scale: anim, child: child),
                            child: Icon(
                              liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: liked
                                  ? AppColors.error
                                  : sub,
                              size: 20,
                              key: ValueKey(liked),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text('$likes',
                              style: TextStyle(
                                  color: liked
                                      ? AppColors.error
                                      : sub,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Comment button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        // Navigate to comments when available
                        // context.push('/comments/$id');
                      },
                      borderRadius: BorderRadius.circular(20),
                      splashColor:
                          AppColors.primary.withOpacity(0.12),
                      highlightColor:
                          AppColors.primary.withOpacity(0.06),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Iconsax.message,
                              color: sub, size: 20),
                          const SizedBox(width: 5),
                          Text('$comments',
                              style: TextStyle(
                                  color: sub,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ).animate().fadeIn(
              delay: Duration(milliseconds: i * 40));
        },
      ),
    );
  }

  // ── Members tab ────────────────────────────────────────────────────────────

  Widget _buildMembersTab(
      bool isDark, Color card, Color border, Color text, Color sub) {
    if (_loadingMembers && _members.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2),
      );
    }

    if (_members.isEmpty) {
      return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          const Text('👥', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No members yet',
              style: TextStyle(color: sub, fontSize: 14)),
          if (!_joined) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _toggleJoin,
              child: Text('Be the first to join!',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _members.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: border),
      itemBuilder: (_, i) {
        final m       = _members[i];
        final isAdmin = m['is_admin'] == true || m['role'] == 'admin';
        final name    = m['name']?.toString() ?? m['username']?.toString() ?? 'Member';
        final uid     = m['id']?.toString() ?? '';
        final avUrl   = m['avatar_url']?.toString();
        final joined  = m['joined_at']?.toString() ?? '';

        return GestureDetector(
          onTap: () => _navigateToUserProfile(uid),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            leading: _buildUserAvatar(
                avatarUrl: avUrl, name: name, size: 44),
            title: Row(children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: text)),
              if (isAdmin) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Admin',
                      style: TextStyle(
                          fontSize: 9,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
            subtitle: joined.isNotEmpty
                ? Text('Joined ${_formatTimestamp(joined)}',
                    style: TextStyle(fontSize: 11, color: sub))
                : null,
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
      },
    );
  }

  // ── About tab ──────────────────────────────────────────────────────────────

  Widget _buildAboutTab(bool isDark, Color card, Color text, Color sub) {
    if (_loadingGroup && _group.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2),
      );
    }

    if (_groupError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Text('⚠️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text('Could not load group details',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: text)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadGroup,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.bgCard
                : const Color(0xFFF8F8F8),
            borderRadius: AppRadius.lg,
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text(_emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.groupName,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: text)),
                  if (_tag.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_tag,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ),
            ]),
            if (_description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_description,
                  style: TextStyle(
                      fontSize: 13, color: sub, height: 1.5)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Icon(Iconsax.people, size: 16, color: sub),
              const SizedBox(width: 6),
              Text(
                  '$_memberCount member${_memberCount == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 13,
                      color: text,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        if (!_joined) ...[
          GestureDetector(
            onTap: _toggleJoin,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('Join This Group',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text('Community Guidelines',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: text)),
        const SizedBox(height: 12),
        ...[
          '✅ Share real experiences and income wins',
          '✅ Ask questions — no question is too basic',
          '🚫 No spam or self-promotion without value',
          '🚫 Be respectful to all members',
          '💡 Help others when you can',
        ].map((rule) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(rule,
                  style: TextStyle(
                      fontSize: 13, color: sub, height: 1.5)),
            )),
      ]),
    );
  }

  // ── Post sheet ─────────────────────────────────────────────────────────────

  void _showPostSheet(BuildContext ctx, bool isDark, Color border,
      Color text, Color sub) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Post to ${widget.groupName}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: text)),
              const SizedBox(height: 12),
              TextField(
                controller: _postCtrl,
                maxLines: 4,
                maxLength: 500,
                style: TextStyle(fontSize: 14, color: text),
                decoration: InputDecoration(
                  hintText:
                      'Share a win, question, or insight...',
                  hintStyle:
                      TextStyle(color: sub),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle:
                      TextStyle(color: sub, fontSize: 11),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _posting
                      ? null
                      : () => _submitPost(_postCtrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withOpacity(0.45),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _posting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Post',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Timestamp ──────────────────────────────────────────────────────────────

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt   = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      if (diff.inDays    <  7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

void unawaited(Future<void> f) {}
