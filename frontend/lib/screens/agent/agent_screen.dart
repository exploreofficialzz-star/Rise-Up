// frontend/lib/screens/agent/agent_screen.dart
//
// APEX Agent — Claude-style conversation interface
//
// Design: conversation-first, no forms upfront, clean input at bottom,
// messages flow naturally, agent thinking shown inline, power is invisible.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/api_service.dart';
import '../../services/api_service_stream.dart';
import '../../services/ad_manager.dart';
import '../../services/currency_service.dart';

// ─────────────────────────────────────────────────────
// Message model
// ─────────────────────────────────────────────────────

enum _Role { user, agent, thinking, tool, action, error, system }

class _Msg {
  final _Role   role;
  final String  text;
  final String? toolName;
  final String? toolCategory;
  final bool    isCollapsed;
  final String? metadata;

  const _Msg({
    required this.role,
    required this.text,
    this.toolName,
    this.toolCategory,
    this.isCollapsed = false,
    this.metadata,
  });

  _Msg copyWith({bool? isCollapsed, String? text}) => _Msg(
    role: role, text: text ?? this.text, toolName: toolName,
    toolCategory: toolCategory,
    isCollapsed: isCollapsed ?? this.isCollapsed,
    metadata: metadata,
  );
}

// ─────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────

class AgentScreen extends ConsumerStatefulWidget {
  final String? workflowId;
  const AgentScreen({super.key, this.workflowId});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  List<_Msg> _msgs      = [];
  bool   _isStreaming   = false;
  bool   _inputEnabled  = true;
  String? _workflowId;
  String? _sessionId;
  int    _thinkIdx      = -1;   // index of current thinking bubble

  static const _suggestions = [
    'I want to land my first freelance client this week',
    'Start a YouTube channel from zero — no budget',
    'Find me a business partner in my niche',
    'Write a contract for a client project',
    'Sell products on WhatsApp and Instagram',
    'Scan for income opportunities matching my skills',
  ];

  @override
  void initState() {
    super.initState();
    _workflowId = widget.workflowId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Greeting ─────────────────────────────────────────
  void _greet() {
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final name    = (profile['full_name']?.toString() ?? '').split(' ').first;
    final hi      = name.isNotEmpty ? 'Hey $name 👋' : 'Hey 👋';
    setState(() => _msgs.add(_Msg(
      role: _Role.agent,
      text: '$hi I\'m APEX — your AI agent.\n\n'
            'I don\'t just plan. I research, write content, find real job leads, '
            'draft contracts, send outreach, and post to social media — all on your behalf.\n\n'
            'What do you want to earn or build?',
    )));
  }

  // ── Submit message ───────────────────────────────────
  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isStreaming) return;

