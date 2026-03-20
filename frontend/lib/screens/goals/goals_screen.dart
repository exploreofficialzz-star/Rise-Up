import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List _goals = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getGoals();
      setState(() { _goals = data['goals'] as List? ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final activeGoals = _goals.where((g) => g['status'] == 'active').toList();
    final doneGoals   = _goals.where((g) => g['status'] == 'completed').toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('My Goals', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
        actions: [
          IconButton(
            icon: const Icon(Iconsax.magic_star, color: AppColors.accent),
            tooltip: 'AI Goal Suggestions',
            onPressed: () => _showAiSuggestions(context),
          ),
          IconButton(
            icon: const Icon(Iconsax.add_circle, color: AppColors.primary),
            onPressed: () => _showCreateGoal(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _goals.isEmpty
                  ? _EmptyState(onTap: () => _showCreateGoal(context))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (activeGoals.isNotEmpty) ...[
                          _SectionHeader('Active Goals (${activeGoals.length})'),
                          ...activeGoals.asMap().entries.map((e) =>
                              _GoalCard(goal: e.value, index: e.key, onRefresh: _load)),
                        ],
                        if (doneGoals.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _SectionHeader('Completed 🏆 (${doneGoals.length})'),
                          ...doneGoals.asMap().entries.map((e) =>
                              _GoalCard(goal: e.value, index: e.key, onRefresh: _load)),
                        ],
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showCreateGoal(context),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('New Goal', style: AppTextStyles.label.copyWith(color: Colors.white)),
      ),
    );
  }

  void _showCreateGoal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreateGoalSheet(onCreated: _load),
    );
  }

  void _showAiSuggestions(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final data = await api.suggestGoals();
      if (!mounted) return;
      Navigator.pop(context);
      final suggestions = data['suggestions'] as List? ?? [];
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bgCard,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _AiSuggestionsSheet(suggestions: suggestions, onAdded: _load),
      );
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(label, style: AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
  );
}

class _GoalCard extends StatelessWidget {
  final Map goal;
  final int index;
  final VoidCallback onRefresh;
  const _GoalCard({required this.goal, required this.index, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final progress = (goal['progress_percent'] ?? 0.0) as num;
    final current  = (goal['current_amount'] ?? 0.0) as num;
    final target   = (goal['target_amount'] ?? 0.0) as num;
    final currency = goal['currency']?.toString() ?? 'NGN';
    final done     = goal['status'] == 'completed';
    final fmt      = NumberFormat('#,##0', 'en_US');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.xl,
        border: Border.all(
          color: done ? AppColors.gold.withOpacity(0.4) : AppColors.bgSurface,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(goal['icon'] ?? '🎯', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(goal['title'] ?? '', style: AppTextStyles.h4),
                  if (goal['description'] != null)
                    Text(goal['description'], style: AppTextStyles.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (!done)
                IconButton(
                  icon: const Icon(Iconsax.add_circle, color: AppColors.success, size: 22),
                  onPressed: () => _showContribute(context),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.toDouble() / 100,
              backgroundColor: AppColors.bgSurface,
              valueColor: AlwaysStoppedAnimation(
                done ? AppColors.gold : AppColors.primary,
              ),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$currency ${fmt.format(current)} / ${fmt.format(target)}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              Text(
                '${progress.toStringAsFixed(0)}%',
                style: AppTextStyles.label.copyWith(
                  color: done ? AppColors.gold : AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (goal['target_date'] != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Iconsax.calendar, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text('By ${goal['target_date']}', style: AppTextStyles.caption),
            ]),
          ],
        ],
      ),
    ).animate(delay: Duration(milliseconds: index * 60)).fadeIn(duration: 350.ms).slideX(begin: -0.1);
  }

  void _showContribute(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to "${goal['title']}"', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'Amount (${goal['currency'] ?? 'NGN'})',
                hintStyle: AppTextStyles.label,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(ctrl.text.replaceAll(',', ''));
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(context);
                  try {
                    final result = await api.contributeToGoal(goal['id'], amount);
                    onRefresh();
                    if (result['completed'] == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🏆 GOAL ACHIEVED! Incredible work!'),
                          backgroundColor: AppColors.gold,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } catch (_) {}
                },
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGoalSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateGoalSheet({required this.onCreated});
  @override
  State<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends State<_CreateGoalSheet> {
  final _titleCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'savings';
  String _icon = '🎯';
  bool _loading = false;

  static const _icons = ['🎯','💰','🏠','🚗','✈️','📚','💼','🏆','🌟','💎'];
  static const _types = ['savings','income','skill','debt_payoff','emergency_fund','custom'];

  @override
  void dispose() { _titleCtrl.dispose(); _amountCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await api.createGoal({
        'title':         _titleCtrl.text.trim(),
        'goal_type':     _type,
        'target_amount': double.tryParse(_amountCtrl.text.replaceAll(',', '')),
        'icon':          _icon,
        'currency':      'NGN',
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Financial Goal', style: AppTextStyles.h3),
          const SizedBox(height: 20),
          // Icon picker
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _icons.map((ic) => GestureDetector(
                onTap: () => setState(() => _icon = ic),
                child: Container(
                  width: 44, height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _icon == ic ? AppColors.primary.withOpacity(0.2) : AppColors.bgSurface,
                    borderRadius: AppRadius.md,
                    border: Border.all(
                      color: _icon == ic ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                  child: Center(child: Text(ic, style: const TextStyle(fontSize: 22))),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleCtrl,
            style: AppTextStyles.body,
            decoration: const InputDecoration(hintText: 'Goal title (e.g. Emergency Fund)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body,
            decoration: const InputDecoration(hintText: 'Target amount (optional)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _type,
            dropdownColor: AppColors.bgCard,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              fillColor: AppColors.bgSurface,
              filled: true,
              border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
            ),
            items: _types.map((t) => DropdownMenuItem(
              value: t,
              child: Text(t.replaceAll('_', ' ').toUpperCase()),
            )).toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Goal'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSuggestionsSheet extends StatelessWidget {
  final List suggestions;
  final VoidCallback onAdded;
  const _AiSuggestionsSheet({required this.suggestions, required this.onAdded});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('✨', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Text('AI-Suggested Goals', style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 4),
            Text('Based on your profile & stage', style: AppTextStyles.bodySmall),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: suggestions.length,
                itemBuilder: (_, i) {
                  final s = suggestions[i];
                  final fmt = NumberFormat('#,##0', 'en_US');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(s['icon'] ?? '🎯', style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s['title'] ?? '', style: AppTextStyles.h4)),
                          ElevatedButton(
                            onPressed: () async {
                              await api.createGoal(s);
                              onAdded();
                              if (context.mounted) Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              backgroundColor: AppColors.primary,
                            ),
                            child: const Text('Add', style: TextStyle(fontSize: 12)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(s['description'] ?? '',
                            style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Text(
                          '${s['currency'] ?? 'NGN'} ${fmt.format((s['target_amount'] ?? 0).toInt())} by ${s['target_date'] ?? ''}',
                          style: AppTextStyles.label.copyWith(color: AppColors.accent),
                        ),
                        if (s['ai_notes'] != null) ...[
                          const SizedBox(height: 6),
                          Text('💡 ${s['ai_notes']}',
                              style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('No goals yet', style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Set your first financial goal and let the AI help you crush it.',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add),
            label: const Text('Create First Goal'),
          ),
        ],
      ),
    ),
  );
}
