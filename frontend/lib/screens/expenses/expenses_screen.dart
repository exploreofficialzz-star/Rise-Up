import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map _summary = {};
  List _expenses = [];
  List _budgets = [];
  bool _loading = true;
  String _currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

  static const _categories = [
    'food','transport','rent','utilities','entertainment',
    'clothing','health','education','savings','debt','business','other',
  ];
  static const _catIcons = {
    'food':'🍔','transport':'🚗','rent':'🏠','utilities':'⚡',
    'entertainment':'🎮','clothing':'👗','health':'🏥',
    'education':'📚','savings':'💰','debt':'💳','business':'💼','other':'📦',
  };

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getMonthlySummary(month: _currentMonth),
        api.getExpenses(month: _currentMonth),
        api.getBudgets(month: _currentMonth),
      ]);
      setState(() {
        _summary  = results[0];
        _expenses = (results[1] as Map)['expenses'] as List? ?? [];
        _budgets  = (results[2] as Map)['budgets']  as List? ?? [];
        _loading  = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Expenses & Budget', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
        actions: [
          // Month picker
          TextButton.icon(
            icon: const Icon(Iconsax.calendar, size: 16, color: AppColors.primary),
            label: Text(_currentMonth,
                style: AppTextStyles.label.copyWith(color: AppColors.primary)),
            onPressed: _pickMonth,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Expenses'),
            Tab(text: 'Budgets'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tab,
              children: [
                _buildOverview(),
                _buildExpensesList(),
                _buildBudgetsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.error,
        onPressed: () => _showLogExpense(context),
        icon: const Icon(Icons.remove, color: Colors.white),
        label: Text('Log Expense', style: AppTextStyles.label.copyWith(color: Colors.white)),
      ),
    );
  }

  Widget _buildOverview() {
    final currency     = _summary['currency']?.toString() ?? 'NGN';
    final income       = (_summary['monthly_income'] ?? 0.0) as num;
    final spent        = (_summary['total_spent'] ?? 0.0) as num;
    final net          = (_summary['net_income'] ?? 0.0) as num;
    final savingsRate  = (_summary['savings_rate'] ?? 0.0) as num;
    final breakdown    = (_summary['breakdown'] as List? ?? []);
    final fmt          = NumberFormat('#,##0', 'en_US');

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Net income card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: net >= 0
                    ? [const Color(0xFF00B894), const Color(0xFF00787A)]
                    : [const Color(0xFFE17055), const Color(0xFFD63031)],
              ),
              borderRadius: AppRadius.xl,
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Income — $_currentMonth',
                    style: AppTextStyles.label.copyWith(color: Colors.white70)),
                const SizedBox(height: 8),
                Text('$currency ${fmt.format(net.abs())}',
                    style: AppTextStyles.h1.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(net >= 0 ? 'Savings rate: ${savingsRate.toStringAsFixed(1)}%' : 'Over budget this month',
                    style: AppTextStyles.bodySmall.copyWith(color: Colors.white70)),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95,0.95)),
          const SizedBox(height: 12),
          // Income vs Spent row
          Row(children: [
            Expanded(child: _MetricCard(
              label: 'Income', value: '$currency ${fmt.format(income)}',
              icon: Iconsax.trend_up, color: AppColors.success,
            )),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(
              label: 'Spent', value: '$currency ${fmt.format(spent)}',
              icon: Iconsax.trend_down, color: AppColors.error,
            )),
          ]),
          const SizedBox(height: 20),
          Text('Category Breakdown', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          if (breakdown.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No expenses logged yet for $_currentMonth',
                  style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                  textAlign: TextAlign.center),
            ))
          else
            ...breakdown.asMap().entries.map((e) => _CategoryBar(
              data: e.value, currency: currency, index: e.key,
            )),
        ],
      ),
    );
  }

  Widget _buildExpensesList() {
    final fmt = NumberFormat('#,##0', 'en_US');
    if (_expenses.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No expenses logged for $_currentMonth',
            style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expenses.length,
      itemBuilder: (_, i) {
        final e = _expenses[i];
        return Dismissible(
          key: Key(e['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: AppColors.error, borderRadius: AppRadius.lg),
            child: const Icon(Iconsax.trash, color: Colors.white),
          ),
          onDismissed: (_) async {
            await api.deleteExpense(e['id']);
            _load();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.bgCard, borderRadius: AppRadius.lg),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: AppColors.bgSurface, borderRadius: AppRadius.md),
                child: Center(child: Text(e['icon'] ?? '📦',
                    style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['description'] ?? e['category'] ?? 'Expense',
                    style: AppTextStyles.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${e['category']} · ${e['spent_at']}',
                    style: AppTextStyles.caption),
              ])),
              Text('${e['currency']} ${fmt.format((e['amount'] as num).toDouble())}',
                  style: AppTextStyles.h4.copyWith(color: AppColors.error)),
            ]),
          ).animate(delay: Duration(milliseconds: i * 40)).fadeIn().slideX(begin: 0.1),
        );
      },
    );
  }

  Widget _buildBudgetsTab() {
    final budgetMap = {for (var b in _budgets) b['category']: b};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3))),
          child: Text(
            '💡 Set monthly spending limits per category. The AI will factor these into your advice.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        ..._categories.map((cat) {
          final existing = budgetMap[cat];
          final amount = existing != null
              ? (existing['budget_amount'] as num).toDouble() : 0.0;
          return _BudgetCategoryRow(
            category: cat,
            icon: _catIcons[cat] ?? '📦',
            currentBudget: amount,
            month: _currentMonth,
            onSaved: _load,
          );
        }),
      ],
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Select Month',
    );
    if (picked != null) {
      setState(() => _currentMonth = DateFormat('yyyy-MM').format(picked));
      _load();
    }
  }

  void _showLogExpense(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LogExpenseSheet(onLogged: _load),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.caption),
      ]),
      const SizedBox(height: 6),
      Text(value, style: AppTextStyles.h4.copyWith(color: color)),
    ]),
  );
}

