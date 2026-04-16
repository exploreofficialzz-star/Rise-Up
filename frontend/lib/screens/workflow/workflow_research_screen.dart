// frontend/lib/screens/workflow/workflow_research_screen.dart
// v3.3 — Natural Input · Live Intent Preview · Conversational UX · Ad-wired

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';

// ═══════════════════════════════════════════════════════════
// INTENT DETECTION
// ═══════════════════════════════════════════════════════════

enum TaskIntent {
  incomeGoal, contactSearch, jobSearch, productSourcing,
  learnSkill, businessResearch, quickAnswer, marketplacePost,
}

class IntentResult {
  final TaskIntent intent;
  final String     label, description, emoji;
  final Color      color;
  final double     confidence;
  const IntentResult({
    required this.intent, required this.label, required this.description,
    required this.emoji,  required this.color,  required this.confidence,
  });
}

IntentResult detectIntent(String text) {
  final t = text.toLowerCase().trim();
  bool has(List<String> p) => p.any((x) => t.contains(x));

  if (has(['contact','phone number','whatsapp number','number of','give me a contact',
            'contacts of','find someone','who sells','sellers in','vendors in',
            'suppliers in','address of']))
    return IntentResult(intent: TaskIntent.contactSearch, label: 'Contact / Directory Search',
      description: "I'll search for contacts and vendors who match what you're looking for.",
      emoji: '📞', color: const Color(0xFF00B894), confidence: 0.92);

  if (has(['where to buy','how to buy','buy cheap','affordable','source for','import from',
            'wholesale','supplier','looking to buy','need to buy','want to buy','price of']))
    return IntentResult(intent: TaskIntent.productSourcing, label: 'Product Sourcing',
      description: "I'll find suppliers, prices, and sourcing strategies.",
      emoji: '🛒', color: const Color(0xFF6C5CE7), confidence: 0.88);

  if (has(['find job','get job','job in','jobs for','freelance job','remote job','hiring',
            'vacancy','employment','work as','looking for work','apply for','job opportunities']))
    return IntentResult(intent: TaskIntent.jobSearch, label: 'Job / Freelance Search',
      description: "I'll find real job openings and freelance opportunities for your skills.",
      emoji: '💼', color: const Color(0xFF0984E3), confidence: 0.90);

  if (has(['i want to sell','i am selling','i sell','selling my','sell my','list my',
            'post my','want to sell','help me sell']))
    return IntentResult(intent: TaskIntent.marketplacePost, label: 'Post a Listing',
      description: "I'll take you to the marketplace to list what you're selling.",
      emoji: '💰', color: AppColors.success, confidence: 0.85);

  if (has(['how to learn','learn to','learn how to','teach me','course for','tutorial on',
            'beginner guide','explain how','what is']))
    return IntentResult(intent: TaskIntent.learnSkill, label: 'Learning & Guidance',
      description: "I'll give you a clear step-by-step guide to learn or get started.",
      emoji: '📚', color: const Color(0xFFFD79A8), confidence: 0.80);

  if (has(['how to start','how to build','how to create','how to launch','business idea',
            'side hustle','start a business','open a','set up a','business plan']))
    return IntentResult(intent: TaskIntent.businessResearch, label: 'Business Research',
      description: "I'll research this business model and create a full execution workflow.",
      emoji: '🔬', color: const Color(0xFF9B59B6), confidence: 0.82);

  if (has(['i want to earn','make money from','income from','i want to start earning',
            'my goal is to earn','passive income','per month','monthly income','earn \$','make \$']))
    return IntentResult(intent: TaskIntent.incomeGoal, label: 'Income Goal',
      description: "I'll research this income path and build your full workflow.",
      emoji: '🚀', color: AppColors.primary, confidence: 0.95);

  if (text.trim().endsWith('?') ||
      has(['what','why','when','who','where','which','can i','is it']))
    return IntentResult(intent: TaskIntent.quickAnswer, label: 'Quick Answer',
      description: "I'll answer this directly with specific, useful information.",
      emoji: '💡', color: const Color(0xFFFDCB6E), confidence: 0.70);

  return IntentResult(intent: TaskIntent.incomeGoal, label: 'Income Workflow',
    description: "I'll research this goal and build your personalized income execution plan.",
    emoji: '⚡', color: AppColors.primary, confidence: 0.60);
}

// ═══════════════════════════════════════════════════════════
// CHAT MESSAGE
// ═══════════════════════════════════════════════════════════

class ChatMessage {
  final String   role, content;
  final DateTime timestamp;
  ChatMessage({required this.role, required this.content}) : timestamp = DateTime.now();
}

// ═══════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════

enum _Phase { input, confirming, researching, review, creating, done, agentMode }

final workflowResearchProvider =
    StateNotifierProvider<WorkflowResearchNotifier, WorkflowResearchState>(
        (ref) => WorkflowResearchNotifier(ref));

class WorkflowResearchState {
  final _Phase               phase;
  final String               goal, currency, language;
  final double               budget, hoursPerDay;
  final String?              timezone;
  final List<String>         skills;
  final Map<String, dynamic> research;
  final String               error;
  final bool                 isLoading, brainUsed;
  final IntentResult?        detectedIntent;
  final String               agentOutput;
  final List<ChatMessage>    chatHistory;
  final bool                 chatLoading;

  const WorkflowResearchState({
    this.phase = _Phase.input,
    this.goal  = '', this.budget = 0, this.hoursPerDay = 2,
    this.currency = 'USD', this.language = 'en',
    this.timezone,
    this.skills   = const [],
    this.research = const {},
    this.error    = '', this.isLoading = false, this.brainUsed = false,
    this.detectedIntent,
    this.agentOutput = '',
    this.chatHistory  = const [],
    this.chatLoading  = false,
  });

