// frontend/lib/screens/expenses/expenses_screen.dart
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
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _kSummary  = 'riseup_expenses_summary_v2';
  static const _kExpenses = 'riseup_expenses_list_v2';
  static const _kBudgets  = 'riseup_budgets_v2';
  static const _kProfile  = 'riseup_finance_profile_v1';

  late TabController _tab;
  Map    _summary  = {};
  List   _expenses = [];
  List   _budgets  = [];
  Map    _profile  = {};
  bool   _loading    = true;
  bool   _refreshing = false;
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
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 3, vsync: this);
    _restoreCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentRefresh();
  }

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sStr = prefs.getString(_kSummary);
      final eStr = prefs.getString(_kExpenses);
      final bStr = prefs.getString(_kBudgets);
      final pStr = prefs.getString(_kProfile);
      if (sStr != null) {
        final s = Map<String, dynamic>.from(jsonDecode(sStr) as Map);
        if (mounted) setState(() { _summary = s; _loading = false; });
      }
      if (eStr != null) {
        if (mounted) setState(() => _expenses = jsonDecode(eStr) as List);
      }
      if (bStr != null) {
        if (mounted) setState(() => _budgets = jsonDecode(bStr) as List);
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
        api.getMonthlySummary(month: _currentMonth),
        api.getExpenses(month: _currentMonth),
        api.getBudgets(month: _currentMonth),
        api.getProfile(),
      ]);
      final summary    = results[0] as Map;
      final expenses   = (results[1] as Map)['expenses'] as List? ?? [];
      final budgets    = (results[2] as Map)['budgets']  as List? ?? [];
      final profile    = ((results[3] as Map)['profile'] as Map?)
                             ?.cast<String, dynamic>() ?? {};
      if (mounted) setState(() {
        _summary    = summary;
        _expenses   = expenses;
        _budgets    = budgets;
        _profile    = profile;
        _loading    = false;
        _refreshing = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kSummary,  jsonEncode(summary)),
        prefs.setString(_kExpenses, jsonEncode(expenses)),
        prefs.setString(_kBudgets,  jsonEncode(budgets)),
        prefs.setString(_kProfile,  jsonEncode(profile)),
      ]);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  String get _currency =>
      _summary['currency']?.toString() ??
      _profile['currency']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Expenses & Budget', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.error.withOpacity(0.5)))),
            ),
          TextButton.icon(
            icon: const Icon(Iconsax.calendar, size: 15,
                color: AppColors.primary),
            label: Text(_currentMonth, style: const TextStyle(
                fontSize: 12, color: AppColors.primary,
                fontWeight: FontWeight.w600)),
            onPressed: _pickMonth,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: t.sub,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Expenses'),
                Tab(text: 'Budgets'),
              ],
            ),
            Divider(height: 1, color: t.border),
          ]),
        ),
      ),
      body: _loading && _summary.isEmpty
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.primary))
          : TabBarView(
              controller: _tab,
              children: [
                _OverviewTab(
                  summary:      _summary,
                  currency:     _currency,
                  currentMonth: _currentMonth,
                  onRefresh:    _fetchAndApply,
                ),
                _ExpensesListTab(
                  expenses:     _expenses,
                  currency:     _currency,
                  currentMonth: _currentMonth,
                  catIcons:     _catIcons,
                  onDelete: (id) async {
                    await api.deleteExpense(id);
                    _fetchAndApply();
                  },
                  onConfirmDelete: _confirmDelete,
                ),
                _BudgetsTab(
                  budgets:      _budgets,
                  categories:   _categories,
                  catIcons:     _catIcons,
                  currency:     _currency,
                  currentMonth: _currentMonth,
                  onSaved:      _fetchAndApply,
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.error,
        onPressed: () => _showLogExpense(context),
        icon: const Icon(Icons.remove, color: Colors.white),
        label: const Text('Log Expense', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600,
            fontSize: 13)),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    final t = _T.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dt = _T.of(ctx);
        return AlertDialog(
          backgroundColor: dt.card,
          title: Text('Delete expense?', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: dt.text)),
          content: Text('This cannot be undone.',
              style: TextStyle(fontSize: 13, color: dt.sub)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.primary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        );
      },
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
      setState(() =>
          _currentMonth = DateFormat('yyyy-MM').format(picked));
      _fetchAndApply();
    }
  }

  void _showLogExpense(BuildContext context) {
    final t = _T.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LogExpenseSheet(
        onLogged: _fetchAndApply,
        currency: _currency,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Overview Tab
// ─────────────────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final Map    summary;
  final String currency, currentMonth;
  final VoidCallback onRefresh;
  const _OverviewTab({
    required this.summary,      required this.currency,
    required this.currentMonth, required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final t         = _T.of(context);
    final income    = (summary['monthly_income'] ?? 0.0) as num;
    final spent     = (summary['total_spent']    ?? 0.0) as num;
    final net       = (summary['net_income']     ?? 0.0) as num;
    final savings   = (summary['savings_rate']   ?? 0.0) as num;
    final breakdown = summary['breakdown'] as List? ?? [];
    final fmt = NumberFormat('#,##0', 'en_US');
    final cur = currency.isNotEmpty ? '$currency ' : '';

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Net income hero
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: net >= 0
                    ? [const Color(0xFF00B894), const Color(0xFF00787A)]
                    : [const Color(0xFFE17055), const Color(0xFFD63031)],
              ),
              borderRadius: AppRadius.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text('Net Income — $currentMonth',
                    style: const TextStyle(fontSize: 12,
                        color: Colors.white70)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: AppRadius.pill),
                  child: Text(
                    net >= 0
                        ? '${savings.toStringAsFixed(1)}% saved'
                        : 'Over budget',
                    style: const TextStyle(fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text('$cur${fmt.format(net.abs())}',
                  style: const TextStyle(fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -1)),
            ]),
          ).animate().fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.97, 0.97)),

          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MetricCard(
              label: 'Income',
              value: '$cur${fmt.format(income)}',
              icon: Iconsax.trend_up, color: AppColors.success,
            )),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(
              label: 'Spent',
              value: '$cur${fmt.format(spent)}',
              icon: Iconsax.trend_down, color: AppColors.error,
            )),
          ]),
          const SizedBox(height: 20),
          Text('Category Breakdown', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 12),
          if (breakdown.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                  color: t.card, borderRadius: AppRadius.lg,
                  border: Border.all(color: t.border)),
              child: Column(children: [
                const Text('📭', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text('No expenses for $currentMonth',
                    style: TextStyle(fontSize: 13, color: t.sub),
                    textAlign: TextAlign.center),
              ]),
            )
          else
            ...breakdown.asMap().entries.map((e) =>
                _CategoryBar(data: e.value, currency: currency,
                    index: e.key)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Expenses List Tab
// ─────────────────────────────────────────────────────────────────────────
class _ExpensesListTab extends StatelessWidget {
  final List   expenses;
  final String currency, currentMonth;
  final Map<String, String> catIcons;
  final Future<void> Function(String) onDelete;
  final Future<bool?> Function(BuildContext) onConfirmDelete;
  const _ExpensesListTab({
    required this.expenses,        required this.currency,
    required this.currentMonth,    required this.catIcons,
    required this.onDelete,        required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t   = _T.of(context);
    final fmt = NumberFormat('#,##0', 'en_US');
    final cur = currency.isNotEmpty ? '$currency ' : '';

    if (expenses.isEmpty) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No expenses for $currentMonth',
            style: TextStyle(fontSize: 14, color: t.sub)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: expenses.length,
      itemBuilder: (ctx, i) {
        final e   = expenses[i];
        final tid = _T.of(ctx);
        return Dismissible(
          key: Key(e['id'].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: AppRadius.lg),
            child: const Icon(Iconsax.trash, color: Colors.white),
          ),
          confirmDismiss: (_) => onConfirmDelete(ctx),
          onDismissed:    (_) => onDelete(e['id'].toString()),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tid.card, borderRadius: AppRadius.lg,
              border: Border.all(color: tid.border),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: tid.surface,
                    borderRadius: AppRadius.md),
                child: Center(child: Text(
                  e['icon'] ?? catIcons[e['category']] ?? '📦',
                  style: const TextStyle(fontSize: 22),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(e['description'] ?? e['category'] ?? 'Expense',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: tid.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${(e['category'] as String? ?? '').replaceAll('_', ' ')} · ${e['spent_at'] ?? ''}',
                  style: TextStyle(fontSize: 11, color: tid.sub),
                ),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '$cur${fmt.format((e['amount'] as num).toDouble())}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: AppColors.error),
                ),
              ),
            ]),
          ).animate(delay: Duration(milliseconds: i * 35))
              .fadeIn().slideX(begin: 0.05),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Budgets Tab
// ─────────────────────────────────────────────────────────────────────────
class _BudgetsTab extends StatelessWidget {
  final List   budgets;
  final List<String> categories;
  final Map<String, String> catIcons;
  final String currency, currentMonth;
  final VoidCallback onSaved;
  const _BudgetsTab({
    required this.budgets,       required this.categories,
    required this.catIcons,      required this.currency,
    required this.currentMonth,  required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final t         = _T.of(context);
    final budgetMap = {for (var b in budgets) b['category']: b};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: AppRadius.lg,
            border: Border.all(
                color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Set monthly limits per category. The AI will factor these into your advice.',
              style: TextStyle(fontSize: 12,
                  color: t.dark ? AppColors.primary
                      : AppColors.primary),
            )),
          ]),
        ),
        const SizedBox(height: 16),
        ...categories.map((cat) {
          final existing = budgetMap[cat];
          final amount   = existing != null
              ? (existing['budget_amount'] as num).toDouble() : 0.0;
          return _BudgetCategoryRow(
            category: cat,
            icon:     catIcons[cat] ?? '📦',
            currentBudget: amount,
            month:    currentMonth,
            currency: currency,
            onSaved:  onSaved,
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Metric Card
// ─────────────────────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    color;
  const _MetricCard({
    required this.label, required this.value,
    required this.icon,  required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.lg,
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 11, color: t.sub)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w700, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Category Bar
// ─────────────────────────────────────────────────────────────────────────
class _CategoryBar extends StatelessWidget {
  final Map    data;
  final String currency;
  final int    index;
  const _CategoryBar({
    required this.data, required this.currency, required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final t        = _T.of(context);
    final spent    = (data['spent']    ?? 0.0) as num;
    final budgeted = (data['budgeted'] ?? 0.0) as num;
    final over     = data['over_budget'] == true;
    final progress = budgeted > 0
        ? (spent / budgeted).clamp(0.0, 1.0) : 0.0;
    final fmt  = NumberFormat('#,##0', 'en_US');
    final icon = data['icon'] ?? '📦';
    final cur  = currency.isNotEmpty ? '$currency ' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.lg,
        border: Border.all(
          color: over ? AppColors.error.withOpacity(0.35) : t.border,
        ),
      ),
      child: Column(children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            (data['category'] ?? '').toString()
                .replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: t.text),
          )),
          Text('$cur${fmt.format(spent.toDouble())}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: over ? AppColors.error : t.text)),
          if (budgeted > 0)
            Text(' / ${fmt.format(budgeted.toDouble())}',
                style: TextStyle(fontSize: 11, color: t.sub)),
          if (over) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OVER', style: TextStyle(
                  fontSize: 8, color: AppColors.error,
                  fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        if (budgeted > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              backgroundColor: t.sub.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(
                  over ? AppColors.error : AppColors.success),
              minHeight: 6,
            ),
          ),
        ],
      ]),
    ).animate(delay: Duration(milliseconds: index * 50))
        .fadeIn().slideX(begin: -0.04);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Budget Category Row
