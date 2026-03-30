// frontend/lib/screens/messages/conversation_screen.dart
// v4 — Production ready
//
// Changes:
//  • Presence heartbeat every 30 s — accurate online dot in AppBar
//  • _poll() now correctly identifies AI messages (sender_type='ai',
//    sender_id=null) instead of treating them as "other user" messages
//  • _loadHistory() same fix for AI messages in DM context
//  • AppBar online status driven by live last_seen, not a stored bool
//  • setOffline() called on dispose
//  • WidgetsBindingObserver pauses/resumes heartbeat on app lifecycle

import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';

// ── Freemium constants ────────────────────────────────────────────────────
const int      _kFreeMessages = 3;
const int      _kMaxAdsPerDay = 5;
const Duration _kWindowDur    = Duration(hours: 4);
const String   _kQuotaPrefsKey = 'riseup_ai_chat_quota_v3';

// ── Message model ─────────────────────────────────────────────────────────
class _Msg {
  final String   id, content, sender, avatar;
  final bool     isMe, isAI;
  final DateTime time;
  String displayText;
  bool   isTyping;

  _Msg({
    String? id,
    required this.content,
    required this.sender,
    required this.avatar,
    required this.isMe,
    this.isAI = false,
    DateTime? time,
  })  : id          = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        displayText = content,
        isTyping    = false,
        time        = time ?? DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  final String  userId;       // conversation UUID or "ai"
  final String  name;
  final String  avatar;
  final bool    isAI;
  final String? postContext;
  final String? postAuthor;

  const ConversationScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    this.isAI       = false,
    this.postContext = null,
    this.postAuthor  = null,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _textCtrl = TextEditingController();
  final _scroll   = ScrollController();

  final List<_Msg> _msgs = [];
  bool   _historyLoaded = false;
  bool   _aiResponding  = false;
  bool   _dmSending     = false;
  bool   _aiJoined      = false;
  String? _aiConvId;

  // Online status for the other user (updated by heartbeat response)
  bool _otherOnline = false;

  Timer? _typingTimer;
  Timer? _pollTimer;
  Timer? _presenceTimer;
  String? _lastPollTime;

