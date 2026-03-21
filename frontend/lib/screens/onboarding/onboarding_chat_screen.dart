import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../utils/storage_service.dart';

class OnboardingChatScreen extends StatefulWidget {
  const OnboardingChatScreen({super.key});
  @override
  State<OnboardingChatScreen> createState() => _OnboardingChatScreenState();
}

class _Message {
  final String text;
  final bool isUser;
  final DateTime time;
  _Message(this.text, this.isUser) : time = DateTime.now();
}

class _OnboardingChatScreenState extends State<OnboardingChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  String? _conversationId;
  bool _loading = false;
  bool _complete = false;

  static const _welcomeMsg =
      "Hey there! 👋 I'm your RiseUp AI mentor, and I'm genuinely excited to help you build real wealth.\n\nBefore I can create your personal roadmap, I need to understand your story. Let's chat — it'll only take a few minutes.\n\n**First question: What's your name, and where are you based?**";

  @override
  void initState() {
    super.initState();
    _messages.add(_Message(_welcomeMsg, false));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _ctrl.text).trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_Message(msg, true));
      _loading = true;
    });
    _scrollDown();

    try {
      final res = await api.chat(
        message: msg,
        conversationId: _conversationId,
        mode: 'onboarding',
      );

      _conversationId ??= res['conversation_id'];

      setState(() {
        _messages.add(_Message(res['content'] ?? '...', false));
        _loading = false;
        if (res['onboarding_complete'] == true) {
          _complete = true;
        }
      });
      _scrollDown();

      if (_complete) {
        // Save onboarding status to storage so splash screen
        // can skip login next time
        await storageService.write(
            key: 'onboarding_completed', value: 'true');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/home');
      }
    } catch (e) {
      setState(() {
        _messages.add(_Message(
            "I had trouble connecting. Please try again! 🔄", false));
        _loading = false;
      });
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

  static const _quickReplies = [
    "I'm employed full-time",
    "I'm freelancing",
    "Currently unemployed",
    "I run a small business",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RiseUp AI',
                    style: AppTextStyles.h4.copyWith(fontSize: 14)),
                Text('Your personal wealth mentor',
                    style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              borderRadius: AppRadius.pill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Online',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.success)),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _complete
                ? 1.0
                : (_messages.length / 20.0).clamp(0, 0.95),
            backgroundColor: AppColors.bgCard,
            valueColor:
                const AlwaysStoppedAnimation(AppColors.primary),
          ),

          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _TypingIndicator();
                final m = _messages[i];
                return _ChatBubble(message: m)
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.2);
              },
            ),
          ),

          if (_messages.length == 1 && !_loading)
            _QuickReplies(replies: _quickReplies, onTap: _send),

          if (_complete)
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.success.withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'Profile complete! Preparing your roadmap...',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.success)),
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.3),

          if (!_complete)
            _ChatInput(
                ctrl: _ctrl, onSend: _send, loading: _loading),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _Message message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
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
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? AppColors.userBubble
                    : AppColors.aiBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft:
                      Radius.circular(message.isUser ? 18 : 4),
                  bottomRight:
                      Radius.circular(message.isUser ? 4 : 18),
                ),
              ),
              child: message.isUser
                  ? Text(message.text, style: AppTextStyles.chatUser)
                  : MarkdownBody(
                      data: message.text,
                      styleSheet: MarkdownStyleSheet(
                        p: AppTextStyles.chatAI,
                        strong: AppTextStyles.chatAI.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                        em: AppTextStyles.chatAI
                            .copyWith(fontStyle: FontStyle.italic),
                        listBullet: AppTextStyles.chatAI,
                        h3: AppTextStyles.h4.copyWith(fontSize: 15),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.aiBubble,
                borderRadius: AppRadius.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                  3,
                  (i) => AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, __) {
                          final phase =
                              (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 2),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(
                                  0.4 +
                                      0.6 *
                                          (phase < 0.5
                                              ? phase * 2
                                              : (1 - phase) * 2)),
                              shape: BoxShape.circle,
                            ),
                          );
                        },
                      )),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReplies extends StatelessWidget {
  final List<String> replies;
  final Function(String) onTap;
  const _QuickReplies(
      {required this.replies, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: replies
            .map((r) => GestureDetector(
                  onTap: () => onTap(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.4)),
                      borderRadius: AppRadius.pill,
                      color: AppColors.primary.withOpacity(0.08),
                    ),
                    child: Text(r,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.primaryLight)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  final TextEditingController ctrl;
  final Function([String?]) onSend;
  final bool loading;
  const _ChatInput(
      {required this.ctrl,
      required this.onSend,
      required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.bgSurface)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: AppTextStyles.body,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type your answer...',
                hintStyle: AppTextStyles.label,
                border: OutlineInputBorder(
                    borderRadius: AppRadius.lg,
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: AppColors.bgSurface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onSubmitted: loading ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: loading ? null : () => onSend(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: loading
                      ? [AppColors.textMuted, AppColors.textMuted]
                      : [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                loading
                    ? Icons.hourglass_empty_rounded
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