  WorkflowResearchState copyWith({
    _Phase? phase, String? goal, double? budget, double? hoursPerDay,
    String? currency, String? language, String? timezone, List<String>? skills,
    Map<String, dynamic>? research, String? error, bool? isLoading,
    bool? brainUsed, IntentResult? detectedIntent, String? agentOutput,
    List<ChatMessage>? chatHistory, bool? chatLoading,
  }) => WorkflowResearchState(
    phase:          phase          ?? this.phase,
    goal:           goal           ?? this.goal,
    budget:         budget         ?? this.budget,
    hoursPerDay:    hoursPerDay    ?? this.hoursPerDay,
    currency:       currency       ?? this.currency,
    language:       language       ?? this.language,
    timezone:       timezone       ?? this.timezone,
    skills:         skills         ?? this.skills,
    research:       research       ?? this.research,
    error:          error          ?? this.error,
    isLoading:      isLoading      ?? this.isLoading,
    brainUsed:      brainUsed      ?? this.brainUsed,
    detectedIntent: detectedIntent ?? this.detectedIntent,
    agentOutput:    agentOutput    ?? this.agentOutput,
    chatHistory:    chatHistory    ?? this.chatHistory,
    chatLoading:    chatLoading    ?? this.chatLoading,
  );
}

class WorkflowResearchNotifier extends StateNotifier<WorkflowResearchState> {
  final Ref                  _ref;
  final TextEditingController goalController = TextEditingController();

  WorkflowResearchNotifier(this._ref) : super(const WorkflowResearchState()) { _init(); }

  void _init() {
    try {
      final locale   = _ref.read(localeProvider);
      final currency = _ref.read(currencyProvider);
      state = state.copyWith(
        language: locale.languageCode,
        currency: currency,
        timezone: DateTime.now().timeZoneName,
      );
    } catch (_) {}
  }

  void updateBudget(double v)      => state = state.copyWith(budget: v,       error: '');
  void updateHoursPerDay(double v) => state = state.copyWith(hoursPerDay: v);
  void addSkill(String s)    { if (!state.skills.contains(s)) state = state.copyWith(skills: [...state.skills, s]); }
  void removeSkill(String s) => state = state.copyWith(skills: state.skills.where((x) => x != s).toList());

  void updateCurrency(String v) {
    state = state.copyWith(currency: v);
    const regionMap = {
      'NGN': 'africa_west', 'GHS': 'africa_west', 'KES': 'africa_east',
      'ZAR': 'africa_south','INR': 'south_asia',   'BRL': 'latin_america',
      'MXN': 'latin_america',
    };
    final region = regionMap[v];
    if (region != null) {
      try { _ref.read(localeProvider.notifier).setLocaleFromRegion(region); } catch (_) {}
    }
  }

  void goBack() {
    if (state.phase != _Phase.input) state = state.copyWith(phase: _Phase.input, error: '');
  }

  void analyzeInput() {
    final text = goalController.text.trim();
    if (text.length < 5) {
      state = state.copyWith(error: 'Tell me a bit more — at least 5 characters');
      return;
    }
    state = state.copyWith(goal: text, detectedIntent: detectIntent(text),
        phase: _Phase.confirming, error: '');
  }

  Future<void> executeIntent(BuildContext context) async {
    switch (state.detectedIntent?.intent ?? TaskIntent.incomeGoal) {
      case TaskIntent.incomeGoal:
      case TaskIntent.businessResearch:
        await startResearch();
        break;
      case TaskIntent.marketplacePost:
        state = state.copyWith(phase: _Phase.input);
        if (context.mounted) context.push('/marketplace');
        break;
      default:
        await _runQuickAgent(context);
    }
  }

  void forceWorkflow() {
    state = state.copyWith(detectedIntent: const IntentResult(
      intent: TaskIntent.incomeGoal, label: 'Income Workflow',
      description: 'Building your personalized income execution plan.',
      emoji: '⚡', color: AppColors.primary, confidence: 1.0));
    startResearch();
  }

  Future<void> startResearch() async {
    state = state.copyWith(phase: _Phase.researching, error: '', isLoading: true, brainUsed: false);
    await adManager.showInterstitial();
    try {
      final result = await api.post('/workflow/research', {
        'goal': state.goal, 'currency': state.currency,
        'available_hours_per_day': state.hoursPerDay, 'budget': state.budget,
        'language': state.language, 'timezone': state.timezone, 'skills': state.skills,
      });
      state = state.copyWith(
        research:  Map<String, dynamic>.from(result['research'] as Map? ?? {}),
        phase:     _Phase.review,
        isLoading: false,
        brainUsed: result['metadata']?['brain_used'] == true,
      );
    } catch (e) {
      state = state.copyWith(error: 'Research failed. Check your connection and try again.',
          phase: _Phase.input, isLoading: false);
    }
  }

  Future<void> _runQuickAgent(BuildContext context) async {
    if (!adManager.canUseAgent) {
      final unlocked = await adManager.watchAdForAgentUse(context);
      if (!unlocked) {
        state = state.copyWith(error: 'Daily AI limit reached. Watch an ad to continue.',
            phase: _Phase.confirming);
        return;
      }
    }
    state = state.copyWith(phase: _Phase.researching, isLoading: true, error: '');
    await adManager.showInterstitial();
    adManager.recordAgentUse();
    try {
      final result = await api.quickAgent(state.goal);
      final output = result['output']?.toString() ?? result.toString();
      state = state.copyWith(
        agentOutput: output,
        chatHistory: [ChatMessage(role: 'assistant', content: output)],
        phase:       _Phase.agentMode,
        isLoading:   false,
      );
    } catch (e) {
      state = state.copyWith(error: 'Could not get answer. Please try again.',
          phase: _Phase.input, isLoading: false);
    }
  }

  Future<void> sendFollowUp(String message) async {
    if (message.trim().isEmpty || state.chatLoading) return;
    if (!adManager.canUseAgent) return;
    final userMsg = ChatMessage(role: 'user', content: message.trim());
    state = state.copyWith(chatHistory: [...state.chatHistory, userMsg], chatLoading: true);
    adManager.recordAgentUse();
    try {
      final history = state.chatHistory
          .map((m) => '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}')
          .join('\n\n');
      final ctx    = 'Original question: ${state.goal}\n\n$history\n\nFollow-up: ${message.trim()}';
      final result = await api.quickAgent(ctx);
      final reply  = result['output']?.toString() ?? result.toString();
      state = state.copyWith(
        chatHistory: [...state.chatHistory, ChatMessage(role: 'assistant', content: reply)],
        chatLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        chatHistory: [...state.chatHistory, ChatMessage(role: 'assistant', content: "Sorry, couldn't get a response. Try again.")],
        chatLoading: false,
      );
    }
  }

