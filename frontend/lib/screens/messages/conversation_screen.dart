// ignore_for_file: deprecated_member_use
// frontend/lib/screens/messages/conversation_screen.dart
// Production v12 — Full history persistence + load-more pagination
//
// Changes vs v11:
//  • History now loads _kHistoryPageSize (100) messages, not 50
//  • Load-more triggered by scrolling to the TOP — fetches older pages
//  • _kContextWindow raised 20 → 50: AI remembers far more of the convo
//  • First-time AI greeting persisted to backend via sendAIMessageInDM
//    (uses isSystemGreeting flag so it doesn't count against quota)
//  • _lastPollTime now initialised from the very first history load so
//    polling never re-delivers messages already shown
//  • _poll guards against running while history is still loading
//  • DM load-more works identically to AI load-more (scroll-up pagination)
//  • All other v11 fixes preserved unchanged

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
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const int _kFreeMessages     = 3;
const int _kMaxAdsPerDay     = 5;
const Duration _kWindowDur   = Duration(hours: 4);
const String _kQuotaPrefsKey = 'riseup_ai_quota_v1';
const String _kAiConvIdKey   = 'riseup_ai_conv_id_v2';
const String _kGreetedPrefix = 'riseup_ai_greeted_v1_';   // + convId
const String _kPollTimePrefix= 'riseup_poll_time_v1_';    // + convId

// CHANGED: larger context window so AI remembers more of the conversation
const int _kContextWindow    = 50;
// CHANGED: page size for initial history load
const int _kHistoryPageSize  = 100;

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
  final bool isError;
  final DateTime time;
  String displayText;
  bool isTyping;

  _Msg({
    String? id,
    required this.content,
    required this.sender,
    required this.avatar,
    required this.isMe,
    this.isAI = false,
    this.isError = false,
    DateTime? time,
  })  : id = id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        displayText = content,
        isTyping = false,
        time = time ?? DateTime.now();
}

