// frontend/lib/screens/messages/conversation_screen.dart
// Production v17.0 — Brain-Aware AI Chat · /ai/chat endpoint · Full Brain Context UI
// ═══════════════════════════════════════════════════════════════════════════════════
// v17 Changes (over v16):
//  • AI mode now routes to POST /ai/chat (brain-aware v3.0 endpoint)
//  • _msgFromAIMap: parses role-based messages from /ai/conversations/{id}/messages
//  • _ensureAIConv: fetches existing convs from GET /ai/conversations; /ai/chat
//    creates a new one on first send — no separate create call needed
//  • _loadAIHistory: loads from GET /ai/conversations/{id}/messages
//  • _sendAI: posts to /ai/chat, persists returned conversation_id, parses all
//    brain fields (intent, methods, marketplace, providers, escalation)
//  • _BrainData model: carries brain search result alongside every AI message
//  • _BrainCard widget: renders methods / marketplace / provider chips inline
//  • Complementary-user row shown under AI messages when brain finds matches
//  • brain_needs_external flag auto-generates a Workflow delegation card
//  • _poll: AI mode uses /ai/conversations/{id}/messages + client-side since filter
//  • All v16 quota / ad-gate / scroll-lock / DM / cache / error-detection preserved
// ═══════════════════════════════════════════════════════════════════════════════════

// ignore_for_file: deprecated_member_use
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
const int _kFreeMessages         = 3;
const int _kAdsPerCycle          = 2;
const int _kMsgsPerCycle         = 3;
const int _kMaxResponses         = 30;
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

// Error phrases the backend AI may return when it is down
const List<String> _kAiErrorPhrases = [
  'experiencing technical difficulties',
  'please try again in a moment',
  'please try again later',
  'service is temporarily unavailable',
  'something went wrong',
  'unable to process your request',
  'i am currently unavailable',
];

// ─────────────────────────────────────────────────────────────────────────────
// Delegation types
// ─────────────────────────────────────────────────────────────────────────────
enum _DelegationType { apex, workflow, none }

