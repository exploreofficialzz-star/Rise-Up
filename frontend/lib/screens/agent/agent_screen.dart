// frontend/lib/screens/agent/agent_screen.dart
//
// APEX Agent — Kimi/Claude-style conversation interface
// Enhanced for global users with persistent chat sessions

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart'; // FIX 1: was iconsax_flutter — wrong package
import 'package:intl/intl.dart';
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
  final String? modelTier;

  const _Msg({
    required this.role,
    required this.text,
    this.toolName,
    this.toolCategory,
    this.isCollapsed = false,
    this.metadata,
    this.modelTier,
  });

  _Msg copyWith({bool? isCollapsed, String? text}) => _Msg(
        role:         role,
        text:         text ?? this.text,
        toolName:     toolName,
        toolCategory: toolCategory,
        isCollapsed:  isCollapsed ?? this.isCollapsed,
        metadata:     metadata,
        modelTier:    modelTier,
      );
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

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  List<_Msg> _msgs        = [];
  bool       _isStreaming  = false;
  bool       _inputEnabled = true;
  String?    _workflowId;
  String?    _sessionId;
  int        _thinkIdx    = -1;
  bool       _showSidebar = false;

  @override
  void initState() {
    super.initState();
    _workflowId = widget.workflowId;
    _sessionId  = widget.sessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Initialize ─────────────────────────────────────
  void _init() async {
    if (_sessionId != null) {
      await _loadSession(_sessionId!);
    } else {
      _greet();
    }
  }

  void _greet() {
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final name    = (profile['full_name']?.toString() ?? '').split(' ').first;

    setState(() => _msgs.add(_Msg(
          role: _Role.agent,
          text: name.isNotEmpty
              ? '**Hey $name** 👋\n\nI\'m **APEX** — your autonomous AI agent. '
                'I can research, write, find opportunities, draft contracts, and even '
                'post to social media for you.\n\nWhat do you want us to work on today?'
              : '**Hey** 👋\n\nI\'m **APEX** — your autonomous AI agent. '
                'I can research, write, find opportunities, draft contracts, and even '
                'post to social media for you.\n\nWhat do you want us to work on today?',
          modelTier: 'free',
        )));
  }

  // ── Load existing session ───────────────────────────
  Future<void> _loadSession(String sessionId) async {
    try {
      final response = await api.get('/agent/chat/sessions/$sessionId');
      final messages = response['recent_messages'] as List? ?? [];

      setState(() {
        _msgs = messages
            .map((m) => _Msg(
                  role:      _parseRole(m['role']),
                  text:      m['content'] ?? '',
                  modelTier: m['metadata']?['model_tier'],
                ))
            .toList();
        _sessionId = sessionId;
      });
      _scrollDown();
    } catch (e) {
      _greet();
    }
  }

  _Role _parseRole(String? role) {
    return switch (role) {
      'user'      => _Role.user,
      'assistant' => _Role.agent,
      'tool'      => _Role.tool,
      'system'    => _Role.system,
      _           => _Role.agent,
    };
  }

  // ── Submit message ──────────────────────────────────
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
      setState(() {
        _isStreaming  = false;
        _inputEnabled = true;
      });
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

  // ── Full agent run (SSE streaming) ──────────────────
  Future<void> _agentRun(String task, String currCode) async {
    setState(() {
      _thinkIdx = _msgs.length;
      _msgs.add(const _Msg(
          role: _Role.thinking, text: 'Understanding your goal...'));
    });
    _scrollDown();

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
        _msgs.removeWhere((m) => m.role == _Role.tool);
        _msgs.add(const _Msg(
            role: _Role.error,
            text: 'Connection issue. Please try again.'));
        _isStreaming  = false;
        _inputEnabled = true;
      });
    }
  }

  void _onEvent(StreamEvent event) {
    setState(() {
      switch (event.type) {
        case 'quota_check':
          break;

        case 'thinking':
          final thought = event.data['thought']?.toString() ?? '';
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs[_thinkIdx] = _Msg(
              role:      _Role.thinking,
              text:      thought.isEmpty ? 'Thinking...' : thought,
              modelTier: event.data['tier']?.toString(),
            );
          }

        case 'tool_call':
          final tool = event.data['tool']?.toString() ?? '';
          final cat  = event.data['category']?.toString() ?? 'thinking';
          _msgs.add(_Msg(
            role:         _Role.tool,
            text:         _toolLabel(tool),
            toolName:     tool,
            toolCategory: cat,
            modelTier:    event.data['tier']?.toString(),
          ));
          _scrollDown();

        case 'tool_result':
          final tool = event.data['tool']?.toString() ?? '';
          for (int i = _msgs.length - 1; i >= 0; i--) {
            if (_msgs[i].role == _Role.tool &&
                _msgs[i].toolName == tool) {
              _msgs[i] = _msgs[i].copyWith(isCollapsed: true);
              break;
            }
          }

        case 'action_done':
          final tool   = event.data['tool']?.toString() ?? '';
          final result = event.data['result'] as Map? ?? {};
          final ok =
              result['posted'] == true || result['sent'] == true;
          _msgs.add(_Msg(
            role:         _Role.action,
            text:         ok
                ? '✅ ${_toolLabel(tool)} — completed'
                : '📋 ${_toolLabel(tool)} — ready',
            toolName:     tool,
            toolCategory: 'action',
            metadata:     jsonEncode(result),
            modelTier:    event.data['tier']?.toString(),
          ));
          _scrollDown();

        case 'finalizing':
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs[_thinkIdx] = const _Msg(
                role: _Role.thinking, text: '', isCollapsed: true);
          }

        case 'complete':
          if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
            _msgs.removeAt(_thinkIdx);
            _thinkIdx = -1;
          }
          _msgs.removeWhere((m) => m.role == _Role.tool);

          _workflowId =
              event.data['workflow_id']?.toString() ?? _workflowId;
          _sessionId =
              event.data['session_id']?.toString() ?? _sessionId;

          _msgs.add(_Msg(
            role:      _Role.agent,
            text:      _buildResponse(
                Map<String, dynamic>.from(event.data)),
            metadata:  jsonEncode(event.data),
            modelTier: event.data['model_tier']?.toString() ?? 'free',
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
          final errMsg = event.data['message']?.toString() ?? '';
          if (errMsg.contains('limit')) {
            _msgs.add(const _Msg(
              role: _Role.system,
              text: '**Daily limit reached** 🔒\n\nYou\'ve used all your '
                  'free runs today. Watch an ad for 1 more, or upgrade to '
                  'Premium for unlimited access.',
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
    _scrollDown();
  }

  // ── Follow-up chat ──────────────────────────────────
  Future<void> _chatRound(String message) async {
    setState(() {
      _thinkIdx = _msgs.length;
      _msgs.add(const _Msg(role: _Role.thinking, text: ''));
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
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
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
        if (_thinkIdx >= 0 && _thinkIdx < _msgs.length) {
          _msgs.removeAt(_thinkIdx);
          _thinkIdx = -1;
        }
        _msgs.add(const _Msg(
          role: _Role.error,
          text: 'Connection issue. Please try again.',
        ));
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
      _msgs         = [];
      _workflowId   = null;
      _sessionId    = null;
      _isStreaming  = false;
      _inputEnabled = true;
      _thinkIdx     = -1;
    });
    _greet();
    _inputFocus.requestFocus();
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
          adManager
              .watchAdForAgentUse(context)
              .then((ok) {
            if (ok && mounted) _submit();
          });
        },
      ),
    );
  }

  // ── Build natural language response from agent data ─
  String _buildResponse(Map<String, dynamic> data) {
    final buf     = StringBuffer();
    final resp    = data['agent_response']?.toString()       ?? '';
    final plan    = data['plan']                  as Map?  ?? {};
    final steps   = data['steps']                as List? ?? [];
    final tools   = data['free_tools']           as List? ?? [];
    final opps    = data['opportunities_found']  as List? ?? [];
    final docs    = data['documents_generated']  as List? ?? [];
    final msgs    = data['outreach_messages']    as List? ?? [];
    final posts   = data['social_posts']         as List? ?? [];
    final now     = data['immediate_action']?.toString()     ?? '';
    final insight = data['wealth_insight']?.toString()       ?? '';

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
        buf.writeln(
            '• **${opp['title']}** — ${opp['platform'] ?? ''}$fit');
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
      buf.writeln(
          '**${msgs.length} outreach message(s)** ready to send.');
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

    if (now.isNotEmpty) {
      buf.writeln('⚡ **Do this now:** $now');
      buf.writeln();
    }

    if (insight.isNotEmpty) {
      buf.writeln('_$insight');
    }

    if (plan['warning']?.toString().isNotEmpty == true) {
      buf.writeln();
      buf.writeln('⚠️ ${plan['warning']}');
    }

    return buf.toString().trim();
  }

  // FIX 2: Safe currency symbol extraction
  String _getCurrencySymbol(String currencyCode) {
    try {
      final formatted = NumberFormat.simpleCurrency(name: currencyCode)
          .format(0);
      return formatted
          .replaceAll(RegExp(r'[\d,. ]'), '')
          .trim();
    } catch (e) {
      return currencyCode;
    }
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
      'analyze_market_trends':     'Analyzing market trends',
      'create_daily_action_plan':  'Creating action plan',
      'create_follow_up_plan':     'Creating follow-up plan',
      'track_earnings_insight':    'Analyzing earnings',
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
    final bg     = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final text   = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, text),
      body: Row(
        children: [
          if (_showSidebar) _buildSidebar(isDark),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildMessages(isDark)),
                _buildInput(isDark, text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(bool isDark, Color text) {
    final runsRemaining = adManager.agentUsesRemaining;
    final isPremium     = adManager.isPremium;

    return AppBar(
      backgroundColor:    isDark ? const Color(0xFF0A0A0A) : Colors.white,
      elevation:          0,
      surfaceTintColor:   Colors.transparent,
      leading: IconButton(
        icon: Icon(
          _showSidebar ? Iconsax.close_square : Iconsax.menu_1,
          color: text,
          size: 22,
        ),
        onPressed: () => setState(() => _showSidebar = !_showSidebar),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'APEX',
            style: TextStyle(
              fontSize:      17,
              fontWeight:    FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: [
        if (!isPremium)
          Container(
            margin:  const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: runsRemaining > 0
                  ? AppColors.success.withOpacity(0.12)
                  : AppColors.error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$runsRemaining left',
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color: runsRemaining > 0
                    ? AppColors.success
                    : AppColors.error,
              ),
            ),
          ),
        IconButton(
          icon:    Icon(Icons.add_rounded, color: text, size: 22),
          tooltip: 'New conversation',
          onPressed: _newChat,
        ),
        if (_workflowId != null)
          IconButton(
            icon: const Icon(
              Iconsax.flash,
              color: AppColors.primary,
              size: 18,
            ),
            tooltip: 'View Workflow',
            onPressed: () => context.push('/workflow/$_workflowId'),
          ),
      ],
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 260,
      color: isDark
          ? const Color(0xFF111111)
          : const Color(0xFFF8F8F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _newChat,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 18,
                      color: isDark
                          ? Colors.white70
                          : Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'New conversation',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white70
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: api.get('/agent/chat/sessions'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  );
                }

                final sessions =
                    snapshot.data?['sessions'] as List? ?? [];

                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session  = sessions[index];
                    final isActive = session['id'] == _sessionId;

                    return ListTile(
                      dense:    true,
                      selected: isActive,
                      selectedTileColor:
                          AppColors.primary.withOpacity(0.1),
                      leading: Icon(
                        Iconsax.message_text,
                        size: 18,
                        color: isActive
                            ? AppColors.primary
                            : (isDark
                                ? Colors.white54
                                : Colors.black54),
                      ),
                      title: Text(
                        session['title'] ?? 'Untitled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isDark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        _formatDate(session['updated_at']),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white38
                              : Colors.black38,
                        ),
                      ),
                      onTap: () {
                        setState(
                            () => _showSidebar = false);
                        _loadSession(session['id']);
                      },
                      trailing: isActive
                          ? Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildMessages(bool isDark) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      itemCount: _msgs.length,
      itemBuilder: (_, i) {
        final msg = _msgs[i];
        return switch (msg.role) {
          _Role.user     => _UserBubble(msg: msg),
          _Role.agent    => _AgentBubble(
              msg:        msg,
              isDark:     isDark,
              onWorkflow: _workflowId != null
                  ? () => context.push('/workflow/$_workflowId')
                  : null,
            ),
          _Role.thinking => _ThinkingBubble(msg: msg, isDark: isDark),
          _Role.tool     => _ToolLine(msg: msg, isDark: isDark),
          _Role.action   => _ActionLine(msg: msg),
          _Role.error    => _ErrorLine(msg: msg),
          _Role.system   => _SystemMsg(
              msg:       msg,
              isDark:    isDark,
              onUpgrade: () => context.push('/premium'),
              onWatchAd: () => adManager
                  .watchAdForAgentUse(context)
                  .then((ok) {
                if (ok && mounted) _submit();
              }),
            ),
        };
      },
    );
  }

  Widget _buildInput(bool isDark, Color text) {
    // FIX 3: Colors.black30/black24 don't exist — use withOpacity
    final hintColor = isDark
        ? Colors.white.withOpacity(0.3)
        : Colors.black.withOpacity(0.3);
    final disabledIconColor = isDark
        ? Colors.white.withOpacity(0.24)
        : Colors.black.withOpacity(0.24);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black12,
                  ),
                ),
                child: TextField(
                  controller:      _inputCtrl,
                  focusNode:       _inputFocus,
                  enabled:         _inputEnabled,
                  maxLines:        null,
                  minLines:        1,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: 15,
                    color:    text,
                    height:   1.45,
                  ),
                  decoration: InputDecoration(
                    hintText:       'What do you want us to work on?',
                    hintStyle:      TextStyle(
                      fontSize: 15,
                      color:    hintColor,
                    ),
                    border:         InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(
                        20, 14, 20, 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isStreaming ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _isStreaming
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.topLeft,
                          end:   Alignment.bottomRight,
                        ),
                  color: _isStreaming
                      ? (isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1))
                      : null,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: _isStreaming ? disabledIconColor : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
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
        margin:  const EdgeInsets.fromLTRB(80, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft:     Radius.circular(20),
            topRight:    Radius.circular(20),
            bottomLeft:  Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
            color:    Colors.white,
            fontSize: 15,
            height:   1.45,
          ),
        ),
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(
        begin: 0.08, curve: Curves.easeOut);
  }
}