  Future<void> createWorkflow(BuildContext context) async {
    state = state.copyWith(phase: _Phase.creating, isLoading: true);
    try {
      final result = await api.post('/workflow/create', {
        'title':         state.research['title'] ?? 'My Income Workflow',
        'goal':          state.goal,
        'income_type':   state.research['income_type'] ?? 'other',
        'research_data': state.research,
        'currency':      state.currency,
        'language':      state.language,
        'timezone':      state.timezone,
      });
      final wfId = result['workflow_id']?.toString() ?? '';
      state = state.copyWith(phase: _Phase.done, isLoading: false);
      if (wfId.isNotEmpty) {
        api.recordInteractionSignal(action: 'workflow_created', postId: wfId, postContent: '');
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!adManager.isPremium) await adManager.forceInterstitial();
      if (context.mounted && wfId.isNotEmpty) context.pushReplacement('/workflow/$wfId');
    } catch (e) {
      state = state.copyWith(error: 'Failed to create workflow. Please try again.',
          phase: _Phase.review, isLoading: false);
    }
  }

  void reset() { state = const WorkflowResearchState(); goalController.clear(); _init(); }

  @override
  void dispose() { goalController.dispose(); super.dispose(); }
}

// ═══════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════

class WorkflowResearchScreen extends ConsumerStatefulWidget {
  const WorkflowResearchScreen({super.key});

  @override
  ConsumerState<WorkflowResearchScreen> createState() => _WorkflowResearchScreenState();
}

class _WorkflowResearchScreenState extends ConsumerState<WorkflowResearchScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(workflowResearchProvider.notifier).reset());
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);

    const titles = {
      _Phase.input:      'What do you need?',
      _Phase.confirming: 'Does this sound right?',
      _Phase.researching:'Working on it...',
      _Phase.review:     'Your Plan',
      _Phase.agentMode:  "Here's Your Answer",
      _Phase.creating:   'Building Workflow',
      _Phase.done:       'Done!',
    };

    return PopScope(
      canPop: state.phase == _Phase.input,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) notifier.goBack(); },
      child: Scaffold(
        backgroundColor:          isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF6F6FA),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor:    isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF6F6FA),
          elevation:          0,
          surfaceTintColor:   Colors.transparent,
          centerTitle:        true,
          leading: IconButton(
            icon: Icon(Iconsax.arrow_left,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: state.phase == _Phase.input
                ? () => context.pop()
                : notifier.goBack,
          ),
          title: Text(titles[state.phase] ?? 'Workflow',
              style: TextStyle(
                  fontSize:   16,
                  fontWeight: FontWeight.w700,
                  color:      isDark ? Colors.white : Colors.black87)),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child:   SlideTransition(
              position: Tween<Offset>(
                  begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: _buildPhase(state, notifier, isDark),
        ),
      ),
    );
  }

  Widget _buildPhase(WorkflowResearchState s, WorkflowResearchNotifier n, bool isDark) {
    switch (s.phase) {
      case _Phase.input:       return _InputPhase(key: const ValueKey('i'), isDark: isDark);
      case _Phase.confirming:  return _ConfirmPhase(key: const ValueKey('c'), isDark: isDark);
      case _Phase.researching: return _LoadingPhase(key: const ValueKey('l'), intent: s.detectedIntent);
      case _Phase.review:      return _ReviewPhase(key: const ValueKey('r'), isDark: isDark);
      case _Phase.agentMode:   return _AgentOutputPhase(key: const ValueKey('a'), isDark: isDark);
      case _Phase.creating:    return const _CreatingPhase(key: ValueKey('cr'));
      case _Phase.done:        return const _DonePhase(key: ValueKey('d'));
    }
  }
}

// ═══════════════════════════════════════════════════════════
// PHASE 1 — INPUT (live intent badge, grouped examples)
// ═══════════════════════════════════════════════════════════

class _InputPhase extends ConsumerStatefulWidget {
  final bool isDark;
  const _InputPhase({super.key, required this.isDark});

  @override
  ConsumerState<_InputPhase> createState() => _InputPhaseState();
}

class _InputPhaseState extends ConsumerState<_InputPhase> {
  bool          _showAdvanced  = false;
  Timer?        _debounce;
  IntentResult? _previewIntent;
  bool          _hasText       = false;

  static const _currencies = ['USD','EUR','GBP','NGN','GHS','KES','ZAR','INR','PKR','BDT','PHP','IDR','BRL','MXN','EGP','TRY','USDT'];
  static const _skills     = ['Writing','Design','Coding','Video Editing','Marketing','Sales','Translation','Data Entry','Photography','Social Media'];
  static const _examples   = [
    '💡 I want to start a YouTube channel',
    '📱 Find contacts of phone sellers in Lagos',
    '💼 Freelance design jobs online',
    '🛒 Where to source phones cheaply',
    '💰 I want to earn \$500/month from home',
    '🔬 How to start dropshipping',
  ];

  @override
  void initState() {
    super.initState();
    ref.read(workflowResearchProvider.notifier).goalController
        .addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final notifier = ref.read(workflowResearchProvider.notifier);
    final text     = notifier.goalController.text.trim();
    setState(() => _hasText = text.length >= 3);
    _debounce?.cancel();
    if (text.length >= 6) {
      _debounce = Timer(const Duration(milliseconds: 380), () {
        if (mounted) setState(() => _previewIntent = detectIntent(text));
      });
    } else {
      if (mounted) setState(() => _previewIntent = null);
    }
  }

