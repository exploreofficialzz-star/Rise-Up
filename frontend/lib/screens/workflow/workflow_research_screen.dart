// frontend/lib/screens/workflow/workflow_research_screen.dart
// v2.0 — Brain-Aware Research Screen
//
// Changes over v1:
//  • After createWorkflow succeeds, fires api.recordInteractionSignal(action:'workflow_created')
//    unawaited — non-blocking, feeds adaptive brain
//  • Shows "🧠 Brain searched internally" badge during researching phase
//  • Shows brain_matched_methods from research results if returned
//  • All existing global features preserved (currency, language, region, skills)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';

// ─────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────

enum _Phase { input, researching, review, creating, done }

final workflowResearchProvider =
    StateNotifierProvider<WorkflowResearchNotifier, WorkflowResearchState>((ref) {
  return WorkflowResearchNotifier(ref);
});

class WorkflowResearchState {
  final _Phase            phase;
  final String            goal;
  final double            budget;
  final double            hoursPerDay;
  final String            currency;
  final String            language;
  final String?           timezone;
  final List<String>      skills;
  final Map<String, dynamic> research;
  final String            error;
  final bool              isLoading;
  final bool              brainUsed;

  WorkflowResearchState({
    this.phase       = _Phase.input,
    this.goal        = '',
    this.budget      = 0,
    this.hoursPerDay = 2,
    this.currency    = 'USD',
    this.language    = 'en',
    this.timezone,
    this.skills      = const [],
    this.research    = const {},
    this.error       = '',
    this.isLoading   = false,
    this.brainUsed   = false,
  });

  WorkflowResearchState copyWith({
    _Phase?             phase,
    String?             goal,
    double?             budget,
    double?             hoursPerDay,
    String?             currency,
    String?             language,
    String?             timezone,
    List<String>?       skills,
    Map<String, dynamic>? research,
    String?             error,
    bool?               isLoading,
    bool?               brainUsed,
  }) {
    return WorkflowResearchState(
      phase:       phase       ?? this.phase,
      goal:        goal        ?? this.goal,
      budget:      budget      ?? this.budget,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      currency:    currency    ?? this.currency,
      language:    language    ?? this.language,
      timezone:    timezone    ?? this.timezone,
      skills:      skills      ?? this.skills,
      research:    research    ?? this.research,
      error:       error       ?? this.error,
      isLoading:   isLoading   ?? this.isLoading,
      brainUsed:   brainUsed   ?? this.brainUsed,
    );
  }
}

class WorkflowResearchNotifier extends StateNotifier<WorkflowResearchState> {
  final Ref ref;
  final _goalCtrl = TextEditingController();

  WorkflowResearchNotifier(this.ref) : super(WorkflowResearchState()) {
    _initializeLocale();
  }

  TextEditingController get goalController => _goalCtrl;

  void _initializeLocale() {
    final locale   = ref.read(localeProvider);
    final currency = ref.read(currencyProvider);
    state = state.copyWith(
      language: locale.languageCode,
      currency: currency,
      timezone: DateTime.now().timeZoneName,
    );
  }

  void updateBudget(double v)      => state = state.copyWith(budget: v, error: '');
  void updateHoursPerDay(double v) => state = state.copyWith(hoursPerDay: v);
  void updateLanguage(String v)    => state = state.copyWith(language: v);
  void addSkill(String s)          { if (!state.skills.contains(s)) state = state.copyWith(skills: [...state.skills, s]); }
  void removeSkill(String s)       => state = state.copyWith(skills: state.skills.where((x) => x != s).toList());
  void goBack()                    { if (state.phase == _Phase.review) state = state.copyWith(phase: _Phase.input); }

  void updateCurrency(String v) {
    state = state.copyWith(currency: v);
    final region = _regionFromCurrency(v);
    if (region != null) ref.read(localeProvider.notifier).setLocaleFromRegion(region);
  }

