// frontend/lib/screens/agent/agent_screen.dart
// APEX Agent Screen — v7.0 (Complete Production File)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/api_service.dart';
import '../../services/api_service_stream.dart';
import '../../services/ad_manager.dart';
import '../../services/currency_service.dart';

// ─────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────

enum _Role { user, agent, action, error, system }

class _Msg {
  final _Role   role;
  final String  text;
  final String? toolName;
  final String? toolCategory;
  final String? metadata;
  final String? modelTier;
  final String? contextualTip;
  const _Msg({
    required this.role,
    required this.text,
    this.toolName,
    this.toolCategory,
    this.metadata,
    this.modelTier,
    this.contextualTip,
  });
}

class _Step {
  final String tool, label, category;
  bool isDone;
  _Step({required this.tool, required this.label,
         required this.category, this.isDone = false});
}

class _TokenState {
  final int  remaining, used, dailyLimit, adWatchesLeft, percentUsed;
  final bool exhausted, canWatchAd, isPremium;
  const _TokenState({
    this.remaining = 500, this.used = 0, this.dailyLimit = 500,
    this.adWatchesLeft = 5, this.exhausted = false,
    this.canWatchAd = true, this.isPremium = false, this.percentUsed = 0,
  });
  factory _TokenState.fromJson(Map<String, dynamic> j) => _TokenState(
    remaining:     (j['tokens_remaining']   ?? 500) as int,
    used:          (j['tokens_used']        ?? 0)   as int,
    dailyLimit:    (j['tokens_daily_limit'] ?? 500) as int,
    adWatchesLeft: (j['ad_watches_left']    ?? 5)   as int,
    exhausted:     j['exhausted']  == true,
    canWatchAd:    j['can_watch_ad'] != false,
    isPremium:     j['is_premium'] == true,
    percentUsed:   (j['percent_used'] ?? 0) as int,
  );
}

enum _BrowserState { hidden, starting, running, waitingHuman, done, error }

class _HumanReq {
  final String inputType, message;
  final String? fieldLabel;
  final List<String> options;
  const _HumanReq({required this.inputType, required this.message,
    this.fieldLabel, this.options = const []});
}

// ─────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────

class AgentScreen extends ConsumerStatefulWidget {
  final String? workflowId;
  final String? sessionId;
  final String? handoffTask;
  final String? handoffSessionId;
  final Map<String, dynamic>?       handoffTemplate;
  final List<Map<String, dynamic>>? handoffQuestions;