class _CategoryBar extends StatelessWidget {
  final Map data;
  final String currency;
  final int index;
  const _CategoryBar({required this.data, required this.currency, required this.index});

  @override
  Widget build(BuildContext context) {
    final spent    = (data['spent'] ?? 0.0) as num;
    final budgeted = (data['budgeted'] ?? 0.0) as num;
    final over     = data['over_budget'] == true;
    final progress = budgeted > 0 ? (spent / budgeted).clamp(0.0, 1.0) : 0.0;
    final fmt      = NumberFormat('#,##0', 'en_US');
    final icon     = data['icon'] ?? '📦';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.bgCard, borderRadius: AppRadius.lg,
          border: Border.all(color: over ? AppColors.error.withOpacity(0.3) : Colors.transparent)),
      child: Column(children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            (data['category'] ?? '').toString().replaceAll('_', ' ').toUpperCase(),
            style: AppTextStyles.label,
          )),
          Text('$currency ${fmt.format(spent.toDouble())}',
              style: AppTextStyles.label.copyWith(color: over ? AppColors.error : AppColors.textPrimary)),
          if (budgeted > 0)
            Text(' / ${fmt.format(budgeted.toDouble())}',
                style: AppTextStyles.caption),
        ]),
        if (budgeted > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              backgroundColor: AppColors.bgSurface,
              valueColor: AlwaysStoppedAnimation(over ? AppColors.error : AppColors.success),
              minHeight: 6,
            ),
          ),
        ],
      ]),
    ).animate(delay: Duration(milliseconds: index * 50)).fadeIn().slideX(begin: -0.1);
  }
}

class _BudgetCategoryRow extends StatefulWidget {
  final String category, icon, month;
  final double currentBudget;
  final VoidCallback onSaved;
  const _BudgetCategoryRow({
    required this.category, required this.icon,
    required this.currentBudget, required this.month, required this.onSaved,
  });
  @override
  State<_BudgetCategoryRow> createState() => _BudgetCategoryRowState();
}

class _BudgetCategoryRowState extends State<_BudgetCategoryRow> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.currentBudget > 0 ? widget.currentBudget.toStringAsFixed(0) : '',
    );
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
    child: Row(children: [
      Text(widget.icon, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 12),
      Expanded(child: Text(
        widget.category.replaceAll('_', ' ').toUpperCase(),
        style: AppTextStyles.label,
      )),
      SizedBox(
        width: 100,
        child: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          style: AppTextStyles.body.copyWith(fontSize: 13),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: 'Budget',
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true, fillColor: AppColors.bgSurface,
            border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _save,
        child: _saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : const Icon(Iconsax.tick_circle, color: AppColors.primary, size: 22),
      ),
    ]),
  );

  Future<void> _save() async {
    final amount = double.tryParse(_ctrl.text.replaceAll(',', ''));
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      await api.setBudget({
        'month': widget.month, 'category': widget.category,
        'budget_amount': amount, 'currency': 'NGN',
      });
      widget.onSaved();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }
}

class _LogExpenseSheet extends StatefulWidget {
  final VoidCallback onLogged;
  const _LogExpenseSheet({required this.onLogged});
  @override
  State<_LogExpenseSheet> createState() => _LogExpenseSheetState();
}

class _LogExpenseSheetState extends State<_LogExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  String _category  = 'food';
  bool _loading = false;

  static const _categories = [
    'food','transport','rent','utilities','entertainment',
    'clothing','health','education','savings','debt','business','other',
  ];
  static const _catIcons = {
    'food':'🍔','transport':'🚗','rent':'🏠','utilities':'⚡',
    'entertainment':'🎮','clothing':'👗','health':'🏥',
    'education':'📚','savings':'💰','debt':'💳','business':'💼','other':'📦',
  };

  @override
  void dispose() { _amountCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      left: 24, right: 24, top: 28,
    ),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Log Expense', style: AppTextStyles.h3),
      const SizedBox(height: 20),
      TextField(
        controller: _amountCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        style: AppTextStyles.body,
        decoration: const InputDecoration(hintText: 'Amount (NGN)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descCtrl,
        style: AppTextStyles.body,
        decoration: const InputDecoration(hintText: 'Description (optional)'),
      ),
      const SizedBox(height: 12),
      // Category chips
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _categories.map((cat) => GestureDetector(
            onTap: () => setState(() => _category = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _category == cat ? AppColors.primary : AppColors.bgSurface,
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                '${_catIcons[cat]} ${cat.replaceAll('_', ' ')}',
                style: AppTextStyles.label.copyWith(
                  color: _category == cat ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          )).toList(),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : () async {
            final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
            if (amount == null || amount <= 0) return;
            setState(() => _loading = true);
            try {
              await api.logExpense({
                'amount': amount, 'category': _category,
                'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                'currency': 'NGN',
              });
              widget.onLogged();
              if (mounted) Navigator.pop(context);
            } catch (_) { setState(() => _loading = false); }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Log Expense'),
        ),
      ),
    ]),
  );
}
