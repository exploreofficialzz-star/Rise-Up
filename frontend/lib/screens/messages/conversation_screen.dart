// frontend/lib/screens/messages/conversation_screen.dart
// Fixed:
//  1. QUOTA RESET BUG: local SharedPreferences is source-of-truth for daily counts.
//     Remote API only used to get premium status + take max(local, remote).
//     Date-based daily reset so counts correctly clear at midnight.
//  2. postContext + postAuthor params: when arriving from "Chat Privately",
//     AI mentor auto-sends a contextual opening message.
//  3. Back navigation works via context.pop() (caller uses context.push).
//  4. DM vs AI message routing fixed: uses @ai prefix to trigger AI in mixed chats.
//  5. Invite AI now calls backend endpoint to persist AI participation.

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

// ─────────────────────────────────────────────────────────────────────────────
// Freemium constants (mirror backend)
// ─────────────────────────────────────────────────────────────────────────────
const int      _kFreeMessages = 3;
const int      _kMaxAdsPerDay = 5;
const Duration _kWindowDur    = Duration(hours: 4);

// FIX: Use SharedPreferences (survives app close/restart on Android).
// Previously used storageService which on some devices loses data between sessions.
// FIX: Single shared key so home feed AI requests and DM AI messages
// count against the SAME daily quota. Previously home_screen used
// 'home_ai_quota_v1' (pipe format) and conversation_screen used
// 'riseup_ai_chat_quota_v3' (JSON) — users got 3 free in each place.
const String _kQuotaPrefsKey = 'riseup_ai_quota_v1';

