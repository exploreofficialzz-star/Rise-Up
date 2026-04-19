// frontend/lib/screens/messages/ai_mentor_screen.dart
// RiseUp AI Mentor — Production v4
//
// v4 complete rewrite of data layer (UI unchanged from v3.1):
//  • Uses messages.py conversation API — REAL persistent chat history
//    - GET  /messages/ai-conversation            → get/create the AI DM conversation
//    - GET  /messages/conversations/{id}/messages → restore history on every open
//    - POST /messages/conversations/{id}/ai-message → send user message, get AI reply
//  • Quota synced from server on every response (no more stale local counters)
//  • _kAdsPerCycle = 1  (one ad unlocks 3 messages for 4 hours — matches backend)
//  • APEX launch: try /agent/handoff first, graceful degradation to /agent + snack
//  • Workflow launch: try-catch so navigation error never crashes the screen
//  • Service unavailable shows a friendly inline error bubble, never an exception
//  • All history restored immediately on screen open — no re-greeting on return
//
// Route: /ai-mentor
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
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_constants.dart';
import '../../services/ad_service.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const int      _kFreeMessages = 3;   // matches backend FREE_MSGS_PER_WINDOW
const int      _kAdsPerCycle  = 1;   // 1 ad = 1 unlock window
const int      _kMsgsPerCycle = 3;   // messages gained per ad watch
const int      _kMaxAdsDay    = 5;   // matches backend MAX_AD_UNLOCKS_PER_DAY

const List<String> _kAiErrorPhrases = [
  'experiencing technical difficulties',
  'please try again in a moment',
  'service is temporarily unavailable',
  'something went wrong',
  'unable to process',
  'i am currently unavailable',
  'experiencing a brief connectivity issue',
];

// ─────────────────────────────────────────────────────────────────────────────
// Brain data model
// ─────────────────────────────────────────────────────────────────────────────
class _BrainData {
  final String intent;
  final bool internalFound;
  final List methods, marketplace, serviceProviders, complementaryUsers;
  final bool needsExternal;
  final String? escalationReason, suggestedTaskType;

  const _BrainData({
    this.intent             = 'explore',
    this.internalFound      = false,
    this.methods            = const [],
    this.marketplace        = const [],
    this.serviceProviders   = const [],
    this.complementaryUsers = const [],
    this.needsExternal      = false,
    this.escalationReason,
    this.suggestedTaskType,
  });

  bool get hasResults =>
      methods.isNotEmpty || marketplace.isNotEmpty || serviceProviders.isNotEmpty;
  bool get hasComplementary => complementaryUsers.isNotEmpty;

