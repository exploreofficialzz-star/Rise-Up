// frontend/lib/screens/referrals/referrals_screen.dart
//
// Production-ready Referrals Screen
// ─────────────────────────────────────────────────────────────────────────────
//  • Stale-while-revalidate cache via SharedPreferences
//    → Instant render from cache, silent background refresh
//  • Full light / dark theme support (follows system / app theme)
//  • Skeleton shimmer on first load (no cache yet)
//  • Pull-to-refresh with optimistic UI
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cache key
// ─────────────────────────────────────────────────────────────────────────────
const _kCacheKey    = 'referrals_cache_v1';
const _kCacheTtlMs  = 5 * 60 * 1000; // 5 minutes before background re-fetch

// ═══════════════════════════════════════════════════════════════════════════════
// ReferralsScreen
// ═══════════════════════════════════════════════════════════════════════════════

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  Map    _data      = {};
  bool   _firstLoad = true;   // true = no cache yet → show shimmer
  bool   _refreshing = false;
  final  _codeCtrl  = TextEditingController();
  bool   _applying  = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Stale-while-revalidate loader ──────────────────────────────────────────

  Future<void> _initLoad() async {
    // 1. Render from cache immediately (sub-millisecond)
    final cached = await _readCache();
    if (cached != null) {
      if (mounted) setState(() { _data = cached; _firstLoad = false; });
    }

    // 2. Decide whether to fetch from network
    final stale = await _isCacheStale();
    if (stale || cached == null) {
      await _fetchFromNetwork(silent: cached != null);
    }
  }

  Future<void> _fetchFromNetwork({bool silent = false}) async {
    if (!silent && mounted) setState(() => _refreshing = true);
    try {
      final data = await api.getMyReferralCode();
      if (!mounted) return;
      setState(() {
        _data      = data;
        _firstLoad = false;
        _refreshing = false;
      });
      await _writeCache(data);
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _onPullRefresh() => _fetchFromNetwork(silent: false);

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<Map?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kCacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['data'] as Map?;
    } catch (_) { return null; }
  }

  Future<bool> _isCacheStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kCacheKey);
      if (raw == null) return true;
      final decoded   = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt   = decoded['saved_at'] as int? ?? 0;
      return DateTime.now().millisecondsSinceEpoch - savedAt > _kCacheTtlMs;
    } catch (_) { return true; }
  }

  Future<void> _writeCache(Map data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode({
        'data':     data,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  // ── Apply referral code ────────────────────────────────────────────────────

  Future<void> _applyCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _applying = true);
    try {
      final result = await api.applyReferralCode(code);
      if (mounted) {
        _showSnack(result['message'] ?? '🎉 Referral applied!',
            AppColors.success);
        _codeCtrl.clear();
        _fetchFromNetwork(silent: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().contains('400')
              ? 'Invalid or already-used referral code'
              : 'Something went wrong. Try again.',
          AppColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('✅ $label copied!', AppColors.success);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? AppColors.bgDark      : Colors.white;
    final cardBg   = isDark ? AppColors.bgCard      : const Color(0xFFF7F7FA);
    final textPri  = isDark ? AppColors.textPrimary : Colors.black87;
    final textSec  = isDark ? AppColors.textSecondary: Colors.black54;
    final border   = isDark ? AppColors.bgSurface   : const Color(0xFFE5E5EA);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Refer & Earn',
            style: AppTextStyles.h3.copyWith(color: textPri)),
        iconTheme: IconThemeData(color: textPri),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
      body: _firstLoad
          ? _ShimmerLayout(isDark: isDark, cardBg: cardBg, border: border)
          : RefreshIndicator(
              onRefresh: _onPullRefresh,
              color: AppColors.primary,
              backgroundColor: cardBg,
              child: _buildContent(
                  isDark: isDark, cardBg: cardBg,
                  textPri: textPri, textSec: textSec, border: border),
            ),
    );
  }

  // ── Main content ───────────────────────────────────────────────────────────

  Widget _buildContent({
    required bool  isDark,
    required Color cardBg,
    required Color textPri,
    required Color textSec,
    required Color border,
  }) {
    final code        = _data['referral_code']?.toString() ?? '--------';
    final link        = _data['referral_link']?.toString() ?? '';
    final msg         = _data['whatsapp_message']?.toString()
                        ?? 'Join me on RiseUp! Use my code $code '
                           'to get 3 days Premium FREE. $link';
    final total       = (_data['total_referrals']   as num?)?.toInt() ?? 0;
    final rewarded    = (_data['rewarded_count']     as num?)?.toInt() ?? 0;
    final premiumDays = (_data['premium_days_earned']as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // ── Hero ────────────────────────────────────────────────────────────
        _HeroCard(isDark: isDark)
            .animate()
            .fadeIn(duration: 350.ms)
            .scale(begin: const Offset(0.96, 0.96), curve: Curves.easeOut),

        const SizedBox(height: 24),

        // ── Code ────────────────────────────────────────────────────────────
        Text('Your Referral Code',
            style: AppTextStyles.h4.copyWith(color: textPri)),
        const SizedBox(height: 10),
        _CodeDisplay(
          code:    code,
          isDark:  isDark,
          cardBg:  cardBg,
          border:  border,
          onCopy:  () => _copyToClipboard(code, 'Code'),
        ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.06),

        const SizedBox(height: 14),

        // ── Share buttons ────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _ShareBtn(
            emoji: '💬', label: 'WhatsApp',
            color: const Color(0xFF25D366),
            isDark: isDark,
            onTap: () {
              api.logShare('referral', 'whatsapp');
              Share.share(msg);
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _ShareBtn(
            emoji: '🔗', label: 'Copy Link',
            color: AppColors.accent,
            isDark: isDark,
            onTap: () => _copyToClipboard(link.isNotEmpty ? link : code, 'Link'),
          )),
          const SizedBox(width: 10),
          Expanded(child: _ShareBtn(
            emoji: '📲', label: 'Share',
            color: AppColors.primary,
            isDark: isDark,
            onTap: () {
              api.logShare('referral', 'other');
              Share.share(msg, subject: 'Join me on RiseUp!');
            },
          )),
        ]).animate().fadeIn(delay: 130.ms),

        const SizedBox(height: 20),

        // ── Stats ────────────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _StatBadge(
            value: '$total', label: 'Total\nInvited',
            color: AppColors.primary, isDark: isDark,
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatBadge(
            value: '$rewarded', label: 'Joined &\nActive',
            color: AppColors.success, isDark: isDark,
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatBadge(
            value: '${premiumDays}d', label: 'Premium\nEarned',
            color: AppColors.gold, isDark: isDark,
          )),
        ]).animate().fadeIn(delay: 180.ms),

        const SizedBox(height: 24),

        // ── Apply code ───────────────────────────────────────────────────────
        _ApplyCodeCard(
          ctrl:     _codeCtrl,
          applying: _applying,
          isDark:   isDark,
          cardBg:   cardBg,
          border:   border,
          textPri:  textPri,
          textSec:  textSec,
          onApply:  _applyCode,
        ).animate().fadeIn(delay: 220.ms),

        const SizedBox(height: 20),

        // ── How it works ─────────────────────────────────────────────────────
        _HowItWorksCard(
          isDark:  isDark,
          cardBg:  cardBg,
          border:  border,
          textPri: textPri,
          textSec: textSec,
        ).animate().fadeIn(delay: 270.ms),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _HeroCard
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final bool isDark;
  const _HeroCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D1B69), Color(0xFF6C5CE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.xl,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(isDark ? 0.4 : 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        const Text('🤝', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 14),
        const Text(
          'Invite Friends. Get Premium FREE.',
          style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800,
            color: Colors.white, height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Share your code and you BOTH get 7 days of RiseUp\nPremium — completely free.',
          style: TextStyle(
            fontSize: 13, color: Colors.white.withOpacity(0.82),
            height: 1.55,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        // Reward badges row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RewardBadge(emoji: '🎁', text: 'You get 7 days'),
            const SizedBox(width: 10),
            Container(width: 1, height: 28, color: Colors.white24),
            const SizedBox(width: 10),
            _RewardBadge(emoji: '⭐', text: 'Friend gets 3 days'),
          ],
        ),
      ]),
    );
  }
}

