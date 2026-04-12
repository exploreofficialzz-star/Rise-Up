// ignore_for_file: deprecated_member_use
// frontend/lib/screens/messages/conversation_screen.dart
// Production v14.3 — Quota v2 (3hr cycle lock + daily lock), msg cache, AI invite removed from DMs

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
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_constants.dart';
import '../../services/ad_service.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const int _kFreeMessages        = 3;
const int _kAdsPerCycle         = 2;
const int _kMsgsPerCycle        = 3;
const int _kMaxResponses        = 30;
const Duration _kCycleLockoutDur = Duration(hours: 3);
const Duration _kDailyLockoutDur = Duration(hours: 24);

const String _kQuotaPrefsKey      = 'riseup_ai_quota_v4';
const String _kAiConvIdKey        = 'riseup_ai_conv_id_v2';
const String _kGreetedPrefix      = 'riseup_ai_greeted_v2_';
const String _kPollTimePrefix     = 'riseup_poll_time_v1_';
const String _kMsgCachePrefix     = 'riseup_msgs_cache_v1_';
const String _kMsgCacheTimePrefix = 'riseup_msgs_ctime_v1_';

const int _kContextWindow   = 50;
const int _kHistoryPageSize = 100;

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
    this.isAI    = false,
    this.isError = false,
    DateTime? time,
  })  : id          = id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        displayText = content,
        isTyping    = false,
        time        = time ?? DateTime.now();

  String get fingerprint => '${isMe ? "u" : "a"}:${content.trim().hashCode}';
}

enum _QuotaResult { allowed, showAdGate, cycleLockout, hardLockout }

