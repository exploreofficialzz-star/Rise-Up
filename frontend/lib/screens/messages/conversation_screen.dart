import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ConversationScreen extends StatefulWidget {
  final String userId;
  final String name;
  final String avatar;
  final bool isAI;
  const ConversationScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    this.isAI = false,
  });
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _Msg {
  final String text, sender, avatar;
  final bool isMe, isAI;
  final DateTime time;
  String displayText;
  bool isTyping;
  _Msg({required this.text, required this.sender, required this.avatar, required this.isMe, this.isAI = false})
      : time = DateTime.now(), displayText = text, isTyping = false;
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _loading = false;
  bool _aiJoined = false;
  String? _convId;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isAI) {
      _msgs.add(_Msg(
        text: "Hey! 👋 I'm your RiseUp AI mentor. Ask me anything about wealth, hustle, investing or personal growth!",
        sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
      ));
    } else {
      _msgs.add(_Msg(
        text: "Hey! 👋 How's the wealth journey going?",
        sender: widget.name, avatar: widget.avatar, isMe: false,
      ));
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _typeMessage(_Msg msg) {
    msg.isTyping = true;
    msg.displayText = '';
    int i = 0;
    _typingTimer = Timer.periodic(const Duration(milliseconds: 18), (t) {
      if (!mounted) { t.cancel(); return; }
      if (i >= msg.text.length) {
        t.cancel();
        setState(() { msg.isTyping = false; msg.displayText = msg.text; });
        return;
      }
      i++;
      setState(() => msg.displayText = msg.text.substring(0, i));
      if (i % 3 == 0) HapticFeedback.selectionClick();
      _scrollDown();
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _msgs.add(_Msg(text: text, sender: 'You', avatar: '👤', isMe: true));
      _loading = true;
    });
    _scrollDown();

    if (widget.isAI || _aiJoined) {
      // Send to AI
      try {
        final res = await api.chat(message: text, conversationId: _convId, mode: 'general');
        _convId ??= res['conversation_id'];
        if (mounted) {
          final aiMsg = _Msg(
            text: res['content'] ?? '...', sender: 'RiseUp AI',
            avatar: '🤖', isMe: false, isAI: true,
          );
          setState(() { _msgs.add(aiMsg); _loading = false; });
          _typeMessage(aiMsg);
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _msgs.add(_Msg(text: 'Connection issue. Try again! 🔄', sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true));
            _loading = false;
          });
        }
      }
    } else {
      // Simulate peer reply
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        final replies = [
          'That\'s a great point! 💪',
          'Totally agree. Consistency is key.',
          'Have you tried the compound approach?',
          'Let\'s collaborate on this! 🚀',
          'I had the same experience. It works!',
        ];
        final reply = replies[DateTime.now().millisecond % replies.length];
        final msg = _Msg(text: reply, sender: widget.name, avatar: widget.avatar, isMe: false);
        setState(() { _msgs.add(msg); _loading = false; });
        _typeMessage(msg);
      }
    }
  }

  void _inviteAI() {
    setState(() {
      _aiJoined = true;
      _msgs.add(_Msg(
        text: '🤖 **RiseUp AI has joined the conversation!**\n\nHey both! I\'m here to help with any wealth questions, strategies or advice you need. Just ask! 💡',
        sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
      ));
    });
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Row(children: [
          Stack(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(widget.avatar, style: const TextStyle(fontSize: 18))),
            ),
            Positioned(bottom: 0, right: 0, child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle,
                border: Border.all(color: cardColor, width: 1.5),
              ),
            )),
          ]),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(widget.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              if (widget.isAI || _aiJoined) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
            Text(widget.isAI ? 'Always online' : 'Online now',
                style: TextStyle(fontSize: 11, color: AppColors.success)),
          ]),
        ]),
        actions: [
          // AI invite button for peer chats
          if (!widget.isAI && !_aiJoined)
            GestureDetector(
              onTap: _inviteAI,
              child: Container(
                margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, color: AppColors.primary, size: 14),
                  const SizedBox(width: 4),
                  const Text('Invite AI', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          if (_aiJoined)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Text('AI Active', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          IconButton(icon: Icon(Iconsax.call, color: textColor, size: 20), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice calls coming soon 📞'), duration: Duration(seconds: 1)))),
          IconButton(icon: Icon(Iconsax.video, color: textColor, size: 20), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video calls coming soon 🎥'), duration: Duration(seconds: 1)))),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(children: [
        // AI joined banner
        if (_aiJoined && !widget.isAI)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.08),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: AppColors.primary, size: 14),
              const SizedBox(width: 8),
              Text('RiseUp AI is in this conversation', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
            ]),
          ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _msgs.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _msgs.length) return _buildTyping(isDark, surfaceColor);
              return _buildBubble(_msgs[i], isDark, textColor, surfaceColor);
            },
          ),
        ),

        // Input
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            IconButton(icon: Icon(Iconsax.image, color: subColor, size: 22), onPressed: () async {
              final picker = ImagePicker();
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Photo selected ✅'), backgroundColor: AppColors.success, duration: Duration(seconds: 1)),
                );
              }
            }),
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: TextStyle(fontSize: 14, color: textColor),
                maxLines: 4, minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _aiJoined || widget.isAI ? 'Message or ask AI...' : 'Message ${widget.name}...',
                  hintStyle: TextStyle(color: subColor, fontSize: 13),
                  filled: true, fillColor: surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: _loading ? null : (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loading ? null : _send,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _loading ? [Colors.grey.shade400, Colors.grey.shade400] : [AppColors.primary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(_loading ? Icons.hourglass_empty : Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildBubble(_Msg m, bool isDark, Color textColor, Color surfaceColor) {
    final aiBubble = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!m.isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(m.sender, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: m.isAI ? AppColors.primary : Colors.orange)),
                if (m.isAI) ...[const SizedBox(width: 4), const Icon(Icons.auto_awesome, size: 10, color: AppColors.primary)],
              ]),
            ),
          Row(
            mainAxisAlignment: m.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!m.isMe) ...[
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text(m.avatar, style: const TextStyle(fontSize: 14))),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: m.isMe ? AppColors.userBubble : aiBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(m.isMe ? 18 : 4),
                      bottomRight: Radius.circular(m.isMe ? 4 : 18),
                    ),
                  ),
                  child: m.isMe || !m.isAI
                      ? Text(m.displayText, style: TextStyle(color: m.isMe ? Colors.white : textColor, fontSize: 14, height: 1.5))
                      : MarkdownBody(
                          data: m.displayText,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: isDark ? const Color(0xFFE8E8F0) : Colors.black87, fontSize: 14, height: 1.5),
                            strong: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryLight),
                          ),
                        ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 40, right: 4),
            child: Text(
              '${m.time.hour}:${m.time.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white30 : Colors.black26),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildTyping(bool isDark, Color surfaceColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), shape: BoxShape.circle), child: const Center(child: Text('💬', style: TextStyle(fontSize: 14)))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: isDark ? AppColors.aiBubble : surfaceColor, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) =>
            Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
              .animate(onPlay: (c) => c.repeat()).fadeIn(delay: Duration(milliseconds: i * 200)).then().fadeOut()
          )),
        ),
      ]),
    );
  }
}
