// frontend/lib/screens/goals/goals_screen.dart
// v4.0 — Every widget resolves Theme.of(context) independently. No color drilling.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Theme helper ──────────────────────────────────────────────────────────
class _T {
  final bool   dark;
  final Color  bg, card, surface, border, text, sub;
  const _T({
    required this.dark,   required this.bg,
    required this.card,   required this.surface,
    required this.border, required this.text,
    required this.sub,
  });
  factory _T.of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return _T(
      dark:    dark,
      bg:      dark ? Colors.black        : Colors.white,
      card:    dark ? AppColors.bgCard    : Colors.white,
      surface: dark ? AppColors.bgSurface : Colors.grey.shade100,
      border:  dark ? AppColors.bgSurface : Colors.grey.shade200,
      text:    dark ? Colors.white        : Colors.black87,
      sub:     dark ? Colors.white54      : Colors.black54,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with WidgetsBindingObserver {
  static const _kGoals   = 'riseup_goals_v2';
  static const _kProfile = 'riseup_finance_profile_v1';

  List _goals   = [];
  Map  _profile = {};
  bool _loading    = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentRefresh();
  }

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gStr  = prefs.getString(_kGoals);
      final pStr  = prefs.getString(_kProfile);
      if (gStr != null) {
        final g = jsonDecode(gStr) as List;
        if (mounted) setState(() { _goals = g; _loading = false; });
      }
      if (pStr != null) {
        final p = Map<String, dynamic>.from(jsonDecode(pStr) as Map);
        if (mounted) setState(() => _profile = p);
      }
    } catch (_) {}
  }

  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    await _fetchAndApply();
  }

  Future<void> _fetchAndApply() async {
    try {
      final results = await Future.wait([
        api.getGoals(),
        api.getProfile(),
      ]);
      final goalsData = (results[0] as Map)['goals'] as List? ?? [];
      final profile   = ((results[1] as Map)['profile'] as Map?)
                            ?.cast<String, dynamic>() ?? {};

      for (final g in goalsData) {
        final target = (g['target_amount'] as num?)?.toDouble() ?? 0.0;
        g['progress_percent'] = target > 0
            ? (((g['current_amount'] as num?)?.toDouble() ?? 0.0) /
               target * 100).clamp(0.0, 100.0)
            : 0.0;
      }

      if (mounted) setState(() {
        _goals      = goalsData;
        _profile    = profile;
        _loading    = false;
        _refreshing = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kGoals,   jsonEncode(goalsData)),
        prefs.setString(_kProfile, jsonEncode(profile)),
      ]);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  String get _currency => _profile['currency']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    final activeGoals = _goals.where((g) =>
        g['status'] == 'active').toList();
    final doneGoals   = _goals.where((g) =>
        g['status'] == 'completed').toList();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('My Goals', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: t.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.primary.withOpacity(0.5)))),
            ),
          IconButton(
            icon: const Icon(Iconsax.magic_star,
                color: AppColors.accent, size: 22),
            tooltip: 'AI Goal Suggestions',
            onPressed: () => _showAiSuggestions(context),
          ),
          IconButton(
            icon: const Icon(Iconsax.add_circle,
                color: AppColors.primary, size: 22),
            onPressed: () => _showCreateGoal(context),
          ),
        ],
      ),
      body: _loading && _goals.isEmpty
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _fetchAndApply,
              color: AppColors.primary,
              child: _goals.isEmpty
                  ? _EmptyState(onTap: () => _showCreateGoal(context))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SummaryStrip(
                          total:     _goals.length,
                          active:    activeGoals.length,
                          completed: doneGoals.length,
                        ).animate().fadeIn(),

                        const SizedBox(height: 20),

                        if (activeGoals.isNotEmpty) ...[
                          _SectionHeader(
                              'Active Goals (${activeGoals.length})'),
                          ...activeGoals.asMap().entries.map((e) =>
                              _GoalCard(
                                goal:      e.value,
                                index:     e.key,
                                currency:  _currency,
                                onRefresh: _fetchAndApply,
                              )),
                        ],

                        if (doneGoals.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _SectionHeader(
                              'Completed 🏆 (${doneGoals.length})'),
                          ...doneGoals.asMap().entries.map((e) =>
                              _GoalCard(
                                goal:      e.value,
                                index:     e.key,
                                currency:  _currency,
                                onRefresh: _fetchAndApply,
                              )),
                        ],

                        const SizedBox(height: 80),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showCreateGoal(context),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600,
            fontSize: 13)),
      ),
    );
  }

  void _showCreateGoal(BuildContext context) {
    final t = _T.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreateGoalSheet(
        onCreated: _fetchAndApply,
        currency:  _currency,
      ),
    );
  }

  void _showAiSuggestions(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(
          color: AppColors.primary)),
    );
    try {
      final data        = await api.suggestGoals();
      if (!mounted) return;
      Navigator.pop(context);
      final suggestions = data['suggestions'] as List? ?? [];
      if (!mounted) return;
      final t = _T.of(context);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: t.card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(24))),
        builder: (_) => _AiSuggestionsSheet(
          suggestions: suggestions,
          onAdded:     _fetchAndApply,
        ),
      );
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sub-widgets — each resolves _T.of(context) in its own build()
// ─────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int total, active, completed;
  const _SummaryStrip({
    required this.total, required this.active, required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Row(children: [
      _StripCell('Total',     '$total',     AppColors.primary, t),
      const SizedBox(width: 10),
      _StripCell('Active',    '$active',    AppColors.accent,  t),
      const SizedBox(width: 10),
      _StripCell('Completed', '$completed', AppColors.gold,    t),
    ]);
  }
}

