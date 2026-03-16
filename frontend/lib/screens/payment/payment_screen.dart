import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

class PaymentScreen extends StatefulWidget {
  final String plan;
  const PaymentScreen({super.key, required this.plan});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late String _plan;
  String _currency = 'NGN';
  bool _loading = false;
  Map? _subscriptionStatus;

  static const _currencies = ['NGN', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR'];

  static const _features = [
    ('🗺️', 'AI Wealth Roadmap', 'Personalized 3-stage wealth plan'),
    ('🤖', 'Unlimited AI Chat', 'Ask your mentor anything, anytime'),
    ('📚', 'All Skill Modules', 'Access all premium earn-while-learning courses'),
    ('⚡', 'Task Booster', 'Get 2x more AI-generated income tasks'),
    ('📊', 'Advanced Analytics', 'Deep insights on your progress'),
    ('👥', 'Mentorship Access', 'Connect with wealth mentors'),
    ('💎', 'Investment Tools', 'Learn to invest and grow assets'),
  ];

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await api.getSubscriptionStatus();
      setState(() => _subscriptionStatus = data);
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    try {
      final data = await api.initiatePayment(plan: _plan, currency: _currency);
      final link = data['payment_link'] as String?;
      if (link != null && await canLaunchUrl(Uri.parse(link))) {
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        // Poll for completion
        _pollPaymentStatus(data['tx_ref']);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment failed. Please try again.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
    setState(() => _loading = false);
  }

  void _pollPaymentStatus(String txRef) async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 5));
      try {
        final verify = await api.verifyPayment(txRef: txRef);
        if (verify['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('🎉 Premium activated! Welcome to RiseUp Premium!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ));
            await _loadStatus();
          }
          break;
        }
      } catch (_) {}
    }
  }

  bool get _isPremium => _subscriptionStatus?['is_premium'] == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: Text('Upgrade to Premium', style: AppTextStyles.h3)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_isPremium) ...[
              _ActivePremiumBanner(expiresAt: _subscriptionStatus!['expires_at']).animate().fadeIn(),
            ] else ...[
              // Hero
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2D1B69), Color(0xFF1A3A4F)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: AppRadius.xl,
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 52)),
                    const SizedBox(height: 12),
                    Text('RiseUp Premium', style: AppTextStyles.h2.copyWith(color: AppColors.gold)),
                    const SizedBox(height: 8),
                    Text('Everything you need to build real wealth', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    // Price toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: AppRadius.lg),
                      child: Row(
                        children: [
                          _PlanTab(label: 'Monthly', selected: _plan == 'monthly', onTap: () => setState(() => _plan = 'monthly')),
                          _PlanTab(
                            label: 'Yearly (Save 35%)',
                            selected: _plan == 'yearly',
                            onTap: () => setState(() => _plan = 'yearly'),
                            badge: 'BEST VALUE',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _plan == 'monthly' ? '\$15.99/month' : '\$99.99/year',
                      style: AppTextStyles.money.copyWith(color: AppColors.gold),
                    ),
                  ],
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 24),

              // Currency selector
              Row(
                children: [
                  Text('Currency:', style: AppTextStyles.label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _currency = v ?? 'NGN'),
                      style: AppTextStyles.body,
                      dropdownColor: AppColors.bgCard,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
                        fillColor: AppColors.bgCard, filled: true,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 24),

              // Features
              Text('What you get:', style: AppTextStyles.h4).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 12),

              ..._features.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(e.value.$1, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.value.$2, style: AppTextStyles.h4.copyWith(fontSize: 14)),
                        Text(e.value.$3, style: AppTextStyles.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  ],
                ),
              ).animate().fadeIn(delay: Duration(milliseconds: 200 + e.key * 50))),

              const SizedBox(height: 28),

              GradientButton(
                text: _loading ? 'Redirecting to payment...' : '💳 Subscribe Now',
                onTap: _loading ? null : _subscribe,
                isLoading: _loading,
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 12),
              Text(
                '🔒 Secure payment via Flutterwave. Cancel anytime.',
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 700.ms),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _PlanTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  const _PlanTab({required this.label, required this.selected, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: AppRadius.md,
          ),
          child: Column(
            children: [
              Text(label, style: AppTextStyles.label.copyWith(color: selected ? Colors.white : AppColors.textMuted, fontWeight: selected ? FontWeight.w700 : FontWeight.w400), textAlign: TextAlign.center),
              if (badge != null) Text(badge!, style: AppTextStyles.caption.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivePremiumBanner extends StatelessWidget {
  final String? expiresAt;
  const _ActivePremiumBanner({this.expiresAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D1B69), Color(0xFF1A3A4F)]),
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.gold.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          const Text('👑', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text('You\'re Premium!', style: AppTextStyles.h2.copyWith(color: AppColors.gold)),
          const SizedBox(height: 8),
          Text('All features are unlocked', style: AppTextStyles.body, textAlign: TextAlign.center),
          if (expiresAt != null) ...[
            const SizedBox(height: 8),
            Text('Renews: $expiresAt', style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}
