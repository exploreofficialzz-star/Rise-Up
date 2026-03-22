import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _yearly = true;

  static const _features = [
    (Iconsax.cpu, 'Unlimited AI responses', 'No daily limits, no ads'),
    (Iconsax.message_favorite, 'Private AI coaching', 'Deep 1-on-1 wealth sessions'),
    (Iconsax.star, 'Premium badge', 'Stand out in the community'),
    (Iconsax.chart_2, 'Advanced analytics', 'Track your wealth progress'),
    (Iconsax.flash, 'Priority AI responses', 'Faster, smarter replies'),
    (Iconsax.crown, 'Exclusive content', 'Members-only wealth strategies'),
    (Iconsax.notification, 'Smart notifications', 'AI alerts for opportunities'),
    (Icons.block, 'No ads ever', 'Pure, distraction-free experience'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade50;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    final monthlyPrice = '\$9.99';
    final yearlyPrice = '\$79.99';
    final yearlyMonthly = '\$6.67';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(isDark ? 0.3 : 0.1),
                    AppColors.accent.withOpacity(isDark ? 0.2 : 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Iconsax.crown, color: Colors.white, size: 30),
                  ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                  const SizedBox(height: 12),
                  Text('RiseUp Premium', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                  const SizedBox(height: 6),
                  Text('Unlock your full wealth potential', style: TextStyle(fontSize: 14, color: subColor)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // ── Billing toggle ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _yearly = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_yearly ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(child: Text('Monthly',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600,
                                    color: !_yearly ? Colors.white : subColor))),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _yearly = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _yearly ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('Yearly', style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: _yearly ? Colors.white : subColor)),
                              const SizedBox(width: 6),
                              if (_yearly)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(6)),
                                  child: const Text('Save 33%', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 24),

                  // ── Price ─────────────────────────────────
                  Center(
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('\$', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
                        Text(_yearly ? '79.99' : '9.99',
                            style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: textColor, height: 1.0)),
                      ]),
                      Text(_yearly ? 'per year ($yearlyMonthly/mo)' : 'per month',
                          style: TextStyle(fontSize: 13, color: subColor)),
                    ]),
                  ).animate().fadeIn(delay: 150.ms),

                  const SizedBox(height: 28),

                  // ── Features ──────────────────────────────
                  ..._features.asMap().entries.map((e) {
                    final f = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(f.$1, color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                            Text(f.$3, style: TextStyle(fontSize: 12, color: subColor)),
                          ],
                        )),
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: 200 + e.key * 40));
                  }),

                  const SizedBox(height: 24),

                  // ── CTA button ────────────────────────────
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, spreadRadius: -4),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _yearly ? 'Start Premium — \$79.99/yr' : 'Start Premium — \$9.99/mo',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms),

                  const SizedBox(height: 12),

                  Text('Cancel anytime. No hidden fees.',
                      style: TextStyle(fontSize: 12, color: subColor),
                      textAlign: TextAlign.center),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