  const AgentScreen({
    super.key,
    this.workflowId,
    this.sessionId,
    this.handoffTask,
    this.handoffSessionId,
    this.handoffTemplate,
    this.handoffQuestions,
  });

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen>
    with SingleTickerProviderStateMixin {

  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  final _answerCtrl = TextEditingController();

  late final AnimationController _starCtrl;
  late final Animation<double>   _starScale, _starGlow;

  List<_Msg>  _msgs              = [];
  List<_Step> _liveSteps         = [];
  String      _currentThought    = '';
  bool        _executionExpanded = true;
  bool        _isStreaming       = false;
  bool        _inputEnabled      = true;
  String?     _workflowId, _sessionId;
  bool        _showSidebar       = false;
  bool        _hasStartedChat    = false;
  bool        _historyLoading    = false;

  _TokenState  _tokenState       = const _TokenState();
  _BrowserState _browserState    = _BrowserState.hidden;
  String       _browserUrl       = '';
  String?      _browserScreenshot;
  _HumanReq?   _humanReq;
  double       _browserPanelH    = 0;

  Map<String, dynamic>?      _detectedTemplate;
  List<Map<String, dynamic>> _preflightQuestions = [];
  Map<String, String>        _preflightAnswers   = {};
  bool                       _showPreflight      = false;

  @override
  void initState() {
    super.initState();
    _starCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _starScale = Tween<double>(begin: 0.85, end: 1.20).animate(CurvedAnimation(parent: _starCtrl, curve: Curves.easeInOut));
    _starGlow  = Tween<double>(begin: 0.20, end: 0.70).animate(CurvedAnimation(parent: _starCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _starCtrl.dispose(); _inputCtrl.dispose();
    _scrollCtrl.dispose(); _inputFocus.dispose(); _answerCtrl.dispose();
    super.dispose();
  }

  void _startStar() { if (!_starCtrl.isAnimating) _starCtrl.repeat(reverse: true); }
  void _stopStar()  { _starCtrl.stop(); _starCtrl.animateTo(0, duration: 350.ms); }

  Future<void> _init() async {
    await _loadTokenState();
    if (widget.handoffTask != null) {
      _sessionId          = widget.handoffSessionId;
      _detectedTemplate   = widget.handoffTemplate;
      _preflightQuestions = widget.handoffQuestions?.cast<Map<String, dynamic>>() ?? [];
      _hasStartedChat     = true;
      if (_preflightQuestions.isNotEmpty) {
        setState(() => _showPreflight = true);
        setState(() => _msgs.add(_Msg(role: _Role.system,
          text: '**Task from your Mentor:** ${widget.handoffTask}\n\nI just need a few details before I start. 👇')));
      } else {
        _inputCtrl.text = widget.handoffTask!;
        await _submit();
      }
      return;
    }
    if (widget.sessionId != null) {
      _workflowId = widget.workflowId;
      _sessionId  = widget.sessionId;
      await _loadSession(widget.sessionId!);
    }
  }

  Future<void> _loadTokenState() async {
    try {
      final data = await api.get('/agent/tokens');
      if (mounted) setState(() => _tokenState = _TokenState.fromJson(Map<String, dynamic>.from(data)));
    } catch (_) {}
  }

  Future<void> _loadSession(String id) async {
    if (!mounted) return;
    setState(() => _historyLoading = true);
    try {
      final r = await api.get('/agent/chat/sessions/$id/messages?limit=100&offset=0');
      final messages = r['messages'] as List? ?? r['recent_messages'] as List? ?? [];
      if (mounted) {
        setState(() {
          _msgs = messages
              .where((m) => ['user','assistant'].contains(m['role']))
              .map((m) => _Msg(role: m['role'] == 'user' ? _Role.user : _Role.agent,
                text: m['content']?.toString() ?? '', modelTier: m['metadata']?['model_tier']))
              .toList();
          _sessionId = id; _hasStartedChat = _msgs.isNotEmpty; _historyLoading = false;
        });
        _scrollDown(jump: true);
      }
    } catch (_) { if (mounted) setState(() => _historyLoading = false); }
  }

  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isStreaming) return;
    _inputCtrl.clear();
    HapticFeedback.lightImpact();
    if (_showSidebar) setState(() => _showSidebar = false);
    if (_tokenState.exhausted && !_tokenState.isPremium) { _showTokenSheet(); return; }
    setState(() {
      _msgs.add(_Msg(role: _Role.user, text: text));
      _isStreaming = true; _inputEnabled = false; _hasStartedChat = true;
      _liveSteps = []; _currentThought = 'Understanding your request...';
      _executionExpanded = true; _showPreflight = false;
    });
    _startStar(); _scrollDown();
    final profile  = ref.read(profileProvider).valueOrNull ?? {};
    final currCode = profile['currency']?.toString() ?? 'USD';
    currency.init(currCode);
    final userCount = _msgs.where((m) => m.role == _Role.user).length;
    if (userCount == 1 && _sessionId == null) await _agentRun(text, currCode, profile);
    else                                       await _chatRound(text);
  }

  Future<void> _agentRun(String task, String currCode, Map profile) async {
    try {
      final stream = api.streamPost('/agent/run-stream', {
        'task': task, 'budget': 0.0, 'hours_per_day': 2.0,
        'currency': currCode, 'country': profile['country'],
        'language': profile['language'] ?? 'en',
        'allow_email': false, 'allow_social_post': false,
        'session_id': _sessionId,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      await for (final event in stream) { if (!mounted) break; _handleSSE(event); }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveSteps = []; _currentThought = '';
        _msgs.add(const _Msg(role: _Role.error, text: 'Connection issue. Please check your network and try again.'));
        _isStreaming = false; _inputEnabled = true;
      });
      _stopStar(); _scrollDown();
    }
  }

  void _handleSSE(StreamEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case 'token_state':
          _tokenState = _TokenState.fromJson(Map<String, dynamic>.from(event.data));
        case 'token_update':
          final rem = (event.data['remaining'] ?? _tokenState.remaining) as int;
          _tokenState = _TokenState(
            remaining: rem, used: (event.data['used'] ?? _tokenState.used) as int,
            dailyLimit: _tokenState.dailyLimit, adWatchesLeft: _tokenState.adWatchesLeft,
            exhausted: rem <= 0, canWatchAd: _tokenState.canWatchAd,
            isPremium: _tokenState.isPremium,
            percentUsed: (event.data['percent_used'] ?? _tokenState.percentUsed) as int);
        case 'token_exhausted':
          _isStreaming = false; _inputEnabled = true;
          _liveSteps = []; _currentThought = ''; _browserPanelH = 0; _stopStar();
          WidgetsBinding.instance.addPostFrameCallback((_) => _showTokenSheet());
        case 'template_detected':
          _detectedTemplate = Map<String, dynamic>.from(event.data);
        case 'quota_check': case 'brain_context': break;
        case 'thinking':
          _currentThought = event.data['thought']?.toString().isNotEmpty == true
              ? event.data['thought'].toString() : 'Thinking...';
        case 'tool_call':
          final tool = event.data['tool']?.toString() ?? '';
          final cat  = event.data['category']?.toString() ?? 'thinking';
          if (!_liveSteps.any((s) => s.tool == tool && !s.isDone))
            _liveSteps.add(_Step(tool: tool, label: _toolLabel(tool), category: cat));
          _currentThought = '${_toolLabel(tool)}...';
        case 'tool_result':
          final tool = event.data['tool']?.toString() ?? '';
          for (final s in _liveSteps.reversed) { if (s.tool == tool && !s.isDone) { s.isDone = true; break; } }
        case 'action_done':
          final tool = event.data['tool']?.toString() ?? '';
          final res  = event.data['result'] as Map? ?? {};
          final ok   = res['posted'] == true || res['sent'] == true;
          for (final s in _liveSteps.reversed) { if (s.tool == tool) { s.isDone = true; break; } }
          _msgs.add(_Msg(role: _Role.action,
            text: ok ? '✅ ${_toolLabel(tool)} — completed' : '📋 ${_toolLabel(tool)} — ready',
            toolName: tool, toolCategory: 'action', metadata: jsonEncode(res)));
        case 'browser_starting':
          _browserState = _BrowserState.starting; _browserPanelH = 260;
          _currentThought = '🌐 Starting browser...';
        case 'browser_ready':
          _browserState = _BrowserState.running;
        case 'browser_action':
          _browserState = _BrowserState.running;
          _browserUrl = event.data['url']?.toString() ?? _browserUrl;
          _browserPanelH = 320;
          final sc = event.data['screenshot_b64']?.toString();
          if (sc != null && sc.isNotEmpty) _browserScreenshot = sc;
          final reason = event.data['reason']?.toString() ?? '';
          final action = event.data['action']?.toString() ?? '';
          _currentThought = reason.isNotEmpty ? reason : 'Browser: $action';
          _liveSteps.add(_Step(tool: 'browser_$action',
            label: reason.isNotEmpty ? reason : _toolLabel('browser_$action'),
            category: 'browser', isDone: true));
        case 'human_required':
          _browserState = _BrowserState.waitingHuman;
          _humanReq = _HumanReq(
            inputType: event.data['input_type']?.toString() ?? 'question',
            message:   event.data['message']?.toString() ?? 'Input required',
            fieldLabel: event.data['field_label']?.toString(),
            options: (event.data['options'] as List? ?? []).cast<String>());
          final sc2 = event.data['screenshot_b64']?.toString();
          if (sc2 != null && sc2.isNotEmpty) _browserScreenshot = sc2;
        case 'human_answered':
          _browserState = _BrowserState.running; _humanReq = null;
        case 'browser_done':
          final sc3 = event.data['screenshot_b64']?.toString();
          if (sc3 != null && sc3.isNotEmpty) _browserScreenshot = sc3;
          _currentThought = event.data['message']?.toString() ?? '✅ Step complete';
        case 'browser_session_complete':
          _browserState = _BrowserState.done;
          _currentThought = '✅ Browser task complete';
          final sc4 = event.data['screenshot_b64']?.toString();
          if (sc4 != null && sc4.isNotEmpty) _browserScreenshot = sc4;
        case 'browser_error':
          _browserState = _BrowserState.error; _browserPanelH = 0; _currentThought = '';
          _msgs.add(_Msg(role: _Role.error, text: '🌐 Browser: ${event.data['message'] ?? 'Error'}'));
        case 'finalizing':
          _currentThought = 'Writing your complete plan...';
          for (final s in _liveSteps) { s.isDone = true; }
          _browserPanelH = 0;
        case 'complete':
          _workflowId = event.data['workflow_id']?.toString() ?? _workflowId;
          _sessionId  = event.data['session_id']?.toString()  ?? _sessionId;
          if (event.data['token_state'] != null)
            _tokenState = _TokenState.fromJson(Map<String, dynamic>.from(event.data['token_state'] as Map));
          final data = Map<String, dynamic>.from(event.data);
          _msgs.add(_Msg(role: _Role.agent, text: _buildResponse(data),
            metadata: jsonEncode(data), modelTier: data['model_tier']?.toString() ?? 'free',
            contextualTip: _buildContextualTip(data)));
          _liveSteps = []; _currentThought = ''; _browserPanelH = 0;
          _isStreaming = false; _inputEnabled = true;
        case 'error':
          _liveSteps = []; _currentThought = ''; _browserPanelH = 0;
          final errMsg = event.data['message']?.toString() ?? '';
          final isLimit = errMsg.contains('limit') || errMsg.contains('quota') || errMsg.contains('token');
          _msgs.add(_Msg(role: isLimit ? _Role.system : _Role.error,
            text: isLimit
              ? '**Limit reached** 🔒\n\nWatch an ad for more tokens, or upgrade to Premium.'
              : (errMsg.isNotEmpty ? errMsg : 'Something went wrong. Please try again.')));
          _isStreaming = false; _inputEnabled = true;
      }
    });
    if (!_isStreaming) _stopStar();
    _scrollDown();
  }

  Future<void> _chatRound(String message) async {
    setState(() { _liveSteps = []; _currentThought = 'Thinking...'; });
    _scrollDown();
    try {
      final r = await api.post('/agent/chat', {
        'message': message, 'session_id': _sessionId, 'workflow_id': _workflowId, 'stream': false});
      _sessionId = r['session_id']?.toString() ?? _sessionId;
      if (mounted) setState(() {
        _currentThought = ''; _liveSteps = [];
        _msgs.add(_Msg(role: _Role.agent, text: r['content']?.toString() ?? '...',
            modelTier: r['model_tier']?.toString()));
        _isStreaming = false; _inputEnabled = true;
      });
    } catch (_) {
      if (mounted) setState(() {
        _currentThought = ''; _liveSteps = [];
        _msgs.add(const _Msg(role: _Role.error, text: 'Connection issue. Please try again.'));
        _isStreaming = false; _inputEnabled = true;
      });
    }
    _stopStar(); _scrollDown();
  }

  Future<void> _submitHumanAnswer(String answer) async {
    if (_sessionId == null) return;
    try {
      await api.post('/agent/browser/answer', {'session_id': _sessionId, 'answer': answer});
      setState(() { _humanReq = null; _browserState = _BrowserState.running; });
    } catch (_) {}
    _answerCtrl.clear();
  }

  Future<void> _submitPreflight() async {
    final missing = _preflightQuestions.where(
        (q) => q['optional'] != true && (_preflightAnswers[q['key']] ?? '').isEmpty);
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please answer all required questions')));
      return;
    }
    setState(() => _showPreflight = false);
    if (_sessionId != null && _detectedTemplate != null) {
      try {
        final r = await api.post('/agent/browser/run', {
          'session_id': _sessionId, 'task': widget.handoffTask ?? '',
          'template_key': _detectedTemplate!['template_key'], 'user_answers': _preflightAnswers});
        if (r['started'] == true) {
          setState(() { _browserState = _BrowserState.starting; _browserPanelH = 260;
            _isStreaming = true; _currentThought = '🌐 Starting browser...'; });
          _startStar();
          final streamUrl = r['stream_url']?.toString() ?? '';
          if (streamUrl.isNotEmpty) {
            try {
              // FIX: use streamPost instead of streamGet (streamGet not defined on ApiService)
              final stream = api.streamPost(streamUrl, {});
              await for (final event in stream) { if (!mounted) break; _handleSSE(event); }
            } catch (_) {}
          }
        }
      } catch (e) {
        setState(() => _msgs.add(_Msg(role: _Role.error, text: 'Failed to start browser: $e')));
      }
    }
  }

  void _showTokenSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gc     = _gc(isDark);
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TokenSheet(
        isDark: isDark, gc: gc, canWatchAd: _tokenState.canWatchAd,
        adWatchesLeft: _tokenState.adWatchesLeft,
        onWatchAd: () async {
          Navigator.pop(context);
          // FIX: use watchAdForAgentUse — watchRewardedAd is not defined on AdManager
          final ok = await adManager.watchAdForAgentUse(context);
          if (ok && mounted) {
            try {
              final r = await api.post('/agent/tokens/ad-grant', {});
              if (r['granted'] == true && mounted) {
                setState(() {
                  _tokenState = _TokenState(
                    remaining: _tokenState.remaining + ((r['tokens_granted'] ?? 100) as int),
                    used: _tokenState.used, dailyLimit: _tokenState.dailyLimit,
                    adWatchesLeft: (r['ads_remaining'] ?? 0) as int,
                    exhausted: false, canWatchAd: ((r['ads_remaining'] ?? 0) as int) > 0,
                    isPremium: _tokenState.isPremium);
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(r['message']?.toString() ?? '🎉 Tokens added!'),
                  backgroundColor: Colors.green));
                final lastUser = _msgs.lastWhere((m) => m.role == _Role.user,
                    orElse: () => const _Msg(role: _Role.system, text: ''));
                if (lastUser.text.isNotEmpty && lastUser.role == _Role.user) {
                  _inputCtrl.text = lastUser.text;
                  _msgs.removeLast();
                  await _submit();
                }
              }
            } catch (_) {}
          }
        },
        onSubscribe: () { Navigator.pop(context); context.push('/premium'); },
        onComeTomorrow: () => Navigator.pop(context),
      ));
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LimitSheet(isDark: isDark, onWatchAd: () {
        Navigator.pop(context);
        adManager.watchAdForAgentUse(context).then((ok) { if (ok && mounted) _submit(); });
      }));
  }

  void _newChat() {
    setState(() {
      _msgs = []; _liveSteps = []; _currentThought = '';
      _workflowId = null; _sessionId = null;
      _isStreaming = false; _inputEnabled = true;
      _hasStartedChat = false; _executionExpanded = true; _showSidebar = false;
      _browserState = _BrowserState.hidden; _browserPanelH = 0;
      _humanReq = null; _browserScreenshot = null; _detectedTemplate = null;
      _preflightQuestions = []; _preflightAnswers = {}; _showPreflight = false;
    });
    _stopStar(); _inputFocus.requestFocus();
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (jump) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      else _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  List<Color> _gc(bool isDark) => isDark
      ? [const Color(0xFF4A90D9), const Color(0xFF7B68EE)]
      : [const Color(0xFF5B7FFF), const Color(0xFF8B5CF6)];

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gc     = _gc(isDark);
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(children: [
        Column(children: [
          _appBar(isDark, gc),
          _tokenBar(isDark, gc),
          if (_detectedTemplate != null && !_hasStartedChat) _templateBanner(isDark, gc),
          Expanded(child: _historyLoading
            ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: gc[0]))
            : (_hasStartedChat || _msgs.isNotEmpty) ? _msgList(isDark, gc) : _emptyState(isDark, gc)),
          if (_browserState != _BrowserState.hidden) _browserPanel(isDark, gc),
          _inputBar(isDark, gc),
        ]),
        if (_showSidebar) ...[
          GestureDetector(onTap: () => setState(() => _showSidebar = false),
            child: Container(color: Colors.black.withOpacity(0.45))),
          Positioned(left: 0, top: 0, bottom: 0, child: _sidebar(isDark, gc)),
        ],
        if (_humanReq != null)
          _HumanOverlay(req: _humanReq!, isDark: isDark, gc: gc,
            ctrl: _answerCtrl, screenshot: _browserScreenshot, onSubmit: _submitHumanAnswer),
        if (_showPreflight && _preflightQuestions.isNotEmpty)
          _PreflightSheet(questions: _preflightQuestions, answers: _preflightAnswers,
            template: _detectedTemplate, isDark: isDark, gc: gc,
            onSubmit: _submitPreflight, onCancel: () => setState(() => _showPreflight = false)),
      ]),
    );
  }

  Widget _tokenBar(bool isDark, List<Color> gc) {
    if (_tokenState.isPremium) return const SizedBox.shrink();
    final rem      = _tokenState.remaining;
    final barColor = rem > 150 ? Colors.green : rem > 50 ? Colors.orange : Colors.red;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bolt_rounded, size: 13, color: barColor),
          const SizedBox(width: 4),
          Text('$rem tokens remaining', style: TextStyle(fontSize: 12, color: barColor, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_tokenState.exhausted)
            GestureDetector(onTap: _showTokenSheet, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: gc[0].withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: gc[0].withOpacity(0.30))),
              child: Text('Get more', style: TextStyle(fontSize: 11, color: gc[0], fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
          value: _tokenState.percentUsed / 100.0,
          backgroundColor: barColor.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(barColor), minHeight: 3)),
      ]));
  }

  Widget _templateBanner(bool isDark, List<Color> gc) {
    final t = _detectedTemplate!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [gc[0].withOpacity(0.10), gc[1].withOpacity(0.10)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gc[0].withOpacity(0.25))),
      child: Row(children: [
        Text(t['icon']?.toString() ?? '🤖', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t['title']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87)),
          Text('${t['platform']} · ~${t['estimated_tokens']} tokens',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45)),
        ])),
        if (t['needs_browser'] == true)
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.language_rounded, size: 11, color: Colors.blue), SizedBox(width: 3),
              Text('Browser', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600))])),
      ])).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0, duration: 300.ms);
  }

  Widget _browserPanel(bool isDark, List<Color> gc) {
    final sub = isDark ? Colors.white54 : Colors.black45;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350), curve: Curves.easeInOut,
      height: _browserPanelH, margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? Colors.white12 : Colors.black12)),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        Container(height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
          child: Row(children: [
            Icon(Icons.language_rounded, size: 14, color: gc[0]), const SizedBox(width: 6),
            Expanded(child: Text(_browserUrl.isEmpty ? 'Browser' : _browserUrl,
                style: TextStyle(fontSize: 12, color: sub), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (_browserState == _BrowserState.running)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: gc[0])),
            if (_browserState == _BrowserState.done)
              Icon(Icons.check_circle_outline_rounded, size: 14, color: gc[0]),
            if (_browserState == _BrowserState.waitingHuman)
              const Icon(Icons.person_outline_rounded, size: 14, color: Colors.orange),
          ])),
        Expanded(child: _browserScreenshot != null
          ? Image.memory(base64Decode(_browserScreenshot!), fit: BoxFit.cover, width: double.infinity)
          : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.language_rounded, size: 28, color: gc[0].withOpacity(0.4)), const SizedBox(height: 8),
              Text(_browserState == _BrowserState.starting ? '🌐 Starting browser...'
                  : _browserState == _BrowserState.waitingHuman ? '⏸ Waiting for your input...'
                      : 'Browser running...', style: TextStyle(fontSize: 13, color: sub))]))),
      ]));
  }

  PreferredSizeWidget _appBar(bool isDark, List<Color> gc) {
    final runsLeft  = adManager.agentUsesRemaining;
    final isPremium = adManager.isPremium;
    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: true,
      leading: IconButton(
        icon: Icon(_showSidebar ? Icons.close_rounded : Iconsax.menu_1,
            color: isDark ? Colors.white : Colors.black87, size: 24),
        onPressed: () => setState(() => _showSidebar = !_showSidebar)),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(animation: _starCtrl, builder: (_, __) => Transform.scale(
          scale: _isStreaming ? _starScale.value : 1.0,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gc, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: gc[0].withOpacity(_isStreaming ? _starGlow.value : 0.28), blurRadius: 14)]),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 18)))),
        const SizedBox(width: 10),
        Text('APEX', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2,
            color: isDark ? Colors.white : Colors.black)),
      ]),
      actions: [
        if (!isPremium)
          GestureDetector(onTap: runsLeft == 0 ? _showLimitDialog : null, child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: runsLeft > 1 ? Colors.green.withOpacity(0.12)
                  : runsLeft == 1 ? Colors.orange.withOpacity(0.12) : Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: runsLeft > 1 ? Colors.green.withOpacity(0.25)
                  : runsLeft == 1 ? Colors.orange.withOpacity(0.25) : Colors.red.withOpacity(0.25))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(runsLeft > 0 ? Icons.bolt_rounded : Icons.lock_outline_rounded, size: 12,
                  color: runsLeft > 1 ? Colors.green : runsLeft == 1 ? Colors.orange : Colors.red),
              const SizedBox(width: 3),
              Text(runsLeft > 0 ? '$runsLeft left' : 'Limit',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: runsLeft > 1 ? Colors.green : runsLeft == 1 ? Colors.orange : Colors.red)),
            ]))),
        IconButton(icon: Icon(Icons.add_rounded, color: isDark ? Colors.white : Colors.black87, size: 24),
            tooltip: 'New conversation', onPressed: _newChat),
        if (_workflowId != null)
          IconButton(icon: Icon(Iconsax.flash, color: gc[0], size: 20),
              onPressed: () => context.push('/workflow/$_workflowId')),
      ]);
  }

  Widget _sidebar(bool isDark, List<Color> gc) {
    return SafeArea(right: false, child: Container(width: 272,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF7F7F8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(4, 0))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 8), child: GestureDetector(onTap: _newChat,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.09) : Colors.black.withOpacity(0.08))),
            child: Row(children: [
              Icon(Icons.add, size: 18, color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54),
              const SizedBox(width: 10),
              Text('New chat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87)),
            ])))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), child: Text('Recent',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6,
                color: isDark ? Colors.white.withOpacity(0.32) : Colors.black.withOpacity(0.32)))),
        Expanded(child: FutureBuilder(
          future: api.get('/agent/chat/sessions'),
          builder: (context, snap) {
            if (!snap.hasData) return Center(child: CircularProgressIndicator(strokeWidth: 2, color: gc[0]));
            final sessions = snap.data?['sessions'] as List? ?? [];
            if (sessions.isEmpty) return Center(child: Text('No conversations yet', style: TextStyle(
                fontSize: 13, color: isDark ? Colors.white.withOpacity(0.28) : Colors.black.withOpacity(0.28))));
            return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final sess = sessions[i] as Map;
                final isActive = sess['id'] == _sessionId;
                return ListTile(dense: true, selected: isActive,
                  selectedTileColor: gc[0].withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  leading: Icon(Iconsax.message_text, size: 18,
                      color: isActive ? gc[0] : (isDark ? Colors.white.withOpacity(0.4) : Colors.black38)),
                  title: Text(sess['title'] ?? 'Untitled', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text(_fmtDate(sess['updated_at']?.toString()),
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white.withOpacity(0.32) : Colors.black38)),
                  onTap: () {
                    setState(() { _showSidebar = false; _hasStartedChat = true; });
                    _loadSession(sess['id']?.toString() ?? '');
                  });
              });
          })),
      ])));
  }

  Widget _emptyState(bool isDark, List<Color> gc) {
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final name    = (profile['full_name']?.toString() ?? '').split(' ').first;
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(animation: _starCtrl, builder: (_, __) => Container(width: 76, height: 76,
          decoration: BoxDecoration(gradient: LinearGradient(colors: gc, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: gc[0].withOpacity(_isStreaming ? _starGlow.value : 0.35), blurRadius: 32, spreadRadius: 3)]),
          child: const Icon(Icons.star_rounded, color: Colors.white, size: 42))),
        const SizedBox(height: 28),
        Text('APEX', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 5,
            color: isDark ? Colors.white : Colors.black, height: 1)),
        const SizedBox(height: 6),
        Text('Your autonomous wealth agent', style: TextStyle(fontSize: 13,
            color: isDark ? Colors.white.withOpacity(0.38) : Colors.black.withOpacity(0.38), letterSpacing: 0.2)),
        const SizedBox(height: 52),
        Text(name.isNotEmpty ? 'Hey $name 👋' : 'Hey there 👋',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 10),
        Text('How can I help you today?', style: TextStyle(fontSize: 17,
            color: isDark ? Colors.white.withOpacity(0.48) : Colors.black.withOpacity(0.48))),
      ]))).animate().fadeIn(duration: 500.ms).slideY(begin: 0.04, end: 0, duration: 500.ms, curve: Curves.easeOut);
  }

  Widget _msgList(bool isDark, List<Color> gc) {
    final showLive = _isStreaming || _currentThought.isNotEmpty;
    return ListView.builder(controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      itemCount: _msgs.length + (showLive ? 1 : 0),
      itemBuilder: (_, i) {
        if (showLive && i == _msgs.length) {
          return _LiveCard(steps: _liveSteps, thought: _currentThought, isDark: isDark, gc: gc,
            isExpanded: _executionExpanded, onToggle: () => setState(() => _executionExpanded = !_executionExpanded));
        }
        final msg = _msgs[i];
        return switch (msg.role) {
          _Role.user   => _UserBubble(msg: msg, gc: gc),
          _Role.agent  => _AgentBubble(msg: msg, isDark: isDark, gc: gc,
              onWorkflow: _workflowId != null ? () => context.push('/workflow/$_workflowId') : null,
              onTip: msg.contextualTip != null ? () {
                _inputCtrl.text = msg.contextualTip!
                    .replaceAll(RegExp(r'^[💡⚡]\s*'), '').replaceAll(RegExp(r' — want.*$'), '');
                _inputFocus.requestFocus();
              } : null),
          _Role.action => _ActionLine(msg: msg),
          _Role.error  => _ErrorLine(msg: msg),
          _Role.system => _SysMsg(msg: msg, isDark: isDark, gc: gc,
              onUpgrade: () => context.push('/premium'), onWatchAd: _showTokenSheet),
        };
      });
  }

  // FIX: Added missing closing ')' for Expanded widget — original had only 4 closing
  // parens after fromLTRB, but 5 are needed: InputDecoration, TextField, ClipRRect,
  // Container, Expanded.
  Widget _inputBar(bool isDark, List<Color> gc) {
    final hintColor   = isDark ? Colors.white.withOpacity(0.30) : Colors.black.withOpacity(0.30);
    final inputBg     = isDark ? const Color(0xFF191919) : const Color(0xFFF3F3F5);
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.07);
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(color: isDark ? Colors.black : Colors.white,
        border: Border(top: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05), width: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(color: inputBg, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor)),
          child: ClipRRect(borderRadius: BorderRadius.circular(24), child: TextField(
            controller: _inputCtrl, focusNode: _inputFocus, enabled: _inputEnabled,
            maxLines: null, minLines: 1, textInputAction: TextInputAction.newline,
            style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black87, height: 1.4),
            decoration: InputDecoration(
              hintText: _isStreaming ? 'APEX is working...' : 'Ask APEX anything...',
              hintStyle: TextStyle(fontSize: 16, color: hintColor),
              border: InputBorder.none, enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none, disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14)))))),
        const SizedBox(width: 10),
        AnimatedBuilder(animation: _starCtrl, builder: (_, __) {
          final active = !_isStreaming;
          return GestureDetector(onTap: active ? _submit : null, child: Transform.scale(
            scale: _isStreaming ? _starScale.value : 1.0,
            child: Container(width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: active ? LinearGradient(colors: gc, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color: active ? null : (isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.07)),
                borderRadius: BorderRadius.circular(23),
                boxShadow: (active || _isStreaming) ? [BoxShadow(
                    color: gc[0].withOpacity(active ? 0.30 : (_isStreaming ? _starGlow.value : 0)),
                    blurRadius: 12, offset: const Offset(0, 3))] : null),
              child: Icon(_isStreaming ? Icons.star_rounded : Icons.arrow_upward_rounded,
                color: active || _isStreaming ? Colors.white
                    : (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.18)),
                size: 20))));
        }),
      ])));
  }

  // Helpers
  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s); if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays}d ago';
    return '${d.day}/${d.month}';
  }

  String? _buildContextualTip(Map<String, dynamic> data) {
    final opps  = data['opportunities_found'] as List? ?? [];
    final plan  = data['plan']               as Map?  ?? {};
    final range = plan['income_range']        as Map?  ?? {};
    final now   = data['immediate_action']?.toString() ?? '';
    if (opps.isNotEmpty) {
      final opp = opps.first as Map;
      final platform = opp['platform']?.toString() ?? '';
      final title    = opp['title']?.toString()    ?? '';
      if (platform.isNotEmpty && title.isNotEmpty)
        return '💡 You could earn from "$title" on $platform — want me to help you apply?';
    }
    if ((range['max'] ?? 0) > 0) {
      final sym = _currSym(range['currency']?.toString() ?? currency.code);
      return '💡 This plan could earn up to $sym${_fmt(range['max'])}/mo in ${plan['timeline'] ?? 'soon'} — want a full breakdown?';
    }
    if (now.isNotEmpty) return '⚡ $now — want help getting started right now?';
    return null;
  }

  String _buildResponse(Map<String, dynamic> data) {
    final buf     = StringBuffer();
    final resp    = data['agent_response']?.toString()      ?? '';
    final plan    = data['plan']                as Map?  ?? {};
    final steps   = data['steps']               as List? ?? [];
    final tools   = data['free_tools']          as List? ?? [];
    final opps    = data['opportunities_found'] as List? ?? [];
    final docs    = data['documents_generated'] as List? ?? [];
    final msgs    = data['outreach_messages']   as List? ?? [];
    final posts   = data['social_posts']        as List? ?? [];
    final now     = data['immediate_action']?.toString()    ?? '';
    final insight = data['wealth_insight']?.toString()      ?? '';
    if (resp.isNotEmpty) { buf.writeln(resp); buf.writeln(); }
    if (plan['title'] != null) {
      buf.writeln('**${plan['title']}**');
      final r   = plan['income_range'] as Map? ?? {};
      final sym = _currSym(r['currency']?.toString() ?? currency.code);
      if ((r['max'] ?? 0) > 0)
        buf.writeln('$sym${_fmt(r['min'] ?? 0)} – $sym${_fmt(r['max'] ?? 0)}/mo  ·  ${plan['timeline'] ?? ''}  ·  ${plan['viability'] ?? 75}% viable');
      buf.writeln();
    }
    if (steps.isNotEmpty) {
      buf.writeln('**Your ${steps.length}-step plan:**');
      for (final s in steps.take(7)) {
        final step = s as Map;
        final auto = step['type'] == 'automated' ? ' _(AI handles this)_' : '';
        buf.writeln('**${step['order'] ?? ''}. ${step['title']}**$auto');
        buf.writeln(step['description'] ?? '');
        final out = step['ai_output']?.toString() ?? '';
        if (out.length > 20) buf.writeln('> ${out.substring(0, out.length.clamp(0, 150))}...');
        buf.writeln();
      }
    }
    if (opps.isNotEmpty) {
      buf.writeln('**${opps.length} real opportunities found:**');
      for (final o in opps.take(4)) {
        final opp = o as Map;
        final fit = opp['fit_score'] != null ? ' (${opp['fit_score']}% fit)' : '';
        buf.writeln('• **${opp['title']}** — ${opp['platform'] ?? ''}$fit');
        if (opp['url']?.toString().isNotEmpty == true) buf.writeln('  ${opp['url']}');
      }
      buf.writeln();
    }
    if (docs.isNotEmpty) {
      buf.writeln('**Documents generated:** ${docs.map((d) => (d as Map)['type']).join(', ')}');
      buf.writeln('_View in Workflow tab_'); buf.writeln();
    }
    if (msgs.isNotEmpty)  { buf.writeln('**${msgs.length} outreach message(s)** ready to send.'); buf.writeln(); }
    if (posts.isNotEmpty) { buf.writeln('**${posts.length} social post(s)** drafted.'); buf.writeln(); }
    if (tools.isNotEmpty) {
      buf.writeln('**Free tools:** ${tools.take(5).map((t) => (t as Map)['name']).join(' · ')}'); buf.writeln();
    }
    if (now.isNotEmpty)    { buf.writeln('⚡ **Do this now:** $now'); buf.writeln(); }
    if (insight.isNotEmpty)  buf.writeln('_${insight}_');
    if (plan['warning']?.toString().isNotEmpty == true) buf.writeln('\n⚠️ ${plan['warning']}');
    return buf.toString().trim();
  }

  String _currSym(String code) {
    try { return NumberFormat.simpleCurrency(name: code).format(0).replaceAll(RegExp(r'[\d,. ]'), '').trim(); }
    catch (_) { return code; }
  }

  String _fmt(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  String _toolLabel(String tool) {
    const map = {
      'web_search': 'Searching the web', 'deep_research': 'Deep researching',
      'find_freelance_jobs': 'Finding freelance jobs', 'find_partners': 'Finding business partners',
      'find_free_resources': 'Finding free tools', 'market_research': 'Analysing the market',
      'scan_opportunities': 'Scanning for opportunities', 'write_content': 'Writing content',
      'create_plan': 'Building execution plan', 'estimate_income': 'Estimating income',
      'generate_ideas': 'Generating ideas', 'write_cold_outreach': 'Writing outreach message',
      'build_profile_content': 'Building your profile', 'breakdown_task': 'Breaking down task',
      'create_template': 'Creating template', 'send_email': 'Sending email',
      'post_twitter': 'Posting to Twitter/X', 'post_linkedin': 'Posting to LinkedIn',
      'generate_contract': 'Generating contract', 'generate_invoice': 'Generating invoice',
      'generate_proposal': 'Generating proposal', 'generate_pitch_deck': 'Generating pitch deck',
      'scrape_live_opportunities': 'Finding live opportunities', 'score_opportunity': 'Scoring opportunity',
      'analyze_market_trends': 'Analysing market trends', 'create_daily_action_plan': 'Creating action plan',
      'create_follow_up_plan': 'Creating follow-up plan', 'track_earnings_insight': 'Analysing earnings',
      'growth_milestone_check': 'Checking milestones', 'browser_navigate': 'Opening page',
      'browser_click': 'Clicking element', 'browser_fill': 'Filling form',
      'browser_scroll': 'Scrolling', 'browser_extract': 'Reading page data',
    };
    return map[tool] ?? tool.replaceAll('_', ' ');
  }
}