  factory _BrainData.fromResponse(Map<String, dynamic> r) => _BrainData(
        intent:             r['brain_intent']?.toString()           ?? 'explore',
        internalFound:      r['brain_internal_found']               == true,
        methods:            (r['brain_methods']           as List?)  ?? [],
        marketplace:        (r['brain_marketplace']       as List?)  ?? [],
        serviceProviders:   (r['brain_service_providers'] as List?)  ?? [],
        needsExternal:      r['brain_needs_external']               == true,
        escalationReason:   r['brain_escalation_reason']?.toString(),
        suggestedTaskType:  r['brain_suggested_task_type']?.toString(),
        complementaryUsers: (r['complementary_users']     as List?)  ?? [],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegation model
// ─────────────────────────────────────────────────────────────────────────────
enum _DelegationType { apex, workflow, none }

class _DelegationPayload {
  final _DelegationType type;
  final String task, sessionId, message;
  const _DelegationPayload({
    required this.type,
    required this.task,
    required this.sessionId,
    required this.message,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Message model
// ─────────────────────────────────────────────────────────────────────────────
class _Msg {
  final String id;
  final bool isMe, isAI, isError;
  bool isDeleted, isTyping;
  String content, displayText;
  _BrainData? brainData;
  _DelegationPayload? delegation;
  final DateTime time;

  _Msg({
    String? id,
    required this.content,
    required this.isMe,
    this.isAI      = false,
    this.isError   = false,
    this.isDeleted = false,
    this.brainData,
    this.delegation,
    DateTime? time,
  })  : id          = id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        displayText = content,
        isTyping    = false,
        time        = time ?? DateTime.now();
}

enum _QuotaResult { allowed, showAdGate, hardLockout }

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class AiMentorScreen extends StatefulWidget {
  final String? postContext;
  final String? postAuthor;
  const AiMentorScreen({super.key, this.postContext, this.postAuthor});

  @override
  State<AiMentorScreen> createState() => _AiMentorScreenState();
}

class _AiMentorScreenState extends State<AiMentorScreen> {
  final _textCtrl   = TextEditingController();
  final _scroll     = ScrollController();
  final _inputFocus = FocusNode();
  final List<_Msg> _msgs = [];

  bool _historyLoaded    = false;
  bool _aiResponding     = false;
  bool _scrollLocked     = false;
  bool _showQuickActions = false;

  /// The persistent AI DM conversation ID (from messages.py).
  String? _conversationId;
  String? _cachedMyName;
  String? _lastSentText;

  Timer? _typingTimer;

  // ── Server-driven quota — synced from /messages/ai-quota and each response ──
  Map<String, dynamic> _quota = {
    'free_used':      0,
    'free_remaining': _kFreeMessages,
    'window_expires': null,
    'is_premium':     false,
    'ads_today':      0,
    'max_ads_day':    _kMaxAdsDay,
    'in_window':      false,
  };

  bool   get _isPremium     => _quota['is_premium']     == true;
  int    get _freeRemaining => (_quota['free_remaining'] as int?) ?? _kFreeMessages;
  int    get _freeUsed      => (_quota['free_used']      as int?) ?? 0;
  int    get _adsToday      => (_quota['ads_today']      as int?) ?? 0;
  bool   get _inWindow      => _quota['in_window']       == true;
  String? get _windowExpires => _quota['window_expires'] as String?;

  _QuotaResult _checkQuota() {
    if (_isPremium) return _QuotaResult.allowed;
    if (_inWindow)  return _QuotaResult.allowed;
    if (_freeRemaining > 0) return _QuotaResult.allowed;
    if (_adsToday >= _kMaxAdsDay) return _QuotaResult.hardLockout;
    return _QuotaResult.showAdGate;
  }

  void _applyQuotaMap(Map? q) {
    if (q == null || !mounted) return;
    setState(() {
      if (q['free_used']       != null) _quota['free_used']      = q['free_used'];
      if (q['free_remaining']  != null) _quota['free_remaining'] = q['free_remaining'];
      if (q['is_premium']      != null) _quota['is_premium']     = q['is_premium'];
      if (q['max_ads_day']     != null) _quota['max_ads_day']    = q['max_ads_day'];

      // Accept both field names from different response shapes
      final exp = q['window_expires'];
      if (exp != null) _quota['window_expires'] = exp;

      final adsToday = q['ads_today'] ?? q['ads_count'];
      if (adsToday != null) _quota['ads_today'] = adsToday;

      // in_unlocked_window (from /ai-quota) OR compute from window_expires
      if (q['in_unlocked_window'] != null) {
        _quota['in_window'] = q['in_unlocked_window'];
      } else {
        final expStr = _quota['window_expires'] as String?;
        if (expStr == null) {
          _quota['in_window'] = false;
        } else {
          final dt = DateTime.tryParse(expStr);
          _quota['in_window'] = dt != null && DateTime.now().isBefore(dt);
        }
      }
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bootstrap();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _textCtrl.dispose();
    _inputFocus.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {}

  Future<void> _bootstrap() async {
    await _fetchMyInfo();
    await _loadQuota();
    await _initConversation();
    await _loadHistory();
    if (widget.postContext?.isNotEmpty == true) {
      await Future.delayed(const Duration(milliseconds: 600));
      await _sendAI(
        'I want to discuss a post: "${widget.postContext}"\nGive me a quick wealth insight.',
        isContext: true,
      );
    }
  }

  // ── User info ──────────────────────────────────────────────────────────────
  Future<void> _fetchMyInfo() async {
    try {
      final userId = await api.getUserId();
      if (userId != null) {
        final p = await api.getUserProfile(userId);
        _cachedMyName = (p['full_name'] as String?)?.trim();
        if (_cachedMyName?.isEmpty != false) {
          _cachedMyName = (p['username'] as String?)?.trim();
        }
      }
    } catch (_) {}
  }

  // ── Quota ──────────────────────────────────────────────────────────────────
  Future<void> _loadQuota() async {
    try {
      final remote = await api.getAIQuota();
      _applyQuotaMap(remote);
    } catch (_) {}
  }

  // ── Conversation bootstrap ─────────────────────────────────────────────────
  /// Gets or creates the dedicated AI DM conversation from messages.py.
  Future<void> _initConversation() async {
    try {
      final res = await api.get('/messages/ai-conversation');
      _conversationId = res['conversation_id']?.toString();
    } catch (e) {
      debugPrint('[AiMentorScreen] _initConversation failed: $e');
    }
  }

  // ── History ────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_conversationId == null) {
      // Conversation could not be created — show greeting as fallback
      if (mounted) setState(() => _historyLoaded = true);
      _showGreeting();
      return;
    }

    try {
      final res = await api.get(
        '/messages/conversations/$_conversationId/messages',
        queryParams: {'limit': '100'},
      );
      final msgs = (res['messages'] as List?) ?? [];

      if (!mounted) return;

      if (msgs.isNotEmpty) {
        final built = <_Msg>[];
        for (final raw in msgs) {
          final m          = raw as Map;
          final senderType = m['sender_type']?.toString() ?? 'user';
          final role       = m['role']?.toString()        ?? 'user';
          final isAI       = senderType == 'ai'  || role == 'assistant';
          final isSys      = senderType == 'system' || role == 'system';
          final content    = m['content']?.toString() ?? '';
          if (isSys) continue;
          if (content.isEmpty) continue;
          if (isAI && _isErrorPhrase(content)) continue;
          built.add(_Msg(
            id:    m['id']?.toString(),
            content: content,
            isMe:  !isAI,
            isAI:  isAI,
            time:  DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
          ));
        }

        setState(() {
          _msgs
            ..clear()
            ..addAll(built);
          _historyLoaded = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown(jump: true));
        return;
      }
    } catch (e) {
      debugPrint('[AiMentorScreen] _loadHistory error: $e');
    }

    // No messages yet — show greeting bubble
    if (mounted) setState(() => _historyLoaded = true);
    _showGreeting();
  }

  void _showGreeting() {
    if (!mounted) return;
    final name = _cachedMyName?.split(' ').first ?? 'there';
    final greeting = _Msg(
      content: 'Hey $name 👋 Welcome to RiseUp!\n\n'
          "I'm your AI Wealth Mentor — built to help you build income, "
          'grow wealth, and level up your finances. 💰\n\n'
          'I can also hand tasks to **APEX** — your autonomous agent that '
          'opens browsers, fills forms, and handles things end-to-end for you.\n\n'
          'Ask me anything or just say **"do it for me"** and I\'ll launch APEX. 🚀',
      isMe: false,
      isAI: true,
    );
    setState(() => _msgs.add(greeting));
    _typeMessage(greeting);
  }

  bool _isErrorPhrase(String content) {
    final lower = content.toLowerCase();
    return _kAiErrorPhrases.any((p) => lower.contains(p));
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _aiResponding) return;
    setState(() => _showQuickActions = false);
    _lastSentText = text;

    switch (_checkQuota()) {
      case _QuotaResult.showAdGate:
        await _showAdGate(text);
        return;
      case _QuotaResult.hardLockout:
        _showLockoutSheet();
        return;
      case _QuotaResult.allowed:
        break;
    }
    await _sendAI(text);
  }

  Future<void> _sendAI(
    String text, {
    bool adUnlocked = false,
    bool isContext  = false,
  }) async {
    if (_conversationId == null) {
      // Retry initializing conversation once
      await _initConversation();
      if (_conversationId == null) {
        _addErrorBubble('Could not connect to AI. Please check your connection and try again.');
        return;
      }
    }

    _textCtrl.clear();
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _msgs.add(_Msg(id: localId, content: text, isMe: true));
      _aiResponding = true;
    });
    _scrollDown();

    try {
      final res = await api.post(
        '/messages/conversations/$_conversationId/ai-message',
        {'content': text, 'ad_unlocked': adUnlocked},
      );

      // ── Sync quota from response ──────────────────────────────────────────
      _applyQuotaMap(res['quota'] as Map?);

      final aiContent = (res['content'] ?? res['message']?['content'] ?? '').toString().trim();

      if (aiContent.isEmpty || _isErrorPhrase(aiContent)) {
        if (!mounted) return;
        setState(() {
          _aiResponding = false;
          _msgs.removeWhere((m) => m.id == localId);
        });
        _addErrorBubble('AI is temporarily unavailable. Please try again. 🔄');
        _showRetrySnack(text);
        return;
      }

      if (!mounted) return;

      // Parse brain / delegation signals from response
      final brainData = _BrainData.fromResponse(Map<String, dynamic>.from(res));
      _DelegationPayload? del;
      del ??= _inferDelegation(aiContent, _conversationId ?? '');
      if (del == null && brainData.needsExternal) {
        del = _DelegationPayload(
          type: _DelegationType.workflow,
          task: _extractTask(aiContent),
          sessionId: _conversationId ?? '',
          message: aiContent,
        );
      }

      final aiMsg = _Msg(
        content: aiContent, isMe: false, isAI: true,
        brainData: brainData, delegation: del,
      );
      setState(() { _aiResponding = false; _msgs.add(aiMsg); });
      _typeMessage(aiMsg);

    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _aiResponding = false; _msgs.removeWhere((m) => m.id == localId); });

      // Try to sync quota data from error body
      if (e.body is Map) _applyQuotaMap(e.body as Map);

      if (e.statusCode == 402) {
        await _showAdGate(text);
      } else if (e.statusCode == 429) {
        _showLockoutSheet();
      } else if (e.statusCode == 503) {
        _addErrorBubble('AI service is temporarily unavailable. Please try again shortly.');
        _showRetrySnack(text);
      } else {
        _addErrorBubble('Error ${e.statusCode}. Please try again.');
        _showRetrySnack(text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiResponding = false; _msgs.removeWhere((m) => m.id == localId); });
      _addErrorBubble('Could not reach AI. Please check your connection and try again.');
      _showRetrySnack(text);
    }
  }

  // ── Delegation inference ──────────────────────────────────────────────────
  _DelegationPayload? _inferDelegation(String content, String sessionId) {
    final lower = content.toLowerCase();
    const apexKw = [
      'launch apex', 'apex will', 'do it for you', 'set it up for you',
      'apply for you', 'handle this for you', 'create the account',
      'sign you up', 'activating apex', "i'll set up",
    ];
    if (apexKw.any((k) => lower.contains(k))) {
      return _DelegationPayload(
        type: _DelegationType.apex,
        task: _extractTask(content),
        sessionId: sessionId,
        message: content,
      );
    }
    const wfKw = [
      'build you a workflow', 'create a workflow', 'step-by-step plan',
      'income plan', 'build a roadmap', 'action plan',
    ];
    if (wfKw.any((k) => lower.contains(k))) {
      return _DelegationPayload(
        type: _DelegationType.workflow,
        task: _extractTask(content),
        sessionId: sessionId,
        message: content,
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

  // ── APEX launch — crash-safe ───────────────────────────────────────────────
  Future<void> _launchApex(String task, String sessionId) async {
    HapticFeedback.mediumImpact();
    if (!mounted) return;

    try {
      final res = await api.post('/agent/handoff', {
        'task': task, 'source': 'mentor', 'source_conv_id': sessionId,
      });
      final apexId    = res['session_id']?.toString() ?? '';
      final questions = (res['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted) return;
      context.push('/agent', extra: {
        'handoffTask':      task,
        'handoffSessionId': apexId.isNotEmpty ? apexId : null,
        'handoffTemplate':  res['template'],
        'handoffQuestions': questions,
      });
    } catch (_) {
      if (!mounted) return;
      // Graceful degradation — open APEX without handoff context
      try {
        context.push('/agent', extra: {'handoffTask': task});
      } catch (_) {
        // Navigation itself failed — show snack, never crash
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('APEX is temporarily unavailable. Please try again shortly.'),
          backgroundColor: AppColors.bgCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  // ── Workflow launch — crash-safe ───────────────────────────────────────────
  void _launchWorkflow(String goal) {
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    try {
      context.push('/workflow/new', extra: {'prefillGoal': goal});
    } catch (_) {
      try {
        context.push('/workflow/new');
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Workflow engine is temporarily unavailable.'),
          backgroundColor: AppColors.bgCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  // ── Bubble long-press menu ─────────────────────────────────────────────────
  void _showBubbleMenu(BuildContext ctx, _Msg m) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2))),
          _menuItem(Icons.copy_rounded, 'Copy', isDark, () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: m.content));
            _showSnack('Copied ✓');
          }),
          if (!m.isMe && m.isAI && !m.isError && !m.isDeleted)
            _menuItem(Icons.share_rounded, 'Share insight', isDark, () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(
                  text: '💡 RiseUp AI:\n\n${m.content}\n\n— via RiseUp'));
              _showSnack('Copied to share! ✓');
            }),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
        ]),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, bool isDark, VoidCallback onTap,
      {Color? color}) =>
      ListTile(
        leading: Icon(icon, color: color ?? AppColors.primary, size: 20),
        title: Text(label,
            style: TextStyle(
                color: color ?? (isDark ? Colors.white : Colors.black87),
                fontSize: 14, fontWeight: FontWeight.w500)),
        onTap: onTap, dense: true,
      );

  // ── Typing animation ───────────────────────────────────────────────────────
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
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  void _addErrorBubble(String msg) {
    if (!mounted) return;
    setState(() =>
        _msgs.add(_Msg(content: msg, isMe: false, isAI: true, isError: true)));
    _scrollDown();
  }

  void _showRetrySnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Tap Retry to resend'),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.bgCard,
      action: SnackBarAction(
        label: 'Retry',
        textColor: AppColors.primary,
        onPressed: () { if (mounted) _sendAI(text); },
      ),
    ));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.success,
    ));
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

  // ── Ad gate ────────────────────────────────────────────────────────────────
  Future<void> _showAdGate(String pendingText) async {
    final success = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      isDismissible: true, backgroundColor: Colors.transparent,
      builder: (_) => _AdGateSheet(
        adsWatchedToday: _adsToday,
        maxAdsDay: _kMaxAdsDay,
        msgsPerUnlock: _kMsgsPerCycle,
        onAdWatched: () async {
          if (!mounted) return;
          setState(() {
            _quota['ads_today'] = _adsToday + 1;
          });
        },
      ),
    );
    if (success != true || !mounted) return;
    await _sendAI(pendingText, adUnlocked: true);
  }

  void _showLockoutSheet() =>
      showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LockoutSheet(
          windowExpires: _windowExpires ?? '',
          onUpgrade: () { Navigator.pop(context); context.go('/premium'); },
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? Colors.black        : Colors.white;
    final card      = isDark ? AppColors.bgCard    : Colors.white;
    final border    = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white        : Colors.black87;
    final subColor  = isDark ? Colors.white54      : Colors.black45;
    final surf      = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, card, border, textColor),
      body: Column(children: [
        if (!_isPremium)
          _QuotaRibbon(
            isPremium: _isPremium,
            freeUsed: _freeUsed,
            freeTotal: _kFreeMessages,
            freeRemaining: _freeRemaining,
            inWindow: _inWindow,
            windowExpires: _windowExpires,
            adsToday: _adsToday,
            maxAdsDay: _kMaxAdsDay,
            onWatchAds: () => _showAdGate(_lastSentText ?? ''),
          ),
        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : ListView.builder(
                  controller: _scroll,
                  physics: _scrollLocked
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _msgs.length + (_aiResponding ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) return _buildTypingIndicator(isDark, surf);
                    return _buildBubble(_msgs[i], isDark, textColor, surf);
                  },
                ),
        ),
        if (_showQuickActions)
          _QuickActionBar(
            isDark: isDark,
            onApex: () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Do it for me: ';
              _inputFocus.requestFocus();
            },
            onWorkflow: () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Build me a plan: ';
              _inputFocus.requestFocus();
            },
            onSearch: () {
              setState(() => _showQuickActions = false);
              _textCtrl.text = 'Find me: ';
              _inputFocus.requestFocus();
            },
          ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0),
        _buildInputBar(isDark, card, border, textColor, subColor, surf),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(
      bool isDark, Color card, Color border, Color text) =>
      AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
          onPressed: () => Navigator.of(context).canPop()
              ? context.pop() : context.go('/messages'),
        ),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('RiseUp AI Mentor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('AI',
                    style: TextStyle(color: Colors.white, fontSize: 8,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const Text('Always online',
                style: TextStyle(fontSize: 11, color: AppColors.success)),
          ]),
        ]),
        actions: [
          Container(margin: const EdgeInsets.only(right: 4), width: 9, height: 9,
              decoration: const BoxDecoration(
                  color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      );

  Widget _buildInputBar(bool isDark, Color card, Color border,
      Color text, Color sub, Color surf) =>
      Container(
        decoration: BoxDecoration(
            color: card, border: Border(top: BorderSide(color: border))),
        padding: EdgeInsets.fromLTRB(
            12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            icon: Icon(
                _showQuickActions ? Icons.close_rounded : Icons.auto_awesome_rounded,
                color: _showQuickActions ? AppColors.primary : sub, size: 22),
            onPressed: () => setState(() => _showQuickActions = !_showQuickActions),
          ),
          Expanded(
            child: TextField(
              controller: _textCtrl, focusNode: _inputFocus,
              style: TextStyle(fontSize: 14, color: text),
              maxLines: 5, minLines: 1, enabled: !_aiResponding,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask your wealth mentor...',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                filled: true, fillColor: surf,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: _aiResponding ? null : (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _aiResponding ? null : () {
              HapticFeedback.lightImpact(); _onSend();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _aiResponding
                    ? [Colors.grey.shade500, Colors.grey.shade500]
                    : [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(child: _aiResponding
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18)),
            ),
          ),
        ]),
      );

  Widget _buildBubble(_Msg m, bool isDark, Color textColor, Color surf) {
    final aiBg    = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final errorBg = isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF0F0);
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
                const Text('RiseUp AI',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(width: 3),
                const Icon(Icons.auto_awesome, size: 10, color: AppColors.primary),
                if (m.brainData?.internalFound ?? false) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6C5CE7), Color(0xFF00B894)]),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('🧠 Brain',
                        style: TextStyle(color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w700)),
                  ),
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                      child: Text('🤖', style: TextStyle(fontSize: 14))),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showBubbleMenu(context, m),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(18),
                        topRight:    const Radius.circular(18),
                        bottomLeft:  Radius.circular(m.isMe ? 18 : 4),
                        bottomRight: Radius.circular(m.isMe ? 4 : 18),
                      ),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: (m.isMe || !m.isAI)
                        ? SelectionArea(child: Text(m.displayText,
                            style: TextStyle(
                                color: m.isMe ? Colors.white
                                    : m.isError ? AppColors.error : textColor,
                                fontSize: 14, height: 1.5)))
                        : SelectionArea(child: MarkdownBody(
                            data: m.displayText,
                            onTapLink: (_, href, __) {
                              if (href != null) _openLink(href);
                            },
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                  color: m.isError ? AppColors.error
                                      : isDark ? const Color(0xFFE8E8F0) : Colors.black87,
                                  fontSize: 14, height: 1.55),
                              strong: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight),
                              a: const TextStyle(color: AppColors.primary,
                                  decoration: TextDecoration.underline),
                              code: TextStyle(fontFamily: 'monospace',
                                  backgroundColor: isDark
                                      ? const Color(0xFF2A2A3E)
                                      : Colors.grey.shade200,
                                  fontSize: 13),
                            ))),
                  ),
                ),
              ),
            ],
          ),

          if (!m.isError && !m.isDeleted &&
              m.delegation != null && m.delegation!.type != _DelegationType.none)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 36),
              child: _DelegationCard(
                payload: m.delegation!, isDark: isDark,
                onLaunch: () => m.delegation!.type == _DelegationType.apex
                    ? _launchApex(m.delegation!.task, m.delegation!.sessionId)
                    : _launchWorkflow(m.delegation!.task),
              ),
            ),

          if (!m.isError && !m.isDeleted && m.isAI &&
              (m.brainData?.hasResults ?? false) && !m.isTyping)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: _BrainCard(brainData: m.brainData!, isDark: isDark),
            ),

          if (!m.isError && !m.isDeleted && m.isAI &&
              (m.brainData?.hasComplementary ?? false) && !m.isTyping)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: _ComplementaryRow(
                users: m.brainData!.complementaryUsers, isDark: isDark,
                onTap: (uid, name, av) => context.push(Uri(
                  path: '/conversation/$uid',
                  queryParameters: {'name': name, if (av.isNotEmpty) 'avatar': av},
                ).toString()),
              ),
            ),

          Padding(
            padding: EdgeInsets.only(
                top: 4, left: m.isMe ? 0 : 40, right: m.isMe ? 4 : 0),
            child: Text(_fmt(m.time),
                style: TextStyle(fontSize: 10,
                    color: isDark ? Colors.white24 : Colors.black26)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms)
        .slideY(begin: 0.08, curve: Curves.easeOut);
  }

  Widget _buildTypingIndicator(bool isDark, Color surf) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                shape: BoxShape.circle),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
                color: isDark ? AppColors.aiBubble : surf,
                borderRadius: BorderRadius.circular(18)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .fadeIn(delay: Duration(milliseconds: i * 200))
                      .then().fadeOut()),
            ),
          ),
        ]),
      );

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Brain Card
// ─────────────────────────────────────────────────────────────────────────────
class _BrainCard extends StatelessWidget {
  final _BrainData brainData;
  final bool isDark;
  const _BrainCard({required this.brainData, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF6C5CE7);
    final items = <Map<String, String>>[];
    for (final m in brainData.methods.take(3)) {
      final map = m as Map;
      items.add({'icon': '💡',
        'label': map['title']?.toString() ?? map['name']?.toString() ?? '',
        'sub': map['category']?.toString() ?? 'Method'});
    }
    for (final m in brainData.marketplace.take(2)) {
      final map = m as Map;
      items.add({'icon': '🛒',
        'label': map['title']?.toString() ?? '',
        'sub': map['type']?.toString() ?? 'Marketplace'});
    }
    for (final m in brainData.serviceProviders.take(2)) {
      final map = m as Map;
      items.add({'icon': '🔧',
        'label': map['name']?.toString() ?? '',
        'sub': map['service']?.toString() ?? 'Provider'});
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withOpacity(0.10), color.withOpacity(0.04)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧠', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text('RiseUp Brain Found',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87)),
        ]),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Text(item['icon']!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['label']!, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  Text(item['sub']!, style: TextStyle(fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.black38)),
                ])),
              ]),
            )),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Complementary Users Row
