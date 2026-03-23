// frontend/lib/screens/agent/agent_screen.dart
//
// APEX Agent Screen — v4
// • Dynamic currency (reads from user profile — no hardcoded $ or NGN)
// • Live streaming progress (SSE: thinking → tool_call → tool_result → complete)
// • All APEX features surfaced: find jobs, find partners, scan opportunities,
//   generate contracts/invoices/proposals, social posting
// • Documents tab shows generated contracts, invoices, proposals
// • Opportunities tab shows real job/partner leads found by the agent
// • Outreach tab shows ready-to-send cold messages

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

// ─────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────

class _Msg {
  final String text;
  final bool   isAgent;
  final bool   isTool;
  final String? toolName;
  final String? toolCategory;
  _Msg({required this.text, required this.isAgent,
        this.isTool = false, this.toolName, this.toolCategory});
}

class _StreamEvent {
  final String type;    // thinking | tool_call | tool_result | action_done | finalizing | complete | error
  final Map    data;
  _StreamEvent(this.type, this.data);
}

// ─────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────

class AgentScreen extends ConsumerStatefulWidget {
  final String? workflowId;
  const AgentScreen({super.key, this.workflowId});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

enum _Phase { idle, streaming, result }

class _AgentScreenState extends ConsumerState<AgentScreen>
    with SingleTickerProviderStateMixin {

  _Phase _phase = _Phase.idle;
  late TabController _resultTab;

  final _taskCtrl   = TextEditingController();
  final _chatCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();

  double _budget = 0;
  double _hours  = 0.5;
  bool   _allowEmail  = false;
  bool   _allowSocial = false;

  Map<String, dynamic> _agentResult = {};
  String? _workflowId;
  String? _sessionId;
  String  _error = '';

  final List<_Msg>    _chatMsgs     = [];
  List<_StreamEvent>  _streamEvents = [];
  bool _chatLoading = false;
  int  _streamIteration = 0;
  String _streamStatus  = '';

  static const _quickTasks = [
    ('▶️', 'Start a YouTube channel',       'I want to start earning on YouTube in 2 months with zero budget'),
    ('💻', 'Freelance on Upwork/Fiverr',    'I want to get my first freelance client this week'),
    ('📱', 'Sell on social media',           'I want to start selling products via WhatsApp and Instagram'),
    ('✍️', 'Content writing',               'I want to earn from writing articles and blog posts'),
    ('🛍️', 'eCommerce / dropshipping',      'I want to start an online store with no upfront stock'),
    ('🤝', 'Find a business partner',        'I want to find a partner to collaborate and build a business'),
    ('📋', 'Land a contract',               'I want to find clients and land my first paid contract'),
    ('🎨', 'Design & creative services',    'I want to earn from graphic design and creative services'),
  ];

  @override
  void initState() {
    super.initState();
    _resultTab  = TabController(length: 5, vsync: this);
    _workflowId = widget.workflowId;
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    _resultTab.dispose();
    super.dispose();
  }

  // ── Currency helper ──────────────────────────────────
  String get _currencyCode {
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final code    = profile['currency']?.toString() ?? 'USD';
    currency.init(code);
    return code;
  }

  // ── Run agent with streaming ─────────────────────────
  Future<void> _runAgent() async {
    final task = _taskCtrl.text.trim();
    if (task.length < 10) {
      setState(() => _error = 'Please describe your goal in more detail');
      return;
    }
    if (!adManager.canUseAgent) { _showLimitDialog(); return; }
    adManager.recordAgentUse();

    setState(() {
      _phase          = _Phase.streaming;
      _error          = '';
      _streamEvents   = [];
      _streamIteration = 0;
      _streamStatus   = 'Starting APEX Agent...';
    });

    try {
      // Use streaming endpoint
      final stream = api.streamPost('/agent/run-stream', {
        'task':              task,
        'budget':            _budget,
        'hours_per_day':     _hours,
        'currency':          _currencyCode,
        'allow_email':       _allowEmail,
        'allow_social_post': _allowSocial,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });

      await for (final event in stream) {
        if (!mounted) break;
        _handleStreamEvent(event);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Agent failed. Please try again.';
          _phase = _Phase.idle;
        });
      }
    }
  }

  void _handleStreamEvent(_StreamEvent event) {
    setState(() {
      _streamEvents.add(event);
      switch (event.type) {
        case 'thinking':
          _streamIteration = event.data['iteration'] as int? ?? _streamIteration;
          _streamStatus    = 'Thinking... (step $_streamIteration)';
          break;
        case 'tool_call':
          final tool = event.data['tool']?.toString() ?? '';
          _streamStatus = '${_toolEmoji(tool)} ${_toolLabel(tool)}...';
          break;
        case 'tool_result':
          _streamStatus = '✅ Got results from ${event.data['tool']}';
          break;
        case 'action_done':
          _streamStatus = '📤 Action completed: ${event.data['tool']}';
          break;
        case 'finalizing':
          _streamStatus = '📝 Writing your complete plan...';
          break;
        case 'complete':
          _agentResult = Map<String, dynamic>.from(event.data);
          _workflowId  = event.data['workflow_id']?.toString();
          _phase       = _Phase.result;
          final intro  = event.data['agent_response']?.toString() ?? '';
          if (intro.isNotEmpty) {
            _chatMsgs.add(_Msg(text: intro, isAgent: true));
          }
          break;
        case 'error':
          _error = event.data['message']?.toString() ?? 'Agent error';
          _phase = _Phase.idle;
          break;
      }
    });
  }

  // ── Chat ─────────────────────────────────────────────
  Future<void> _sendChat() async {
    final msg = _chatCtrl.text.trim();
    if (msg.isEmpty || _chatLoading) return;
    _chatCtrl.clear();
    setState(() {
      _chatMsgs.add(_Msg(text: msg, isAgent: false));
      _chatLoading = true;
    });
    _scrollDown();
    try {
      final r = await api.post('/agent/chat', {
        'message':    msg,
        if (_sessionId  != null) 'session_id':  _sessionId,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      setState(() {
        _sessionId = r['session_id']?.toString();
        _chatMsgs.add(_Msg(text: r['content']?.toString() ?? '...', isAgent: true));
        _chatLoading = false;
      });
      _scrollDown();
    } catch (_) {
      setState(() {
        _chatMsgs.add(_Msg(text: 'Connection issue. Try again.', isAgent: true));
        _chatLoading = false;
      });
    }
  }

  // ── Run a specific tool directly ─────────────────────
  Future<void> _runTool(String tool, Map<String, dynamic> input) async {
    setState(() => _chatLoading = true);
    try {
      final r   = await api.post('/agent/execute-tool', {
        'tool': tool, 'input': input,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      final out = r['output'] as Map? ?? {};
      // Pull out document if this was a doc tool
      final txt = out['document']?.toString()
          ?? out['content']?.toString()
          ?? out['template']?.toString()
          ?? out['result']?.toString()
          ?? jsonEncode(out);
      setState(() {
        _chatMsgs.add(_Msg(
          text: txt, isAgent: true, isTool: true,
          toolName: tool, toolCategory: _toolCategory(tool),
        ));
        _chatLoading = false;
      });
      _scrollDown();
    } catch (_) {
      setState(() => _chatLoading = false);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔒', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text('Daily Limit Reached',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            '3 runs per day on free plan.\nWatch an ad for 1 more run, or go Premium for 25 runs/day.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: _OutlineBtn(
                label: 'Watch Ad',
                onTap: () {
                  Navigator.pop(context);
                  adManager.watchAdForAgentUse(context).then((ok) {
                    if (ok && mounted) _runAgent();
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GradientBtn(
                label: 'Go Premium',
                onTap: () { Navigator.pop(context); context.push('/premium'); },
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? Colors.black : Colors.white;
    final card    = isDark ? AppColors.bgCard : Colors.white;
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text    = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;
    final profile = ref.watch(profileProvider).valueOrNull ?? {};
    final currCode = profile['currency']?.toString() ?? 'USD';
    currency.init(currCode);

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, text, border, card),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_phase) {
          _Phase.streaming => _buildStreaming(isDark, text, sub),
          _Phase.result    => _buildResult(isDark, text, sub, card, border),
          _Phase.idle      => _buildIdle(isDark, text, sub, card, border),
        },
      ),
    );
  }

  AppBar _buildAppBar(bool isDark, Color text, Color border, Color card) {
    return AppBar(
      backgroundColor: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: text),
        onPressed: () {
          if (_phase != _Phase.idle) {
            setState(() {
              _phase = _Phase.idle;
              _taskCtrl.clear();
              _agentResult = {};
              _chatMsgs.clear();
              _streamEvents.clear();
            });
          } else {
            context.pop();
          }
        },
      ),
      title: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Text('APEX Agent',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
      ]),
      actions: [
        if (!adManager.isPremium)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: adManager.agentUsesRemaining > 0
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${adManager.agentUsesRemaining}/3 runs',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: adManager.agentUsesRemaining > 0
                            ? AppColors.success : AppColors.error)),
              ),
            ),
          ),
        if (_workflowId != null)
          TextButton.icon(
            onPressed: () => context.push('/workflow/$_workflowId'),
            icon: const Icon(Iconsax.flash, size: 14, color: AppColors.primary),
            label: const Text('Workflow',
                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border)),
    );
  }

  // ─────────────────────────────────────────────────────
  // IDLE VIEW
  // ─────────────────────────────────────────────────────

  Widget _buildIdle(bool isDark, Color text, Color sub, Color card, Color border) {
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Hero card ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : const Color(0xFFF8F8FF),
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(child: Text('What do you want to earn from?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
            ]),
            const SizedBox(height: 8),
            Text(
              'Describe ANY income goal. APEX researches, plans, executes — '
              'finds jobs, sends outreach, builds documents, posts social media. '
              'This is a real AI worker, not a chatbot.',
              style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
          ]),
        ).animate().fadeIn(),
        const SizedBox(height: 16),

        // ── Task input ─────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: TextField(
            controller: _taskCtrl,
            maxLines: 4,
            style: TextStyle(fontSize: 14, color: text),
            decoration: InputDecoration(
              hintText: 'e.g. "I want to start earning on YouTube in 2 months with zero budget"',
              hintStyle: TextStyle(color: sub, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ).animate().fadeIn(delay: 100.ms),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],
        const SizedBox(height: 16),

        // ── Budget + Hours ─────────────────────────────
        Row(children: [
          Expanded(child: _SliderCard(
            label: 'Budget',
            value: currency.budgetLabel(_budget),
            min: 0, max: 500, current: _budget,
            onChanged: (v) => setState(() => _budget = v),
            isDark: isDark,
          )),
          const SizedBox(width: 12),
          Expanded(child: _SliderCard(
            label: 'Daily time',
            value: '${_hours.toStringAsFixed(1)}h',
            min: 0.5, max: 8, current: _hours,
            onChanged: (v) => setState(() => _hours = v),
            isDark: isDark,
          )),
        ]).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: 12),

        // ── Currency badge (dynamic) ───────────────────
        GestureDetector(
          onTap: _showCurrencyInfo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Iconsax.dollar_circle, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('${currency.code} — ${CurrencyService.nameFor(currency.code)}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline_rounded, size: 12, color: AppColors.primary),
            ]),
          ),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 12),

        // ── Permission toggles ─────────────────────────
        _PermissionRow(
          label: 'Allow APEX to send emails on your behalf',
          value: _allowEmail,
          onChanged: (v) => setState(() => _allowEmail = v),
          isDark: isDark,
        ).animate().fadeIn(delay: 220.ms),
        const SizedBox(height: 8),
        _PermissionRow(
          label: 'Allow APEX to post to social media',
          value: _allowSocial,
          onChanged: (v) => setState(() => _allowSocial = v),
          isDark: isDark,
        ).animate().fadeIn(delay: 240.ms),
        const SizedBox(height: 20),

        // ── Run button ─────────────────────────────────
        _GradientBtn(
          label: '✦  Run APEX Agent',
          onTap: _runAgent,
          fontSize: 15,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ).animate().fadeIn(delay: 260.ms),
        const SizedBox(height: 28),

        // ── Quick start ────────────────────────────────
        Text('Quick Start', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text))
            .animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 12),
        ..._quickTasks.asMap().entries.map((e) {
          final t = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _taskCtrl.text = t.$3);
                HapticFeedback.lightImpact();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.bgCard : Colors.grey.shade50,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: border),
                ),
                child: Row(children: [
                  Text(t.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                    Text(t.$3, style: TextStyle(fontSize: 11, color: sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: sub),
                ]),
              ),
            ).animate(delay: (300 + e.key * 40).ms).fadeIn().slideY(begin: 0.05),
          );
        }),

        // ── Direct APEX actions ────────────────────────
        const SizedBox(height: 28),
        Text('Direct APEX Actions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text))
            .animate().fadeIn(delay: 600.ms),
        const SizedBox(height: 4),
        Text('Run a specific task without a full agent run',
            style: TextStyle(fontSize: 12, color: sub))
            .animate().fadeIn(delay: 620.ms),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ActionChip(label: '🔍 Find Jobs',       onTap: () => _showFindJobsSheet()),
          _ActionChip(label: '🤝 Find Partners',   onTap: () => _showFindPartnersSheet()),
          _ActionChip(label: '🌐 Scan Opps',       onTap: () => _runQuickScan()),
          _ActionChip(label: '📋 Contract',        onTap: () => _showDocSheet('generate_contract')),
          _ActionChip(label: '🧾 Invoice',         onTap: () => _showDocSheet('generate_invoice')),
          _ActionChip(label: '📄 Proposal',        onTap: () => _showDocSheet('generate_proposal')),
          _ActionChip(label: '✉️ Cold Email',      onTap: () => _showColdEmailSheet()),
          _ActionChip(label: '👤 Build Profile',   onTap: () => _showProfileSheet()),
        ]).animate().fadeIn(delay: 640.ms),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────
  // STREAMING VIEW
  // ─────────────────────────────────────────────────────

  Widget _buildStreaming(bool isDark, Color text, Color sub) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
          ).animate().scale().then().shimmer(duration: 2.seconds),
          const SizedBox(height: 24),
          Text('APEX is working...', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 6),
          Text(_streamStatus, style: const TextStyle(
              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 28),

          // Live event feed
          Expanded(
            child: ListView.builder(
              itemCount: _streamEvents.length,
              itemBuilder: (_, i) {
                final e = _streamEvents[i];
                return _StreamEventTile(event: e, isDark: isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // RESULT VIEW
  // ─────────────────────────────────────────────────────

  Widget _buildResult(bool isDark, Color text, Color sub, Color card, Color border) {
    final r     = _agentResult;
    final plan  = r['plan']  as Map? ?? {};
    final steps = r['steps'] as List? ?? [];
    final opps  = r['opportunities_found']  as List? ?? [];
    final docs  = r['documents_generated']  as List? ?? [];
    final msgs  = r['outreach_messages']    as List? ?? [];
    final posts = r['social_posts']         as List? ?? [];

    // Count non-empty extra sections for tab badge
    final hasOpps  = opps.isNotEmpty;
    final hasDocs  = docs.isNotEmpty;
    final hasMsgs  = msgs.isNotEmpty;
    final hasPosts = posts.isNotEmpty;

    return Column(children: [
      // ── Summary bar ──────────────────────────────────
      Container(
        color: card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan['title']?.toString() ?? 'Your Plan',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
              const SizedBox(height: 2),
              Row(children: [
                _ResultChip(
                  '${plan['viability'] ?? 75}% viable',
                  AppColors.success,
                ),
                const SizedBox(width: 6),
                _ResultChip(
                  currency.range(
                    (plan['income_range']?['min'] ?? 0).toDouble(),
                    (plan['income_range']?['max'] ?? 0).toDouble(),
                    currency: plan['income_range']?['currency'] ?? currency.code,
                  ),
                  AppColors.gold,
                ),
                const SizedBox(width: 6),
                _ResultChip(plan['timeline']?.toString() ?? '', AppColors.primary),
              ]),
            ])),
            if (_workflowId != null)
              GestureDetector(
                onTap: () => context.push('/workflow/$_workflowId'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: AppRadius.md,
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Iconsax.flash, size: 12, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text('View Workflow', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          TabBar(
            controller: _resultTab,
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: sub,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: 'Plan'),
              Tab(text: hasOpps  ? 'Jobs ${opps.length}' : 'Chat'),
              Tab(text: hasDocs  ? 'Docs ${docs.length}' : 'Docs'),
              Tab(text: hasMsgs  ? 'Outreach ${msgs.length}' : 'Outreach'),
              Tab(text: hasPosts ? 'Posts ${posts.length}' : 'Posts'),
            ],
          ),
        ]),
      ),

      Expanded(
        child: TabBarView(
          controller: _resultTab,
          children: [
            // ── Tab 0: Plan + Steps ───────────────────
            _PlanTab(
              result:     r,
              steps:      steps,
              chatMsgs:   _chatMsgs,
              chatCtrl:   _chatCtrl,
              scrollCtrl: _scrollCtrl,
              chatLoading: _chatLoading,
              isDark:     isDark,
              text:       text, sub: sub, card: card, border: border,
              onSend:     _sendChat,
              onRunTool:  _runTool,
              currency:   currency,
            ),
            // ── Tab 1: Opportunities / Jobs ───────────
            _OpportunitiesTab(
              opps: opps, isDark: isDark, text: text, sub: sub, card: card, border: border,
              onScanMore: _runQuickScan,
              onFindJobs: _showFindJobsSheet,
            ),
            // ── Tab 2: Generated Documents ────────────
            _DocumentsTab(
              docs: docs, isDark: isDark, text: text, sub: sub, card: card,
              onGenerate: _showDocSheet,
            ),
            // ── Tab 3: Outreach Messages ──────────────
            _OutreachTab(
              msgs: msgs, isDark: isDark, text: text, sub: sub, card: card,
              onGenerate: _showColdEmailSheet,
            ),
            // ── Tab 4: Social Posts ───────────────────
            _SocialTab(
              posts: posts, isDark: isDark, text: text, sub: sub, card: card,
            ),
          ],
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────
  // QUICK ACTION SHEETS
  // ─────────────────────────────────────────────────────

  void _showCurrencyInfo() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _CurrencyInfoSheet(code: currency.code),
      backgroundColor: Colors.transparent,
    );
  }

  void _showFindJobsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.read(profileProvider).valueOrNull ?? {};
    final skills  = (profile['current_skills'] as List? ?? []).join(', ');
    final ctrl    = TextEditingController(text: skills);

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionSheet(
        title: '🔍 Find Freelance Jobs',
        subtitle: 'APEX will search real job boards for your skills',
        field: TextField(controller: ctrl,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Your skills (e.g. copywriting, design)',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          )),
        onRun: () {
          Navigator.pop(context);
          _runTool('find_freelance_jobs', {'skill': ctrl.text.trim()});
        },
        isDark: isDark,
      ),
    );
  }

  void _showFindPartnersSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl   = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionSheet(
        title: '🤝 Find Partners & Collaborators',
        subtitle: 'APEX searches for potential business partners in your niche',
        field: TextField(controller: ctrl,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Your niche (e.g. content creation, web dev)',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          )),
        onRun: () {
          Navigator.pop(context);
          _runTool('find_partners', {'niche': ctrl.text.trim()});
        },
        isDark: isDark,
      ),
    );
  }

  Future<void> _runQuickScan() async {
    setState(() => _chatLoading = true);
    try {
      final r = await api.post('/agent/scan', {'force_refresh': false});
      final opps = r['opportunities'] as List? ?? [];
      final txt  = opps.isEmpty
          ? 'No new opportunities found right now. Try again tomorrow.'
          : 'Found ${opps.length} opportunities:\n\n' +
            opps.take(5).map((o) =>
              '• ${o['title']}\n  ${o['url'] ?? ''}\n  ${o['snippet'] ?? ''}'
            ).join('\n\n');
      setState(() {
        _chatMsgs.add(_Msg(text: txt, isAgent: true, isTool: true, toolName: 'scan_opportunities'));
        _chatLoading = false;
      });
      _scrollDown();
      if (_phase == _Phase.idle) {
        setState(() => _phase = _Phase.result);
        _agentResult = {'agent_response': txt, 'opportunities_found': opps,
                        'plan': {}, 'steps': []};
      }
    } catch (_) {
      setState(() => _chatLoading = false);
    }
  }

  void _showDocSheet(String tool) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titles = {
      'generate_contract': ('📋 Generate Contract', 'client name, project title, amount'),
      'generate_invoice':  ('🧾 Generate Invoice',  'client name, item description, amount'),
      'generate_proposal': ('📄 Generate Proposal', 'business name, problem, solution'),
    };
    final (title, hint) = titles[tool] ?? ('Generate Document', 'details');
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionSheet(
        title: title, subtitle: 'APEX generates a complete, ready-to-send document',
        field: TextField(controller: ctrl, maxLines: 3,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          )),
        onRun: () {
          Navigator.pop(context);
          // Parse user's free-text input through AI via quick endpoint
          api.post('/agent/quick', {
            'task':        'Generate $tool: ${ctrl.text.trim()}. Currency: ${currency.code}',
            'output_type': 'document',
          }).then((r) {
            setState(() {
              _chatMsgs.add(_Msg(
                text: r['output']?.toString() ?? 'Done', isAgent: true,
                isTool: true, toolName: tool, toolCategory: 'document'));
            });
            if (_phase != _Phase.result) setState(() => _phase = _Phase.result);
            _scrollDown();
          });
        },
        isDark: isDark,
      ),
    );
  }

  void _showColdEmailSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl   = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionSheet(
        title: '✉️ Write Cold Outreach',
        subtitle: 'APEX writes a personalized message to land clients or partners',
        field: TextField(controller: ctrl, maxLines: 3,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Who are you contacting and for what? e.g. "Lagos tech startup for web dev services"',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          )),
        onRun: () {
          Navigator.pop(context);
          _runTool('write_cold_outreach', {'target': ctrl.text.trim(), 'currency': currency.code});
        },
        isDark: isDark,
      ),
    );
  }

  void _showProfileSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl   = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionSheet(
        title: '👤 Build Platform Profile',
        subtitle: 'APEX writes an optimised bio for Fiverr, LinkedIn, Upwork, etc.',
        field: TextField(controller: ctrl,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Platform + skill (e.g. "Fiverr copywriting")',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          )),
        onRun: () {
          Navigator.pop(context);
          _runTool('build_profile_content', {'platform_and_skill': ctrl.text.trim()});
        },
        isDark: isDark,
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────

  String _toolEmoji(String tool) {
    const map = {
      'web_search':           '🌐',
      'deep_research':        '🔬',
      'find_freelance_jobs':  '💼',
      'find_partners':        '🤝',
      'find_free_resources':  '🆓',
      'market_research':      '📊',
      'scan_opportunities':   '🔍',
      'write_content':        '✍️',
      'create_plan':          '📅',
      'estimate_income':      '💰',
      'generate_ideas':       '💡',
      'write_cold_outreach':  '✉️',
      'build_profile_content':'👤',
      'send_email':           '📤',
      'post_twitter':         '🐦',
      'post_linkedin':        '💼',
      'schedule_post':        '⏰',
      'generate_contract':    '📋',
      'generate_invoice':     '🧾',
      'generate_proposal':    '📄',
      'generate_pitch_deck':  '🎯',
    };
    return map[tool] ?? '🔧';
  }

  String _toolLabel(String tool) {
    final map = {
      'web_search':           'Searching the web',
      'deep_research':        'Deep researching topic',
      'find_freelance_jobs':  'Finding freelance jobs',
      'find_partners':        'Finding business partners',
      'find_free_resources':  'Finding free tools',
      'market_research':      'Analysing market',
      'scan_opportunities':   'Scanning opportunities',
      'write_content':        'Writing content',
      'create_plan':          'Building execution plan',
      'estimate_income':      'Estimating income potential',
      'generate_ideas':       'Generating ideas',
      'write_cold_outreach':  'Writing outreach messages',
      'build_profile_content':'Building platform profile',
      'send_email':           'Sending email',
      'post_twitter':         'Posting to Twitter/X',
      'post_linkedin':        'Posting to LinkedIn',
      'generate_contract':    'Generating contract',
      'generate_invoice':     'Generating invoice',
      'generate_proposal':    'Generating proposal',
    };
    return map[tool] ?? 'Running tool';
  }

  String _toolCategory(String tool) {
    return TOOLS_CATEGORY[tool] ?? 'thinking';
  }

  static const TOOLS_CATEGORY = {
    'web_search': 'research',      'deep_research': 'research',
    'find_freelance_jobs': 'research', 'find_partners': 'research',
    'scan_opportunities': 'research', 'market_research': 'research',
    'send_email': 'action',        'post_twitter': 'action',
    'post_linkedin': 'action',     'schedule_post': 'action',
    'generate_contract': 'document', 'generate_invoice': 'document',
    'generate_proposal': 'document', 'generate_pitch_deck': 'document',
  };
}

// ─────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _StreamEventTile extends StatelessWidget {
  final _StreamEvent event;
  final bool isDark;
  const _StreamEventTile({required this.event, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (event.type) {
      'thinking'    => ('🧠', AppColors.primary,  'Thinking: ${event.data['thought']?.toString().substring(0, _min(event.data['thought']?.toString().length ?? 0, 80)) ?? ''}...'),
      'tool_call'   => ('🔧', AppColors.warning,   'Using: ${event.data['tool']}'),
      'tool_result' => ('✅', AppColors.success,   'Got results'),
      'action_done' => ('📤', AppColors.accent,    'Action done: ${event.data['tool']}'),
      'finalizing'  => ('📝', AppColors.gold,      'Writing final plan...'),
      _             => ('ℹ️', AppColors.info,      event.type),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54))),
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ]),
    ).animate().fadeIn().slideY(begin: 0.2);
  }

  int _min(int a, int b) => a < b ? a : b;
}

