import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final String postContent;
  final String postAuthor;
  const CommentsScreen({super.key, required this.postId, required this.postContent, required this.postAuthor});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _Comment {
  final String avatar, name, text, time;
  int likes;
  bool liked;
  _Comment({required this.avatar, required this.name, required this.text, required this.time, this.likes = 0, this.liked = false});
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  final _comments = [
    _Comment(avatar: '🚀', name: 'Sarah Builds', text: 'This is exactly what I needed to hear today! Taking action right now.', time: '5m ago', likes: 12),
    _Comment(avatar: '💎', name: 'Marcus Wealth', text: 'Couldn\'t agree more. I made my first \$5K using this exact mindset. It works!', time: '12m ago', likes: 34),
    _Comment(avatar: '🎯', name: 'Priya Skills', text: 'The key insight here is "ONE specific problem". Most people try to solve everything.', time: '30m ago', likes: 8),
    _Comment(avatar: '🔥', name: 'David Hustle', text: 'Bookmarked. Sharing this with my accountability group 🔥', time: '1h ago', likes: 5),
    _Comment(avatar: '🌱', name: 'Linda Growth', text: 'How long did it take you to get to this level? Any tips for beginners?', time: '2h ago', likes: 2),
  ];

  void _addComment() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _comments.insert(0, _Comment(avatar: '👤', name: 'You', text: text, time: 'Just now'));
    });
    _ctrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

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
        title: Text('Comments',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(
        children: [
          // ── Original post preview ─────────────────────
          Container(
            color: cardColor,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                  child: const Center(child: Text('💼', style: TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.postAuthor, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                      const SizedBox(height: 4),
                      Text(widget.postContent, style: TextStyle(fontSize: 13, color: subColor, height: 1.4),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),

          // ── Comments list ─────────────────────────────
          Expanded(
            child: ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _comments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (_, i) {
                final c = _comments[i];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(c.avatar, style: const TextStyle(fontSize: 18))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                                const SizedBox(height: 4),
                                Text(c.text, style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Text(c.time, style: TextStyle(fontSize: 11, color: subColor)),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () => setState(() { c.liked = !c.liked; c.likes += c.liked ? 1 : -1; }),
                              child: Row(children: [
                                Icon(c.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    size: 14, color: c.liked ? Colors.red : subColor),
                                const SizedBox(width: 4),
                                Text('${c.likes}', style: TextStyle(fontSize: 11, color: subColor)),
                              ]),
                            ),
                            const SizedBox(width: 16),
                            Text('Reply', style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
              },
            ),
          ),

          // ── Comment input ─────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('👤', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: subColor, fontSize: 13),
                    filled: true,
                    fillColor: surfaceColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addComment,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