// ─────────────────────────────────────────────────────────────────
// LIVE EXECUTION CARD
// ─────────────────────────────────────────────────────────────────

class _LiveCard extends StatefulWidget {
  final List<_Step> steps; final String thought;
  final bool isDark; final List<Color> gc;
  final bool isExpanded; final VoidCallback onToggle;
  const _LiveCard({required this.steps, required this.thought, required this.isDark,
      required this.gc, required this.isExpanded, required this.onToggle});
  @override
  State<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<_LiveCard> with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  @override
  void initState() { super.initState(); _dotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(); }
  @override
  void dispose() { _dotCtrl.dispose(); super.dispose(); }

  String get _catIcon {
    final cur = widget.steps.lastWhere((s) => !s.isDone,
        orElse: () => widget.steps.isEmpty ? _Step(tool:'',label:'',category:'thinking') : widget.steps.last);
    return switch (cur.category) { 'research'=>'🔍','action'=>'⚡','document'=>'📄','browser'=>'🌐',_=>'💭' };
  }

  @override
  Widget build(BuildContext context) {
    final sub       = widget.isDark ? Colors.white.withOpacity(0.46) : Colors.black.withOpacity(0.46);
    final bgColor   = widget.isDark ? const Color(0xFF111111) : const Color(0xFFF4F4F6);
    final border    = widget.isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final done  = widget.steps.where((s) => s.isDone).length;
    final total = widget.steps.length;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 6, 80, 6), child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(gradient: LinearGradient(colors: widget.gc), borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 10),
          Text('APEX', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1, color: textColor)),
        ])),
        GestureDetector(onTap: total > 0 ? widget.onToggle : null, child: AnimatedContainer(
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _Dots(ctrl: _dotCtrl, color: widget.gc[0]), const SizedBox(width: 10),
              if (total == 0)
                Expanded(child: Text(widget.thought.isEmpty ? 'Working...' : widget.thought,
                    style: TextStyle(fontSize: 14, color: sub, fontStyle: FontStyle.italic),
                    maxLines: 2, overflow: TextOverflow.ellipsis))
              else ...[
                Text(total == done ? '✓  All $total steps complete' : '$done of $total steps done',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: total == done ? widget.gc[0] : textColor)),
                const Spacer(),
                Icon(widget.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 18, color: sub),
              ],
            ]),
            if (widget.thought.isNotEmpty && total > 0) ...[
              const SizedBox(height: 6),
              Text('$_catIcon ${widget.thought}',
                  style: TextStyle(fontSize: 13, color: sub, fontStyle: FontStyle.italic),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (widget.isExpanded && total > 0) ...[
              const SizedBox(height: 12), Divider(height: 1, color: border), const SizedBox(height: 10),
              ...widget.steps.map((step) {
                final ci = switch (step.category) { 'research'=>'🔍','action'=>'⚡','document'=>'📄','browser'=>'🌐',_=>'●' };
                return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                  SizedBox(width: 20, child: step.isDone
                      ? Icon(Icons.check_circle_outline_rounded, size: 16, color: widget.gc[0])
                      : SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: widget.gc[0]))),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$ci ${step.label}', style: TextStyle(fontSize: 13,
                      color: step.isDone ? sub : textColor, fontWeight: step.isDone ? FontWeight.normal : FontWeight.w500))),
                ]));
              }),
            ],
          ]))),
      ])).animate().fadeIn(duration: 200.ms);
  }
}