// ─────────────────────────────────────────────────────────────────────────────
class _ComplementaryRow extends StatelessWidget {
  final List users;
  final bool isDark;
  final void Function(String userId, String name, String avatar) onTap;
  const _ComplementaryRow(
      {required this.users, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('👥 People who can help',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45)),
      ),
      SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: users.length,
          itemBuilder: (_, i) {
            final u      = users[i] as Map;
            final userId = u['user_id']?.toString() ?? u['id']?.toString() ?? '';
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
                      gradient: isUrl ? null
                          : const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent]),
                      image: isUrl ? DecorationImage(
                          image: NetworkImage(avatar), fit: BoxFit.cover) : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.4), width: 1.5),
                    ),
                    child: isUrl ? null : Center(child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '👤',
                        style: const TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(height: 4),
                  Text(name.split(' ').first, maxLines: 1,
                      overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500)),
                  if (reason.isNotEmpty)
                    Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 8,
                            color: isDark ? Colors.white38 : Colors.black38)),
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
  final bool isDark;
  final VoidCallback onLaunch;
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
        gradient: LinearGradient(colors: [
          color.withOpacity(0.10), color.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87))),
        ]),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45, height: 1.4)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: onLaunch,
              style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.white,
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
  final bool isDark;
  final VoidCallback onApex, onWorkflow, onSearch;
  const _QuickActionBar({required this.isDark, required this.onApex,
      required this.onWorkflow, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF5F5F8);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        _chip('🤖 APEX',    AppColors.primary, onApex),
        const SizedBox(width: 8),
        _chip('⚡ Workflow', AppColors.success, onWorkflow),
        const SizedBox(width: 8),
        _chip('🔍 Search',  AppColors.info,    onSearch),
      ]),
    );
  }

  Widget _chip(String label, Color color, VoidCallback onTap) =>
      Expanded(child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.25))),
            child: Text(label, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: color,
                    fontWeight: FontWeight.w700)),
          )));
}