class _PlanTab extends StatelessWidget {
  final Map result;
  final List steps;
  final List<_Msg> chatMsgs;
  final TextEditingController chatCtrl;
  final ScrollController scrollCtrl;
  final bool chatLoading;
  final bool isDark;
  final Color text, sub, card, border;
  final VoidCallback onSend;
  final Function(String, Map<String, dynamic>) onRunTool;
  final CurrencyService currency;

  const _PlanTab({
    required this.result, required this.steps, required this.chatMsgs,
    required this.chatCtrl, required this.scrollCtrl, required this.chatLoading,
    required this.isDark, required this.text, required this.sub,
    required this.card, required this.border, required this.onSend,
    required this.onRunTool, required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final freeTools = result['free_tools'] as List? ?? [];
    final warning   = result['plan']?['warning']?.toString() ?? '';
    final immediate = result['immediate_action']?.toString() ?? '';
    final insight   = result['wealth_insight']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Immediate action
        if (immediate.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.12), AppColors.accent.withOpacity(0.05)]),
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text('Do NOW: $immediate',
                  style: TextStyle(fontSize: 12, color: text, fontWeight: FontWeight.w600))),
            ]),
          ),

        // Steps
        ...steps.asMap().entries.map((e) {
          final s      = e.value as Map;
          final isAuto = s['type']?.toString() == 'automated';
          return _StepCard(step: s, index: e.key, isDark: isDark, text: text, sub: sub,
              isAuto: isAuto, onRunTool: onRunTool, currency: currency);
        }),

        // Free tools
        if (freeTools.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Free Tools', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          ...freeTools.map((t) => _ToolRow(tool: t as Map, isDark: isDark, text: text, sub: sub)),
        ],

        // Warning
        if (warning.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Text('⚠️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(warning, style: TextStyle(fontSize: 12, color: text))),
            ]),
          ),
        ],

        // Wealth insight
        if (insight.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.06),
              borderRadius: AppRadius.md,
            ),
            child: Row(children: [
              const Text('💡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(insight, style: TextStyle(fontSize: 12, color: sub))),
            ]),
          ),
        ],

        // Chat
        const SizedBox(height: 20),
        Text('Ask APEX Follow-ups', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        ...chatMsgs.map((m) => _ChatBubble(msg: m, isDark: isDark)),
        if (chatLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: isDark ? AppColors.bgCard : Colors.grey.shade100,
                    borderRadius: AppRadius.md),
                child: const Row(children: [
                  SizedBox(width: 40, height: 12,
                      child: LinearProgressIndicator(backgroundColor: Colors.transparent,
                          color: AppColors.primary)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: chatCtrl,
            style: TextStyle(fontSize: 13, color: text),
            decoration: InputDecoration(
              hintText: 'Ask a follow-up or say "write my first email"',
              hintStyle: TextStyle(color: sub, fontSize: 12),
              filled: true,
              fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: AppRadius.md),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final Map step;
  final int index;
  final bool isDark, isAuto;
  final Color text, sub;
  final Function(String, Map<String, dynamic>) onRunTool;
  final CurrencyService currency;
  const _StepCard({required this.step, required this.index, required this.isDark,
      required this.isAuto, required this.text, required this.sub,
      required this.onRunTool, required this.currency});

  @override
  Widget build(BuildContext context) {
    final output = step['ai_output']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.grey.shade50,
        borderRadius: AppRadius.md,
        border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: isAuto
                  ? [AppColors.accent, AppColors.primary]
                  : [AppColors.bgSurface, AppColors.bgSurface]),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: Text('${step['order'] ?? index + 1}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: Colors.white))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(step['title']?.toString() ?? '',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text))),
          if (isAuto)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: AppRadius.pill,
              ),
              child: const Text('AI', style: TextStyle(fontSize: 9, color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(step['description']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
        if (output.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: AppRadius.sm,
            ),
            child: Text(output,
                maxLines: 4, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: text, height: 1.4)),
          ),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: output)),
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Copy', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final Map tool;
  final bool isDark;
  final Color text, sub;
  const _ToolRow({required this.tool, required this.isDark, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Icon(Iconsax.global, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tool['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text)),
          Text(tool['purpose']?.toString() ?? '', style: TextStyle(fontSize: 11, color: sub)),
        ])),
        if (tool['url']?.toString().isNotEmpty == true)
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: tool['url'] as String)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: AppRadius.pill,
              ),
              child: const Text('Copy URL', style: TextStyle(fontSize: 10, color: AppColors.primary)),
            ),
          ),
      ]),
    );
  }
}