    _inputCtrl.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _msgs.add(_Msg(role: _Role.user, text: text));
      _isStreaming  = true;
      _inputEnabled = false;
    });
    _scrollDown();

    if (!adManager.canUseAgent) {
      _showLimitDialog();
      setState(() { _isStreaming = false; _inputEnabled = true; });
      return;
    }
    adManager.recordAgentUse();

    final profile  = ref.read(profileProvider).valueOrNull ?? {};
    final currCode = profile['currency']?.toString() ?? 'USD';
    currency.init(currCode);

    // First user message = full agent run; subsequent = chat
    final isFirst = _msgs.where((m) => m.role == _Role.user).length == 1;
    if (isFirst) {
      await _agentRun(text, currCode);
    } else {
      await _chatRound(text);
    }
  }

  // ── Full agent run (SSE streaming) ───────────────────
  Future<void> _agentRun(String task, String currCode) async {
    // Insert thinking bubble
    setState(() {
      _thinkIdx = _msgs.length;
      _msgs.add(const _Msg(role: _Role.thinking, text: 'Analysing your goal...'));
    });
    _scrollDown();

    try {
      final stream = api.streamPost('/agent/run-stream', {
        'task':              task,
        'budget':            0.0,
        'hours_per_day':     2.0,
        'currency':          currCode,
        'allow_email':       false,
        'allow_social_post': false,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });

      await for (final event in stream) {
        if (!mounted) break;
        _onEvent(event);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
        _msgs.removeWhere((m) => m.role == _Role.tool);
        _msgs.add(const _Msg(role: _Role.error, text: 'Agent hit a snag. Please try again.'));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    }
  }

  void _onEvent(StreamEvent event) {
    setState(() {
      switch (event.type) {

        case 'thinking':
          final thought = event.data['thought']?.toString() ?? '';
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs[_thinkIdx] = _Msg(
              role: _Role.thinking,
              text: thought.isEmpty ? 'Thinking...' : thought,
            );
          }

        case 'tool_call':
          final tool = event.data['tool']?.toString() ?? '';
          final cat  = event.data['category']?.toString() ?? 'thinking';
          _msgs.add(_Msg(
            role: _Role.tool, text: _toolLabel(tool),
            toolName: tool, toolCategory: cat,
          ));
          _scrollDown();

        case 'tool_result':
          // Mark tool bubble as done (will be cleaned up on complete)
          final tool = event.data['tool']?.toString() ?? '';
          for (int i = _msgs.length - 1; i >= 0; i--) {
            if (_msgs[i].role == _Role.tool && _msgs[i].toolName == tool) {
              _msgs[i] = _msgs[i].copyWith(isCollapsed: true);
              break;
            }
          }

        case 'action_done':
          final tool   = event.data['tool']?.toString() ?? '';
          final result = event.data['result'] as Map? ?? {};
          final ok     = result['posted'] == true || result['sent'] == true;
          _msgs.add(_Msg(
            role: _Role.action,
            text: ok
                ? '✅ ${_toolLabel(tool)} — done'
                : '📋 ${_toolLabel(tool)} — ready to send',
            toolName:     tool,
            toolCategory: 'action',
            metadata:     jsonEncode(result),
          ));
          _scrollDown();

        case 'finalizing':
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs[_thinkIdx] = const _Msg(
                role: _Role.thinking, text: '', isCollapsed: true);
          }

        case 'complete':
          // Clean up
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs.removeAt(_thinkIdx);
            _thinkIdx = -1;
          }
          _msgs.removeWhere((m) => m.role == _Role.tool);

          _workflowId = event.data['workflow_id']?.toString() ?? _workflowId;
          _sessionId ??= 'apex_${DateTime.now().millisecondsSinceEpoch}';

          _msgs.add(_Msg(
            role:     _Role.agent,
            text:     _buildResponse(Map<String, dynamic>.from(event.data)),
            metadata: jsonEncode(event.data),
          ));
          _isStreaming  = false;
          _inputEnabled = true;
          _scrollDown();

        case 'error':
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs.removeAt(_thinkIdx);
            _thinkIdx = -1;
          }
          _msgs.removeWhere((m) => m.role == _Role.tool);
          final msg = event.data['message']?.toString() ?? '';
          if (msg.contains('limit')) {
            _msgs.add(const _Msg(role: _Role.system,
              text: '🔒 You\'ve used all 3 free runs today.\nWatch an ad for 1 more or upgrade to Premium for 25/day.'));
          } else {
            _msgs.add(const _Msg(role: _Role.error,
              text: 'Agent hit an issue. Try rephrasing your goal.'));
          }
          _isStreaming  = false;
          _inputEnabled = true;
      }
    });
    _scrollDown();
  }

  // ── Follow-up chat ───────────────────────────────────
  Future<void> _chatRound(String message) async {
    setState(() {
      _thinkIdx = _msgs.length;
      _msgs.add(const _Msg(role: _Role.thinking, text: ''));
    });
    _scrollDown();

    try {
      final r = await api.post('/agent/chat', {
        'message':    message,
        if (_sessionId  != null) 'session_id':  _sessionId,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      _sessionId = r['session_id']?.toString() ?? _sessionId;
      setState(() {
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
        _msgs.add(_Msg(role: _Role.agent, text: r['content']?.toString() ?? '...'));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    } catch (_) {
      setState(() {
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
        _msgs.add(const _Msg(role: _Role.error, text: 'Connection issue. Please try again.'));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newChat() {
    setState(() {
      _msgs       = [];
      _workflowId = null;
      _sessionId  = null;
      _isStreaming = false;
      _inputEnabled = true;
      _thinkIdx   = -1;
    });
    _greet();
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LimitSheet(
        isDark: isDark,
        onWatchAd: () {
          Navigator.pop(context);
          adManager.watchAdForAgentUse(context)
              .then((ok) { if (ok && mounted) _submit(); });
        },
      ),
    );
  }

  // ── Build natural language response from agent data ──
  String _buildResponse(Map<String, dynamic> data) {
    final buf     = StringBuffer();
    final resp    = data['agent_response']?.toString() ?? '';
    final plan    = data['plan']   as Map?  ?? {};
    final steps   = data['steps']  as List? ?? [];
    final tools   = data['free_tools']           as List? ?? [];
    final opps    = data['opportunities_found']  as List? ?? [];
    final docs    = data['documents_generated']  as List? ?? [];
    final msgs    = data['outreach_messages']    as List? ?? [];
    final posts   = data['social_posts']         as List? ?? [];
    final now     = data['immediate_action']?.toString() ?? '';
    final insight = data['wealth_insight']?.toString() ?? '';

    if (resp.isNotEmpty) { buf.writeln(resp); buf.writeln(); }

    if (plan['title'] != null) {
      buf.writeln('**${plan['title']}**');
      final r   = plan['income_range'] as Map? ?? {};
      final sym = CurrencyService.symbolFor(
          r['currency']?.toString() ?? currency.code);
      if ((r['max'] ?? 0) > 0) {
        buf.writeln('$sym${_fmt(r['min'] ?? 0)} – $sym${_fmt(r['max'] ?? 0)}/mo  ·  '
            '${plan['timeline'] ?? ''}  ·  ${plan['viability'] ?? 75}% viable');
      }
      buf.writeln();
    }

    if (steps.isNotEmpty) {
      buf.writeln('**Your ${steps.length}-step plan:**');
      for (final s in steps.take(7)) {
        final step  = s as Map;
        final auto  = step['type'] == 'automated' ? ' _(AI handles this)_' : '';
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
        final fit = opp['fit_score'] != null ? ' (${opp['fit_score']}% fit)' : '';
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
      buf.writeln('_Copy them from the Workflow screen._');
      buf.writeln();
    }

    if (msgs.isNotEmpty) {
      buf.writeln('**${msgs.length} outreach message(s) written** and ready to send.');
      buf.writeln();
    }

    if (posts.isNotEmpty) {
      buf.writeln('**${posts.length} social post(s)** written.');
      buf.writeln();
    }

    if (tools.isNotEmpty) {
      buf.writeln('**Free tools:** '
          '${tools.take(5).map((t) => (t as Map)['name']).join(' · ')}');
      buf.writeln();
    }

    if (now.isNotEmpty) {
      buf.writeln('⚡ **Do this right now:** $now');
      buf.writeln();
    }

    if (insight.isNotEmpty) {
      buf.writeln('_$insight_');
    }

    if (plan['warning']?.toString().isNotEmpty == true) {
      buf.writeln();
      buf.writeln('⚠️ ${plan['warning']}');
    }

    return buf.toString().trim();
  }

  String _fmt(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  String _toolLabel(String tool) {
    const map = {
      'web_search':           'Searching the web',
      'deep_research':        'Deep researching',
      'find_freelance_jobs':  'Finding freelance jobs',
      'find_partners':        'Finding business partners',
      'find_free_resources':  'Finding free tools',
      'market_research':      'Analysing the market',
      'scan_opportunities':   'Scanning for opportunities',
      'write_content':        'Writing content',
      'create_plan':          'Building execution plan',
      'estimate_income':      'Estimating income',
      'generate_ideas':       'Generating ideas',
      'write_cold_outreach':  'Writing outreach',
      'build_profile_content':'Building profile',
      'breakdown_task':       'Breaking down task',
      'create_template':      'Creating template',
      'send_email':           'Sending email',
      'post_twitter':         'Posting to Twitter/X',
      'post_linkedin':        'Posting to LinkedIn',
      'generate_contract':    'Generating contract',
      'generate_invoice':     'Generating invoice',
      'generate_proposal':    'Generating proposal',
      'generate_pitch_deck':  'Generating pitch deck',
    };
    return map[tool] ?? tool.replaceAll('_', ' ');
  }

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final text   = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, text),
      body: Column(children: [
        Expanded(child: _buildMessages(isDark)),
        _buildInput(isDark, text),
      ]),
    );
  }

  AppBar _buildAppBar(bool isDark, Color text) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: text, size: 22),
        onPressed: () => context.pop(),
      ),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 9),
        Text('APEX', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: text)),
      ]),
      actions: [
        if (!adManager.isPremium)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: adManager.agentUsesRemaining > 0
                  ? AppColors.success.withOpacity(0.12)
                  : AppColors.error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${adManager.agentUsesRemaining}/3',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: adManager.agentUsesRemaining > 0
                    ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        if (_msgs.length > 1)
          IconButton(
            icon: Icon(Icons.add_rounded, color: text, size: 22),
            tooltip: 'New conversation',
            onPressed: _newChat,
          ),
        if (_workflowId != null)
          IconButton(
            icon: const Icon(Iconsax.flash, color: AppColors.primary, size: 18),
            tooltip: 'View Workflow',
            onPressed: () => context.push('/workflow/$_workflowId'),
          ),
      ],
    );
  }

  Widget _buildMessages(bool isDark) {
    // Show suggestion chips after the initial greeting
    final showSuggestions = _msgs.length == 1 &&
        _msgs.first.role == _Role.agent;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      itemCount: _msgs.length + (showSuggestions ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _msgs.length) return _buildSuggestions(isDark);
        final msg = _msgs[i];
        return switch (msg.role) {
          _Role.user     => _UserBubble(msg: msg),
          _Role.agent    => _AgentBubble(
              msg: msg, isDark: isDark,
              onWorkflow: _workflowId != null
                  ? () => context.push('/workflow/$_workflowId') : null,
            ),
          _Role.thinking => _ThinkingBubble(msg: msg, isDark: isDark),
          _Role.tool     => _ToolLine(msg: msg, isDark: isDark),
          _Role.action   => _ActionLine(msg: msg),
          _Role.error    => _ErrorLine(msg: msg),
          _Role.system   => _SystemMsg(
              msg: msg, isDark: isDark,
              onUpgrade: () => context.push('/premium'),
              onWatchAd: () => adManager.watchAdForAgentUse(context)
                  .then((ok) { if (ok && mounted) _submit(); }),
            ),
        };
      },
    );
  }

  Widget _buildSuggestions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(spacing: 8, runSpacing: 8,
        children: _suggestions.map((s) => GestureDetector(
          onTap: () {
            _inputCtrl.text = s;
            _inputFocus.requestFocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Text(s,
              style: TextStyle(fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildInput(bool isDark, Color text) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
          border: Border(top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: TextField(
                controller:  _inputCtrl,
                focusNode:   _inputFocus,
                enabled:     _inputEnabled,
                maxLines:    null,
                minLines:    1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(fontSize: 15, color: text, height: 1.45),
                decoration: InputDecoration(
                  hintText: 'Message APEX...',
                  hintStyle: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white24 : Colors.black26),
                  border:          InputBorder.none,
                  contentPadding:  const EdgeInsets.fromLTRB(18, 12, 18, 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isStreaming ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: _isStreaming ? null : const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                color: _isStreaming
                    ? (isDark ? Colors.white10 : Colors.black12) : null,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: _isStreaming
                    ? (isDark ? Colors.white24 : Colors.black12)
                    : Colors.white,
                size: 20,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Bubble widgets
// ─────────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  final _Msg msg;
  const _UserBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(72, 3, 16, 3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft:     Radius.circular(20),
            topRight:    Radius.circular(20),
            bottomLeft:  Radius.circular(20),
            bottomRight: Radius.circular(5),
          ),
        ),
        child: Text(msg.text,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45)),
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.08, curve: Curves.easeOut);
  }
}

class _AgentBubble extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final VoidCallback? onWorkflow;
  const _AgentBubble({required this.msg, required this.isDark, this.onWorkflow});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor  = isDark ? Colors.white38 : Colors.black38;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 72, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // APEX label
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 11),
            ),
            const SizedBox(width: 6),
            Text('APEX', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: subColor)),
          ]),
        ),

        // Message body
        _MdText(text: msg.text, isDark: isDark),

        // Action row
        const SizedBox(height: 8),
        Row(children: [
          _IconBtn(
            icon: Icons.copy_outlined,
            color: subColor,
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied'), duration: Duration(seconds: 1)));
            },
          ),
          if (onWorkflow != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onWorkflow,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Iconsax.flash, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                const Text('View Workflow',
                    style: TextStyle(fontSize: 12, color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ]),
      ]),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.05, curve: Curves.easeOut);
  }
}

