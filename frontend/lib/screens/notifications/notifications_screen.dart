// frontend/lib/screens/notifications/notifications_screen.dart
// v3.0 — Facebook-style Professional Notifications
//
// Features:
//  • Actor avatar (CachedNetworkImage) with action icon badge
//  • Rich text: "John liked your post" — actor name bold
//  • Post preview snippet + thumbnail (image posts)
//  • Sections: Today / This Week / Earlier
//  • Swipe-to-dismiss individual notifications
//  • Tap navigates to relevant post / profile / conversation
//  • Unread blue dot + unread count badge in AppBar
//  • Mark all read / mark single read on tap
//  • Pull-to-refresh
//  • Empty state + loading skeleton

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification model
// ─────────────────────────────────────────────────────────────────────────────
class _NotifModel {
  final String  id;
  final String  type;
  final String  title;
  final String  message;
  final String  timeAgo;
  final DateTime createdAt;
  bool          isRead;

  // Actor info (person who triggered the notification)
  final String? actorName;
  final String? actorAvatar;
  final String? actorId;

  // Post info
  final String? postId;
  final String? postPreview;
  final String? postImage;

  // Route to navigate on tap
  final String? route;

  _NotifModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timeAgo,
    required this.createdAt,
    required this.isRead,
    this.actorName,
    this.actorAvatar,
    this.actorId,
    this.postId,
    this.postPreview,
    this.postImage,
    this.route,
  });

  factory _NotifModel.fromMap(Map<String, dynamic> m) {
    final data    = (m['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final created = DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now();
    final diff    = DateTime.now().difference(created);

    String ago;
    if (diff.inSeconds < 60)       ago = 'just now';
    else if (diff.inMinutes < 60)  ago = '${diff.inMinutes}m';
    else if (diff.inHours < 24)    ago = '${diff.inHours}h';
    else if (diff.inDays < 7)      ago = '${diff.inDays}d';
    else                           ago = '${(diff.inDays / 7).floor()}w';

    return _NotifModel(
      id:           m['id']?.toString() ?? '',
      type:         m['type']?.toString() ?? 'system',
      title:        m['title']?.toString() ?? '',
      message:      m['message']?.toString() ?? '',
      timeAgo:      ago,
      createdAt:    created,
      isRead:       m['is_read'] == true,
      actorName:    data['actor_name']?.toString(),
      actorAvatar:  data['actor_avatar']?.toString(),
      actorId:      data['actor_id']?.toString() ?? data['user_id']?.toString(),
      postId:       data['post_id']?.toString(),
      postPreview:  data['post_preview']?.toString(),
      postImage:    data['post_image']?.toString(),
      route:        data['route']?.toString(),
    );
  }

  bool get isToday {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return createdAt.isAfter(today);
  }

  bool get isThisWeek {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return createdAt.isAfter(weekAgo) && !isToday;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Screen
// ─────────────────────────────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_NotifModel> _notifs  = [];
  bool              _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getNotifications(limit: 60);
      if (!mounted) return;
      final list = ((data['notifications'] as List?) ?? [])
          .map((x) => _NotifModel.fromMap(x as Map<String, dynamic>))
          .toList();
      setState(() { _notifs = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await api.markNotificationsRead();
      if (mounted) setState(() { for (final n in _notifs) n.isRead = true; });
    } catch (_) {}
  }

  Future<void> _markRead(_NotifModel n) async {
    if (n.isRead) return;
    try {
      await api.markNotificationsRead(ids: [n.id]);
      if (mounted) setState(() => n.isRead = true);
    } catch (_) {}
  }

  Future<void> _dismiss(_NotifModel n) async {
    if (mounted) setState(() => _notifs.remove(n));
    try { await api.markNotificationsRead(ids: [n.id]); } catch (_) {}
  }

  void _onTap(_NotifModel n) {
    _markRead(n);
    HapticFeedback.lightImpact();
    final route = n.route;
    if (route != null && route.isNotEmpty) {
      context.push(route);
      return;
    }
    if (n.postId != null) {
      context.push('/comments/${n.postId}');
      return;
    }
    if (n.actorId != null && (n.type == 'follow')) {
      context.push('/user-profile/${n.actorId}');
      return;
    }
  }

  int get _unreadCount => _notifs.where((n) => !n.isRead).length;

  // ── Sections ──────────────────────────────────────────────────────────────
  List<_NotifModel> get _today     => _notifs.where((n) => n.isToday).toList();
  List<_NotifModel> get _thisWeek  => _notifs.where((n) => n.isThisWeek).toList();
  List<_NotifModel> get _earlier   => _notifs.where((n) => !n.isToday && !n.isThisWeek).toList();

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? Colors.black : const Color(0xFFF0F2F5);
    final card    = dark ? AppColors.bgCard : Colors.white;
    final border  = dark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt     = dark ? Colors.white : Colors.black87;
    final sub     = dark ? Colors.white54 : Colors.black45;
    final unread  = _unreadCount;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: dark ? Colors.white70 : Colors.black54),
          onPressed: () => context.go('/home'),
        ),
        title: Row(children: [
          Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: txt)),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: _loading
          ? _buildSkeleton(dark, card, border)
          : _notifs.isEmpty
              ? _buildEmpty(sub)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: _buildList(dark, card, border, txt, sub),
                ),
    );
  }

  Widget _buildSkeleton(bool dark, Color card, Color border) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (_, i) => _SkeletonTile(isDark: dark, cardColor: card),
    );
  }

  Widget _buildEmpty(Color sub) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), shape: BoxShape.circle),
        child: const Center(child: Text('🔔', style: TextStyle(fontSize: 40))),
      ),
      const SizedBox(height: 20),
      const Text('All caught up!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('No notifications yet.\nStart engaging with the community!',
          textAlign: TextAlign.center,
          style: TextStyle(color: sub, fontSize: 14, height: 1.5)),
    ]));
  }

  Widget _buildList(bool dark, Color card, Color border, Color txt, Color sub) {
    final today    = _today;
    final thisWeek = _thisWeek;
    final earlier  = _earlier;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (today.isNotEmpty) ...[
          _SectionHeader(label: 'Today', isDark: dark),
          ...today.asMap().entries.map((e) => _buildTile(e.value, dark, card, txt, sub, e.key)),
        ],
        if (thisWeek.isNotEmpty) ...[
          _SectionHeader(label: 'This Week', isDark: dark),
          ...thisWeek.asMap().entries.map((e) => _buildTile(e.value, dark, card, txt, sub, e.key)),
        ],
        if (earlier.isNotEmpty) ...[
          _SectionHeader(label: 'Earlier', isDark: dark),
          ...earlier.asMap().entries.map((e) => _buildTile(e.value, dark, card, txt, sub, e.key)),
        ],
      ],
    );
  }

  Widget _buildTile(_NotifModel n, bool dark, Color card, Color txt, Color sub, int index) {
    return Dismissible(
      key: ValueKey('notif_${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error.withOpacity(0.85),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
          SizedBox(height: 4),
          Text('Dismiss', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
      onDismissed: (_) => _dismiss(n),
      child: GestureDetector(
        onTap: () => _onTap(n),
        child: Container(
          color: n.isRead
              ? card
              : (dark ? AppColors.primary.withOpacity(0.07) : const Color(0xFFE8F0FE)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Actor avatar with action badge ──────────────────────────────
            _ActorAvatar(
              avatarUrl: n.actorAvatar ?? '',
              fallback:  _fallback(n),
              type:      n.type,
            ),
            const SizedBox(width: 12),

            // ── Content ─────────────────────────────────────────────────────
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Rich text: actor name bold + action
              _RichNotifText(n: n, textColor: txt, subColor: sub),
              const SizedBox(height: 4),
              // Post preview snippet
              if (n.postPreview != null && n.postPreview!.isNotEmpty)
                Text(
                  n.postPreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: sub, height: 1.35),
                ),
              const SizedBox(height: 6),
              // Time
              Text(n.timeAgo, style: TextStyle(fontSize: 12, color: n.isRead ? sub : AppColors.primary, fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600)),
            ])),

            const SizedBox(width: 10),

            // ── Post thumbnail OR unread dot ─────────────────────────────────
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.start, children: [
              if (n.postImage != null && n.postImage!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: n.postImage!,
                    width: 52, height: 52,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(width: 52, height: 52, color: dark ? Colors.grey.shade800 : Colors.grey.shade200),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                )
              else
                const SizedBox(width: 52, height: 52),
              const SizedBox(height: 8),
              if (!n.isRead)
                Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
            ]),
          ]),
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: index * 30), duration: const Duration(milliseconds: 220)),
        );
  }

  String _fallback(_NotifModel n) {
    final name = n.actorName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : _typeEmoji(n.type);
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'like':            return '❤️';
      case 'comment':         return '💬';
      case 'follow':          return '👤';
      case 'share':           return '📤';
      case 'save':            return '🔖';
      case 'new_post':        return '📣';
      case 'status_reaction': return '❤️';
      case 'streak_reminder': return '🔥';
      case 'task_reminder':   return '💰';
      case 'coins':           return '🪙';
      default:                return '🔔';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor Avatar with action badge
// ─────────────────────────────────────────────────────────────────────────────
class _ActorAvatar extends StatelessWidget {
  final String avatarUrl, fallback, type;
  const _ActorAvatar({required this.avatarUrl, required this.fallback, required this.type});

  Color get _badgeColor {
    switch (type) {
      case 'like':             return Colors.red;
      case 'comment':          return AppColors.primary;
      case 'follow':           return AppColors.success;
      case 'share':            return Colors.blue;
      case 'save':             return AppColors.primary;
      case 'new_post':         return AppColors.accent;
      case 'status_reaction':  return Colors.pink;
      case 'streak_reminder':  return Colors.orange;
      case 'task_reminder':    return AppColors.gold;
      case 'coins':            return AppColors.gold;
      default:                 return AppColors.primary;
    }
  }

  IconData get _badgeIcon {
    switch (type) {
      case 'like':             return Icons.favorite_rounded;
      case 'comment':          return Icons.mode_comment_rounded;
      case 'follow':           return Icons.person_add_rounded;
      case 'share':            return Icons.share_rounded;
      case 'save':             return Iconsax.archive_add;
      case 'new_post':         return Icons.post_add_rounded;
      case 'status_reaction':  return Icons.favorite_rounded;
      case 'streak_reminder':  return Icons.local_fire_department_rounded;
      case 'task_reminder':    return Icons.task_alt_rounded;
      case 'coins':            return Icons.monetization_on_rounded;
      default:                 return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return SizedBox(
      width: 52, height: 52,
      child: Stack(children: [
        // Avatar
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: avatarUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: avatarUrl,
                    fit: BoxFit.cover,
                    width: 52, height: 52,
                    placeholder: (_, __) => _ini(),
                    errorWidget: (_, __, ___) => _ini(),
                  )
                : _ini(),
          ),
        ),
        // Action badge
        Positioned(
          bottom: 0, right: 0,
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color:  _badgeColor,
              shape:  BoxShape.circle,
              border: Border.all(color: Theme.of(ctx).brightness == Brightness.dark ? Colors.black : Colors.white, width: 2),
            ),
            child: Center(child: Icon(_badgeIcon, color: Colors.white, size: 10)),
          ),
        ),
      ]),
    );
  }

  Widget _ini() => Container(
    color: AppColors.primary.withOpacity(0.15),
    child: Center(child: Text(fallback.length == 1 ? fallback : '👤', style: const TextStyle(fontSize: 18))),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rich notification text: "John liked your post"
// ─────────────────────────────────────────────────────────────────────────────
class _RichNotifText extends StatelessWidget {
  final _NotifModel n;
  final Color textColor, subColor;
  const _RichNotifText({required this.n, required this.textColor, required this.subColor});

  String _actionText() {
    switch (n.type) {
      case 'like':            return 'liked your post';
      case 'comment':         return 'commented on your post';
      case 'follow':          return 'started following you';
      case 'share':           return 'shared your post';
      case 'save':            return 'saved your post';
      case 'new_post':        return 'just posted something new';
      case 'status_reaction': return 'reacted ❤️ to your status';
      case 'streak_reminder': return 'Your streak is at risk! Check in now';
      case 'task_reminder':   return 'You have income tasks ready';
      case 'coins':           return n.message;
      default:                return n.message;
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final actorName = n.actorName;
    final action    = _actionText();

    if (actorName == null || actorName.isEmpty) {
      return Text(
        n.title.isNotEmpty ? n.title : action,
        style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w500, height: 1.4),
        maxLines: 3, overflow: TextOverflow.ellipsis,
      );
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: [
        TextSpan(
          text: actorName,
          style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w700, height: 1.4),
        ),
        TextSpan(
          text: ' $action',
          style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w400, height: 1.4),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final bool   isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize:      13,
        fontWeight:    FontWeight.w800,
        color:         isDark ? Colors.white60 : Colors.black45,
        letterSpacing: 0.4,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton tile
// ─────────────────────────────────────────────────────────────────────────────
class _SkeletonTile extends StatelessWidget {
  final bool isDark; final Color cardColor;
  const _SkeletonTile({required this.isDark, required this.cardColor});

  Widget _sh({double? w, required double h, bool circle = false}) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color:        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
        shape:        circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(6),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: isDark ? Colors.white10 : Colors.white70);
  }

  @override
  Widget build(BuildContext ctx) => Container(
    color: cardColor,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sh(w: 52, h: 52, circle: true),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sh(w: double.infinity, h: 14),
        const SizedBox(height: 6),
        _sh(w: 200, h: 12),
        const SizedBox(height: 6),
        _sh(w: 60, h: 10),
      ])),
      const SizedBox(width: 10),
      _sh(w: 52, h: 52),
    ]),
  );
}