// ─────────────────────────────────────────────────────────────────────────────
// Quota Ribbon  (simplified — server-driven)
// ─────────────────────────────────────────────────────────────────────────────
class _QuotaRibbon extends StatefulWidget {
  final bool isPremium, inWindow;
  final int freeUsed, freeTotal, freeRemaining, adsToday, maxAdsDay;
  final String? windowExpires;
  final VoidCallback onWatchAds;

  const _QuotaRibbon({
    required this.isPremium,
    required this.inWindow,
    required this.freeUsed,
    required this.freeTotal,
    required this.freeRemaining,
    required this.adsToday,
    required this.maxAdsDay,
    required this.onWatchAds,
    this.windowExpires,
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
    if (widget.inWindow && widget.windowExpires != null) _start();
  }

  @override
  void didUpdateWidget(_QuotaRibbon old) {
    super.didUpdateWidget(old);
    if (widget.inWindow && widget.windowExpires != null && _timer == null) _start();
    if (!widget.inWindow) { _timer?.cancel(); _timer = null; }
  }

  void _start() {
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final exp = DateTime.tryParse(widget.windowExpires ?? '');
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

    // In unlocked window
    if (widget.inWindow) {
      final left = widget.freeRemaining;
      return _ribbon(
        Icons.lock_open_rounded, AppColors.success,
        '$left message${left == 1 ? '' : 's'} left'
        '${_countdown.isNotEmpty ? ' · unlocks in $_countdown' : ''}',
        Colors.transparent, null,
      );
    }

    // Daily lockout
    if (widget.adsToday >= widget.maxAdsDay) {
      return _ribbon(Icons.lock_rounded, AppColors.error,
          'Daily limit reached — resets tomorrow',
          AppColors.error.withOpacity(0.08), null);
    }

    // Free messages remaining
    if (widget.freeRemaining > 0) {
      return _ribbon(Icons.chat_bubble_outline_rounded, AppColors.primary,
          '${widget.freeRemaining} free message${widget.freeRemaining == 1 ? '' : 's'} remaining',
          AppColors.primary.withOpacity(0.06), null);
    }

    // Need to watch an ad
    final adsLeft = widget.maxAdsDay - widget.adsToday;
    return _ribbon(Icons.play_circle_outline_rounded, AppColors.warning,
        'Watch an ad for ${_QuotaRibbon._kMsgsPerCycle} more messages · $adsLeft unlock${adsLeft == 1 ? '' : 's'} left today',
        AppColors.warning.withOpacity(0.08), widget.onWatchAds);
  }

  static const _kMsgsPerCycle = 3;

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
            Expanded(child: Text(label, style: TextStyle(fontSize: 12,
                color: color, fontWeight: FontWeight.w500))),
            if (onTap != null)
              Text('Tap to watch', style: TextStyle(fontSize: 11,
                  color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => GoRouter.of(context).go('/premium'),
              child: const Text('Go Premium',
                  style: TextStyle(fontSize: 11, color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
}


// ─────────────────────────────────────────────────────────────────────────────
// Ad Gate Sheet  (1 ad = 3 messages unlock)
// ─────────────────────────────────────────────────────────────────────────────
class _AdGateSheet extends StatefulWidget {
  final int adsWatchedToday, maxAdsDay, msgsPerUnlock;
  final Future<void> Function() onAdWatched;

  const _AdGateSheet({
    required this.adsWatchedToday,
    required this.maxAdsDay,
    required this.msgsPerUnlock,
    required this.onAdWatched,
  });

  @override
  State<_AdGateSheet> createState() => _AdGateSheetState();
}

class _AdGateSheetState extends State<_AdGateSheet> {
  bool    _watching = false;
  String? _error;
  bool    _success  = false;

  int  get _adsLeft => widget.maxAdsDay - widget.adsWatchedToday;
  bool get _canWatch => _adsLeft > 0;

  Future<void> _watchAd() async {
    if (_watching || !_canWatch) return;
    if (!adService.isRewardedReady) {
      setState(() => _error = 'Ad not ready yet. Please try again in a moment.');
      return;
    }
    setState(() { _watching = true; _error = null; });
    await adService.showRewardedAd(
      featureKey: 'ai_chat',
      onRewarded: () async {
        await widget.onAdWatched();
        if (!mounted) return;
        setState(() { _watching = false; _success = true; });
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.pop(context, true);
      },
      onDismissed: () {
        if (!mounted) return;
        setState(() {
          _watching = false;
          _error = 'Watch the full ad to unlock messages.';
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
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        if (!_success) ...[
          Text(
            _canWatch
              ? 'Watch 1 short ad to unlock ${widget.msgsPerUnlock} more messages. ($_adsLeft unlock${_adsLeft == 1 ? '' : 's'} left today)'
              : 'You\'ve reached your daily ad limit. Come back tomorrow or upgrade.',
            style: TextStyle(fontSize: 14, color: sub, height: 1.5),
            textAlign: TextAlign.center),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        if (!_success && _canWatch) ...[
          SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _watching ? null : _watchAd,
                icon: _watching
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_circle_fill_rounded, size: 20),
                label: Text(_watching ? 'Loading ad...' : 'Watch Ad — Unlock ${widget.msgsPerUnlock} Messages'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              )),
          const SizedBox(height: 12),
        ],
        SizedBox(width: double.infinity,
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
                      borderRadius: BorderRadius.circular(14))),
            )),
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
// Lockout Sheet  (daily ad limit reached)
// ─────────────────────────────────────────────────────────────────────────────
class _LockoutSheet extends StatefulWidget {
  final String lockoutUntil;
  final VoidCallback onUpgrade;
  const _LockoutSheet({required this.lockoutUntil, required this.onUpgrade});

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
    // Daily limit — countdown to midnight
    final now     = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final diff    = tomorrow.difference(now);
    if (diff.isNegative) {
      setState(() { _countdown = 'Ready!'; _expired = true; }); return;
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
        Text(_expired ? '✅' : '🔒', style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(_expired ? 'Daily Limit Reset! ✅' : 'Daily Limit Reached',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 8),
        Text(
          _expired
              ? 'Daily limit reset. Watch an ad to keep chatting!'
              : 'Used all AI messages today. Upgrade for unlimited, or come back tomorrow.',
          style: TextStyle(fontSize: 14, color: sub, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (!_expired) ...[
          const SizedBox(height: 24),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text('Resets in', style: TextStyle(fontSize: 12, color: sub)),
                const SizedBox(height: 6),
                Text(_countdown, style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w800, color: text,
                    fontFamily: 'monospace', letterSpacing: 2)),
              ])),
        ],
        const SizedBox(height: 24),
        SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onUpgrade,
              icon: const Icon(Icons.workspace_premium_rounded, size: 20),
              label: const Text('Upgrade — Unlimited AI Forever'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold, foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            )),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_expired ? 'Start chatting!' : 'Come back tomorrow',
              style: TextStyle(color: sub, fontSize: 13)),
        ),
      ]),
    );
  }
}