class _AgentBubble extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final VoidCallback? onWorkflow;

  const _AgentBubble({
    required this.msg,
    required this.isDark,
    this.onWorkflow,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    // FIX 4: Colors.black38/white38 don't exist — use withOpacity
    final subColor = isDark
        ? Colors.white.withOpacity(0.38)
        : Colors.black.withOpacity(0.38);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 80, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'APEX',
                  style: TextStyle(
                    fontSize:      12,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                if (msg.modelTier != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: msg.modelTier == 'premium'
                          ? Colors.amber.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      msg.modelTier!.toUpperCase(),
                      style: TextStyle(
                        fontSize:   9,
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
          _MdText(text: msg.text, isDark: isDark),
          const SizedBox(height: 10),
          Row(
            children: [
              _IconBtn(
                icon:  Icons.copy_outlined,
                color: subColor,
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: msg.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:  Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (onWorkflow != null) ...[
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: onWorkflow,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Iconsax.flash,
                          size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'View Workflow',
                        style: TextStyle(
                          fontSize:   12,
                          color:      AppColors.primary,
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
    ).animate().fadeIn(duration: 280.ms).slideY(
        begin: 0.05, curve: Curves.easeOut);
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
    _ctrl = AnimationController(vsync: this, duration: 1200.ms)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX 5: Colors.black38/white38 don't exist — use withOpacity
    final sub = widget.isDark
        ? Colors.white.withOpacity(0.38)
        : Colors.black.withOpacity(0.38);
    final empty =
        widget.msg.text.isEmpty || widget.msg.isCollapsed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 80, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 12,
            ),
          ),
          const SizedBox(width: 12),
          if (!empty)
            Expanded(
              child: Text(
                widget.msg.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize:   13,
                  color:      sub,
                  fontStyle:  FontStyle.italic,
                  height:     1.4,
                ),
              ),
            ),
          if (!empty) const SizedBox(width: 8),
          _Dots(controller: _ctrl),
        ],
      ),
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

    final color = _categoryColor(msg.toolCategory);
    final icon  = _categoryIcon(msg.toolCategory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(50, 2, 80, 2),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 12,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$icon ${msg.text}',
            style: TextStyle(
              fontSize: 12,
              color:    color.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width:  10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color:       color.withOpacity(0.5),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Color _categoryColor(String? cat) => switch (cat) {
        'research' => AppColors.info,
        'action'   => AppColors.success,
        'document' => Colors.amber,
        'thinking' => AppColors.primary,
        _          => AppColors.primary,
      };

  String _categoryIcon(String? cat) => switch (cat) {
        'research' => '🔍',
        'action'   => '⚡',
        'document' => '📄',
        'thinking' => '💭',
        _          => '●',
      };
}

class _ActionLine extends StatelessWidget {
  final _Msg msg;
  const _ActionLine({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(50, 2, 80, 2),
      child: Text(
        msg.text,
        style: const TextStyle(
          fontSize:   12,
          color:      AppColors.success,
          fontWeight: FontWeight.w500,
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 80, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:        AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
              color: AppColors.error.withOpacity(0.2)),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
            fontSize: 14,
            color:    AppColors.error,
            height:   1.4,
          ),
        ),
      ),
    ).animate().fadeIn();
  }
}

class _SystemMsg extends StatelessWidget {
  final _Msg         msg;
  final bool         isDark;
  final VoidCallback onUpgrade;
  final VoidCallback onWatchAd;

  const _SystemMsg({
    required this.msg,
    required this.isDark,
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
              ? const Color(0xFF1A1A1A)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          // FIX 6: Colors.black12 → withOpacity(0.12)
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MdText(text: msg.text, isDark: isDark),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onWatchAd,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12),
                    ),
                    child: const Text(
                      'Watch Ad',
                      style: TextStyle(
                        color:      AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize:   13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                        color:      Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize:   13,
                      ),
                    ),
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
// Helper widgets
// ─────────────────────────────────────────────────────────────────

class _MdText extends StatelessWidget {
  final String text;
  final bool   isDark;
  const _MdText({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base  = isDark ? Colors.white : Colors.black87;
    // FIX 7: Colors.black60/white60 don't exist — use withOpacity
    final muted = isDark
        ? Colors.white.withOpacity(0.6)
        : Colors.black.withOpacity(0.6);

    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (int li = 0; li < lines.length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[li];

      if (line.startsWith('> ')) {
        spans.add(TextSpan(
          text: '  ${line.substring(2)}',
          style: TextStyle(
            color:      muted,
            fontSize:   13,
            height:     1.5,
            fontStyle:  FontStyle.italic,
          ),
        ));
        continue;
      }

      final re   = RegExp(r'\*\*(.*?)\*\*|_(.*?)_|`(.*?)`');
      int   last = 0;

      for (final m in re.allMatches(line)) {
        if (m.start > last) {
          spans.add(TextSpan(
            text:  line.substring(last, m.start),
            style: TextStyle(
              color: base, fontSize: 15, height: 1.5),
          ));
        }

        if (m.group(1) != null) {
          spans.add(TextSpan(
            text:  m.group(1),
            style: TextStyle(
              color:      base,
              fontSize:   15,
              height:     1.5,
              fontWeight: FontWeight.w700,
            ),
          ));
        } else if (m.group(2) != null) {
          spans.add(TextSpan(
            text:  m.group(2),
            style: TextStyle(
              color:     muted,
              fontSize:  14,
              height:    1.5,
              fontStyle: FontStyle.italic,
            ),
          ));
        } else if (m.group(3) != null) {
          spans.add(TextSpan(
            text:  m.group(3),
            style: TextStyle(
              color:           AppColors.accent,
              fontSize:        13,
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
          style: TextStyle(
            color: base, fontSize: 15, height: 1.5),
        ));
      }
    }

    return SelectableText.rich(TextSpan(children: spans));
  }
}

class _Dots extends StatelessWidget {
  final AnimationController controller;
  const _Dots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (controller.value + i / 3.0) % 1.0;
          final op    = 0.2 +
              0.8 *
                  (phase < 0.5
                      ? phase * 2
                      : (1 - phase) * 2);
          return Container(
            margin: const EdgeInsets.only(right: 3),
            width:  5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(op),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap:  onTap,
        child: Icon(icon, size: 18, color: color),
      );
}

class _LimitSheet extends StatelessWidget {
  final bool         isDark;
  final VoidCallback onWatchAd;

  const _LimitSheet({
    required this.isDark,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    // FIX 8: Colors.white24/black12 don't exist — use withOpacity
    final handleColor = isDark
        ? Colors.white.withOpacity(0.24)
        : Colors.black.withOpacity(0.12);
    // FIX 9: Colors.black60/white60 don't exist — use withOpacity
    final subColor = isDark
        ? Colors.white.withOpacity(0.6)
        : Colors.black.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  36,
            height: 4,
            decoration: BoxDecoration(
              color:        handleColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Iconsax.lock_1,
              size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Daily limit reached',
            style: TextStyle(
              fontSize:   18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ve used all your free runs today.\n'
            'Watch an ad for 1 more, or upgrade to Premium '
            'for unlimited access.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height:   1.5,
              color:    subColor,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onWatchAd,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                  ),
                  child: const Text(
                    'Watch Ad',
                    style: TextStyle(
                      color:      AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize:   14,
                    ),
                  ),
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
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                  ),
                  child: const Text(
                    'Upgrade',
                    style: TextStyle(
                      color:      Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize:   14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
