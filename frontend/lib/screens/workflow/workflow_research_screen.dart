// frontend/lib/screens/workflow/workflow_research_screen.dart
import 'dart:convert';
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

// ═════════════════════════════════════════════════════════════════════════════
// GLOBAL WORKFLOW RESEARCH SCREEN
// Enhanced with: Multi-currency, i18n, timezone support, Riverpod state management
// ═════════════════════════════════════════════════════════════════════════════

enum _Phase { input, researching, review, creating, done }

// Riverpod State for Workflow Research
final workflowResearchProvider = StateNotifierProvider<WorkflowResearchNotifier, WorkflowResearchState>((ref) {
  return WorkflowResearchNotifier(ref);
});

class WorkflowResearchState {
  final _Phase phase;
  final String goal;
  final double budget;
  final double hoursPerDay;
  final String currency;
  final String language;
  final String? timezone;
  final List<String> skills;
  final Map<String, dynamic> research;
  final String error;
  final bool isLoading;

  WorkflowResearchState({
    this.phase = _Phase.input,
    this.goal = '',
    this.budget = 0,
    this.hoursPerDay = 2,
    this.currency = 'USD',
    this.language = 'en',
    this.timezone,
    this.skills = const [],
    this.research = const {},
    this.error = '',
    this.isLoading = false,
  });