// ─────────────────────────────────────────────────────────────────
// BUBBLES
// ─────────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  final _Msg msg; final List<Color> gc;
  const _UserBubble({required this.msg, required this.gc});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerRight,
    child: Container(margin: const EdgeInsets.fromLTRB(72, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(gradient: LinearGradient(colors: gc, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6))),
      child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.45)))
  ).animate().fadeIn(duration: 160.ms).slideY(begin: 0.06, end: 0, duration: 160.ms, curve: Curves.easeOut);
}

class _AgentBubble extends StatelessWidget {
  final _Msg msg; final bool isDark; final List<Color> gc;
  final VoidCallback? onWorkflow, onTip;
  const _AgentBubble({required this.msg, required this.isDark, required this.gc, this.onWorkflow, this.onTip});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor  = isDark ? Colors.white.withOpacity(0.42) : Colors.black.withOpacity(0.42);
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 64, 8), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(gradient: LinearGradient(colors: gc), borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 10),
          Text('APEX', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1, color: textColor)),
          if (msg.modelTier != null) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: msg.modelTier == 'premium' ? Colors.amber.withOpacity(0.12) : Colors.grey.withOpacity(0.11),
                borderRadius: BorderRadius.circular(5)),
              child: Text(msg.modelTier!.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: msg.modelTier == 'premium' ? Colors.amber : subColor))),
          ],
        ])),
        _MdText(text: msg.text, isDark: isDark, accent: gc[1]),
        if (msg.contextualTip != null) ...[
          const SizedBox(height: 14),
          GestureDetector(onTap: onTip, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [gc[0].withOpacity(0.10), gc[1].withOpacity(0.10)]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: gc[0].withOpacity(0.25))),
            child: Row(children: [
              Expanded(child: Text(msg.contextualTip!, style: TextStyle(fontSize: 13,
                  color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87, height: 1.45))),
              if (onTip != null) ...[const SizedBox(width: 8), Icon(Icons.arrow_forward_ios_rounded, size: 13, color: gc[0])],
            ]))),
        ],
        const SizedBox(height: 10),
        Row(children: [
          _IBtn(icon: Icons.copy_outlined, color: subColor, onTap: () {
            Clipboard.setData(ClipboardData(text: msg.text));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
          }),
          if (onWorkflow != null) ...[
            const SizedBox(width: 16),
            GestureDetector(onTap: onWorkflow, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Iconsax.flash, size: 15, color: gc[0]), const SizedBox(width: 5),
              Text('View Workflow', style: TextStyle(fontSize: 13, color: gc[0], fontWeight: FontWeight.w600)),
            ])),
          ],
        ]),
      ])).animate().fadeIn(duration: 260.ms).slideY(begin: 0.04, end: 0, duration: 260.ms, curve: Curves.easeOut);
  }
}

