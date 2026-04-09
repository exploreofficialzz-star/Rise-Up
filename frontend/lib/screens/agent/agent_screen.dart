// frontend/lib/screens/agent/agent_screen.dart
//
// APEX Agent — v6.1
// • Sidebar overlays content (no layout shift / resize)
// • Simple empty state: greeting only, no suggestion chips
// • Star ⭐ on send button twinkles while streaming
// • Input always rounded (no focus-border flash)
// • Contextual wealth tip shown after task completes
// • All quota / ad-credit / premium limits enforced

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
  /// Contextual wealth tip extracted from agent response data.
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

/// One live execution step shown inside the task-preview card.
class _Step {
  final String tool;
  final String label;
  final String category;
  bool isDone;

  _Step({
    required this.tool,
    required this.label,
    required this.category,
    this.isDone = false,
  });
}

// ─────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────

class AgentScreen extends ConsumerStatefulWidget {
  final String? workflowId;
  final String? sessionId;
  const AgentScreen({super.key, this.workflowId, this.sessionId});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen>
    with SingleTickerProviderStateMixin {

  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  // Star pulse animation
  late final AnimationController _starCtrl;
  late final Animation<double>   _starScale;
  late final Animation<double>   _starGlow;

  // Message & live execution state
  List<_Msg>  _msgs              = [];
  List<_Step> _liveSteps         = [];
  String      _currentThought    = '';
  bool        _executionExpanded = false;

  // Chat state
  bool    _isStreaming    = false;
  bool    _inputEnabled   = true;
  String? _workflowId;
  String? _sessionId;
  bool    _showSidebar    = false;
  bool    _hasStartedChat = false;

  @override
  void initState() {
    super.initState();
    _workflowId = widget.workflowId;
    _sessionId  = widget.sessionId;

    _starCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _starScale = Tween<double>(begin: 0.85, end: 1.20).animate(
      CurvedAnimation(parent: _starCtrl, curve: Curves.easeInOut),
    );
    _starGlow = Tween<double>(begin: 0.20, end: 0.70).animate(
      CurvedAnimation(parent: _starCtrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _starCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _startStar() {
    if (!_starCtrl.isAnimating) _starCtrl.repeat(reverse: true);
  }

  void _stopStar() {
    _starCtrl.stop();
    _starCtrl.animateTo(0, duration: const Duration(milliseconds: 350));
  }

  // ── Init ───────────────────────────────────────────
  void _init() async {
    if (_sessionId != null) {
      await _loadSession(_sessionId!);
      setState(() => _hasStartedChat = true);
    }
  }

  // ── Load session ────────────────────────────────────
  Future<void> _loadSession(String sessionId) async {
    try {
      final response = await api.get('/agent/chat/sessions/$sessionId');
      final messages = response['recent_messages'] as List? ?? [];
      setState(() {
        _msgs = messages
            .where((m) => ['user', 'assistant'].contains(m['role']))
            .map((m) => _Msg(
                  role:      m['role'] == 'user' ? _Role.user : _Role.agent,
                  text:      m['content'] ?? '',
                  modelTier: m['metadata']?['model_tier'],
                ))
            .toList();
        _sessionId = sessionId;
      });
      _scrollDown();
    } catch (_) {}
  }

  // ── Submit ──────────────────────────────────────────
  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isStreaming) return;

    _inputCtrl.clear();
    HapticFeedback.lightImpact();
    if (_showSidebar) setState(() => _showSidebar = false);

    setState(() {
      _msgs.add(_Msg(role: _Role.user, text: text));
      _isStreaming       = true;
      _inputEnabled      = false;
      _hasStartedChat    = true;
      _liveSteps         = [];
      _currentThought    = 'Understanding your goal...';
      _executionExpanded = false;
    });
    _startStar();
    _scrollDown();

    if (!adManager.canUseAgent) {
      _showLimitDialog();
      setState(() {
        _isStreaming    = false;
        _inputEnabled   = true;
        _currentThought = '';
        _liveSteps      = [];
      });
      _stopStar();
      return;
    }
    adManager.recordAgentUse();

    final profile  = ref.read(profileProvider).valueOrNull ?? {};
    final currCode = profile['currency']?.toString() ?? 'USD';
    currency.init(currCode);

    final userMsgCount = _msgs.where((m) => m.role == _Role.user).length;
    if (userMsgCount == 1 && _sessionId == null) {
      await _agentRun(text, currCode);
    } else {
      await _chatRound(text);
    }
  }

  // ── Full agent run (SSE) ────────────────────────────
  Future<void> _agentRun(String task, String currCode) async {
    try {
      final profile = ref.read(profileProvider).valueOrNull ?? {};
      final stream  = api.streamPost('/agent/run-stream', {
        'task':              task,
        'budget':            0.0,
        'hours_per_day':     2.0,
        'currency':          currCode,
        'country':           profile['country'],
        'language':          profile['language'] ?? 'en',
        'allow_email':       false,
        'allow_social_post': false,
        'session_id':        _sessionId,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });

      await for (final event in stream) {
        if (!mounted) break;
        _onEvent(event);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveSteps      = [];
        _currentThought = '';
        _msgs.add(const _Msg(
          role: _Role.error,
          text: 'Connection issue. Please try again.',
        ));
        _isStreaming  = false;
        _inputEnabled = true;
      });
      _stopStar();
    }
  }

  void _onEvent(StreamEvent event) {
    setState(() {
      switch (event.type) {
        case 'quota_check':
        case 'brain_context':
          break;

        case 'thinking':
          final thought = event.data['thought']?.toString() ?? '';
          _currentThought = thought.isEmpty ? 'Thinking...' : thought;

        case 'tool_call':
          final tool = event.data['tool']?.toString() ?? '';
          final cat  = event.data['category']?.toString() ?? 'thinking';
          _liveSteps.add(_Step(
            tool:     tool,
            label:    _toolLabel(tool),
            category: cat,
          ));
          _currentThought = '${_toolLabel(tool)}...';

        case 'tool_result':
          final tool = event.data['tool']?.toString() ?? '';
          for (final step in _liveSteps.reversed) {
            if (step.tool == tool && !step.isDone) {
              step.isDone = true;
              break;
            }
          }

        case 'action_done':
          final tool   = event.data['tool']?.toString() ?? '';
          final result = event.data['result'] as Map? ?? {};
          final ok = result['posted'] == true || result['sent'] == true;
          for (final step in _liveSteps.reversed) {
            if (step.tool == tool) { step.isDone = true; break; }
          }
          _msgs.add(_Msg(
            role:         _Role.action,
            text:         ok
                ? '✅ ${_toolLabel(tool)} — completed'
                : '📋 ${_toolLabel(tool)} — ready',
            toolName:     tool,
            toolCategory: 'action',
            metadata:     jsonEncode(result),
          ));

        case 'finalizing':
          _currentThought = 'Writing your complete plan...';

        case 'complete':
          _workflowId = event.data['workflow_id']?.toString() ?? _workflowId;
          _sessionId  = event.data['session_id']?.toString()  ?? _sessionId;
          final data  = Map<String, dynamic>.from(event.data);
          _msgs.add(_Msg(
            role:          _Role.agent,
            text:          _buildResponse(data),
            metadata:      jsonEncode(data),
            modelTier:     data['model_tier']?.toString() ?? 'free',
            contextualTip: _buildContextualTip(data),
          ));
          _liveSteps      = [];
          _currentThought = '';
          _isStreaming     = false;
          _inputEnabled    = true;

        case 'error':
          _liveSteps      = [];
          _currentThought = '';
          final errMsg = event.data['message']?.toString() ?? '';
          if (errMsg.contains('limit')) {
            _msgs.add(const _Msg(
              role: _Role.system,
              text: '**Daily limit reached** 🔒\n\nYou\'ve used all your free '
                  'runs today. Watch an ad for 1 more, or upgrade to Premium '
                  'for unlimited access.',
            ));
          } else {
            _msgs.add(const _Msg(
              role: _Role.error,
              text: 'Something went wrong. Please try rephrasing your request.',
            ));
          }
          _isStreaming  = false;
          _inputEnabled = true;
      }
    });

    if (!_isStreaming) _stopStar();
    _scrollDown();
  }

  // ── Follow-up chat ──────────────────────────────────
  Future<void> _chatRound(String message) async {
    setState(() {
      _liveSteps      = [];
      _currentThought = 'Thinking...';
    });
    _scrollDown();

    try {
      final r = await api.post('/agent/chat', {
        'message':     message,
        'session_id':  _sessionId,
        'workflow_id': _workflowId,
        'stream':      false,
      });
      _sessionId = r['session_id']?.toString() ?? _sessionId;
      setState(() {
        _currentThought = '';
        _msgs.add(_Msg(
          role:      _Role.agent,
          text:      r['content']?.toString() ?? '...',
          modelTier: r['model_tier']?.toString(),
        ));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    } catch (_) {
      setState(() {
        _currentThought = '';
        _msgs.add(const _Msg(
          role: _Role.error,
          text: 'Connection issue. Please try again.',
        ));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    }
    _stopStar();
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newChat() {
    setState(() {
      _msgs              = [];
      _liveSteps         = [];
      _currentThought    = '';
      _workflowId        = null;
      _sessionId         = null;
      _isStreaming        = false;
      _inputEnabled       = true;
      _hasStartedChat     = false;
      _executionExpanded  = false;
      _showSidebar        = false;
    });
    _stopStar();
    _inputFocus.requestFocus();
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LimitSheet(
        isDark: isDark,
        onWatchAd: () {
          Navigator.pop(context);
          adManager.watchAdForAgentUse(context).then((ok) {
            if (ok && mounted) _submit();
          });
        },
      ),
    );
  }

  // ── Contextual tip from agent data ──────────────────
  String? _buildContextualTip(Map<String, dynamic> data) {
    final now     = data['immediate_action']?.toString() ?? '';
    final insight = data['wealth_insight']?.toString()   ?? '';
    final plan    = data['plan']                as Map?  ?? {};
    final opps    = data['opportunities_found'] as List? ?? [];
    final range   = plan['income_range']        as Map?  ?? {};
    final sym     = _getCurrencySymbol(
        range['currency']?.toString() ?? currency.code);

    if (opps.isNotEmpty) {
      final opp      = opps.first as Map;
      final platform = opp['platform']?.toString() ?? '';
      final title    = opp['title']?.toString()    ?? '';
      if (platform.isNotEmpty && title.isNotEmpty) {
        return '💡 You could earn from "$title" on $platform — want me to help you apply?';
      }
    }
    if ((range['max'] ?? 0) > 0) {
      final max      = _fmt(range['max']);
      final timeline = plan['timeline']?.toString() ?? 'soon';
      return '💡 This plan could earn you up to $sym$max/mo in $timeline — want a full breakdown?';
    }
    if (now.isNotEmpty)     return '⚡ $now — want help getting started right now?';
    if (insight.isNotEmpty) return '💡 $insight';
    return null;
  }

  // ── Build response text ─────────────────────────────
  String _buildResponse(Map<String, dynamic> data) {
    final buf   = StringBuffer();
    final resp  = data['agent_response']?.toString()      ?? '';
    final plan  = data['plan']                as Map?  ?? {};
    final steps = data['steps']               as List? ?? [];
    final tools = data['free_tools']          as List? ?? [];
    final opps  = data['opportunities_found'] as List? ?? [];
    final docs  = data['documents_generated'] as List? ?? [];
    final msgs  = data['outreach_messages']   as List? ?? [];
    final posts = data['social_posts']        as List? ?? [];

    if (resp.isNotEmpty) { buf.writeln(resp); buf.writeln(); }

    if (plan['title'] != null) {
      buf.writeln('**${plan['title']}**');
      final r   = plan['income_range'] as Map? ?? {};
      final sym = _getCurrencySymbol(
          r['currency']?.toString() ?? currency.code);
      if ((r['max'] ?? 0) > 0) {
        buf.writeln(
            '$sym${_fmt(r['min'] ?? 0)} – $sym${_fmt(r['max'] ?? 0)}/mo  ·  '
            '${plan['timeline'] ?? ''}  ·  ${plan['viability'] ?? 75}% viable');
      }
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
        if (out.length > 20) {
          buf.writeln('> ${out.substring(0, out.length.clamp(0, 150))}...');
        }
        buf.writeln();
      }
    }

    if (opps.isNotEmpty) {
      buf.writeln('**${opps.length} real opportunities found:**');
      for (final o in opps.take(4)) {
        final opp = o as Map;
        final fit = opp['fit_score'] != null
            ? ' (${opp['fit_score']}% fit)'
            : '';
        buf.writeln('• **${opp['title']}** — ${opp['platform'] ?? ''}$fit');
        if (opp['url']?.toString().isNotEmpty == true) {
          buf.writeln('  ${opp['url']}');
        }
      }
      buf.writeln();
    }

    if (docs.isNotEmpty) {
      buf.writeln('**Documents generated:** '
          '${docs.map((d) => (d as Map)['type']).join(', ')}');
      buf.writeln('_View in Workflow tab_');
      buf.writeln();
    }

    if (msgs.isNotEmpty) {
      buf.writeln('**${msgs.length} outreach message(s)** ready to send.');
      buf.writeln();
    }
    if (posts.isNotEmpty) {
      buf.writeln('**${posts.length} social post(s)** drafted.');
      buf.writeln();
    }

    if (tools.isNotEmpty) {
      buf.writeln('**Free tools:** '
          '${tools.take(5).map((t) => (t as Map)['name']).join(' · ')}');
      buf.writeln();
    }

    if (plan['warning']?.toString().isNotEmpty == true) {
      buf.writeln('\n⚠️ ${plan['warning']}');
    }

    return buf.toString().trim();
  }

  String _getCurrencySymbol(String code) {
    try {
      return NumberFormat.simpleCurrency(name: code)
          .format(0)
          .replaceAll(RegExp(r'[\d,. ]'), '')
          .trim();
    } catch (_) { return code; }
  }

  String _fmt(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  String _toolLabel(String tool) {
    const map = {
      'web_search':                'Searching the web',
      'deep_research':             'Deep researching',
      'find_freelance_jobs':       'Finding freelance jobs',
      'find_partners':             'Finding business partners',
      'find_free_resources':       'Finding free tools',
      'market_research':           'Analysing the market',
      'scan_opportunities':        'Scanning for opportunities',
      'write_content':             'Writing content',
      'create_plan':               'Building execution plan',
      'estimate_income':           'Estimating income',
      'generate_ideas':            'Generating ideas',
      'write_cold_outreach':       'Writing outreach',
      'build_profile_content':     'Building profile',
      'breakdown_task':            'Breaking down task',
      'create_template':           'Creating template',
      'send_email':                'Sending email',
      'post_twitter':              'Posting to Twitter/X',
      'post_linkedin':             'Posting to LinkedIn',
      'generate_contract':         'Generating contract',
      'generate_invoice':          'Generating invoice',
      'generate_proposal':         'Generating proposal',
      'generate_pitch_deck':       'Generating pitch deck',
      'scrape_live_opportunities': 'Finding live opportunities',
      'score_opportunity':         'Scoring opportunity',
      'analyze_market_trends':     'Analysing market trends',
      'create_daily_action_plan':  'Creating action plan',
      'create_follow_up_plan':     'Creating follow-up plan',
      'track_earnings_insight':    'Analysing earnings',
      'growth_milestone_check':    'Checking milestones',
    };
    return map[tool] ?? tool.replaceAll('_', ' ');
  }

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gc     = isDark
        ? [const Color(0xFF4A90D9), const Color(0xFF7B68EE)]
        : [const Color(0xFF5B7FFF), const Color(0xFF8B5CF6)];

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      // Stack: main content always full-width, sidebar overlays on top
      body: Stack(
        children: [
          // Main content — never resized
          Column(
            children: [
              _buildAppBar(isDark, gc),
              Expanded(
                child: _hasStartedChat || _msgs.isNotEmpty
                    ? _buildMessages(isDark, gc)
                    : _buildEmptyState(isDark, gc),
              ),
              _buildInput(isDark, gc),
            ],
          ),

          // Sidebar overlay (dim + slide-in panel)
          if (_showSidebar) ...[
            GestureDetector(
              onTap: () => setState(() => _showSidebar = false),
              child: Container(color: Colors.black.withOpacity(0.45)),
            ),
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: _buildSidebar(isDark, gc),
            ),
          ],
        ],
      ),
    );
  }

  // ── App Bar ─────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isDark, List<Color> gc) {
    final runsLeft  = adManager.agentUsesRemaining;
    final isPremium = adManager.isPremium;

    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(
          _showSidebar ? Icons.close_rounded : Iconsax.menu_1,
          color: isDark ? Colors.white : Colors.black87,
          size: 24,
        ),
        onPressed: () => setState(() => _showSidebar = !_showSidebar),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Twinkling star badge
          AnimatedBuilder(
            animation: _starCtrl,
            builder: (_, __) {
              final scale = _isStreaming ? _starScale.value : 1.0;
              final glow  = _isStreaming ? _starGlow.value  : 0.28;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gc,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: gc[0].withOpacity(glow),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 18),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(
            'APEX',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
      actions: [
        if (!isPremium)
          GestureDetector(
            onTap: runsLeft == 0 ? _showLimitDialog : null,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: runsLeft > 1
                    ? Colors.green.withOpacity(0.12)
                    : runsLeft == 1
                        ? Colors.orange.withOpacity(0.12)
                        : Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: runsLeft > 1
                      ? Colors.green.withOpacity(0.25)
                      : runsLeft == 1
                          ? Colors.orange.withOpacity(0.25)
                          : Colors.red.withOpacity(0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    runsLeft > 0
                        ? Icons.bolt_rounded
                        : Icons.lock_outline_rounded,
                    size: 12,
                    color: runsLeft > 1
                        ? Colors.green
                        : runsLeft == 1
                            ? Colors.orange
                            : Colors.red,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    runsLeft > 0 ? '$runsLeft left' : 'Limit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: runsLeft > 1
                          ? Colors.green
                          : runsLeft == 1
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        IconButton(
          icon: Icon(Icons.add_rounded,
              color: isDark ? Colors.white : Colors.black87, size: 24),
          tooltip: 'New conversation',
          onPressed: _newChat,
        ),
        if (_workflowId != null)
          IconButton(
            icon: Icon(Iconsax.flash, color: gc[0], size: 20),
            tooltip: 'View Workflow',
            onPressed: () => context.push('/workflow/$_workflowId'),
          ),
      ],
    );
  }

  // ── Sidebar (overlay panel) ──────────────────────────
  Widget _buildSidebar(bool isDark, List<Color> gc) {
    return SafeArea(
      right: false,
      child: Container(
        width: 272,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0D0D0D)
              : const Color(0xFFF7F7F8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(4, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: GestureDetector(
                onTap: _newChat,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.09)
                          : Colors.black.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 18,
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : Colors.black54),
                      const SizedBox(width: 10),
                      Text(
                        'New chat',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white.withOpacity(0.9)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                'Recent',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: isDark
                      ? Colors.white.withOpacity(0.32)
                      : Colors.black.withOpacity(0.32),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: api.get('/agent/chat/sessions'),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: gc[0]),
                    );
                  }
                  final sessions =
                      snapshot.data?['sessions'] as List? ?? [];
                  if (sessions.isEmpty) {
                    return Center(
                      child: Text(
                        'No conversations yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withOpacity(0.28)
                              : Colors.black.withOpacity(0.28),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final sess     = sessions[i];
                      final isActive = sess['id'] == _sessionId;
                      return ListTile(
                        dense: true,
                        selected: isActive,
                        selectedTileColor: gc[0].withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        leading: Icon(
                          Iconsax.message_text,
                          size: 18,
                          color: isActive
                              ? gc[0]
                              : (isDark
                                  ? Colors.white.withOpacity(0.4)
                                  : Colors.black38),
                        ),
                        title: Text(
                          sess['title'] ?? 'Untitled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          _formatDate(sess['updated_at']),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white.withOpacity(0.32)
                                : Colors.black38,
                          ),
                        ),
                        onTap: () {
                          setState(() => _showSidebar = false);
                          _loadSession(sess['id']);
                          setState(() => _hasStartedChat = true);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? s) {
    if (s == null) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays}d ago';
    return '${d.day}/${d.month}';
  }

  // ── Empty state — simple greeting only ──────────────
  Widget _buildEmptyState(bool isDark, List<Color> gc) {
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final name    = (profile['full_name']?.toString() ?? '').split(' ').first;
    final greeting = name.isNotEmpty ? 'Hey $name 👋' : 'Hey there 👋';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing star icon
            AnimatedBuilder(
              animation: _starCtrl,
              builder: (_, __) {
                final glow = _isStreaming ? _starGlow.value : 0.35;
                return Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gc,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: gc[0].withOpacity(glow),
                        blurRadius: 32,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 42),
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              'APEX',
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                color: isDark ? Colors.white : Colors.black,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your autonomous wealth agent',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withOpacity(0.38)
                    : Colors.black.withOpacity(0.38),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 52),
            Text(
              greeting,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'How can I help you today?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? Colors.white.withOpacity(0.48)
                    : Colors.black.withOpacity(0.48),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(
      begin: 0.04, end: 0, duration: 500.ms, curve: Curves.easeOut,
    );
  }

  // ── Message list ─────────────────────────────────────
  Widget _buildMessages(bool isDark, List<Color> gc) {
    final showLiveCard =
        _isStreaming && (_liveSteps.isNotEmpty || _currentThought.isNotEmpty);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      itemCount: _msgs.length + (showLiveCard ? 1 : 0),
      itemBuilder: (_, i) {
        if (showLiveCard && i == _msgs.length) {
          return _LiveExecutionCard(
            steps:          _liveSteps,
            currentThought: _currentThought,
            isDark:         isDark,
            gc:             gc,
            isExpanded:     _executionExpanded,
            onToggle: () =>
                setState(() => _executionExpanded = !_executionExpanded),
          );
        }
        final msg = _msgs[i];
        return switch (msg.role) {
          _Role.user   => _UserBubble(msg: msg, gc: gc),
          _Role.agent  => _AgentBubble(
              msg:        msg,
              isDark:     isDark,
              gc:         gc,
              onWorkflow: _workflowId != null
                  ? () => context.push('/workflow/$_workflowId')
                  : null,
              onTip: msg.contextualTip != null
                  ? () {
                      _inputCtrl.text = msg.contextualTip!
                          .replaceAll(RegExp(r'^[💡⚡]\s*'), '')
                          .replaceAll(RegExp(r' — want.*$'), '');
                      _inputFocus.requestFocus();
                    }
                  : null,
            ),
          _Role.action => _ActionLine(msg: msg),
          _Role.error  => _ErrorLine(msg: msg),
          _Role.system => _SystemMsg(
              msg:       msg,
              isDark:    isDark,
              gc:        gc,
              onUpgrade: () => context.push('/premium'),
              onWatchAd: () => adManager
                  .watchAdForAgentUse(context)
                  .then((ok) { if (ok && mounted) _submit(); }),
            ),
        };
      },
    );
  }

  // ── Input bar ────────────────────────────────────────
  Widget _buildInput(bool isDark, List<Color> gc) {
    final hintColor = isDark
        ? Colors.white.withOpacity(0.30)
        : Colors.black.withOpacity(0.30);
    final inputBg =
        isDark ? const Color(0xFF191919) : const Color(0xFFF3F3F5);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.07);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.05),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Always-rounded text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color:        inputBg,
                  borderRadius: BorderRadius.circular(24),
                  border:       Border.all(color: borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: TextField(
                    controller:      _inputCtrl,
                    focusNode:       _inputFocus,
                    enabled:         _inputEnabled,
                    maxLines:        null,
                    minLines:        1,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      fontSize: 16,
                      color:    isDark ? Colors.white : Colors.black87,
                      height:   1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: _isStreaming
                          ? 'APEX is working...'
                          : 'Ask APEX anything...',
                      hintStyle: TextStyle(fontSize: 16, color: hintColor),
                      // All border states removed — container handles visuals
                      border:         InputBorder.none,
                      enabledBorder:  InputBorder.none,
                      focusedBorder:  InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(
                          18, 14, 18, 14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Send button — twinkling star while streaming
            AnimatedBuilder(
              animation: _starCtrl,
              builder: (_, __) {
                final scale  = _isStreaming ? _starScale.value : 1.0;
                final glow   = _isStreaming ? _starGlow.value  : 0.0;
                final active = !_isStreaming;
                return GestureDetector(
                  onTap: active ? _submit : null,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        gradient: active
                            ? LinearGradient(
                                colors: gc,
                                begin: Alignment.topLeft,
                                end:   Alignment.bottomRight,
                              )
                            : null,
                        color: active
                            ? null
                            : (isDark
                                ? Colors.white.withOpacity(0.07)
                                : Colors.black.withOpacity(0.07)),
                        borderRadius: BorderRadius.circular(23),
                        boxShadow: (active || _isStreaming)
                            ? [
                                BoxShadow(
                                  color: gc[0].withOpacity(
                                      active ? 0.30 : glow),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isStreaming
                            ? Icons.star_rounded
                            : Icons.arrow_upward_rounded,
                        color: active || _isStreaming
                            ? Colors.white
                            : (isDark
                                ? Colors.white.withOpacity(0.18)
                                : Colors.black.withOpacity(0.18)),
                        size: 20,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Live execution card (Claude AI-style task preview)
// ─────────────────────────────────────────────────────────────────

class _LiveExecutionCard extends StatefulWidget {
  final List<_Step>  steps;
  final String       currentThought;
  final bool         isDark;
  final List<Color>  gc;
  final bool         isExpanded;
  final VoidCallback onToggle;

  const _LiveExecutionCard({
    required this.steps,
    required this.currentThought,
    required this.isDark,
    required this.gc,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  State<_LiveExecutionCard> createState() => _LiveExecutionCardState();
}

class _LiveExecutionCardState extends State<_LiveExecutionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.isDark
        ? Colors.white.withOpacity(0.46)
        : Colors.black.withOpacity(0.46);
    final bgColor = widget.isDark
        ? const Color(0xFF111111)
        : const Color(0xFFF4F4F6);
    final borderColor = widget.isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.06);
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final doneCount  = widget.steps.where((s) => s.isDone).length;
    final totalCount = widget.steps.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 80, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // APEX label row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: widget.gc),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                Text('APEX',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: textColor,
                    )),
              ],
            ),
          ),
          // Card body
          GestureDetector(
            onTap: totalCount > 0 ? widget.onToggle : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        bgColor,
                borderRadius: BorderRadius.circular(16),
                border:       Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Dots(controller: _dotCtrl, color: widget.gc[0]),
                      const SizedBox(width: 10),
                      if (totalCount == 0)
                        Expanded(
                          child: Text(
                            widget.currentThought.isEmpty
                                ? 'Working...'
                                : widget.currentThought,
                            style: TextStyle(
                              fontSize: 14,
                              color: sub,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else ...[
                        Text(
                          '$doneCount of $totalCount steps done',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.gc[0],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          widget.isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: sub,
                        ),
                      ],
                    ],
                  ),
                  if (widget.currentThought.isNotEmpty &&
                      totalCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.currentThought,
                      style: TextStyle(
                        fontSize: 13,
                        color: sub,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.isExpanded && totalCount > 0) ...[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: borderColor),
                    const SizedBox(height: 10),
                    ...widget.steps.map((step) {
                      final catIcon = switch (step.category) {
                        'research' => '🔍',
                        'action'   => '⚡',
                        'document' => '📄',
                        'thinking' => '💭',
                        _          => '●',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              child: step.isDone
                                  ? Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 16,
                                      color: widget.gc[0],
                                    )
                                  : SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: widget.gc[0],
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$catIcon ${step.label}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: step.isDone ? sub : textColor,
                                  fontWeight: step.isDone
                                      ? FontWeight.normal
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

// ─────────────────────────────────────────────────────────────────
// Message bubbles
// ─────────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  final _Msg        msg;
  final List<Color> gc;
  const _UserBubble({required this.msg, required this.gc});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin:  const EdgeInsets.fromLTRB(72, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gc,
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(20),
            topRight:    Radius.circular(20),
            bottomLeft:  Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, height: 1.45),
        ),
      ),
    ).animate().fadeIn(duration: 160.ms).slideY(
        begin: 0.06, end: 0, duration: 160.ms, curve: Curves.easeOut);
  }
}

class _AgentBubble extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final List<Color>  gc;
  final VoidCallback? onWorkflow;
  final VoidCallback? onTip;

  const _AgentBubble({
    required this.msg,
    required this.isDark,
    required this.gc,
    this.onWorkflow,
    this.onTip,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor  = isDark
        ? Colors.white.withOpacity(0.42)
        : Colors.black.withOpacity(0.42);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 64, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gc),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                Text('APEX',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: textColor,
                    )),
                if (msg.modelTier != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: msg.modelTier == 'premium'
                          ? Colors.amber.withOpacity(0.12)
                          : Colors.grey.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      msg.modelTier!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: msg.modelTier == 'premium'
                            ? Colors.amber
                            : subColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _MdText(text: msg.text, isDark: isDark, accentColor: gc[1]),

          // Contextual wealth tip card
          if (msg.contextualTip != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onTip,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      gc[0].withOpacity(0.10),
                      gc[1].withOpacity(0.10),
                    ],
                    begin: Alignment.centerLeft,
                    end:   Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gc[0].withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        msg.contextualTip!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withOpacity(0.85)
                              : Colors.black87,
                          height: 1.45,
                        ),
                      ),
                    ),
                    if (onTip != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 13, color: gc[0]),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              _IconBtn(
                icon:  Icons.copy_outlined,
                color: subColor,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:  Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (onWorkflow != null) ...[
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onWorkflow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Iconsax.flash, size: 15, color: gc[0]),
                      const SizedBox(width: 5),
                      Text(
                        'View Workflow',
                        style: TextStyle(
                          fontSize: 13,
                          color:      gc[0],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms).slideY(
        begin: 0.04, end: 0, duration: 260.ms, curve: Curves.easeOut);
  }
}

class _ActionLine extends StatelessWidget {
  final _Msg msg;
  const _ActionLine({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 2, 80, 2),
      child: Text(
        msg.text,
        style: const TextStyle(
          fontSize: 13, color: Colors.green, fontWeight: FontWeight.w500),
      ),
    ).animate().fadeIn();
  }
}

class _ErrorLine extends StatelessWidget {
  final _Msg msg;
  const _ErrorLine({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 64, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:        Colors.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: Colors.red.withOpacity(0.18)),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
              fontSize: 15, color: Colors.red, height: 1.45),
        ),
      ),
    ).animate().fadeIn();
  }
}

class _SystemMsg extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final List<Color>  gc;
  final VoidCallback onUpgrade;
  final VoidCallback onWatchAd;

  const _SystemMsg({
    required this.msg,
    required this.isDark,
    required this.gc,
    required this.onUpgrade,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF141414)
              : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.07)
                : Colors.black.withOpacity(0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MdText(text: msg.text, isDark: isDark, accentColor: gc[1]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onWatchAd,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: gc[0]),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Watch Ad',
                        style: TextStyle(
                          color: gc[0],
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gc[0],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Upgrade',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        )),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }
}

// ─────────────────────────────────────────────────────────────────
// Markdown text renderer
// ─────────────────────────────────────────────────────────────────

class _MdText extends StatelessWidget {
  final String text;
  final bool   isDark;
  final Color  accentColor;
  const _MdText(
      {required this.text, required this.isDark, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final base  = isDark ? Colors.white : Colors.black87;
    final muted = isDark
        ? Colors.white.withOpacity(0.52)
        : Colors.black.withOpacity(0.52);
    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (int li = 0; li < lines.length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[li];

      if (line.startsWith('> ')) {
        spans.add(TextSpan(
          text: '  ${line.substring(2)}',
          style: TextStyle(
            color: muted, fontSize: 14, height: 1.5,
            fontStyle: FontStyle.italic),
        ));
        continue;
      }

      final re   = RegExp(r'\*\*(.*?)\*\*|_(.*?)_|`(.*?)`');
      int   last = 0;

      for (final m in re.allMatches(line)) {
        if (m.start > last) {
          spans.add(TextSpan(
            text:  line.substring(last, m.start),
            style: TextStyle(color: base, fontSize: 16, height: 1.5),
          ));
        }
        if (m.group(1) != null) {
          spans.add(TextSpan(
            text: m.group(1),
            style: TextStyle(
                color: base, fontSize: 16, height: 1.5,
                fontWeight: FontWeight.w700),
          ));
        } else if (m.group(2) != null) {
          spans.add(TextSpan(
            text: m.group(2),
            style: TextStyle(
                color: muted, fontSize: 15, height: 1.5,
                fontStyle: FontStyle.italic),
          ));
        } else if (m.group(3) != null) {
          spans.add(TextSpan(
            text: m.group(3),
            style: TextStyle(
              color:           accentColor,
              fontSize:        14,
              height:          1.5,
              fontFamily:      'monospace',
              backgroundColor: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
            ),
          ));
        }
        last = m.end;
      }

      if (last < line.length) {
        spans.add(TextSpan(
          text:  line.substring(last),
          style: TextStyle(color: base, fontSize: 16, height: 1.5),
        ));
      }
    }

    return SelectableText.rich(TextSpan(children: spans));
  }
}

// ─────────────────────────────────────────────────────────────────
// Animated dots
// ─────────────────────────────────────────────────────────────────

class _Dots extends StatelessWidget {
  final AnimationController controller;
  final Color               color;
  const _Dots({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (controller.value + i / 3.0) % 1.0;
          final op    =
              0.2 + 0.8 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
          return Container(
            margin: const EdgeInsets.only(right: 4),
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color.withOpacity(op),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Icon button
// ─────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: Icon(icon, size: 19, color: color));
}

// ─────────────────────────────────────────────────────────────────
// Daily limit sheet
// ─────────────────────────────────────────────────────────────────

class _LimitSheet extends StatelessWidget {
  final bool         isDark;
  final VoidCallback onWatchAd;
  const _LimitSheet({required this.isDark, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    final handleColor = isDark
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.1);
    final subColor = isDark
        ? Colors.white.withOpacity(0.52)
        : Colors.black.withOpacity(0.52);
    final gc = isDark
        ? [const Color(0xFF4A90D9), const Color(0xFF7B68EE)]
        : [const Color(0xFF5B7FFF), const Color(0xFF8B5CF6)];

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 28 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color:        isDark ? const Color(0xFF0F0F0F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color:        handleColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gc),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Daily limit reached',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You\'ve used all your free runs today.\n'
            'Watch a short ad for 1 more run, or upgrade\n'
            'to Premium for unlimited access.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15, height: 1.55, color: subColor),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onWatchAd,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: gc[0]),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Watch Ad',
                      style: TextStyle(
                        color: gc[0],
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      )),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/premium');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gc[0],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Upgrade',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