class _DelegationPayload {
  final _DelegationType type;
  final String          task;
  final String          sessionId;
  final String          message;
  const _DelegationPayload({
    required this.type,
    required this.task,
    required this.sessionId,
    required this.message,
  });
  factory _DelegationPayload.fromJson(Map<String, dynamic> j, String fallbackSessionId) {
    final typeStr = j['type']?.toString() ?? '';
    return _DelegationPayload(
      type:      typeStr == 'apex'     ? _DelegationType.apex
               : typeStr == 'workflow' ? _DelegationType.workflow
               : _DelegationType.none,
      task:      j['task']?.toString() ?? j['goal']?.toString() ?? '',
      sessionId: j['session_id']?.toString() ?? fallbackSessionId,
      message:   j['message']?.toString() ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brain data model — carries brain search result alongside each AI message
// ─────────────────────────────────────────────────────────────────────────────
class _BrainData {
  final String        intent;
  final bool          internalFound;
  final List<dynamic> methods;
  final List<dynamic> marketplace;
  final List<dynamic> serviceProviders;
  final bool          needsExternal;
  final String?       escalationReason;
  final String?       suggestedTaskType;
  final List<dynamic> complementaryUsers;

  const _BrainData({
    this.intent             = 'explore',
    this.internalFound      = false,
    this.methods            = const [],
    this.marketplace        = const [],
    this.serviceProviders   = const [],
    this.needsExternal      = false,
    this.escalationReason,
    this.suggestedTaskType,
    this.complementaryUsers = const [],
  });

  bool get hasResults =>
      methods.isNotEmpty || marketplace.isNotEmpty || serviceProviders.isNotEmpty;

  bool get hasComplementaryUsers => complementaryUsers.isNotEmpty;

  factory _BrainData.fromResponse(Map<String, dynamic> res) {
    return _BrainData(
      intent:             res['brain_intent']?.toString()              ?? 'explore',
      internalFound:      res['brain_internal_found']                  == true,
      methods:            (res['brain_methods']            as List?)   ?? [],
      marketplace:        (res['brain_marketplace']        as List?)   ?? [],
      serviceProviders:   (res['brain_service_providers']  as List?)   ?? [],
      needsExternal:      res['brain_needs_external']                  == true,
      escalationReason:   res['brain_escalation_reason']?.toString(),
      suggestedTaskType:  res['brain_suggested_task_type']?.toString(),
      complementaryUsers: (res['complementary_users']      as List?)   ?? [],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message model
// ─────────────────────────────────────────────────────────────────────────────
class _Msg {
  final String  id;
  final String  content;
  final String  sender;
  final String  avatar;
  final bool    isMe;
  final bool    isAI;
  final bool    isError;
  final bool    brainUsed;
  final DateTime time;
  _DelegationPayload? delegation;
  _BrainData?         brainData;
  String displayText;
  bool   isTyping;

  _Msg({
    String? id,
    required this.content,
    required this.sender,
    required this.avatar,
    required this.isMe,
    this.isAI        = false,
    this.isError     = false,
    this.brainUsed   = false,
    this.delegation,
    this.brainData,
    DateTime? time,
  })  : id          = id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        displayText = content,
        isTyping    = false,
        time        = time ?? DateTime.now();

  String get fingerprint => '${isMe ? "u" : "a"}:${content.trim().hashCode}';
}

enum _QuotaResult { allowed, showAdGate, cycleLockout, hardLockout }

// ─────────────────────────────────────────────────────────────────────────────
// ConversationScreen
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  final String  userId;
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
    this.isAI        = false,
    this.postContext  = null,
    this.postAuthor   = null,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _textCtrl   = TextEditingController();
  final _scroll     = ScrollController();
  final _inputFocus = FocusNode();
  final List<_Msg>  _msgs = [];

  bool _historyLoaded    = false;
  bool _aiResponding     = false;
  bool _dmSending        = false;
  bool _convInitializing = false;
  bool _scrollLocked     = false;
  bool _loadingMore      = false;
  bool _hasMoreHistory   = true;
  bool _showQuickActions = false;

  String? _aiConvId;
  String? _lastPollTime;
  String? _cachedMyId;
  String? _cachedMyName;
  String? _lastSentText;

  Timer? _typingTimer;
  Timer? _pollTimer;

  Map<String, dynamic> _quota = {
    'free_used': 0, 'cycle_ads': 0, 'cycle_msgs': 0,
    'total_responses': 0, 'cycle_lockout_until': null,
    'daily_lockout_until': null, 'is_premium': false,
  };

  bool   get _isAIMode       => widget.isAI || widget.userId == 'ai';
  bool   get _isSending      => _aiResponding || _dmSending;
  bool   get _isPremium      => _quota['is_premium'] == true;
  int    get _freeUsed       => (_quota['free_used']       as int?) ?? 0;
  int    get _cycleAds       => (_quota['cycle_ads']       as int?) ?? 0;
  int    get _cycleMsgs      => (_quota['cycle_msgs']      as int?) ?? 0;
  int    get _totalResponses => (_quota['total_responses'] as int?) ?? 0;
  String? get _activeConvId  => _isAIMode ? _aiConvId : widget.userId;

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

  bool get _cycleActive => _cycleAds >= _kAdsPerCycle && _cycleMsgs < _kMsgsPerCycle;

  // ── Cache keys ────────────────────────────────────────────────────────────
  String get _convCacheKey     => '$_kMsgCachePrefix${_isAIMode ? 'ai' : widget.userId}';
  String get _convCacheTimeKey => '$_kMsgCacheTimePrefix${_isAIMode ? 'ai' : widget.userId}';

  // ─────────────────────────────────────────────────────────────────────────
  // Cache helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _saveMessageCache(List<_Msg> msgs) async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final encoded = jsonEncode(msgs
          .where((m) => !m.isError && m.content.isNotEmpty)
          .map((m) => {
                'id': m.id, 'content': m.content, 'sender': m.sender,
                'avatar': m.avatar, 'isMe': m.isMe, 'isAI': m.isAI,
                'brainUsed': m.brainUsed, 'time': m.time.toIso8601String(),
              })
          .toList());
      await prefs.setString(_convCacheKey, encoded);
      await prefs.setString(_convCacheTimeKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<List<_Msg>?> _loadMessageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_convCacheKey);
      if (raw == null) return null;
      final list  = jsonDecode(raw) as List;
      return list.map((m) => _Msg(
        id:        m['id']?.toString(),
        content:   m['content']?.toString()  ?? '',
        sender:    m['sender']?.toString()   ?? '',
        avatar:    m['avatar']?.toString()   ?? '',
        isMe:      m['isMe']     == true,
        isAI:      m['isAI']     == true,
        brainUsed: m['brainUsed'] == true,
        time:      DateTime.tryParse(m['time']?.toString() ?? '')?.toLocal(),
      )).toList();
    } catch (_) { return null; }
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
    _inputFocus.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _scrollLocked) return;
    // Only load more for DM mode — AI history is not paginated
    if (!_isAIMode &&
        _scroll.position.pixels <= 120 &&
        !_loadingMore && _hasMoreHistory && _historyLoaded) {
      _loadMoreHistory();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Poll-time persistence
  // ─────────────────────────────────────────────────────────────────────────
  String get _pollKey => '$_kPollTimePrefix${widget.userId}';

  Future<void> _restorePollTime() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
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
        if (mounted) setState(() {
          _quota['free_used']           = (local['free_used']           as int?) ?? 0;
          _quota['cycle_ads']           = (local['cycle_ads']           as int?) ?? 0;
          _quota['cycle_msgs']          = (local['cycle_msgs']          as int?) ?? 0;
          _quota['total_responses']     = (local['total_responses']     as int?) ?? 0;
          _quota['cycle_lockout_until'] =  local['cycle_lockout_until'] as String?;
          _quota['daily_lockout_until'] =  local['daily_lockout_until'] as String?;
        });
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
        'free_used':           _freeUsed,
        'cycle_ads':           _cycleAds,
        'cycle_msgs':          _cycleMsgs,
        'total_responses':     _totalResponses,
        'cycle_lockout_until': _quota['cycle_lockout_until'],
        'daily_lockout_until': _quota['daily_lockout_until'],
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
        _quota['daily_lockout_until'] =
            DateTime.now().add(_kDailyLockoutDur).toIso8601String();
        _quota['cycle_lockout_until'] = null;
        _quota['cycle_ads']           = 0;
        _quota['cycle_msgs']          = 0;
      } else if (cycleExhausted) {
        _quota['cycle_lockout_until'] =
            DateTime.now().add(_kCycleLockoutDur).toIso8601String();
        _quota['cycle_ads']  = 0;
        _quota['cycle_msgs'] = 0;
      }
    });
    await _saveQuota();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ensure AI conversation (v17: uses GET /ai/conversations)
  // /ai/chat creates a new conv on first send — no separate create call needed
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
      // Fetch existing conversations from GET /ai/conversations
      final res  = await api.get('/ai/conversations');
      final list = (res['conversations'] as List?) ?? [];
      if (list.isNotEmpty) {
        _aiConvId = list.first['id']?.toString() ?? '';
        if (_aiConvId!.isNotEmpty) {
          await prefs.setString(_kAiConvIdKey, _aiConvId!);
        }
      }
      // If no conv yet that's fine — /ai/chat will create one on first send
      // and we'll persist the returned conversation_id at that point
    } catch (e) {
      debugPrint('[Conv] _ensureAIConv error: $e');
    }
    if (mounted) setState(() => _convInitializing = false);
    return true; // always allow send
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_historyLoaded) return;
    await _fetchMyInfo();
    final cached = await _loadMessageCache();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _msgs.clear();
        _msgs.addAll(cached);
        _historyLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback(
          (_) { if (mounted) _scrollDown(jump: true); });
    }
    try {
      if (_isAIMode) await _loadAIHistory();
      else           await _loadDMHistory();
    } catch (e) {
      debugPrint('[Conv] history error: $e');
    } finally {
      if (mounted && !_historyLoaded) {
        setState(() => _historyLoaded = true);
        WidgetsBinding.instance.addPostFrameCallback(
            (_) { if (mounted) _scrollDown(jump: true); });
      }
    }
    // Auto-inject post context as first message
    if (_isAIMode &&
        widget.postContext != null &&
        widget.postContext!.isNotEmpty) {
      await _sendAI(
        'I want to discuss a post: "${widget.postContext}"\n'
        'Give me a quick wealth insight.',
        adUnlocked: false,
        isContextMessage: true,
      );
    }
  }

  Future<void> _fetchMyInfo() async {
    try {
      _cachedMyId ??= await api.getUserId();
      if (_cachedMyId != null) {
        final p = await api.getUserProfile(_cachedMyId!);
        _cachedMyName = (p['full_name'] as String?)?.trim();
        if (_cachedMyName == null || _cachedMyName!.isEmpty)
          _cachedMyName = (p['username'] as String?)?.trim();
      }
    } catch (_) {}
  }

  // v17: load AI history from GET /ai/conversations/{id}/messages
  Future<void> _loadAIHistory() async {
    await _ensureAIConv();
    if (_aiConvId == null || _aiConvId!.isEmpty) {
      _hasMoreHistory = false;
      if (mounted) setState(() => _historyLoaded = true);
      await _maybeShowFirstTimeGreeting();
      return;
    }
    try {
      final res  = await api.get('/ai/conversations/$_aiConvId/messages');
      final msgs = (res['messages'] as List?) ?? [];
      if (!mounted) return;
      if (msgs.isNotEmpty) {
        setState(() {
          _msgs.clear();
          for (final m in msgs) _msgs.add(_msgFromAIMap(m as Map));
          _hasMoreHistory = false; // /ai/conversations endpoint doesn't paginate
          _historyLoaded  = true;
        });
        await _savePollTime(msgs.last['created_at']?.toString() ?? '');
        await _saveMessageCache(_msgs);
        WidgetsBinding.instance.addPostFrameCallback(
            (_) { if (mounted) _scrollDown(jump: true); });
      } else {
        _hasMoreHistory = false;
        if (mounted) setState(() => _historyLoaded = true);
        await _maybeShowFirstTimeGreeting();
      }
    } catch (e) {
      debugPrint('[Conv] AI history error: $e');
      _hasMoreHistory = false;
      if (mounted) setState(() => _historyLoaded = true);
      await _maybeShowFirstTimeGreeting();
    }
  }

  Future<void> _loadDMHistory() async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;
    try {
      final msgs = await api.getDMMessages(widget.userId, limit: _kHistoryPageSize);
      if (!mounted || msgs.isEmpty) { _hasMoreHistory = false; return; }
      setState(() {
        _msgs.clear();
        for (final m in msgs) {
          final st = (m['sender_type']?.toString() ?? '');
          if (st == 'ai' || st == 'system') continue;
          _msgs.add(_msgFromMap(m, myId: _cachedMyId));
        }
        _hasMoreHistory = msgs.length >= _kHistoryPageSize;
        _historyLoaded  = true;
      });
      await _savePollTime(msgs.last['created_at']?.toString() ?? '');
      await _saveMessageCache(_msgs);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) { if (mounted) _scrollDown(jump: true); });
    } catch (e) {
      debugPrint('[Conv] DM history error: $e');
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMore || !_hasMoreHistory || _msgs.isEmpty || _isAIMode) return;
    setState(() => _loadingMore = true);
    try {
      final convId = _activeConvId;
      if (convId == null || convId.isEmpty) {
        setState(() => _loadingMore = false);
        return;
      }
      final older = await api.getDMMessages(convId, limit: _kHistoryPageSize);
      if (!mounted) return;
      if (older.isEmpty || older.length < _kHistoryPageSize) {
        setState(() => _hasMoreHistory = false);
      } else {
        final myId    = await _getMyId();
        final newMsgs = <_Msg>[];
        for (final m in older) {
          final st = m['sender_type']?.toString() ?? '';
          if (st == 'ai' || st == 'system') continue;
          newMsgs.add(_msgFromMap(m, myId: myId));
        }
        setState(() => _msgs.insertAll(0, newMsgs));
      }
    } catch (e) {
      debugPrint('[Conv] load more error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _maybeShowFirstTimeGreeting() async {
    if (_aiConvId == null && _aiConvId?.isEmpty != false) {
      // No conv yet — greet with a local bubble (conv created on first send)
      final greetKey = '${_kGreetedPrefix}new_user';
      try {
        final prefs       = await SharedPreferences.getInstance();
        final alreadyDone = prefs.getBool(greetKey) ?? false;
        if (alreadyDone) return;
        await prefs.setBool(greetKey, true);
        _showGreetingBubble();
      } catch (_) {}
      return;
    }
    final greetKey = '$_kGreetedPrefix$_aiConvId';
    try {
      final prefs       = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(greetKey) ?? false;
      if (alreadyDone) return;
      await prefs.setBool(greetKey, true);
      _showGreetingBubble();
      await _savePollTime(DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      debugPrint('[Conv] greeting error: $e');
    }
  }

  void _showGreetingBubble() {
    if (!mounted) return;
    final firstName = _cachedMyName?.split(' ').first ?? 'there';
    final greeting  =
        'Hey $firstName 👋 Welcome to RiseUp!\n\n'
        "I'm your AI Wealth Mentor — here to help you build income, grow wealth, "
        'and level up your finances. 💰\n\n'
        'I can also hand tasks to **APEX** — your autonomous AI agent that '
        'opens browsers, fills forms, applies to jobs, and sets up accounts for you.\n\n'
        'Ask me anything, or just say **"do it for me"** and I\'ll launch APEX. 🚀';
    final greetMsg = _Msg(
      content: greeting,
      sender:  'RiseUp AI',
      avatar:  '🤖',
      isMe:    false,
      isAI:    true,
    );
    setState(() => _msgs.add(greetMsg));
    _typeMessage(greetMsg);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Parses a role-based message map from /ai/conversations/{id}/messages
  _Msg _msgFromAIMap(Map m) {
    final id      = m['id']?.toString()      ?? '';
    final role    = m['role']?.toString()    ?? '';
    final content = m['content']?.toString() ?? '';
    final isAI    = role == 'assistant';
    return _Msg(
      id:      id.isNotEmpty ? id : null,
      content: content,
      sender:  isAI ? 'RiseUp AI' : (_cachedMyName ?? 'You'),
      avatar:  isAI ? '🤖' : '👤',
      isMe:    !isAI,
      isAI:    isAI,
      time:    DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  /// Parses a sender_type-based message map from /api/v1/messages (DM mode)
  _Msg _msgFromMap(Map m, {required String? myId}) {
    final id         = m['id']?.toString()          ?? '';
    final senderId   = m['sender_id']?.toString()   ?? '';
    final senderType = m['sender_type']?.toString() ?? '';
    final isAIMsg    = senderType == 'ai' || senderType == 'system';
    final isMe       = !isAIMsg && myId != null && senderId == myId;
    final profile    = (m['profiles'] as Map?) ?? {};
    return _Msg(
      id:      id.isNotEmpty ? id : null,
      content: m['content']?.toString() ?? '',
      sender: isAIMsg ? 'RiseUp AI'
             : isMe   ? (_cachedMyName ?? 'You')
             : (profile['full_name']?.toString() ?? widget.name),
      avatar: isAIMsg ? '🤖'
             : isMe   ? '👤'
             : (profile['avatar_url']?.toString() ?? widget.avatar),
      isMe:  isMe,
      isAI:  isAIMsg,
      time:  DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal(),
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
  // Delegation inference (client-side fallback)
  // ─────────────────────────────────────────────────────────────────────────
  _DelegationPayload? _inferDelegation(String content, String sessionId) {
    final lower = content.toLowerCase();

    final apexKeywords = [
      'launch apex', "i'll use apex", 'apex will', 'let me use apex',
      'autonomous agent', "i'll do it for you", 'handle this for you',
      'set it up for you', "i'll set up", 'do it for you',
      'apply for you', 'open the browser', 'fill out the form',
      'create the account', 'sign you up', 'register for you',
    ];
    if (apexKeywords.any((k) => lower.contains(k))) {
      return _DelegationPayload(
        type:      _DelegationType.apex,
        task:      _extractTask(content),
        sessionId: sessionId,
        message:   content,
      );
    }

    final workflowKeywords = [
      'build you a workflow', 'create a workflow', 'build a plan',
      'step-by-step plan', 'workflow engine', 'income plan',
      "i'll build", 'let me build', 'create a roadmap',
      'build a roadmap', 'action plan', 'build your plan',
    ];
    if (workflowKeywords.any((k) => lower.contains(k))) {
      return _DelegationPayload(
        type:      _DelegationType.workflow,
        task:      _extractTask(content),
        sessionId: sessionId,
        message:   content,
      );
    }
    return null;
  }

  String _extractTask(String content) {
    var clean = content.replaceAll(RegExp(r'\*+'), '').trim();
    final dot = clean.indexOf('.');
    if (dot > 0 && dot < 120) clean = clean.substring(0, dot).trim();
    return clean.length > 100 ? '${clean.substring(0, 97)}...' : clean;
  }

  bool _isAIBackendError(String content) {
    final lower = content.toLowerCase().trim();
    return _kAiErrorPhrases.any((phrase) => lower.contains(phrase));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling (v17: AI mode uses /ai/conversations/{id}/messages)
  // ─────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_historyLoaded || _isSending || _loadingMore) return;
    final convId = _activeConvId;
    if (convId == null || convId.isEmpty) return;

    try {
      List<dynamic> newMsgs;

      if (_isAIMode) {
        // v17: AI mode — poll /ai/conversations/{id}/messages, filter client-side
        final res = await api.get('/ai/conversations/$convId/messages');
        final all = (res['messages'] as List?) ?? [];
        if (_lastPollTime != null && _lastPollTime!.isNotEmpty) {
          final since = DateTime.tryParse(_lastPollTime!);
          newMsgs = since != null
              ? all.where((m) {
                  final t = DateTime.tryParse(
                      (m as Map)['created_at']?.toString() ?? '');
                  return t != null && t.isAfter(since);
                }).toList()
              : all;
        } else {
          newMsgs = all;
        }
      } else {
        newMsgs = await api.getDMMessages(convId, since: _lastPollTime);
      }

      if (!mounted || newMsgs.isEmpty) return;
      final myId         = await _getMyId();
      final existingIds  = _msgs.map((m) => m.id).toSet();
      final fingerprints = _msgs.map((m) => m.fingerprint).toSet();
      bool added = false;

      setState(() {
        for (final raw in newMsgs) {
          final m          = raw as Map;
          final id         = m['id']?.toString() ?? '';
          final content    = m['content']?.toString() ?? '';

          // Normalise sender type across both endpoint formats
          final String senderType;
          if (_isAIMode) {
            senderType = m['role']?.toString() == 'assistant' ? 'ai' : 'user';
          } else {
            senderType = m['sender_type']?.toString() ?? '';
          }

          final senderId = m['sender_id']?.toString() ?? '';
          final isAIMsg  = senderType == 'ai' || senderType == 'system';
          final isMe     = _isAIMode
              ? senderType == 'user'
              : (!isAIMsg && myId != null && senderId == myId);

          if (!_isAIMode && isAIMsg) continue;
          if (id.isEmpty || existingIds.contains(id)) continue;
          final fp = '${isMe ? "u" : "a"}:${content.trim().hashCode}';
          if (fingerprints.contains(fp)) continue;

          // v16/v17: silently drop backend error messages from poll
          if (isAIMsg && _isAIBackendError(content)) continue;

          // Optimistic local message reconciliation (DM mode only)
          if (!_isAIMode && isMe) {
            final optIdx = _msgs.indexWhere((msg) =>
                msg.id.startsWith('local_') &&
                msg.isMe &&
                msg.content == content);
            if (optIdx != -1) {
              final old = _msgs[optIdx];
              _msgs[optIdx] = _Msg(
                  id: id, content: old.content,
                  sender: old.sender, avatar: old.avatar,
                  isMe: true, time: old.time);
              existingIds.add(id); fingerprints.add(fp);
              added = true; continue;
            }
          }

          _msgs.add(_isAIMode ? _msgFromAIMap(m) : _msgFromMap(m, myId: myId));
          existingIds.add(id); fingerprints.add(fp);
          added = true;
        }
      });

      if (newMsgs.isNotEmpty) {
        await _savePollTime(
            (newMsgs.last as Map)['created_at']?.toString() ?? '');
      }
      if (added) { _scrollDown(); await _saveMessageCache(_msgs); }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Send routing
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _showQuickActions = false);
    _lastSentText = text;
    if (_isAIMode) await _trySendAI(text);
    else           await _sendDM(text);
  }

  Future<void> _trySendAI(String text, {bool viaAIDM = false}) async {
    final result = _checkAIQuota();
    switch (result) {
      case _QuotaResult.showAdGate:   await _showAdGate(text, viaAIDM: viaAIDM); return;
      case _QuotaResult.cycleLockout: _showCycleLockoutSheet(); return;
      case _QuotaResult.hardLockout:  _showDailyLockoutSheet(); return;
      case _QuotaResult.allowed:      break;
    }
    await _sendAI(text, adUnlocked: false, viaAIDM: viaAIDM);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _sendAI — v17: routes to POST /ai/chat (brain-aware endpoint)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendAI(
    String text, {
    bool adUnlocked       = false,
    bool viaAIDM          = false,
    bool isContextMessage = false,
    bool retried          = false,
  }) async {
    // Ensure we have a conv id (or will get one back from /ai/chat)
    if (!viaAIDM && (_aiConvId == null || _aiConvId!.isEmpty)) {
      await _ensureAIConv();
    }

    _textCtrl.clear();
    final optimisticId = 'local_${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      _msgs.add(_Msg(
        id:      optimisticId,
        content: text,
        sender:  _cachedMyName ?? 'You',
        avatar:  '👤',
        isMe:    true,
      ));
      _aiResponding = true;
    });
    _scrollDown();

    try {
      // v17: POST /ai/chat — brain-aware endpoint
      final res = await api.post('/ai/chat', {
        'message':         text,
        'conversation_id': (_aiConvId != null && _aiConvId!.isNotEmpty)
                           ? _aiConvId
                           : null,
        'mode':            'chat',
      });

      final aiContent = (res['content'] ?? '').toString().trim();
      if (aiContent.isEmpty) throw Exception('Empty AI response');

      // v16/v17: Detect backend error responses
      if (_isAIBackendError(aiContent)) {
        if (!mounted) return;
        setState(() {
          _aiResponding = false;
          _msgs.removeWhere((m) => m.id == optimisticId);
        });
        _addErrorBubble('AI is temporarily unavailable. Please try again in a moment.');
        _showRetrySnackbar(text, viaAIDM: viaAIDM, adUnlocked: adUnlocked);
        return;
      }

      // Persist conversation_id returned by /ai/chat if new
      final returnedConvId = res['conversation_id']?.toString() ?? '';
      if (returnedConvId.isNotEmpty &&
          (_aiConvId == null || _aiConvId!.isEmpty)) {
        _aiConvId = returnedConvId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAiConvIdKey, _aiConvId!);
      }

      await _savePollTime(DateTime.now().toUtc().toIso8601String());

      // Quota accounting
      if (!_isPremium && !isContextMessage) {
        if (_freeUsed < _kFreeMessages) {
          final newTotal = _totalResponses + 1;
          setState(() {
            _quota['free_used']       = _freeUsed + 1;
            _quota['total_responses'] = newTotal;
            if (newTotal >= _kMaxResponses)
              _quota['daily_lockout_until'] =
                  DateTime.now().add(_kDailyLockoutDur).toIso8601String();
          });
          await _saveQuota();
        } else if (adUnlocked || _cycleActive) {
          await _consumeAdMessage();
        }
      }

      if (!mounted) return;

      // Update optimistic message with server id
      final realUserMsgId = res['message_id']?.toString() ?? '';
      if (realUserMsgId.isNotEmpty) {
        final idx = _msgs.indexWhere((m) => m.id == optimisticId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _Msg(
              id: realUserMsgId, content: old.content,
              sender: old.sender, avatar: old.avatar,
              isMe: true, time: old.time);
        }
      }

      // ── v17: Parse brain data from response ──────────────────────────────
      final brainData = _BrainData.fromResponse(res);

      // Brain = internal found or model indicated brain usage
      final brainUsed = brainData.internalFound || res['brain_used'] == true;

      // ── Delegation: backend first, then client-side inference, then brain ─
      final convIdForSession = returnedConvId.isNotEmpty
          ? returnedConvId : (_aiConvId ?? '');
      _DelegationPayload? delegationPayload;

      final delegationMap = res['delegation'] as Map<String, dynamic>?;
      if (delegationMap != null) {
        delegationPayload = _DelegationPayload.fromJson(delegationMap, convIdForSession);
        if (delegationPayload.type == _DelegationType.none)
          delegationPayload = null;
      }

      // Client-side inference fallback
      delegationPayload ??= _inferDelegation(aiContent, convIdForSession);

      // If brain says external search needed → auto-suggest workflow
      if (delegationPayload == null && brainData.needsExternal) {
        delegationPayload = _DelegationPayload(
          type:      _DelegationType.workflow,
          task:      _extractTask(aiContent),
          sessionId: convIdForSession,
          message:   aiContent,
        );
      }
      // ─────────────────────────────────────────────────────────────────────

      final aiMsg = _Msg(
        content:    aiContent,
        sender:     'RiseUp AI',
        avatar:     '🤖',
        isMe:       false,
        isAI:       true,
        brainUsed:  brainUsed,
        delegation: delegationPayload,
        brainData:  brainData,
      );
      setState(() { _aiResponding = false; _msgs.add(aiMsg); });
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
        // Conv may be stale — clear and retry once
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kAiConvIdKey);
        _aiConvId = null;
        final ok = await _ensureAIConv();
        if (ok && mounted) {
          await _sendAI(text,
              adUnlocked:       adUnlocked,
              viaAIDM:          viaAIDM,
              isContextMessage: isContextMessage,
              retried:          true);
        } else {
          _addErrorBubble('Could not connect to AI. Please try again.');
        }
      } else {
        _addErrorBubble('Failed (${e.statusCode}). Please try again.');
        _showRetrySnackbar(text, viaAIDM: viaAIDM, adUnlocked: adUnlocked);
      }
    } catch (e) {
      debugPrint('[Conv] _sendAI error: $e');
      if (!mounted) return;
      setState(() {
        _aiResponding = false;
        _msgs.removeWhere((m) => m.id == optimisticId);
      });
      _addErrorBubble('Could not reach AI right now. Please try again.');
      _showRetrySnackbar(text, viaAIDM: viaAIDM, adUnlocked: adUnlocked);
    }
  }

  void _showRetrySnackbar(
      String text, {bool viaAIDM = false, bool adUnlocked = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Tap Retry to resend your message'),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.bgCard,
      action: SnackBarAction(
        label: 'Retry',
        textColor: AppColors.primary,
        onPressed: () {
          if (mounted)
            _sendAI(text, adUnlocked: adUnlocked, viaAIDM: viaAIDM);
        },
      ),
    ));
  }

  Future<void> _sendDM(String text) async {
    if (widget.userId.isEmpty || widget.userId == 'ai') return;
    _textCtrl.clear();
    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _msgs.add(_Msg(
        id:      optimisticId,
        content: text,
        sender:  _cachedMyName ?? 'You',
        avatar:  '👤',
        isMe:    true,
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
              id: optimisticId, content: old.content,
              sender: old.sender, avatar: old.avatar,
              isMe: true, isError: true, time: old.time);
        }
        _dmSending = false;
      });
    }
  }

  void _addErrorBubble(String msg) {
    if (!mounted) return;
    setState(() => _msgs.add(_Msg(
        content: msg, sender: 'RiseUp AI',
        avatar: '🤖', isMe: false, isAI: true, isError: true)));
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
        if (mounted) setState(() {
          msg.isTyping    = false;
          msg.displayText = msg.content;
          _scrollLocked   = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
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
      if (jump) _scroll.jumpTo(maxExt);
      else _scroll.animateTo(maxExt, duration: 180.ms, curve: Curves.easeOut);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Link, copy & context-menu helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

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

  void _showBubbleMenu(BuildContext ctx, _Msg m) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2))),
          _menuItem(Icons.copy_rounded, 'Copy message',
              isDark ? Colors.white : Colors.black87, () {
            Navigator.pop(ctx);
            _copyToClipboard(m.content, label: 'Copied');
          }),
          if (!m.isMe && m.isAI && !m.isError)
            _menuItem(Icons.share_rounded, 'Share insight',
                isDark ? Colors.white : Colors.black87, () {
              Navigator.pop(ctx);
              _copyToClipboard(
                  '💡 RiseUp AI:\n\n${m.content}\n\n— via RiseUp',
                  label: 'Copied to share!');
            }),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
        ]),
      ),
    );
  }

  Widget _menuItem(
          IconData icon, String label, Color textColor, VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 20),
        title: Text(label,
            style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        onTap: onTap,
        dense: true,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // APEX / Workflow delegation
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _launchApex(String task, String sessionId) async {
    HapticFeedback.mediumImpact();
    try {
      final res = await api.post('/agent/handoff', {
        'task':           task,
        'source':         'mentor',
        'source_conv_id': sessionId,
      });
      final apexSessionId = res['session_id']?.toString() ?? '';
      final questions     =
          (res['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final template = res['template'] as Map<String, dynamic>?;
      if (mounted) {
        context.push('/agent', extra: {
          'handoffTask':      task,
          'handoffSessionId': apexSessionId,
          'handoffTemplate':  template,
          'handoffQuestions': questions,
        });
      }
    } catch (e) {
      debugPrint('[Conv] APEX handoff error: $e');
      if (mounted) context.push('/agent', extra: {'handoffTask': task});
    }
  }

  void _launchWorkflow(String goal) {
    HapticFeedback.mediumImpact();
    context.push('/workflow/new', extra: {'prefillGoal': goal});
  }

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
        adsPerCycle:     _kAdsPerCycle,
        msgsPerCycle:    _kMsgsPerCycle,
        totalResponses:  _totalResponses,
        maxResponses:    _kMaxResponses,
        onAdWatched: () async {
          if (!mounted) return;
          setState(() => _quota['cycle_ads'] = _cycleAds + 1);
          await _saveQuota();
        },
      ),
    );
    if (!mounted || success != true) return;
    await _sendAI(pendingText, adUnlocked: true, viaAIDM: viaAIDM);
  }

  void _showCycleLockoutSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LockoutSheet(
          lockoutUntil: (_quota['cycle_lockout_until'] as String?) ?? '',
          isDaily:  false,
          onUpgrade: () { Navigator.pop(context); context.go('/premium'); },
        ),
      );

  void _showDailyLockoutSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LockoutSheet(
          lockoutUntil: (_quota['daily_lockout_until'] as String?) ?? '',
          isDaily:  true,
          onUpgrade: () { Navigator.pop(context); context.go('/premium'); },
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black        : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard    : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white        : Colors.black87;
    final subColor    = isDark ? Colors.white54      : Colors.black45;
    final surfColor   = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(isDark, cardColor, borderColor, textColor, subColor),
      body: Column(children: [
        if (_convInitializing)
          LinearProgressIndicator(
              color: AppColors.primary.withOpacity(0.5),
              minHeight: 2,
              backgroundColor: Colors.transparent),
        if (_isAIMode && !_isPremium)
          _QuotaRibbon(
            isPremium:          _isPremium,
            inDailyLockout:     _inDailyLockout,
            inCycleLockout:     _inCycleLockout,
            freeUsed:           _freeUsed,
            freeTotal:          _kFreeMessages,
            cycleAds:           _cycleAds,
            adsPerCycle:        _kAdsPerCycle,
            cycleMsgs:          _cycleMsgs,
            msgsPerCycle:       _kMsgsPerCycle,
            totalResponses:     _totalResponses,
            maxResponses:       _kMaxResponses,
            cycleLockoutUntil:  _quota['cycle_lockout_until'] as String?,
            dailyLockoutUntil:  _quota['daily_lockout_until'] as String?,
            onWatchAds: () => _showAdGate(_lastSentText ?? ''),
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _msgs.length +
                          (_aiResponding ? 1 : 0) +
                          (_loadingMore  ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_loadingMore && i == 0)
                          return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                  child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary))));
                        final msgIdx = _loadingMore ? i - 1 : i;
                        if (msgIdx == _msgs.length)
                          return _buildTypingIndicator(isDark, surfColor);
                        return _buildBubble(
                            _msgs[msgIdx], isDark, textColor, surfColor);
                      },
                    ),
        ),
        if (_isAIMode && _showQuickActions)
          _QuickActionBar(
            isDark:     isDark,
            onApex:     () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Do it for me: ';
              _inputFocus.requestFocus();
            },
            onWorkflow: () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Build me a plan: ';
              _inputFocus.requestFocus();
            },
            onSearch:   () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Find me: ';
              _inputFocus.requestFocus();
            },
          ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0),
        _buildInputBar(isDark, cardColor, borderColor, textColor, subColor, surfColor),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AppBar
  // ─────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
      bool isDark, Color card, Color border, Color text, Color sub) {
    final displayName   = _isAIMode ? 'RiseUp AI Mentor' : widget.name;
    final displayAvatar = _isAIMode ? '🤖' : widget.avatar;
    final avatarIsUrl   = !_isAIMode && displayAvatar.startsWith('http');

    return AppBar(
      backgroundColor: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
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
                      border: Border.all(color: card, width: 1.5)))),
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
                        overflow: TextOverflow.ellipsis)),
                if (_isAIMode) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent]),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('AI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700))),
                ],
              ]),
              const Text('Always online',
                  style: TextStyle(fontSize: 11, color: AppColors.success)),
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
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Input bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark, Color card, Color border,
      Color text, Color sub, Color surf) {
    return Container(
      decoration: BoxDecoration(
          color: card,
          border: Border(top: BorderSide(color: border))),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (_isAIMode)
          IconButton(
            icon: Icon(
                _showQuickActions
                    ? Icons.close_rounded
                    : Icons.auto_awesome_rounded,
                color:
                    _showQuickActions ? AppColors.primary : sub,
                size: 22),
            onPressed: () =>
                setState(() => _showQuickActions = !_showQuickActions),
          )
        else
          IconButton(
            icon: Icon(Iconsax.image, color: sub, size: 22),
            onPressed: () async {
              final file = await ImagePicker()
                  .pickImage(source: ImageSource.gallery);
              if (file != null && mounted)
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Photo selected ✅ — media upload coming soon')));
            },
          ),
        Expanded(
          child: TextField(
            controller:  _textCtrl,
            focusNode:   _inputFocus,
            style:       TextStyle(fontSize: 14, color: text),
            maxLines:    5,
            minLines:    1,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_isSending,
            decoration: InputDecoration(
              hintText: _isAIMode
                  ? 'Ask your wealth mentor...'
                  : 'Message ${widget.name}...',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              filled:    true,
              fillColor: surf,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
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
            duration: 200.ms,
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _isSending
                  ? [Colors.grey.shade500, Colors.grey.shade500]
                  : [AppColors.primary, AppColors.accent]),
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
    final bubbleBg = m.isError ? errorBg : m.isMe ? AppColors.userBubble : aiBg;
    final avatarIsUrl = m.avatar.startsWith('http');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender label
          if (!m.isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 36),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(m.sender,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: m.isAI
                            ? AppColors.primary
                            : AppColors.warning)),
                if (m.isAI) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.auto_awesome,
                      size: 10, color: AppColors.primary),
                ],
                if (m.brainUsed) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFF6C5CE7),
                          Color(0xFF00B894)
                        ]),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('🧠 Brain',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700))),
                ],
              ]),
            ),

          // Bubble row
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
                child: GestureDetector(
                  onLongPress: () => _showBubbleMenu(context, m),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(18),
                        topRight:    const Radius.circular(18),
                        bottomLeft:  Radius.circular(m.isMe ? 18 : 4),
                        bottomRight: Radius.circular(m.isMe ? 4  : 18)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: (m.isMe || !m.isAI)
                        ? SelectionArea(
                            child: Text(m.displayText,
                                style: TextStyle(
                                    color: m.isMe
                                        ? Colors.white
                                        : m.isError
                                            ? AppColors.error
                                            : textColor,
                                    fontSize: 14,
                                    height:   1.5)))
                        : SelectionArea(
                            child: MarkdownBody(
                              data: m.displayText,
                              onTapLink: (text, href, title) {
                                if (href != null) _openLink(href);
                              },
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                    color: m.isError
                                        ? AppColors.error
                                        : isDark
                                            ? const Color(0xFFE8E8F0)
                                            : Colors.black87,
                                    fontSize: 14,
                                    height:   1.55),
                                strong: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryLight),
                                a: const TextStyle(
                                    color: AppColors.primary,
                                    decoration: TextDecoration.underline),
                                code: TextStyle(
                                    fontFamily: 'monospace',
                                    backgroundColor: isDark
                                        ? const Color(0xFF2A2A3E)
                                        : Colors.grey.shade200,
                                    fontSize: 13),
                                codeblockDecoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0D1117)
                                        : Colors.grey.shade900,
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                codeblockPadding:
                                    const EdgeInsets.all(12),
                              ))),
                  ),
                ),
              ),
            ],
          ),

          // ── Delegation card ───────────────────────────────────────────
          if (!m.isError &&
              m.delegation != null &&
              m.delegation!.type != _DelegationType.none)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 36),
              child: _DelegationCard(
                payload: m.delegation!,
                isDark:  isDark,
                onLaunch: () {
                  if (m.delegation!.type == _DelegationType.apex)
                    _launchApex(
                        m.delegation!.task, m.delegation!.sessionId);
                  else
                    _launchWorkflow(m.delegation!.task);
                },
              ),
            ),

          // ── v17: Brain result card ────────────────────────────────────
          if (!m.isError && m.isAI && m.brainData != null && m.brainData!.hasResults && !m.isTyping)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: _BrainCard(
                  brainData: m.brainData!, isDark: isDark),
            ),

          // ── v17: Complementary user suggestions ───────────────────────
          if (!m.isError &&
              m.isAI &&
              m.brainData != null &&
              m.brainData!.hasComplementaryUsers &&
              !m.isTyping)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: _ComplementaryUsersRow(
                  users: m.brainData!.complementaryUsers,
                  isDark: isDark,
                  onTap: (userId, name, avatar) {
                    context.push('/messages/$userId',
                        extra: {'name': name, 'avatar': avatar});
                  }),
            ),

          // Timestamp
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
              shape: BoxShape.circle),
          child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 14)))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
              color: isDark ? AppColors.aiBubble : surfColor,
              borderRadius: BorderRadius.circular(18)),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                  3,
                  (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle))
                      .animate(onPlay: (c) => c.repeat())
                      .fadeIn(delay: Duration(milliseconds: i * 200))
                      .then()
                      .fadeOut())),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(bool isDark, Color subColor, Color textColor) {
    if (_isAIMode) {
      final firstName = _cachedMyName?.split(' ').first ?? '';
      final prompts   = [
        '💰  How do I make my first \$1,000 online?',
        '🤖  Set up my Fiverr account for me',
        '📈  Best beginner investments right now?',
        '🚀  Build me a side hustle plan',
        '🌍  Find phone sellers in Lagos',
        '💼  Apply to remote jobs for me',
      ];
      return Container(
        color: isDark ? Colors.black : Colors.white,
        child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 32),
            children: [
              Container(
                      width: 80, height: 80,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppColors.primary,
                            AppColors.accent
                          ]),
                          shape: BoxShape.circle),
                      child: const Center(
                          child: Text('🤖',
                              style: TextStyle(fontSize: 40))))
                  .animate()
                  .scale(duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 20),
              Text('Your AI Wealth Mentor + APEX Agent',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: textColor),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                firstName.isNotEmpty
                    ? 'Hey $firstName! Ask anything — or say "do it for me" to launch APEX.'
                    : 'Ask anything about money. Say "do it for me" to launch APEX.',
                style: TextStyle(
                    fontSize: 14, color: subColor, height: 1.6),
                textAlign: TextAlign.center),
              const SizedBox(height: 32),
              Text('Try:',
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
                                  color: AppColors.primary
                                      .withOpacity(0.18))),
                          child: Text(p,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  height: 1.4)))
                        .animate()
                        .fadeIn(
                            delay: Duration(
                                milliseconds:
                                    prompts.indexOf(p) * 80)))),
            ]));
    }
    return Container(
      color: isDark ? Colors.black : Colors.white,
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
          ])));
  }

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brain Card — v17: shows methods / marketplace / providers from brain search
// ─────────────────────────────────────────────────────────────────────────────
class _BrainCard extends StatelessWidget {
  final _BrainData brainData;
  final bool       isDark;

