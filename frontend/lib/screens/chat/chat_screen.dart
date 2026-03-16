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
  const ChatScreen({super.key, this.conversationId, this.mode = 'general'});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  final String text; final bool isUser; final String? model;
  _Msg(this.text, this.isUser, {this.model});
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String? _convId;
  bool _loading = false;
  String _currentModel = 'groq';

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
    if (_convId != null) _loadHistory();
    else _addWelcome();
  }

  void _addWelcome() {
    _msgs.add(_Msg(
      "Hey! 👋 I'm your RiseUp AI mentor.\n\nI'm here to help you **earn more, learn faster, and build real wealth**.\n\nWhat would you like to work on today?",
      false,
    ));
  }

  Future<void> _loadHistory() async {
    final msgs = await api.getMessages(_convId!);
    setState(() {
      for (final m in msgs) {
        if (m['role'] != 'system') {
          _msgs.add(_Msg(m['content'], m['role'] == 'user', model: m['ai_model']));
        }
      }
    });
    _scrollDown();
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _ctrl.text).trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() { _msgs.add(_Msg(msg, true)); _loading = true; });
    _scrollDown();

    try {
      final res = await api.chat(
        message: msg,
        conversationId: _convId,
        mode: widget.mode,
      );
      _convId ??= res['conversation_id'];
      setState(() {
        _msgs.add(_Msg(res['content'] ?? '...', false, model: res['ai_model']));
        _currentModel = res['ai_model'] ?? _currentModel;
        _loading = false;
      });
      _scrollDown();
    } catch (_) {
      setState(() {
        _msgs.add(_Msg('Connection issue. Try again! 🔄', false));
        _loading = false;
      });
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RiseUp AI', style: AppTextStyles.h4.copyWith(fontSize: 14)),
                Text(_modelLabel(_currentModel), style: AppTextStyles.caption.copyWith(color: AppColors.success)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.note_add, size: 20),
            onPressed: () {
              setState(() { _msgs.clear(); _convId = null; _addWelcome(); });
            },
            tooltip: 'New Chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _msgs.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _msgs.length) return _buildTyping();
                final m = _msgs[i];
                return _buildBubble(m, i);
              },
            ),
          ),

          // Quick actions (when empty)
          if (_msgs.length == 1 && !_loading)
            _QuickActions(actions: _quickActions, onTap: _send),

          _InputBar(ctrl: _ctrl, onSend: _send, loading: _loading),
        ],
      ),
    );
  }

  String _modelLabel(String model) {
    switch (model) {
      case 'groq': return '⚡ Groq (Llama 3.1) · Free';
      case 'gemini': return '✨ Gemini Flash · Free';
      case 'cohere': return '🤖 Cohere Command R · Free';
      case 'openai': return '🧠 GPT-4o Mini';
      case 'anthropic': return '🎭 Claude';
      default: return '🤖 AI Active';
    }
  }

  Widget _buildBubble(_Msg m, int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: m.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: m.isUser ? AppColors.userBubble : AppColors.aiBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                  bottomRight: Radius.circular(m.isUser ? 4 : 18),
                ),
              ),
              child: m.isUser
                  ? Text(m.text, style: AppTextStyles.chatUser)
                  : MarkdownBody(
                      data: m.text,
                      styleSheet: MarkdownStyleSheet(
                        p: AppTextStyles.chatAI,
                        strong: AppTextStyles.chatAI.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryLight),
                        code: AppTextStyles.body.copyWith(backgroundColor: AppColors.bgDark, fontFamily: 'monospace'),
                        blockquote: AppTextStyles.chatAI.copyWith(color: AppColors.textSecondary),
                        h3: AppTextStyles.h4.copyWith(fontSize: 15),
                        h4: AppTextStyles.h4.copyWith(fontSize: 14),
                        listBullet: AppTextStyles.chatAI,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.15);
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.aiBubble, borderRadius: AppRadius.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6, height: 6,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ).animate(onPlay: (c) => c.repeat()).fadeIn(delay: Duration(milliseconds: i * 200)).then().fadeOut()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final List<(String, String)> actions;
  final Function(String) onTap;
  const _QuickActions({required this.actions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: actions.map((a) => GestureDetector(
          onTap: () => onTap(a.$2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.bgSurface),
            ),
            child: Text(a.$1, style: AppTextStyles.bodySmall),
          ),
        )).toList(),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final Function([String?]) onSend;
  final bool loading;
  const _InputBar({required this.ctrl, required this.onSend, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
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
              maxLines: 4, minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask your AI mentor...',
                hintStyle: AppTextStyles.label,
                border: OutlineInputBorder(borderRadius: AppRadius.lg, borderSide: BorderSide.none),
                filled: true, fillColor: AppColors.bgSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: loading ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: loading ? null : () => onSend(),
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: loading ? [AppColors.textMuted, AppColors.textMuted] : [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(loading ? Icons.hourglass_empty : Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