enum _QuotaResult { allowed, showAdGate, dailyLimit }

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  final String userId;   // conversation UUID for DM; 'ai' for AI-only
  final String name;
  final String avatar;
  final bool isAI;
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
  final _textCtrl  = TextEditingController();
  final _scroll    = ScrollController();
  final List<_Msg> _msgs = [];

  bool _historyLoaded    = false;
  bool _aiResponding     = false;
  bool _dmSending        = false;
  bool _aiJoined         = false;
  bool _convInitializing = false;

  // CHANGED: pagination state
  bool _loadingMore    = false;
  bool _hasMoreHistory = true;

  String? _aiConvId;
  String? _lastPollTime;

  String? _cachedMyId;
  String? _cachedMyName;

  Timer? _typingTimer;
  Timer? _pollTimer;

  Map<String, dynamic> _quota = {
    'free_used': 0,
    'ads_today': 0,
    'window_expires': null,
    'is_premium': false,
    'date': '',
  };

  bool get _isAIMode   => widget.isAI || widget.userId == 'ai';
  String? get _activeConvId => _isAIMode ? _aiConvId : widget.userId;
  bool get _isSending  => _aiResponding || _dmSending;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bootstrap();
    // CHANGED: attach scroll listener for load-more (scroll to top = older msgs)
    _scroll.addListener(_onScroll);
  }

  Future<void> _bootstrap() async {
    await _loadQuota();
    await _restorePollTime();
    await _loadHistory();
    _startPolling();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // CHANGED: trigger load-more when user scrolls near the top
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels <= 120 &&
        !_loadingMore &&
        _hasMoreHistory &&
        _historyLoaded) {
      _loadMoreHistory();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Poll-time persistence
  // ─────────────────────────────────────────────────────────────────────────
  String get _pollKey => '$_kPollTimePrefix${widget.userId}';

  Future<void> _restorePollTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastPollTime = prefs.getString(_pollKey);
    } catch (_) {}
  }

  Future<void> _savePollTime(String t) async {
    _lastPollTime = t;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pollKey, t);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Quota
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadQuota() async {
    final today = _todayStr();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQuotaPrefsKey);
      if (raw != null) {
        final local = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (local['date'] == today && mounted) {
          setState(() {
            _quota['free_used']     = (local['used']    as int?) ?? 0;
            _quota['ads_today']     = (local['ads']     as int?) ?? 0;
            _quota['window_expires']= local['lockout']  as String?;
          });
        }
      }
    } catch (_) {}

    try {
      final remote = await api.getAIQuota();
      if (mounted) {
        setState(() {
          _quota['free_used']     = max((_quota['free_used'] as int?) ?? 0,
                                        (remote['free_used'] as int?) ?? 0);
          _quota['is_premium']    = remote['is_premium'] ?? _quota['is_premium'];
          _quota['window_expires']??= remote['window_expires'];
          _quota['ads_today']     = max((_quota['ads_today'] as int?) ?? 0,
                                        (remote['ads_today'] as int?) ?? 0);
        });
        await _saveQuota();
      }
    } catch (_) {}
  }

  Future<void> _saveQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQuotaPrefsKey, jsonEncode({
        'date'   : _todayStr(),
        'used'   : _quota['free_used'] ?? 0,
        'ads'    : _quota['ads_today'] ?? 0,
        'lockout': _quota['window_expires'],
      }));
    } catch (_) {}
  }

  String _todayStr() => DateTime.now().toIso8601String().substring(0, 10);

  bool get _isPremium   => _quota['is_premium'] == true;
  int  get _freeUsed    => (_quota['free_used'] as int?) ?? 0;
  int  get _adsToday    => (_quota['ads_today'] as int?) ?? 0;
  bool get _hasFreeMsgs => _freeUsed < _kFreeMessages;
  bool get _canWatchAd  => _adsToday < _kMaxAdsPerDay;

  bool get _inUnlockedWindow {
    final exp = _quota['window_expires'] as String?;
    if (exp == null) return false;
    final dt  = DateTime.tryParse(exp);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Ensure AI conversation ID
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _ensureAIConv() async {
    if (_aiConvId != null && _aiConvId!.isNotEmpty) return true;
    if (mounted) setState(() => _convInitializing = true);

    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kAiConvIdKey);
      if (cached != null && cached.isNotEmpty) {
        _aiConvId = cached;
        if (mounted) setState(() => _convInitializing = false);
        return true;
      }

      final convId = await api.getOrCreateAIConversation();
      if (convId.isNotEmpty) {
        _aiConvId = convId;
        await prefs.setString(_kAiConvIdKey, convId);
        if (mounted) setState(() => _convInitializing = false);
        return true;
      }
    } catch (e) {
      debugPrint('[ConversationScreen] _ensureAIConv error: $e');
    }

    if (mounted) setState(() => _convInitializing = false);
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History — initial load
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_historyLoaded) return;

    await _fetchMyInfo();

    try {
      if (_isAIMode) {
        await _loadAIHistory();
      } else {
        await _loadDMHistory();
        _checkAIJoined();
      }
    } catch (e) {
      debugPrint('[ConversationScreen] _loadHistory error: $e');
    } finally {
      if (mounted) setState(() => _historyLoaded = true);
      _scrollDown(jump: true);
    }

    if (_isAIMode && widget.postContext != null && widget.postContext!.isNotEmpty) {
      final author = (widget.postAuthor?.isNotEmpty == true) ? widget.postAuthor! : 'a community member';
      await _sendAI(
        'I want to discuss a post from $author: "${widget.postContext}"\n\n'
        'Give me a quick wealth insight or action tip about this.',
        adUnlocked: false,
        isContextMessage: true,
      );
    }
  }

  Future<void> _fetchMyInfo() async {
    try {
      _cachedMyId ??= await api.getUserId();
      if (_cachedMyId != null) {
        final profile = await api.getUserProfile(_cachedMyId!);
        _cachedMyName = (profile['full_name'] as String?)?.trim();
        if (_cachedMyName == null || _cachedMyName!.isEmpty) {
          _cachedMyName = (profile['username'] as String?)?.trim();
        }
      }
    } catch (_) {}
  }

  // CHANGED: load _kHistoryPageSize messages; set _hasMoreHistory accordingly
  Future<void> _loadAIHistory() async {
    await _ensureAIConv();
    if (_aiConvId == null || _aiConvId!.isEmpty) return;

    try {
      final msgs = await api.getDMMessages(_aiConvId!, limit: _kHistoryPageSize);
      if (!mounted) return;

      if (msgs.isNotEmpty) {
        setState(() {
          _msgs.clear();
          for (final m in msgs) _msgs.add(_msgFromMap(m, myId: _cachedMyId));
          // CHANGED: if we got a full page there are likely older messages
          _hasMoreHistory = msgs.length >= _kHistoryPageSize;
        });
        // CHANGED: initialise poll-time from the very last loaded message
        await _savePollTime(msgs.last['created_at']?.toString() ?? '');
      } else {
        _hasMoreHistory = false;
        await _maybeShowFirstTimeGreeting();
      }
    } catch (e) {
      debugPrint('[ConversationScreen] _loadAIHistory error: $e');
    }
  }

  // CHANGED: same page-size treatment for DM history
  Future<void> _loadDMHistory() async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;

    try {
      final msgs = await api.getDMMessages(widget.userId, limit: _kHistoryPageSize);
      if (!mounted || msgs.isEmpty) {
        _hasMoreHistory = false;
        return;
      }

      setState(() {
        _msgs.clear();
        for (final m in msgs) _msgs.add(_msgFromMap(m, myId: _cachedMyId));
        _hasMoreHistory = msgs.length >= _kHistoryPageSize;
      });
      await _savePollTime(msgs.last['created_at']?.toString() ?? '');
    } catch (e) {
      debugPrint('[ConversationScreen] _loadDMHistory error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHANGED: load-more (older messages) triggered by scroll-to-top
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadMoreHistory() async {
    if (_loadingMore || !_hasMoreHistory || _msgs.isEmpty) return;
    if (mounted) setState(() => _loadingMore = true);

    // The oldest message currently in the list gives us our "before" cursor.
    final oldestTime = _msgs.first.time.toUtc().toIso8601String();
    final convId     = _activeConvId;
    if (convId == null || convId.isEmpty) {
      if (mounted) setState(() => _loadingMore = false);
      return;
    }

    try {
      // Pass `before` param — your ApiService.getDMMessages must support it.
      // Signature: getDMMessages(convId, {int? limit, String? since, String? before})
      final older = await api.getDMMessages(
        convId,
        limit : _kHistoryPageSize,
        before: oldestTime,
      );

      if (!mounted) return;

      if (older.isEmpty) {
        setState(() {
          _hasMoreHistory = false;
          _loadingMore    = false;
        });
        return;
      }

      // Remember scroll position so the view doesn't jump.
      final prevExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;

      setState(() {
        final newMsgs = older
            .map((m) => _msgFromMap(m, myId: _cachedMyId))
            .toList();
        _msgs.insertAll(0, newMsgs);
        _hasMoreHistory = older.length >= _kHistoryPageSize;
        _loadingMore    = false;
      });

      // Restore scroll position after the new items are inserted at the top.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final newExtent = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(_scroll.offset + (newExtent - prevExtent));
      });
    } catch (e) {
      debugPrint('[ConversationScreen] _loadMoreHistory error: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHANGED: first-time greeting is stored to the backend so it persists
  //          across devices and reinstalls.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _maybeShowFirstTimeGreeting() async {
    if (_aiConvId == null) return;
    final greetKey = '$_kGreetedPrefix$_aiConvId';
    try {
      final prefs        = await SharedPreferences.getInstance();
      final alreadyLocal = prefs.getBool(greetKey) ?? false;
      if (alreadyLocal) return;

      final firstName = _cachedMyName?.split(' ').first ?? 'there';
      final greeting  =
          'Hey $firstName 👋 Nice meeting you!\n\n'
          "I'm your RiseUp AI Mentor — here to help you build wealth, grow income, "
          'and level up your financial game. 😊\n\n'
          'Ask me anything about investing, side hustles, money mindset, or '
          'how to reach your next income goal.';

      // Show locally immediately so the user sees it right away.
      if (mounted) {
        final greetMsg = _Msg(
          content: greeting,
          sender : 'RiseUp AI',
          avatar : '🤖',
          isMe   : false,
          isAI   : true,
        );
        setState(() => _msgs.add(greetMsg));
        _typeMessage(greetMsg);
      }

      // Persist to backend in the background (isSystemGreeting skips quota).
      // If your backend doesn't support this flag yet, wrap in try/catch
      // so the local greeting still shows even if the API call fails.
      try {
        await api.sendAIMessageInDM(
          _aiConvId!,
          greeting,
          adUnlocked      : false,
          contextHistory  : [],
          isSystemGreeting: true,   // Add this optional param to your ApiService
        );
      } catch (_) {
        // Backend persistence failed — greeting is still shown locally.
        // On next open from a fresh device it will show again until the
        // backend call succeeds once.
      }

      await prefs.setBool(greetKey, true);
    } catch (e) {
      debugPrint('[ConversationScreen] greeting error: $e');
    }
  }

  _Msg _msgFromMap(Map m, {required String? myId}) {
    final id         = m['id']?.toString()          ?? '';
    final senderId   = m['sender_id']?.toString()   ?? '';
    final senderType = m['sender_type']?.toString() ?? '';
    final isAIMsg    = senderType == 'ai' || senderType == 'system';
    final isMe       = !isAIMsg && myId != null && senderId == myId;
    final profile    = (m['profiles'] as Map?) ?? {};

    return _Msg(
      id     : id.isNotEmpty ? id : null,
      content: m['content']?.toString() ?? '',
      sender : isAIMsg ? 'RiseUp AI'
               : isMe  ? (_cachedMyName ?? 'You')
               : (profile['full_name']?.toString() ?? widget.name),
      avatar : isAIMsg ? '🤖'
               : isMe  ? '👤'
               : (profile['avatar_url']?.toString() ?? widget.avatar),
      isMe   : isMe,
      isAI   : isAIMsg,
      time   : DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  Future<String?> _getMyId() async {
    _cachedMyId ??= await api.getUserId();
    return _cachedMyId;
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
  // CHANGED: context window uses all loaded messages (capped at _kContextWindow)
  // ─────────────────────────────────────────────────────────────────────────
  List<Map<String, String>> _buildAIContext() {
    final relevant = _msgs
        .where((m) => !m.isError && m.content.isNotEmpty)
        .toList();
    // Take the MOST RECENT _kContextWindow messages so the AI has the
    // freshest context while staying within token limits.
    final window = relevant.length > _kContextWindow
        ? relevant.sublist(relevant.length - _kContextWindow)
        : relevant;
    return window
        .map((m) => {'role': m.isMe ? 'user' : 'assistant', 'content': m.content})
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling — CHANGED: guard against running before history is fully loaded
  // ─────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    // CHANGED: don't poll if history hasn't loaded yet — avoids duplicate msgs
    if (!_historyLoaded || _isSending || _loadingMore) return;
    final convId = _activeConvId;
    if (convId == null || convId.isEmpty) return;

    try {
      final newMsgs = await api.getDMMessages(convId, since: _lastPollTime);
      if (!mounted || newMsgs.isEmpty) return;

      final myId        = await _getMyId();
      final existingIds = _msgs.map((m) => m.id).toSet();
      bool  added       = false;

      setState(() {
        for (final m in newMsgs) {
          final id         = m['id']?.toString()          ?? '';
          final content    = m['content']?.toString()     ?? '';
          final senderType = m['sender_type']?.toString() ?? '';
          final senderId   = m['sender_id']?.toString()   ?? '';
          final isAIMsg    = senderType == 'ai' || senderType == 'system';
          final isMe       = !isAIMsg && myId != null && senderId == myId;

          if (id.isEmpty || existingIds.contains(id)) continue;

          if (isMe) {
            final optIdx = _msgs.indexWhere(
              (msg) => msg.id.startsWith('local_') && msg.isMe && msg.content == content,
            );
            if (optIdx != -1) {
              final old = _msgs[optIdx];
              _msgs[optIdx] = _Msg(
                  id: id, content: old.content,
                  sender: old.sender, avatar: old.avatar,
                  isMe: true, time: old.time);
              existingIds.add(id);
              added = true;
              continue;
            }
          }

          _msgs.add(_msgFromMap(m, myId: myId));
          existingIds.add(id);
          added = true;
        }
      });

      await _savePollTime(newMsgs.last['created_at']?.toString() ?? '');
      if (added) _scrollDown();
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Send routing
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    if (_isAIMode) {
      await _trySendAI(text);
    } else if (_aiJoined && text.startsWith('@ai ')) {
      final aiText = text.substring(4).trim();
      if (aiText.isNotEmpty) {
        _textCtrl.clear();
        await _trySendAI(aiText, viaAIDM: true);
      }
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

  Future<void> _sendAI(
    String text, {
    bool adUnlocked       = false,
    bool viaAIDM          = false,
    bool isContextMessage = false,
  }) async {
    String? convId = viaAIDM ? widget.userId : _aiConvId;

    if ((convId == null || convId.isEmpty) && !viaAIDM) {
      final ok = await _ensureAIConv();
      if (!ok) {
        _addErrorBubble('Could not connect to AI. Check your internet and try again.');
        return;
      }
      convId = _aiConvId;
    }
    if (convId == null || convId.isEmpty) {
      _addErrorBubble('Could not connect to AI. Check your internet and try again.');
      return;
    }

    _textCtrl.clear();
    // CHANGED: build context BEFORE adding the optimistic user bubble so
    //          the current message isn't included in its own context window.
    final contextHistory = _buildAIContext();
    final optimisticId   = 'local_${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      _msgs.add(_Msg(
        id     : optimisticId,
        content: text,
        sender : _cachedMyName ?? 'You',
        avatar : '👤',
        isMe   : true,
      ));
      _aiResponding = true;
    });
    _scrollDown();

    try {
      final res = await api.sendAIMessageInDM(
        convId, text,
        adUnlocked    : adUnlocked,
        contextHistory: contextHistory,
      );

      final aiContent = (res['content'] ?? '').toString().trim();
      if (aiContent.isEmpty) throw Exception('Empty AI response');

      await _savePollTime(DateTime.now().toUtc().toIso8601String());

      if (res['quota'] != null) {
        final q = res['quota'] as Map;
        setState(() {
          _quota['free_used']     = max(_freeUsed, (q['free_used'] as int?) ?? 0);
          _quota['window_expires']= q['window_expires'] ?? _quota['window_expires'];
          _quota['is_premium']    = q['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      } else if (!_isPremium && !_inUnlockedWindow && !isContextMessage) {
        setState(() => _quota['free_used'] = _freeUsed + 1);
        await _saveQuota();
      }

      if (!mounted) return;

      final realUserMsgId = res['user_message_id']?.toString();
      if (realUserMsgId != null && realUserMsgId.isNotEmpty) {
        final idx = _msgs.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _Msg(
              id: realUserMsgId, content: old.content,
              sender: old.sender, avatar: old.avatar,
              isMe: true, time: old.time);
        }
      }

      final aiMsg = _Msg(
        content: aiContent,
        sender : 'RiseUp AI',
        avatar : '🤖',
        isMe   : false,
        isAI   : true,
      );
      setState(() {
        _aiResponding = false;
        _msgs.add(aiMsg);
      });
      _typeMessage(aiMsg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _aiResponding = false);
      if      (e.statusCode == 402) await _showAdGate(text, viaAIDM: viaAIDM);
      else if (e.statusCode == 429) _showDailyLimit();
      else _addErrorBubble('Failed to get a response (${e.statusCode}). Please try again.');
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ConversationScreen] _sendAI error: $e');
      setState(() => _aiResponding = false);
      _addErrorBubble('Could not reach AI right now. Please try again.');
    }
  }

  Future<void> _sendDM(String text) async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;

    _textCtrl.clear();
    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _msgs.add(_Msg(
        id     : optimisticId,
        content: text,
        sender : _cachedMyName ?? 'You',
        avatar : '👤',
        isMe   : true,
      ));
      _dmSending = true;
    });
    _scrollDown();

    try {
      final result = await api.sendDMMessage(widget.userId, text);
      final msgMap = (result['message'] as Map?) ?? result;
      final realId = msgMap['id']?.toString();

      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere((m) => m.id == optimisticId);
          if (idx != -1 && realId != null && realId.isNotEmpty) {
            final old = _msgs[idx];
            _msgs[idx] = _Msg(
                id: realId, content: old.content,
                sender: old.sender, avatar: old.avatar,
                isMe: true, time: old.time);
          }
          _dmSending = false;
        });
        await _savePollTime(DateTime.now().toUtc().toIso8601String());
      }
    } catch (e) {
      debugPrint('[ConversationScreen] _sendDM error: $e');
      if (!mounted) return;
      setState(() {
        final idx = _msgs.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _Msg(
            id: optimisticId, content: old.content,
            sender: old.sender, avatar: old.avatar,
            isMe: true, isError: true, time: old.time,
          );
        }
        _dmSending = false;
      });
    }
  }

  void _addErrorBubble(String msg) {
    if (!mounted) return;
    setState(() => _msgs.add(_Msg(
      content: msg, sender: 'RiseUp AI',
      avatar: '🤖', isMe: false, isAI: true, isError: true,
    )));
    _scrollDown();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Invite AI
  // ─────────────────────────────────────────────────────────────────────────
  void _inviteAI() {
    if (widget.userId.isEmpty || _isAIMode || _aiJoined) return;
    HapticFeedback.lightImpact();
    _doInviteAI();
  }

  Future<void> _doInviteAI() async {
    if (mounted) setState(() => _convInitializing = true);
    try {
      await api.inviteAIToConversation(widget.userId);
      if (!mounted) return;
      setState(() {
        _aiJoined = true;
        _convInitializing = false;
        _msgs.add(_Msg(
          content: '🤖 **RiseUp AI has joined the conversation!**\n\n'
                   'Use **@ai** followed by your question to get wealth advice right here.',
          sender : 'RiseUp AI',
          avatar : '🤖',
          isMe   : false,
          isAI   : true,
        ));
      });
      _scrollDown();
    } catch (e) {
      debugPrint('[ConversationScreen] _doInviteAI error: $e');
      if (!mounted) return;
      setState(() => _convInitializing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not invite AI. Please try again.'),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 2),
      ));
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
    _typingTimer = Timer.periodic(const Duration(milliseconds: 12), (t) {
      if (!mounted) { t.cancel(); return; }
      if (i >= msg.content.length) {
        t.cancel();
        if (mounted) {
          setState(() {
            msg.isTyping    = false;
            msg.displayText = msg.content;
          });
        }
        return;
      }
      i++;
      if (mounted) setState(() => msg.displayText = msg.content.substring(0, i));
      if (i % 5 == 0) HapticFeedback.selectionClick();
      _scrollDown();
    });
  }

  void _scrollDown({bool jump = false}) {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || !_scroll.hasClients) return;
      final maxExt = _scroll.position.maxScrollExtent;
      if (jump) _scroll.jumpTo(maxExt);
      else _scroll.animateTo(maxExt,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied to clipboard ✓'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ad gate / daily limit
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showAdGate(String pendingText, {bool viaAIDM = false}) async {
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
          _quota['free_used']     = 0;
          _quota['ads_today']     = _adsToday + 1;
          _quota['window_expires']= DateTime.now().add(_kWindowDur).toIso8601String();
        });
        await _saveQuota();
        if (mounted) await _sendAI(pendingText, adUnlocked: true, viaAIDM: viaAIDM);
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
      builder: (_) => _DailyLimitSheet(onUpgrade: () {
        Navigator.pop(context);
        context.go('/premium');
      }),
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(isDark, cardColor, borderColor, textColor, subColor),
      body: Column(children: [
        if (_convInitializing)
          LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            color: AppColors.primary.withOpacity(0.5),
            minHeight: 2,
          ),
        if (_aiJoined && !_isAIMode) _AIJoinedBanner(),
        if ((_isAIMode || _aiJoined) && !_isPremium)
          _QuotaRibbon(
            isPremium     : _isPremium,
            inWindow      : _inUnlockedWindow,
            freeUsed      : _freeUsed,
            freeTotal     : _kFreeMessages,
            adsToday      : _adsToday,
            maxAds        : _kMaxAdsPerDay,
            windowExpires : _quota['window_expires'] as String?,
          ),
        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : _msgs.isEmpty
                  ? _buildEmptyState(isDark, subColor, textColor)
                  : ListView.builder(
                      controller : _scroll,
                      padding    : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      // CHANGED: +1 for load-more indicator at top, +1 for typing at bottom
                      itemCount  : _msgs.length +
                                   (_aiResponding ? 1 : 0) +
                                   (_loadingMore  ? 1 : 0),
                      itemBuilder: (_, i) {
                        // CHANGED: first slot = "loading older messages" spinner
                        if (_loadingMore && i == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            )),
                          );
                        }
                        final msgIdx = _loadingMore ? i - 1 : i;
                        if (msgIdx == _msgs.length) {
                          return _buildTypingIndicator(isDark, surfColor, ai: true);
                        }
                        return _buildBubble(_msgs[msgIdx], isDark, textColor, surfColor);
                      },
                    ),
        ),
        _buildInputBar(isDark, cardColor, borderColor, textColor, subColor, surfColor),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AppBar
  // ─────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
      bool isDark, Color card, Color border, Color text, Color sub) {
    final displayName   = _isAIMode ? 'RiseUp AI' : widget.name;
    final displayAvatar = _isAIMode ? '🤖' : widget.avatar;
    final avatarIsUrl   = !_isAIMode && displayAvatar.startsWith('http');

    return AppBar(
      backgroundColor  : card,
      elevation        : 0,
      surfaceTintColor : Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
        onPressed: () =>
            Navigator.of(context).canPop() ? context.pop() : context.go('/messages'),
      ),
      title: Row(children: [
        Stack(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: avatarIsUrl ? null
                  : const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              image: avatarIsUrl
                  ? DecorationImage(
                      image: NetworkImage(widget.avatar), fit: BoxFit.cover)
                  : null,
              shape: BoxShape.circle,
            ),
            child: avatarIsUrl ? null
                : Center(child: Text(displayAvatar,
                    style: const TextStyle(fontSize: 18))),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle,
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
                  child: Text(displayName,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                    overflow: TextOverflow.ellipsis),
                ),
                if (_isAIMode || _aiJoined) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('AI',
                        style: TextStyle(color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              Text(
                _isAIMode ? 'Always online' : 'Online',
                style: const TextStyle(fontSize: 11, color: AppColors.success),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary, size: 13),
                  SizedBox(width: 4),
                  Text('Invite AI', style: TextStyle(
                      color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
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
                  color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        IconButton(
          icon: Icon(Iconsax.call, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Voice calls coming soon 📞'), duration: Duration(seconds: 1))),
        ),
        IconButton(
          icon: Icon(Iconsax.video, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Video calls coming soon 🎥'), duration: Duration(seconds: 1))),
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
  Widget _buildInputBar(bool isDark, Color card, Color border,
      Color text, Color sub, Color surf) {
    final hintText = _isAIMode
        ? 'Ask your wealth mentor...'
        : _aiJoined
            ? 'Message or "@ai ${widget.name}"...'
            : 'Message ${widget.name}...';

    return Container(
      decoration: BoxDecoration(
          color: card, border: Border(top: BorderSide(color: border))),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(children: [
        IconButton(
          icon: Icon(Iconsax.image, color: sub, size: 22),
          onPressed: () async {
            final file =
                await ImagePicker().pickImage(source: ImageSource.gallery);
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
            enabled: !_isSending,
            decoration: InputDecoration(
              hintText : hintText,
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled   : true, fillColor: surf,
              border   : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: _isSending ? null : (_) => _onSend(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isSending
              ? null
              : () { HapticFeedback.lightImpact(); _onSend(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isSending
                    ? [Colors.grey.shade500, Colors.grey.shade500]
                    : [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: _isSending
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
      _Msg m, bool isDark, Color textColor, Color surfColor) {
    final aiBg    = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final errorBg = isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF0F0);
    final avatarIsUrl = m.avatar.startsWith('http') && m.avatar.length > 10;

    final bubbleBg = m.isError
        ? errorBg
        : m.isMe
            ? AppColors.userBubble
            : aiBg;

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
                Text(m.sender,
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: m.isAI ? AppColors.primary : AppColors.warning,
                    )),
                if (m.isAI) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.auto_awesome,
                      size: 10, color: AppColors.primary),
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
                  child: avatarIsUrl ? null
                      : Center(child: Text(m.avatar,
                          style: const TextStyle(fontSize: 14))),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onTap: (m.isError && m.isMe)
                      ? () async {
                          setState(() => _msgs.remove(m));
                          await _sendDM(m.content);
                        }
                      : null,
                  onLongPress: () => _showBubbleMenu(context, m),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft    : const Radius.circular(18),
                        topRight   : const Radius.circular(18),
                        bottomLeft : Radius.circular(m.isMe ? 18 : 4),
                        bottomRight: Radius.circular(m.isMe ? 4  : 18),
                      ),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6, offset: const Offset(0, 2),
                      )],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectionArea(
                          child: (m.isMe || !m.isAI)
                              ? Text(m.displayText,
                                  style: TextStyle(
                                    color: m.isMe ? Colors.white : textColor,
                                    fontSize: 14, height: 1.5,
                                  ))
                              : MarkdownBody(
                                  data: m.displayText,
                                  styleSheet: MarkdownStyleSheet(
                                    p     : TextStyle(
                                      color: isDark
                                          ? const Color(0xFFE8E8F0)
                                          : Colors.black87,
                                      fontSize: 14, height: 1.55,
                                    ),
                                    strong: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryLight,
                                    ),
                                    code  : TextStyle(
                                      fontFamily: 'monospace',
                                      backgroundColor: isDark
                                          ? const Color(0xFF2A2A3E)
                                          : Colors.grey.shade200,
                                      fontSize: 13,
                                    ),
                                    codeblockDecoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0D1117)
                                          : Colors.grey.shade900,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    codeblockPadding: const EdgeInsets.all(12),
                                  ),
                                ),
                        ),
                        if (m.isError && m.isMe)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.error_outline,
                                  size: 12, color: AppColors.error),
                              const SizedBox(width: 4),
                              Text('Failed · Tap to retry',
                                  style: TextStyle(
                                    fontSize: 10, color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  )),
                            ]),
                          ),
                      ],
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
                right: m.isMe ? 4 : 0),
            child: Text(_formatTime(m.time),
                style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white24 : Colors.black26)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.08, curve: Curves.easeOut);
  }

  void _showBubbleMenu(BuildContext context, _Msg m) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg     = isDark ? AppColors.bgCard : Colors.white;
        final text   = isDark ? Colors.white : Colors.black87;

        final codeBlocks = RegExp(r'```[\s\S]*?```')
            .allMatches(m.content)
            .map((e) => e
                .group(0)!
                .replaceAll(RegExp(r'^```\w*\n?|```$'), '')
                .trim())
            .where((s) => s.isNotEmpty)
            .toList();

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 4),
            _menuItem(Icons.copy_rounded, 'Copy message', text, () {
              Navigator.pop(context);
              _copyToClipboard(m.content);
            }),
            if (codeBlocks.isNotEmpty)
              _menuItem(Icons.code_rounded, 'Copy code', text, () {
                Navigator.pop(context);
                _copyToClipboard(codeBlocks.join('\n\n'));
              }),
            _menuItem(Icons.select_all_rounded, 'Select text', text, () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Hold and drag on the message to select text'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ));
            }),
            if (!m.isMe && m.isAI)
              _menuItem(Icons.share_rounded, 'Share insight', text, () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(
                    text: '💡 RiseUp AI insight:\n\n${m.content}'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Insight copied — ready to share! ✓'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ]),
        );
      },
    );
  }

  Widget _menuItem(IconData icon, String label, Color textColor,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(label,
          style: TextStyle(
              color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _buildTypingIndicator(bool isDark, Color surfColor, {required bool ai}) {
    final avatarEmoji = ai ? '🤖' : widget.avatar;
    final avatarIsUrl = !ai && avatarEmoji.startsWith('http');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: avatarIsUrl ? null
                : const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
            image: avatarIsUrl
                ? DecorationImage(
                    image: NetworkImage(avatarEmoji), fit: BoxFit.cover)
                : null,
            shape: BoxShape.circle,
          ),
          child: avatarIsUrl ? null
              : Center(child: Text(avatarEmoji,
                  style: const TextStyle(fontSize: 14))),
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

  Widget _buildEmptyState(bool isDark, Color subColor, Color textColor) {
    final bg = isDark ? Colors.black : Colors.white;

    if (_isAIMode) {
      final firstName = _cachedMyName?.split(' ').first ?? '';
      final prompts   = [
        '💰  How do I make my first \$1,000 online?',
        '📈  Best beginner investments in 2025?',
        '🚀  Top side hustles I can start today?',
        '🧠  How do I improve my money mindset?',
      ];

      return Container(
        color: bg,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 40))),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 20),
            Text('Your AI Wealth Mentor',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              firstName.isNotEmpty
                  ? 'Hi $firstName! Ask anything about money,\ninvesting, or building financial freedom.'
                  : 'Ask anything about money, investing, or\nbuilding financial freedom.',
              style: TextStyle(fontSize: 14, color: subColor, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text('Try asking:',
                style: TextStyle(
                    fontSize: 12,
                    color: subColor,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...prompts.map((p) => GestureDetector(
              onTap: () { _textCtrl.text = p.substring(3).trim(); _onSend(); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.18)),
                ),
                child: Text(p,
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4)),
              ).animate().fadeIn(
                  delay: Duration(milliseconds: prompts.indexOf(p) * 80)),
            )),
          ],
        ),
      );
    }

    return Container(
      color: bg,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('👋', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('Say hello!',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor)),
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

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
           '${local.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (unchanged from v11)
// ─────────────────────────────────────────────────────────────────────────────

class _AIJoinedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: AppColors.primary.withOpacity(0.08),
    child: const Row(children: [
      Icon(Icons.auto_awesome, color: AppColors.primary, size: 14),
      SizedBox(width: 8),
      Text('RiseUp AI is in this conversation',
          style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w500)),
    ]),
  );
}