class _OpportunitiesTab extends StatelessWidget {
  final List opps;
  final bool isDark;
  final Color text, sub, card, border;
  final VoidCallback onScanMore, onFindJobs;
  const _OpportunitiesTab({required this.opps, required this.isDark,
      required this.text, required this.sub, required this.card,
      required this.border, required this.onScanMore, required this.onFindJobs});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: _OutlineBtn(label: '🔄 Scan Again', onTap: onScanMore)),
          const SizedBox(width: 8),
          Expanded(child: _OutlineBtn(label: '💼 Find Jobs', onTap: onFindJobs)),
        ]),
        const SizedBox(height: 16),
        if (opps.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const Text('🔍', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text('No opportunities yet', style: TextStyle(color: sub, fontSize: 14)),
              const SizedBox(height: 6),
              Text('Run a full agent task to discover real leads', style: TextStyle(color: sub, fontSize: 12)),
            ]),
          ))
        else
          ...opps.map((o) {
            final opp = o as Map;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade50,
                borderRadius: AppRadius.md,
                border: Border.all(color: border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(opp['title']?.toString() ?? '',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text))),
                  if ((opp['fit_score'] as num? ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text('${opp['fit_score']}% fit',
                          style: const TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                    ),
                ]),
                if ((opp['snippet'] ?? opp['why'])?.toString().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text((opp['snippet'] ?? opp['why'])!.toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: sub)),
                  ),
                if (opp['url']?.toString().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: opp['url'] as String)),
                      child: Text(opp['url']!.toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                    ),
                  ),
              ]),
            );
          }),
      ],
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  final List docs;
  final bool isDark;
  final Color text, sub, card;
  final Function(String) onGenerate;
  const _DocumentsTab({required this.docs, required this.isDark,
      required this.text, required this.sub, required this.card, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ActionChip(label: '📋 Contract',  onTap: () => onGenerate('generate_contract')),
          _ActionChip(label: '🧾 Invoice',   onTap: () => onGenerate('generate_invoice')),
          _ActionChip(label: '📄 Proposal',  onTap: () => onGenerate('generate_proposal')),
        ]),
        const SizedBox(height: 16),
        if (docs.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const Text('📄', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text('No documents yet', style: TextStyle(color: sub, fontSize: 14)),
              const SizedBox(height: 6),
              Text('Generate a contract, invoice, or proposal above', style: TextStyle(color: sub, fontSize: 12)),
            ]),
          ))
        else
          ...docs.asMap().entries.map((e) {
            final doc  = e.value as Map;
            final type = doc['type']?.toString() ?? 'document';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade50,
                borderRadius: AppRadius.md,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_docEmoji(type), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(type.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Clipboard.setData(ClipboardData(text: doc['content']?.toString() ?? '')),
                    child: const Text('Copy', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(doc['content']?.toString() ?? '',
                    maxLines: 6, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: sub, height: 1.4, fontFamily: 'monospace')),
              ]),
            );
          }),
      ],
    );
  }

  String _docEmoji(String type) {
    return {'contract': '📋', 'invoice': '🧾', 'proposal': '📄', 'pitch_deck': '🎯'}[type] ?? '📄';
  }
}

