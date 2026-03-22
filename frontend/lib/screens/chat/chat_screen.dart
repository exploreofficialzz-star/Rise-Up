import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String mode;
  final String? postContext;
  final String? postAuthor;

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
  bool isTyping;        // ← is this message currently typing
  String displayText;   // ← what's shown so far

  _Msg(this.text, this.isUser, {this.model})
      : isTyping = false,
        displayText = '';
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String? _convId;
  bool _loading = false;
  bool _soundEnabled = true;
  Timer? _typingTimer;

  static const _quickActions = [
    ('💰 Income ideas',  'What are some quick income tasks I can start today?'),
    ('📚 Skill advice',  'What skill should I learn to increase my income?'),
    ('🗺️ My roadmap',   'Show me my personalized wealth roadmap'),
    ('📊 Progress',      'Analyze my progress and tell me what to focus on'),
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

  @override
  void dispose() {
    _typingTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addWelcome() {
    final msg = _Msg(
      "Hey! 👋 I'm your RiseUp AI mentor.\n\nI'm here to help you **earn more, learn faster, and build real wealth**.\n\nWhat would you like to work on today?",
      false,
    );
    _msgs.add(msg);
    // Animate welcome message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _typeMessage(msg);
    });
  }

  void _addPostContextWelcome() {
    final msg = _Msg(
      "Hey! 👋 I've read **${widget.postAuthor ?? 'that post'}**'s post.\n\nThis is your **private conversation** — everything here is only visible to you.\n\nFeel free to ask me anything about it. What would you like to know?",
      false,
    );
    _msgs.add(msg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _typeMessage(msg);
      _sendPostContext();
    });
  }

  // ── Typewriter effect ──────────────────────────────
  void _typeMessage(_Msg msg) {
    if (!mounted) return;
    msg.isTyping = true;
    msg.displayText = '';

    final fullText = msg.text;
    int charIndex = 0;

    // Speed: ~25ms per character = natural typing speed
    _typingTimer = Timer.periodic(
      const Duration(milliseconds: 18),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (charIndex >= fullText.length) {
          timer.cancel();
          setState(() {
            msg.isTyping = false;
            msg.displayText = fullText;
          });
          return;
        }

        // Add next character
        charIndex++;
        setState(() {
          msg.displayText = fullText.substring(0, charIndex);
        });

        // Play tick sound every ~3 chars if enabled
        if (_soundEnabled && charIndex % 3 == 0) {
          HapticFeedback.selectionClick();
        }

        _scrollDown();
      },
    );
  }

  Future<void> _sendPostContext() async {
    setState(() => _loading = true);
    try {
      final prompt =
          '[PRIVATE CONTEXT — User came from this post on RiseUp]\n\nPost by ${widget.postAuthor ?? "a user"}:\n"${widget.postContext}"\n\nThe user wants to discuss this privately. Be ready to help them understand, apply, or go deeper on the topic of this post.';

      final res = await api.chat(message: prompt, mode: 'general');
      _convId ??= res['conversation_id'];

      if (mounted) {
        final msg = _Msg(
          "I've analyzed the post. I'm ready to help you go **deeper on this topic privately**.\n\nAsk me anything — strategy, how to apply it, potential income, risks, or anything else! 💡",
          false,
          model: res['ai_model'],
        );
        setState(() {
          _msgs.add(msg);
          _loading = false;
        });
        _typeMessage(msg);
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
              final msg = _Msg(m['content'], m['role'] == 'user',
                  model: m['ai_model']);
              // History messages show instantly — no typing
              msg.displayText = m['content'];
              _msgs.add(msg);
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

    final userMsg = _Msg(msg, true);
    userMsg.displayText = msg; // user messages show instantly

    setState(() {
      _msgs.add(userMsg);
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
        final aiMsg = _Msg(
          res['content'] ?? '...',
          false,
          model: res['ai_model'],
        );
        setState(() {
          _msgs.add(aiMsg);
          _loading = false;
        });
        _typeMessage(aiMsg); // ← animate AI response
        _scrollDown();
      }
    } catch (_) {
      if (mounted) {
        final errMsg = _Msg('Connection issue. Try again! 🔄', false);
        errMsg.displayText = 'Connection issue. Try again! 🔄';
        setState(() {
          _msgs.add(errMsg);
          _loading = false;
        });
      }
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
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
                Text('RiseUp AI',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor)),
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isFromPost
                        ? '🔒 Private · Post context'
                        : 'Your personal wealth mentor',
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ]),
              ],
            ),
          ],
        ),
        actions: [
          // Sound toggle
          IconButton(
            icon: Icon(
              _soundEnabled ? Iconsax.volume_high : Iconsax.volume_slash,
              color: _soundEnabled ? AppColors.primary : subColor,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _soundEnabled = !_soundEnabled),
            tooltip: _soundEnabled ? 'Mute typing sound' : 'Enable typing sound',
          ),
        ],
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
                    child: Text('Back to feed',
                        style: TextStyle(
                            fontSize: 11,
                            color: subColor,
                            decoration: TextDecoration.underline)),
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
                  return _buildTypingDots(isDark, surfaceColor);
                return _buildBubble(
                    _msgs[i], isDark, textColor, surfaceColor);
              },
            ),
          ),

          // ── Quick actions ────────────────────────────
          if (_msgs.length == 1 && !_loading && !isFromPost)
            _QuickActions(actions: _quickActions, onTap: _send,
                isDark: isDark),

          // ── Input bar ────────────────────────────────
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

  Widget _buildBubble(
      _Msg m, bool isDark, Color textColor, Color surfaceColor) {
    final aiBubble = isDark ? AppColors.aiBubble : Colors.grey.shade100;
    // Show displayText while typing, full text when done
    final shownText = m.displayText.isEmpty && !m.isUser
        ? ''
        : m.displayText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            m.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: m.isUser ? AppColors.userBubble : aiBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                  bottomRight: Radius.circular(m.isUser ? 4 : 18),
                ),
              ),
              child: m.isUser
                  ? Text(shownText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5))
                  : shownText.isEmpty
                      ? const SizedBox(height: 14)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: shownText,
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
                            // Blinking cursor while typing
                            if (m.isTyping)
                              _BlinkingCursor(isDark: isDark),
                          ],
                        ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildTypingDots(bool isDark, Color surfaceColor) {
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
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(
                        delay: Duration(milliseconds: i * 200))
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

// ── Blinking cursor ───────────────────────────────────
class _BlinkingCursor extends StatefulWidget {
  final bool isDark;
  const _BlinkingCursor({required this.isDark});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _ctrl.value,
        child: Container(
          width: 2,
          height: 14,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final List<(String, String)> actions;
  final Function(String) onTap;
  final bool isDark;
  const _QuickActions(
      {required this.actions, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
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

// ── Input Bar ─────────────────────────────────────────
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
          16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
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
                hintStyle: TextStyle(color: subColor, fontSize: 13),
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