  String? _regionFromCurrency(String c) {
    const map = {
      'NGN': 'africa_west', 'GHS': 'africa_west',
      'KES': 'africa_east', 'ZAR': 'africa_south',
      'INR': 'south_asia',  'BRL': 'latin_america', 'MXN': 'latin_america',
    };
    return map[c];
  }

  Future<void> startResearch() async {
    if (_goalCtrl.text.trim().length < 10) {
      state = state.copyWith(error: _localError('goal_too_short')); return;
    }
    state = state.copyWith(phase: _Phase.researching, error: '', isLoading: true, brainUsed: false);
    try {
      final result = await api.post('/workflow/research', {
        'goal':                    _goalCtrl.text.trim(),
        'currency':                state.currency,
        'available_hours_per_day': state.hoursPerDay,
        'budget':                  state.budget,
        'language':                state.language,
        'region':                  _regionFromCurrency(state.currency),
        'timezone':                state.timezone,
        'skills':                  state.skills,
      });
      state = state.copyWith(
        research:  Map<String, dynamic>.from(result['research'] as Map? ?? {}),
        phase:     _Phase.review,
        isLoading: false,
        brainUsed: result['metadata']?['brain_used'] == true,
      );
    } catch (e) {
      state = state.copyWith(error: _localError('research_failed'), phase: _Phase.input, isLoading: false);
    }
  }

  Future<void> createWorkflow(BuildContext context) async {
    state = state.copyWith(phase: _Phase.creating, isLoading: true);
    try {
      final result = await api.post('/workflow/create', {
        'title':         state.research['title'] ?? 'My Income Workflow',
        'goal':          _goalCtrl.text.trim(),
        'income_type':   state.research['income_type'] ?? 'other',
        'research_data': state.research,
        'currency':      state.currency,
        'language':      state.language,
        'timezone':      state.timezone,
      });

      final wfId = result['workflow_id']?.toString() ?? '';
      state = state.copyWith(phase: _Phase.done, isLoading: false);

      // ── Brain signal: non-blocking, fire and forget ───────────────────────
      if (wfId.isNotEmpty) {
        api.recordInteractionSignal(
          action:      'workflow_created',
          postId:      wfId,
          postContent: '',           // ← FIX: required param — not a post context
        );
      }
      // ─────────────────────────────────────────────────────────────────────

      await Future.delayed(const Duration(milliseconds: 800));
      if (context.mounted && wfId.isNotEmpty) {
        context.pushReplacement('/workflow/$wfId');
      }
    } catch (e) {
      state = state.copyWith(error: _localError('create_failed'), phase: _Phase.review, isLoading: false);
    }
  }

  void reset() { state = WorkflowResearchState(); _goalCtrl.clear(); _initializeLocale(); }

  String _localError(String key) {
    final map = {
      'en': {
        'goal_too_short':  'Please describe your goal in more detail (at least 10 characters)',
        'research_failed': 'Research failed. Check your connection and try again.',
        'create_failed':   'Failed to create workflow. Please try again.',
      },
      'es': {
        'goal_too_short':  'Describa su objetivo con más detalle (al menos 10 caracteres)',
        'research_failed': 'Error en la investigación. Verifique su conexión.',
        'create_failed':   'Error al crear el flujo de trabajo. Inténtelo de nuevo.',
      },
    };
    return map[state.language]?[key] ?? map['en']![key]!;
  }

  @override
  void dispose() { _goalCtrl.dispose(); super.dispose(); }
}

// ─────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────

class WorkflowResearchScreen extends ConsumerStatefulWidget {
  const WorkflowResearchScreen({super.key});

  @override
  ConsumerState<WorkflowResearchScreen> createState() =>
      _WorkflowResearchScreenState();
}

