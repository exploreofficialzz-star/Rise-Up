import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final String postContent;
  final String postAuthor;
  const CommentsScreen({super.key, required this.postId, required this.postContent, required this.postAuthor});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getPostComments(widget.postId);
      if (mounted) setState(() { _comments = data['comments'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final data = await api.addComment(widget.postId, text);
      _ctrl.clear();
      if (mounted) {
        setState(() {
          _comments.add(data['comment'] as Map);
          _sending = false;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _likeComment(Map comment) async {
    try {
      final res = await api.likeComment(comment['id'].toString());
      setState(() {
        comment['is_liked'] = res['liked'] == true;
        final likes = comment['likes_count'] as int? ?? 0;
        comment['likes_count'] = res['liked'] == true ? likes + 1 : likes - 1;
      });
    } catch (_) {}
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Comments (${_comments.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: borderColor)),
      ),
      body: Column(children: [
        // Post preview
        Container(
          color: cardColor,
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle), child: const Center(child: Text('💼', style: TextStyle(fontSize: 18)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.postAuthor, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 4),
              Text(widget.postContent, style: TextStyle(fontSize: 13, color: subColor, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        Divider(height: 1, color: borderColor),

        // Comments
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _comments.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('💬', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('No comments yet. Be first!', style: TextStyle(color: subColor, fontSize: 14)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) {
                          final c = _comments[i] as Map;
                          final profile = c['profiles'] as Map? ?? {};
                          final name = profile['full_name']?.toString() ?? 'User';
                          final isLiked = c['is_liked'] == true;
                          final likes = c['likes_count'] as int? ?? 0;

                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                              child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '👤', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: isDark ? AppColors.bgSurface : Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                                  const SizedBox(height: 4),
                                  Text(c['content']?.toString() ?? '', style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
                                ]),
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                Text(_timeAgo(c['created_at']?.toString()), style: TextStyle(fontSize: 11, color: subColor)),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap: () => _likeComment(c),
                                  child: Row(children: [
                                    Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 14, color: isLiked ? Colors.red : subColor),
                                    const SizedBox(width: 4),
                                    Text('$likes', style: TextStyle(fontSize: 11, color: subColor)),
                                  ]),
                                ),
                                const SizedBox(width: 16),
                                Text('Reply', style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                              ]),
                            ])),
                          ]).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                        },
                      ),
                    ),
        ),

        // Input
        Container(
          decoration: BoxDecoration(color: cardColor, border: Border(top: BorderSide(color: borderColor))),
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), shape: BoxShape.circle), child: const Center(child: Text('👤', style: TextStyle(fontSize: 18)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _ctrl,
              style: TextStyle(fontSize: 14, color: textColor),
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                hintStyle: TextStyle(color: subColor, fontSize: 13),
                filled: true, fillColor: surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(gradient: LinearGradient(colors: _sending ? [Colors.grey.shade400, Colors.grey.shade400] : [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(12)),
                child: Icon(_sending ? Icons.hourglass_empty : Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
