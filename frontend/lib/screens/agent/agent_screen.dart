import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../widgets/ad_widgets.dart';

// ─────────────────────────────────────────────────────────────────
// RiseUp Agentic AI Screen
// User describes ANY task → Agent plans + executes → saves workflow
// ─────────────────────────────────────────────────────────────────

class AgentScreen extends StatefulWidget {
  final String? workflowId;
  const AgentScreen({super.key, this.workflowId});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

enum _Phase { idle, thinking, result, chatting }

class _AgentScreenState extends State<AgentScreen> {
  _Phase _phase = _Phase.idle;
  final _taskCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  double _budget = 0;
  double _hours = 2;
  static const String _currency = 'USD'; // USD only - universal system

  Map<String, dynamic> _agentResult = {};
  String? _workflowId;
  String? _sessionId;
  String _error = '';

  // Chat messages for follow-up
  final List<_ChatMsg> _chatMsgs = [];
  bool _chatLoading = false;

  // Quick task templates
  static const _quickTasks = [
    ('▶️', 'Start a YouTube channel', 'I want to start earning on YouTube in the next 2 months'),
    ('💻', 'Freelance on Upwork/Fiverr', 'I want to get my first freelance client this week'),
    ('📱', 'Sell on social media', 'I want to start selling products via WhatsApp and Instagram'),
    ('✍️', 'Content writing income', 'I want to earn from writing articles and blog posts'),
    ('🛍️', 'eCommerce / dropshipping', 'I want to start an online store with no upfront stock'),
    ('📊', 'Trading / investing', 'I want to learn trading and start making money from it'),
    ('🎨', 'Design & creative work', 'I want to earn from graphic design and creative services'),
    ('📚', 'Online tutoring / teaching', 'I want to earn money teaching skills I know online'),
  ];

  @override
  void initState() {
    super.initState();
    _workflowId = widget.workflowId;
  }