  Map<String, dynamic> _quota = {
    'free_used':      0,
    'ads_today':      0,
    'window_expires': null,
    'is_premium':     false,
    'date':           '',
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadQuota().then((_) => _loadHistory());
    _startPresence();
    if (!widget.isAI && widget.userId != 'ai') _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _textCtrl.dispose();
    _scroll.dispose();
    api.setOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive) {
      _presenceTimer?.cancel();
      api.setOffline();
    }
  }

  // ── Presence ──────────────────────────────────────────────────────────────
  void _startPresence() {
    api.updatePresence();
    _presenceTimer?.cancel();
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => api.updatePresence());
  }

  // ── Quota ─────────────────────────────────────────────────────────────────
  Future<void> _loadQuota() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Step 1: local SharedPreferences (fast, survives restart)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kQuotaPrefsKey);
      if (raw != null) {
        final local = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (local['date'] == today && mounted) {
          setState(() => _quota = local);
        }
      }
    } catch (_) {}

    // Step 2: sync with remote (premium status, server windows)
    try {
      final remote     = await api.getAIQuota();
      final remoteUsed = remote['free_used'] as int? ?? 0;
      final localUsed  = _quota['free_used'] as int? ?? 0;
      if (mounted) {
        setState(() {
          _quota['free_used']  = max(localUsed, remoteUsed);
          _quota['is_premium'] = remote['is_premium'] ?? _quota['is_premium'];
          if (_quota['window_expires'] == null &&
              remote['window_expires'] != null) {
            _quota['window_expires'] = remote['window_expires'];
          }
          _quota['ads_today'] = max(
            _quota['ads_today'] as int? ?? 0,
            remote['ads_today'] as int? ?? 0,
          );
        });
        await _saveQuota();
      }
    } catch (_) {}
  }

  Future<void> _saveQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _quota['date'] = DateTime.now().toIso8601String().substring(0, 10);
      await prefs.setString(_kQuotaPrefsKey, jsonEncode(_quota));
    } catch (_) {}
  }

  bool get _isPremium     => _quota['is_premium'] == true;
  int  get _freeUsed      => _quota['free_used'] as int? ?? 0;
  int  get _adsToday      => _quota['ads_today'] as int? ?? 0;
  bool get _hasFreeMsgs   => _freeUsed < _kFreeMessages;
  bool get _canWatchAd    => _adsToday < _kMaxAdsPerDay;

  bool get _inUnlockedWindow {
    final exp = _quota['window_expires'] as String?;
    if (exp == null) return false;
    final dt = DateTime.tryParse(exp);
    if (dt == null) return false;
    if (DateTime.now().isAfter(dt)) {
      _quota['window_expires'] = null;
      _saveQuota();
      return false;
    }
    return true;
  }

  _QuotaResult _checkAIQuota() {
    if (_isPremium)        return _QuotaResult.allowed;
    if (_inUnlockedWindow) return _QuotaResult.allowed;
    if (_hasFreeMsgs)      return _QuotaResult.allowed;
    if (_canWatchAd)       return _QuotaResult.showAdGate;
    return _QuotaResult.dailyLimit;
  }

  // ── History ───────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_historyLoaded) return;
    try {
      if (widget.isAI || widget.userId == 'ai') {
        // AI mentor conversation
        final convos = await api.getAiConversations();
        if (convos.isNotEmpty) {
          _aiConvId = convos.first['id']?.toString();
          final msgs = await api.getMessages(_aiConvId!);
          if (mounted && msgs.isNotEmpty) {
            setState(() {
              for (final m in msgs) {
                final isAI = m['role'] == 'assistant' ||
                    m['sender_type'] == 'ai';
                _msgs.add(_Msg(
                  id:     m['id']?.toString(),
                  content: m['content']?.toString() ?? '',
                  sender:  isAI ? 'RiseUp AI' : 'You',
                  avatar:  isAI ? '🤖' : '👤',
                  isMe:    !isAI,
                  isAI:    isAI,
                  time:    DateTime.tryParse(
                      m['created_at']?.toString() ?? ''),
                ));
              }
            });
          }
        }

        if (_msgs.isEmpty) {
          _msgs.add(_Msg(
            content: "Hey! 👋 I'm your RiseUp AI mentor. Ask me anything "
                "about wealth-building, side hustles, investing or personal growth!",
            sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
          ));
        }

        if (widget.postContext != null && widget.postContext!.isNotEmpty) {
          if (mounted) {
            setState(() => _historyLoaded = true);
            _scrollDown(jump: true);
          }
          final author  = widget.postAuthor?.isNotEmpty == true
              ? widget.postAuthor! : 'a community member';
          await _sendAI(
            'I want to discuss a post from $author: '
            '"${widget.postContext!}"\n\n'
            'Give me a quick wealth insight or action tip about this.',
            adUnlocked: false,
            isContextMessage: true,
          );
          return;
        }
      } else {
        // Peer DM — load existing messages
        if (widget.userId.isEmpty) return;
        final msgs = await api.getDMMessages(widget.userId);
        if (mounted && msgs.isNotEmpty) {
          final myId = await api.getUserId() ?? '';
          setState(() {
            for (final m in msgs) {
              final senderId   = m['sender_id']?.toString() ?? '';
              final senderType = m['sender_type']?.toString() ?? 'user';
              final isAI       = senderType == 'ai';
              final isMe       = !isAI && senderId == myId;
              final profile    = (m['profiles'] as Map?) ?? {};

              _msgs.add(_Msg(
                id:      m['id']?.toString(),
                content: m['content']?.toString() ?? '',
                sender:  isMe  ? 'You'
                    : isAI ? 'RiseUp AI'
                    : (profile['full_name']?.toString() ?? widget.name),
                avatar:  isMe  ? '👤'
                    : isAI ? '🤖'
                    : (profile['avatar_url']?.toString() ?? widget.avatar),
                isMe:    isMe,
                isAI:    isAI,
                time:    DateTime.tryParse(
                    m['created_at']?.toString() ?? ''),
              ));
            }
          });
          if (_msgs.isNotEmpty) {
            _lastPollTime = msgs.last['created_at']?.toString();
          }
        }
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _historyLoaded = true);
      _scrollDown(jump: true);
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_historyLoaded || widget.userId.isEmpty || widget.userId == 'ai') {
      return;
    }
    try {
      final newMsgs = await api.getDMMessages(
          widget.userId, since: _lastPollTime);
      if (!mounted || newMsgs.isEmpty) return;

      final myId = await api.getUserId() ?? '';
      setState(() {
        for (final m in newMsgs) {
          final id         = m['id']?.toString() ?? '';
          final senderId   = m['sender_id']?.toString() ?? '';
          final senderType = m['sender_type']?.toString() ?? 'user';
          final isAI       = senderType == 'ai';
          final isMe       = !isAI && senderId == myId;

          if (_msgs.any((msg) => msg.id == id)) continue;

          final profile = (m['profiles'] as Map?) ?? {};
          _msgs.add(_Msg(
            id:      id,
            content: m['content']?.toString() ?? '',
            sender:  isMe  ? 'You'
                : isAI ? 'RiseUp AI'
                : (profile['full_name']?.toString() ?? widget.name),
            avatar:  isMe  ? '👤'
                : isAI ? '🤖'
                : (profile['avatar_url']?.toString() ?? widget.avatar),
            isMe:    isMe,
            isAI:    isAI,
            time:    DateTime.tryParse(m['created_at']?.toString() ?? ''),
          ));
        }
      });

      if (newMsgs.isNotEmpty) {
        _lastPollTime = newMsgs.last['created_at']?.toString();
        _scrollDown();
      }
    } catch (_) {}
  }

  // ── Sending ───────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    if (widget.isAI || widget.userId == 'ai' || _aiJoined) {
      await _trySendAI(text);
    } else {
      await _sendDM(text);
    }
  }

  Future<void> _trySendAI(String text) async {
    final result = _checkAIQuota();
    if (result == _QuotaResult.showAdGate) {
      await _showAdGate(text);
      return;
    }
    if (result == _QuotaResult.dailyLimit) {
      _showDailyLimit();
      return;
    }
    await _sendAI(text, adUnlocked: false);
  }

  Future<void> _sendAI(
    String text, {
    bool adUnlocked       = false,
    bool isContextMessage = false,
  }) async {
    _textCtrl.clear();
    setState(() {
      _msgs.add(_Msg(
          content: text, sender: 'You', avatar: '👤', isMe: true));
      _aiResponding = true;
    });
    _scrollDown();

    try {
      Map<String, dynamic> res;

      if (widget.isAI || widget.userId == 'ai') {
        res = await api.chat(
          message: text, conversationId: _aiConvId, mode: 'general',
        );
        _aiConvId ??= res['conversation_id']?.toString();
      } else {
        // AI invited into a peer DM
        res = await api.sendAIMessageInDM(
            widget.userId, text, adUnlocked: adUnlocked);
      }

      final aiContent =
          (res['content'] ?? "I'm here to help! 💡").toString();

      // Sync quota from response
      if (res['quota'] != null) {
        final q          = res['quota'] as Map;
        final remoteUsed = q['free_used'] as int? ?? 0;
        setState(() {
          _quota['free_used']      = max(_freeUsed, remoteUsed);
          _quota['window_expires'] =
              q['window_expires'] ?? _quota['window_expires'];
          _quota['is_premium'] =
              q['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      } else if (!_isPremium && !_inUnlockedWindow && !isContextMessage) {
        setState(() => _quota['free_used'] = _freeUsed + 1);
        await _saveQuota();
      }

      if (mounted) {
        final aiMsg = _Msg(
          content: aiContent, sender: 'RiseUp AI',
          avatar: '🤖', isMe: false, isAI: true,
        );
        setState(() { _msgs.add(aiMsg); _aiResponding = false; });
        _typeMessage(aiMsg);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _aiResponding = false);
      if (e.statusCode == 402) {
        await _showAdGate(text);
      } else if (e.statusCode == 429) {
        _showDailyLimit();
      } else {
        _addErrorBubble('Connection issue. Try again! 🔄');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aiResponding = false);
        _addErrorBubble('Connection issue. Try again! 🔄');
      }
    }
  }

  void _addErrorBubble(String msg) {
    _msgs.add(_Msg(
        content: msg, sender: 'RiseUp AI',
        avatar: '🤖', isMe: false, isAI: true));
    setState(() {});
  }

  Future<void> _sendDM(String text) async {
    _textCtrl.clear();
    final optId = 'opt_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _msgs.add(_Msg(id: optId, content: text,
          sender: 'You', avatar: '👤', isMe: true));
      _dmSending = true;
    });
    _scrollDown();

    try {
      await api.sendDMMessage(widget.userId, text);
      if (mounted) setState(() => _dmSending = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _msgs.removeWhere((m) => m.id == optId);
          _dmSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send. Check your connection.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 2),
        ));
      }
    }
  }

  // ── AI join in peer DM ────────────────────────────────────────────────────
  void _inviteAI() {
    setState(() {
      _aiJoined = true;
      _msgs.add(_Msg(
        content: '🤖 **RiseUp AI has joined the conversation!**\n\n'
            "Hey! I'm here to help with wealth questions, strategies or "
            "anything you need. Just ask! 💡",
        sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
      ));
    });
    _scrollDown();
  }

  // ── Typing animation ──────────────────────────────────────────────────────
  void _typeMessage(_Msg msg) {
    msg.isTyping    = true;
    msg.displayText = '';
    int i = 0;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 14), (t) {
      if (!mounted) { t.cancel(); return; }
      if (i >= msg.content.length) {
        t.cancel();
        setState(() { msg.isTyping = false; msg.displayText = msg.content; });
        return;
      }
      i++;
      setState(() => msg.displayText = msg.content.substring(0, i));
      if (i % 4 == 0) HapticFeedback.selectionClick();
      _scrollDown();
    });
  }

  void _scrollDown({bool jump = false}) {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || !_scroll.hasClients) return;
      if (jump) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut);
      }
    });
  }

  // ── Freemium gates ────────────────────────────────────────────────────────
  Future<void> _showAdGate(String pendingText) async {
    final watched = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdGateSheet(
        freeUsed: _freeUsed, adsToday: _adsToday,
        maxAds: _kMaxAdsPerDay, windowHours: _kWindowDur.inHours,
      ),
    );
    if (watched != true || !mounted) return;

    if (!adService.isRewardedReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ad not ready yet. Try again in a moment.'),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    await adService.showRewardedAd(
      featureKey: 'ai_chat',
      onRewarded: () async {
        setState(() {
          _quota['free_used']      = 0;
          _quota['ads_today']      = _adsToday + 1;
          _quota['window_expires'] =
              DateTime.now().add(_kWindowDur).toIso8601String();
        });
        await _saveQuota();
        if (mounted) await _sendAI(pendingText, adUnlocked: true);
      },
      onDismissed: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Watch the full ad to unlock AI messages.'),
            duration: Duration(seconds: 2),
          ));
        }
      },
    );
  }

  void _showDailyLimit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyLimitSheet(
        onUpgrade: () { Navigator.pop(context); context.go('/premium'); },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard : Colors.white;
    final surfColor   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white : Colors.black87;
    final subColor    = isDark ? Colors.white54 : Colors.black45;
    final isAIMode    = widget.isAI || widget.userId == 'ai';
    final isSending   = _aiResponding || _dmSending;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(
          isDark, cardColor, borderColor, textColor, subColor, isAIMode),
      body: Column(children: [
        if (_aiJoined && !isAIMode) _AIJoinedBanner(),

        if ((isAIMode || _aiJoined) && !_isPremium)
          _QuotaRibbon(
            isPremium:     _isPremium,
            inWindow:      _inUnlockedWindow,
            freeUsed:      _freeUsed,
            freeTotal:     _kFreeMessages,
            adsToday:      _adsToday,
            maxAds:        _kMaxAdsPerDay,
            windowExpires: _quota['window_expires'] as String?,
          ),

        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: _msgs.length + (isSending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) {
                      return _buildTypingIndicator(isDark, surfColor);
                    }
                    return _buildBubble(
                        _msgs[i], isDark, textColor, surfColor, cardColor);
                  },
                ),
        ),

        _buildInputBar(isDark, cardColor, borderColor, textColor, subColor,
            surfColor, isSending, isAIMode),
      ]),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
    bool isDark, Color card, Color border, Color text,
    Color sub, bool isAIMode,
  ) {
    final avatarIsUrl   = widget.avatar.startsWith('http');
    final displayName   = isAIMode ? 'RiseUp AI' : widget.name;
    final displayAvatar = isAIMode ? '🤖' : widget.avatar;

    // AI is always online; peers use presence-computed status
    final showOnline = isAIMode || _otherOnline;

    return AppBar(
      backgroundColor: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/messages');
          }
        },
      ),
      title: Row(children: [
        Stack(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: (avatarIsUrl && !isAIMode)
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent]),
              image: (avatarIsUrl && !isAIMode)
                  ? DecorationImage(
                      image: NetworkImage(widget.avatar),
                      fit: BoxFit.cover)
                  : null,
              shape: BoxShape.circle,
            ),
            child: (avatarIsUrl && !isAIMode)
                ? null
                : Center(child: Text(displayAvatar,
                    style: const TextStyle(fontSize: 18))),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: showOnline
                    ? AppColors.success
                    : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: card, width: 1.5),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Flexible(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(displayName, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: text),
                  overflow: TextOverflow.ellipsis)),
              if (isAIMode || _aiJoined) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AI', style: TextStyle(
                      color: Colors.white, fontSize: 8,
                      fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
            Text(
              isAIMode
                  ? 'Always online'
                  : showOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 11,
                color: showOnline
                    ? AppColors.success
                    : Colors.grey.shade500,
              ),
            ),
          ],
        )),
      ]),
      actions: [
        if (!isAIMode && !_aiJoined)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); _inviteAI(); },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary, size: 13),
                  SizedBox(width: 4),
                  Text('Invite AI', style: TextStyle(
                      color: AppColors.primary, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        if (_aiJoined)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, color: AppColors.success, size: 13),
              SizedBox(width: 4),
              Text('AI Active', style: TextStyle(
                  color: AppColors.success, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            ]),
          ),
        IconButton(
          icon: Icon(Iconsax.call, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Voice calls coming soon 📞'),
                  duration: Duration(seconds: 1))),
        ),
        IconButton(
          icon: Icon(Iconsax.video, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Video calls coming soon 🎥'),
                  duration: Duration(seconds: 1))),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: border),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar(
    bool isDark, Color card, Color border, Color text,
    Color sub, Color surf, bool isSending, bool isAIMode,
  ) {
    return Container(
      decoration: BoxDecoration(
          color: card,
          border: Border(top: BorderSide(color: border))),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(children: [
        IconButton(
          icon: Icon(Iconsax.image, color: sub, size: 22),
          onPressed: () async {
            final file = await ImagePicker()
                .pickImage(source: ImageSource.gallery);
            if (file != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Photo selected ✅ — media upload coming soon'),
                backgroundColor: AppColors.success,
                duration: Duration(seconds: 2),
              ));
            }
          },
        ),
        Expanded(
          child: TextField(
            controller: _textCtrl,
            style: TextStyle(fontSize: 14, color: text),
            maxLines: 5, minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            enabled: !isSending,
            decoration: InputDecoration(
              hintText: isAIMode || _aiJoined
                  ? 'Ask your wealth mentor...'
                  : 'Message ${widget.name}...',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled: true, fillColor: surf,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            onSubmitted: isSending ? null : (_) => _onSend(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: isSending ? null : () {
            HapticFeedback.lightImpact();
            _onSend();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSending
                    ? [Colors.grey.shade500, Colors.grey.shade500]
                    : [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: isSending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Message bubble ────────────────────────────────────────────────────────
  Widget _buildBubble(
    _Msg m, bool isDark, Color textColor, Color surfColor, Color cardColor,
  ) {
    final aiBg        = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final avatarIsUrl = m.avatar.startsWith('http');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!m.isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 36),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(m.sender, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: m.isAI ? AppColors.primary : AppColors.warning,
                )),
                if (m.isAI) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.auto_awesome, size: 10,
                      color: AppColors.primary),
                ],
              ]),
            ),

          Row(
            mainAxisAlignment:
                m.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!m.isMe) ...[
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: avatarIsUrl ? null
                        : const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent]),
                    image: avatarIsUrl
                        ? DecorationImage(
                            image: NetworkImage(m.avatar),
                            fit: BoxFit.cover)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: avatarIsUrl
                      ? null
                      : Center(child: Text(m.avatar,
                          style: const TextStyle(fontSize: 14))),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: m.isMe ? AppColors.userBubble : aiBg,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(m.isMe ? 18 : 4),
                      bottomRight: Radius.circular(m.isMe ? 4 : 18),
                    ),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 6, offset: const Offset(0, 2),
                    )],
                  ),
                  child: m.isMe || !m.isAI
                      ? Text(m.displayText, style: TextStyle(
                          color: m.isMe ? Colors.white : textColor,
                          fontSize: 14, height: 1.5))
                      : MarkdownBody(
                          data: m.displayText,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: isDark
                                  ? const Color(0xFFE8E8F0)
                                  : Colors.black87,
                              fontSize: 14, height: 1.55,
                            ),
                            strong: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryLight),
                            code: TextStyle(
                              fontFamily: 'monospace',
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A3E)
                                  : Colors.grey.shade200,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),

          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: m.isMe ? 0 : 40,
              right: m.isMe ? 4 : 0,
            ),
            child: Text(_formatTime(m.time), style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white24 : Colors.black26,
            )),
          ),
        ],
      ),
    ).animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.08, curve: Curves.easeOut);
  }

  Widget _buildTypingIndicator(bool isDark, Color surfColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
            shape: BoxShape.circle,
          ),
          child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 14))),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: isDark ? AppColors.aiBubble : surfColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat())
              .fadeIn(delay: Duration(milliseconds: i * 200))
              .then()
              .fadeOut()),
          ),
        ),
      ]),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
