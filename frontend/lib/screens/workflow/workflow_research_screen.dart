import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Workflow Research Screen ──────────────────────────────────────
// User describes their income goal → AI researches → shows breakdown
// → User confirms → Workflow is created
class WorkflowResearchScreen extends StatefulWidget {
  const WorkflowResearchScreen({super.key});
  @override
  State<WorkflowResearchScreen> createState() => _WorkflowResearchScreenState();
}

enum _Phase { input, researching, review, creating, done }

class _WorkflowResearchScreenState extends State<WorkflowResearchScreen> {
  _Phase _phase = _Phase.input;
  final _goalCtrl = TextEditingController();
  double _budget = 0;
  double _hoursPerDay = 2;
  String _currency = 'NGN';
  Map<String, dynamic> _research = {};
  String _error = '';

  // ── Research call ──────────────────────────────────────────────
  Future<void> _startResearch() async {
    if (_goalCtrl.text.trim().length < 10) {
      setState(() => _error = 'Please describe your goal in more detail');
      return;
    }
    setState(() {
      _phase = _Phase.researching;
      _error = '';
    });

    try {
      final result = await api.post('/workflow/research', {
        'goal': _goalCtrl.text.trim(),
        'currency': _currency,
        'available_hours_per_day': _hoursPerDay,
        'budget': _budget,
      });
      setState(() {
        _research = Map<String, dynamic>.from(result['research'] as Map? ?? {});
        _phase = _Phase.review;
      });
    } catch (e) {
      setState(() {
        _error = 'Research failed. Check your connection and try again.';
        _phase = _Phase.input;
      });
    }
  }