// ─────────────────────────────────────────────────────────────────────────────
// ConversationScreen widget
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  final String userId;
  final String name;
  final String avatar;
  final bool   isAI;
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

  bool _historyLoaded    = false;
  bool _aiResponding     = false;
  bool _dmSending        = false;
  bool _convInitializing = false;
  bool _scrollLocked     = false;
  bool _loadingMore      = false;
  bool _hasMoreHistory   = true;

  String? _aiConvId;
  String? _lastPollTime;
  String? _cachedMyId;
  String? _cachedMyName;

  Timer? _typingTimer;
  Timer? _pollTimer;

  Map<String, dynamic> _quota = {
    'free_used'           : 0,
    'cycle_ads'           : 0,
    'cycle_msgs'          : 0,
    'total_responses'     : 0,
    'cycle_lockout_until' : null,
    'daily_lockout_until' : null,
    'is_premium'          : false,
  };

  bool get _isAIMode    => widget.isAI || widget.userId == 'ai';
  bool get _isSending   => _aiResponding || _dmSending;
  String? get _activeConvId => _isAIMode ? _aiConvId : widget.userId;

  bool get _isPremium       => _quota['is_premium'] == true;
  int  get _freeUsed        => (_quota['free_used']       as int?) ?? 0;
  int  get _cycleAds        => (_quota['cycle_ads']       as int?) ?? 0;
  int  get _cycleMsgs       => (_quota['cycle_msgs']      as int?) ?? 0;
  int  get _totalResponses  => (_quota['total_responses'] as int?) ?? 0;

  bool get _inDailyLockout {
    final exp = _quota['daily_lockout_until'] as String?;
    if (exp == null) return false;
    final dt = DateTime.tryParse(exp);
    if (dt == null) return false;
    if (DateTime.now().isAfter(dt)) {
      _quota['daily_lockout_until'] = null;
      _quota['total_responses']     = 0;
      _quota['cycle_lockout_until'] = null;
      _quota['cycle_ads']           = 0;
      _quota['cycle_msgs']          = 0;
      _saveQuota();
      return false;
    }
    return true;
  }

  bool get _inCycleLockout {
    if (_inDailyLockout) return false;
    final exp = _quota['cycle_lockout_until'] as String?;
    if (exp == null) return false;
    final dt = DateTime.tryParse(exp);
    if (dt == null) return false;
    if (DateTime.now().isAfter(dt)) {
      _quota['cycle_lockout_until'] = null;
      _quota['cycle_ads']           = 0;
      _quota['cycle_msgs']          = 0;
      _saveQuota();
      return false;
    }
    return true;
  }

  bool get _cycleActive =>
      _cycleAds >= _kAdsPerCycle && _cycleMsgs < _kMsgsPerCycle;

  // ─────────────────────────────────────────────────────────────────────────
  // Cache helpers
  // ─────────────────────────────────────────────────────────────────────────
  String get _convCacheKey =>
      '$_kMsgCachePrefix${_isAIMode ? 'ai' : widget.userId}';
  String get _convCacheTimeKey =>
      '$_kMsgCacheTimePrefix${_isAIMode ? 'ai' : widget.userId}';

  Future<void> _saveMessageCache(List<_Msg> msgs) async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final encoded = jsonEncode(msgs
          .where((m) => !m.isError && m.content.isNotEmpty)
          .map((m) => {
                'id'     : m.id,
                'content': m.content,
                'sender' : m.sender,
                'avatar' : m.avatar,
                'isMe'   : m.isMe,
                'isAI'   : m.isAI,
                'time'   : m.time.toIso8601String(),
              })
          .toList());
      await prefs.setString(_convCacheKey, encoded);
      await prefs.setString(
          _convCacheTimeKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<List<_Msg>?> _loadMessageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_convCacheKey);
      if (raw == null) return null;
      final list  = jsonDecode(raw) as List;
      return list
          .map((m) => _Msg(
                id     : m['id']?.toString(),
                content: m['content']?.toString() ?? '',
                sender : m['sender']?.toString()  ?? '',
                avatar : m['avatar']?.toString()  ?? '',
                isMe   : m['isMe'] == true,
                isAI   : m['isAI'] == true,
                time   : DateTime.tryParse(m['time']?.toString() ?? '')
                             ?.toLocal(),
              ))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bootstrap();
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

  void _onScroll() {
    if (!_scroll.hasClients || _scrollLocked) return;
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kQuotaPrefsKey);
      if (raw != null) {
        final local = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (mounted) {
          setState(() {
            _quota['free_used']           = (local['free_used']           as int?) ?? 0;
            _quota['cycle_ads']           = (local['cycle_ads']           as int?) ?? 0;
            _quota['cycle_msgs']          = (local['cycle_msgs']          as int?) ?? 0;
            _quota['total_responses']     = (local['total_responses']     as int?) ?? 0;
            _quota['cycle_lockout_until'] =  local['cycle_lockout_until'] as String?;
            _quota['daily_lockout_until'] =  local['daily_lockout_until'] as String?;
          });
        }
      }
    } catch (_) {}
    try {
      final remote = await api.getAIQuota();
      if (mounted) {
        setState(() {
          _quota['free_used']  = max(_freeUsed, (remote['free_used'] as int?) ?? 0);
          _quota['is_premium'] = remote['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      }
    } catch (_) {}
  }

  Future<void> _saveQuota() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQuotaPrefsKey, jsonEncode({
        'free_used'           : _freeUsed,
        'cycle_ads'           : _cycleAds,
        'cycle_msgs'          : _cycleMsgs,
        'total_responses'     : _totalResponses,
        'cycle_lockout_until' : _quota['cycle_lockout_until'],
        'daily_lockout_until' : _quota['daily_lockout_until'],
      }));
    } catch (_) {}
  }

  _QuotaResult _checkAIQuota() {
    if (_isPremium)      return _QuotaResult.allowed;
    if (_inDailyLockout) return _QuotaResult.hardLockout;
    if (_inCycleLockout) return _QuotaResult.cycleLockout;
    if (_freeUsed < _kFreeMessages) return _QuotaResult.allowed;
    if (_cycleActive)    return _QuotaResult.allowed;
    return _QuotaResult.showAdGate;
  }

  Future<void> _consumeAdMessage() async {
    final newCycleMsgs      = _cycleMsgs + 1;
    final newTotalResponses = _totalResponses + 1;
    final cycleExhausted    = newCycleMsgs >= _kMsgsPerCycle;
    final hitDailyMax       = newTotalResponses >= _kMaxResponses;

    setState(() {
      _quota['cycle_msgs']      = newCycleMsgs;
      _quota['total_responses'] = newTotalResponses;

      if (hitDailyMax) {
        _quota['daily_lockout_until']  =
            DateTime.now().add(_kDailyLockoutDur).toIso8601String();
        _quota['cycle_lockout_until']  = null;
        _quota['cycle_ads']            = 0;
        _quota['cycle_msgs']           = 0;
      } else if (cycleExhausted) {
        _quota['cycle_lockout_until']  =
            DateTime.now().add(_kCycleLockoutDur).toIso8601String();
        _quota['cycle_ads']            = 0;
        _quota['cycle_msgs']           = 0;
      }
    });
    await _saveQuota();
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
      debugPrint('[Conv] _ensureAIConv error: $e');
    }

    if (mounted) setState(() => _convInitializing = false);
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_historyLoaded) return;
    await _fetchMyInfo();

    // ── Step 1: show cached messages instantly ──
    final cached = await _loadMessageCache();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _msgs.clear();
        _msgs.addAll(cached);
        _historyLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollDown(jump: true);
      });
    }

    // ── Step 2: fetch fresh data in background ──
    try {
      if (_isAIMode) {
        await _loadAIHistory();
      } else {
        await _loadDMHistory();
      }
    } catch (e) {
      debugPrint('[Conv] _loadHistory error: $e');
    } finally {
      if (mounted && !_historyLoaded) {
        setState(() => _historyLoaded = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollDown(jump: true);
        });
      }
    }

    if (_isAIMode &&
        widget.postContext != null &&
        widget.postContext!.isNotEmpty) {
      final author = (widget.postAuthor?.isNotEmpty == true)
          ? widget.postAuthor!
          : 'a community member';
      await _sendAI(
        'I want to discuss a post from $author: "${widget.postContext}"\n\n'
        'Give me a quick wealth insight or action tip about this.',
        adUnlocked      : false,
        isContextMessage: true,
      );
    }
  }

  Future<void> _fetchMyInfo() async {
    try {
      _cachedMyId ??= await api.getUserId();
      if (_cachedMyId != null) {
        final p   = await api.getUserProfile(_cachedMyId!);
        _cachedMyName = (p['full_name']  as String?)?.trim();
        if (_cachedMyName == null || _cachedMyName!.isEmpty) {
          _cachedMyName = (p['username'] as String?)?.trim();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAIHistory() async {
    await _ensureAIConv();
    if (_aiConvId == null || _aiConvId!.isEmpty) return;

    try {
      final msgs = await api.getDMMessages(_aiConvId!, limit: _kHistoryPageSize);
      if (!mounted) return;

      if (msgs.isNotEmpty) {
        final hasAIMsg = msgs.any((m) {
          final st = (m['sender_type'] as String?) ?? '';
          return st == 'ai' || st == 'system';
        });
        if (msgs.length > 5 && !hasAIMsg) {
          debugPrint('[Conv] AI conv validation failed — resetting cached ID');
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kAiConvIdKey);
          _aiConvId = null;
          final ok = await _ensureAIConv();
          if (!ok || !mounted) return;
          final fresh =
              await api.getDMMessages(_aiConvId!, limit: _kHistoryPageSize);
          if (!mounted) return;
          if (fresh.isEmpty) {
            _hasMoreHistory = false;
            await _maybeShowFirstTimeGreeting();
          } else {
            setState(() {
              _msgs.clear();
              for (final m in fresh) _msgs.add(_msgFromMap(m, myId: _cachedMyId));
              _hasMoreHistory = fresh.length >= _kHistoryPageSize;
            });
            await _savePollTime(fresh.last['created_at']?.toString() ?? '');
            await _saveMessageCache(_msgs);
          }
          return;
        }
        setState(() {
          _msgs.clear();
          for (final m in msgs) _msgs.add(_msgFromMap(m, myId: _cachedMyId));
          _hasMoreHistory = msgs.length >= _kHistoryPageSize;
        });
        await _savePollTime(msgs.last['created_at']?.toString() ?? '');
        await _saveMessageCache(_msgs);
      } else {
        _hasMoreHistory = false;
        await _maybeShowFirstTimeGreeting();
      }
    } catch (e) {
      debugPrint('[Conv] _loadAIHistory error: $e');
    }
  }

  Future<void> _loadDMHistory() async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;

    try {
      final msgs =
          await api.getDMMessages(widget.userId, limit: _kHistoryPageSize);
      if (!mounted || msgs.isEmpty) {
        _hasMoreHistory = false;
        return;
      }

      setState(() {
        _msgs.clear();
        for (final m in msgs) {
          final senderType = m['sender_type']?.toString() ?? '';
          if (senderType == 'ai' || senderType == 'system') continue;
          _msgs.add(_msgFromMap(m, myId: _cachedMyId));
        }
        _hasMoreHistory = msgs.length >= _kHistoryPageSize;
      });
      await _savePollTime(msgs.last['created_at']?.toString() ?? '');
      await _saveMessageCache(_msgs);
    } catch (e) {
      debugPrint('[Conv] _loadDMHistory error: $e');
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMore || !_hasMoreHistory || _msgs.isEmpty) return;

    setState(() => _loadingMore = true);

    try {
      final convId = _activeConvId;
      if (convId == null || convId.isEmpty) {
        setState(() => _loadingMore = false);
        return;
      }

      final olderMsgs = await api.getDMMessages(
        convId,
        limit: _kHistoryPageSize,
      );

      if (!mounted) return;

      if (olderMsgs.isEmpty || olderMsgs.length < _kHistoryPageSize) {
        setState(() => _hasMoreHistory = false);
      } else {
        final myId    = await _getMyId();
        final newMsgs = <_Msg>[];
        for (final m in olderMsgs) {
          final senderType = m['sender_type']?.toString() ?? '';
          if (!_isAIMode &&
              (senderType == 'ai' || senderType == 'system')) continue;
          newMsgs.add(_msgFromMap(m, myId: myId));
        }
        setState(() => _msgs.insertAll(0, newMsgs));
      }
    } catch (e) {
      debugPrint('[Conv] _loadMoreHistory error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // First-time greeting
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _maybeShowFirstTimeGreeting() async {
    if (_aiConvId == null) return;
    final greetKey = '$_kGreetedPrefix$_aiConvId';
    try {
      final prefs       = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(greetKey) ?? false;
      if (alreadyDone) return;

      await prefs.setBool(greetKey, true);

      final firstName = _cachedMyName?.split(' ').first ?? 'there';
      final greeting  =
          'Hey $firstName 👋 Welcome to RiseUp!\n\n'
          "I'm your AI Wealth Mentor — here to help you build wealth, grow income, "
          'and level up your financial game. 💰\n\n'
          'Ask me anything about investing, side hustles, money mindset, or '
          'how to reach your next income goal. Let\'s get started! 🚀';

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

      await _savePollTime(DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      debugPrint('[Conv] greeting error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message helpers
  // ─────────────────────────────────────────────────────────────────────────
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

  List<Map<String, String>> _buildAIContext() {
    final relevant = _msgs.where((m) => !m.isError && m.content.isNotEmpty).toList();
    final window   = relevant.length > _kContextWindow
        ? relevant.sublist(relevant.length - _kContextWindow)
        : relevant;
    return window
        .map((m) => {'role': m.isMe ? 'user' : 'assistant', 'content': m.content})
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling
  // ─────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_historyLoaded || _isSending || _loadingMore) return;
    final convId = _activeConvId;
    if (convId == null || convId.isEmpty) return;

    try {
      final newMsgs = await api.getDMMessages(convId, since: _lastPollTime);
      if (!mounted || newMsgs.isEmpty) return;

      final myId         = await _getMyId();
      final existingIds  = _msgs.map((m) => m.id).toSet();
      final fingerprints = _msgs.map((m) => m.fingerprint).toSet();
      bool  added        = false;

      setState(() {
        for (final m in newMsgs) {
          final id         = m['id']?.toString()          ?? '';
          final content    = m['content']?.toString()     ?? '';
          final senderType = m['sender_type']?.toString() ?? '';
          final senderId   = m['sender_id']?.toString()   ?? '';
          final isAIMsg    = senderType == 'ai' || senderType == 'system';
          final isMe       = !isAIMsg && myId != null && senderId == myId;

          if (!_isAIMode && isAIMsg) continue;
          if (id.isEmpty || existingIds.contains(id)) continue;

          final fp = '${isMe ? "u" : "a"}:${content.trim().hashCode}';
          if (fingerprints.contains(fp)) continue;

          if (isMe) {
            final optIdx = _msgs.indexWhere(
              (msg) =>
                  msg.id.startsWith('local_') &&
                  msg.isMe &&
                  msg.content == content,
            );
            if (optIdx != -1) {
              final old = _msgs[optIdx];
              _msgs[optIdx] = _Msg(
                  id     : id,
                  content: old.content,
                  sender : old.sender,
                  avatar : old.avatar,
                  isMe   : true,
                  time   : old.time);
              existingIds.add(id);
              fingerprints.add(fp);
              added = true;
              continue;
            }
          }

          _msgs.add(_msgFromMap(m, myId: myId));
          existingIds.add(id);
          fingerprints.add(fp);
          added = true;
        }
      });

      if (newMsgs.isNotEmpty) {
        await _savePollTime(newMsgs.last['created_at']?.toString() ?? '');
      }
      if (added) {
        _scrollDown();
        await _saveMessageCache(_msgs);
      }
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
    } else {
      await _sendDM(text);
    }
  }

  Future<void> _trySendAI(String text, {bool viaAIDM = false}) async {
    final result = _checkAIQuota();
    switch (result) {
      case _QuotaResult.showAdGate:
        await _showAdGate(text, viaAIDM: viaAIDM);
        return;
      case _QuotaResult.cycleLockout:
        _showCycleLockoutSheet();
        return;
      case _QuotaResult.hardLockout:
        _showDailyLockoutSheet();
        return;
      case _QuotaResult.allowed:
        break;
    }
    await _sendAI(text, adUnlocked: false, viaAIDM: viaAIDM);
  }

  Future<void> _sendAI(
    String text, {
    bool adUnlocked       = false,
    bool viaAIDM          = false,
    bool isContextMessage = false,
    bool retried          = false,
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
          _quota['free_used']  = max(_freeUsed, (q['free_used'] as int?) ?? 0);
          _quota['is_premium'] = q['is_premium'] ?? _quota['is_premium'];
        });
        await _saveQuota();
      } else if (!_isPremium && !isContextMessage) {
        if (_freeUsed < _kFreeMessages) {
          final newTotal = _totalResponses + 1;
          setState(() {
            _quota['free_used']       = _freeUsed + 1;
            _quota['total_responses'] = newTotal;
            if (newTotal >= _kMaxResponses) {
              _quota['daily_lockout_until'] =
                  DateTime.now().add(_kDailyLockoutDur).toIso8601String();
            }
          });
          await _saveQuota();
        } else if (adUnlocked || _cycleActive) {
          await _consumeAdMessage();
        }
      }

      if (!mounted) return;

      final realUserMsgId = res['user_message_id']?.toString();
      if (realUserMsgId != null && realUserMsgId.isNotEmpty) {
        final idx = _msgs.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _Msg(
              id     : realUserMsgId,
              content: old.content,
              sender : old.sender,
              avatar : old.avatar,
              isMe   : true,
              time   : old.time);
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
      await _saveMessageCache(_msgs);

    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiResponding = false;
        _msgs.removeWhere((m) => m.id == optimisticId);
      });

      if (e.statusCode == 402) {
        await _showAdGate(text, viaAIDM: viaAIDM);
      } else if (e.statusCode == 429) {
        _showDailyLockoutSheet();
      } else if (e.statusCode == 403 && !retried) {
        debugPrint('[Conv] 403 — resetting AI conv and retrying once');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kAiConvIdKey);
        _aiConvId = null;
        final ok = await _ensureAIConv();
        if (ok && mounted) {
          await _sendAI(
            text,
            adUnlocked      : adUnlocked,
            viaAIDM         : viaAIDM,
            isContextMessage: isContextMessage,
            retried         : true,
          );
        } else {
          _addErrorBubble('Could not connect to AI. Please try again.');
        }
      } else {
        _addErrorBubble(
            'Failed to get AI response (${e.statusCode}). Please try again.');
      }

    } catch (e) {
      if (!mounted) return;
      debugPrint('[Conv] _sendAI error: $e');
      setState(() {
        _aiResponding = false;
        _msgs.removeWhere((m) => m.id == optimisticId);
      });
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
                id     : realId,
                content: old.content,
                sender : old.sender,
                avatar : old.avatar,
                isMe   : true,
                time   : old.time);
          }
          _dmSending = false;
        });
        await _savePollTime(DateTime.now().toUtc().toIso8601String());
        await _saveMessageCache(_msgs);
      }
    } catch (e) {
      debugPrint('[Conv] _sendDM error: $e');
      if (!mounted) return;
      setState(() {
        final idx = _msgs.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _Msg(
            id     : optimisticId,
            content: old.content,
            sender : old.sender,
            avatar : old.avatar,
            isMe   : true,
            isError: true,
            time   : old.time,
          );
        }
        _dmSending = false;
      });
    }
  }

  void _addErrorBubble(String msg) {
    if (!mounted) return;
    setState(() => _msgs.add(_Msg(
      content: msg,
      sender : 'RiseUp AI',
      avatar : '🤖',
      isMe   : false,
      isAI   : true,
      isError: true,
    )));
    _scrollDown();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Typing animation
  // ─────────────────────────────────────────────────────────────────────────
  void _typeMessage(_Msg msg) {
    msg.isTyping    = true;
    msg.displayText = '';
    int i = 0;

    if (mounted) setState(() => _scrollLocked = true);

    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 6), (t) {
      if (!mounted) { t.cancel(); return; }

      if (i >= msg.content.length) {
        t.cancel();
        if (mounted) {
          setState(() {
            msg.isTyping    = false;
            msg.displayText = msg.content;
            _scrollLocked   = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
        }
        return;
      }

      i++;
      if (mounted) setState(() => msg.displayText = msg.content.substring(0, i));
      if (i % 50 == 0) HapticFeedback.selectionClick();
      if (i % 10 == 0) _scrollDown();
    });
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final maxExt = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(maxExt);
      } else {
        _scroll.animateTo(maxExt,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // In-app link handler
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Smart copy
  // ─────────────────────────────────────────────────────────────────────────
  void _copyToClipboard(String text, {String label = 'Copied'}) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label ✓'),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.success,
    ));
  }

  List<Map<String, dynamic>> _detectSections(_Msg m) {
    final sections = <Map<String, dynamic>>[];
    final content  = m.content;

    final codeMatches = RegExp(r'```(\w*)\n?([\s\S]*?)```').allMatches(content);
    for (final match in codeMatches) {
      final lang = match.group(1)?.trim() ?? '';
      final code = match.group(2)?.trim() ?? '';
      if (code.isNotEmpty) {
        sections.add({
          'icon' : Icons.code_rounded,
          'label': lang.isNotEmpty ? 'Copy $lang code' : 'Copy code',
          'text' : code,
          'type' : 'code',
        });
      }
    }

    final urls =
        RegExp(r'https?://[^\s\]\)>"]+', caseSensitive: false).allMatches(content);
    for (final u in urls) {
      sections.add({
        'icon' : Icons.open_in_browser_rounded,
        'label': 'Open link',
        'text' : u.group(0)!,
        'type' : 'link',
      });
    }

    if (RegExp(r'^\d+\.\s', multiLine: true).hasMatch(content) ||
        RegExp(r'^[-•*]\s', multiLine: true).hasMatch(content)) {
      sections.add({
        'icon' : Icons.format_list_bulleted_rounded,
        'label': 'Copy full list',
        'text' : content,
        'type' : 'list',
      });
    }

    if (content.length > 300 && codeMatches.isEmpty) {
      sections.add({
        'icon' : Icons.article_rounded,
        'label': 'Copy as article',
        'text' : content,
        'type' : 'article',
      });
    }

    if (RegExp(r'[\w.]+@[\w.]+\.\w+').hasMatch(content) ||
        RegExp(r'\+?\d[\d\s\-\(\)]{7,}').hasMatch(content)) {
      sections.add({
        'icon' : Icons.contacts_rounded,
        'label': 'Copy contact info',
        'text' : content,
        'type' : 'contact',
      });
    }

    return sections;
  }

  void _showBubbleMenu(BuildContext ctx, _Msg m) {
    HapticFeedback.mediumImpact();
    final sections = _detectSections(m);

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg     = isDark ? AppColors.bgCard : Colors.white;
        final text   = isDark ? Colors.white     : Colors.black87;

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 4),

              _menuItem(Icons.copy_rounded, 'Copy message', text, () {
                Navigator.pop(ctx);
                _copyToClipboard(m.content, label: 'Message copied');
              }),

              for (final s in sections)
                if (s['type'] == 'link')
                  _menuItem(s['icon'] as IconData, s['label'] as String, text, () {
                    Navigator.pop(ctx);
                    _openLink(s['text'] as String);
                  })
                else
                  _menuItem(s['icon'] as IconData, s['label'] as String, text, () {
                    Navigator.pop(ctx);
                    _copyToClipboard(s['text'] as String,
                        label: s['label'] as String);
                  }),

              _menuItem(Icons.select_all_rounded, 'Select text', text, () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Hold and drag to select text'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ));
              }),

              if (!m.isMe && m.isAI)
                _menuItem(Icons.share_rounded, 'Share insight', text, () {
                  Navigator.pop(ctx);
                  _copyToClipboard(
                    '💡 RiseUp AI Wealth Insight:\n\n${m.content}\n\n— via RiseUp',
                    label: 'Insight copied — ready to share!',
                  );
                }),

              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
            ]),
          ),
        );
      },
    );
  }

  Widget _menuItem(
          IconData icon, String label, Color textColor, VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 20),
        title: Text(label,
            style: TextStyle(
                color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
        onTap: onTap,
        dense: true,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Ad gate & lockout sheets
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showAdGate(String pendingText, {bool viaAIDM = false}) async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdGateSheet(
        cycleAdsWatched: _cycleAds,
        adsPerCycle    : _kAdsPerCycle,
        msgsPerCycle   : _kMsgsPerCycle,
        totalResponses : _totalResponses,
        maxResponses   : _kMaxResponses,
        onAdWatched    : () async {
          if (!mounted) return;
          setState(() => _quota['cycle_ads'] = _cycleAds + 1);
          await _saveQuota();
        },
      ),
    );
    if (!mounted || success != true) return;
    await _sendAI(pendingText, adUnlocked: true, viaAIDM: viaAIDM);
  }

  void _showCycleLockoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LockoutSheet(
        lockoutUntil: (_quota['cycle_lockout_until'] as String?) ?? '',
        isDaily     : false,
        onUpgrade   : () { Navigator.pop(context); context.go('/premium'); },
      ),
    );
  }

  void _showDailyLockoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LockoutSheet(
        lockoutUntil: (_quota['daily_lockout_until'] as String?) ?? '',
        isDaily     : true,
        onUpgrade   : () { Navigator.pop(context); context.go('/premium'); },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black        : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard    : Colors.white;
    final surfColor   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white        : Colors.black87;
    final subColor    = isDark ? Colors.white54      : Colors.black45;

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
        if (_isAIMode && !_isPremium)
          _QuotaRibbon(
            isPremium      : _isPremium,
            inDailyLockout : _inDailyLockout,
            inCycleLockout : _inCycleLockout,
            freeUsed       : _freeUsed,
            freeTotal      : _kFreeMessages,
            cycleAds       : _cycleAds,
            adsPerCycle    : _kAdsPerCycle,
            cycleMsgs      : _cycleMsgs,
            msgsPerCycle   : _kMsgsPerCycle,
            totalResponses : _totalResponses,
            maxResponses   : _kMaxResponses,
            cycleLockoutUntil: _quota['cycle_lockout_until'] as String?,
            dailyLockoutUntil: _quota['daily_lockout_until'] as String?,
          ),
        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : _msgs.isEmpty
                  ? _buildEmptyState(isDark, subColor, textColor)
                  : ListView.builder(
                      controller: _scroll,
                      physics: _scrollLocked
                          ? const NeverScrollableScrollPhysics()
                          : const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      reverse: false,
                      itemCount: _msgs.length +
                          (_aiResponding ? 1 : 0) +
                          (_loadingMore  ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_loadingMore && i == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary),
                              ),
                            ),
                          );
                        }
                        final msgIdx = _loadingMore ? i - 1 : i;
                        if (msgIdx == _msgs.length) {
                          return _buildTypingIndicator(isDark, surfColor);
                        }
                        return _buildBubble(
                            _msgs[msgIdx], isDark, textColor, surfColor);
                      },
                    ),
        ),
        _buildInputBar(
            isDark, cardColor, borderColor, textColor, subColor, surfColor),
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
      backgroundColor : card,
      elevation       : 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
        onPressed: () => Navigator.of(context).canPop()
            ? context.pop()
            : context.go('/messages'),
      ),
      title: Row(children: [
        Stack(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: avatarIsUrl
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent]),
              image: avatarIsUrl
                  ? DecorationImage(
                      image: NetworkImage(widget.avatar), fit: BoxFit.cover)
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
            bottom: 0, right: 0,
            child: Container(
              width: 10, height: 10,
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
                  child: Text(displayName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: text),
                      overflow: TextOverflow.ellipsis),
                ),
                if (_isAIMode) ...[
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
                style: const TextStyle(fontSize: 11, color: AppColors.success),
              ),
            ],
          ),
        ),
      ]),
      actions: [
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

  // ─────────────────────────────────────────────────────────────────────────
  // Input bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark, Color card, Color border, Color text,
      Color sub, Color surf) {
    final hintText = _isAIMode
        ? 'Ask your wealth mentor...'
        : 'Message ${widget.name}...';

    return Container(
      decoration:
          BoxDecoration(color: card, border: Border(top: BorderSide(color: border))),
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
            maxLines: 5,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_isSending,
            decoration: InputDecoration(
              hintText : hintText,
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled   : true,
              fillColor: surf,
              border: OutlineInputBorder(
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
              : () {
                  HapticFeedback.lightImpact();
                  _onSend();
                },
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

  // ─────────────────────────────────────────────────────────────────────────
  // Message bubble
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBubble(
      _Msg m, bool isDark, Color textColor, Color surfColor) {
    final aiBg    = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final errorBg = isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF0F0);
    final avatarIsUrl = m.avatar.startsWith('http') && m.avatar.length > 10;
    final bubbleBg = m.isError ? errorBg : m.isMe ? AppColors.userBubble : aiBg;

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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
                    gradient: avatarIsUrl
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent]),
                    image: avatarIsUrl
                        ? DecorationImage(
                            image: NetworkImage(m.avatar), fit: BoxFit.cover)
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectionArea(
                          child: (m.isMe || !m.isAI)
                              ? Text(m.displayText,
                                  style: TextStyle(
                                    color: m.isMe ? Colors.white : textColor,
                                    fontSize: 14,
                                    height: 1.5,
                                  ))
                              : MarkdownBody(
                                  data: m.displayText,
                                  onTapLink: (text, href, title) {
                                    if (href != null && href.isNotEmpty) {
                                      _openLink(href);
                                    }
                                  },
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
                                      color: AppColors.primaryLight,
                                    ),
                                    a: const TextStyle(
                                      color: AppColors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                    code: TextStyle(
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
                                    fontSize: 10,
                                    color: AppColors.error,
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
          child:
              const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
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
                width: 6, height: 6,
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

  Widget _buildEmptyState(bool isDark, Color subColor, Color textColor) {
    if (_isAIMode) {
      final firstName = _cachedMyName?.split(' ').first ?? '';
      final prompts   = [
        '💰  How do I make my first \$1,000 online?',
        '📈  Best beginner investments right now?',
        '🚀  Top side hustles I can start today?',
        '🧠  How do I improve my money mindset?',
      ];
      return Container(
        color: isDark ? Colors.black : Colors.white,
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
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: textColor),
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
                  onTap: () {
                    _textCtrl.text = p.substring(3).trim();
                    _onSend();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
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
                      delay:
                          Duration(milliseconds: prompts.indexOf(p) * 80)),
                )),
          ],
        ),
      );
    }

    return Container(
      color: isDark ? Colors.black : Colors.white,
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
// _QuotaRibbon
// ─────────────────────────────────────────────────────────────────────────────
class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inDailyLockout, inCycleLockout;
  final int  freeUsed, freeTotal;
  final int  cycleAds, adsPerCycle;
  final int  cycleMsgs, msgsPerCycle;
  final int  totalResponses, maxResponses;
  final String? cycleLockoutUntil;
  final String? dailyLockoutUntil;

  const _QuotaRibbon({
    required this.isPremium,
    required this.inDailyLockout,
    required this.inCycleLockout,
    required this.freeUsed,
    required this.freeTotal,
    required this.cycleAds,
    required this.adsPerCycle,
    required this.cycleMsgs,
    required this.msgsPerCycle,
    required this.totalResponses,
    required this.maxResponses,
    this.cycleLockoutUntil,
    this.dailyLockoutUntil,
  });

  @override
  State<_QuotaRibbon> createState() => _QuotaRibbonState();
}

class _QuotaRibbonState extends State<_QuotaRibbon> {
  Timer?  _timer;
  String  _countdown = '';

  @override
  void initState() {
    super.initState();
    if (widget.inCycleLockout || widget.inDailyLockout) _startTimer();
  }

  void _startTimer() {
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final lockStr = widget.inDailyLockout
        ? widget.dailyLockoutUntil
        : widget.cycleLockoutUntil;
    final exp = DateTime.tryParse(lockStr ?? '');
    if (exp == null) return;
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) { setState(() => _countdown = ''); return; }
    final h = diff.inHours;
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _countdown = h > 0 ? '${h}h ${m}m' : '$m:$s');
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.isPremium) return const SizedBox.shrink();

    if (widget.inDailyLockout) {
      return _ribbon(
        Icons.lock_rounded,
        AppColors.error,
        'Daily limit reached${_countdown.isNotEmpty ? ' · resets in $_countdown' : ''}',
        AppColors.error.withOpacity(0.08),
      );
    }

    if (widget.inCycleLockout) {
      return _ribbon(
        Icons.hourglass_bottom_rounded,
        AppColors.warning,
        'Take a break${_countdown.isNotEmpty ? ' · unlocks in $_countdown' : ''}',
        AppColors.warning.withOpacity(0.08),
      );
    }

    final freeLeft = widget.freeTotal - widget.freeUsed;
    if (freeLeft > 0) {
      return _ribbon(
        Icons.chat_bubble_outline_rounded,
        AppColors.primary,
        '$freeLeft free message${freeLeft == 1 ? '' : 's'} remaining',
        AppColors.primary.withOpacity(0.06),
      );
    }

    if (widget.cycleAds >= widget.adsPerCycle) {
      final left = widget.msgsPerCycle - widget.cycleMsgs;
      return _ribbon(
        Icons.lock_open_rounded,
        AppColors.success,
        '$left message${left == 1 ? '' : 's'} left · ${widget.totalResponses}/${widget.maxResponses} today',
        Colors.transparent,
      );
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
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _AdGateSheet
// ─────────────────────────────────────────────────────────────────────────────
class _AdGateSheet extends StatefulWidget {
  final int cycleAdsWatched;
  final int adsPerCycle;
  final int msgsPerCycle;
  final int totalResponses;
  final int maxResponses;
  final Future<void> Function() onAdWatched;

  const _AdGateSheet({
    required this.cycleAdsWatched,
    required this.adsPerCycle,
    required this.msgsPerCycle,
    required this.totalResponses,
    required this.maxResponses,
    required this.onAdWatched,
  });

  @override
  State<_AdGateSheet> createState() => _AdGateSheetState();
}

class _AdGateSheetState extends State<_AdGateSheet> {
  int     _localWatched = 0;
  bool    _watching     = false;
  String? _error;
  bool    _success      = false;

  int  get _totalWatched  => widget.cycleAdsWatched + _localWatched;
  int  get _adsRemaining  => widget.adsPerCycle - _totalWatched;
  bool get _cycleComplete => _totalWatched >= widget.adsPerCycle;

  Future<void> _watchAd() async {
    if (_watching || _cycleComplete) return;

    if (!adService.isRewardedReady) {
      setState(() =>
          _error = 'Ad not ready. Please wait a moment and try again.');
      return;
    }

    setState(() { _watching = true; _error = null; });

    await adService.showRewardedAd(
      featureKey: 'ai_chat',
      onRewarded: () async {
        await widget.onAdWatched();
        if (!mounted) return;
        setState(() {
          _localWatched++;
          _watching = false;
        });
        if (_cycleComplete) {
          setState(() => _success = true);
          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) Navigator.pop(context, true);
        }
      },
      onDismissed: () {
        if (!mounted) return;
        setState(() {
          _watching = false;
          _error    = 'Please watch the full ad to unlock messages.';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? AppColors.bgCard : Colors.white;
    final text      = isDark ? Colors.white     : Colors.black87;
    final sub       = isDark ? Colors.white60   : Colors.black54;
    final remaining = widget.maxResponses - widget.totalResponses;

    return Container(
      decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _success
              ? const Text('🎉',
                  style: TextStyle(fontSize: 56), key: ValueKey('success'))
              : Container(
                  key: const ValueKey('robot'),
                  width: 72, height: 72,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                      child: Text('🤖', style: TextStyle(fontSize: 36))),
                ),
        ),
        const SizedBox(height: 16),

        Text(
          _success ? 'Unlocked! 🚀' : 'Unlock AI Messages',
          style:
              TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text),
        ),
        const SizedBox(height: 8),
        if (!_success) ...[
          Text(
            'Watch $_adsRemaining more ad${_adsRemaining == 1 ? '' : 's'} to unlock ${widget.msgsPerCycle} messages.',
            style: TextStyle(fontSize: 14, color: sub, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '$remaining responses left before daily reset',
            style: TextStyle(fontSize: 11, color: sub),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (int i = 0; i < widget.adsPerCycle; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28, height: 8,
                decoration: BoxDecoration(
                  color: i < _totalWatched
                      ? AppColors.success
                      : AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (i < widget.adsPerCycle - 1) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 4),
          Text(
            '$_totalWatched / ${widget.adsPerCycle} ads watched',
            style: TextStyle(fontSize: 11, color: sub),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),

        if (!_success) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _watching ? null : _watchAd,
              icon: _watching
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_circle_fill_rounded, size: 20),
              label: Text(_watching
                  ? 'Loading ad...'
                  : 'Watch Ad ${_totalWatched + 1} of ${widget.adsPerCycle}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade500,
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
                GoRouter.of(context).go('/premium');
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
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LockoutSheet  (handles both 3hr cycle lock and 24hr daily lock)
// ─────────────────────────────────────────────────────────────────────────────
class _LockoutSheet extends StatefulWidget {
  final String       lockoutUntil;
  final bool         isDaily;
  final VoidCallback onUpgrade;

  const _LockoutSheet({
    required this.lockoutUntil,
    required this.isDaily,
    required this.onUpgrade,
  });

  @override
  State<_LockoutSheet> createState() => _LockoutSheetState();
}

class _LockoutSheetState extends State<_LockoutSheet> {
  Timer?  _timer;
  String  _countdown = '--:--:--';
  bool    _expired   = false;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final exp  = DateTime.tryParse(widget.lockoutUntil);
    if (exp == null) {
      setState(() { _countdown = '—'; _expired = true; });
      return;
    }
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) {
      setState(() { _countdown = 'Ready!'; _expired = true; });
      return;
    }
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

    final title = _expired
        ? (widget.isDaily ? 'Daily Limit Reset! ✅' : 'Break Over! ✅')
        : (widget.isDaily ? 'Daily Limit Reached' : 'Time for a Break ⏸️');

    final emoji = _expired ? '✅' : (widget.isDaily ? '🔒' : '⏸️');

    final bodyText = _expired
        ? (widget.isDaily
            ? 'Your daily limit has reset. Watch ads to keep chatting!'
            : 'Your break is over — watch ads to unlock more messages!')
        : (widget.isDaily
            ? 'You\'ve used all $_kMaxResponses responses today. Come back tomorrow or upgrade for unlimited access.'
            : 'Nice work! Take a 3-hour break, then you can watch ads to unlock more messages. Or upgrade for unlimited access.');

    return Container(
      decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Text(emoji, style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          bodyText,
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (!_expired) ...[
          const SizedBox(height: 24),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(
                widget.isDaily ? 'Resets in' : 'Unlocks in',
                style: TextStyle(fontSize: 12, color: sub),
              ),
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
        ],
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
          child: Text(
            _expired
                ? 'Start chatting!'
                : (widget.isDaily ? 'Come back tomorrow' : 'Come back later'),
            style: TextStyle(color: sub, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}
