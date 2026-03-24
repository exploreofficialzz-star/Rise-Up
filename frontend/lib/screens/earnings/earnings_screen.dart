import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map _earnings = {};
  Map _profile = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await api.getEarnings();
      final p = await api.getProfile();
      setState(() {
        _earnings = e;
        _profile = p['profile'] as Map? ?? {};
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logManualEarning() async {
    final amountCtrl = TextEditingController();
    String sourceType = 'other';
    String descCtrl = '';

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💰 Log Manual Earning', style: AppTextStyles.h4),
              const SizedBox(height: 4),
              Text('Track any income earned outside RiseUp tasks',
                  style: AppTextStyles.bodySmall),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  labelStyle: AppTextStyles.label,
                  prefixText:
                      '${_profile['currency'] ?? 'NGN'} ',
                  prefixStyle: AppTextStyles.body
                      .copyWith(color: AppColors.success),
                ),
              ),
              const SizedBox(height: 16),
              // Source type chips
              Text('Source type', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in [
                    ('freelance', '💼'),
                    ('skill', '📚'),
                    ('business', '🏢'),
                    ('investment', '📈'),
                    ('other', '💡'),
                  ])
                    GestureDetector(
                      onTap: () => set(() => sourceType = s.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sourceType == s.$1
                              ? AppColors.primary.withOpacity(0.2)
                              : AppColors.bgSurface,
                          borderRadius: AppRadius.pill,
                          border: Border.all(
                            color: sourceType == s.$1
                                ? AppColors.primary
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          '${s.$2} ${s.$1}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: sourceType == s.$1
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                style: AppTextStyles.body,
                onChanged: (v) => descCtrl = v,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  labelStyle: AppTextStyles.label,
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                text: 'Log Earning',
                onTap: () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(context);
                  await api.logEarning(
                    amount: amount,
                    sourceType: sourceType,
                    description: descCtrl.isEmpty ? null : descCtrl,
                    currency: _profile['currency']?.toString() ?? 'NGN',
                  );
                  await _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '💰 ${_profile['currency'] ?? 'NGN'} ${amount.toStringAsFixed(0)} logged!'),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = _profile['currency']?.toString() ?? 'NGN';
    final total = (_earnings['total'] ?? 0.0) as num;
    final count = (_earnings['count'] ?? 0) as num;
    final breakdown =
        (_earnings['breakdown'] as List?)?.cast<Map>() ?? [];

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Earnings', style: AppTextStyles.h3),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Total earned hero ────────────────────
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.success.withOpacity(0.2),
                            AppColors.bgCard,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: AppRadius.xl,
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Earned via RiseUp',
                              style: AppTextStyles.label),
                          const SizedBox(height: 6),
                          Text(
                            '$currency ${_fmt(total.toDouble())}',
                            style: AppTextStyles.money,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$count income entries logged',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.success),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(),

                    const SizedBox(height: 24),

                    // ── Quick-log button ─────────────────────
                    GradientButton(
                      text: '+ Log Manual Earning',
                      onTap: _logManualEarning,
                      colors: [AppColors.success, AppColors.accent],
                    ).animate().fadeIn(delay: 80.ms),

                    const SizedBox(height: 28),

                    // ── Source breakdown cards ───────────────
                    Text('By Source', style: AppTextStyles.h4),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final s in [
                          ('Tasks', 'task', AppColors.primary, Iconsax.task),
                          ('Skills', 'skill', AppColors.accent, Iconsax.book),
                          ('Other', 'other', AppColors.gold,
                              Iconsax.category),
                        ])
                          Expanded(
                            child: Container(
                              margin: EdgeInsets.only(
                                  right: s.$1 != 'Other' ? 10 : 0),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius: AppRadius.lg,
                                border: Border.all(
                                    color: s.$3.withOpacity(0.15)),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(s.$4, color: s.$3, size: 18),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$currency ${_fmtShort(_sumBySource(breakdown, s.$2))}',
                                    style: AppTextStyles.h4
                                        .copyWith(color: s.$3, fontSize: 14),
                                  ),
                                  Text(s.$1,
                                      style: AppTextStyles.caption),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ).animate().fadeIn(delay: 120.ms),

                    const SizedBox(height: 28),

                    // ── Recent earnings list ─────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Activity', style: AppTextStyles.h4),
                        Text('Last 10 entries',
                            style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (breakdown.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: AppRadius.lg,
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Iconsax.wallet,
                                  size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text('No earnings yet',
                                  style: AppTextStyles.h4),
                              const SizedBox(height: 6),
                              Text(
                                  'Complete tasks or log income to track here',
                                  style: AppTextStyles.bodySmall,
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 160.ms)
                    else
                      ...breakdown.reversed.toList().asMap().entries.map(
                            (e) => _EarningTile(
                              earning: e.value,
                              currency: currency,
                            )
                                .animate()
                                .fadeIn(
                                    delay: Duration(
                                        milliseconds: 160 + e.key * 50))
                                .slideX(begin: 0.05),
                          ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  double _sumBySource(List<Map> list, String source) {
    return list
        .where((e) => e['source_type'] == source)
        .fold(0.0, (sum, e) => sum + ((e['amount'] as num).toDouble()));
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtShort(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _EarningTile extends StatelessWidget {
  final Map earning;
  final String currency;
  const _EarningTile({required this.earning, required this.currency});

  IconData get _icon {
    switch (earning['source_type']) {
      case 'task':
        return Iconsax.task_square;
      case 'skill':
        return Iconsax.book;
      case 'investment':
        return Iconsax.chart;
      case 'business':
        return Iconsax.shop;
      case 'referral':
        return Iconsax.people;
      default:
        return Iconsax.dollar_circle;
    }
  }

  Color get _color {
    switch (earning['source_type']) {
      case 'task':
        return AppColors.primary;
      case 'skill':
        return AppColors.accent;
      case 'investment':
        return AppColors.gold;
      case 'business':
        return AppColors.success;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = (earning['amount'] as num).toDouble();
    final earnedAt = earning['earned_at'] as String?;
    DateTime? date;
    if (earnedAt != null) {
      try {
        date = DateTime.parse(earnedAt);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.bgSurface),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: _color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  earning['description']?.toString() ??
                      earning['source_type']?.toString() ??
                      'Income',
                  style: AppTextStyles.h4.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null)
                  Text(
                    DateFormat('MMM d, yyyy · h:mm a').format(date),
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          Text(
            '+ $currency ${amount.toStringAsFixed(0)}',
            style: AppTextStyles.h4
                .copyWith(color: AppColors.success, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