class _WorkflowResearchScreenState
    extends ConsumerState<WorkflowResearchScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(workflowResearchProvider.notifier).reset());
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final state     = ref.watch(workflowResearchProvider);
    final notifier  = ref.read(workflowResearchProvider.notifier);

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation:       0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () {
            if (state.phase == _Phase.review) notifier.goBack();
            else context.pop();
          },
        ),
        title: Text(_title(state.phase), style: AppTextStyles.h4),
        actions: [
          if (state.phase == _Phase.input)
            _LanguageSelector(
                current:   state.language,
                onChanged: notifier.updateLanguage),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _buildPhase(state, notifier, isDark),
      ),
    );
  }

  String _title(_Phase p) => {
    _Phase.input:      'New Income Workflow',
    _Phase.researching:'AI Research in Progress',
    _Phase.review:     'Research Results',
    _Phase.creating:   'Creating Workflow',
    _Phase.done:       'Success!',
  }[p]!;

  Widget _buildPhase(WorkflowResearchState s,
      WorkflowResearchNotifier n, bool isDark) {
    switch (s.phase) {
      case _Phase.input:       return _InputPhase(key: const ValueKey('i'), isDark: isDark);
      case _Phase.researching: return _ResearchingPhase(key: const ValueKey('r'));
      case _Phase.review:      return _ReviewPhase(key: const ValueKey('v'), isDark: isDark);
      case _Phase.creating:    return const _CreatingPhase(key: ValueKey('c'));
      case _Phase.done:        return const _DonePhase(key: ValueKey('d'));
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// PHASE 1: INPUT
// ─────────────────────────────────────────────────────────────────

class _InputPhase extends ConsumerWidget {
  final bool isDark;
  const _InputPhase({super.key, required this.isDark});

  static const _currencies = ['USD','EUR','GBP','NGN','GHS','KES','ZAR','INR','PKR','BDT','PHP','IDR','BRL','MXN','EGP','TRY','USDT'];
  static const _skills = ['Writing','Design','Coding','Video Editing','Marketing','Sales','Translation','Data Entry','Photography','Social Media'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final locale   = ref.watch(localeProvider);
    final surface  = isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0);
    final text     = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: AppRadius.lg,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚡', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text('Tell me your income goal.',
                style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              "I'll search RiseUp's brain, research what's working NOW, and build your execution plan.",
              style: AppTextStyles.body.copyWith(color: Colors.white.withOpacity(0.85)),
            ),
          ]),
        ).animate().fadeIn().slideY(begin: -0.1),
        const SizedBox(height: 24),

        // Goal
        Text('What do you want to earn from?',
            style: AppTextStyles.h4.copyWith(color: text)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: TextField(
            controller: notifier.goalController,
            maxLines:   4,
            onChanged:  (_) => ref.read(workflowResearchProvider.notifier),
            style:      TextStyle(fontSize: 14, color: text),
            decoration: InputDecoration(
              hintText: state.language == 'es'
                  ? 'ej. "Quiero ganar dinero en YouTube en 2 meses"'
                  : 'e.g. "I want to start earning on YouTube in 2 months"',
              hintStyle: TextStyle(color: sub, fontSize: 12),
              border:    InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
        if (state.error.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(state.error,
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],
        const SizedBox(height: 20),

        // Skills
        Text('Your Skills (Optional)',
            style: AppTextStyles.h4.copyWith(color: text, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _skills.map((skill) {
            final sel = state.skills.contains(skill);
            return FilterChip(
              label: Text(skill, style: const TextStyle(fontSize: 12)),
              selected: sel,
              onSelected: (v) => v ? notifier.addSkill(skill) : notifier.removeSkill(skill),
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Budget
        _SettingCard(isDark: isDark, icon: Iconsax.wallet, label: 'Starting Budget', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            state.budget == 0
                ? '${state.currency} 0 — Free tools only ✅'
                : '${state.currency} ${state.budget.toStringAsFixed(0)}',
            style: TextStyle(
                color:      state.budget == 0 ? AppColors.success : AppColors.primary,
                fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Slider(
            value: state.budget, min: 0, max: 500, divisions: 50,
            activeColor: AppColors.primary,
            onChanged: notifier.updateBudget,
          ),
          Text(
            state.budget == 0 ? '✅ Only 100% free tools will be shown' : 'Mix of free + affordable paid tools',
            style: AppTextStyles.caption.copyWith(fontSize: 10),
          ),
        ])),
        const SizedBox(height: 12),

        // Hours
        _SettingCard(isDark: isDark, icon: Iconsax.clock, label: 'Daily Time Available', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${state.hoursPerDay.toStringAsFixed(1)} hours/day',
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
          Slider(
            value: state.hoursPerDay, min: 0.5, max: 12, divisions: 23,
            activeColor: AppColors.accent,
            onChanged: notifier.updateHoursPerDay,
          ),
        ])),
        const SizedBox(height: 12),

        // Currency
        _SettingCard(isDark: isDark, icon: Iconsax.money, label: 'Your Currency', child: Wrap(
          spacing: 8, runSpacing: 8,
          children: _currencies.map((c) {
            final sel = state.currency == c;
            return GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); notifier.updateCurrency(c); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:  sel ? AppColors.primary : Colors.transparent,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: sel ? AppColors.primary : AppColors.textMuted),
                ),
                child: Text(c,
                    style: TextStyle(
                        color:      sel ? Colors.white : AppColors.textSecondary,
                        fontSize:   12, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        )),
        const SizedBox(height: 32),

        // CTA
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: notifier.startResearch,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: AppRadius.pill,
                boxShadow: AppShadows.glow,
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Iconsax.search_normal, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Research My Income Goal',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
            ),
          ),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 40),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PHASE 2: RESEARCHING
// ─────────────────────────────────────────────────────────────────

class _ResearchingPhase extends ConsumerWidget {
  const _ResearchingPhase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(workflowResearchProvider).language;
    final messages = [
      '🧠 Searching RiseUp brain for proven methods...',
      '🔍 Researching what\'s working in 2025/2026...',
      '📊 Analyzing income potential in your region...',
      '🛠️ Finding free tools available in your country...',
      '⚡ Breaking down what AI can automate...',
      '📋 Building your step-by-step workflow...',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
              borderRadius: AppRadius.xl,
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
          ).animate().scale().then().shimmer(duration: 2.seconds),
          const SizedBox(height: 32),
          Text('Deep Research in Progress',
              style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(
            'AI is searching RiseUp\'s brain, analyzing your goal, and building your execution plan.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          ...messages.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Iconsax.tick_circle, color: AppColors.success, size: 14),
              const SizedBox(width: 8),
              Text(e.value, style: AppTextStyles.bodySmall),
            ]),
          ).animate(delay: (e.key * 700).ms).fadeIn().slideX(begin: -0.1)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PHASE 3: REVIEW
// ─────────────────────────────────────────────────────────────────

class _ReviewPhase extends ConsumerWidget {
  final bool isDark;
  const _ReviewPhase({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final d        = state.research;
    final text     = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white54 : Colors.black45;

    final potMin      = d['potential_monthly_income']?['min'] ?? 0;
    final potMax      = d['potential_monthly_income']?['max'] ?? 0;
    final currency    = d['potential_monthly_income']?['currency'] ?? state.currency;
    final score       = d['viability_score'] as int? ?? 75;
    final timeline    = d['realistic_timeline']?.toString() ?? '';
    final warning     = d['honest_warning']?.toString() ?? '';
    final brainMethods = (d['brain_matched_methods'] as List? ?? []);
    final working     = (d['what_is_working_now'] as List? ?? []);
    final regional    = (d['regional_opportunities'] as List? ?? []);
    final freeTools   = (d['free_tools'] as List? ?? []);
    final steps       = (d['step_by_step_workflow'] as List? ?? []);
    final aiCan       = (d['breakdown']?['ai_can_do'] as List? ?? []);
    final userMust    = (d['breakdown']?['user_must_do'] as List? ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Brain used badge
        if (state.brainUsed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00B894)]),
              borderRadius: AppRadius.pill,
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 13),
              SizedBox(width: 5),
              Text('🧠 Enhanced with RiseUp Brain',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Viability card
        _ViabilityCard(
          title: d['title']?.toString() ?? 'Your Workflow',
          score: score, timeline: timeline,
          potMin: potMin, potMax: potMax,
          currency: currency, isDark: isDark,
        ).animate().fadeIn(),
        const SizedBox(height: 20),

        // Brain-matched methods
        if (brainMethods.isNotEmpty) ...[
          _SectionTitle('🧠 Matched from RiseUp Brain', text),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            children: brainMethods.map((m) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: AppRadius.pill,
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Text(m.toString(),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Regional opportunities
        if (regional.isNotEmpty) ...[
          _SectionTitle('🌍 Regional Opportunities', text),
          const SizedBox(height: 8),
          ...regional.map((op) => _Bullet(op.toString(), AppColors.info, isDark)),
          const SizedBox(height: 20),
        ],

        // What's working now
        if (working.isNotEmpty) ...[
          _SectionTitle('📈 What\'s Working Right Now', text),
          const SizedBox(height: 8),
          ...working.map((w) => _Bullet(w.toString(), AppColors.success, isDark)),
          const SizedBox(height: 20),
        ],

        // AI breakdown
        _SectionTitle('⚡ What AI Can Do For You', text),
        const SizedBox(height: 8),
        ...aiCan.map((item) {
          final m = item as Map;
          return _BreakdownCard(
            emoji: '🤖', title: m['task']?.toString() ?? '',
            subtitle: m['how']?.toString() ?? '',
            badge: 'Saves ${m['saves_hours']}h', badgeColor: AppColors.success,
            isDark: isDark,
          );
        }),
        const SizedBox(height: 16),
        _SectionTitle('👤 What You Must Do', text),
        const SizedBox(height: 8),
        ...userMust.map((item) {
          final m = item as Map;
          return _BreakdownCard(
            emoji: '🎯', title: m['task']?.toString() ?? '',
            subtitle: m['why']?.toString() ?? '',
            badge: m['time_required']?.toString() ?? '', badgeColor: AppColors.warning,
            isDark: isDark,
          );
        }),
        const SizedBox(height: 20),

        // Free tools
        if (freeTools.isNotEmpty) ...[
          _SectionTitle('🆓 Free Tools (Start at \$0)', text),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            children: freeTools.map((t) {
              final tool = t as Map;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: AppRadius.md,
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tool['name']?.toString() ?? '',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(tool['purpose']?.toString() ?? '',
                      style: AppTextStyles.caption.copyWith(fontSize: 10)),
                ]),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Steps preview
        if (steps.isNotEmpty) ...[
          _SectionTitle('📋 Your ${steps.length}-Step Workflow', text),
          const SizedBox(height: 8),
          ...steps.take(4).toList().asMap().entries.map((e) {
            final s = e.value as Map;
            final isAuto = s['type'] == 'automated';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
                borderRadius: AppRadius.md,
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isAuto ? AppColors.primary.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text('${e.key + 1}',
                      style: TextStyle(
                          color: isAuto ? AppColors.primary : AppColors.warning,
                          fontWeight: FontWeight.w700, fontSize: 11))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['title']?.toString() ?? '',
                      style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 12)),
                  Text(isAuto ? '🤖 AI handles this' : '👤 You do this',
                      style: TextStyle(
                          color: isAuto ? AppColors.primary : AppColors.warning,
                          fontSize: 10, fontWeight: FontWeight.w600)),
                ])),
                Text('${s['time_minutes'] ?? 30} min', style: AppTextStyles.caption.copyWith(fontSize: 10)),
              ]),
            );
          }),
          if (steps.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${steps.length - 4} more steps in your workflow',
                  style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
            ),
          const SizedBox(height: 20),
        ],

        // Warning
        if (warning.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.warning.withOpacity(0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text(warning,
                  style: TextStyle(
                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                      fontSize: 12))),
            ]),
          ),
        const SizedBox(height: 24),

        // Create CTA
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => notifier.createWorkflow(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: AppRadius.pill,
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Iconsax.flash, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Create This Workflow',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: notifier.goBack,
            child: Text('← Research a Different Goal',
                style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PHASE 4 & 5
// ─────────────────────────────────────────────────────────────────

class _CreatingPhase extends StatelessWidget {
  const _CreatingPhase({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('⚡', style: TextStyle(fontSize: 64)),
      SizedBox(height: 16),
      Text('Building Your Workflow...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      SizedBox(height: 8),
      Text('Setting up your personalized execution plan', style: TextStyle(color: Colors.grey)),
    ]));
  }
}

class _DonePhase extends StatelessWidget {
  const _DonePhase({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('✅', style: TextStyle(fontSize: 64)).animate().scale(),
      const SizedBox(height: 16),
      const Text('Workflow Created!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Taking you there now...', style: TextStyle(color: Colors.grey)),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  final String current;
  final Function(String) onChanged;
  const _LanguageSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final langs = {'en':'🇺🇸','es':'🇪🇸','fr':'🇫🇷','hi':'🇮🇳','ar':'🇸🇦','pt':'🇧🇷','sw':'🌍'};
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (_) => langs.entries.map((e) => PopupMenuItem(
        value: e.key,
        child: Row(children: [
          Text(e.value), const SizedBox(width: 8), Text(e.key.toUpperCase()),
        ]),
      )).toList(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(langs[current] ?? '🌐'), const Icon(Iconsax.arrow_down, size: 16),
        ]),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final bool     isDark;
  final IconData icon;
  final String   label;
  final Widget   child;
  const _SettingCard({required this.isDark, required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.lg,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.label.copyWith(
              color: isDark ? Colors.white70 : Colors.black54)),
        ]),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }
}