  WorkflowResearchState copyWith({
    _Phase? phase,
    String? goal,
    double? budget,
    double? hoursPerDay,
    String? currency,
    String? language,
    String? timezone,
    List<String>? skills,
    Map<String, dynamic>? research,
    String? error,
    bool? isLoading,
  }) {
    return WorkflowResearchState(
      phase: phase ?? this.phase,
      goal: goal ?? this.goal,
      budget: budget ?? this.budget,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      currency: currency ?? this.currency,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      skills: skills ?? this.skills,
      research: research ?? this.research,
      error: error ?? this.error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class WorkflowResearchNotifier extends StateNotifier<WorkflowResearchState> {
  final Ref ref;
  final _goalCtrl = TextEditingController();

  WorkflowResearchNotifier(this.ref) : super(WorkflowResearchState()) {
    // Initialize with user's locale preferences
    _initializeLocale();
  }

  TextEditingController get goalController => _goalCtrl;

  void _initializeLocale() {
    final locale = ref.read(localeProvider);
    final currency = ref.read(currencyProvider);
    
    state = state.copyWith(
      language: locale.languageCode,
      currency: currency,
      timezone: DateTime.now().timeZoneName,
    );
  }

  void updateGoal(String value) {
    state = state.copyWith(goal: value, error: '');
  }

  void updateBudget(double value) {
    state = state.copyWith(budget: value);
  }

  void updateHoursPerDay(double value) {
    state = state.copyWith(hoursPerDay: value);
  }

  void updateCurrency(String value) {
    state = state.copyWith(currency: value);
    // Update locale based on currency region
    final region = _getRegionFromCurrency(value);
    if (region != null) {
      ref.read(localeProvider.notifier).setLocaleFromRegion(region);
    }
  }

  void updateLanguage(String value) {
    state = state.copyWith(language: value);
    ref.read(localeProvider.notifier).setLocale(Locale(value));
  }

  void addSkill(String skill) {
    if (!state.skills.contains(skill)) {
      state = state.copyWith(skills: [...state.skills, skill]);
    }
  }

  void removeSkill(String skill) {
    state = state.copyWith(
      skills: state.skills.where((s) => s != skill).toList(),
    );
  }

  String? _getRegionFromCurrency(String currency) {
    final regions = {
      'NGN': 'africa_west',
      'GHS': 'africa_west',
      'KES': 'africa_east',
      'ZAR': 'africa_south',
      'INR': 'south_asia',
      'BRL': 'latin_america',
      'MXN': 'latin_america',
    };
    return regions[currency];
  }

  Future<void> startResearch() async {
    if (_goalCtrl.text.trim().length < 10) {
      state = state.copyWith(
        error: _getLocalizedError('goal_too_short'),
        phase: _Phase.input,
      );
      return;
    }

    state = state.copyWith(phase: _Phase.researching, error: '', isLoading: true);

    try {
      final result = await api.post('/workflow/research', {
        'goal': _goalCtrl.text.trim(),
        'currency': state.currency,
        'available_hours_per_day': state.hoursPerDay,
        'budget': state.budget,
        'language': state.language,
        'region': _getRegionFromCurrency(state.currency),
        'timezone': state.timezone,
        'skills': state.skills,
      });

      state = state.copyWith(
        research: Map<String, dynamic>.from(result['research'] as Map? ?? {}),
        phase: _Phase.review,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: _getLocalizedError('research_failed'),
        phase: _Phase.input,
        isLoading: false,
      );
    }
  }

  Future<void> createWorkflow(BuildContext context) async {
    state = state.copyWith(phase: _Phase.creating, isLoading: true);

    try {
      final result = await api.post('/workflow/create', {
        'title': state.research['title'] ?? 'My Income Workflow',
        'goal': _goalCtrl.text.trim(),
        'income_type': state.research['income_type'] ?? 'other',
        'research_data': state.research,
        'currency': state.currency,
        'language': state.language,
        'timezone': state.timezone,
      });

      final wfId = result['workflow_id'];
      state = state.copyWith(phase: _Phase.done, isLoading: false);
      
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        context.pushReplacement('/workflow/$wfId');
      }
    } catch (e) {
      state = state.copyWith(
        error: _getLocalizedError('create_failed'),
        phase: _Phase.review,
        isLoading: false,
      );
    }
  }

  void reset() {
    state = WorkflowResearchState();
    _goalCtrl.clear();
  }

  void goBack() {
    if (state.phase == _Phase.review) {
      state = state.copyWith(phase: _Phase.input);
    }
  }

  String _getLocalizedError(String key) {
    // This would connect to your i18n system
    final errors = {
      'en': {
        'goal_too_short': 'Please describe your goal in more detail (at least 10 characters)',
        'research_failed': 'Research failed. Check your connection and try again.',
        'create_failed': 'Failed to create workflow. Please try again.',
      },
      'es': {
        'goal_too_short': 'Describa su objetivo con más detalle (al menos 10 caracteres)',
        'research_failed': 'Error en la investigación. Verifique su conexión.',
        'create_failed': 'Error al crear el flujo de trabajo. Inténtelo de nuevo.',
      },
      // Add more languages...
    };
    return errors[state.language]?[key] ?? errors['en']![key]!;
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class WorkflowResearchScreen extends ConsumerStatefulWidget {
  const WorkflowResearchScreen({super.key});

  @override
  ConsumerState<WorkflowResearchScreen> createState() => _WorkflowResearchScreenState();
}

class _WorkflowResearchScreenState extends ConsumerState<WorkflowResearchScreen> {
  @override
  void initState() {
    super.initState();
    // Reset state when entering screen
    Future.microtask(() {
      ref.read(workflowResearchProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () {
            if (state.phase == _Phase.review) {
              notifier.goBack();
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _getScreenTitle(state.phase),
          style: AppTextStyles.h4,
        ),
        actions: [
          // Language selector
          if (state.phase == _Phase.input)
            _LanguageSelector(
              currentLanguage: state.language,
              onChanged: notifier.updateLanguage,
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(state, notifier, isDark),
      ),
    );
  }

  String _getScreenTitle(_Phase phase) {
    final titles = {
      _Phase.input: 'New Income Workflow',
      _Phase.researching: 'AI Research in Progress',
      _Phase.review: 'Research Results',
      _Phase.creating: 'Creating Workflow',
      _Phase.done: 'Success!',
    };
    return titles[phase] ?? 'Workflow';
  }

  Widget _buildBody(WorkflowResearchState state, WorkflowResearchNotifier notifier, bool isDark) {
    switch (state.phase) {
      case _Phase.input:
        return _InputPhase(key: const ValueKey('input'), isDark: isDark);
      case _Phase.researching:
        return const _ResearchingPhase(key: ValueKey('researching'));
      case _Phase.review:
        return _ReviewPhase(key: const ValueKey('review'), isDark: isDark);
      case _Phase.creating:
        return const _CreatingPhase(key: ValueKey('creating'));
      case _Phase.done:
        return const _DonePhase(key: ValueKey('done'));
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PHASE 1: INPUT (Enhanced with Global Features)
// ═════════════════════════════════════════════════════════════════════════════

class _InputPhase extends ConsumerWidget {
  final bool isDark;

  const _InputPhase({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final locale = ref.watch(localeProvider);

    // Comprehensive currency list with regional grouping
    final currencyGroups = {
      'Major': ['USD', 'EUR', 'GBP', 'JPY', 'CNY'],
      'Africa': ['NGN', 'GHS', 'KES', 'ZAR', 'EGP'],
      'Asia': ['INR', 'PKR', 'BDT', 'PHP', 'IDR', 'MYR', 'SGD'],
      'Americas': ['BRL', 'MXN', 'CAD', 'ARS', 'COP'],
      'Middle East': ['AED', 'SAR', 'TRY', 'QAR'],
      'Crypto': ['BTC', 'ETH', 'USDT'],
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Section with Localization
          _HeroCard(isDark: isDark, language: state.language),
          const SizedBox(height: 24),

          // Goal Input with localization
          _LocalizedText(
            'income_goal_prompt',
            style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: TextField(
              controller: notifier.goalController,
              maxLines: 4,
              onChanged: notifier.updateGoal,
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: _getLocalizedHint(state.language),
                hintStyle: AppTextStyles.label.copyWith(color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          if (state.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error,
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),

          const SizedBox(height: 20),

          // Skills Selector (New - Global Feature)
          _SkillsSelector(
            skills: state.skills,
            onAdd: notifier.addSkill,
            onRemove: notifier.removeSkill,
            isDark: isDark,
          ),

          const SizedBox(height: 20),

          // Budget Slider with currency formatting
          _SettingRow(
            label: _getLocalizedString('starting_budget', state.language),
            icon: Iconsax.wallet,
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatBudget(state.budget, state.currency, locale),
                  style: TextStyle(
                    color: state.budget == 0 ? AppColors.success : AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: state.budget,
                  min: 0,
                  max: 500,
                  divisions: 50,
                  activeColor: AppColors.primary,
                  onChanged: notifier.updateBudget,
                ),
                Text(
                  state.budget == 0
                      ? _getLocalizedString('free_tools_only', state.language)
                      : _getLocalizedString('mixed_tools', state.language),
                  style: AppTextStyles.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Hours Slider
          _SettingRow(
            label: _getLocalizedString('daily_time', state.language),
            icon: Iconsax.clock,
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.hoursPerDay.toStringAsFixed(1)} ${_getLocalizedString('hours_per_day', state.language)}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: state.hoursPerDay,
                  min: 0.5,
                  max: 12,
                  divisions: 23,
                  activeColor: AppColors.accent,
                  onChanged: notifier.updateHoursPerDay,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Currency Selector (Grouped by region)
          _SettingRow(
            label: _getLocalizedString('your_currency', state.language),
            icon: Iconsax.money,
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current selection display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.currency,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${_getCurrencyName(state.currency)})',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Currency groups
                ...currencyGroups.entries.map((group) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.key,
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: group.value.map((c) {
                          final selected = state.currency == c;
                          return GestureDetector(
                            onTap: () => notifier.updateCurrency(c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary : Colors.transparent,
                                borderRadius: AppRadius.pill,
                                border: Border.all(
                                  color: selected ? AppColors.primary : AppColors.textMuted,
                                ),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  color: selected ? Colors.white : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // CTA Button with localization
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: notifier.startResearch,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                  ),
                  borderRadius: AppRadius.pill,
                  boxShadow: AppShadows.glow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.search_normal, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _getLocalizedString('research_goal', state.language),
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _formatBudget(double budget, String currency, Locale locale) {
    if (budget == 0) return '$currency 0 — ${_getLocalizedString('free_only', 'en')}';
    
    final format = NumberFormat.currency(
      locale: locale.toString(),
      symbol: currency,
      decimalDigits: 0,
    );
    return format.format(budget);
  }

  String _getCurrencyName(String code) {
    final names = {
      'USD': 'US Dollar',
      'EUR': 'Euro',
      'GBP': 'British Pound',
      'NGN': 'Nigerian Naira',
      'GHS': 'Ghana Cedi',
      'KES': 'Kenyan Shilling',
      'ZAR': 'South African Rand',
      'INR': 'Indian Rupee',
      'BRL': 'Brazilian Real',
    };
    return names[code] ?? code;
  }

  String _getLocalizedHint(String language) {
    final hints = {
      'en': 'e.g. "I want to start earning on YouTube in 2 months" or "I want to sell clothes on WhatsApp in Lagos"',
      'es': 'ej. "Quiero ganar dinero en YouTube en 2 meses" o "Vender ropa por WhatsApp"',
      'fr': 'ex. "Je veux gagner sur YouTube en 2 mois" ou "Vendre des vêtements sur WhatsApp"',
      'hi': 'उदाहरण: "2 महीने में YouTube से कमाई शुरू करना चाहता हूं"',
    };
    return hints[language] ?? hints['en']!;
  }

  String _getLocalizedString(String key, String language) {
    final strings = {
      'en': {
        'income_goal_prompt': 'What do you want to earn from?',
        'starting_budget': 'Starting Budget',
        'daily_time': 'Daily Time Available',
        'your_currency': 'Your Currency',
        'hours_per_day': 'hours/day',
        'free_tools_only': '✅ Only 100% free tools will be shown',
        'mixed_tools': 'Mix of free + affordable paid tools',
        'free_only': 'Free only',
        'research_goal': 'Research My Income Goal',
      },
      'es': {
        'income_goal_prompt': '¿De qué quieres ganar dinero?',
        'starting_budget': 'Presupuesto Inicial',
        'daily_time': 'Tiempo Diario Disponible',
        'your_currency': 'Tu Moneda',
        'hours_per_day': 'horas/día',
        'free_tools_only': '✅ Solo herramientas 100% gratuitas',
        'mixed_tools': 'Mix de herramientas gratis + pagadas',
        'free_only': 'Solo gratis',
        'research_goal': 'Investigar Mi Objetivo',
      },
    };
    return strings[language]?[key] ?? strings['en']![key]!;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PHASE 2: RESEARCHING (Enhanced with localized messages)
// ═════════════════════════════════════════════════════════════════════════════

class _ResearchingPhase extends ConsumerWidget {
  const _ResearchingPhase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(workflowResearchProvider).language;
    
    final localizedMessages = {
      'en': [
        '🔍 Researching what\'s working in 2025/2026...',
        '📊 Analyzing income potential in your region...',
        '🛠️ Finding free tools available in your country...',
        '⚡ Breaking down what AI can automate...',
        '📋 Building your step-by-step workflow...',
      ],
      'es': [
        '🔍 Investigando qué está funcionando en 2025/2026...',
        '📊 Analizando potencial de ingresos en tu región...',
        '🛠️ Buscando herramientas gratuitas en tu país...',
        '⚡ Determinando qué puede automatizar la IA...',
        '📋 Construyendo tu flujo de trabajo paso a paso...',
      ],
    };

    final messages = localizedMessages[language] ?? localizedMessages['en']!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                ),
                borderRadius: AppRadius.xl,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ).animate().scale().then().shimmer(duration: 2.seconds),
            const SizedBox(height: 32),
            Text(
              _getLocalizedTitle(language),
              style: AppTextStyles.h3.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              _getLocalizedSubtitle(language),
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            ...messages.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Iconsax.tick_circle, color: AppColors.success, size: 14),
                    const SizedBox(width: 8),
                    Text(e.value, style: AppTextStyles.bodySmall),
                  ],
                ),
              ).animate(delay: (e.key * 600).ms).fadeIn().slideX(begin: -0.1);
            }),
          ],
        ),
      ),
    );
  }

  String _getLocalizedTitle(String language) {
    final titles = {
      'en': 'Deep Research in Progress',
      'es': 'Investigación Profunda en Progreso',
      'fr': 'Recherche Approfondie en Cours',
    };
    return titles[language] ?? titles['en']!;
  }

  String _getLocalizedSubtitle(String language) {
    final subtitles = {
      'en': 'AI is analyzing your goal, finding what\'s actually working, and building your execution plan.',
      'es': 'La IA está analizando tu objetivo, encontrando lo que realmente funciona, y construyendo tu plan.',
    };
    return subtitles[language] ?? subtitles['en']!;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PHASE 3: REVIEW (Enhanced with Global Formatting)
// ═════════════════════════════════════════════════════════════════════════════

class _ReviewPhase extends ConsumerWidget {
  final bool isDark;

  const _ReviewPhase({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workflowResearchProvider);
    final notifier = ref.read(workflowResearchProvider.notifier);
    final data = state.research;
    final locale = ref.watch(localeProvider);

    final aiCan = (data['breakdown']?['ai_can_do'] as List? ?? []);
    final userMust = (data['breakdown']?['user_must_do'] as List? ?? []);
    final freeTools = (data['free_tools'] as List? ?? []);
    final steps = (data['step_by_step_workflow'] as List? ?? []);
    final working = (data['what_is_working_now'] as List? ?? []);
    final regionalOps = (data['regional_opportunities'] as List? ?? []);
    
    final potMin = data['potential_monthly_income']?['min'] ?? 0;
    final potMax = data['potential_monthly_income']?['max'] ?? 0;
    final currency = data['potential_monthly_income']?['currency'] ?? state.currency;
    final warning = data['honest_warning']?.toString() ?? '';
    final score = data['viability_score'] as int? ?? 75;
    final timeline = data['realistic_timeline']?.toString() ?? '';

    // Format numbers according to locale
    final numberFormat = NumberFormat.currency(
      locale: locale.toString(),
      symbol: currency,
      decimalDigits: 0,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Viability Card with localization
          _ViabilityCard(
            title: data['title']?.toString() ?? 'Your Workflow',
            score: score,
            timeline: timeline,
            potMin: potMin,
            potMax: potMax,
            currency: currency,
            numberFormat: numberFormat,
            isDark: isDark,
          ).animate().fadeIn(),

          const SizedBox(height: 20),

          // Regional Opportunities (New)
          if (regionalOps.isNotEmpty) ...[
            _sectionTitle('🌍 Regional Opportunities', isDark),
            const SizedBox(height: 8),
            ...regionalOps.map((op) => _bulletItem(op.toString(), AppColors.info, isDark)),
            const SizedBox(height: 20),
          ],

          // What's working now
          if (working.isNotEmpty) ...[
            _sectionTitle('📈 What\'s Working Right Now', isDark),
            const SizedBox(height: 8),
            ...working.map((w) => _bulletItem(w.toString(), AppColors.success, isDark)),
            const SizedBox(height: 20),
          ],

          // AI vs User breakdown
          _sectionTitle('⚡ What AI Can Do For You', isDark),
          const SizedBox(height: 8),
          ...aiCan.map((item) {
            final m = item as Map;
            return _BreakdownCard(
              emoji: '🤖',
              title: m['task']?.toString() ?? '',
              subtitle: m['how']?.toString() ?? '',
              badge: 'Saves ${m['saves_hours']}h',
              badgeColor: AppColors.success,
              isDark: isDark,
            );
          }),

          const SizedBox(height: 16),
          _sectionTitle('👤 What You Must Do', isDark),
          const SizedBox(height: 8),
          ...userMust.map((item) {
            final m = item as Map;
            return _BreakdownCard(
              emoji: '🎯',
              title: m['task']?.toString() ?? '',
              subtitle: m['why']?.toString() ?? '',
              badge: m['time_required']?.toString() ?? '',
              badgeColor: AppColors.warning,
              isDark: isDark,
            );
          }),

          const SizedBox(height: 20),

          // Free Tools with regional availability
          if (freeTools.isNotEmpty) ...[
            _sectionTitle('🆓 Free Tools (Start at \$0)', isDark),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: freeTools.map((t) {
                final tool = t as Map;
                final available = tool['region_available'] ?? true;
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: available 
                      ? AppColors.success.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                    borderRadius: AppRadius.md,
                    border: Border.all(
                      color: available 
                        ? AppColors.success.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tool['name']?.toString() ?? '',
                            style: TextStyle(
                              color: available ? AppColors.success : Colors.grey,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          if (!available) ...[
                            const SizedBox(width: 4),
                            const Icon(Iconsax.global, size: 10, color: Colors.grey),
                          ],
                        ],
                      ),
                      Text(
                        tool['purpose']?.toString() ?? '',
                        style: AppTextStyles.caption.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Steps preview with time estimates
          if (steps.isNotEmpty) ...[
            _sectionTitle('📋 Your ${steps.length}-Step Workflow', isDark),
            const SizedBox(height: 8),
            ...steps.take(4).toList().asMap().entries.map((e) {
              final s = e.value as Map;
              final isAuto = s['type'] == 'automated';
              return _StepPreview(
                index: e.key + 1,
                title: s['title']?.toString() ?? '',
                type: s['type']?.toString() ?? 'manual',
                timeMinutes: s['time_minutes'] as int? ?? 30,
                isAuto: isAuto,
                isDark: isDark,
              );
            }),
            if (steps.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${steps.length - 4} more steps in your workflow',
                  style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                ),
              ),
            const SizedBox(height: 20),
          ],

          // Payment Methods (New)
          _PaymentMethodsSection(
            region: data['region']?.toString() ?? 'global',
            isDark: isDark,
          ),

          const SizedBox(height: 12),

          // Warning
          if (warning.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: AppRadius.md,
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warning,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Create button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => notifier.createWorkflow(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                  ),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.flash, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Create This Workflow',
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => notifier.goBack(),
              child: Text(
                '← Research a Different Goal',
                style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) => Text(
    title,
    style: AppTextStyles.h4.copyWith(
      color: isDark ? Colors.white : Colors.black87,
      fontSize: 15,
    ),
  );

  Widget _bulletItem(String text, Color color, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Iconsax.tick_circle, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark ? AppColors.textSecondary : Colors.black54,
            ),
          ),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PHASE 4 & 5: Creating and Done
// ═════════════════════════════════════════════════════════════════════════════

class _CreatingPhase extends StatelessWidget {
  const _CreatingPhase({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('⚡', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Building Your Workflow...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            'Setting up your personalized execution plan',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _DonePhase extends StatelessWidget {
  const _DonePhase({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('✅', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Workflow Created!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            'Taking you there now...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final bool isDark;
  final String language;

  const _HeroCard({required this.isDark, required this.language});

  @override
  Widget build(BuildContext context) {
    final localizedText = {
      'en': {
        'title': 'Tell me your income goal.',
        'subtitle': 'I\'ll research what\'s working NOW, break it down step by step, find you free tools, and manage the execution.',
      },
      'es': {
        'title': 'Cuéntame tu objetivo de ingresos.',
        'subtitle': 'Investigaré qué está funcionando AHORA, lo desglosaré paso a paso, encontraré herramientas gratuitas y gestionaré la ejecución.',
      },
    };

    final text = localizedText[language] ?? localizedText['en']!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚡', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            text['title']!,
            style: AppTextStyles.h3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            text['subtitle']!,
            style: AppTextStyles.body.copyWith(
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }
}

class _LanguageSelector extends StatelessWidget {
  final String currentLanguage;
  final Function(String) onChanged;

  const _LanguageSelector({
    required this.currentLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final languages = {
      'en': '🇺🇸',
      'es': '🇪🇸',
      'fr': '🇫🇷',
      'hi': '🇮🇳',
      'ar': '🇸🇦',
      'pt': '🇧🇷',
    };

    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) {
        return languages.entries.map((e) {
          return PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                Text(e.value),
                const SizedBox(width: 8),
                Text(e.key.toUpperCase()),
              ],
            ),
          );
        }).toList();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(languages[currentLanguage] ?? '🌐'),
            const Icon(Iconsax.arrow_down, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SkillsSelector extends StatelessWidget {
  final List<String> skills;
  final Function(String) onAdd;
  final Function(String) onRemove;
  final bool isDark;

  const _SkillsSelector({
    required this.skills,
    required this.onAdd,
    required this.onRemove,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final availableSkills = [
      'Writing',
      'Design',
      'Coding',
      'Video Editing',
      'Marketing',
      'Sales',
      'Translation',
      'Data Entry',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Skills (Optional)',
          style: AppTextStyles.h4.copyWith(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableSkills.map((skill) {
            final selected = skills.contains(skill);
            return FilterChip(
              label: Text(skill),
              selected: selected,
              onSelected: (selected) {
                if (selected) {
                  onAdd(skill);
                } else {
                  onRemove(skill);
                }
              },
              selectedColor: AppColors.primary.withOpacity(0.2),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Widget child;

  const _SettingRow({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ViabilityCard extends StatelessWidget {
  final String title;
  final int score;
  final String timeline;
  final num potMin;
  final num potMax;
  final String currency;
  final NumberFormat numberFormat;
  final bool isDark;

  const _ViabilityCard({
    required this.title,
    required this.score,
    required this.timeline,
    required this.potMin,
    required this.potMax,
    required this.currency,
    required this.numberFormat,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(AppColors.success),
                  strokeWidth: 5,
                ),
                Center(
                  child: Text(
                    '$score',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.h4.copyWith(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '⏱ $timeline  •  ${numberFormat.format(potMin)}-${numberFormat.format(potMax)}/mo potential',
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final bool isDark;

  const _BreakdownCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
        borderRadius: AppRadius.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.label.copyWith(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPreview extends StatelessWidget {
  final int index;
  final String title;
  final String type;
  final int timeMinutes;
  final bool isAuto;
  final bool isDark;

  const _StepPreview({
    required this.index,
    required this.title,
    required this.type,
    required this.timeMinutes,
    required this.isAuto,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : const Color(0xFFF5F5F5),
        borderRadius: AppRadius.md,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isAuto
                  ? AppColors.primary.withOpacity(0.15)
                  : AppColors.warning.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: isAuto ? AppColors.primary : AppColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.label.copyWith(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                ),
                Text(
                  isAuto ? '🤖 AI handles this' : '👤 You do this',
                  style: TextStyle(
                    color: isAuto ? AppColors.primary : AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$timeMinutes min',
            style: AppTextStyles.caption.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodsSection extends ConsumerWidget {
  final String region;
  final bool isDark;

  const _PaymentMethodsSection({
    required this.region,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = _getPaymentMethods(region);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('💳 Recommended Payment Methods', isDark),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.map((method) {
            return Chip(
              avatar: Icon(
                _getPaymentIcon(method),
                size: 16,
                color: AppColors.primary,
              ),
              label: Text(
                method,
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: AppColors.primary.withOpacity(0.1),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<String> _getPaymentMethods(String region) {
    final methods = {
      'global': ['PayPal', 'Wise', 'Payoneer', 'Crypto (USDT)'],
      'africa_west': ['PayPal', 'Chipper Cash', 'Flutterwave', 'Paga'],
      'africa_east': ['M-Pesa', 'PayPal', 'Flutterwave', 'Chipper Cash'],
      'south_asia': ['PayPal', 'Razorpay', 'Paytm', 'UPI'],
      'latin_america': ['PayPal', 'Mercado Pago', 'Pix'],
    };
    return methods[region] ?? methods['global']!;
  }

  IconData _getPaymentIcon(String method) {
    if (method.contains('PayPal')) return Iconsax.money;
    if (method.contains('M-Pesa')) return Iconsax.mobile;
    if (method.contains('Crypto')) return Iconsax.arrow_swap;
    return Iconsax.wallet;
  }

  Widget _sectionTitle(String title, bool isDark) => Text(
    title,
    style: AppTextStyles.h4.copyWith(
      color: isDark ? Colors.white : Colors.black87,
      fontSize: 15,
    ),
  );
}

class _LocalizedText extends StatelessWidget {
  final String key_;
  final TextStyle? style;

  const _LocalizedText(this.key_, {this.style});

  @override
  Widget build(BuildContext context) {
    // This would integrate with your full i18n system
    return Text(
      key_,
      style: style,
    );
  }
}