  Future<void> _runAgent() async {
    final task = _taskCtrl.text.trim();
    if (task.length < 10) {
      setState(() => _error = 'Please describe your goal in more detail');
      return;
    }
    // Check free usage limit
    if (!adManager.canUseAgent) {
      _showLimitDialog();
      return;
    }
    adManager.recordAgentUse();
    setState(() { _phase = _Phase.thinking; _error = ''; });

    try {
      final result = await api.post('/agent/run', {
        'task': task,
        'budget_usd': _budget,
        'hours_per_day': _hours,
        'urgency': 'normal',
      });

      setState(() {
        _agentResult = Map<String, dynamic>.from(result as Map);
        _workflowId = result['workflow_id']?.toString();
        _phase = _Phase.result;

        // Add initial agent message to chat
        final agentResp = result['agent_response']?.toString() ?? '';
        if (agentResp.isNotEmpty) {
          _chatMsgs.add(_ChatMsg(text: agentResp, isAgent: true));
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Agent failed. Please try again.';
        _phase = _Phase.idle;
      });
    }
  }

  Future<void> _sendChat() async {
    final msg = _chatCtrl.text.trim();
    if (msg.isEmpty || _chatLoading) return;
    _chatCtrl.clear();
    setState(() {
      _chatMsgs.add(_ChatMsg(text: msg, isAgent: false));
      _chatLoading = true;
    });
    _scrollToBottom();

    try {
      final result = await api.post('/agent/chat', {
        'message': msg,
        if (_sessionId != null) 'session_id': _sessionId,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      setState(() {
        _sessionId = result['session_id']?.toString();
        _chatMsgs.add(_ChatMsg(text: result['content']?.toString() ?? '...', isAgent: true));
        _chatLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _chatMsgs.add(_ChatMsg(text: 'Connection issue. Try again! 🔄', isAgent: true));
        _chatLoading = false;
      });
    }
  }

  Future<void> _executeTool(String tool, Map<String, dynamic> input) async {
    setState(() => _chatLoading = true);
    try {
      final result = await api.post('/agent/execute-tool', {
        'tool': tool,
        'input': input,
        if (_workflowId != null) 'workflow_id': _workflowId,
      });
      final output = result['output'] as Map? ?? {};
      final content = output['content']?.toString()
          ?? output['template']?.toString()
          ?? output['result']?.toString()
          ?? jsonEncode(output);
      setState(() {
        _chatMsgs.add(_ChatMsg(text: content, isAgent: true, isTool: true, toolName: tool));
        _chatLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _chatLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () {
            if (_phase == _Phase.result || _phase == _Phase.chatting) {
              setState(() { _phase = _Phase.idle; _taskCtrl.clear(); _agentResult = {}; _chatMsgs.clear(); });
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
          Text('Agentic AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          if (!adManager.isPremium)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: adManager.agentUsesRemaining > 0
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${adManager.agentUsesRemaining}/3 runs',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: adManager.agentUsesRemaining > 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              )),
            ),
          if (_workflowId != null)
            TextButton.icon(
              onPressed: () => context.push('/workflow/$_workflowId'),
              icon: const Icon(Iconsax.flash, size: 14, color: AppColors.primary),
              label: const Text('Workflow', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: border)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _phase == _Phase.thinking
            ? _ThinkingView()
            : _phase == _Phase.result || _phase == _Phase.chatting
                ? _ResultView(
                    result: _agentResult,
                    chatMsgs: _chatMsgs,
                    chatCtrl: _chatCtrl,
                    scrollCtrl: _scrollCtrl,
                    chatLoading: _chatLoading,
                    isDark: isDark,
                    text: text,
                    sub: sub,
                    card: card,
                    border: border,
                    workflowId: _workflowId,
                    onSend: _sendChat,
                    onExecuteTool: _executeTool,
                    onViewWorkflow: () => _workflowId != null ? context.push('/workflow/$_workflowId') : null,
                  )
                : _InputView(
                    taskCtrl: _taskCtrl,
                    budget: _budget,
                    hours: _hours,
                    currency: _currency,
                    error: _error,
                    quickTasks: _quickTasks,
                    isDark: isDark,
                    text: text,
                    sub: sub,
                    card: card,
                    onBudgetChange: (v) => setState(() => _budget = v),
                    onHoursChange: (v) => setState(() => _hours = v),
                    onCurrencyChange: (v) => setState(() => _currency = v),
                    onRun: _runAgent,
                    onQuickTask: (task) {
                      setState(() => _taskCtrl.text = task);
                    },
                  ),
      ),
    );
  }
}

// ── Input Phase ───────────────────────────────────────────────────
class _InputView extends StatelessWidget {
  final TextEditingController taskCtrl;
  final double budget, hours;
  final String currency, error;
  final List<(String, String, String)> quickTasks;
  final bool isDark;
  final Color text, sub, card;
  final Function(double) onBudgetChange, onHoursChange;
  final Function(String) onCurrencyChange, onQuickTask;
  final VoidCallback onRun;

  const _InputView({
    required this.taskCtrl, required this.budget, required this.hours,
    required this.currency, required this.error, required this.quickTasks,
    required this.isDark, required this.text, required this.sub, required this.card,
    required this.onBudgetChange, required this.onHoursChange,
    required this.onCurrencyChange, required this.onQuickTask, required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final currencies = ['NGN', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8FF),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('⚡', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('What do you want to earn from?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
                ]),
                const SizedBox(height: 8),
                Text('Describe ANY income goal. The agent will research, plan, and execute it with you — step by step.',
                    style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
              ],
            ),
          ).animate().fadeIn(),

          const SizedBox(height: 20),

          // Task input
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: TextField(
              controller: taskCtrl,
              maxLines: 4,
              style: TextStyle(fontSize: 14, color: text),
              decoration: InputDecoration(
                hintText: 'e.g. "I want to start earning on YouTube in 2 months with zero budget" or "Help me get my first freelance client this week" or "I sell food — help me get more customers"',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),

          const SizedBox(height: 16),

          // Settings row
          Row(children: [
            // Budget
            Expanded(
              child: _SettingCard(
                label: 'Budget',
                value: budget == 0 ? '₦0 Free' : '\$${budget.toStringAsFixed(0)}',
                valueColor: budget == 0 ? AppColors.success : AppColors.primary,
                child: Slider(
                  value: budget, min: 0, max: 100, divisions: 10,
                  activeColor: AppColors.primary,
                  onChanged: onBudgetChange,
                ),
                isDark: isDark, text: text,
              ),
            ),
            const SizedBox(width: 10),
            // Hours
            Expanded(
              child: _SettingCard(
                label: 'Daily time',
                value: '${hours.toStringAsFixed(1)}h',
                valueColor: AppColors.accent,
                child: Slider(
                  value: hours, min: 0.5, max: 8, divisions: 15,
                  activeColor: AppColors.accent,
                  onChanged: onHoursChange,
                ),
                isDark: isDark, text: text,
              ),
            ),
          ]),


          // USD only — universal currency
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: const Text('💵 USD — Universal Currency', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // Run button
          GestureDetector(
            onTap: onRun,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                borderRadius: AppRadius.pill,
                boxShadow: AppShadows.glow,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Run Agent', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 28),

          // Quick tasks
          Text('Quick Start', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 12),
          ...quickTasks.map((t) => GestureDetector(
            onTap: () {
              onQuickTask(t.$3);
              HapticFeedback.lightImpact();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                borderRadius: AppRadius.md,
              ),
              child: Row(children: [
                Text(t.$1, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                  Text(t.$3, style: TextStyle(fontSize: 11, color: sub), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: sub),
              ]),
            ),
          )),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Thinking Phase ────────────────────────────────────────────────
class _ThinkingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final steps = [
      '🔍 Researching what works right now...',
      '🧠 Analyzing your goal deeply...',
      '⚡ Identifying what AI can automate...',
      '🛠️ Finding free tools for you...',
      '📋 Building your execution plan...',
      '💰 Estimating your income potential...',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            const SizedBox(height: 28),
            const Text('Agent is working...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 6),
            const Text('Deep researching your goal', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 28),
            ...steps.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 14),
                const SizedBox(width: 8),
                Text(e.value, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ]).animate(delay: (e.key * 500).ms).fadeIn().slideX(begin: -0.1),
            )),
          ],
        ),
      ),
    );
  }
}

// ── Result + Chat Phase ───────────────────────────────────────────
class _ResultView extends StatefulWidget {
  final Map<String, dynamic> result;
  final List<_ChatMsg> chatMsgs;
  final TextEditingController chatCtrl;
  final ScrollController scrollCtrl;
  final bool chatLoading;
  final bool isDark;
  final Color text, sub, card, border;
  final String? workflowId;
  final VoidCallback onSend;
  final Function(String, Map<String, dynamic>) onExecuteTool;
  final VoidCallback? onViewWorkflow;

  const _ResultView({
    required this.result, required this.chatMsgs, required this.chatCtrl,
    required this.scrollCtrl, required this.chatLoading, required this.isDark,
    required this.text, required this.sub, required this.card, required this.border,
    required this.workflowId, required this.onSend, required this.onExecuteTool,
    required this.onViewWorkflow,
  });

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final plan = widget.result['plan'] as Map? ?? {};
    final steps = widget.result['steps'] as List? ?? [];
    final tools = widget.result['free_tools'] as List? ?? [];
    final immediate = widget.result['immediate_action']?.toString() ?? '';
    final surface = widget.isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Column(
      children: [
        // Plan summary card
        Container(
          color: widget.card,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(plan['title']?.toString() ?? 'Your Plan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.text))),
                if (widget.workflowId != null)
                  GestureDetector(
                    onTap: widget.onViewWorkflow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: AppRadius.pill),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Iconsax.flash, size: 12, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text('View Workflow', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _pill('${plan['viability'] ?? 75}% viable', AppColors.success),
                const SizedBox(width: 8),
                _pill(plan['timeline']?.toString() ?? '', AppColors.accent),
                const SizedBox(width: 8),
                _pill('${plan['income_range']?['currency'] ?? ''} ${_fmt(plan['income_range']?['max']?.toDouble() ?? 0)}/mo max', AppColors.gold),
              ]),
              if (immediate.isNotEmpty) ...[
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
                    Expanded(child: Text('Do this NOW: $immediate',
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
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [Tab(text: 'Steps'), Tab(text: 'Stack'), Tab(text: 'Tools'), Tab(text: 'Chat')],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: widget.border),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // ── Steps tab ──────────────────────────────
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: steps.length + (plan['warning'] != null ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == steps.length) {
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: AppRadius.md,
                        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('⚠️', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(plan['warning']?.toString() ?? '',
                            style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.orange.shade200 : Colors.orange.shade800))),
                      ]),
                    );
                  }
                  final s = steps[i] as Map;
                  final isAuto = s['type'] == 'automated';
                  final aiOutput = s['ai_output']?.toString() ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                      borderRadius: AppRadius.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: isAuto ? AppColors.primary.withOpacity(0.12) : AppColors.warning.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: Text('${s['order'] ?? i + 1}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                    color: isAuto ? AppColors.primary : AppColors.warning))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s['title']?.toString() ?? '',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isAuto ? AppColors.primary.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(isAuto ? '🤖 AI' : '👤 You',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                    color: isAuto ? AppColors.primary : AppColors.warning)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(s['description']?.toString() ?? '',
                            style: TextStyle(fontSize: 12, color: widget.sub, height: 1.5)),
                        if (aiOutput.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.06),
                              borderRadius: AppRadius.md,
                              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('🤖 AI Output — Ready to use:', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(aiOutput, style: TextStyle(fontSize: 12, color: widget.text)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: aiOutput));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('✅ Copied!'), backgroundColor: AppColors.success, duration: Duration(seconds: 1)),
                                  );
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
                        if ((s['tools'] as List? ?? []).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, children: ((s['tools'] as List?) ?? []).map((t) =>
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: surface, borderRadius: AppRadius.pill),
                              child: Text(t.toString(), style: TextStyle(fontSize: 10, color: widget.sub)),
                            )
                          ).toList()),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                },
              ),

              // ── Tools tab ──────────────────────────────
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
                        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.md),
                        child: const Center(child: Icon(Iconsax.tick_circle, color: AppColors.success, size: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text)),
                        Text(t['purpose']?.toString() ?? '', style: TextStyle(fontSize: 11, color: widget.sub)),
                        if (t['url'] != null) Text(t['url'].toString(), style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                      ])),
                      const Text('FREE', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800)),
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                },
              ),

              // ── Income Stack tab ───────────────────────
              Builder(builder: (ctx) {
                final stacks = widget.result['income_stacking'] as List? ?? [];
                final antiFailure = widget.result['anti_failure_protocols'] as List? ?? [];
                final timeline = widget.result['cash_pull_timeline'] as Map? ?? {};
                final surface = widget.isDark ? AppColors.bgSurface : Colors.grey.shade100;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (timeline.isNotEmpty) ...[
                      Text('💰 Cash Pull Timeline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
                      const SizedBox(height: 10),
                      Row(children: [
                        _timelinePill('Day 7', '\$${timeline['day7_target_usd'] ?? 0}', AppColors.success),
                        const SizedBox(width: 8),
                        _timelinePill('Month 1', '\$${timeline['month1_target_usd'] ?? 0}', AppColors.primary),
                        const SizedBox(width: 8),
                        _timelinePill('Month 3', '\$${timeline['month3_target_usd'] ?? 0}', AppColors.accent),
                        const SizedBox(width: 8),
                        _timelinePill('Month 6', '\$${timeline['month6_target_usd'] ?? 0}', AppColors.gold),
                      ]),
                      if (timeline['day7_how'] != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: AppRadius.md),
                          child: Text('Day 7: ${timeline['day7_how']}', style: TextStyle(fontSize: 12, color: widget.text, height: 1.4)),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                    if (stacks.isNotEmpty) ...[
                      Text('📈 Income Stacking — 3 Streams, 1 Skill', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
                      const SizedBox(height: 10),
                      ...stacks.map((s) {
                        final stream = s as Map;
                        final colors = [AppColors.success, AppColors.primary, AppColors.accent];
                        final idx = stacks.indexOf(s).clamp(0, 2);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: widget.isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: colors[idx].withOpacity(0.2)),
                          ),
                          child: Row(children: [
                            Container(width: 4, height: 50, decoration: BoxDecoration(color: colors[idx], borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(stream['stream']?.toString() ?? '', style: TextStyle(fontSize: 11, color: colors[idx], fontWeight: FontWeight.w700)),
                              Text(stream['method']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.text)),
                              const SizedBox(height: 2),
                              Row(children: [
                                Icon(Icons.attach_money_rounded, size: 12, color: AppColors.gold),
                                Text('\$${stream['monthly_potential_usd'] ?? 0}/mo potential', style: TextStyle(fontSize: 11, color: widget.sub)),
                              ]),
                            ])),
                          ]),
                        );
                      }),
                      const SizedBox(height: 20),
                    ],
                    if (antiFailure.isNotEmpty) ...[
                      Text('🛡️ Anti-Failure Protocols', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.text)),
                      const SizedBox(height: 10),
                      ...antiFailure.map((f) {
                        final fail = f as Map;
                        final prob = fail['probability']?.toString() ?? 'medium';
                        final color = prob == 'high' ? AppColors.error : prob == 'medium' ? AppColors.warning : AppColors.success;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.06),
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: color.withOpacity(0.2)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(prob == 'high' ? '⚠️' : prob == 'medium' ? '⚡' : '💡', style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(fail['failure_mode']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.text))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppRadius.pill),
                                child: Text(prob.toUpperCase(), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text('Prevention: ${fail['counter_strategy'] ?? ''}', style: TextStyle(fontSize: 12, color: widget.sub, height: 1.4)),
                          ]),
                        );
                      }),
                    ],
                  ],
                );
              }),

                            // ── AI Chat tab ────────────────────────────
              Column(
                children: [
                  // Quick tool buttons
                  Container(
                    color: widget.card,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ('✍️', 'Write Script', 'write_content', {'type': 'script', 'topic': widget.result['task'] ?? ''}),
                          ('📧', 'Client Email', 'create_template', {'type': 'cold_email', 'purpose': 'find first client'}),
                          ('💡', 'Content Ideas', 'write_content', {'type': 'content_ideas', 'niche': widget.result['task'] ?? ''}),
                          ('🔍', 'Research More', 'research', {'topic': widget.result['task'] ?? ''}),
                          ('📅', '30-Day Plan', 'create_plan', {'goal': widget.result['task'] ?? '', 'days': 30}),
                        ].map((btn) => GestureDetector(
                          onTap: () => widget.onExecuteTool(btn.$3, btn.$4),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: AppRadius.pill,
                              border: Border.all(color: widget.isDark ? Colors.white12 : Colors.grey.shade300),
                            ),
                            child: Text('${btn.$1} ${btn.$2}', style: TextStyle(fontSize: 11, color: widget.text, fontWeight: FontWeight.w500)),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: widget.border),

                  // Messages
                  Expanded(
                    child: widget.chatMsgs.isEmpty
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('💬', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            Text('Ask the agent anything', style: TextStyle(color: widget.sub, fontSize: 13)),
                            Text('Write scripts, email templates, plans, research...', style: TextStyle(color: widget.sub, fontSize: 11), textAlign: TextAlign.center),
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
                                        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(child: SizedBox(width: 12, height: 12,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Agent is working...', style: TextStyle(color: widget.sub, fontSize: 12)),
                                  ]),
                                );
                              }
                              final msg = widget.chatMsgs[i];
                              return _ChatBubble(msg: msg, isDark: widget.isDark, text: widget.text, sub: widget.sub);
                            },
                          ),
                  ),

                  // Input
                  Container(
                    padding: EdgeInsets.only(
                      left: 12, right: 12, top: 10,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 10,
                    ),
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
                              hintText: 'Ask anything — write a script, find tools, make a plan...',
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
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timelinePill(String period, String amount, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: AppRadius.md, border: Border.all(color: color.withOpacity(0.25))),
      child: Column(children: [
        Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        Text(period, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7))),
      ]),
    ),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Chat Bubble ───────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  final bool isDark;
  final Color text, sub;
  const _ChatBubble({required this.msg, required this.isDark, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    if (msg.isAgent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (msg.isTool) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: AppRadius.pill),
                        child: Text('🛠️ ${msg.toolName ?? 'Tool output'}',
                            style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    SelectableText(msg.text, style: TextStyle(color: text, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: msg.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Copied!'), backgroundColor: AppColors.success, duration: Duration(seconds: 1)),
                        );
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Iconsax.copy, size: 11, color: sub),
                        const SizedBox(width: 3),
                        Text('Copy', style: TextStyle(fontSize: 10, color: sub)),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14), topRight: Radius.circular(14), bottomLeft: Radius.circular(14),
                ),
              ),
              child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Setting Card Helper ───────────────────────────────────────────
class _SettingCard extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final Widget child;
  final bool isDark;
  final Color text;
  const _SettingCard({required this.label, required this.value, required this.valueColor,
      required this.child, required this.isDark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 12, color: valueColor, fontWeight: FontWeight.w700)),
          ]),
          child,
        ],
      ),
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isAgent, isTool;
  final String? toolName;
  const _ChatMsg({required this.text, required this.isAgent, this.isTool = false, this.toolName});
}