  Future<void> _onAnalyse(WorkflowResearchNotifier notifier) async {
    final text = notifier.goalController.text.trim();
    if (text.length < 5) { notifier.analyzeInput(); return; }
    final intent     = detectIntent(text).intent;
    final isWorkflow = intent == TaskIntent.incomeGoal || intent == TaskIntent.businessResearch;
    if (isWorkflow && !adManager.canCreateWorkflow) {
      await _showLimitDialog(); return;
    }
    notifier.analyzeInput();
  }

  Future<void> _showLimitDialog() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
        decoration: BoxDecoration(
            color:        isDark ? const Color(0xFF1A1A20) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: AppRadius.pill)),
          const SizedBox(height: 20),
          const Text('🚀', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Free Workflow Limit Reached',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Watch a short ad to continue free, or upgrade to Pro.',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final ok = await adManager.watchAdForWorkflow(context);
                if (ok && mounted) ref.read(workflowResearchProvider.notifier).analyzeInput();
              },
              icon:  const Icon(Iconsax.play_circle),
              label: const Text('Watch Ad & Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill)),
            )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); context.push('/upgrade'); },
              icon:  const Icon(Iconsax.crown, color: AppColors.warning),
              label: const Text('Upgrade to Pro'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning, side: const BorderSide(color: AppColors.warning),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pill)),
            )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final isDark   = widget.isDark;
    final bg       = isDark ? const Color(0xFF141418) : Colors.white;
    final surface  = isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F6);
    final txt      = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Main card ──────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
                blurRadius: 20, offset: const Offset(0, 5))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title + live badge
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tell me what you need',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: txt)),
                    const SizedBox(height: 2),
                    Text("Ask anything — I'll figure out the best way to help",
                        style: TextStyle(fontSize: 12, color: sub)),
                  ])),
                  if (_previewIntent != null) ...[
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color:  _previewIntent!.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _previewIntent!.color.withOpacity(0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_previewIntent!.emoji, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          _previewIntent!.label.split(' ').first,
                          style: TextStyle(color: _previewIntent!.color,
                              fontSize: 10, fontWeight: FontWeight.w700)),
                      ])).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9)),
                  ],
                ]),
                const SizedBox(height: 14),

                // Textarea
                Container(
                  decoration: BoxDecoration(
                    color: surface, borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasText ? AppColors.primary.withOpacity(0.4) : Colors.transparent,
                      width: 1.5)),
                  child: TextField(
                    controller:              notifier.goalController,
                    maxLines:                5, minLines: 3,
                    textCapitalization:      TextCapitalization.sentences,
                    style: TextStyle(fontSize: 15, color: txt, height: 1.55),
                    onSubmitted: (_) { HapticFeedback.mediumImpact(); _onAnalyse(notifier); },
                    decoration: InputDecoration(
                      hintText: 'e.g. "I want to earn from YouTube" or "find phone sellers in Lagos"\n\nBe specific — the more detail, the better your plan.',
                      hintStyle: TextStyle(color: sub.withOpacity(0.55), fontSize: 12, height: 1.5),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16)),
                  ),
                ),
              ]),
            ),

            if (state.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Row(children: [
                  const Icon(Iconsax.warning_2, color: AppColors.error, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(state.error,
                      style: const TextStyle(color: AppColors.error, fontSize: 12))),
                ])),

            const SizedBox(height: 14),

            // Example chips
            Padding(padding: const EdgeInsets.only(left: 18),
              child: Text('Try these:',
                  style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w500))),
            const SizedBox(height: 7),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _examples.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (_, i) {
                  final ex = _examples[i];
                  return GestureDetector(
                    onTap: () {
                      final stripped = ex.substring(ex.indexOf(' ') + 1);
                      notifier.goalController.text = stripped;
                      notifier.goalController.selection = TextSelection.fromPosition(
                          TextPosition(offset: stripped.length));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withOpacity(0.18))),
                      child: Text(ex,
                          style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w500)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Analyse button
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () { HapticFeedback.mediumImpact(); _onAnalyse(notifier); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: _hasText
                          ? const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)])
                          : LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade500]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _hasText ? [BoxShadow(
                        color: const Color(0xFF6C5CE7).withOpacity(0.28),
                        blurRadius: 14, offset: const Offset(0, 5))] : []),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Iconsax.flash, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _previewIntent != null
                            ? 'Analyse & Execute ${_previewIntent!.emoji}'
                            : 'Analyse & Execute',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ).animate().fadeIn(duration: 280.ms),

        const SizedBox(height: 14),

        // ── Advanced Settings ──────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Row(children: [
              const Icon(Iconsax.setting_2, color: AppColors.primary, size: 16),
              const SizedBox(width: 10),
              Text('Advanced Settings', style: TextStyle(color: txt, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(_showAdvanced ? Iconsax.arrow_up_2 : Iconsax.arrow_down, color: sub, size: 15),
            ]),
          ),
        ),

        AnimatedCrossFade(
          duration:       const Duration(milliseconds: 220),
          crossFadeState: _showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild:     const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Skills', style: TextStyle(color: txt, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6,
                  children: _skills.map((s) {
                    final sel = state.skills.contains(s);
                    return FilterChip(label: Text(s, style: const TextStyle(fontSize: 11)),
                      selected: sel,
                      onSelected: (v) => v ? notifier.addSkill(s) : notifier.removeSkill(s),
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      checkmarkColor: AppColors.primary);
                  }).toList()),
                const SizedBox(height: 14),
                Divider(color: sub.withOpacity(0.12)),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Iconsax.wallet, color: AppColors.primary, size: 14), const SizedBox(width: 6),
                  Text('Starting Budget', style: TextStyle(color: txt, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(state.budget == 0 ? '${state.currency} 0 (Free)' : '${state.currency} ${state.budget.toStringAsFixed(0)}',
                      style: TextStyle(color: state.budget == 0 ? AppColors.success : AppColors.primary,
                          fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                Slider(value: state.budget, min: 0, max: 500, divisions: 50,
                  activeColor: AppColors.primary, onChanged: notifier.updateBudget),
                Row(children: [
                  const Icon(Iconsax.clock, color: AppColors.accent, size: 14), const SizedBox(width: 6),
                  Text('Daily Time', style: TextStyle(color: txt, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${state.hoursPerDay.toStringAsFixed(1)}h/day',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                Slider(value: state.hoursPerDay, min: 0.5, max: 12, divisions: 23,
                  activeColor: AppColors.accent, onChanged: notifier.updateHoursPerDay),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Iconsax.money, color: AppColors.textMuted, size: 14), const SizedBox(width: 6),
                  Text('Currency', style: TextStyle(color: txt, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6,
                  children: _currencies.map((c) {
                    final sel = state.currency == c;
                    return GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); notifier.updateCurrency(c); },
                      child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.primary : sub.withOpacity(0.3))),
                        child: Text(c,
                            style: TextStyle(color: sel ? Colors.white : sub,
                                fontSize: 12, fontWeight: FontWeight.w600))));
                  }).toList()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PHASE 2 — CONFIRM
// ═══════════════════════════════════════════════════════════

class _ConfirmPhase extends ConsumerWidget {
  final bool isDark;
  const _ConfirmPhase({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final intent   = state.detectedIntent!;
    final bg       = isDark ? const Color(0xFF141418) : Colors.white;
    final txt      = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;
    final surface  = isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F6);

    List<String> actionPreview() {
      switch (intent.intent) {
        case TaskIntent.incomeGoal:
        case TaskIntent.businessResearch:
          return ['Search RiseUp brain for proven methods', 'Analyze income potential in your region',
            'Find free tools available in your country', 'Build a step-by-step execution plan'];
        case TaskIntent.contactSearch:
          return ['Search directories for matching contacts', 'Return names, phone & WhatsApp details', 'Filter by location and criteria'];
        case TaskIntent.jobSearch:
          return ['Search live job boards & freelance platforms', 'Find openings matching your skills', 'Show application links & salary ranges'];
        case TaskIntent.productSourcing:
          return ['Find local & international suppliers', 'Compare prices & MOQ', 'Show trusted platforms for your region'];
        case TaskIntent.learnSkill:
          return ['Create a structured learning roadmap', 'Find free and paid resources', 'Estimate time to proficiency'];
        default:
          return ['Research this topic thoroughly', 'Provide a direct, specific answer'];
      }
    }

    String btnLabel() {
      switch (intent.intent) {
        case TaskIntent.contactSearch:   return 'Search contacts';
        case TaskIntent.jobSearch:       return 'Find jobs for me';
        case TaskIntent.productSourcing: return 'Find suppliers';
        case TaskIntent.marketplacePost: return 'Go to marketplace';
        case TaskIntent.learnSkill:      return 'Get the guide';
        case TaskIntent.quickAnswer:     return 'Get the answer';
        case TaskIntent.businessResearch:return 'Research this business';
        default:                         return 'Build my income workflow';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Intent card
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: intent.color.withOpacity(0.35), width: 1.5),
            boxShadow: [BoxShadow(color: intent.color.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 50, height: 50,
                decoration: BoxDecoration(color: intent.color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(intent.emoji, style: const TextStyle(fontSize: 26)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: intent.color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('I understand you want to:',
                      style: TextStyle(fontSize: 10, color: intent.color, fontWeight: FontWeight.w600))),
                const SizedBox(height: 5),
                Text(intent.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: txt)),
              ])),
            ]),
            const SizedBox(height: 12),
            Text(intent.description, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
            const SizedBox(height: 10),
            Row(children: [
              Text('Confidence: ', style: TextStyle(fontSize: 11, color: sub)),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: intent.confidence,
                  backgroundColor: surface,
                  valueColor: AlwaysStoppedAnimation(intent.color), minHeight: 4))),
              const SizedBox(width: 6),
              Text('${(intent.confidence * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: intent.color, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Iconsax.quote_down_circle, color: sub, size: 14), const SizedBox(width: 8),
                Expanded(child: Text('"${state.goal}"',
                    style: TextStyle(fontSize: 12, color: sub, fontStyle: FontStyle.italic, height: 1.4))),
              ])),
            const SizedBox(height: 12),
            Text("What I'll do:", style: TextStyle(fontSize: 12, color: txt, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            ...actionPreview().map((step) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Iconsax.tick_circle, color: intent.color, size: 13), const SizedBox(width: 8),
                Expanded(child: Text(step, style: TextStyle(fontSize: 11, color: sub, height: 1.4))),
              ]))),
            if (!adManager.isPremium &&
                intent.intent != TaskIntent.incomeGoal &&
                intent.intent != TaskIntent.businessResearch) ...[
              const SizedBox(height: 12),
              _AgentUsageChip(isDark: isDark, color: intent.color),
            ],
          ]),
        ).animate().fadeIn().scale(begin: const Offset(0.97, 0.97)),

        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () { HapticFeedback.mediumImpact(); notifier.executeIntent(context); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [intent.color, intent.color.withOpacity(0.75)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: intent.color.withOpacity(0.28), blurRadius: 14, offset: const Offset(0, 5))]),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(intent.emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 10),
                Text(btnLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ])),
          )).animate().fadeIn(delay: 80.ms).slideY(begin: 0.08),

        const SizedBox(height: 10),

        if (intent.intent != TaskIntent.incomeGoal && intent.intent != TaskIntent.businessResearch)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { HapticFeedback.lightImpact(); notifier.forceWorkflow(); },
              icon:  const Icon(Iconsax.flash, color: AppColors.primary, size: 14),
              label: const Text('Build a full income workflow instead',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),

        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: notifier.goBack,
          icon:  Icon(Iconsax.edit_2, color: sub, size: 14),
          label: Text('Edit my request', style: TextStyle(color: sub, fontSize: 13))),
      ]),
    );
  }
}