// ─────────────────────────────────────────────────────────────────────────
class _BudgetCategoryRow extends StatefulWidget {
  final String   category, icon, month, currency;
  final double   currentBudget;
  final VoidCallback onSaved;
  const _BudgetCategoryRow({
    required this.category, required this.icon,
    required this.currentBudget, required this.month,
    required this.currency, required this.onSaved,
  });
  @override
  State<_BudgetCategoryRow> createState() =>
      _BudgetCategoryRowState();
}

class _BudgetCategoryRowState extends State<_BudgetCategoryRow> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.currentBudget > 0
          ? widget.currentBudget.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Each row resolves its own theme
    final t = _T.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.lg,
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Text(widget.icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Text(
          widget.category.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600, color: t.text),
        )),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 13, color: t.text),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'Budget',
              hintStyle: TextStyle(fontSize: 12, color: t.sub),
              prefixText: widget.currency.isNotEmpty
                  ? '${widget.currency} ' : null,
              prefixStyle: TextStyle(fontSize: 11, color: t.sub),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              filled: true, fillColor: t.surface,
              border: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _save,
          child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
              : const Icon(Iconsax.tick_circle,
                  color: AppColors.primary, size: 22),
        ),
      ]),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(
        _ctrl.text.replaceAll(',', ''));
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      await api.setBudget({
        'month':         widget.month,
        'category':      widget.category,
        'budget_amount': amount,
        'currency':      widget.currency.isNotEmpty
                             ? widget.currency : 'USD',
      });
      widget.onSaved();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Log Expense Sheet  (StatefulWidget — resolves own theme in build)
