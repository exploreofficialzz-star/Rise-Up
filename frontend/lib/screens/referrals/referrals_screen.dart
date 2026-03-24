import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});
  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  Map _data = {};
  bool _loading = true;
  final _codeCtrl = TextEditingController();
  bool _applying = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final data = await api.getMyReferralCode();
      setState(() { _data = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _applyCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _applying = true);
    try {
      final result = await api.applyReferralCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message'] ?? '🎉 Referral applied!'),
          backgroundColor: AppColors.success,
        ));
        _codeCtrl.clear();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('400')
              ? 'Invalid or already-used referral code'
              : 'Something went wrong. Try again.'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code    = _data['referral_code']?.toString() ?? '--------';
    final link    = _data['referral_link']?.toString() ?? '';
    final msg     = _data['whatsapp_message']?.toString() ?? '';
    final total   = (_data['total_referrals'] ?? 0) as int;
    final rewarded = (_data['rewarded_count'] ?? 0) as int;
    final premiumDays = (_data['premium_days_earned'] ?? 0) as int;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Refer & Earn', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Hero ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2D1B69), Color(0xFF6C5CE7)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: AppRadius.xl,
                      boxShadow: AppShadows.glow,
                    ),
                    child: Column(children: [
                      const Text('🤝', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('Invite Friends. Get Premium FREE.',
                          style: AppTextStyles.h3, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        'Share your code and you BOTH get 7 days of RiseUp Premium — completely free.',
                        style: AppTextStyles.body.copyWith(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95,0.95)),

                  const SizedBox(height: 24),

                  // ── Code display ──────────────────────────
                  Text('Your Referral Code', style: AppTextStyles.h4),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Code copied!'), backgroundColor: AppColors.success),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: AppRadius.xl,
                        border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w900,
                              color: AppColors.primary, letterSpacing: 6,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Iconsax.copy, color: AppColors.primary, size: 22),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Share buttons ─────────────────────────
                  Row(children: [
                    Expanded(child: _ShareBtn(
                      icon: '💬',
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () {
                        final uri = Uri.parse(
                          'https://wa.me/?text=${Uri.encodeComponent(msg)}',
                        );
                        api.logShare('referral', 'whatsapp');
                        Share.share(msg);
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ShareBtn(
                      icon: '🔗',
                      label: 'Copy Link',
                      color: AppColors.accent,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Link copied!'), backgroundColor: AppColors.success),
                        );
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ShareBtn(
                      icon: '📲',
                      label: 'Share',
                      color: AppColors.primary,
                      onTap: () {
                        api.logShare('referral', 'other');
                        Share.share(msg, subject: 'Join me on RiseUp!');
                      },
                    )),
                  ]),

                  const SizedBox(height: 24),

                  // ── Stats ─────────────────────────────────
                  Row(children: [
                    Expanded(child: _StatBadge(value: '$total', label: 'Total Invited')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatBadge(value: '$rewarded', label: 'Joined & Active')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatBadge(
                      value: '${premiumDays}d', label: 'Premium Earned',
                      color: AppColors.gold,
                    )),
                  ]),

                  const SizedBox(height: 28),

                  // ── Apply a code ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard, borderRadius: AppRadius.xl,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Have a friend\'s code?', style: AppTextStyles.h4),
                      const SizedBox(height: 4),
                      Text('Enter it to get 3 days of Premium FREE',
                          style: AppTextStyles.bodySmall),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtrl,
                            style: AppTextStyles.body.copyWith(letterSpacing: 3, fontWeight: FontWeight.w700),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 8,
                            decoration: const InputDecoration(
                              hintText: 'XXXXXXXX',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _applying ? null : _applyCode,
                          child: _applying
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Apply'),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  // ── How it works ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard, borderRadius: AppRadius.xl,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('How it works', style: AppTextStyles.h4),
                      const SizedBox(height: 16),
                      ...[
                        ('1️⃣', 'Share your code with a friend'),
                        ('2️⃣', 'They sign up and enter your code'),
                        ('3️⃣', 'They get 3 days Premium FREE'),
                        ('4️⃣', 'You get 7 days Premium FREE'),
                      ].map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          Text(s.$1, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.$2, style: AppTextStyles.body)),
                        ]),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _ShareBtn extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _ShareBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppRadius.lg,
          border: Border.all(color: color.withOpacity(0.4))),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _StatBadge extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatBadge({required this.value, required this.label, this.color = AppColors.primary});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.3))),
    child: Column(children: [
      Text(value, style: AppTextStyles.h3.copyWith(color: color)),
      const SizedBox(height: 4),
      Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
    ]),
  );
}