class _ViabilityCard extends StatelessWidget {
  final String title;
  final int    score;
  final String timeline;
  final num    potMin, potMax;
  final String currency;
  final bool   isDark;
  const _ViabilityCard({required this.title, required this.score, required this.timeline, required this.potMin, required this.potMax, required this.currency, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(children: [
        SizedBox(width: 60, height: 60,
          child: Stack(children: [
            CircularProgressIndicator(
              value: score / 100,
              backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
              strokeWidth: 5,
            ),
            Center(child: Text('$score',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 16))),
          ])),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white : Colors.black87),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('⏱ $timeline  •  $currency $potMin–$currency $potMax/mo potential',
              style: AppTextStyles.caption.copyWith(fontSize: 11)),
        ])),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color  color;
  const _SectionTitle(this.title, this.color);
  @override
  Widget build(BuildContext context) => Text(title,
      style: AppTextStyles.h4.copyWith(color: color, fontSize: 15));
}

class _Bullet extends StatelessWidget {
  final String text;
  final Color  color;
  final bool   isDark;
  const _Bullet(this.text, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Iconsax.tick_circle, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: AppTextStyles.bodySmall.copyWith(
          color: isDark ? AppColors.textSecondary : Colors.black54))),
    ]),
  );
}

class _BreakdownCard extends StatelessWidget {
  final String emoji, title, subtitle, badge;
  final Color  badgeColor;
  final bool   isDark;
  const _BreakdownCard({required this.emoji, required this.title, required this.subtitle, required this.badge, required this.badgeColor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
        borderRadius: AppRadius.md,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.label.copyWith(
              color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTextStyles.caption),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.15), borderRadius: AppRadius.pill),
          child: Text(badge, style: TextStyle(
              color: badgeColor, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