class _ThinkingBubble extends StatefulWidget {
  final _Msg msg;
  final bool isDark;
  const _ThinkingBubble({required this.msg, required this.isDark});
  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 1200.ms)..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sub   = widget.isDark ? Colors.white38 : Colors.black38;
    final empty = widget.msg.text.isEmpty || widget.msg.isCollapsed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 72, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 11),
        ),
        const SizedBox(width: 10),
        if (!empty)
          Expanded(child: Text(
            widget.msg.text,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: sub,
                fontStyle: FontStyle.italic, height: 1.4),
          )),
        if (!empty) const SizedBox(width: 8),
        _Dots(controller: _ctrl),
      ]),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _ToolLine extends StatelessWidget {
  final _Msg msg;
  final bool isDark;
  const _ToolLine({required this.msg, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (msg.isCollapsed) return const SizedBox.shrink();
    final color = _c(msg.toolCategory);
    final emoji = _e(msg.toolCategory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 2, 72, 2),
      child: Row(children: [
        Container(width: 2, height: 12,
            decoration: BoxDecoration(
                color: color.withOpacity(0.35),
                borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 8),
        Text('$emoji ${msg.text}',
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.75))),
        const SizedBox(width: 6),
        SizedBox(width: 9, height: 9,
          child: CircularProgressIndicator(
              strokeWidth: 1.2, color: color.withOpacity(0.4))),
      ]),
    ).animate().fadeIn(duration: 150.ms);
  }

  Color _c(String? cat) => switch (cat) {
    'research' => AppColors.info,
    'action'   => AppColors.success,
    'document' => AppColors.gold,
    _          => AppColors.primary,
  };
  String _e(String? cat) => switch (cat) {
    'research' => '🔍',
    'action'   => '📤',
    'document' => '📄',
    _          => '🧠',
  };
}