class _ActionLine extends StatelessWidget {
  final _Msg msg; const _ActionLine({required this.msg});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(56, 2, 80, 2),
    child: Text(msg.text, style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.w500))).animate().fadeIn();
}

class _ErrorLine extends StatelessWidget {
  final _Msg msg; const _ErrorLine({required this.msg});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 6, 64, 6),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.07), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.18))),
      child: Text(msg.text, style: const TextStyle(fontSize: 15, color: Colors.red, height: 1.45)))).animate().fadeIn();
}

class _SysMsg extends StatelessWidget {
  final _Msg msg; final bool isDark; final List<Color> gc;
  final VoidCallback onUpgrade, onWatchAd;
  const _SysMsg({required this.msg, required this.isDark, required this.gc, required this.onUpgrade, required this.onWatchAd});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF141414) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _MdText(text: msg.text, isDark: isDark, accent: gc[1]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onWatchAd,
            style: OutlinedButton.styleFrom(side: BorderSide(color: gc[0]),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: Text('Watch Ad', style: TextStyle(color: gc[0], fontWeight: FontWeight.w600, fontSize: 14)))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(onPressed: onUpgrade,
            style: ElevatedButton.styleFrom(backgroundColor: gc[0],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Upgrade', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)))),
        ]),
      ]))).animate().fadeIn();
}


