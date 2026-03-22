import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String mode;
  final String? postContext;   // ← post content passed from feed
  final String? postAuthor;   // ← post author name

  const ChatScreen({
    super.key,
    this.conversationId,
    this.mode = 'general',
    this.postContext,
    this.postAuthor,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  final String text;
  final bool isUser;
  final String? model;
  _Msg(this.text, this.isUser, {this.model});
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String? _convId;
  bool _loading = false;
  String _currentModel = 'groq';
  bool _sentPostContext = false;

  static const _quickActions = [
    ('💰 Income ideas', 'What are some quick income tasks I can start today?'),
    ('📚 Skill advice', 'What skill should I learn to increase my income?'),
    ('🗺️ My roadmap', 'Show me my personalized wealth roadmap'),
    ('📊 Progress', 'Analyze my progress and tell me what to focus on'),
  ];

  @override
  void initState() {
    super.initState();
    _convId = widget.conversationId;
    if (_convId != null) {
      _loadHistory();
    } else if (widget.postContext != null) {
      _addPostContextWelcome();
    } else {
      _addWelcome();
    }
  }

  void _addWelcome() {
    _msgs.add(_Msg(
      "Hey! 👋 I'm your RiseUp AI mentor.\n\nI'm here to help you **earn more, learn faster, and build real wealth**.\n\nWhat would you like to work on today?",
      false,
    ));
  }

  void _addPostContextWelcome() {
    _msgs.add(_Msg(
      "Hey! 👋 I've read **${widget.postAuthor ?? 'that post'}**'s post.\n\nThis is your **private conversation** — everything you discuss here is only visible to you.\n\nFeel free to ask me anything about it, or explore the topic deeper. What would you like to know?",
      false,
    ));
    // Auto-send post context silently
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.postContext != null && !_sentPostContext) {
        _sendPostContext();
      }
    });
  }

  Future<void> _sendPostContext() async {
    _sentPostContext = true;
    setState(() => _loading = true);
    try {
      final prompt =
          '[PRIVATE CONTEXT — User came from this post on RiseUp]\n\nPost by ${widget.postAuthor ?? "a user"}:\n"${widget.postContext}"\n\nThe user wants to discuss this privately. Be ready to help them understand, apply, or go deeper on the topic of this post. Keep responses focused on wealth, income, and personal growth.';

      final res = await api.chat(
        message: prompt,
        mode: 'general',
      );
      _convId ??= res['conversation_id'];

      if (mounted) {
        setState(() {
          _msgs.add(_Msg(
            "I've analyzed the post. I'm ready to help you go **deeper on this topic privately**.\n\nAsk me anything — strategy, how to apply it, potential income, risks, or anything else on your mind! 💡",
            false,
            model: res['ai_model'],
          ));
          _loading = false;
        });
        _scrollDown();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final msgs = await api.getMessages(_convId!);
      if (mounted) {
        setState(() {
          for (final m in msgs) {
            if (m['role'] != 'system') {
              _msgs.add(_Msg(m['content'], m['role'] == 'user',
                  model: m['ai_model']));
            }
          }
        });
        _scrollDown();
      }
    } catch (_) {}
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _ctrl.text).trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(_Msg(msg, true));
      _loading = true;
    });
    _scrollDown();

    try {
      final res = await api.chat(
        message: msg,
        conversationId: _convId,
        mode: widget.mode,
      );
      _convId ??= res['conversation_id'];
      if (mounted) {
        setState(() {
          _msgs.add(_Msg(res['content'] ?? '...', false,
              model: res['ai_model']));
          _currentModel = res['ai_model'] ?? _currentModel;
          _loading = false;
        });
        _scrollDown();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _msgs.add(
              _Msg('Connection issue. Try again! 🔄', false));
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

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final surfaceColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final isFromPost = widget.postContext != null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: textColor, size: 18),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Column(
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
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isFromPost
                        ? '🔒 Private · Post context'
                        : 'Your personal wealth mentor',
                    style: TextStyle(
                        fontSize: 11, color: subColor),
                  ),
                ]),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),

      body: Column(
        children: [
          // ── Post context banner ──────────────────────
          if (isFromPost)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: AppColors.accent.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Iconsax.lock,
                      color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Private chat about ${widget.postAuthor ?? "this post"}\'s content',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Text(
                      'Back to feed',
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Messages ─────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _msgs.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _msgs.length)
                  return _buildTyping(isDark, surfaceColor);
                return _buildBubble(
                    _msgs[i], isDark, textColor, surfaceColor);
              },
            ),
          ),

          // ── Quick actions (empty state) ───────────────
          if (_msgs.length == 1 && !_loading && !isFromPost)
            _QuickActions(
                actions: _quickActions, onTap: _send),

          // ── Input bar ─────────────────────────────────
          _InputBar(
            ctrl: _ctrl,
            onSend: _send,
            loading: _loading,
            isDark: isDark,
            textColor: textColor,
            subColor: subColor,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_Msg m, bool isDark, Color textColor,
      Color surfaceColor) {
    final aiBubble =
        isDark ? AppColors.aiBubble : Colors.grey.shade100;

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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: m.isUser ? AppColors.userBubble : aiBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                  bottomRight:
                      Radius.circular(m.isUser ? 4 : 18),
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
                          height: 1.6,
                        ),
                        strong: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                          fontSize: 14,
                        ),
                        listBullet: TextStyle(
                          color: isDark
                              ? const Color(0xFFE8E8F0)
                              : Colors.black87,
                        ),
                        h3: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                        h4: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.15);
  }

  Widget _buildTyping(bool isDark, Color surfaceColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.aiBubble : surfaceColor,
              borderRadius: AppRadius.lg,
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
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(delay: Duration(milliseconds: i * 200))
                    .then()
                    .fadeOut(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick actions ──────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final List<(String, String)> actions;
  final Function(String) onTap;
  const _QuickActions({required this.actions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions
            .map((a) => GestureDetector(
                  onTap: () => onTap(a.$2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.bgCard
                          : Colors.grey.shade100,
                      borderRadius: AppRadius.pill,
                      border: Border.all(
                        color: isDark
                            ? AppColors.bgSurface
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Text(a.$1,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white70
                              : Colors.black54,
                        )),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final Function([String?]) onSend;
  final bool loading, isDark;
  final Color textColor, subColor, surfaceColor, borderColor;

  const _InputBar({
    required this.ctrl,
    required this.onSend,
    required this.loading,
    required this.isDark,
    required this.textColor,
    required this.subColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: TextStyle(fontSize: 14, color: textColor),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask your AI mentor...',
                hintStyle:
                    TextStyle(color: subColor, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: surfaceColor,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onSubmitted: loading ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: loading ? null : () => onSend(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: loading
                      ? [Colors.grey.shade400, Colors.grey.shade400]
                      : [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                loading
                    ? Icons.hourglass_empty
                    : Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