class _RewardBadge extends StatelessWidget {
  final String emoji, text;
  const _RewardBadge({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 6),
      Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _CodeDisplay
// ═══════════════════════════════════════════════════════════════════════════════

class _CodeDisplay extends StatelessWidget {
  final String   code;
  final bool     isDark;
  final Color    cardBg, border;
  final VoidCallback onCopy;

  const _CodeDisplay({
    required this.code,
    required this.isDark,
    required this.cardBg,
    required this.border,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: AppRadius.xl,
          border: Border.all(
              color: AppColors.primary.withOpacity(0.45), width: 2),
          boxShadow: isDark
              ? []
              : [BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12, offset: const Offset(0, 3),
                )],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              code,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: AppRadius.sm,
              ),
              child: const Icon(Iconsax.copy, color: AppColors.primary, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _ShareBtn
// ═══════════════════════════════════════════════════════════════════════════════

class _ShareBtn extends StatelessWidget {
  final String       emoji, label;
  final Color        color;
  final bool         isDark;
  final VoidCallback onTap;

  const _ShareBtn({
    required this.emoji,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.12 : 0.08),
          borderRadius: AppRadius.lg,
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              )),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _StatBadge
// ═══════════════════════════════════════════════════════════════════════════════

class _StatBadge extends StatelessWidget {
  final String value, label;
  final Color  color;
  final bool   isDark;

  const _StatBadge({
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.1 : 0.07),
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
            )),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textMuted : Colors.black45,
              height: 1.4,
            ),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _ApplyCodeCard
// ═══════════════════════════════════════════════════════════════════════════════

class _ApplyCodeCard extends StatelessWidget {
  final TextEditingController ctrl;
  final bool     applying, isDark;
  final Color    cardBg, border, textPri, textSec;
  final VoidCallback onApply;

  const _ApplyCodeCard({
    required this.ctrl,
    required this.applying,
    required this.isDark,
    required this.cardBg,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: AppRadius.xl,
        border: Border.all(color: border),
        boxShadow: isDark
            ? []
            : [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10, offset: const Offset(0, 2),
              )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('👋', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Have a friend\'s code?',
                style: AppTextStyles.h4.copyWith(color: textPri)),
            Text('Enter it to get 3 days of Premium FREE',
                style: AppTextStyles.bodySmall.copyWith(color: textSec)),
          ])),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: TextStyle(
                letterSpacing: 4,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: textPri,
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              onSubmitted: (_) => onApply(),
              decoration: InputDecoration(
                hintText: 'XXXXXXXX',
                hintStyle: TextStyle(
                    letterSpacing: 3,
                    color: isDark ? AppColors.textMuted : Colors.black26),
                counterText: '',
                filled: true,
                fillColor: isDark ? AppColors.bgSurface : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: applying ? null : onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
              ),
              child: applying
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Apply',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _HowItWorksCard
// ═══════════════════════════════════════════════════════════════════════════════

class _HowItWorksCard extends StatelessWidget {
  final bool  isDark;
  final Color cardBg, border, textPri, textSec;

  const _HowItWorksCard({
    required this.isDark,
    required this.cardBg,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  static const _steps = [
    ('1️⃣', 'Share your unique code with a friend'),
    ('2️⃣', 'They sign up on RiseUp and enter your code'),
    ('3️⃣', 'They instantly get 3 days Premium FREE'),
    ('4️⃣', 'You earn 7 days Premium FREE — no limit!'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: AppRadius.xl,
        border: Border.all(color: border),
        boxShadow: isDark
            ? []
            : [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10, offset: const Offset(0, 2),
              )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How it works',
            style: AppTextStyles.h4.copyWith(color: textPri)),
        const SizedBox(height: 16),
        ..._steps.map((s) {
          final isLast = s == _steps.last;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [
                Text(s.$1, style: const TextStyle(fontSize: 22)),
                if (!isLast) Container(
                  width: 2, height: 18,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.bgSurface
                        : Colors.black.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(s.$2,
                      style: AppTextStyles.body.copyWith(
                          color: textSec, height: 1.55)),
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 16),
        // Unlimited reward callout
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(isDark ? 0.1 : 0.07),
            borderRadius: AppRadius.md,
            border: Border.all(
                color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No limit! Refer 10 friends → earn 70 days Premium FREE.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _ShimmerLayout  —  skeleton shown only on first load (no cache)
// ═══════════════════════════════════════════════════════════════════════════════

class _ShimmerLayout extends StatelessWidget {
  final bool  isDark;
  final Color cardBg, border;

  const _ShimmerLayout({
    required this.isDark,
    required this.cardBg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // Hero skeleton
        _Shimmer(
          isDark: isDark,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: AppRadius.xl,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Label
        _Shimmer(isDark: isDark,
            child: _SkeletonBox(w: 140, h: 16, cardBg: cardBg)),
        const SizedBox(height: 10),

        // Code box
        _Shimmer(
          isDark: isDark,
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: AppRadius.xl,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Share buttons
        Row(children: [
          for (int i = 0; i < 3; i++) ...[
            Expanded(child: _Shimmer(
              isDark: isDark,
              child: Container(height: 70,
                decoration: BoxDecoration(
                    color: cardBg, borderRadius: AppRadius.lg)),
            )),
            if (i < 2) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 20),

        // Stat badges
        Row(children: [
          for (int i = 0; i < 3; i++) ...[
            Expanded(child: _Shimmer(
              isDark: isDark,
              child: Container(height: 80,
                decoration: BoxDecoration(
                    color: cardBg, borderRadius: AppRadius.lg)),
            )),
            if (i < 2) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 24),

        // Apply code card
        _Shimmer(
          isDark: isDark,
          child: Container(height: 120,
              decoration: BoxDecoration(
                  color: cardBg, borderRadius: AppRadius.xl)),
        ),
        const SizedBox(height: 20),

        // How it works card
        _Shimmer(
          isDark: isDark,
          child: Container(height: 240,
              decoration: BoxDecoration(
                  color: cardBg, borderRadius: AppRadius.xl)),
        ),
      ],
    );
  }
}

// ─── Shimmer wrapper ─────────────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final bool   isDark;
  final Widget child;
  const _Shimmer({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return child
        .animate(onPlay: (ctrl) => ctrl.repeat())
        .shimmer(
          duration:  900.ms,
          delay:     200.ms,
          color:     isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double w, h;
  final Color  cardBg;
  const _SkeletonBox(
      {required this.w, required this.h, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