class _OutreachTab extends StatelessWidget {
  final List msgs;
  final bool isDark;
  final Color text, sub, card;
  final VoidCallback onGenerate;
  const _OutreachTab({required this.msgs, required this.isDark,
      required this.text, required this.sub, required this.card, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OutlineBtn(label: '✉️ Write Cold Outreach', onTap: onGenerate),
        const SizedBox(height: 16),
        if (msgs.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const Text('✉️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text('No outreach messages yet', style: TextStyle(color: sub, fontSize: 14)),
            ]),
          ))
        else
          ...msgs.map((m) {
            final msg = m as Map;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade50,
                borderRadius: AppRadius.md,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_typeEmoji(msg['type']?.toString() ?? ''), style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text((msg['type']?.toString() ?? '').toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Clipboard.setData(ClipboardData(text: msg['body']?.toString() ?? '')),
                    child: const Text('Copy', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ]),
                if (msg['subject']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('Subject: ${msg['subject']}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text)),
                ],
                const SizedBox(height: 6),
                Text(msg['body']?.toString() ?? '',
                    maxLines: 5, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
              ]),
            );
          }),
      ],
    );
  }

  String _typeEmoji(String type) {
    return {'email': '✉️', 'dm': '💬', 'whatsapp': '📱'}[type] ?? '✉️';
  }
}

