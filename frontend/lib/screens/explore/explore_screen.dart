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
  static const String _currency = 'USD';

  Map<String, dynamic> _agentResult = {};
  String? _workflowId;
  String? _sessionId;
  String _error = '';

  final List<_ChatMsg> _chatMsgs = [];
  bool _chatLoading = false;

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
            '${AdManager.kFreeAgentDaily} agent runs per day on free plan.\nWatch an ad for 1 more run, or go Premium for unlimited.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black45,
              height: 1.5,
            ),
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
                    child: Text('▶️  Watch Ad',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  context.push('/premium');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('⭐ Go Premium',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
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
    if (!adManager.canUseAgent) {
      _showLimitDialog();
      return;
    }
    adManager.recordAgentUse();
    setState(() {
      _phase = _Phase.thinking;
      _error = '';
    });

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
        _chatMsgs.add(_ChatMsg(
            text: result['content']?.toString() ?? '...', isAgent: true));
        _chatLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _chatMsgs
            .add(_ChatMsg(text: 'Connection issue. Try again! 🔄', isAgent: true));
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
      final content = output['content']?.toString() ??
          output['template']?.toString() ??
          output['result']?.toString() ??
          jsonEncode(output);
      setState(() {
        _chatMsgs.add(
            _ChatMsg(text: content, isAgent: true, isTool: true, toolName: tool));
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
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Agentic AI',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          if (!adManager.isPremium)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: adManager.agentUsesRemaining > 0
                        ? AppColors.success.withOpacity(0.12)
                        : AppColors.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${adManager.agentUsesRemaining}/3 runs',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: adManager.agentUsesRemaining > 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ),
            ),
          if (_workflowId != null)
            TextButton.icon(
              onPressed: () => context.push('/workflow/$_workflowId'),
              icon: const Icon(Iconsax.flash, size: 14, color: AppColors.primary),
              label: const Text('Workflow',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
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
                    onViewWorkflow: () => _workflowId != null
                        ? context.push('/workflow/$_workflowId')
                        : null,
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
                    onCurrencyChange: (_) {},
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
    required this.taskCtrl,
    required this.budget,
    required this.hours,
    required this.currency,
    required this.error,
    required this.quickTasks,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.card,
    required this.onBudgetChange,
    required this.onHoursChange,
    required this.onCurrencyChange,
    required this.onQuickTask,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8FF),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                const Text('⚡', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('What do you want to earn from?',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: text))),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Describe ANY income goal. The agent will research, plan, and execute it with you — step by step.',
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
              controller: taskCtrl,
              maxLines: 4,
              style: TextStyle(fontSize: 14, color: text),
              decoration: InputDecoration(
                hintText:
                    'e.g. "I want to start earning on YouTube in 2 months with zero budget" or "Help me get my first freelance client this week"',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),

          const SizedBox(height: 16),

          Row(children: [
            Expanded(
              child: _SettingCard(
                label: 'Budget',
                value: budget == 0 ? '\$0 Free' : '\$${budget.toStringAsFixed(0)}',
                valueColor:
                    budget == 0 ? AppColors.success : AppColors.primary,
                child: Slider(
                  value: budget,
                  min: 0,
                  max: 100,
                  divisions: 10,
                  activeColor: AppColors.primary,
                  onChanged: onBudgetChange,
                ),
                isDark: isDark,
                text: text,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SettingCard(
                label: 'Daily time',
                value: '${hours.toStringAsFixed(1)}h',
                valueColor: AppColors.accent,
                child: Slider(
                  value: hours,
                  min: 0.5,
                  max: 8,
                  divisions: 15,
                  activeColor: AppColors.accent,
                  onChanged: onHoursChange,
                ),
                isDark: isDark,
                text: text,
              ),
            ),
          ]),

          const SizedBox(height: 10),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Text('💵 USD — Universal Currency',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: onRun,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: AppRadius.pill,
                boxShadow: AppShadows.glow,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                 