// ─────────────────────────────────────────────────────────────────
// MARKDOWN TEXT
// ─────────────────────────────────────────────────────────────────

class _MdText extends StatelessWidget {
  final String text; final bool isDark; final Color accent;
  const _MdText({required this.text, required this.isDark, required this.accent});
  @override
  Widget build(BuildContext context) {
    final base  = isDark ? Colors.white : Colors.black87;
    final muted = isDark ? Colors.white.withOpacity(0.52) : Colors.black.withOpacity(0.52);
    final spans = <TextSpan>[];
    for (int li = 0; li < text.split('\n').length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      final line = text.split('\n')[li];
      if (line.startsWith('> ')) {
        spans.add(TextSpan(text: '  ${line.substring(2)}',
            style: TextStyle(color: muted, fontSize: 14, height: 1.5, fontStyle: FontStyle.italic)));
        continue;
      }
      final re = RegExp(r'\*\*(.*?)\*\*|_(.*?)_|`(.*?)`');
      int last = 0;
      for (final m in re.allMatches(line)) {
        if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start),
            style: TextStyle(color: base, fontSize: 16, height: 1.5)));
        if (m.group(1) != null) spans.add(TextSpan(text: m.group(1),
            style: TextStyle(color: base, fontSize: 16, height: 1.5, fontWeight: FontWeight.w700)));
        else if (m.group(2) != null) spans.add(TextSpan(text: m.group(2),
            style: TextStyle(color: muted, fontSize: 15, height: 1.5, fontStyle: FontStyle.italic)));
        else if (m.group(3) != null) spans.add(TextSpan(text: m.group(3), style: TextStyle(
            color: accent, fontSize: 14, height: 1.5, fontFamily: 'monospace',
            backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))));
        last = m.end;
      }
      if (last < line.length) spans.add(TextSpan(text: line.substring(last),
          style: TextStyle(color: base, fontSize: 16, height: 1.5)));
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}