class _SocialTab extends StatelessWidget {
  final List posts;
  final bool isDark;
  final Color text, sub, card;
  const _SocialTab({required this.posts, required this.isDark,
      required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (posts.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const Text('📱', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text('No social posts yet', style: TextStyle(color: sub, fontSize: 14)),
              const SizedBox(height: 6),
              Text('Enable social posting in the task options to let APEX post for you',
                  style: TextStyle(color: sub, fontSize: 12), textAlign: TextAlign.center),
            ]),
          ))
        else
          ...posts.map((p) {
            final post    = p as Map;
            final posted  = post['posted'] == true;
            final platform = post['platform']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade50,
                borderRadius: AppRadius.md,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(platform == 'twitter' ? '🐦' : '💼', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(platform.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (posted ? AppColors.success : AppColors.warning).withOpacity(0.12),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(posted ? '✅ Posted' : '📋 Draft',
                        style: TextStyle(fontSize: 10,
                            color: posted ? AppColors.success : AppColors.warning,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(post['text']?.toString() ?? '',
                    maxLines: 4, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => Clipboard.setData(ClipboardData(text: post['text']?.toString() ?? '')),
                  child: const Text('Copy post', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          }),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _Msg msg;
  final bool isDark;
  const _ChatBubble({required this.msg, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isUser = !msg.isAgent;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary
              : (isDark ? AppColors.bgCard : Colors.grey.shade100),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.isTool && msg.toolName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Tool: ${msg.toolName}',
                  style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : AppColors.accent,
                      fontWeight: FontWeight.w600)),
            ),
          Text(msg.text,
              style: TextStyle(
                  fontSize: 13,
                  color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  height: 1.4)),
        ]),
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────

class _ResultChip extends StatelessWidget {
  final String label;
  final Color color;
  const _ResultChip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _SliderCard extends StatelessWidget {
  final String label, value;
  final double min, max, current;
  final Function(double) onChanged;
  final bool isDark;
  const _SliderCard({required this.label, required this.value, required this.min,
      required this.max, required this.current, required this.onChanged, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.grey.shade50,
        borderRadius: AppRadius.md,
        border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.bgSurface,
            thumbColor: AppColors.primary,
          ),
          child: Slider(value: current.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
      ]),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;
  final bool isDark;
  const _PermissionRow({required this.label, required this.value,
      required this.onChanged, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(
          fontSize: 12, color: isDark ? Colors.white60 : Colors.black54))),
      Switch.adaptive(value: value, onChanged: onChanged,
          activeColor: AppColors.primary),
    ]);
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: AppRadius.pill,
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _GradientBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double fontSize;
  final bool fullWidth;
  final EdgeInsets? padding;
  const _GradientBtn({required this.label, required this.onTap,
      this.fontSize = 13, this.fullWidth = false, this.padding});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          borderRadius: AppRadius.md,
        ),
        child: Center(child: Text(label, style: TextStyle(
            color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700))),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.07),
          borderRadius: AppRadius.md,
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Center(child: Text(label, style: const TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
      ),
    );
  }
}

class _QuickActionSheet extends StatelessWidget {
  final String title, subtitle;
  final Widget field;
  final VoidCallback onRun;
  final bool isDark;
  const _QuickActionSheet({required this.title, required this.subtitle,
      required this.field, required this.onRun, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          field,
          const SizedBox(height: 16),
          _GradientBtn(label: 'Run APEX', onTap: onRun, fullWidth: true),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _CurrencyInfoSheet extends StatelessWidget {
  final String code;
  const _CurrencyInfoSheet({required this.code});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your Currency', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 8),
        Text('APEX uses your profile currency ($code) for all income estimates and plans. '
            'You can change it in Settings → Edit Profile.',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54, height: 1.5)),
        const SizedBox(height: 16),
        _GradientBtn(
          label: 'Go to Settings',
          onTap: () { Navigator.pop(context); context.push('/settings'); },
          fullWidth: true,
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
