// frontend/lib/screens/earnings/earnings_screen.dart
// v4.0 — Every widget resolves Theme.of(context) independently. No color drilling.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

// ── Theme helper – used by every widget in this file ─────────────────────
class _T {
  final bool   dark;
  final Color  bg, card, surface, border, text, sub;
  const _T({
    required this.dark,    required this.bg,
    required this.card,    required this.surface,
    required this.border,  required this.text,
    required this.sub,
  });

  factory _T.of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return _T(
      dark:    dark,
      bg:      dark ? Colors.black           : Colors.white,
      card:    dark ? AppColors.bgCard       : Colors.white,
      surface: dark ? AppColors.bgSurface    : Colors.grey.shade100,
      border:  dark ? AppColors.bgSurface    : Colors.grey.shade200,
      text:    dark ? Colors.white           : Colors.black87,
      sub:     dark ? Colors.white54         : Colors.black54,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with WidgetsBindingObserver {
  static const _kEarnings = 'riseup_earnings_v2';
  static const _kProfile  = 'riseup_finance_profile_v1';

  Map  _earnings = {};
  Map  _profile  = {};
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
      final eStr  = prefs.getString(_kEarnings);
      final pStr  = prefs.getString(_kProfile);
      if (eStr != null) {
        final e = Map<String, dynamic>.from(jsonDecode(eStr) as Map);
        if (mounted) setState(() { _earnings = e; _loading = false; });
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
        api.getEarnings(),
        api.getProfile(),
      ]);
      final earnings   = results[0] as Map;
      final profileRes = results[1] as Map;
      final profile    = (profileRes['profile'] as Map?)
                             ?.cast<String, dynamic>() ?? {};
      if (mounted) setState(() {
        _earnings   = earnings;
        _profile    = profile;
        _loading    = false;
        _refreshing = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kEarnings, jsonEncode(earnings)),
        prefs.setString(_kProfile,  jsonEncode(profile)),
      ]);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  String get _currency => _profile['currency']?.toString() ?? '';

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtShort(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  double _sumBySource(List<Map> list, String src) => list
      .where((e) => e['source_type'] == src)
      .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());