class _ActionLine extends StatelessWidget {
  final _Msg msg;
  const _ActionLine({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 2, 72, 2),
      child: Text(msg.text,
          style: const TextStyle(fontSize: 12, color: AppColors.success)),
    ).animate().fadeIn();
  }
}

class _ErrorLine extends StatelessWidget {
  final _Msg msg;
  const _ErrorLine({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 72, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withOpacity(0.18)),
        ),
        child: Text(msg.text,
            style: const TextStyle(fontSize: 14, color: AppColors.error, height: 1.4)),
      ),
    ).animate().fadeIn();
  }
}

class _SystemMsg extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final VoidCallback onUpgrade;
  final VoidCallback onWatchAd;
  const _SystemMsg({required this.msg, required this.isDark,
      required this.onUpgrade, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.text, style: TextStyle(fontSize: 13, height: 1.5,
              color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: onWatchAd,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child: const Text('Watch Ad',
                  style: TextStyle(color: AppColors.primary,
                      fontWeight: FontWeight.w600, fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: onUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child: const Text('Upgrade',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13)),
            )),
          ]),
        ]),
      ),
    ).animate().fadeIn();
  }
}

// ─────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────

// Light markdown parser: **bold**, _italic_, `code`, > blockquote
class _MdText extends StatelessWidget {
  final String text;
  final bool   isDark;
  const _MdText({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base    = isDark ? Colors.white    : Colors.black87;
    final muted   = isDark ? Colors.white54  : Colors.black45;
    final spans   = <TextSpan>[];
    final lines   = text.split('\n');

    for (int li = 0; li < lines.length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[li];

      // Blockquote
      if (line.startsWith('> ')) {
        spans.add(TextSpan(
            text: '  ${line.substring(2)}',
            style: TextStyle(color: muted, fontSize: 13,
                height: 1.5, fontStyle: FontStyle.italic)));
        continue;
      }

      // Inline parsing
      final re = RegExp(r'\*\*(.*?)\*\*|_(.*?)_|`(.*?)`');
      int last = 0;
      for (final m in re.allMatches(line)) {
        if (m.start > last) {
          spans.add(TextSpan(text: line.substring(last, m.start),
              style: TextStyle(color: base, fontSize: 15, height: 1.5)));
        }
        if (m.group(1) != null) {
          spans.add(TextSpan(text: m.group(1),
              style: TextStyle(color: base, fontSize: 15, height: 1.5,
                  fontWeight: FontWeight.w700)));
        } else if (m.group(2) != null) {
          spans.add(TextSpan(text: m.group(2),
              style: TextStyle(color: muted, fontSize: 14, height: 1.5,
                  fontStyle: FontStyle.italic)));
        } else if (m.group(3) != null) {
          spans.add(TextSpan(text: m.group(3),
              style: TextStyle(
                  color: AppColors.accent, fontSize: 13, height: 1.5,
                  fontFamily: 'monospace',
                  backgroundColor: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04))));
        }
        last = m.end;
      }
      if (last < line.length) {
        spans.add(TextSpan(text: line.substring(last),
            style: TextStyle(color: base, fontSize: 15, height: 1.5)));
      }
    }

    return SelectableText.rich(TextSpan(children: spans));
  }
}

// Animated typing dots
class _Dots extends StatelessWidget {
  final AnimationController controller;
  const _Dots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = ((controller.value + i / 3.0) % 1.0);
          final op    = 0.2 + 0.8 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
          return Container(
            margin: const EdgeInsets.only(right: 3),
            width: 5, height: 5,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(op),
                shape: BoxShape.circle),
          );
        }),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Icon(icon, size: 16, color: color),
  );
}

class _LimitSheet extends StatelessWidget {
  final bool isDark;
  final VoidCallback onWatchAd;
  const _LimitSheet({required this.isDark, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('🔒', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        Text('Daily limit reached',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 6),
        Text('3 free runs/day. Watch an ad for 1 more,\nor upgrade to Premium for 25/day.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5,
                color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: onWatchAd,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Watch Ad',
                style: TextStyle(color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/premium');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Upgrade',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          )),
        ]),
      ]),
    );
  }
}