class _Dots extends StatelessWidget {
  final AnimationController ctrl; final Color color;
  const _Dots({required this.ctrl, required this.color});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: ctrl, builder: (_, __) =>
    Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final phase = (ctrl.value + i / 3.0) % 1.0;
      final op    = 0.2 + 0.8 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
      return Container(margin: const EdgeInsets.only(right: 4), width: 6, height: 6,
          decoration: BoxDecoration(color: color.withOpacity(op), shape: BoxShape.circle));
    })));
}

class _IBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _IBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Icon(icon, size: 19, color: color));
}


// ─────────────────────────────────────────────────────────────────
// HUMAN INPUT OVERLAY
// ─────────────────────────────────────────────────────────────────

class _HumanOverlay extends StatelessWidget {
  final _HumanReq req; final bool isDark; final List<Color> gc;
  final TextEditingController ctrl; final String? screenshot;
  final void Function(String) onSubmit;
  const _HumanOverlay({required this.req, required this.isDark, required this.gc,
      required this.ctrl, required this.onSubmit, this.screenshot});

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black.withOpacity(0.70),
      child: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Container(padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF111111) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, 10))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 56, height: 56,
              decoration: BoxDecoration(
                color: req.inputType == 'captcha' ? Colors.orange.withOpacity(0.12) : gc[0].withOpacity(0.12),
                shape: BoxShape.circle),
              child: Icon(req.inputType == 'captcha' ? Icons.shield_outlined
                  : req.inputType == '2fa' ? Icons.phone_android_rounded : Icons.person_outline_rounded,
                color: req.inputType == 'captcha' ? Colors.orange : gc[0], size: 28)),
            const SizedBox(height: 18),
            if (screenshot != null)
              Container(height: 120, margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.hardEdge, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                child: Image.memory(base64Decode(screenshot!), fit: BoxFit.cover, width: double.infinity)),
            Text(req.message, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 20),
            if (req.inputType == 'captcha') ...[
              Text('Solve the CAPTCHA above, then tap Done.', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => onSubmit('captcha_done'),
                style: ElevatedButton.styleFrom(backgroundColor: gc[0],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('✅ Done — Continue',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)))),
            ] else ...[
              TextField(controller: ctrl, autofocus: true,
                keyboardType: req.inputType == '2fa' ? TextInputType.number : TextInputType.text,
                style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: req.fieldLabel ?? 'Type your answer...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  filled: true, fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () { final a = ctrl.text.trim(); if (a.isNotEmpty) onSubmit(a); },
                style: ElevatedButton.styleFrom(backgroundColor: gc[0],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Submit & Continue',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)))),
            ],
          ]))))));
  }
}


