import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';

class AgentScreen extends StatefulWidget {
  final String? workflowId;
  const AgentScreen({super.key, this.workflowId});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

enum _Phase { idle, thinking, result }

class _AgentScreenState extends State<AgentScreen> {
  _Phase _phase = _Phase.idle;
  final _taskCtrl   = TextEditingController();
  final _chatCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();

  double _budget = 0;
  double _hours  = 2;

  Map<String, dynamic> _agentResult = {};
  String? _workflowId;
  String? _sessionId;
  String  _error = '';

  final List<_Msg> _chatMsgs  = [];
  bool             _chatLoading = false;

  static const _quickTasks = [
    ('video',    'Start a YouTube channel',      'I want to start earning on YouTube in the next 2 months'),
    ('laptop',   'Freelance on Upwork/Fiverr',   'I want to get my first freelance client this week'),
    ('phone',    'Sell on social media',         'I want to start selling products via WhatsApp and Instagram'),
    ('pen',      'Content writing income',       'I want to earn from writing articles and blog posts'),
    ('shop',     'eCommerce / dropshipping',     'I want to start an online store with no upfront stock'),
    ('chart',    'Trading / investing',          'I want to learn trading and start making money from it'),
    ('palette',  'Design and creative work',     'I want to earn from graphic design and creative services'),
    ('books',    'Online tutoring / teaching',   'I want to earn money teaching skills I know online'),
  ];

  static const _quickEmoji = ['▶️', '💻', '📱', '✍️', '🛍️', '📊', '🎨', '📚'];

  @override
  void initState() {
    super.initState();
    _workflowId = widget.workflowId;
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
            '${AdManager.kFreeAgentDaily} runs per day on free plan.\n'
            'Watch an ad for 1 more run, or go Premium for unlimited.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  adManager.watchAdForAgentUse(context).then((ok) {
                    if (ok && mounted) _runAgent();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: const Center(
                      child: Text('Watch Ad',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () { Navigator.pop(context); context.push('/premium'); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                      child: Text('Go Premium',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _runAgent() async {
    final task = _taskCtrl.text.trim();
    if (task.length < 10) {
      setState(() => _error = 'Please describe your goal in more detail');
      return;
    }
    if (!adManager.canUseAgent) { _showLimitDialog(); return; }
    adManager.recordAgentUse();
    setState(() { _phase = _Phase.thinking; _error = ''; });

    try {
      final result = await api.post('/agent/run', {
        'task':          task,
        'budget_usd':    _budget,
        'hours_per_day': _hours,
        'urgency':       'normal',
      });
      setState(() {
        _agentResult = Map<String, dynamic>.from(result as Map);
        _workflowId  = result['workflow_id']?.toString();
        _phase       = _Phase.result;
        final intro  = result['agent_response']?.toString() ?? '';
        if (intro.isNotEmpty) _chatMsgs.add(_Msg(text: intro, isAgent: true));
      });
    } catch (e) {
      setState(() { _error = 'Agent failed. Please try again.'; _phase = _Phase.idle; });
    }
  }

  Future<void> _sendChat() async {
    final msg = _chatCtrl.text.trim();
    if (msg.isEmpty || _chatLoading) return;
    _chatCtrl.clear();
    setState(() { _chatMsgs.add(_Msg(text: msg, isAgent: false)); _chatLoading = true; });
    _scrollDown();
    try {
      final r = await api.post('/agent/chat', {
        'message': msg,
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

  Future<void> _runTool(String tool, Map<String, dynamic> input) async {
    setState(() => _chatLoading = true);
    try {
      final r   = await api.post('/agent/execute-tool', {
        'tool': tool, 'input': input,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      final out = r['output'] as Map? ?? {};
      final txt = out['content']?.toString()
          ?? out['template']?.toString()
          ?? out['result']?.toString()
          ?? jsonEncode(out);
      setState(() {
        _chatMsgs.add(_Msg(text: txt, isAgent: true, isTool: true, toolName: tool));
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black : Colors.white;
    final card   = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text   = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
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
          Text('Agentic AI',
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
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
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
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _phase == _Phase.thinking
            ? _buildThinking()
            : _phase == _Phase.result
                ? _ResultView(
                    result:      _agentResult,
                    chatMsgs:    _chatMsgs,
                    chatCtrl:    _chatCtrl,
                    scrollCtrl:  _scrollCtrl,
                    chatLoading: _chatLoading,
                    isDark:      isDark,
                    text:        text, sub: sub, card: card, border: border,
                    workflowId:  _workflowId,
                    onSend:      _sendChat,
                    onRunTool:   _runTool,
                    onWorkflow:  _workflowId != null
                        ? () => context.push('/workflow/$_workflowId') : null,
                  )
                : _buildIdle(isDark, text, sub, card),
      ),
    );
  }

  Widget _buildThinking() {
    final items = [
      'Researching your market...',
      'Analyzing skill-market fit...',
      'Mapping AI automation...',
      'Finding free tools...',
      'Building execution plan...',
      'Estimating income potential...',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
          ).animate().scale().then().shimmer(duration: 2.seconds),
          const SizedBox(height: 28),
          const Text('APEX Agent is working...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 6),
          const Text('Building your complete income system',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 28),
          ...items.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 14),
              const SizedBox(width: 8),
              Text(e.value, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ]).animate(delay: (e.key * 500).ms).fadeIn().slideX(begin: -0.1),
          )),
        ]),
      ),
    );
  }

  Widget _buildIdle(bool isDark, Color text, Color sub, Color card) {
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              'Describe ANY income goal. APEX researches, plans, and executes it with full AI outputs.',
              style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
          ]),
        ).animate().fadeIn(),
        const SizedBox(height: 20),

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
        ),

        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),

        const SizedBox(height: 16),

        Row(children: [
          Expanded(child: _SliderCard(
            label: 'Budget',
            value: _budget == 0 ? r'$0 Free' : '\$${_budget.toStringAsFixed(0)}',
            valueColor: _budget == 0 ? AppColors.success : AppColors.primary,
            child: Slider(value: _budget, min: 0, max: 200, divisions: 20,
                activeColor: AppColors.primary, onChanged: (v) => setState(() => _budget = v)),
            isDark: isDark, text: text,
          )),
          const SizedBox(width: 10),
          Expanded(child: _SliderCard(
            label: 'Daily time',
            value: '${_hours.toStringAsFixed(1)}h',
            valueColor: AppColors.accent,
            child: Slider(value: _hours, min: 0.5, max: 8, divisions: 15,
                activeColor: AppColors.accent, onChanged: (v) => setState(() => _hours = v)),
            isDark: isDark, text: text,
          )),
        ]),

        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: AppRadius.pill,
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: const Text('USD - Universal Currency',
              style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
        ),

        const SizedBox(height: 20),

        GestureDetector(
          onTap: _runAgent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: AppRadius.pill,
              boxShadow: AppShadows.glow,
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Run Agent', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 28),
        Text('Quick Start', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 12),

        ..._quickTasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          return GestureDetector(
            onTap: () { setState(() => _taskCtrl.text = t.$3); HapticFeedback.lightImpact(); },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                borderRadius: AppRadius.md,
              ),
              child: Row(children: [
                Text(_quickEmoji[i], style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                  Text(t.$3, style: TextStyle(fontSize: 11, color: sub),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: sub),
              ]),
            ),
          );
        }),