  void _showLogEarning() {
    final t          = _T.of(context);
    final currency   = _currency;
    final amountCtrl = TextEditingController();
    String sourceType = 'freelance';
    String desc       = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) {
          final st = _T.of(ctx);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 28, 24, MediaQuery.of(ctx).viewInsets.bottom + 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: st.border,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                        child: Text('💰', style: TextStyle(fontSize: 20)))),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Log Earning', style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w700, color: st.text)),
                    Text('Track any income earned',
                        style: TextStyle(fontSize: 12, color: st.sub)),
                  ]),
                ]),
                const SizedBox(height: 24),
                // Amount
                Container(
                  decoration: BoxDecoration(
                    color: st.surface, borderRadius: AppRadius.lg,
                    border: Border.all(
                        color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: TextField(
                    controller: amountCtrl, autofocus: true,
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
                      prefixIcon: currency.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 4, top: 16),
                              child: Text(currency, style: TextStyle(
                                  fontSize: 13, color: st.sub,
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
                const SizedBox(height: 20),
                Text('Source', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600, color: st.sub)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8,
                  children: [
                    for (final s in [
                      ('freelance',  '💼', 'Freelance'),
                      ('skill',      '📚', 'Skills'),
                      ('business',   '🏢', 'Business'),
                      ('investment', '📈', 'Investment'),
                      ('other',      '💡', 'Other'),
                    ])
                      GestureDetector(
                        onTap: () => set(() => sourceType = s.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sourceType == s.$1
                                ? AppColors.success.withOpacity(0.12)
                                : st.surface,
                            borderRadius: AppRadius.pill,
                            border: Border.all(color: sourceType == s.$1
                                ? AppColors.success : st.border),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(s.$2,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(s.$3, style: TextStyle(
                              fontSize: 12,
                              fontWeight: sourceType == s.$1
                                  ? FontWeight.w600 : FontWeight.normal,
                              color: sourceType == s.$1
                                  ? AppColors.success : st.sub,
                            )),
                          ]),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  style: TextStyle(fontSize: 14, color: st.text),
                  onChanged: (v) => desc = v,
                  decoration: InputDecoration(
                    hintText: 'Note (optional)',
                    hintStyle: TextStyle(fontSize: 13, color: st.sub),
                    filled: true, fillColor: st.surface,
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.md,
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                GradientButton(
                  text: 'Log Earning',
                  colors: [AppColors.success, AppColors.accent],
                  onTap: () async {
                    final amount = double.tryParse(amountCtrl.text);
                    if (amount == null || amount <= 0) return;
                    Navigator.pop(context);
                    await api.logEarning(
                      amount:      amount,
                      sourceType:  sourceType,
                      description: desc.isEmpty ? null : desc,
                      currency:    currency.isNotEmpty ? currency : 'USD',
                    );
                    await _fetchAndApply();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('💰 ${currency.isNotEmpty ? '$currency ' : ''}'
                            '${_fmt(amount)} logged!'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t         = _T.of(context);
    final currency  = _currency;
    final total     = (_earnings['total']     ?? 0.0) as num;
    final count     = (_earnings['count']     ?? 0)   as num;
    final breakdown = (_earnings['breakdown'] as List?)?.cast<Map>() ?? [];

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Earnings', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: t.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.success.withOpacity(0.5)))),
            ),
          IconButton(
            icon: Icon(Iconsax.refresh, color: t.sub, size: 22),
            onPressed: _fetchAndApply,
          ),
        ],
      ),
      body: _loading && _earnings.isEmpty
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.success))
          : RefreshIndicator(
              onRefresh: _fetchAndApply,
              color: AppColors.success,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroCard(
                      currency: currency,
                      total: total.toDouble(),
                      count: count.toInt(),
                      fmtFn: _fmt,
                    ).animate().fadeIn().slideY(begin: -0.04),

                    const SizedBox(height: 20),

                    GradientButton(
                      text: '+ Log Earning',
                      colors: [AppColors.success, AppColors.accent],
                      onTap: _showLogEarning,
                    ).animate().fadeIn(delay: 80.ms),

                    const SizedBox(height: 28),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('By Source', style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w700, color: t.text)),
                        if (total > 0)
                          Text('${count.toInt()} entries',
                              style: TextStyle(fontSize: 12, color: t.sub)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SourceRow(
                      breakdown:   breakdown,
                      currency:    currency,
                      total:       total.toDouble(),
                      sumBySource: _sumBySource,
                      fmtShort:    _fmtShort,
                    ).animate().fadeIn(delay: 120.ms),

                    const SizedBox(height: 28),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Activity', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            color: t.text)),
                        Text('Last ${breakdown.length > 10
                            ? 10 : breakdown.length} entries',
                            style: TextStyle(fontSize: 12, color: t.sub)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (breakdown.isEmpty)
                      const _EmptyEarnings()
                          .animate().fadeIn(delay: 160.ms)
                    else
                      ...breakdown.reversed.take(10).toList()
                          .asMap().entries.map((e) => _EarningTile(
                            earning:  e.value,
                            currency: currency,
                          )
                          .animate()
                          .fadeIn(delay: Duration(
                              milliseconds: 160 + e.key * 40))
                          .slideX(begin: 0.05)),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sub-widgets — each resolves _T.of(context) in its own build()
// ─────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String currency;
  final double total;
  final int    count;
  final String Function(double) fmtFn;
  const _HeroCard({
    required this.currency, required this.total,
    required this.count,    required this.fmtFn,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.card,
        gradient: LinearGradient(
          colors: [AppColors.success.withOpacity(0.1), t.card],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.success.withOpacity(0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: AppRadius.pill,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Total Earned via RiseUp',
                style: TextStyle(fontSize: 11,
                    color: AppColors.success, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (currency.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 7, right: 4),
              child: Text(currency, style: TextStyle(
                  fontSize: 16, color: t.sub, fontWeight: FontWeight.w600)),
            ),
          Text(fmtFn(total), style: const TextStyle(
            fontSize: 42, fontWeight: FontWeight.w800,
            color: AppColors.success, letterSpacing: -1.5,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Iconsax.receipt_item, size: 13, color: t.sub),
          const SizedBox(width: 6),
          Text('$count income ${count == 1 ? 'entry' : 'entries'} logged',
              style: TextStyle(fontSize: 12, color: t.sub)),
        ]),
      ]),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final List<Map>  breakdown;
  final String     currency;
  final double     total;
  final double Function(List<Map>, String) sumBySource;
  final String Function(double)            fmtShort;
  const _SourceRow({
    required this.breakdown,   required this.currency,
    required this.total,       required this.sumBySource,
    required this.fmtShort,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    final sources = [
      ('Tasks',  'task',  AppColors.primary, Iconsax.task_square),
      ('Skills', 'skill', AppColors.accent,  Iconsax.book),
      ('Other',  'other', AppColors.gold,    Iconsax.category),
    ];
    return Row(
      children: List.generate(sources.length, (i) {
        final s      = sources[i];
        final amount = sumBySource(breakdown, s.$2);
        final pct    = total > 0 ? (amount / total * 100).round() : 0;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < sources.length - 1 ? 10 : 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.card, borderRadius: AppRadius.lg,
              border: Border.all(color: t.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Icon(s.$4, color: s.$3, size: 18),
                if (total > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: s.$3.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('$pct%', style: TextStyle(
                        fontSize: 9, color: s.$3,
                        fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 10),
              Text('${currency.isNotEmpty ? '$currency ' : ''}'
                  '${fmtShort(amount)}',
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: s.$3)),
              const SizedBox(height: 2),
              Text(s.$1, style: TextStyle(fontSize: 11, color: t.sub)),
            ]),
          ),
        );
      }),
    );
  }
}

class _EmptyEarnings extends StatelessWidget {
  const _EmptyEarnings();
  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
          color: t.card, borderRadius: AppRadius.lg,
          border: Border.all(color: t.border)),
      child: Column(children: [
        Icon(Iconsax.wallet, size: 44, color: t.sub),
        const SizedBox(height: 16),
        Text('No earnings yet', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 6),
        Text('Complete tasks or log income\nto start tracking here',
            style: TextStyle(fontSize: 13, color: t.sub),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _EarningTile extends StatelessWidget {
  final Map    earning;
  final String currency;
  const _EarningTile({required this.earning, required this.currency});

  IconData get _icon {
    switch (earning['source_type']) {
      case 'task':
      case 'freelance':  return Iconsax.briefcase;
      case 'skill':      return Iconsax.book;
      case 'investment': return Iconsax.chart;
      case 'business':   return Iconsax.shop;
      case 'referral':   return Iconsax.people;
      default:           return Iconsax.dollar_circle;
    }
  }

  Color get _color {
    switch (earning['source_type']) {
      case 'task':
      case 'freelance':  return AppColors.primary;
      case 'skill':      return AppColors.accent;
      case 'investment': return AppColors.gold;
      case 'business':   return AppColors.success;
      default:           return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t        = _T.of(context);
    final amount   = (earning['amount'] as num).toDouble();
    final earnedAt = earning['earned_at'] as String?;
    DateTime? date;
    if (earnedAt != null) {
      try { date = DateTime.parse(earnedAt); } catch (_) {}
    }
    final label = earning['description']?.toString().isNotEmpty == true
        ? earning['description'].toString()
        : (earning['source_type']?.toString() ?? 'Income');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.card, borderRadius: AppRadius.md,
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: _color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(_icon, color: _color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label, style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: t.text),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (date != null)
            Text(DateFormat('MMM d, yyyy · h:mm a').format(date.toLocal()),
                style: TextStyle(fontSize: 11, color: t.sub)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Text(
            '+${currency.isNotEmpty ? '$currency ' : ''}'
            '${amount.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: AppColors.success),
          ),
        ),
      ]),
    );
  }
}