class _StripCell extends StatelessWidget {
  final String label, value;
  final Color  accent;
  final _T     t;
  const _StripCell(this.label, this.value, this.accent, this.t);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.lg,
        border: Border.all(color: t.border),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 22,
            fontWeight: FontWeight.w800, color: accent)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: t.sub)),
      ]),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: t.sub)),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Map    goal;
  final int    index;
  final String currency;
  final VoidCallback onRefresh;
  const _GoalCard({
    required this.goal,     required this.index,
    required this.currency, required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final t    = _T.of(context);
    final gc   = goal['currency']?.toString() ??
        (currency.isNotEmpty ? currency : '');
    final cur  = gc.isNotEmpty ? '$gc ' : '';
    final prog = (goal['progress_percent'] ?? 0.0) as num;
    final curr = (goal['current_amount']   ?? 0.0) as num;
    final targ = (goal['target_amount']    ?? 0.0) as num;
    final done = goal['status'] == 'completed';
    final fmt  = NumberFormat('#,##0', 'en_US');
    final milestones = (goal['milestones'] as List? ?? [])
        .cast<Map>()
        .where((m) => m['reached_at'] != null)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.xl,
        border: Border.all(
            color: done ? AppColors.gold.withOpacity(0.4) : t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: done
                    ? AppColors.gold.withOpacity(0.12)
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(goal['icon'] ?? '🎯',
                  style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal['title'] ?? '', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
              if ((goal['description'] as String? ?? '').isNotEmpty)
                Text(goal['description'], style: TextStyle(
                    fontSize: 12, color: t.sub),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (!done)
              GestureDetector(
                onTap: () => _showContribute(context, gc),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.add,
                      color: AppColors.success, size: 18),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: AppRadius.pill),
                child: const Text('🏆 Done', style: TextStyle(
                    fontSize: 11, color: AppColors.gold,
                    fontWeight: FontWeight.w700)),
              ),
          ]),

          const SizedBox(height: 16),

          // Progress bar
          Stack(children: [
            Container(height: 10,
                decoration: BoxDecoration(
                    color: t.sub.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5))),
            FractionallySizedBox(
              widthFactor: (prog.toDouble() / 100).clamp(0.0, 1.0),
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: done
                        ? [AppColors.gold, const Color(0xFFFFB347)]
                        : [AppColors.primary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text('$cur${fmt.format(curr)} / $cur${fmt.format(targ)}',
                style: TextStyle(fontSize: 12, color: t.sub)),
            Text('${prog.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: done ? AppColors.gold : AppColors.primary)),
          ]),

          if ((goal['target_date'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Iconsax.calendar, size: 12, color: t.sub),
              const SizedBox(width: 4),
              Text('Target: ${goal['target_date']}',
                  style: TextStyle(fontSize: 11, color: t.sub)),
            ]),
          ],

          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6,
              children: milestones.map((m) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.1),
                  borderRadius: AppRadius.pill,
                  border: Border.all(
                      color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Text(m['label'] as String? ?? '',
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ],
        ]),
      ),
    ).animate(delay: Duration(milliseconds: index * 60))
        .fadeIn(duration: 350.ms).slideY(begin: 0.04);
  }

  void _showContribute(BuildContext context, String goalCurrency) {
    final t    = _T.of(context);
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        // Sheet resolves its own theme
        final st = _T.of(sheetCtx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            left: 24, right: 24, top: 28,
          ),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: st.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              Text(goal['icon'] ?? '🎯',
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Add to goal',
                    style: TextStyle(fontSize: 12, color: st.sub)),
                Text(goal['title'] ?? '',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700, color: st.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: st.surface, borderRadius: AppRadius.lg,
                border: Border.all(
                    color: AppColors.success.withOpacity(0.3)),
              ),
              child: TextField(
                controller: ctrl, autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                style: const TextStyle(fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: TextStyle(fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: st.sub.withOpacity(0.35)),
                  prefixIcon: goalCurrency.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 4, top: 16),
                          child: Text(goalCurrency,
                              style: TextStyle(fontSize: 13,
                                  color: st.sub,
                                  fontWeight: FontWeight.w600)))
                      : null,
                  prefixIconConstraints: const BoxConstraints(
                      minWidth: 0, minHeight: 0),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(
                      ctrl.text.replaceAll(',', ''));
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(sheetCtx);
                  try {
                    final result = await api.contributeToGoal(
                        goal['id'], amount);
                    onRefresh();
                    if (result['completed'] == true &&
                        context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              '🏆 GOAL ACHIEVED! Incredible work!'),
                          backgroundColor: AppColors.gold,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } catch (_) {}
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Add to Goal', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: Colors.white)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Create Goal Sheet  (StatefulWidget — resolves own theme in build)
// ─────────────────────────────────────────────────────────────────────────
class _CreateGoalSheet extends StatefulWidget {
  final VoidCallback onCreated;
  final String       currency;
  const _CreateGoalSheet({required this.onCreated, required this.currency});
  @override
  State<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends State<_CreateGoalSheet> {
  final _titleCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type    = 'savings';
  String _icon    = '🎯';
  bool   _loading = false;

  static const _icons = [
    '🎯','💰','🏠','🚗','✈️','📚','💼','🏆','🌟','💎','🌍','🎓',
  ];
  static const _types = [
    'savings','income','skill','debt_payoff','emergency_fund','custom',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await api.createGoal({
        'title':         _titleCtrl.text.trim(),
        'goal_type':     _type,
        'target_amount': double.tryParse(
            _amountCtrl.text.replaceAll(',', '')),
        'icon':          _icon,
        'currency':      widget.currency.isNotEmpty
                             ? widget.currency : 'USD',
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Resolves its own theme
    final t        = _T.of(context);
    final currency = widget.currency;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 28,
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Text('New Financial Goal', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 4),
        Text('Set a target and track your progress',
            style: TextStyle(fontSize: 12, color: t.sub)),
        const SizedBox(height: 20),
        // Icon picker
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _icons.map((ic) => GestureDetector(
              onTap: () => setState(() => _icon = ic),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 46, height: 46,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _icon == ic
                      ? AppColors.primary.withOpacity(0.15) : t.surface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: _icon == ic
                      ? AppColors.primary : t.border),
                ),
                child: Center(child: Text(ic,
                    style: const TextStyle(fontSize: 22))),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          style: TextStyle(fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Goal title (e.g. Emergency Fund)',
            hintStyle: TextStyle(fontSize: 13, color: t.sub),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: AppRadius.md,
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true),
          style: TextStyle(fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Target amount (optional)',
            hintStyle: TextStyle(fontSize: 13, color: t.sub),
            prefixText:  currency.isNotEmpty ? '$currency ' : null,
            prefixStyle: TextStyle(fontSize: 13, color: t.sub),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: AppRadius.md,
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _type,
          dropdownColor: t.card,
          style: TextStyle(fontSize: 14, color: t.text),
          decoration: InputDecoration(
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: AppRadius.md,
                borderSide: BorderSide.none),
          ),
          items: _types.map((tp) => DropdownMenuItem(
            value: tp,
            child: Text(tp.replaceAll('_', ' ')
                .split(' ')
                .map((w) => w.isNotEmpty
                    ? w[0].toUpperCase() + w.substring(1) : w)
                .join(' ')),
          )).toList(),
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _create,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create Goal', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// AI Suggestions Sheet  (StatelessWidget — resolves own theme in build)
// ─────────────────────────────────────────────────────────────────────────
class _AiSuggestionsSheet extends StatelessWidget {
  final List         suggestions;
  final VoidCallback onAdded;
  const _AiSuggestionsSheet({
    required this.suggestions, required this.onAdded,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (ctx, ctrl) {
        final st = _T.of(ctx);
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: st.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('✨',
                    style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('AI-Suggested Goals',
                    style: TextStyle(fontSize: 17,
                        fontWeight: FontWeight.w700, color: st.text)),
                Text('Based on your profile & stage',
                    style: TextStyle(fontSize: 12, color: st.sub)),
              ]),
            ]),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: suggestions.length,
                itemBuilder: (_, i) {
                  final s   = suggestions[i];
                  final fmt = NumberFormat('#,##0', 'en_US');
                  final cur = s['currency']?.toString() ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: st.surface,
                        borderRadius: AppRadius.lg),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(s['icon'] ?? '🎯',
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(s['title'] ?? '',
                            style: TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: st.text))),
                        ElevatedButton(
                          onPressed: () async {
                            await api.createGoal(s);
                            onAdded();
                            if (context.mounted) Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            backgroundColor: AppColors.primary,
                          ),
                          child: const Text('Add',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(s['description'] ?? '',
                          style: TextStyle(
                              fontSize: 12, color: st.sub),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        if (s['target_amount'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: AppRadius.pill),
                            child: Text(
                              '${cur.isNotEmpty ? '$cur ' : ''}'
                              '${fmt.format((s['target_amount'] as num).toInt())}',
                              style: const TextStyle(fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        if ((s['target_date'] ?? '').isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: st.border,
                                borderRadius: AppRadius.pill),
                            child: Text('By ${s['target_date']}',
                                style: TextStyle(
                                    fontSize: 11, color: st.sub)),
                          ),
                      ]),
                      if ((s['ai_notes'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          const Icon(Iconsax.lamp_on,
                              size: 12, color: AppColors.gold),
                          const SizedBox(width: 4),
                          Expanded(child: Text(s['ai_notes'],
                              style: TextStyle(
                                  fontSize: 11, color: st.sub),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                        ]),
                      ],
                    ]),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🎯',
                style: TextStyle(fontSize: 48))),
          ),
          const SizedBox(height: 20),
          Text('No goals yet', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: t.text),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Set your first financial goal and\nlet the AI help you crush it.',
            style: TextStyle(fontSize: 14, color: t.sub),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add),
            label: const Text('Create First Goal'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14)),
          ),
        ]),
      ),
    );
  }
}