// ─────────────────────────────────────────────────────────────────────────────
// Message model
// ─────────────────────────────────────────────────────────────────────────────
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
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  final String  userId;        // conversation UUID or "ai"
  final String  name;
  final String  avatar;
  final bool    isAI;
  // FIX: Added for "Chat Privately" flow from home_screen.
  // When set, AI mentor auto-sends a contextual opening about the post.
  final String? postContext;
  final String? postAuthor;

  const ConversationScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    this.isAI        = false,
    this.postContext  = null,
    this.postAuthor   = null,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _textCtrl = TextEditingController();
  final _scroll   = ScrollController();

  final List<_Msg> _msgs = [];
  bool   _historyLoaded = false;
  bool   _aiResponding  = false;
  bool   _dmSending     = false;
  bool   _aiJoined      = false;
  String? _aiConvId;

  Timer? _typingTimer;
  Timer? _pollTimer;
  String? _lastPollTime;

  // ── Quota state ────────────────────────────────────────────────────────────
  // FIX: Map includes 'date' field for daily reset detection.
  Map<String, dynamic> _quota = {
    'free_used':      0,
    'ads_today':      0,
    'window_expires': null,
    'is_premium':     false,
    'date':           '',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadQuota().then((_) => _loadHistory());
    if (!widget.isAI && widget.userId != 'ai') _startPolling();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUOTA — LOCAL-FIRST, DATE-BASED DAILY RESET
  // ─────────────────────────────────────────────────────────────────────────
  // FIX: The previous implementation called api.getAIQuota() first and
  // overwrote local data with whatever the server returned (often free_used: 0).
  // This caused the quota to reset every time the app was reopened.
  //
  // New approach:
  //  Step 1 — Load from SharedPreferences. If date == today, restore counts.
  //           If date != today (new day), counts naturally reset to defaults.
  //  Step 2 — Sync with remote to get premium status and unlock windows.
  //           Take MAX(local, remote) for free_used so neither source can
  //           reset the other.
  Future<void> _loadQuota() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Step 1: local SharedPreferences — same key + JSON format as home_screen.
    // This is instant (SharedPreferences caches in memory after first load)
    // so there is no "3 left" flash on widget rebuild.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kQuotaPrefsKey);
      if (raw != null) {
        final local = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (local['date'] == today) {
          if (mounted) {
            setState(() {
              _quota['free_used']      = local['used']    as int?    ?? 0;
              _quota['ads_today']      = local['ads']     as int?    ?? 0;
              final lockStr            = local['lockout'] as String?;
              _quota['window_expires'] = lockStr;
            });
          }
        }
        // Different day → defaults stay (free_used = 0 = correct new day reset)
      }
    } catch (_) {}

    // Step 2: sync remote (premium status + server-side unlock windows).
    // MAX(local, remote) for free_used prevents the server returning 0
    // from overwriting our locally-tracked usage.
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
    } catch (_) {
      // Local quota is still valid — continue with it
    }
  }

  Future<void> _saveQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      // Write in the SAME JSON format as home_screen so both screens
      // always read each other's writes correctly.
      await prefs.setString(_kQuotaPrefsKey, jsonEncode({
        'date':    today,
        'used':    _quota['free_used']      ?? 0,
        'ads':     _quota['ads_today']      ?? 0,
        'lockout': _quota['window_expires'],
      }));
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
      // Window expired — clear it
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

  // ─────────────────────────────────────────────────────────────────────────
  // History loading
  // ─────────────────────────────────────────────────────────────────────────
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
                final isAI = m['role'] == 'assistant' || m['sender_type'] == 'ai';
                _msgs.add(_Msg(
                  id:      m['id']?.toString(),
                  content: m['content']?.toString() ?? '',
                  sender:  isAI ? 'RiseUp AI' : 'You',
                  avatar:  isAI ? '🤖' : '👤',
                  isMe:    !isAI, isAI: isAI,
                  time:    DateTime.tryParse(m['created_at']?.toString() ?? ''),
                ));
              }
            });
          }
        }

        // Default greeting if no history
        if (_msgs.isEmpty) {
          _msgs.add(_Msg(
            content: "Hey! 👋 I'm your RiseUp AI mentor. Ask me anything about "
                     "wealth-building, side hustles, investing or personal growth!",
            sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
          ));
        }

        // FIX: If arriving from "Chat Privately" on a post, auto-send a
        // context message so the mentor immediately has the post to discuss.
        if (widget.postContext != null && widget.postContext!.isNotEmpty) {
          if (mounted) {
            setState(() => _historyLoaded = true);
            _scrollDown(jump: true);
          }
          final author  = widget.postAuthor?.isNotEmpty == true
              ? widget.postAuthor! : 'a community member';
          final context = widget.postContext!;
          // Auto-send without consuming quota (this is the entry context)
          await _sendAI(
            'I want to discuss a post from $author: "$context"\n\n'
            'Give me a quick wealth insight or action tip about this.',
            adUnlocked: false,
            isContextMessage: true,
          );
          return;
        }
      } else {
        // Peer DM conversation
        if (widget.userId.isEmpty) return;
        final msgs = await api.getDMMessages(widget.userId);
        if (mounted && msgs.isNotEmpty) {
          final myId = await api.getUserId() ?? '';
          setState(() {
            for (final m in msgs) {
              final senderId = m['sender_id']?.toString() ?? '';
              final isMe     = senderId == myId;
              final profile  = m['profiles'] as Map? ?? {};
              _msgs.add(_Msg(
                id:      m['id']?.toString(),
                content: m['content']?.toString() ?? '',
                sender:  isMe ? 'You' : (profile['full_name']?.toString() ?? widget.name),
                avatar:  isMe ? '👤' : (profile['avatar_url']?.toString() ?? widget.avatar),
                isMe:    isMe,
                time:    DateTime.tryParse(m['created_at']?.toString() ?? ''),
              ));
            }
          });
          if (_msgs.isNotEmpty) {
            _lastPollTime = msgs.last['created_at']?.toString();
          }
        }
        // Check if AI is already in this conversation
        _checkAIJoined();
      }
    } catch (_) {
      // Non-fatal — show empty state
    } finally {
      if (mounted) setState(() => _historyLoaded = true);
      _scrollDown(jump: true);
    }
  }

  // Check if AI has been invited to this DM
  Future<void> _checkAIJoined() async {
    try {
      final result = await api.checkAIInConversation(widget.userId);
      if (mounted && result['ai_joined'] == true) {
        setState(() => _aiJoined = true);
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling (peer DMs — every 4 seconds)
  // ─────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_historyLoaded || widget.userId.isEmpty || widget.userId == 'ai') return;
    try {
      final newMsgs = await api.getDMMessages(
          widget.userId, since: _lastPollTime);
      if (!mounted || newMsgs.isEmpty) return;
      final myId = await api.getUserId() ?? '';
      setState(() {
        for (final m in newMsgs) {
          final id       = m['id']?.toString() ?? '';
          final senderId = m['sender_id']?.toString() ?? '';
          final isMe     = senderId == myId;
          if (_msgs.any((msg) => msg.id == id)) continue;
          final profile = m['profiles'] as Map? ?? {};
          _msgs.add(_Msg(
            id:      id,
            content: m['content']?.toString() ?? '',
            sender:  isMe ? 'You' : (profile['full_name']?.toString() ?? widget.name),
            avatar:  isMe ? '👤' : (profile['avatar_url']?.toString() ?? widget.avatar),
            isMe:    isMe,
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

  // ─────────────────────────────────────────────────────────────────────────
  // Sending
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    
    // FIX: Route messages correctly based on context and prefix
    if (widget.isAI || widget.userId == 'ai') {
      // Pure AI conversation mode
      await _trySendAI(text);
    } else if (_aiJoined && text.startsWith('@ai ')) {
      // DM with AI present - @ai prefix triggers AI response
      final aiText = text.substring(4).trim();
      if (aiText.isNotEmpty) {
        // First send the @ai message as regular DM for visibility
        await _sendDM(text);
        // Then get AI response
        await _trySendAI(aiText);
      }
    } else {
      // Regular user-to-user DM
      await _sendDM(text);
    }
  }

  Future<void> _trySendAI(String text) async {
    final result = _checkAIQuota();
    if (result == _QuotaResult.showAdGate) { await _showAdGate(text); return; }
    if (result == _QuotaResult.dailyLimit) { _showDailyLimit(); return; }
    await _sendAI(text, adUnlocked: false);
  }

  Future<void> _sendAI(String text, {
    bool adUnlocked       = false,
    bool isContextMessage = false,  // FIX: context messages don't count against quota
  }) async {
    _textCtrl.clear();
    setState(() {
      _msgs.add(_Msg(content: text, sender: 'You', avatar: '👤', isMe: true));
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
        res = await api.sendAIMessageInDM(
            widget.userId, text, adUnlocked: adUnlocked);
      }

      final aiContent = (res['content'] ?? 'I\'m here to help! 💡').toString();

      // Update quota from response (remote may have more accurate window data)
      if (res['quota'] != null) {
        final q = res['quota'] as Map;
        final remoteUsed = q['free_used'] as int? ?? 0;
        final localUsed  = _freeUsed;
        setState(() {
          _quota['free_used']      = max(localUsed, remoteUsed);
          _quota['window_expires'] = q['window_expires'] ?? _quota['window_expires'];
          _quota['is_premium']     = q['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      } else if (!_isPremium && !_inUnlockedWindow && !isContextMessage) {
        // Increment local count only for real user-initiated messages
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
    _msgs.add(_Msg(content: msg, sender: 'RiseUp AI',
        avatar: '🤖', isMe: false, isAI: true));
    setState(() {});
  }

  Future<void> _sendDM(String text) async {
    _textCtrl.clear();
    final optimisticId = 'opt_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _msgs.add(_Msg(id: optimisticId, content: text,
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
          _msgs.removeWhere((m) => m.id == optimisticId);
          _dmSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send. Check your connection.'),
          backgroundColor: AppColors.error, duration: Duration(seconds: 2),
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AI join in peer DM
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _inviteAI() async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;
    
    try {
      await api.inviteAIToConversation(widget.userId);
      setState(() {
        _aiJoined = true;
        _msgs.add(_Msg(
          content: '🤖 **RiseUp AI has joined the conversation!**\n\n'
                   'Hey! I\'m here to help with wealth questions, strategies or '
                   'anything you need. Just ask! 💡\n\n'
                   'Tip: Use "@ai your question" to ask me anything.',
          sender: 'RiseUp AI', avatar: '🤖', isMe: false, isAI: true,
        ));
      });
      _scrollDown();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not invite AI. Try again.'),
          backgroundColor: AppColors.error, duration: Duration(seconds: 2),
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Typing animation
  // ─────────────────────────────────────────────────────────────────────────
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
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FREEMIUM GATE
  // ─────────────────────────────────────────────────────────────────────────
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
        content: Text('Ad not ready yet. Please try again in a moment.'),
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

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
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

    final bool isSending = _aiResponding || _dmSending;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(isDark, cardColor, borderColor, textColor, subColor, isAIMode),
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
              : _msgs.isEmpty
                  ? _buildEmptyState(isDark, subColor, isAIMode)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  // FIX: Replaces the black screen shown when _msgs is empty.
  // Previously an empty ListView had a transparent background which
  // rendered as solid black in dark mode.
  Widget _buildEmptyState(bool isDark, Color subColor, bool isAIMode) {
    final bg = isDark ? Colors.black : Colors.white;
    if (isAIMode) {
      return Container(
        color: bg,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 40))),
            ),
            const SizedBox(height: 20),
            const Text('RiseUp AI Mentor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(height: 10),
            Text(
              'Your personal wealth coach.\nAsk me anything about income,\ninvesting or financial freedom!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: subColor, height: 1.6),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: const Text('💡 Try: "How do I make my first \$1k online?"',
                  style: TextStyle(fontSize: 12, color: AppColors.primary,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      );
    }
    return Container(
      color: bg,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('👋', style: TextStyle(fontSize: 56,
              color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 16),
          Text('Say hello!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          Text('Start a conversation below',
              style: TextStyle(fontSize: 14, color: subColor)),
          if (_aiJoined) ...[
            const SizedBox(height: 16),
            Text('Use "@ai your message" to ask AI',
                style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ],
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AppBar
  // ─────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
    bool isDark, Color card, Color border, Color text, Color sub, bool isAIMode,
  ) {
    final avatarIsUrl = widget.avatar.startsWith('http');
    final displayName = isAIMode ? 'RiseUp AI' : widget.name;
    final displayAvatar = isAIMode ? '🤖' : widget.avatar;

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
              gradient: (avatarIsUrl && !isAIMode) ? null
                  : const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              image: (avatarIsUrl && !isAIMode)
                  ? DecorationImage(image: NetworkImage(widget.avatar), fit: BoxFit.cover)
                  : null,
              shape: BoxShape.circle,
            ),
            child: (avatarIsUrl && !isAIMode)
                ? null
                : Center(child: Text(displayAvatar,
                    style: const TextStyle(fontSize: 18))),
          ),
          Positioned(bottom: 0, right: 0,
            child: Container(width: 10, height: 10,
              decoration: BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle,
                border: Border.all(color: card, width: 1.5)))),
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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AI', style: TextStyle(
                      color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
            Text(isAIMode ? 'Always online' : 'Online',
                style: const TextStyle(fontSize: 11, color: AppColors.success)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary, size: 13),
                  SizedBox(width: 4),
                  Text('Invite AI', style: TextStyle(color: AppColors.primary,
                      fontSize: 11, fontWeight: FontWeight.w600)),
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
              Text('AI Active', style: TextStyle(color: AppColors.success,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        IconButton(
          icon: Icon(Iconsax.call, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Voice calls coming soon 📞'),
              duration: Duration(seconds: 1))),
        ),
        IconButton(
          icon: Icon(Iconsax.video, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
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

  // ─────────────────────────────────────────────────────────────────────────
  // Input bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInputBar(
    bool isDark, Color card, Color border, Color text,
    Color sub, Color surf, bool isSending, bool isAIMode,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: card, border: Border(top: BorderSide(color: border))),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(children: [
        IconButton(
          icon: Icon(Iconsax.image, color: sub, size: 22),
          onPressed: () async {
            final file = await ImagePicker().pickImage(source: ImageSource.gallery);
            if (file != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Photo selected ✅ — media upload coming soon'),
                backgroundColor: AppColors.success, duration: Duration(seconds: 2),
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
              hintText: isAIMode 
                  ? 'Ask your wealth mentor...'
                  : _aiJoined 
                      ? 'Message @ai or ${widget.name}...'
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
              gradient: LinearGradient(colors: isSending
                  ? [Colors.grey.shade500, Colors.grey.shade500]
                  : [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: isSending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message bubble
  // ─────────────────────────────────────────────────────────────────────────
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
                  const Icon(Icons.auto_awesome, size: 10, color: AppColors.primary),
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
                            image: NetworkImage(m.avatar), fit: BoxFit.cover)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: avatarIsUrl ? null : Center(
                      child: Text(m.avatar,
                          style: const TextStyle(fontSize: 14))),
                ),
                const SizedBox(width: 8),
              ],

              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
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
                                  ? const Color(0xFFE8E8F0) : Colors.black87,
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
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.08, curve: Curves.easeOut);
  }

  Widget _buildTypingIndicator(bool isDark, Color surfColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateExpiry());
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
              fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AdGateSheet extends StatelessWidget {
  final int freeUsed, adsToday, maxAds, windowHours;
  const _AdGateSheet({required this.freeUsed, required this.adsToday,
      required this.maxAds, required this.windowHours});

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? AppColors.bgCard : Colors.white;
    final text      = isDark ? Colors.white : Colors.black87;
    final sub       = isDark ? Colors.white60 : Colors.black54;
    final remaining = maxAds - adsToday;

    return Container(
      decoration: BoxDecoration(color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
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
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 36)))),
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
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () { Navigator.pop(context, false); context.go('/premium'); },
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: const Text('Go Premium — Unlimited AI'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: const BorderSide(color: AppColors.gold),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
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
          "You've used all your free AI unlocks for today.\nYour limit resets at midnight UTC.",
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('Resets in', style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 6),
            Text(_countdown, style: TextStyle(fontSize: 32,
                fontWeight: FontWeight.w800, color: text,
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
              backgroundColor: AppColors.gold, foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Come back later', style: TextStyle(color: sub, fontSize: 13)),
        ),
      ]),
    );
  }
}