  const _BrainCard({required this.brainData, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF6C5CE7);
    final items = <Map<String, String>>[];

    for (final m in brainData.methods.take(3)) {
      final map = m as Map;
      items.add({
        'icon':  '💡',
        'label': map['title']?.toString() ?? map['name']?.toString() ?? '',
        'sub':   map['category']?.toString() ?? 'Method',
      });
    }
    for (final m in brainData.marketplace.take(2)) {
      final map = m as Map;
      items.add({
        'icon':  '🛒',
        'label': map['title']?.toString() ?? '',
        'sub':   map['type']?.toString() ?? 'Marketplace',
      });
    }
    for (final m in brainData.serviceProviders.take(2)) {
      final map = m as Map;
      items.add({
        'icon':  '🔧',
        'label': map['name']?.toString() ?? '',
        'sub':   map['service']?.toString() ?? 'Provider',
      });
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [color.withOpacity(0.10), color.withOpacity(0.04)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧠', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text('RiseUp Brain Found',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87)),
        ]),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Text(item['icon']!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item['label']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87)),
                      Text(item['sub']!,
                          style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38)),
                    ])),
              ]),
            )),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Complementary Users Row — v17
// ─────────────────────────────────────────────────────────────────────────────
class _ComplementaryUsersRow extends StatelessWidget {
  final List<dynamic> users;
  final bool          isDark;
  final void Function(String userId, String name, String avatar) onTap;

