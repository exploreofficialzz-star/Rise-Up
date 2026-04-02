// frontend/lib/screens/messages/conversation_screen.dart
// Production v9 — Full fix
//
// Root bugs fixed vs v8:
//  • AI chat history now loads from the messages system (not the old /ai/chat
//    system) — history actually persists across restarts.
//  • AI memory fixed — every send goes through sendAIMessageInDM which passes
//    the last 20 DB messages as context to the AI model.
//  • Duplicate DM messages fixed — optimistic message is replaced with the
//    real DB row (using its real UUID) so the poller never re-adds it.
//  • Polling is unified for both AI-only and peer-DM modes.
//  • _lastPollTime is advanced after every send so the poller doesn't
//    re-fetch messages we already displayed locally.
//  • getOrCreateAIConversation() is called on every open to guarantee
//    _aiConvId always points to a valid messages-system conversation.

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
import '../../services/ad_service.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Freemium constants (mirror backend)
// ─────────────────────────────────────────────────────────────────────────────
const int _kFreeMessages = 3;
const int _kMaxAdsPerDay = 5;
const Duration _kWindowDur = Duration(hours: 4);

/// Shared quota key — same format as home_screen so both screens
/// count against the same daily budget.
const String _kQuotaPrefsKey = 'riseup_ai_quota_v1';

/// Persisted AI conversation ID (messages-system UUID).
const String _kAiConvIdKey = 'riseup_ai_conv_id_v2'; // v2 = messages-system

// ─────────────────────────────────────────────────────────────────────────────
// Internal message model
// ─────────────────────────────────────────────────────────────────────────────
class _Msg {
  final String id;
  final String content;
  final String sender;
  final String avatar;
  final bool isMe;
  final bool isAI;
  final DateTime time;

  /// Mutated during the typing animation only.
  String displayText;
  bool isTyping;

  _Msg({
    String? id,
    required this.content,
    required this.sender,
    required this.avatar,
    required this.isMe,
    this.isAI = false,
    DateTime? time,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        displayText = content,
        isTyping = false,
        time = time ?? DateTime.now();
}

enum _QuotaResult { allowed, showAdGate, dailyLimit }

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  /// For AI-only mode pass 'ai'; for DM mode pass the conversation UUID.
  final String userId;
  final String name;
  final String avatar;
  final bool isAI;

  /// Optional: when arriving from "Chat Privately" on a post, the AI mentor
  /// auto-sends an opening message about the post.
  final String? postContext;
  final String? postAuthor;

  const ConversationScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    this.isAI = false,
    this.postContext,
    this.postAuthor,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];

  bool _historyLoaded = false;
  bool _aiResponding = false;
  bool _dmSending = false;
  bool _aiJoined = false;

  /// Conversation UUID in the messages system.
  /// • AI-only mode  → obtained from getOrCreateAIConversation()
  /// • Peer-DM mode  → widget.userId
  String? _aiConvId;

  /// ISO timestamp of the newest message we've seen — used for incremental polls.
  String? _lastPollTime;

  Timer? _typingTimer;
  Timer? _pollTimer;

  // ── Quota ─────────────────────────────────────────────────────────────────
  Map<String, dynamic> _quota = {
    'free_used': 0,
    'ads_today': 0,
    'window_expires': null,
    'is_premium': false,
    'date': '',
  };

  bool get _isAIMode => widget.isAI || widget.userId == 'ai';