class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inWindow;
  final int freeUsed, freeTotal, adsToday, maxAds;
  final String? windowExpires;

  const _QuotaRibbon({
    required this.isPremium,  required this.inWindow,
    required this.freeUsed,   required this.freeTotal,
    required this.adsToday,   required this.maxAds,
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
      return _ribbon(
          Icons.chat_bubble_outline_rounded, AppColors.primary,
          '$remaining free AI message${remaining == 1 ? '' : 's'} remaining',
          AppColors.primary.withOpacity(0.06));
    }
    return const SizedBox.shrink();
  }

  Widget _ribbon(IconData icon, Color color, String label, Color bg) =>
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: bg,
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
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

class _AdGateSheet extends StatelessWidget {
  final int freeUsed, adsToday, maxAds, windowHours;

  const _AdGateSheet({
    required this.freeUsed,  required this.adsToday,
    required this.maxAds,    required this.windowHours,
  });

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? AppColors.bgCard : Colors.white;
    final text      = isDark ? Colors.white     : Colors.black87;
    final sub       = isDark ? Colors.white60   : Colors.black54;
    final remaining = maxAds - adsToday;

    return Container(
      decoration: BoxDecoration(
          color: bg,
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
        Container(
          width: 72, height: 72,
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
                fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used your $freeUsed free AI messages.\n"
          'Watch a short ad to unlock ${windowHours}h of unlimited AI mentoring.',
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text('$remaining unlock${remaining == 1 ? '' : 's'} remaining today',
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
    final text   = isDark ? Colors.white     : Colors.black87;
    final sub    = isDark ? Colors.white60   : Colors.black54;

    return Container(
      decoration: BoxDecoration(
          color: bg,
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
        Text('Daily Limit Reached',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          "You've used all your free AI unlocks for today.\n"
          'Your limit resets at midnight UTC.',
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
            Text(_countdown,
                style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w800, color: text,
                    fontFamily: 'monospace', letterSpacing: 2)),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
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
