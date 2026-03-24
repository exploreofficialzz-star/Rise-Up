import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final String postContent;
  final String postAuthor;
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
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  List _comments     = [];
  Map  _aiComment    = {};   // pinned AI comment if exists
  Map  _postDetails  = {};
  Map  _posterProfile = {};
  bool _loading      = true;
  bool _sending      = false;
  bool _isFollowing  = false;
  bool _followLoading = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _myUserId = await api.getUserId();

      final List results = await Future.wait([
        api.getPostComments(widget.postId),
        if (widget.postUserId != null)
          api.get('/posts/users/${widget.postUserId}/profile'),
      ]);

      final commentsData = results[0] as Map? ?? {};
      final all = (commentsData['comments'] as List? ?? []).cast<Map>();

      // Separate pinned AI comment from regular comments
      Map aiComment = {};
      List regular  = [];
      for (final c in all) {
        if (c['is_ai'] == true || c['is_pinned'] == true) {
          aiComment = c;
        } else {
          regular.add(c);
        }
      }

      Map posterProfile = {};
      bool isFollowing  = false;
      if (results.length > 1) {
        final pd = results[1] as Map? ?? {};
        posterProfile = pd['profile'] as Map? ?? {};
        isFollowing   = pd['is_following'] == true;
      }

      if (mounted) setState(() {
        _comments      = regular;
        _aiComment     = aiComment;
        _posterProfile = posterProfile;
        _isFollowing   = isFollowing;
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() => _sending = true);
    try {
      final data = await api.addComment(widget.postId, text);
      if (mounted) setState(() {
        _comments.add(data['comment'] as Map? ?? {'content': text});
        _sending = false;
      });
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _likeComment(Map c) async {
    try {
      final r = await api.likeComment(c['id'].toString());
      setState(() {
        c['is_liked']    = r['liked'] == true;
        final n          = (c['likes_count'] as int? ?? 0);
        c['likes_count'] = r['liked'] == true ? n + 1 : (n - 1).clamp(0, 999999);
      });
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_followLoading || widget.postUserId == null) return;
    setState(() => _followLoading = true);
    try {
      final r = await api.toggleFollow(widget.postUserId!);
      setState(() {
        _isFollowing   = r['following'] == true;
        _followLoading = false;
      });
      HapticFeedback.lightImpact();
    } catch (_) {
      setState(() => _followLoading = false);
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours   < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? Colors.black : Colors.white;
    final card    = isDark ? AppColors.bgCard : Colors.white;
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text    = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final posterName   = _posterProfile['full_name']?.toString() ?? widget.postAuthor;
    final posterAvatar = _posterProfile['avatar_url']?.toString();
    final posterId     = widget.postUserId;
    final isOwnPost    = posterId != null && posterId == _myUserId;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
          tooltip: 'Back to post',
        ),
        title: Text('Comments (${_comments.length + (_aiComment.isNotEmpty ? 1 : 0)})',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.send_1, color: sub, size: 20),
            tooltip: 'Share post',
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'riseup.app/post/${widget.postId}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Post link copied!'),
                    backgroundColor: AppColors.success,
                    duration: Duration(seconds: 1)));
            },
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: Column(children: [
        // ── Post preview with poster profile + follow ─────────────
        GestureDetector(
          onTap: posterId != null
              ? () => context.push('/user-profile/$posterId')
              : null,
          child: Container(
            color: card,
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Poster avatar — tap to go to profile
              GestureDetector(
                onTap: posterId != null
                    ? () => context.push('/user-profile/$posterId')
                    : null,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: ClipOval(
                    child: posterAvatar != null && posterAvatar.isNotEmpty
                        ? Image.network(posterAvatar, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _initials(posterName))
                        : _initials(posterName),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GestureDetector(
                    onTap: posterId != null
                        ? () => context.push('/user-profile/$posterId')
                        : null,
                    child: Text(posterName, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                  ),
                  const Spacer(),
                  if (!isOwnPost && posterId != null)
                    GestureDetector(
                      onTap: _toggleFollow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isFollowing
                              ? Colors.transparent
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          border: _isFollowing
                              ? Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300)
                              : null,
                        ),
                        child: _followLoading
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2))
                            : Text(_isFollowing ? 'Following' : 'Follow',
                                style: TextStyle(
                                    color: _isFollowing
                                        ? sub
                                        : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(widget.postContent,
                    style: TextStyle(fontSize: 13, color: sub, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
        ),
        Divider(height: 1, color: border),

        // ── Comments list ──────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      // ── Pinned AI Comment ──────────────────────
                      if (_aiComment.isNotEmpty)
                        _AiCommentCard(
                          comment: _aiComment,
                          isDark: isDark,
                          text: text,
                          sub: sub,
                          surface: surface,
                          onTap: () {},
                        ).animate().fadeIn(),

                      if (_comments.isEmpty && _aiComment.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Column(children: [
                            const Text('💬', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('No comments yet — be first!',
                                style: TextStyle(color: sub, fontSize: 14)),
                          ]),
                        ),

                      // ── Regular comments ───────────────────────
                      ..._comments.asMap().entries.map((entry) {
                        final i = entry.key;
                        final c = entry.value as Map;
                        return _CommentCard(
                          comment: c,
                          isDark: isDark,
                          text: text,
                          sub: sub,
                          surface: surface,
                          onLike: () => _likeComment(c),
                          onProfileTap: () {
                            final uid = (c['profiles'] as Map?)?['id']?.toString()
                                ?? c['user_id']?.toString();
                            if (uid != null) context.push('/user-profile/$uid');
                          },
                          onReply: () {
                            final name = (c['profiles'] as Map?)?['full_name']?.toString() ?? 'User';
                            _ctrl.text = '@$name ';
                            FocusScope.of(context).requestFocus(FocusNode());
                          },
                          timeAgo: _timeAgo(c['created_at']?.toString()),
                          fmt: _fmt,
                        ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                      }),
                    ],
                  ),
                ),
        ),

        // ── Comment input ──────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
              color: card,
              border: Border(top: BorderSide(color: border))),
          padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Icon(Icons.person_rounded,
                  color: Colors.white, size: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(fontSize: 14, color: text),
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: sub, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: _sending
                          ? [Colors.grey.shade400, Colors.grey.shade400]
                          : [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_sending ? Icons.hourglass_empty_rounded : Icons.send_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _initials(String name) => Container(
    color: AppColors.primary.withOpacity(0.15),
    child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
            color: AppColors.primary))),
  );
}

// ── Pinned AI Comment Card ─────────────────────────────────────────
class _AiCommentCard extends StatelessWidget {
  final Map comment;
  final bool isDark;
  final Color text, sub, surface;
  final VoidCallback onTap;

  const _AiCommentCard({
    required this.comment, required this.isDark,
    required this.text, required this.sub, required this.surface,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = comment['content']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.08), AppColors.accent.withOpacity(0.06)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pinned header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(child: Icon(Icons.auto_awesome,
                  color: Colors.white, size: 12)),
            ),
            const SizedBox(width: 8),
            const Text('RiseUp AI',
                style: TextStyle(fontSize: 12, color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('PINNED',
                  style: TextStyle(fontSize: 8, color: AppColors.primary,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
            const Spacer(),
            Icon(Icons.push_pin_rounded, size: 14,
                color: AppColors.primary.withOpacity(0.6)),
          ]),
        ),
        // Content
        Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(content,
              style: TextStyle(fontSize: 13, color: text, height: 1.5)),
        ),
      ]),
    );
  }
}

