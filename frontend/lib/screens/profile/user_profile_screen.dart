import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map _profile = {};
  Map _stats   = {};
  List _posts  = [];
  bool _loading     = true;
  bool _isFollowing = false;
  bool _isOwnProfile = false;
  bool _followLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final myId = await api.getUserId() ?? '';
      _isOwnProfile = myId == widget.userId;

      final results = await Future.wait([
        api.get('/posts/users/${widget.userId}/profile'),
        api.get('/posts/users/${widget.userId}/posts?limit=30'),
      ]);

      if (mounted) setState(() {
        final d = results[0] as Map? ?? {};
        _profile     = d['profile']    as Map? ?? {};
        _stats       = d['stats']      as Map? ?? {};
        _isFollowing = d['is_following'] == true;
        _posts       = (results[1] as Map?)?['posts'] as List? ?? [];
        _loading     = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    try {
      final r = await api.toggleFollow(widget.userId);
      final following = r['following'] == true;
      setState(() {
        _isFollowing = following;
        _followLoading = false;
        final c = (_stats['followers'] as int? ?? 0);
        _stats = {..._stats, 'followers': following ? c + 1 : (c - 1).clamp(0, 999999)};
      });
      HapticFeedback.lightImpact();
    } catch (_) {
      setState(() => _followLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    try {
      final r = await api.getOrCreateConversation(widget.userId);
      final convId = r['conversation_id']?.toString() ?? r['id']?.toString();
      if (convId != null && mounted) {
        context.push('/conversation/${widget.userId}?name=${Uri.encodeComponent(_profile['full_name']?.toString() ?? 'User')}&avatar=${Uri.encodeComponent(_profile['avatar_url']?.toString() ?? '👤')}');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open message thread'),
              backgroundColor: AppColors.error));
      }
    }
  }

  void _shareProfile() {
    Clipboard.setData(ClipboardData(text: 'riseup.app/u/${widget.userId}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile link copied!'),
          backgroundColor: AppColors.success, duration: Duration(seconds: 2)));
  }

  String _fmt(dynamic n) {
    final val = (n as num?)?.toInt() ?? 0;
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000)    return '${(val / 1000).toStringAsFixed(1)}K';
    return '$val';
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours   < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? Colors.black : Colors.white;
    final card     = isDark ? AppColors.bgCard : Colors.white;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text     = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;
    final surface  = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final name     = _profile['full_name']?.toString() ?? 'User';
    final bio      = _profile['bio']?.toString() ?? '';
    final status   = _profile['status']?.toString() ?? '';
    final country  = _profile['country']?.toString() ?? '';
    final stage    = _profile['stage']?.toString() ?? 'survival';
    final avatar   = _profile['avatar_url']?.toString();
    final earned   = (_profile['total_earned'] as num?)?.toDouble() ?? 0;
    final isOnline = _profile['is_online'] == true;
    final skills   = (_profile['current_skills'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      backgroundColor: bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : CustomScrollView(slivers: [

        // ── App Bar ─────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: text),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.ios_share_rounded, color: text, size: 20),
              onPressed: _shareProfile,
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: text, size: 20),
              onPressed: () => _showMoreSheet(isDark, text, sub),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary.withOpacity(0.8), AppColors.accent.withOpacity(0.6)],
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
                        // Avatar
                        Stack(children: [
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: ClipOval(
                              child: avatar != null && avatar.isNotEmpty
                                  ? Image.network(avatar, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _avatarFallback(name))
                                  : _avatarFallback(name),
                            ),
                          ),
                          if (isOnline)
                            Positioned(bottom: 2, right: 2,
                              child: Container(width: 18, height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2)),
                              )),
                        ]),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Row(children: [
                            Flexible(child: Text(name,
                                style: const TextStyle(fontSize: 20,
                                    fontWeight: FontWeight.w800, color: Colors.white))),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_stageLabel(stage),
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          if (status.isNotEmpty)
                            Text(status, style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                          if (country.isNotEmpty)
                            Text(country, style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                        ])),
                      ]),

                      const SizedBox(height: 16),

                      // Stats row
                      Row(children: [
                        _StatChip(_fmt(_stats['posts']),   'Posts',     Colors.white),
                        const SizedBox(width: 20),
                        _StatChip(_fmt(_stats['followers']),'Followers', Colors.white),
                        const SizedBox(width: 20),
                        _StatChip(_fmt(_stats['following']),'Following', Colors.white),
                        const Spacer(),
                        if (earned > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('\$${_fmt(earned.toInt())} earned',
                                style: const TextStyle(color: AppColors.gold,
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Action buttons + bio ─────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: card,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Action buttons
              if (!_isOwnProfile)
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _toggleFollow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _isFollowing ? Colors.transparent : AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          border: _isFollowing
                              ? Border.all(color: isDark ? Colors.white30 : Colors.grey.shade300)
                              : null,
                        ),
                        child: Center(child: _followLoading
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(_isFollowing ? Icons.check_rounded : Icons.add_rounded,
                                    color: _isFollowing
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : Colors.white,
                                    size: 16),
                                const SizedBox(width: 5),
                                Text(_isFollowing ? 'Following' : 'Follow',
                                    style: TextStyle(
                                        color: _isFollowing
                                            ? (isDark ? Colors.white : Colors.black87)
                                            : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                              ])),
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
                              color: isDark ? Colors.white12 : Colors.grey.shade300),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _shareProfile,
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Icon(Icons.ios_share_rounded, size: 18,
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ])
              else
                GestureDetector(
                  onTap: () => context.push('/edit-profile'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: const Center(child: Text('Edit Profile',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  ),
                ),

              const SizedBox(height: 14),

              // Bio
              if (bio.isNotEmpty) ...[
                Text(bio, style: TextStyle(fontSize: 13, color: text, height: 1.5)),
                const SizedBox(height: 10),
              ],

              // Skills
              if (skills.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: skills.take(6).map((s) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(s, style: const TextStyle(
                        fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  )).toList()),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 4),
            ]),
          ),
        ),

        // ── Tabs ────────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabDelegate(
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Iconsax.grid_1, size: 20)),
                Tab(icon: Icon(Iconsax.heart, size: 20)),
              ],
            ),
            card,
            border,
          ),
        ),

        // ── Posts grid ──────────────────────────────────────────
        SliverFillRemaining(
          child: TabBarView(controller: _tabs, children: [
            // Posts
            _posts.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('📝', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('No posts yet', style: TextStyle(color: sub, fontSize: 14)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(0),
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 8, thickness: 8, color: border),
                    itemBuilder: (_, i) {
                      final p = _posts[i] as Map;
                      final pName   = _profile['full_name']?.toString() ?? 'User';
                      final content = p['content']?.toString() ?? '';
                      final likes   = (p['likes_count'] as num?)?.toInt() ?? 0;
                      final isLiked = p['is_liked'] == true;
                      final tag     = p['tag']?.toString() ?? '';

                      return Container(
                        color: card,
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(child: avatar != null && avatar.isNotEmpty
                                  ? Image.network(avatar, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _avatarFallback(name))
                                  : _avatarFallback(name)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(pName, style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w700, color: text)),
                              Text(_timeAgo(p['created_at']?.toString()),
                                  style: TextStyle(fontSize: 11, color: sub)),
                            ])),
                            if (tag.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(tag, style: const TextStyle(
                                    fontSize: 10, color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          Text(content, style: TextStyle(fontSize: 14, color: text, height: 1.5)),
                          if (p['media_url'] != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(p['media_url'].toString(),
                                  fit: BoxFit.cover, width: double.infinity,
                                  height: 200,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            GestureDetector(
                              onTap: () async {
                                final r = await api.toggleLike(p['id'].toString());
                                setState(() {
                                  p['is_liked'] = r['liked'] == true;
                                  p['likes_count'] = r['liked'] == true
                                      ? likes + 1 : (likes - 1).clamp(0, 999999);
                                });
                              },
                              child: Row(children: [
                                Icon(isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                    color: isLiked ? Colors.red : sub, size: 20),
                                const SizedBox(width: 4),
                                Text('$likes', style: TextStyle(color: sub, fontSize: 13)),
                              ]),
                            ),
                            const SizedBox(width: 18),
                            GestureDetector(
                              onTap: () => context.push(
                                  '/comments/${p['id']}?content=${Uri.encodeComponent(content)}&author=${Uri.encodeComponent(pName)}&userId=${widget.userId}'),
                              child: Row(children: [
                                Icon(Iconsax.message, color: sub, size: 20),
                                const SizedBox(width: 4),
                                Text('${(p['post_comments'] as List?)?.length ?? 0}',
                                    style: TextStyle(color: sub, fontSize: 13)),
                              ]),
                            ),
                            const SizedBox(width: 18),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(
                                    text: 'riseup.app/post/${p['id']}'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post link copied!'),
                                      backgroundColor: AppColors.success,
                                      duration: Duration(seconds: 1)));
                              },
                              child: Row(children: [
                                Icon(Iconsax.send_1, color: sub, size: 20),
                              ]),
                            ),
                          ]),
                        ]),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                    },
                  ),

            // Liked posts placeholder
            Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('❤️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Liked posts are private', style: TextStyle(color: sub, fontSize: 14)),
            ])),
          ]),
        ),
      ]),
    );
  }

  void _showMoreSheet(bool isDark, Color text, Color sub) {
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
          _moreOption(Icons.ios_share_rounded, 'Share Profile', sub, _shareProfile),
          _moreOption(Icons.block_rounded, 'Block User', Colors.red, () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User blocked'),
                  backgroundColor: AppColors.error));
          }),
          _moreOption(Icons.flag_rounded, 'Report User', Colors.orange, () {
            Navigator.pop(context);
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _moreOption(IconData icon, String label, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    );

  Widget _avatarFallback(String name) => Container(
    color: AppColors.primary.withOpacity(0.15),
    child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
            color: AppColors.primary))),
  );

  String _stageLabel(String stage) {
    switch (stage) {
      case 'earning': return '💰 Earning';
      case 'growing': return '📈 Growing';
      case 'wealth':  return '👑 Wealth';
      default:        return '🌱 Survival';
    }
  }
}

class _StatChip extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatChip(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
  ]);
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bg, border;
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