class _AgentUsageChip extends StatelessWidget {
  final bool isDark; final Color color;
  const _AgentUsageChip({required this.isDark, required this.color});
  @override
  Widget build(BuildContext context) {
    final remaining = adManager.agentUsesRemaining;
    final clr = remaining > 0 ? color : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: clr.withOpacity(0.08), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clr.withOpacity(0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Iconsax.cpu, color: clr, size: 12), const SizedBox(width: 5),
        Text(remaining > 0 ? '$remaining free AI use${remaining == 1 ? "" : "s"} left today' : 'No free AI uses left today',
            style: TextStyle(color: clr, fontSize: 10, fontWeight: FontWeight.w600)),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════
// PHASE 3 — LOADING
// ═══════════════════════════════════════════════════════════

class _LoadingPhase extends StatefulWidget {
  final IntentResult? intent;
  const _LoadingPhase({super.key, required this.intent});
  @override State<_LoadingPhase> createState() => _LoadingPhaseState();
}

class _LoadingPhaseState extends State<_LoadingPhase> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  int    _msgIdx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 1900), (_) {
      if (mounted) setState(() => _msgIdx = (_msgIdx + 1) % _messages.length);
    });
  }

  @override
  void dispose() { _pulse.dispose(); _timer?.cancel(); super.dispose(); }

  bool get _isWorkflow {
    final i = widget.intent?.intent;
    return i == null || i == TaskIntent.incomeGoal || i == TaskIntent.businessResearch;
  }

  List<String> get _messages => _isWorkflow ? [
    '🧠 Searching RiseUp brain for proven methods...',
    '🔍 Researching what\'s working in 2025/2026...',
    '📊 Analyzing income potential in your region...',
    '🛠️ Finding free tools available in your country...',
    '⚡ Identifying what AI can automate for you...',
    '📋 Assembling your personalized step-by-step plan...',
  ] : [
    '🔎 Understanding exactly what you need...',
    '🧠 Searching RiseUp brain for best matches...',
    '🌍 Scanning relevant sources and directories...',
    '✨ Preparing your personalized results...',
  ];

  @override
  Widget build(BuildContext context) {
    final color = widget.intent?.color ?? AppColors.primary;
    final emoji = widget.intent?.emoji ?? '⚡';
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Transform.scale(
            scale: 1.0 + _pulse.value * 0.06,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [BoxShadow(color: color.withOpacity(0.3 + _pulse.value * 0.18), blurRadius: 24, offset: const Offset(0, 6))]),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 38)))),
          )),
        const SizedBox(height: 26),
        Text(_isWorkflow ? 'Deep Research in Progress' : 'Working on it...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 8),
        Text(
          _isWorkflow
              ? 'AI is analyzing your goal, researching your region, and building a real execution plan.'
              : 'Finding exactly what you need — this takes just a moment.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(key: ValueKey(_msgIdx), _messages[_msgIdx],
              style: TextStyle(fontSize: 13, color: color.withOpacity(0.85)),
              textAlign: TextAlign.center)),
        const SizedBox(height: 20),
        SizedBox(width: 200, child: LinearProgressIndicator(
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
          borderRadius: BorderRadius.circular(4))),
      ])));
  }
}