// ─────────────────────────────────────────────────────────────────
// PREFLIGHT SHEET
// ─────────────────────────────────────────────────────────────────

class _PreflightSheet extends StatefulWidget {
  final List<Map<String, dynamic>> questions; final Map<String, String> answers;
  final Map<String, dynamic>? template; final bool isDark; final List<Color> gc;
  final VoidCallback onSubmit, onCancel;
  const _PreflightSheet({required this.questions, required this.answers, required this.template,
      required this.isDark, required this.gc, required this.onSubmit, required this.onCancel});
  @override
  State<_PreflightSheet> createState() => _PreflightSheetState();
}

class _PreflightSheetState extends State<_PreflightSheet> {
  late final Map<String, TextEditingController> _ctrls;
  @override
  void initState() {
    super.initState();
    _ctrls = { for (final q in widget.questions) q['key']: TextEditingController() };
  }
  @override
  void dispose() { for (final c in _ctrls.values) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t   = widget.template;
    final bg  = widget.isDark ? const Color(0xFF0D0D0D) : Colors.white;
    final txt = widget.isDark ? Colors.white : Colors.black87;
    final sub = widget.isDark ? Colors.white54 : Colors.black45;
    return Container(color: Colors.black.withOpacity(0.65),
      child: SafeArea(child: Align(alignment: Alignment.bottomCenter, child: Container(
        margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (t != null) Text(t['icon']?.toString() ?? '🤖', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t?['title']?.toString() ?? 'Before we start',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: txt)),
              Text(t?['platform']?.toString() ?? '', style: TextStyle(fontSize: 13, color: sub)),
            ])),
            GestureDetector(onTap: widget.onCancel, child: Icon(Icons.close_rounded, color: sub)),
          ]),
          const SizedBox(height: 20),
          ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: SingleChildScrollView(child: Column(children: [
              ...widget.questions.map((q) {
                final key  = q['key']      as String;
                final lbl  = q['question'] as String;
                final type = q['type']     as String? ?? 'text';
                final opts = (q['options'] as List? ?? []).cast<String>();
                if (type == 'yes_no') {
                  return Padding(padding: const EdgeInsets.only(bottom: 16), child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lbl, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txt)),
                      const SizedBox(height: 8),
                      Row(children: ['Yes','No'].map((opt) {
                        final sel = widget.answers[key] == opt.toLowerCase();
                        return Padding(padding: const EdgeInsets.only(right: 10), child: GestureDetector(
                          onTap: () => setState(() => widget.answers[key] = opt.toLowerCase()),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? widget.gc[0] : widget.gc[0].withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: widget.gc[0].withOpacity(sel ? 1 : 0.25))),
                            child: Text(opt, style: TextStyle(color: sel ? Colors.white : widget.gc[0],
                                fontWeight: FontWeight.w600, fontSize: 14)))));
                      }).toList()),
                    ]));
                }
                if (type == 'choice' && opts.isNotEmpty) {
                  return Padding(padding: const EdgeInsets.only(bottom: 16), child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lbl, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txt)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: opts.map((opt) {
                        final sel = widget.answers[key] == opt;
                        return GestureDetector(onTap: () => setState(() => widget.answers[key] = opt),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? widget.gc[0] : widget.gc[0].withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: widget.gc[0].withOpacity(sel ? 1 : 0.25))),
                            child: Text(opt, style: TextStyle(color: sel ? Colors.white : widget.gc[0],
                                fontWeight: FontWeight.w600, fontSize: 13))));
                      }).toList()),
                    ]));
                }
                return Padding(padding: const EdgeInsets.only(bottom: 16), child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(lbl, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txt)),
                    const SizedBox(height: 8),
                    TextField(controller: _ctrls[key],
                      maxLines: type == 'textarea' ? 4 : 1,
                      keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
                      onChanged: (v) => widget.answers[key] = v,
                      style: TextStyle(fontSize: 15, color: txt),
                      decoration: InputDecoration(filled: true,
                        fillColor: widget.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
                  ]));
              }),
            ]))),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: widget.gc[0],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text('Start ${t?['icon'] ?? ''} ${t?['platform'] ?? 'Task'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)))),
        ])))));
  }
}


// ─────────────────────────────────────────────────────────────────
// TOKEN EXHAUSTED SHEET
// ─────────────────────────────────────────────────────────────────

class _TokenSheet extends StatelessWidget {
  final bool isDark, canWatchAd; final int adWatchesLeft; final List<Color> gc;
  final VoidCallback onWatchAd, onSubscribe, onComeTomorrow;
  const _TokenSheet({required this.isDark, required this.canWatchAd, required this.adWatchesLeft,
      required this.gc, required this.onWatchAd, required this.onSubscribe, required this.onComeTomorrow});

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? Colors.white.withOpacity(0.52) : Colors.black.withOpacity(0.52);
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Container(width: 60, height: 60,
          decoration: BoxDecoration(gradient: LinearGradient(colors: gc), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32)),
        const SizedBox(height: 18),
        Text('APEX tokens used up ⚡', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 10),
        Text(
          canWatchAd
              ? 'Watch a short ad to get 100 more tokens ($adWatchesLeft ad${adWatchesLeft != 1 ? 's' : ''} left today), or upgrade for unlimited access.'
              : "You've watched all 5 ads today. Come back tomorrow, or upgrade to Premium for unlimited APEX.",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.6, color: sub)),
        const SizedBox(height: 28),
        if (canWatchAd) ...[
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: onWatchAd,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
            label: const Text('Watch Ad — Get 100 Tokens',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: gc[0], foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 15)))),
          const SizedBox(height: 10),
        ],
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onSubscribe,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 15)),
          child: const Text('⭐ Upgrade to Premium — Unlimited',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))),
        const SizedBox(height: 10),
        TextButton(onPressed: onComeTomorrow,
            child: Text('Come back tomorrow', style: TextStyle(color: sub, fontSize: 14))),
      ]));
  }
}


// ─────────────────────────────────────────────────────────────────
// OLD LIMIT SHEET (run-quota system)
// ─────────────────────────────────────────────────────────────────

class _LimitSheet extends StatelessWidget {
  final bool isDark; final VoidCallback onWatchAd;
  const _LimitSheet({required this.isDark, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? Colors.white.withOpacity(0.52) : Colors.black.withOpacity(0.52);
    final gc  = isDark ? [const Color(0xFF4A90D9), const Color(0xFF7B68EE)]
                       : [const Color(0xFF5B7FFF), const Color(0xFF8B5CF6)];
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 24),
        Container(width: 58, height: 58,
          decoration: BoxDecoration(gradient: LinearGradient(colors: gc), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 28)),
        const SizedBox(height: 16),
        Text('Daily limit reached', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 10),
        Text("You've used all your free runs today.\nWatch a short ad for 1 more run, or upgrade\nto Premium for unlimited access.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.55, color: sub)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onWatchAd,
            style: OutlinedButton.styleFrom(side: BorderSide(color: gc[0]),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text('Watch Ad', style: TextStyle(color: gc[0], fontWeight: FontWeight.w600, fontSize: 15)))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(context); context.push('/premium'); },
            style: ElevatedButton.styleFrom(backgroundColor: gc[0],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Upgrade', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)))),
        ]),
      ]));
  }
}

// ignore_for_file: deprecated_member_use