        const SizedBox(height: 40),
      ]),
    );
  }
}

// RESULT VIEW
class _ResultView extends StatefulWidget {
  final Map<String, dynamic> result;
  final List<_Msg>           chatMsgs;
  final TextEditingController chatCtrl;
  final ScrollController      scrollCtrl;
  final bool chatLoading, isDark;
  final Color text, sub, card, border;
  final String? workflowId;
  final VoidCallback onSend;
  final Function(String, Map<String, dynamic>) onRunTool;
  final VoidCallback? onWorkflow;

  const _ResultView({
    required this.result, required this.chatMsgs, required this.chatCtrl,
    required this.scrollCtrl, required this.chatLoading, required this.isDark,
    required this.text, required this.sub, required this.card, required this.border,
    required this.workflowId, required this.onSend, required this.onRunTool,
    required this.onWorkflow,
  });

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 4, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final plan    = widget.result['plan']       as Map?  ?? {};
    final steps   = widget.result['steps']      as List? ?? [];
    final tools   = widget.result['free_tools'] as List? ?? [];
    final now     = widget.result['immediate_action']?.toString() ?? '';
    final surface = widget.isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Column(children: [
      Container(
        color: widget.card,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(plan['title']?.toString() ?? 'Your Plan',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.text))),
            if (widget.workflowId != null)
              GestureDetector(
                onTap: widget.onWorkflow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12), borderRadius: AppRadius.pill),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Iconsax.flash, size: 12, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text('Workflow',
                        style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            _chip('${plan['viability_score'] ?? plan['viability'] ?? 75}% viable', AppColors.success),
            _chip(plan['timeline']?.toString() ?? '', AppColors.accent),
            _chip('\$${_fmt((plan['max_monthly_usd'] ?? 0).toDouble())}/mo max', AppColors.gold),
          ]),
          if (now.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: AppRadius.md,
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('⚡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text('Do NOW: $now',
                    style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: widget.sub,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            tabs: const [Tab(text: 'Steps'), Tab(text: 'Stack'), Tab(text: 'Tools'), Tab(text: 'Chat')],
          ),
        ]),
      ),
      Divider(height: 1, color: widget.border),

      Expanded(child: TabBarView(controller: _tabs, children: [

        // STEPS
        ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: steps.length,
          itemBuilder: (_, i) {
            final s     = steps[i] as Map;
            final auto  = s['type'] == 'ai_automated' || s['type'] == 'automated';
            final aiOut = s['ai_output']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                borderRadius: AppRadius.lg,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: auto
                          ? AppColors.primary.withOpacity(0.12)
                          : AppColors.warning.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text('${s['order'] ?? i + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: auto ? AppColors.primary : AppColors.warning))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s['title']?.toString() ?? '',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: auto
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.warning.withOpacity(0.1),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(auto ? 'AI' : s['type'] == 'hybrid' ? 'AI+You' : 'You',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                            color: auto ? AppColors.primary : AppColors.warning)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(s['description']?.toString() ?? '',
                    style: TextStyle(fontSize: 12, color: widget.sub, height: 1.5)),
                if (aiOut.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: AppRadius.md,
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('AI Output - Ready to use:',
                          style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SelectableText(aiOut, style: TextStyle(fontSize: 12, color: widget.text)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: aiOut));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Copied!'),
                              backgroundColor: AppColors.success,
                              duration: Duration(seconds: 1)));
                        },
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Iconsax.copy, size: 12, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text('Copy', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                ],
              ]),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
          },
        ),

        // STACK
        Builder(builder: (ctx) {
          final stacks  = widget.result['income_stacking']       as List? ?? [];
          final fails   = widget.result['anti_failure_protocols'] as List? ?? [];
          final tl      = widget.result['cash_pull_timeline']     as Map?  ?? {};
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (tl.isNotEmpty) ...[
              Text('Cash Pull Timeline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
              const SizedBox(height: 10),
              Row(children: [
                _tp('Day 7',   '\$${tl['day7_target_usd']   ?? 0}', AppColors.success),
                const SizedBox(width: 8),
                _tp('Month 1', '\$${tl['month1_target_usd'] ?? 0}', AppColors.primary),
                const SizedBox(width: 8),
                _tp('Month 3', '\$${tl['month3_target_usd'] ?? 0}', AppColors.accent),
                const SizedBox(width: 8),
                _tp('Month 6', '\$${tl['month6_target_usd'] ?? 0}', AppColors.gold),
              ]),
              const SizedBox(height: 20),
            ],
            if (stacks.isNotEmpty) ...[
              Text('Income Stacking',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
              const SizedBox(height: 10),
              ...stacks.map((s) {
                final m  = s as Map;
                final cs = [AppColors.success, AppColors.primary, AppColors.accent];
                final ci = stacks.indexOf(s).clamp(0, 2);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: cs[ci].withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Container(width: 4, height: 50,
                        decoration: BoxDecoration(color: cs[ci], borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m['stream']?.toString() ?? '',
                          style: TextStyle(fontSize: 11, color: cs[ci], fontWeight: FontWeight.w700)),
                      Text(m['method']?.toString() ?? '',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text)),
                      Text('\$${m['monthly_potential_usd'] ?? 0}/mo',
                          style: TextStyle(fontSize: 11, color: widget.sub)),
                    ])),
                  ]),
                );
              }),
              const SizedBox(height: 20),
            ],
            if (fails.isNotEmpty) ...[
              Text('Anti-Failure Protocols',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
              const SizedBox(height: 10),
              ...fails.map((f) {
                final m   = f as Map;
                final p   = m['probability']?.toString() ?? 'medium';
                final col = p == 'high' ? AppColors.error
                    : p == 'medium' ? AppColors.warning : AppColors.success;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: col.withOpacity(0.06),
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: col.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(m['failure_mode']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.text))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: col.withOpacity(0.15), borderRadius: AppRadius.pill),
                        child: Text(p.toUpperCase(),
                            style: TextStyle(fontSize: 9, color: col, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('Prevention: ${m['counter_strategy'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: widget.sub, height: 1.4)),
                  ]),
                );
              }),
            ],
          ]);
        }),

        // TOOLS
        ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tools.length,
          itemBuilder: (_, i) {
            final t = tools[i] as Map;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                borderRadius: AppRadius.lg,
                border: Border.all(color: AppColors.success.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.md),
                  child: const Center(child: Icon(Iconsax.tick_circle, color: AppColors.success, size: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['name']?.toString() ?? '',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text)),
                  Text(t['purpose']?.toString() ?? '',
                      style: TextStyle(fontSize: 11, color: widget.sub)),
                  if (t['url'] != null)
                    Text(t['url'].toString(),
                        style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                ])),
                const Text('FREE',
                    style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
          },
        ),

        // CHAT
        Column(children: [
          Container(
            color: widget.card,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _toolBtn('Write Script',  'write_content',   {'type': 'script',       'topic': widget.result['task'] ?? ''}, surface, widget.text, widget.isDark),
                _toolBtn('Client Email',  'create_template', {'type': 'cold_email',   'purpose': 'first client'},             surface, widget.text, widget.isDark),
                _toolBtn('Content Ideas', 'write_content',   {'type': 'content_ideas','niche': widget.result['task'] ?? ''},  surface, widget.text, widget.isDark),
                _toolBtn('Research',      'research',        {'topic': widget.result['task'] ?? ''},                          surface, widget.text, widget.isDark),
                _toolBtn('30-Day Plan',   'create_plan',     {'goal': widget.result['task'] ?? '', 'days': 30},               surface, widget.text, widget.isDark),
              ]),
            ),
          ),
          Divider(height: 1, color: widget.border),
          Expanded(
            child: widget.chatMsgs.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('💬', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text('Ask the agent anything', style: TextStyle(color: widget.sub, fontSize: 13)),
                  ]))
                : ListView.builder(
                    controller: widget.scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.chatMsgs.length + (widget.chatLoading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == widget.chatMsgs.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [AppColors.primary, AppColors.accent]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(child: SizedBox(width: 12, height: 12,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))),
                            ),
                            const SizedBox(width: 8),
                            Text('Working...', style: TextStyle(color: widget.sub, fontSize: 12)),
                          ]),
                        );
                      }
                      return _Bubble(msg: widget.chatMsgs[i],
                          isDark: widget.isDark, text: widget.text, sub: widget.sub);
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
                left: 12, right: 12, top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 10),
            decoration: BoxDecoration(
              color: widget.card,
              border: Border(top: BorderSide(color: widget.border, width: 0.8)),
            ),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.bgSurface : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: widget.chatCtrl,
                    style: TextStyle(color: widget.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ask anything...',
                      hintStyle: TextStyle(color: widget.sub, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onSend,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Iconsax.send_1, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ]),

      ])),
    ]);
  }

  Widget _toolBtn(String label, String tool, Map<String,dynamic> input, Color surface, Color text, bool isDark) {
    return GestureDetector(
      onTap: () => widget.onRunTool(tool, input),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: AppRadius.pill,
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: text, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _tp(String period, String amount, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: AppRadius.md,
          border: Border.all(color: color.withOpacity(0.25))),
      child: Column(children: [
        Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        Text(period, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7))),
      ]),
    ),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// BUBBLE
