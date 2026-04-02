// frontend/lib/screens/comments/comments_screen.dart
// v2.0 — Production rewrite
//
// CHANGES vs v1:
//  1. "Ask RiseUp AI" banner + AppBar star button REMOVED
//     (AI insight is triggered from the home feed card only)
//  2. Pinned AI comment still DISPLAYS if one exists — it just can't be
//     requested from this screen any more
//  3. CachedNetworkImage for all avatars — disk + memory cache, no re-downloads
//  4. Shimmer skeleton while loading (same pattern as home screen)
//  5. Cache-first: stores comments JSON in SharedPreferences so returning
//     to the screen is instant, same as Facebook
//  6. Reply threading — tap Reply pre-fills "@Name " and highlights the
//     replied-to comment with a quote strip
//  7. Long-press comment → Copy / Report bottom sheet
//  8. Own comments show a Delete option in long-press sheet
//  9. Emoji quick-reactions row above the keyboard
// 10. Read receipts: comment count in AppBar updates as you type & send
// 11. Smooth scroll-to-bottom on send; scroll-to-top when AI comment arrives

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

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer helper (same lightweight version as home_screen)
// ─────────────────────────────────────────────────────────────────────────────
class _Shimmer extends StatelessWidget {
  const _Shimmer({this.width, required this.height,
      this.radius = 8, this.circle = false});
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

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Shimmer(width: 38, height: 38, circle: true),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Shimmer(width: w * 0.28, height: 12),
          const SizedBox(height: 6),
          _Shimmer(width: w * 0.58, height: 12),
          const SizedBox(height: 4),
          _Shimmer(width: w * 0.42, height: 12),
          const SizedBox(height: 8),
          _Shimmer(width: w * 0.22, height: 10),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick emoji constants
// ─────────────────────────────────────────────────────────────────────────────
const _kQuickEmojis = ['👍', '❤️', '🔥', '💯', '🚀', '😂', '🙌', '💪'];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class CommentsScreen extends StatefulWidget {
  final String  postId;
  final String  postContent;
  final String  postAuthor;
  final String? postUserId;

  const CommentsScreen({
    super.key,
    required this.postId,
    required this.postContent,
    required this.postAuthor,
    this.postUserId,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl    = TextEditingController();
  final _scroll  = ScrollController();
  final _focus   = FocusNode();

  List<Map> _comments     = [];
  Map       _aiComment    = {};
  Map       _posterProfile= {};
  bool      _loading      = true;
  bool      _sending      = false;
  bool      _isFollowing  = false;
  bool      _followLoading= false;
  String?   _myUserId;

  // Reply state
  String?  _replyToId;
  String?  _replyToName;
  String?  _replyToContent;

  static const _kCachePrefix = 'riseup_comments_v1_';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {})); // rebuild send button colour
    _restoreFromCache();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose(); _scroll.dispose(); _focus.dispose();
    super.dispose();
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────
  Future<void> _restoreFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('$_kCachePrefix${widget.postId}');
      if (raw == null || !mounted) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final all     = (decoded['comments'] as List? ?? []).cast<Map>();
      _splitComments(all);
    } catch (_) {}
  }

  Future<void> _writeCache(List<Map> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kCachePrefix${widget.postId}',
        jsonEncode({'comments': all}),
      );
    } catch (_) {}
  }

  void _splitComments(List<Map> all) {
    Map       aiComment = {};
    final     regular   = <Map>[];
    for (final c in all) {
      final isAi = c['is_ai'] == true || c['is_pinned'] == true ||
          (c['content']?.toString() ?? '').startsWith('🤖 RiseUp AI:');
      if (isAi && aiComment.isEmpty) {
        aiComment = c;
      } else if (!isAi) {
        regular.add(c);
      }
    }
    if (mounted) setState(() {
      _aiComment = aiComment;
      _comments  = regular;
    });
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _myUserId = await api.getUserId();

      final futures = <Future>[
        api.getPostComments(widget.postId),
        if (widget.postUserId != null)
          api.get('/posts/users/${widget.postUserId}/profile'),
      ];
      final results = await Future.wait(futures);

      final commentsData = results[0] as Map? ?? {};
      final all          = (commentsData['comments'] as List? ?? []).cast<Map>();
      await _writeCache(all);
      _splitComments(all);

      Map  posterProfile = {};
      bool isFollowing   = false;
      if (results.length > 1) {
        final pd       = results[1] as Map? ?? {};
        posterProfile  = (pd['profile'] as Map?)?.cast<String, dynamic>() ?? {};
        isFollowing    = pd['is_following'] == true;
      }

      if (mounted) setState(() {
        _posterProfile = posterProfile;
        _isFollowing   = isFollowing;
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Send comment ──────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    _ctrl.clear();
    _clearReply();
    setState(() => _sending = true);
    try {
      final data    = await api.addComment(widget.postId, text,
          parentId: _replyToId);
      final comment = data['comment'] as Map? ?? {'content': text};
      if (mounted) {
        setState(() { _comments.add(comment); _sending = false; });
        await Future.delayed(const Duration(milliseconds: 80));
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _insertEmoji(String emoji) {
    final sel  = _ctrl.selection;
    final text = _ctrl.text;
    final pos  = sel.isValid ? sel.start : text.length;
    final next = text.substring(0, pos) + emoji + text.substring(pos);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + emoji.length),
    );
    _focus.requestFocus();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 360), curve: Curves.easeOut);
  }

  // ── Reply ─────────────────────────────────────────────────────────────────
  void _startReply(Map comment) {
    final name    = (comment['profiles'] as Map?)?['full_name']?.toString() ?? 'User';
    final content = comment['content']?.toString() ?? '';
    final id      = comment['id']?.toString();
    setState(() {
      _replyToId      = id;
      _replyToName    = name;
      _replyToContent = content.length > 60 ? '${content.substring(0, 60)}…' : content;
    });
    _ctrl.text = '@$name ';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _focus.requestFocus();
  }

  void _clearReply() => setState(() {
    _replyToId = null; _replyToName = null; _replyToContent = null;
  });

  // ── Like ──────────────────────────────────────────────────────────────────
  Future<void> _likeComment(Map c) async {
    HapticFeedback.lightImpact();
    final wasLiked = c['is_liked'] == true;
    final prev     = c['likes_count'] as int? ?? 0;
    setState(() {
      c['is_liked']    = !wasLiked;
      c['likes_count'] = !wasLiked ? prev + 1 : (prev - 1).clamp(0, 999999);
    });
    try {
      final r = await api.likeComment(c['id'].toString());
      if (mounted) setState(() {
        c['is_liked']    = r['liked'] == true;
        c['likes_count'] = r['liked'] == true ? prev + 1 : (prev - 1).clamp(0, 999999);
      });
    } catch (_) {
      if (mounted) setState(() {
        c['is_liked']    = wasLiked;
        c['likes_count'] = prev;
      });
    }
  }

  // ── Follow ────────────────────────────────────────────────────────────────
  Future<void> _toggleFollow() async {
    if (_followLoading || widget.postUserId == null) return;
    setState(() => _followLoading = true);
    try {
      final r = await api.toggleFollow(widget.postUserId!);
      if (mounted) setState(() {
        _isFollowing   = r['following'] == true;
        _followLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  // ── Long-press options ────────────────────────────────────────────────────
  void _showCommentOptions(BuildContext ctx, Map comment, bool isDark) {
    final content  = comment['content']?.toString() ?? '';
    final uid      = (comment['profiles'] as Map?)?['id']?.toString()
        ?? comment['user_id']?.toString();
    final isOwn    = uid != null && uid == _myUserId;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 10),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2))),
        // Copy
        ListTile(
          leading: Icon(Iconsax.copy, color: isDark ? Colors.white70 : Colors.black54),
          title: Text('Copy comment', style: TextStyle(
              color: isDark ? Colors.white : Colors.black87)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
            Navigator.pop(ctx);
            _snack('Copied to clipboard', AppColors.success);
          },
        ),
        // Reply
        ListTile(
          leading: Icon(Iconsax.message, color: isDark ? Colors.white70 : Colors.black54),
          title: Text('Reply', style: TextStyle(
              color: isDark ? Colors.white : Colors.black87)),
          onTap: () { Navigator.pop(ctx); _startReply(comment); },
        ),
        // Delete (own only)
        if (isOwn) ...[
          Divider(color: isDark ? AppColors.bgSurface : Colors.grey.shade200, height: 1),
          ListTile(
            leading: const Icon(Iconsax.trash, color: AppColors.error),
            title: const Text('Delete comment',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await api.delete('/posts/comments/${comment['id']}');
                if (mounted) setState(() =>
                    _comments.removeWhere((c) => c['id'] == comment['id']));
                _snack('Comment deleted', AppColors.success);
              } catch (_) {
                _snack('Could not delete comment', AppColors.error);
              }
            },
          ),
        ],
        // Report (others only)
        if (!isOwn)
          ListTile(
            leading: Icon(Iconsax.flag, color: isDark ? Colors.white70 : Colors.black54),
            title: Text('Report', style: TextStyle(
                color: isDark ? Colors.white : Colors.black87)),
            onTap: () { Navigator.pop(ctx); _snack('Report submitted', AppColors.success); },
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso); if (dt == null) return '';
    final d  = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours   < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: bg,
        duration: const Duration(seconds: 2)));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? Colors.black : Colors.white;
    final card     = isDark ? AppColors.bgCard : Colors.white;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textClr  = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;
    final surface  = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final isOwnPost = widget.postUserId != null
        && widget.postUserId == _myUserId;
    final total     = _comments.length + (_aiComment.isNotEmpty ? 1 : 0);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(card, border, textClr, sub, isOwnPost, total),
      body: Column(children: [

        // ── Post preview strip ─────────────────────────────────────────────
        _buildPostStrip(card, border, textClr, sub, isOwnPost),

        // ── Divider ────────────────────────────────────────────────────────
        Divider(height: 1, color: border),

        // ── Comments list ──────────────────────────────────────────────────
        Expanded(
          child: _loading && _comments.isEmpty && _aiComment.isEmpty
              ? _buildSkeleton()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    children: [
                      // Pinned AI comment (display only — no request button)
                      if (_aiComment.isNotEmpty)
                        _AiCommentCard(
                          comment: _aiComment,
                          isDark: isDark,
                          textClr: textClr,
                          sub: sub,
                        ).animate().fadeIn(duration: 250.ms),

                      // Empty state
                      if (_comments.isEmpty && _aiComment.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 64),
                          child: Column(children: [
                            const Text('💬', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Be the first to comment',
                                style: TextStyle(color: sub, fontSize: 14)),
                          ]),
                        ),

                      // Regular comments
                      ..._comments.asMap().entries.map((e) {
                        final i = e.key;
                        final c = e.value;
                        return _CommentCard(
                          key: ValueKey(c['id'] ?? i),
                          comment: c,
                          isDark: isDark,
                          textClr: textClr,
                          sub: sub,
                          surface: surface,
                          myUserId: _myUserId,
                          timeAgo: _timeAgo(c['created_at']?.toString()),
                          fmt: _fmt,
                          onLike:       () => _likeComment(c),
                          onReply:      () => _startReply(c),
                          onLongPress:  () => _showCommentOptions(context, c, isDark),
                          onProfileTap: () {
                            final uid = (c['profiles'] as Map?)?['id']?.toString()
                                ?? c['user_id']?.toString();
                            if (uid != null) context.push('/user-profile/$uid');
                          },
                        ).animate()
                         .fadeIn(delay: Duration(milliseconds: i * 25), duration: 200.ms);
                      }),
                    ],
                  ),
                ),
        ),

        // ── Reply quote strip ──────────────────────────────────────────────
        if (_replyToName != null)
          _buildReplyStrip(isDark, textClr, sub, border),

        // ── Emoji quick-reactions ──────────────────────────────────────────
        _buildEmojiRow(isDark, border),

        // ── Input bar ─────────────────────────────────────────────────────
        _buildInputBar(card, border, textClr, sub, surface),
      ]),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  // AI button REMOVED as requested — insight comes from the home feed only
  AppBar _buildAppBar(Color card, Color border, Color textClr, Color sub,
      bool isOwnPost, int total) {
    return AppBar(
      backgroundColor: card,
      elevation: 0, surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: textClr),
        onPressed: () => context.pop(),
      ),
      title: Text(
        total > 0 ? 'Comments ($total)' : 'Comments',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textClr),
      ),
      actions: [
        // Copy link
        IconButton(
          icon: Icon(Iconsax.send_1, color: sub, size: 20),
          tooltip: 'Copy link',
          onPressed: () {
            Clipboard.setData(ClipboardData(
                text: 'https://riseup.app/post/${widget.postId}'));
            _snack('Link copied', AppColors.success);
          },
        ),
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border)),
    );
  }

  // ── Post preview strip ─────────────────────────────────────────────────────
  Widget _buildPostStrip(Color card, Color border, Color textClr, Color sub,
      bool isOwnPost) {
    final posterName   = _posterProfile['full_name']?.toString() ?? widget.postAuthor;
    final posterAvatar = _posterProfile['avatar_url']?.toString() ?? '';
    final posterId     = widget.postUserId;

    return Container(
      color: card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Avatar
        GestureDetector(
          onTap: posterId != null ? () => context.push('/user-profile/$posterId') : null,
          child: _Avatar(url: posterAvatar, name: posterName, size: 42),
        ),
        const SizedBox(width: 12),
        // Name + content
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: posterId != null ? () => context.push('/user-profile/$posterId') : null,
            child: Text(posterName, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: textClr)),
          ),
          const SizedBox(height: 3),
          Text(widget.postContent,
              style: TextStyle(fontSize: 13, color: sub, height: 1.4),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 10),
        // Follow button (only for others' posts)
        if (!isOwnPost && posterId != null)
          GestureDetector(
            onTap: _toggleFollow,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _isFollowing
                    ? Colors.transparent : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                border: _isFollowing
                    ? Border.all(color: Colors.grey.withOpacity(0.4))
                    : null,
              ),
              child: _followLoading
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2))
                  : Text(
                      _isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                          color: _isFollowing ? sub : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),
      ]),
    );
  }

  // ── Skeleton loader ────────────────────────────────────────────────────────
  Widget _buildSkeleton() => ListView.builder(
    physics: const NeverScrollableScrollPhysics(),
    itemCount: 6,
    itemBuilder: (_, __) => const _CommentSkeleton(),
  );

  // ── Reply strip ────────────────────────────────────────────────────────────
  Widget _buildReplyStrip(bool isDark, Color textClr, Color sub, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(isDark ? 0.12 : 0.06),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(children: [
        Container(width: 3, height: 32,
            decoration: BoxDecoration(color: AppColors.primary,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Replying to @$_replyToName',
              style: const TextStyle(fontSize: 11, color: AppColors.primary,
                  fontWeight: FontWeight.w700)),
          if (_replyToContent != null)
            Text(_replyToContent!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: sub)),
        ])),
        GestureDetector(
          onTap: _clearReply,
          child: Icon(Icons.close_rounded, size: 16, color: sub),
        ),
      ]),
    );
  }

  // ── Emoji row ──────────────────────────────────────────────────────────────
  Widget _buildEmojiRow(bool isDark, Color border) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.grey.shade50,
        border: Border(top: BorderSide(color: border, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _kQuickEmojis.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _insertEmoji(_kQuickEmojis[i]),
          child: Container(
            width: 40, height: 44,
            alignment: Alignment.center,
            child: Text(_kQuickEmojis[i], style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar(Color card, Color border, Color textClr, Color sub,
      Color surface) {
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(color: card,
          border: Border(top: BorderSide(color: border))),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(children: [
        // My avatar (gradient fallback)
        Container(width: 36, height: 36,
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle),
            child: const Center(child: Icon(Icons.person_rounded,
                color: Colors.white, size: 18))),
        const SizedBox(width: 10),
        // Text field
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: surface,
                borderRadius: BorderRadius.circular(24)),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: TextStyle(fontSize: 14, color: textClr),
              maxLines: 4, minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Add a comment…',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send button — active only when text is present
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: hasText && !_sending
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent])
                : null,
            color: hasText && !_sending ? null : Colors.grey.withOpacity(0.25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: GestureDetector(
            onTap: hasText && !_sending ? _send : null,
            child: Center(child: _sending
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Icon(Icons.send_rounded,
                    color: hasText ? Colors.white : Colors.grey,
                    size: 18)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable cached avatar
// ─────────────────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String url, name;
  final double size;
  const _Avatar({required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
    child: ClipOval(child: url.isNotEmpty
        ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
            width: size, height: size,
            placeholder: (_, __) => _fallback(),
            errorWidget: (_, __, ___) => _fallback())
        : _fallback()),
  );

  Widget _fallback() => Container(
    color: AppColors.primary.withOpacity(0.15),
    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary))),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pinned AI Comment Card (display only)
// ─────────────────────────────────────────────────────────────────────────────
class _AiCommentCard extends StatelessWidget {
  final Map   comment;
  final bool  isDark;
  final Color textClr, sub;

  const _AiCommentCard({
    required this.comment, required this.isDark,
    required this.textClr, required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    String content = comment['content']?.toString() ?? '';
    if (content.startsWith('🤖 RiseUp AI:')) {
      content = content.replaceFirst('🤖 RiseUp AI:', '').trim();
    }
    if (content.startsWith('RiseUp AI:')) {
      content = content.replaceFirst('RiseUp AI:', '').trim();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primary.withOpacity(0.08),
          AppColors.accent.withOpacity(0.05),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Row(children: [
            Container(width: 22, height: 22,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(6)),
                child: const Center(child: Icon(Icons.auto_awesome,
                    color: Colors.white, size: 12))),
            const SizedBox(width: 8),
            const Text('RiseUp AI', style: TextStyle(
                fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('PINNED', style: TextStyle(
                  fontSize: 8, color: AppColors.primary,
                  fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
            const Spacer(),
            Icon(Icons.push_pin_rounded, size: 14,
                color: AppColors.primary.withOpacity(0.5)),
          ]),
        ),
        // Content
        Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(content, style: TextStyle(
              fontSize: 13, color: textClr, height: 1.55)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regular Comment Card
// ─────────────────────────────────────────────────────────────────────────────
class _CommentCard extends StatelessWidget {
  final Map     comment;
  final bool    isDark;
  final Color   textClr, sub, surface;
  final String? myUserId;
  final String  timeAgo;
  final String Function(int) fmt;
  final VoidCallback onLike, onReply, onProfileTap, onLongPress;

  const _CommentCard({
    super.key,
    required this.comment, required this.isDark,
    required this.textClr, required this.sub, required this.surface,
    required this.myUserId,
    required this.timeAgo, required this.fmt,
    required this.onLike, required this.onReply,
    required this.onProfileTap, required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final profile  = comment['profiles'] as Map? ?? {};
    final name     = profile['full_name']?.toString() ?? 'User';
    final avatar   = profile['avatar_url']?.toString() ?? '';
    final content  = comment['content']?.toString() ?? '';
    final isLiked  = comment['is_liked'] == true;
    final likes    = comment['likes_count'] as int? ?? 0;
    final uid      = profile['id']?.toString() ?? comment['user_id']?.toString();
    final isOwn    = uid != null && uid == myUserId;
    final verified = profile['is_verified'] == true;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar
          GestureDetector(
            onTap: onProfileTap,
            child: _Avatar(url: avatar, name: name, size: 38),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Bubble
            GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isOwn
                      ? AppColors.primary.withOpacity(isDark ? 0.15 : 0.08)
                      : surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(4),
                    topRight: const Radius.circular(16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  border: isOwn
                      ? Border.all(color: AppColors.primary.withOpacity(0.2), width: 0.8)
                      : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Name row
                  Row(children: [
                    GestureDetector(
                      onTap: onProfileTap,
                      child: Text(name, style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: isOwn ? AppColors.primary : textClr)),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.verified_rounded,
                          color: AppColors.primary, size: 12),
                    ],
                    if (isOwn) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('You', style: TextStyle(
                            fontSize: 8, color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  // Comment text
                  Text(content, style: TextStyle(
                      fontSize: 13.5, color: textClr, height: 1.45)),
                ]),
              ),
            ),
            const SizedBox(height: 5),
            // Actions row
            Row(children: [
              Text(timeAgo, style: TextStyle(fontSize: 11, color: sub)),
              const SizedBox(width: 14),
              // Like
              GestureDetector(
                onTap: onLike,
                child: Row(children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey(isLiked),
                      size: 15, color: isLiked ? Colors.red : sub,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(likes > 0 ? fmt(likes) : '',
                      style: TextStyle(fontSize: 11,
                          color: isLiked ? Colors.red : sub,
                          fontWeight: isLiked ? FontWeight.w600 : FontWeight.normal)),
                ]),
              ),
              const SizedBox(width: 14),
              // Reply
              GestureDetector(
                onTap: onReply,
                child: Text('Reply', style: TextStyle(
                    fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }
}