// ── Regular Comment Card ───────────────────────────────────────────
class _CommentCard extends StatelessWidget {
  final Map     comment;
  final bool    isDark;
  final Color   text, sub, surface;
  final VoidCallback onLike, onProfileTap, onReply;
  final String  timeAgo;
  final String Function(int) fmt;

  const _CommentCard({
    required this.comment, required this.isDark,
    required this.text, required this.sub, required this.surface,
    required this.onLike, required this.onProfileTap, required this.onReply,
    required this.timeAgo, required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final profile  = comment['profiles'] as Map? ?? {};
    final name     = profile['full_name']?.toString() ?? 'User';
    final avatar   = profile['avatar_url']?.toString();
    final content  = comment['content']?.toString() ?? '';
    final isLiked  = comment['is_liked'] == true;
    final likes    = comment['likes_count'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar — tap opens profile
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: ClipOval(
              child: avatar != null && avatar.isNotEmpty
                  ? Image.network(avatar, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initials(name))
                  : _initials(name),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Name — tap opens profile
              GestureDetector(
                onTap: onProfileTap,
                child: Text(name, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: text)),
              ),
              const SizedBox(height: 4),
              Text(content, style: TextStyle(
                  fontSize: 13, color: text, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(timeAgo, style: TextStyle(fontSize: 11, color: sub)),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onLike,
              child: Row(children: [
                Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 14,
                    color: isLiked ? Colors.red : sub),
                const SizedBox(width: 4),
                Text(fmt(likes), style: TextStyle(fontSize: 11, color: sub)),
              ]),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onReply,
              child: Text('Reply', style: TextStyle(
                  fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
            ),
          ]),
        ])),
      ]),
    );
  }

  Widget _initials(String name) => Container(
    color: AppColors.primary.withOpacity(0.15),
    child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
            color: AppColors.primary))),
  );
}