  const _ComplementaryUsersRow({
    required this.users,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('👥 People who can help',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45)),
      ),
      SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: users.length,
          itemBuilder: (_, i) {
            final u      = users[i] as Map;
            final userId = u['user_id']?.toString()  ?? u['id']?.toString() ?? '';
            final name   = u['full_name']?.toString() ?? u['username']?.toString() ?? 'User';
            final avatar = u['avatar_url']?.toString() ?? '';
            final reason = u['match_reason']?.toString() ?? '';
            final isUrl  = avatar.startsWith('http');

            return GestureDetector(
              onTap: () => onTap(userId, name, avatar),
              child: Container(
                width: 60,
                margin: EdgeInsets.only(right: i < users.length - 1 ? 10 : 0),
                child: Column(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      gradient: isUrl
                          ? null
                          : const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent]),
                      image: isUrl
                          ? DecorationImage(
                              image: NetworkImage(avatar),
                              fit: BoxFit.cover)
                          : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: isUrl
                        ? null
                        : Center(
                            child: Text(name.isNotEmpty
                                ? name[0].toUpperCase() : '👤',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(height: 4),
                  Text(name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500)),
                  if (reason.isNotEmpty)
                    Text(reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 8,
                            color: isDark
                                ? Colors.white38
                                : Colors.black38)),
                ]),
              ),
            );
          },
        ),
      ),
    ]).animate().fadeIn(duration: 300.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegation Card
// ─────────────────────────────────────────────────────────────────────────────
class _DelegationCard extends StatelessWidget {
  final _DelegationPayload payload;
  final bool               isDark;
  final VoidCallback        onLaunch;
  const _DelegationCard(
      {required this.payload, required this.isDark, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final isApex = payload.type == _DelegationType.apex;
    final color  = isApex ? AppColors.primary : AppColors.success;
    final icon   = isApex ? '🤖' : '⚡';
    final label  = isApex ? 'Launch APEX Agent' : 'Build Workflow';
    final desc   = isApex
        ? 'APEX will open a browser and handle this task automatically'
        : 'Workflow Engine will build your step-by-step income plan';

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [color.withOpacity(0.10), color.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87))),
        ]),
        const SizedBox(height: 4),
        Text(desc,
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
                height: 1.4)),
        const SizedBox(height: 10),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onLaunch,
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              child: Text(label),
            )),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action Bar
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionBar extends StatelessWidget {
  final bool         isDark;
  final VoidCallback onApex, onWorkflow, onSearch;
  const _QuickActionBar({
    required this.isDark,
    required this.onApex,
    required this.onWorkflow,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF5F5F8);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        _chip('🤖 APEX',    'Handle task for me',   AppColors.primary, onApex),
        const SizedBox(width: 8),
        _chip('⚡ Workflow', 'Build income plan',    AppColors.success, onWorkflow),
        const SizedBox(width: 8),
        _chip('🔍 Search',  'Find contacts / jobs', AppColors.info,    onSearch),
      ]),
    );
  }

  Widget _chip(String label, String tooltip, Color color, VoidCallback onTap) =>
      Expanded(
          child: Tooltip(
              message: tooltip,
              child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.25))),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700))))));
}