  /// The active conversation ID to pass to poll / send helpers.
  String? get _activeConvId => _isAIMode ? _aiConvId : widget.userId;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadQuota();
    await _loadHistory();
    // Poll for both AI and peer-DM modes — same code path now.
    _startPolling();
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
  // QUOTA — local-first, date-based daily reset
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadQuota() async {
    final today = _todayStr();

    // Step 1: local SharedPreferences (instant, no network).
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQuotaPrefsKey);
      if (raw != null) {
        final local = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (local['date'] == today) {
          if (mounted) {
            setState(() {
              _quota['free_used'] = (local['used'] as int?) ?? 0;
              _quota['ads_today'] = (local['ads'] as int?) ?? 0;
              _quota['window_expires'] = local['lockout'] as String?;
            });
          }
        }
      }
    } catch (_) {}

    // Step 2: sync remote for premium status + server-side window.
    try {
      final remote = await api.getAIQuota();
      final remoteUsed = (remote['free_used'] as int?) ?? 0;
      final localUsed = (_quota['free_used'] as int?) ?? 0;
      if (mounted) {
        setState(() {
          _quota['free_used'] = max(localUsed, remoteUsed);
          _quota['is_premium'] = remote['is_premium'] ?? _quota['is_premium'];
          if (_quota['window_expires'] == null &&
              remote['window_expires'] != null) {
            _quota['window_expires'] = remote['window_expires'];
          }
          _quota['ads_today'] = max(
            (_quota['ads_today'] as int?) ?? 0,
            (remote['ads_today'] as int?) ?? 0,
          );
        });
        await _saveQuota();
      }
    } catch (_) {}
  }

  Future<void> _saveQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kQuotaPrefsKey,
        jsonEncode({
          'date': _todayStr(),
          'used': _quota['free_used'] ?? 0,
          'ads': _quota['ads_today'] ?? 0,
          'lockout': _quota['window_expires'],
        }),
      );
    } catch (_) {}
  }

  String _todayStr() =>
      DateTime.now().toIso8601String().substring(0, 10);

  bool get _isPremium => _quota['is_premium'] == true;
  int get _freeUsed => (_quota['free_used'] as int?) ?? 0;
  int get _adsToday => (_quota['ads_today'] as int?) ?? 0;
  bool get _hasFreeMsgs => _freeUsed < _kFreeMessages;
  bool get _canWatchAd => _adsToday < _kMaxAdsPerDay;

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
    if (_isPremium) return _QuotaResult.allowed;
    if (_inUnlockedWindow) return _QuotaResult.allowed;
    if (_hasFreeMsgs) return _QuotaResult.allowed;
    if (_canWatchAd) return _QuotaResult.showAdGate;
    return _QuotaResult.dailyLimit;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History loading
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_historyLoaded) return;

    try {
      if (_isAIMode) {
        await _loadAIHistory();
      } else {
        await _loadDMHistory();
        _checkAIJoined();
      }
    } catch (_) {
      // Non-fatal — show empty / greeting state.
    } finally {
      if (mounted) setState(() => _historyLoaded = true);
      _scrollDown(jump: true);
    }

    // Auto-send post context message after history is shown.
    if (_isAIMode &&
        widget.postContext != null &&
        widget.postContext!.isNotEmpty) {
      final author = (widget.postAuthor?.isNotEmpty == true)
          ? widget.postAuthor!
          : 'a community member';
      await _sendAI(
        'I want to discuss a post from $author: "${widget.postContext}"\n\n'
        'Give me a quick wealth insight or action tip about this.',
        adUnlocked: false,
        isContextMessage: true,
      );
    }
  }

  /// FIX: Always use the messages system for AI chat.
  /// 1. Call getOrCreateAIConversation() to get/create the correct
  ///    messages-system conversation UUID.
  /// 2. Load history via getDMMessages() — same as peer DMs.
  /// 3. AI context is naturally in the DB; backend reads last 20 rows.
  Future<void> _loadAIHistory() async {
    final prefs = await SharedPreferences.getInstance();

    // Always fetch the canonical AI conversation ID from the server.
    // The endpoint is idempotent — cheap to call on every open.
    try {
      final convId = await api.getOrCreateAIConversation();
      if (convId.isNotEmpty) {
        _aiConvId = convId;
        await prefs.setString(_kAiConvIdKey, convId);
      }
    } catch (_) {
      // Fallback: use cached ID (works offline or on transient error).
      _aiConvId ??= prefs.getString(_kAiConvIdKey);
    }

    if (_aiConvId == null || _aiConvId!.isEmpty) {
      // Can't reach server and no cache — show greeting.
      _addGreeting();
      return;
    }

    // Load persisted messages from the messages table.
    try {
      final msgs = await api.getDMMessages(_aiConvId!, limit: 50);
      if (mounted && msgs.isNotEmpty) {
        setState(() {
          for (final m in msgs) {
            final senderType = m['sender_type']?.toString() ?? '';
            final isAI =
                senderType == 'ai' || senderType == 'system';
            _msgs.add(_Msg(
              id: m['id']?.toString(),
              content: m['content']?.toString() ?? '',
              sender: isAI ? 'RiseUp AI' : 'You',
              avatar: isAI ? '🤖' : '👤',
              isMe: !isAI,
              isAI: isAI,
              time: DateTime.tryParse(
                  m['created_at']?.toString() ?? ''),
            ));
          }
        });
        _lastPollTime = msgs.last['created_at']?.toString();
        return;
      }
    } catch (_) {
      // Network error — fall through to greeting.
    }

    // No history yet → greeting is already stored in DB by the backend
    // on conversation creation, but just in case show it locally too.
    if (_msgs.isEmpty) _addGreeting();
  }

  void _addGreeting() {
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(
        content:
            "Hey! 👋 I'm your RiseUp AI mentor. Ask me anything about "
            "wealth-building, side hustles, investing, or personal growth!",
        sender: 'RiseUp AI',
        avatar: '🤖',
        isMe: false,
        isAI: true,
      ));
    });
  }

  Future<void> _loadDMHistory() async {
    if (widget.userId.isEmpty) return;
    final msgs = await api.getDMMessages(widget.userId);
    if (!mounted || msgs.isEmpty) return;

    final myId = await api.getUserId() ?? '';
    setState(() {
      for (final m in msgs) {
        final senderId = m['sender_id']?.toString() ?? '';
        final senderType = m['sender_type']?.toString() ?? '';
        final isAIMsg =
            senderType == 'ai' || senderType == 'system';
        final isMe = senderId == myId;
        final profile = (m['profiles'] as Map?) ?? {};
        _msgs.add(_Msg(
          id: m['id']?.toString(),
          content: m['content']?.toString() ?? '',
          sender: isAIMsg
              ? 'RiseUp AI'
              : isMe
                  ? 'You'
                  : (profile['full_name']?.toString() ?? widget.name),
          avatar: isAIMsg
              ? '🤖'
              : isMe
                  ? '👤'
                  : (profile['avatar_url']?.toString() ?? widget.avatar),
          isMe: isMe && !isAIMsg,
          isAI: isAIMsg,
          time: DateTime.tryParse(m['created_at']?.toString() ?? ''),
        ));
      }
    });
    if (_msgs.isNotEmpty) {
      _lastPollTime = msgs.last['created_at']?.toString();
    }
  }

  Future<void> _checkAIJoined() async {
    try {
      if (widget.userId.isEmpty) return;
      final result = await api.checkAIInConversation(widget.userId);
      if (mounted && result['ai_joined'] == true) {
        setState(() => _aiJoined = true);
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling — unified for AI-only and peer-DM modes (every 4 s)
  // ─────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_historyLoaded) return;
    final convId = _activeConvId;
    if (convId == null || convId.isEmpty) return;

    try {
      final newMsgs =
          await api.getDMMessages(convId, since: _lastPollTime);
      if (!mounted || newMsgs.isEmpty) return;

      final myId = await api.getUserId() ?? '';
      final existingIds = _msgs.map((m) => m.id).toSet();

      bool added = false;
      setState(() {
        for (final m in newMsgs) {
          final id = m['id']?.toString() ?? '';
          if (id.isEmpty || existingIds.contains(id)) continue;

          final senderId = m['sender_id']?.toString() ?? '';
          final senderType = m['sender_type']?.toString() ?? '';
          final isAIMsg =
              senderType == 'ai' || senderType == 'system';
          final isMe = senderId == myId && !isAIMsg;
          final profile = (m['profiles'] as Map?) ?? {};

          _msgs.add(_Msg(
            id: id,
            content: m['content']?.toString() ?? '',
            sender: isAIMsg
                ? 'RiseUp AI'
                : isMe
                    ? 'You'
                    : (profile['full_name']?.toString() ??
                        widget.name),
            avatar: isAIMsg
                ? '🤖'
                : isMe
                    ? '👤'
                    : (profile['avatar_url']?.toString() ??
                        widget.avatar),
            isMe: isMe,
            isAI: isAIMsg,
            time: DateTime.tryParse(
                m['created_at']?.toString() ?? ''),
          ));
          existingIds.add(id);
          added = true;
        }
      });

      _lastPollTime = newMsgs.last['created_at']?.toString();
      if (added) _scrollDown();
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Send routing
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    if (_isAIMode) {
      await _trySendAI(text);
    } else if (_aiJoined && text.startsWith('@ai ')) {
      final aiText = text.substring(4).trim();
      if (aiText.isEmpty) return;
      _textCtrl.clear();
      await _trySendAI(aiText, viaAIDM: true);
    } else {
      await _sendDM(text);
    }
  }

  Future<void> _trySendAI(String text, {bool viaAIDM = false}) async {
    final result = _checkAIQuota();
    if (result == _QuotaResult.showAdGate) {
      await _showAdGate(text, viaAIDM: viaAIDM);
      return;
    }
    if (result == _QuotaResult.dailyLimit) {
      _showDailyLimit();
      return;
    }
    await _sendAI(text, adUnlocked: false, viaAIDM: viaAIDM);
  }

  /// Core AI send — FIX: always uses sendAIMessageInDM so messages are
  /// stored in the messages table and the AI receives full DB context.
  ///
  /// [viaAIDM]          — true when inside a peer DM with AI joined.
  /// [isContextMessage] — true for auto-sent post context (no quota charge).
  Future<void> _sendAI(
    String text, {
    bool adUnlocked = false,
    bool viaAIDM = false,
    bool isContextMessage = false,
  }) async {
    // Resolve which conversation to use.
    final convId = viaAIDM ? widget.userId : _aiConvId;
    if (convId == null || convId.isEmpty) {
      _addErrorBubble('Connection issue. Please try again! 🔄');
      return;
    }

    _textCtrl.clear();

    // Add user bubble immediately (optimistic).
    final optimisticId = 'opt_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _msgs.add(_Msg(
        id: optimisticId,
        content: text,
        sender: 'You',
        avatar: '👤',
        isMe: true,
      ));
      _aiResponding = true;
    });
    _scrollDown();

    try {
      final res = await api.sendAIMessageInDM(
        convId,
        text,
        adUnlocked: adUnlocked,
      );

      final aiContent =
          (res['content'] ?? "I'm here to help! 💡").toString();

      // The backend stored both the user message and the AI reply.
      // Advance poll time so the poller doesn't re-add them.
      _lastPollTime = DateTime.now().toUtc().toIso8601String();

      // Reconcile quota from server response.
      if (res['quota'] != null) {
        final q = res['quota'] as Map;
        final remoteUsed = (q['free_used'] as int?) ?? 0;
        setState(() {
          _quota['free_used'] = max(_freeUsed, remoteUsed);
          _quota['window_expires'] =
              q['window_expires'] ?? _quota['window_expires'];
          _quota['is_premium'] =
              q['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      } else if (!_isPremium &&
          !_inUnlockedWindow &&
          !isContextMessage) {
        setState(() => _quota['free_used'] = _freeUsed + 1);
        await _saveQuota();
      }

      if (!mounted) return;

      final aiMsg = _Msg(
        content: aiContent,
        sender: 'RiseUp AI',
        avatar: '🤖',
        isMe: false,
        isAI: true,
      );
      setState(() {
        _aiResponding = false;
        _msgs.add(aiMsg);
      });
      _typeMessage(aiMsg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _aiResponding = false);
      if (e.statusCode == 402) {
        await _showAdGate(text, viaAIDM: viaAIDM);
      } else if (e.statusCode == 429) {
        _showDailyLimit();
      } else {
        _addErrorBubble('Connection issue. Please try again! 🔄');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiResponding = false);
      _addErrorBubble('Connection issue. Please try again! 🔄');
    }
  }

  /// FIX: Replace optimistic message with real DB message (real UUID) so
  /// the poller never re-adds it as a duplicate.
  Future<void> _sendDM(String text) async {
    _textCtrl.clear();
    final optimisticId = 'opt_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _msgs.add(_Msg(
        id: optimisticId,
        content: text,
        sender: 'You',
        avatar: '👤',
        isMe: true,
      ));
      _dmSending = true;
    });
    _scrollDown();

    try {
      final result = await api.sendDMMessage(widget.userId, text);

      // Replace the optimistic bubble with the real DB row.
      final realId =
          result['message']?['id']?.toString() ?? optimisticId;

      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere((m) => m.id == optimisticId);
          if (idx != -1) {
            final old = _msgs[idx];
            _msgs[idx] = _Msg(
              id: realId,
              content: old.content,
              sender: old.sender,
              avatar: old.avatar,
              isMe: true,
              time: old.time,
            );
          }
          _dmSending = false;
        });
        // Advance poll time so the poller ignores this message.
        _lastPollTime = DateTime.now().toUtc().toIso8601String();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((m) => m.id == optimisticId);
        _dmSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to send. Check your connection.'),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 2),
      ));
    }
  }

  void _addErrorBubble(String msg) {
    if (!mounted) return;
    setState(() => _msgs.add(_Msg(
          content: msg,
          sender: 'RiseUp AI',
          avatar: '🤖',
          isMe: false,
          isAI: true,
        )));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Invite AI to peer DM
  // ─────────────────────────────────────────────────────────────────────────
  void _inviteAI() {
    if (widget.userId.isEmpty || _isAIMode) return;
    HapticFeedback.lightImpact();
    _doInviteAI();
  }

  Future<void> _doInviteAI() async {
    try {
      await api.inviteAIToConversation(widget.userId);
      if (!mounted) return;
      setState(() {
        _aiJoined = true;
        _msgs.add(_Msg(
          content:
              '🤖 **RiseUp AI has joined the conversation!**\n\n'
              "I'm here to help with wealth questions, strategies, or anything "
              "you need. Just ask!\n\n"
              'Tip: Use "@ai your question" to ask me anything.',
          sender: 'RiseUp AI',
          avatar: '🤖',
          isMe: false,
          isAI: true,
        ));
      });
      _scrollDown();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not invite AI. Try again.'),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 2),
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Typing animation
  // ─────────────────────────────────────────────────────────────────────────
  void _typeMessage(_Msg msg) {
    msg.isTyping = true;
    msg.displayText = '';
    int i = 0;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 14), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (i >= msg.content.length) {
        t.cancel();
        setState(() {
          msg.isTyping = false;
          msg.displayText = msg.content;
        });
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
      final maxExt = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(maxExt);
      } else {
        _scroll.animateTo(
          maxExt,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Freemium gate
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showAdGate(String pendingText,
      {bool viaAIDM = false}) async {
    final watched = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdGateSheet(
        freeUsed: _freeUsed,
        adsToday: _adsToday,
        maxAds: _kMaxAdsPerDay,
        windowHours: _kWindowDur.inHours,
      ),
    );
    if (watched != true || !mounted) return;

    if (!adService.isRewardedReady) {
      if (!mounted) return;
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
          _quota['free_used'] = 0;
          _quota['ads_today'] = _adsToday + 1;
          _quota['window_expires'] =
              DateTime.now().add(_kWindowDur).toIso8601String();
        });
        await _saveQuota();
        if (mounted) {
          await _sendAI(pendingText,
              adUnlocked: true, viaAIDM: viaAIDM);
        }
      },
      onDismissed: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Watch the full ad to unlock AI messages.'),
          duration: Duration(seconds: 2),
        ));
      },
    );
  }

  void _showDailyLimit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyLimitSheet(
        onUpgrade: () {
          Navigator.pop(context);
          context.go('/premium');
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final isSending = _aiResponding || _dmSending;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(
          isDark, cardColor, borderColor, textColor, subColor),
      body: Column(children: [
        if (_aiJoined && !_isAIMode) _AIJoinedBanner(),
        if ((_isAIMode || _aiJoined) && !_isPremium)
          _QuotaRibbon(
            isPremium: _isPremium,
            inWindow: _inUnlockedWindow,
            freeUsed: _freeUsed,
            freeTotal: _kFreeMessages,
            adsToday: _adsToday,
            maxAds: _kMaxAdsPerDay,
            windowExpires: _quota['window_expires'] as String?,
          ),
        Expanded(
          child: !_historyLoaded
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
              : _msgs.isEmpty
                  ? _buildEmptyState(isDark, subColor)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount:
                          _msgs.length + (isSending ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _msgs.length) {
                          return _buildTypingIndicator(
                              isDark, surfColor);
                        }
                        return _buildBubble(
                            _msgs[i], isDark, textColor, surfColor);
                      },
                    ),
        ),
        _buildInputBar(isDark, cardColor, borderColor, textColor,
            subColor, surfColor, isSending),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AppBar
  // ─────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
    bool isDark,
    Color card,
    Color border,
    Color text,
    Color sub,
  ) {
    final displayName = _isAIMode ? 'RiseUp AI' : widget.name;
    final displayAvatar = _isAIMode ? '🤖' : widget.avatar;
    final avatarIsUrl =
        !_isAIMode && displayAvatar.startsWith('http');

    return AppBar(
      backgroundColor: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon:
            Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: avatarIsUrl
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent]),
              image: avatarIsUrl
                  ? DecorationImage(
                      image: NetworkImage(widget.avatar),
                      fit: BoxFit.cover)
                  : null,
              shape: BoxShape.circle,
            ),
            child: avatarIsUrl
                ? null
                : Center(
                    child: Text(displayAvatar,
                        style: const TextStyle(fontSize: 18))),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: card, width: 1.5),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isAIMode || _aiJoined) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('AI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              Text(
                _isAIMode ? 'Always online' : 'Online',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.success),
              ),
            ],
          ),
        ),
      ]),
      actions: [
        if (!_isAIMode && !_aiJoined)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: _inviteAI,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.3)),
                ),
                child:
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 13),
                  SizedBox(width: 4),
                  Text('Invite AI',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
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
              Text('AI Active',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        IconButton(
          icon: Icon(Iconsax.call, color: text, size: 20),
          onPressed: () =>
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Voice calls coming soon 📞'),
                  duration: Duration(seconds: 1))),
        ),
        IconButton(
          icon: Icon(Iconsax.video, color: text, size: 20),
          onPressed: () =>
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
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
    bool isDark,
    Color card,
    Color border,
    Color text,
    Color sub,
    Color surf,
    bool isSending,
  ) {
    String hintText;
    if (_isAIMode) {
      hintText = 'Ask your wealth mentor...';
    } else if (_aiJoined) {
      hintText = 'Message or @ai ${widget.name}...';
    } else {
      hintText = 'Message ${widget.name}...';
    }

    return Container(
      decoration: BoxDecoration(
          color: card, border: Border(top: BorderSide(color: border))),
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
                content: Text(
                    'Photo selected ✅ — media upload coming soon'),
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
            maxLines: 5,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            enabled: !isSending,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled: true,
              fillColor: surf,
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
          onTap: isSending
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  _onSend();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
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
                      width: 18,
                      height: 18,
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

  // ─────────────────────────────────────────────────────────────────────────
  // Message bubble
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBubble(
      _Msg m, bool isDark, Color textColor, Color surfColor) {
    final aiBg =
        isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final avatarIsUrl =
        m.avatar.startsWith('http') && m.avatar.length > 10;

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
                Text(
                  m.sender,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: m.isAI
                          ? AppColors.primary
                          : AppColors.warning),
                ),
                if (m.isAI) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.auto_awesome,
                      size: 10, color: AppColors.primary),
                ],
              ]),
            ),
          Row(
            mainAxisAlignment: m.isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!m.isMe) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: avatarIsUrl
                        ? null
                        : const LinearGradient(colors: [
                            AppColors.primary,
                            AppColors.accent
                          ]),
                    image: avatarIsUrl
                        ? DecorationImage(
                            image: NetworkImage(m.avatar),
                            fit: BoxFit.cover)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: avatarIsUrl
                      ? null
                      : Center(
                          child: Text(m.avatar,
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
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(m.isMe ? 18 : 4),
                      bottomRight: Radius.circular(m.isMe ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: (m.isMe || !m.isAI)
                      ? Text(
                          m.displayText,
                          style: TextStyle(
                              color: m.isMe ? Colors.white : textColor,
                              fontSize: 14,
                              height: 1.5),
                        )
                      : MarkdownBody(
                          data: m.displayText,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: isDark
                                  ? const Color(0xFFE8E8F0)
                                  : Colors.black87,
                              fontSize: 14,
                              height: 1.55,
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
            child: Text(
              _formatTime(m.time),
              style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white24 : Colors.black26),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.08, curve: Curves.easeOut);
  }

  Widget _buildTypingIndicator(bool isDark, Color surfColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: isDark ? AppColors.aiBubble : surfColor,
            borderRadius: BorderRadius.circular(18),
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
                    color: AppColors.primary, shape: BoxShape.circle),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .fadeIn(delay: Duration(milliseconds: i * 200))
                  .then()
                  .fadeOut(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(bool isDark, Color subColor) {
    final bg = isDark ? Colors.black : Colors.white;
    if (_isAIMode) {
      return Container(
        color: bg,
        child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                      child:
                          Text('🤖', style: TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 20),
                const Text('RiseUp AI Mentor',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 10),
                Text(
                  'Your personal wealth coach.\nAsk me anything about income,\n'
                  'investing, or financial freedom!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: subColor, height: 1.6),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Text(
                    '💡 Try: "How do I make my first \$1k online?"',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
        ),
      );
    }
    return Container(
      color: bg,
      child: Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('👋',
                  style: TextStyle(
                      fontSize: 56,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              Text('Say hello!',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Text('Start a conversation below',
                  style: TextStyle(fontSize: 14, color: subColor)),
              if (_aiJoined) ...[
                const SizedBox(height: 16),
                Text('Use "@ai your message" to ask AI',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.primary)),
              ],
            ]),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (unchanged from v8)
// ─────────────────────────────────────────────────────────────────────────────

class _AIJoinedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withOpacity(0.08),
      child: const Row(children: [
        Icon(Icons.auto_awesome, color: AppColors.primary, size: 14),
        SizedBox(width: 8),
        Text(
          'RiseUp AI is in this conversation',
          style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }
}

class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inWindow;
  final int freeUsed, freeTotal, adsToday, maxAds;
  final String? windowExpires;

  const _QuotaRibbon({
    required this.isPremium,
    required this.inWindow,
    required this.freeUsed,
    required this.freeTotal,
    required this.adsToday,
    required this.maxAds,
    this.windowExpires,
  });

  @override
  State<_QuotaRibbon> createState() => _QuotaRibbonState();
}

class _QuotaRibbonState extends State<_QuotaRibbon> {
  Timer? _timer;
  String _expiry = '';

  @override
  void initState() {
    super.initState();
    if (widget.inWindow && widget.windowExpires != null) _startTimer();
  }

  void _startTimer() {
    _updateExpiry();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => _updateExpiry());
  }

  void _updateExpiry() {
    if (!mounted) return;
    final exp = DateTime.tryParse(widget.windowExpires ?? '');
    if (exp == null) return;
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) {
      setState(() => _expiry = '');
      return;
    }
    final h = diff.inHours;
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _expiry = h > 0 ? '${h}h ${m}m' : '$m:$s');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPremium) return const SizedBox.shrink();
    final remaining = widget.freeTotal - widget.freeUsed;

    if (widget.inWindow) {
      return _ribbon(
        Icons.lock_open_rounded,
        AppColors.success,
        'AI unlocked${_expiry.isNotEmpty ? ' · $_expiry left' : ''}',
        Colors.transparent,
      );
    }
    if (remaining > 0) {
      return _ribbon(
        Icons.chat_bubble_outline_rounded,
        AppColors.primary,
        '$remaining free AI message${remaining == 1 ? '' : 's'} remaining',
        AppColors.primary.withOpacity(0.06),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _ribbon(
      IconData icon, Color color, String label, Color bg) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: bg,
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        GestureDetector(
          onTap: () => GoRouter.of(context).go('/premium'),
          child: const Text('Go Premium',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _AdGateSheet extends StatelessWidget {
  final int freeUsed, adsToday, maxAds, windowHours;

  const _AdGateSheet({
    required this.freeUsed,
    required this.adsToday,
    required this.maxAds,
    required this.windowHours,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;
    final remaining = maxAds - adsToday;

    return Container(
      decoration: BoxDecoration(
          color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
            shape: BoxShape.circle,
          ),
          child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 36))),
        ),
        const SizedBox(height: 16),
        Text('Unlock AI Messages',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used your $freeUsed free AI messages.\n"
          'Watch a short ad to unlock ${windowHours}h of unlimited AI mentoring.',
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
            '$remaining unlock${remaining == 1 ? '' : 's'} remaining today',
            style: TextStyle(fontSize: 12, color: sub)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
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
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context, false);
              context.go('/premium');
            },
            icon:
                const Icon(Icons.workspace_premium_rounded, size: 18),
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
          child:
              Text('Not now', style: TextStyle(color: sub, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _DailyLimitSheet extends StatefulWidget {
  final VoidCallback onUpgrade;

  const _DailyLimitSheet({required this.onUpgrade});

  @override
  State<_DailyLimitSheet> createState() => _DailyLimitSheetState();
}

class _DailyLimitSheetState extends State<_DailyLimitSheet> {
  Timer? _timer;
  String _countdown = '--:--:--';

  @override
  void initState() {
    super.initState();
    _update();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    final midnight =
        DateTime.utc(now.year, now.month, now.day + 1);
    final diff = midnight.difference(now);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _countdown = '$h:$m:$s');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
          color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        const Text('⏰', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text('Daily Limit Reached',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used all your free AI unlocks for today.\n"
          'Your limit resets at midnight UTC.',
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
            Text(_countdown,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: text,
                    fontFamily: 'monospace',
                    letterSpacing: 2)),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onUpgrade,
            icon:
                const Icon(Icons.workspace_premium_rounded, size: 20),
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
