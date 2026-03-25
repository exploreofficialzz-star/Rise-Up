import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart';

class PostAiSheet extends StatefulWidget {
  final PostModel post;
  final bool postAsComment;
  const PostAiSheet({super.key, required this.post, this.postAsComment = false});
  @override
  State<PostAiSheet> createState() => _PostAiSheetState();
}

class _AiMessage {
  final String text;
  final bool isUser;
  _AiMessage(this.text, this.isUser);
}

class _PostAiSheetState extends State<PostAiSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_AiMessage> _messages = [];
  String? _convId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Auto-ask AI about the post on open
    _autoAsk();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _autoAsk() async {
    setState(() => _loading = true);
    try {
      final prompt =
          'A user posted this on RiseUp (a wealth & hustle social platform):\n\n"${widget.post.content}"\n\nPosted by ${widget.post.name} under the category "${widget.post.tag}".\n\nPlease give a detailed, practical, and insightful wealth response to this post. Include actionable advice, relevant strategies, and any important context that would help the community.';

      final res = await api.chat(
        message: prompt,
        mode: 'general',
      );
      _convId = res['conversation_id'];

      final aiResponse = res['content'] ?? '...';

      if (mounted) {
        setState(() {
          _messages.add(_AiMessage(aiResponse, false));
          _loading = false;
        });
        _scrollDown();

        // FIX: Post AI response as a comment on the original post
        if (widget.postAsComment && aiResponse.isNotEmpty) {
          api.addComment(widget.post.id, '🤖 RiseUp AI: $aiResponse').catchError((_) => {});
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(_AiMessage('Unable to connect. Please try again! 🔄', false));
          _loading = false;
        });
      }
    }
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _ctrl.text).trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_AiMessage(msg, true));
      _loading = true;
    });
    _scrollDown();

    try {
      final res = await api.chat(
        message: msg,
        conversationId: _convId,
        mode: 'general',
      );
      _convId ??= res['conversation_id'];

      if (mounted) {
        setState(() {
          _messages.add(
              _AiMessage(res['content'] ?? '...', false));
          _loading = false;
        });
        _scrollDown();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(_AiMessage(
              'Connection issue. Try again! 🔄', false));
          _loading = false;
        });
      }
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Follow-up quick suggestions
  static const _followUps = [
    'How do I start this?',
    'Give me a step-by-step plan',
    'What are the risks?',
    'How much can I earn?',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.bgCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final surfaceColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle ──────────────────────────────────
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white24
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RiseUp AI',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'Responding to ${widget.post.name}\'s post',
                        style: TextStyle(
                            fontSize: 12, color: subColor),
                      ),
                    ],
                  ),
                ),
                // Public badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '🌍 Public',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close,
                        color: subColor, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // ── Post preview ─────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(widget.post.avatar,
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.name,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor),
                      ),
                      Text(
                        widget.post.content.length > 80
                            ? '${widget.post.content.substring(0, 80)}...'
                            : widget.post.content,
                        style: TextStyle(
                            fontSize: 11, color: subColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(
              height: 20,
              indent: 16,
              endIndent: 16,
              color: borderColor),

          // ── Messages ─────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length)
                  return _buildTyping(isDark);
                return _buildBubble(
                    _messages[i], isDark, textColor);
              },
            ),
          ),

          // ── Follow-up suggestions ─────────────────────
          if (_messages.isNotEmpty && !_loading)
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16),
                itemCount: _followUps.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _send(_followUps[i]),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      _followUps[i],
                      style: TextStyle(
                          fontSize: 12, color: subColor),
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // ── Input ─────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: bgColor,
              border:
                  Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: TextStyle(
                        fontSize: 14, color: textColor),
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization:
                        TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Ask a follow-up question...',
                      hintStyle: TextStyle(
                          color: subColor, fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: surfaceColor,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                    ),
                    onSubmitted:
                        _loading ? null : (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _loading ? null : () => _send(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _loading
                            ? [
                                Colors.grey.shade400,
                                Colors.grey.shade400
                              ]
                            : [
                                AppColors.primary,
                                AppColors.accent
                              ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _loading
                          ? Icons.hourglass_empty
                          : Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
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

  Widget _buildBubble(
      _AiMessage m, bool isDark, Color textColor) {
    final aiBubble =
        isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: m.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.isUser ? AppColors.userBubble : aiBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(m.isUser ? 16 : 4),
                  bottomRight:
                      Radius.circular(m.isUser ? 4 : 16),
                ),
              ),
              child: m.isUser
                  ? Text(m.text,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5))
                  : MarkdownBody(
                      data: m.text,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                            color: isDark
                                ? const Color(0xFFE8E8F0)
                                : Colors.black87,
                            fontSize: 14,
                            height: 1.6),
                        strong: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontSize: 14),
                        listBullet: TextStyle(
                            color: isDark
                                ? const Color(0xFFE8E8F0)
                                : Colors.black87),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTyping(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.bgSurface
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