// ─────────────────────────────────────────────────────────────────────────────
// Quota Ribbon (v16 fix preserved)
// ─────────────────────────────────────────────────────────────────────────────
class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inDailyLockout, inCycleLockout;
  final int  freeUsed, freeTotal, cycleAds, adsPerCycle, cycleMsgs, msgsPerCycle;
  final int  totalResponses, maxResponses;
  final String? cycleLockoutUntil, dailyLockoutUntil;
  final VoidCallback onWatchAds;

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
    required this.onWatchAds,
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

  @override
  void didUpdateWidget(_QuotaRibbon old) {
    super.didUpdateWidget(old);
    if ((widget.inCycleLockout || widget.inDailyLockout) && _timer == null)
      _startTimer();
    if (!widget.inCycleLockout && !widget.inDailyLockout) {
      _timer?.cancel();
      _timer = null;
    }
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

    if (widget.inDailyLockout)
      return _ribbon(Icons.lock_rounded, AppColors.error,
          'Daily limit reached${_countdown.isNotEmpty ? ' · resets in $_countdown' : ''}',
          AppColors.error.withOpacity(0.08), null);

    if (widget.inCycleLockout)
      return _ribbon(Icons.hourglass_bottom_rounded, AppColors.warning,
          'Take a break${_countdown.isNotEmpty ? ' · unlocks in $_countdown' : ''}',
          AppColors.warning.withOpacity(0.08), null);

    final freeLeft = widget.freeTotal - widget.freeUsed;

    if (freeLeft > 0)
      return _ribbon(Icons.chat_bubble_outline_rounded, AppColors.primary,
          '$freeLeft free message${freeLeft == 1 ? '' : 's'} remaining',
          AppColors.primary.withOpacity(0.06), null);

    if (widget.cycleAds < widget.adsPerCycle) {
      final adsLeft = widget.adsPerCycle - widget.cycleAds;
      return _ribbon(
        Icons.play_circle_outline_rounded, AppColors.warning,
        'Watch $adsLeft ad${adsLeft == 1 ? '' : 's'} to unlock ${widget.msgsPerCycle} messages',
        AppColors.warning.withOpacity(0.08),
        widget.onWatchAds,
      );
    }

    if (widget.cycleAds >= widget.adsPerCycle) {
      final left = widget.msgsPerCycle - widget.cycleMsgs;
      if (left > 0)
        return _ribbon(Icons.lock_open_rounded, AppColors.success,
            '$left message${left == 1 ? '' : 's'} left · ${widget.totalResponses}/${widget.maxResponses} today',
            Colors.transparent, null);
    }

    return const SizedBox.shrink();
  }

  Widget _ribbon(IconData icon, Color color, String label,
      Color bg, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: bg,
          child: Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500))),
            if (onTap != null)
              Text('Tap to watch',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => GoRouter.of(context).go('/premium'),
              child: const Text('Go Premium',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ad Gate Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _AdGateSheet extends StatefulWidget {
  final int cycleAdsWatched, adsPerCycle, msgsPerCycle, totalResponses, maxResponses;
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
      setState(() => _error = 'Ad not ready. Try again in a moment.');
      return;
    }
    setState(() { _watching = true; _error = null; });
    await adService.showRewardedAd(
      featureKey: 'ai_chat',
      onRewarded: () async {
        await widget.onAdWatched();
        if (!mounted) return;
        setState(() { _localWatched++; _watching = false; });
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
          _error    = 'Watch the full ad to unlock messages.';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg   = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white     : Colors.black87;
    final sub  = isDark ? Colors.white60   : Colors.black54;

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
        _success
            ? const Text('🎉', style: TextStyle(fontSize: 56))
            : Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle),
                child: const Center(
                    child: Text('🤖', style: TextStyle(fontSize: 36)))),
        const SizedBox(height: 16),
        Text(_success ? 'Unlocked! 🚀' : 'Unlock AI Messages',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        if (!_success) ...[
          Text(
              'Watch $_adsRemaining more ad${_adsRemaining == 1 ? '' : 's'} '
              'to unlock ${widget.msgsPerCycle} messages.',
              style:     TextStyle(fontSize: 14, color: sub, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.adsPerCycle, (i) => Padding(
                    padding: EdgeInsets.only(
                        right: i < widget.adsPerCycle - 1 ? 6 : 0),
                    child: AnimatedContainer(
                        duration: 300.ms,
                        width: 28, height: 8,
                        decoration: BoxDecoration(
                          color: i < _totalWatched
                              ? AppColors.success
                              : AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4)))))),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style:     const TextStyle(fontSize: 12, color: AppColors.error),
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context, false);
                  GoRouter.of(context).go('/premium');
                },
                icon: const Icon(
                    Icons.workspace_premium_rounded, size: 18),
                label: const Text('Go Premium — Unlimited AI'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.gold),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))))),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Not now',
                style: TextStyle(color: sub, fontSize: 13))),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lockout Sheet
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
    final exp = DateTime.tryParse(widget.lockoutUntil);
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
    final bg   = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white     : Colors.black87;
    final sub  = isDark ? Colors.white60   : Colors.black54;
    final title = _expired
        ? (widget.isDaily ? 'Daily Limit Reset! ✅' : 'Break Over! ✅')
        : (widget.isDaily ? 'Daily Limit Reached'  : 'Time for a Break ⏸️');

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
        Text(_expired ? '✅' : (widget.isDaily ? '🔒' : '⏸️'),
            style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          _expired
              ? (widget.isDaily
                  ? 'Daily limit reset. Watch ads to keep chatting!'
                  : 'Break over — watch ads to unlock more!')
              : (widget.isDaily
                  ? 'Used all 30 responses today. Upgrade for unlimited.'
                  : 'Take a 3-hour break, then watch ads for more.'),
          style:     TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center),
        if (!_expired) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(widget.isDaily ? 'Resets in' : 'Unlocks in',
                  style: TextStyle(fontSize: 12, color: sub)),
              const SizedBox(height: 6),
              Text(_countdown,
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: text,
                      fontFamily: 'monospace',
                      letterSpacing: 2)),
            ])),
        ],
        const SizedBox(height: 24),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onUpgrade,
              icon: const Icon(
                  Icons.workspace_premium_rounded, size: 20),
              label: const Text('Upgrade — Unlimited AI Forever'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_expired ? 'Start chatting!' : 'Come back later',
              style: TextStyle(color: sub, fontSize: 13))),
      ]),
    );
  }
}