  // ── Create workflow ────────────────────────────────────────────
  Future<void> _createWorkflow() async {
    setState(() => _phase = _Phase.creating);
    try {
      final result = await api.post('/workflow/create', {
        'title': _research['title'] ?? 'My Income Workflow',
        'goal': _goalCtrl.text.trim(),
        'income_type': _research['income_type'] ?? 'other',
        'research_data': _research,
        'currency': _currency,
      });
      final wfId = result['workflow_id'];
      setState(() => _phase = _Phase.done);
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) context.pushReplacement('/workflow/$wfId');
    } catch (e) {
      setState(() {
        _error = 'Failed to create workflow. Try again.';
        _phase = _Phase.review;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () {
            if (_phase == _Phase.review) {
              setState(() => _phase = _Phase.input);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _phase == _Phase.review ? 'AI Research Results' : 'New Workflow',
          style: AppTextStyles.h4,
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    switch (_phase) {
      case _Phase.input:       return _InputPhase(this, isDark);
      case _Phase.researching: return _ResearchingPhase();
      case _Phase.review:      return _ReviewPhase(this, isDark, _research);
      case _Phase.creating:    return _CreatingPhase();
      case _Phase.done:        return _DonePhase();
    }
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }
}

// ── Phase 1: Input ────────────────────────────────────────────────
class _InputPhase extends StatelessWidget {
  final _WorkflowResearchScreenState state;
  final bool isDark;
  const _InputPhase(this.state, this.isDark);

  @override
  Widget build(BuildContext context) {
    final currencies = ['NGN', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero text
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: AppRadius.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚡', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                Text('Tell me your income goal.',
                    style: AppTextStyles.h3.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'I\'ll research what\'s working NOW, break it down step by step, find you free tools, and manage the execution.',
                  style: AppTextStyles.body.copyWith(color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.1),

          const SizedBox(height: 24),

          // Goal input
          Text('What do you want to earn from?',
              style: AppTextStyles.h4.copyWith(
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : const Color(0xFFF0F0F0),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: TextField(
              controller: state._goalCtrl,
              maxLines: 4,
              style: AppTextStyles.body.copyWith(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'e.g. "I want to start earning on YouTube by the end of two months" or "I want to make money selling clothes on WhatsApp" or "I want to freelance as a graphic designer"',
                hintStyle: AppTextStyles.label.copyWith(color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          if (state._error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state._error,
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),

          const SizedBox(height: 20),

          // Budget
          _SettingRow(
            label: 'Starting Budget',
            icon: Iconsax.wallet,
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state._budget == 0
                      ? '₦0 — Free tools only'
                      : '\$${state._budget.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: state._budget == 0 ? AppColors.success : AppColors.primary,
                    fontWeight: FontWeight.w700, fontSize: 13,
                  ),
                ),
                Slider(
                  value: state._budget,
                  min: 0, max: 100,
                  divisions: 10,
                  activeColor: AppColors.primary,
                  onChanged: (v) => (state..setState(() => state._budget = v)),
                ),
                Text(
                  state._budget == 0
                      ? '✅ System will only show 100% free tools'
                      : 'System will mix free + affordable paid tools',
                  style: AppTextStyles.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Hours
          _SettingRow(
            label: 'Daily Time Available',
            icon: Iconsax.clock,
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${state._hoursPerDay.toStringAsFixed(1)} hours/day',
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                Slider(
                  value: state._hoursPerDay,
                  min: 0.5, max: 8,
                  divisions: 15,
                  activeColor: AppColors.accent,
                  onChanged: (v) => (state..setState(() => state._hoursPerDay = v)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Currency
          _SettingRow(
            label: 'Your Currency',
            icon: Iconsax.money,
            isDark: isDark,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: currencies.map((c) {
                  final selected = state._currency == c;
                  return GestureDetector(
                    onTap: () => state.setState(() => state._currency = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.transparent,
                        borderRadius: AppRadius.pill,
                        border: Border.all(color: selected ? AppColors.primary : AppColors.textMuted),
                      ),
                      child: Text(c,
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.textSecondary,
                            fontSize: 12, fontWeight: FontWeight.w600,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // CTA
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: state._startResearch,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                  borderRadius: AppRadius.pill,
                  boxShadow: AppShadows.glow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.search_normal, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Research My Income Goal',
                        style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 15)),
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
}

// ── Phase 2: Researching ──────────────────────────────────────────
class _ResearchingPhase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final messages = [
      '🔍 Researching what\'s working in 2025/2026...',
      '📊 Analyzing income potential and timelines...',
      '🛠️ Finding free tools for you...',
      '⚡ Breaking down what AI can automate...',
      '📋 Building your step-by-step workflow...',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                borderRadius: AppRadius.xl,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5,
                ),
              ),
            ).animate().scale().then().shimmer(duration: 2.seconds),
            const SizedBox(height: 32),
            Text('Deep Research in Progress',
                style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
            const SizedBox(height: 8),
            Text(
              'AI is analyzing your goal, finding what\'s actually working, and building your execution plan.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            ...messages.asMap().entries.map((e) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Iconsax.tick_circle, color: AppColors.success, size: 14),
                      const SizedBox(width: 8),
                      Text(e.value, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ).animate(delay: (e.key * 600).ms).fadeIn().slideX(begin: -0.1),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Phase 3: Review Research Results ─────────────────────────────
class _ReviewPhase extends StatelessWidget {
  final _WorkflowResearchScreenState state;
  final bool isDark;
  final Map<String, dynamic> data;
  const _ReviewPhase(this.state, this.isDark, this.data);

  @override
  Widget build(BuildContext context) {
    final aiCan = (data['breakdown']?['ai_can_do'] as List? ?? []);
    final userMust = (data['breakdown']?['user_must_do'] as List? ?? []);
    final freeTools = (data['free_tools'] as List? ?? []);
    final steps = (data['step_by_step_workflow'] as List? ?? []);
    final working = (data['what_is_working_now'] as List? ?? []);
    final potMin = data['potential_monthly_income']?['min'] ?? 0;
    final potMax = data['potential_monthly_income']?['max'] ?? 0;
    final currency = data['potential_monthly_income']?['currency'] ?? 'NGN';
    final warning = data['honest_warning']?.toString() ?? '';
    final score = data['viability_score'] as int? ?? 75;
    final timeline = data['realistic_timeline']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Viability card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 60, height: 60,
                  child: Stack(
                    children: [
                      CircularProgressIndicator(
                        value: score / 100,
                        backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation(AppColors.success),
                        strokeWidth: 5,
                      ),
                      Center(
                        child: Text('$score',
                            style: const TextStyle(
                              color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['title']?.toString() ?? 'Your Workflow',
                          style: AppTextStyles.h4.copyWith(
                              color: isDark ? Colors.white : Colors.black87),
                          maxLines: 2),
                      const SizedBox(height: 4),
                      Text('⏱ $timeline  •  $currency ${_fmtNum(potMin.toDouble())}-${_fmtNum(potMax.toDouble())}/mo potential',
                          style: AppTextStyles.caption.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(),

          const SizedBox(height: 20),

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
            return _breakdownCard(
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
            return _breakdownCard(
              emoji: '🎯',
              title: m['task']?.toString() ?? '',
              subtitle: m['why']?.toString() ?? '',
              badge: m['time_required']?.toString() ?? '',
              badgeColor: AppColors.warning,
              isDark: isDark,
            );
          }),

          const SizedBox(height: 20),

          // Free Tools
          if (freeTools.isNotEmpty) ...[
            _sectionTitle('🆓 Free Tools (Start at \$0)', isDark),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: freeTools.map((t) {
                final tool = t as Map;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: AppRadius.md,
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tool['name']?.toString() ?? '',
                          style: const TextStyle(
                              color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(tool['purpose']?.toString() ?? '',
                          style: AppTextStyles.caption.copyWith(fontSize: 10)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Steps preview
          if (steps.isNotEmpty) ...[
            _sectionTitle('📋 Your ${steps.length}-Step Workflow', isDark),
            const SizedBox(height: 8),
            ...steps.take(4).asMap().entries.map((e) {
              final s = e.value as Map;
              final isAuto = s['type'] == 'automated';
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
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isAuto ? AppColors.primary.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: TextStyle(
                                color: isAuto ? AppColors.primary : AppColors.warning,
                                fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['title']?.toString() ?? '',
                              style: AppTextStyles.label.copyWith(
                                  color: isDark ? Colors.white : Colors.black87, fontSize: 12)),
                          Text(isAuto ? '🤖 AI handles this' : '👤 You do this',
                              style: TextStyle(
                                  color: isAuto ? AppColors.primary : AppColors.warning,
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Text('${s['time_minutes']} min',
                        style: AppTextStyles.caption.copyWith(fontSize: 10)),
                  ],
                ),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(warning,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: isDark ? Colors.orange.shade300 : Colors.orange.shade800)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Create button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: state._createWorkflow,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)]),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.flash, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Create This Workflow',
                        style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => state.setState(() => state._phase = _Phase.input),
              child: Text('← Research a Different Goal',
                  style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
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
        color: isDark ? Colors.white : Colors.black87, fontSize: 15),
  );

  Widget _bulletItem(String text, Color color, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Iconsax.tick_circle, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textSecondary : Colors.black54))),
      ],
    ),
  );

  Widget _breakdownCard({
    required String emoji, required String title, required String subtitle,
    required String badge, required Color badgeColor, required bool isDark,
  }) {
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
                Text(title, style: AppTextStyles.label.copyWith(
                    color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
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
            child: Text(badge,
                style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Phase 4: Creating ─────────────────────────────────────────────
class _CreatingPhase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('⚡', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text('Building Your Workflow...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Phase 5: Done ─────────────────────────────────────────────────
class _DonePhase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('✅', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text('Workflow Created!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Taking you there now...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────
class _SettingRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Widget child;
  const _SettingRow({required this.label, required this.icon, required this.isDark, required this.child});

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
              Text(label, style: AppTextStyles.label.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