// ─────────────────────────────────────────────────────────────────────────
class _LogExpenseSheet extends StatefulWidget {
  final VoidCallback onLogged;
  final String       currency;
  const _LogExpenseSheet({required this.onLogged, required this.currency});

  @override
  State<_LogExpenseSheet> createState() => _LogExpenseSheetState();
}

class _LogExpenseSheetState extends State<_LogExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  String _category  = 'food';
  bool   _loading   = false;

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
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolves own theme — works correctly even inside bottom sheet
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
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: const Center(
                child: Icon(Icons.remove, color: AppColors.error, size: 20)),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Log Expense', style: TextStyle(fontSize: 16,
                fontWeight: FontWeight.w700, color: t.text)),
            Text('Track your spending',
                style: TextStyle(fontSize: 12, color: t.sub)),
          ]),
        ]),
        const SizedBox(height: 24),
        // Amount
        Container(
          decoration: BoxDecoration(
            color: t.surface, borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.error.withOpacity(0.3)),
          ),
          child: TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            style: const TextStyle(fontSize: 30,
                fontWeight: FontWeight.w800, color: AppColors.error),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: t.sub.withOpacity(0.35)),
              prefixIcon: currency.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 4, top: 16),
                      child: Text(currency, style: TextStyle(
                          fontSize: 13, color: t.sub,
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
        const SizedBox(height: 14),
        TextField(
          controller: _descCtrl,
          style: TextStyle(fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Description (optional)',
            hintStyle: TextStyle(fontSize: 13, color: t.sub),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: AppRadius.md,
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        Text('Category', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: t.sub)),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _categories.map((cat) => GestureDetector(
              onTap: () => setState(() => _category = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _category == cat
                      ? AppColors.error.withOpacity(0.12) : t.surface,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: _category == cat
                      ? AppColors.error : t.border),
                ),
                child: Text(
                  '${_catIcons[cat]} ${cat.replaceAll('_', ' ')}',
                  style: TextStyle(fontSize: 12,
                      fontWeight: _category == cat
                          ? FontWeight.w600 : FontWeight.normal,
                      color: _category == cat
                          ? AppColors.error : t.sub),
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : () async {
              final amount = double.tryParse(
                  _amountCtrl.text.replaceAll(',', ''));
              if (amount == null || amount <= 0) return;
              setState(() => _loading = true);
              try {
                await api.logExpense({
                  'amount':      amount,
                  'category':    _category,
                  'description': _descCtrl.text.trim().isEmpty
                      ? null : _descCtrl.text.trim(),
                  'currency':    currency.isNotEmpty
                      ? currency : 'USD',
                });
                widget.onLogged();
                if (mounted) Navigator.pop(context);
              } catch (_) {
                if (mounted) setState(() => _loading = false);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Log Expense', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