// ═══════════════════════════════════════════════════════════
// PHASE 4a — AGENT OUTPUT + CHAT
// ═══════════════════════════════════════════════════════════

class _AgentOutputPhase extends ConsumerStatefulWidget {
  final bool isDark;
  const _AgentOutputPhase({super.key, required this.isDark});
  @override ConsumerState<_AgentOutputPhase> createState() => _AgentOutputPhaseState();
}

class _AgentOutputPhaseState extends ConsumerState<_AgentOutputPhase> {
  final _chatCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool  _focused    = false;

  @override void dispose() { _chatCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(WorkflowResearchNotifier notifier) async {
    final txt = _chatCtrl.text.trim();
    if (txt.isEmpty) return;
    if (!adManager.canUseAgent) {
      final ok = await adManager.watchAdForAgentUse(context);
      if (!ok) return;
    }
    _chatCtrl.clear();
    HapticFeedback.lightImpact();
    await notifier.sendFollowUp(txt);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final intent   = state.detectedIntent!;
    final isDark   = widget.isDark;
    final surface  = isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F6);
    final sub      = isDark ? Colors.white54 : Colors.black45;
    final inputBg  = isDark ? const Color(0xFF1A1A20) : Colors.white;

    if (state.chatHistory.isNotEmpty) _scrollToBottom();

    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: intent.color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(intent.emoji, style: const TextStyle(fontSize: 12)), const SizedBox(width: 5),
                  Text(intent.label, style: TextStyle(color: intent.color, fontSize: 11, fontWeight: FontWeight.w700)),
                ])),
              const Spacer(),
              if (state.chatHistory.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: state.chatHistory.first.content));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Copied ✅'), backgroundColor: AppColors.success,
                        duration: Duration(seconds: 2)));
                  },
                  child: Padding(padding: const EdgeInsets.all(6), child: Icon(Iconsax.copy, color: sub, size: 17))),
            ]),
            const SizedBox(height: 10),

            ...state.chatHistory.asMap().entries.map((e) => _ChatBubble(
              key: ValueKey('msg_${e.key}'), message: e.value,
              isUser: e.value.role == 'user', isDark: isDark, accentColor: intent.color,
            ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04)),

            if (state.chatLoading)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(color: surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4), topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
                  child: _TypingDots(color: intent.color))).animate().fadeIn(),

            if (!adManager.isPremium) ...[
              const SizedBox(height: 8),
              _ChatUsageBanner(isDark: isDark, color: intent.color),
            ],
            const SizedBox(height: 12),

            // Build workflow upsell card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.07), AppColors.accent.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Text('⚡', style: TextStyle(fontSize: 14)), SizedBox(width: 8),
                  Text('Want a full income plan?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                ]),
                const SizedBox(height: 3),
                Text('Build a step-by-step AI workflow to execute this properly and track your earnings.',
                    style: TextStyle(fontSize: 11, color: sub)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () { HapticFeedback.mediumImpact(); notifier.forceWorkflow(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Iconsax.flash, color: Colors.white, size: 14), SizedBox(width: 7),
                      Text('Build Income Workflow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]))),
              ])),
            const SizedBox(height: 6),
          ],
        ),
      ),

      // Sticky chat input
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F0F13) : const Color(0xFFEFEFF4),
          border: Border(top: BorderSide(color: (isDark ? Colors.white : Colors.black).withOpacity(0.07))),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -3))]),
        padding: EdgeInsets.fromLTRB(12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: inputBg, borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _focused ? intent.color.withOpacity(0.5) : (isDark ? Colors.white12 : Colors.black12),
                  width: _focused ? 1.5 : 1.0),
                boxShadow: _focused ? [BoxShadow(color: intent.color.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))] : []),
              child: Focus(
                onFocusChange: (v) => setState(() => _focused = v),
                child: TextField(
                  controller: _chatCtrl, maxLines: 3, minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText:  'Ask a follow-up question...',
                    hintStyle: TextStyle(color: sub.withOpacity(0.6), fontSize: 13),
                    border:    InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  onSubmitted: (_) => _send(notifier)),
              )),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: state.chatLoading ? null : () => _send(notifier),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: state.chatLoading ? null : LinearGradient(colors: [intent.color, intent.color.withOpacity(0.75)]),
                color: state.chatLoading ? sub.withOpacity(0.15) : null,
                shape: BoxShape.circle,
                boxShadow: state.chatLoading ? [] : [BoxShadow(color: intent.color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
              child: state.chatLoading
                  ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                  : const Icon(Iconsax.send_1, color: Colors.white, size: 18))),
        ]),
      ),
    ]);
  }
}