class _Bubble extends StatelessWidget {
  final _Msg msg;
  final bool isDark;
  final Color text, sub;
  const _Bubble({required this.msg, required this.isDark, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    if (msg.isAgent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.auto_awesome, color: Colors.white, size: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : const Color(0xFFF0F0F8),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (msg.isTool) Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1), borderRadius: AppRadius.pill),
                  child: Text('Tool: ${msg.toolName ?? "output"}',
                      style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
                SelectableText(msg.text,
                    style: TextStyle(color: text, fontSize: 13, height: 1.5)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Copied!'),
                        backgroundColor: AppColors.success,
                        duration: Duration(seconds: 1)));
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Iconsax.copy, size: 11, color: sub),
                    const SizedBox(width: 3),
                    Text('Copy', style: TextStyle(fontSize: 10, color: sub)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
            ),
            child: Text(msg.text,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
          ),
        ),
      ]),
    );
  }
}

// HELPERS
class _SliderCard extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final Widget child;
  final bool isDark;
  final Color text;
  const _SliderCard({required this.label, required this.value, required this.valueColor,
      required this.child, required this.isDark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.md,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: TextStyle(fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, color: valueColor, fontWeight: FontWeight.w700)),
        ]),
        child,
      ]),
    );
  }
}

class _Msg {
  final String  text;
  final bool    isAgent, isTool;
  final String? toolName;
  const _Msg({required this.text, required this.isAgent, this.isTool = false, this.toolName});
}