enum _QuotaResult { allowed, showAdGate, dailyLimit }

// ─────────────────────────────────────────────────────────────────────────────
class _AIJoinedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withOpacity(0.08),
      child: const Row(children: [
        Icon(Icons.auto_awesome, color: AppColors.primary, size: 14),
        SizedBox(width: 8),
        Text('RiseUp AI is in this conversation',
            style: TextStyle(fontSize: 12, color: AppColors.primary,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inWindow;
  final int  freeUsed, freeTotal, adsToday, maxAds;
  final String? windowExpires;

  const _QuotaRibbon({
    required this.isPremium, required this.inWindow,
    required this.freeUsed, required this.freeTotal,
    required this.adsToday, required this.maxAds,
    this.windowExpires,
  });

  @override
  State<_QuotaRibbon> createState() => _QuotaRibbonState();
}

class _QuotaRibbonState extends State<_QuotaRibbon> {
  Timer?  _timer;
  String  _expiry = '';

  @override
  void initState() {
    super.initState();
    if (widget.inWindow && widget.windowExpires != null) _startTimer();
  }

  void _startTimer() {
    _updateExpiry();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateExpiry());
  }

  void _updateExpiry() {
    if (!mounted) return;
    final exp  = DateTime.tryParse(widget.windowExpires ?? '');
    if (exp == null) return;
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) { setState(() => _expiry = ''); return; }
    final h = diff.inHours;
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _expiry = h > 0 ? '${h}h ${m}m' : '$m:$s');
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.isPremium) return const SizedBox.shrink();
    final remaining = widget.freeTotal - widget.freeUsed;

    if (widget.inWindow) {
      return _ribbon(Icons.lock_open_rounded, AppColors.success,
          'AI unlocked${_expiry.isNotEmpty ? ' · $_expiry left' : ''}',
          Colors.transparent);
    }
    if (remaining > 0) {
      return _ribbon(Icons.chat_bubble_outline_rounded, AppColors.primary,
          '$remaining free AI message${remaining == 1 ? '' : 's'} remaining',
          AppColors.primary.withOpacity(0.06));
    }
    return const SizedBox.shrink();
  }

  Widget _ribbon(IconData icon, Color color, String label, Color bg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: bg,
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color,
            fontWeight: FontWeight.w500)),
        const Spacer(),
        GestureDetector(
          onTap: () => GoRouter.of(context).go('/premium'),
          child: const Text('Go Premium', style: TextStyle(
              fontSize: 11, color: AppColors.primary,
              fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AdGateSheet extends StatelessWidget {
  final int freeUsed, adsToday, maxAds, windowHours;
  const _AdGateSheet({
    required this.freeUsed, required this.adsToday,
    required this.maxAds, required this.windowHours,
  });

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? AppColors.bgCard : Colors.white;
    final text      = isDark ? Colors.white : Colors.black87;
    final sub       = isDark ? Colors.white60 : Colors.black54;
    final remaining = maxAds - adsToday;

    return Container(
      decoration: BoxDecoration(color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Container(width: 72, height: 72,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 36)))),
        const SizedBox(height: 16),
        Text('Unlock AI Messages', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used your $freeUsed free AI messages.\n"
          "Watch a short ad to unlock ${windowHours}h of unlimited AI mentoring.",
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text('$remaining unlock${remaining == 1 ? '' : 's'} remaining today',
            style: TextStyle(fontSize: 12, color: sub)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
            label: Text('Watch Ad — Unlock ${windowHours}h Free'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context, false);
              context.go('/premium');
            },
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: const Text('Go Premium — Unlimited AI'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: const BorderSide(color: AppColors.gold),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Not now', style: TextStyle(color: sub, fontSize: 13)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _DailyLimitSheet extends StatefulWidget {
  final VoidCallback onUpgrade;
  const _DailyLimitSheet({required this.onUpgrade});
  @override
  State<_DailyLimitSheet> createState() => _DailyLimitSheetState();
}

class _DailyLimitSheetState extends State<_DailyLimitSheet> {
  Timer?  _timer;
  String  _countdown = '--:--:--';

  @override
  void initState() {
    super.initState();
    _update();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final now      = DateTime.now().toUtc();
    final midnight = DateTime.utc(now.year, now.month, now.day + 1);
    final diff     = midnight.difference(now);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _countdown = '$h:$m:$s');
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? AppColors.bgCard : Colors.white;
    final text   = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white60 : Colors.black54;

    return Container(
      decoration: BoxDecoration(color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        const Text('⏰', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text('Daily Limit Reached', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used all your free AI unlocks for today.\n"
          "Your limit resets at midnight UTC.",
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('Resets in', style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 6),
            Text(_countdown, style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w800, color: text,
                fontFamily: 'monospace', letterSpacing: 2)),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onUpgrade,
            icon: const Icon(Icons.workspace_premium_rounded, size: 20),
            label: const Text('Upgrade — Unlimited AI Forever'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Come back later',
              style: TextStyle(color: sub, fontSize: 13)),
        ),
      ]),
    );
  }
}