class _ChatUsageBanner extends StatelessWidget {
  final bool isDark; final Color color;
  const _ChatUsageBanner({required this.isDark, required this.color});
  @override
  Widget build(BuildContext context) {
    final remaining = adManager.agentUsesRemaining;
    if (remaining > 1) return const SizedBox.shrink();
    final clr = remaining > 0 ? AppColors.warning : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: clr.withOpacity(0.07), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: clr.withOpacity(0.2))),
      child: Row(children: [
        Icon(remaining > 0 ? Iconsax.warning_2 : Iconsax.cpu, color: clr, size: 12),
        const SizedBox(width: 8),
        Expanded(child: Text(remaining > 0 ? '$remaining follow-up left today' : 'Follow-ups used up today',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.w600))),
        if (remaining == 0)
          GestureDetector(
            onTap: () async {
              final ok = await adManager.watchAdForAgentUse(context);
              if (ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('✅ Follow-up unlocked!'), backgroundColor: AppColors.success));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: clr.withOpacity(0.1), borderRadius: AppRadius.pill,
                border: Border.all(color: clr.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Iconsax.play_circle, color: clr, size: 10), const SizedBox(width: 3),
                Text('Watch Ad', style: TextStyle(color: clr, fontSize: 9, fontWeight: FontWeight.w700)),
              ]))),
      ]));
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message; final bool isUser, isDark; final Color accentColor;
  const _ChatBubble({super.key, required this.message, required this.isUser, required this.isDark, required this.accentColor});
  @override
  Widget build(BuildContext context) {
    final bg  = isUser ? accentColor : (isDark ? const Color(0xFF1E1E26) : const Color(0xFFEEEEF4));
    final clr = isUser ? Colors.white : (isDark ? Colors.white : Colors.black87);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft:     Radius.circular(isUser ? 16 : 4),
            topRight:    Radius.circular(isUser ? 4  : 16),
            bottomLeft:  const Radius.circular(16),
            bottomRight: const Radius.circular(16)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]),
        child: SelectableText(message.content,
            style: TextStyle(fontSize: 13.5, color: clr, height: 1.55))));
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});
  @override State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t     = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
        final scale = 0.6 + (t < 0.5 ? t : 1 - t) * 0.8;
        return Container(margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 7 * scale, height: 7 * scale,
          decoration: BoxDecoration(color: widget.color.withOpacity(0.7), shape: BoxShape.circle));
      })));
}

// ═══════════════════════════════════════════════════════════
// PHASE 4b — REVIEW
// ═══════════════════════════════════════════════════════════

class _ReviewPhase extends ConsumerWidget {
  final bool isDark;
  const _ReviewPhase({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final d        = state.research;
    final bg       = isDark ? const Color(0xFF141418) : Colors.white;
    final txt      = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;
    final surface  = isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F6);

    final score        = d['viability_score']                        as int?    ?? 75;
    final timeline     = d['realistic_timeline']?.toString()                    ?? '';
    final warning      = d['honest_warning']?.toString()                        ?? '';
    final currency     = d['potential_monthly_income']?['currency']             ?? state.currency;
    final potMin       = d['potential_monthly_income']?['min']                  ?? 0;
    final potMax       = d['potential_monthly_income']?['max']                  ?? 0;
    final brainMethods = (d['brain_matched_methods']  as List? ?? []);
    final working      = (d['what_is_working_now']    as List? ?? []);
    final regional     = (d['regional_opportunities'] as List? ?? []);
    final freeTools    = (d['free_tools']             as List? ?? []);
    final steps        = (d['step_by_step_workflow']  as List? ?? []);
    final aiCan        = (d['breakdown']?['ai_can_do']    as List? ?? []);
    final userMust     = (d['breakdown']?['user_must_do'] as List? ?? []);

    Widget sTitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 10),
      child: Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: txt)));

    Widget bullet(String t, Color c) => Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Iconsax.tick_circle, color: c, size: 13), const SizedBox(width: 8),
        Expanded(child: Text(t, style: TextStyle(fontSize: 12, color: sub, height: 1.4))),
      ]));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (state.brainUsed)
          Container(margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00B894)]),
              borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 10), SizedBox(width: 4),
              Text('🧠 Enhanced with RiseUp Brain', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ])),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Row(children: [
            SizedBox(width: 58, height: 58, child: Stack(children: [
              CircularProgressIndicator(value: score / 100, backgroundColor: surface,
                valueColor: const AlwaysStoppedAnimation(AppColors.success), strokeWidth: 5),
              Center(child: Text('$score', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 15))),
            ])),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['title']?.toString() ?? 'Your Workflow',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: txt), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                _SmTag('⏱ $timeline', AppColors.primary),
                _SmTag('$currency $potMin–$potMax/mo', AppColors.success),
              ]),
            ])),
          ])).animate().fadeIn(),
        const SizedBox(height: 16),

        if (brainMethods.isNotEmpty) ...[
          sTitle('🧠 Matched from RiseUp Brain'),
          Wrap(spacing: 8, runSpacing: 6,
            children: brainMethods.map((m) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.2))),
              child: Text(m.toString(), style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)))).toList()),
          const SizedBox(height: 16),
        ],
        if (regional.isNotEmpty)  ...[sTitle('🌍 Regional Opportunities'), ...regional.map((x) => bullet(x.toString(), AppColors.info)), const SizedBox(height: 16)],
        if (working.isNotEmpty)   ...[sTitle('📈 What\'s Working Right Now'), ...working.map((x) => bullet(x.toString(), AppColors.success)), const SizedBox(height: 16)],

        if (aiCan.isNotEmpty) ...[
          sTitle('⚡ What AI Can Do For You'),
          ...aiCan.map((item) { final m = item as Map;
            return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withOpacity(0.18))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🤖', style: TextStyle(fontSize: 16)), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['task']?.toString() ?? '', style: TextStyle(color: txt, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(m['how']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('Saves ${m['saves_hours']}h', style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700))),
              ]));
          }),
          const SizedBox(height: 16),
        ],

        if (userMust.isNotEmpty) ...[
          sTitle('👤 What You Must Do'),
          ...userMust.map((item) { final m = item as Map;
            return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.18))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🎯', style: TextStyle(fontSize: 16)), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['task']?.toString() ?? '', style: TextStyle(color: txt, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(m['why']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ])),
                Text(m['time_required']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
              ]));
          }),
          const SizedBox(height: 16),
        ],

        if (freeTools.isNotEmpty) ...[
          sTitle('🆓 Free Tools (Start at \$0)'),
          Wrap(spacing: 8, runSpacing: 8,
            children: freeTools.map((t) { final tool = t as Map;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.07), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withOpacity(0.22))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tool['name']?.toString() ?? '', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(tool['purpose']?.toString() ?? '', style: TextStyle(color: sub, fontSize: 10)),
                ]));
            }).toList()),
          const SizedBox(height: 16),
        ],

        if (steps.isNotEmpty) ...[
          sTitle('📋 Your ${steps.length}-Step Workflow'),
          ...steps.take(4).toList().asMap().entries.map((e) {
            final s = e.value as Map; final isAuto = s['type'] == 'automated';
            return Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (isAuto ? AppColors.primary : AppColors.warning).withOpacity(0.18))),
              child: Row(children: [
                Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: (isAuto ? AppColors.primary : AppColors.warning).withOpacity(0.1), shape: BoxShape.circle),
                  child: Center(child: Text('${e.key + 1}', style: TextStyle(
                    color: isAuto ? AppColors.primary : AppColors.warning, fontWeight: FontWeight.w700, fontSize: 11)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['title']?.toString() ?? '', style: TextStyle(color: txt, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(isAuto ? '🤖 AI handles this' : '👤 You do this',
                      style: TextStyle(color: isAuto ? AppColors.primary : AppColors.warning, fontSize: 10, fontWeight: FontWeight.w600)),
                ])),
                Text('${s['time_minutes'] ?? 30} min', style: TextStyle(color: sub, fontSize: 11)),
              ]));
          }),
          if (steps.length > 4)
            Padding(padding: const EdgeInsets.only(top: 3, bottom: 4),
              child: Text('+${steps.length - 4} more steps inside the workflow',
                  style: const TextStyle(fontSize: 12, color: AppColors.primary))),
          const SizedBox(height: 16),
        ],

        if (warning.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.07), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withOpacity(0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠️', style: TextStyle(fontSize: 13)), const SizedBox(width: 10),
              Expanded(child: Text(warning,
                  style: TextStyle(color: isDark ? Colors.orange.shade200 : Colors.orange.shade800, fontSize: 12, height: 1.5))),
            ])),
          const SizedBox(height: 16),
        ],

        if (!adManager.isPremium)
          Padding(padding: const EdgeInsets.only(bottom: 16), child: adManager.getBannerWidget()),

        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () { HapticFeedback.mediumImpact(); notifier.createWorkflow(context); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))]),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Iconsax.flash, color: Colors.white, size: 17), SizedBox(width: 8),
                Text('Create This Workflow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ])))).animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: TextButton.icon(
          onPressed: notifier.goBack,
          icon:  Icon(Iconsax.arrow_left, color: sub, size: 13),
          label: Text('Research a different goal', style: TextStyle(color: sub, fontSize: 13)))),
        const SizedBox(height: 40),
      ]),
    );
  }
}

class _SmTag extends StatelessWidget {
  final String label; final Color color;
  const _SmTag(this.label, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)));
}

// ═══════════════════════════════════════════════════════════
// PHASES 5 & 6
// ═══════════════════════════════════════════════════════════

class _CreatingPhase extends StatelessWidget {
  const _CreatingPhase({super.key});
  @override Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('⚡', style: TextStyle(fontSize: 60)).animate().scale(),
    const SizedBox(height: 16),
    const Text('Building Your Workflow...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    const Text('Setting up your personalized execution plan', style: TextStyle(color: AppColors.textSecondary)),
    const SizedBox(height: 20),
    const SizedBox(width: 180, child: LinearProgressIndicator(color: AppColors.primary)),
  ]));
}

class _DonePhase extends StatelessWidget {
  const _DonePhase({super.key});
  @override Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('✅', style: TextStyle(fontSize: 60)).animate().scale(),
    const SizedBox(height: 16),
    const Text('Workflow Created!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    const Text('Taking you there now...', style: TextStyle(color: AppColors.textSecondary)),
  ]));
}
