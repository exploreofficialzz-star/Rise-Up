import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _resending = false;
  bool _resent = false;
  int _countdown = 0;
  Timer? _timer;

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 0) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    setState(() { _resending = true; _resent = false; });
    try {
      await api.resendVerification(widget.email);
      if (mounted) {
        setState(() { _resent = true; _resending = false; });
        _startCountdown();
      }
    } catch (_) {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _checkVerified() async {
    try {
      final profile = await api.getProfile();
      if (mounted) context.go('/onboarding');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Email not verified yet. Please check your inbox.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Envelope animation
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary.withOpacity(0.2), AppColors.accent.withOpacity(0.2)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.email_rounded, color: AppColors.primary, size: 52),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
               .scale(begin: const Offset(1,1), end: const Offset(1.05,1.05), duration: 1500.ms),

              const SizedBox(height: 32),
              Text('Verify Your Email', style: AppTextStyles.h2, textAlign: TextAlign.center)
                  .animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  children: [
                    const TextSpan(text: "We sent a verification link to\n"),
                    TextSpan(
                      text: widget.email,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 12),
              Text(
                'Click the link in your email to activate your account.',
                style: AppTextStyles.label,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 400.ms),

              if (_resent)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: AppRadius.md,
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    const Text('Verification email sent!', style: TextStyle(color: AppColors.success)),
                  ]),
                ).animate().fadeIn().slideY(begin: -0.2),

              const SizedBox(height: 48),

              GradientButton(
                text: "I've Verified My Email",
                onTap: _checkVerified,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 16),

              // Resend button with countdown
              GestureDetector(
                onTap: _countdown > 0 || _resending ? null : _resend,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: AppColors.bgSurface),
                  ),
                  child: Center(
                    child: _resending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : Text(
                            _countdown > 0 ? 'Resend in ${_countdown}s' : 'Resend Verification Email',
                            style: AppTextStyles.label.copyWith(
                              color: _countdown > 0 ? AppColors.textMuted : AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 24),

              GestureDetector(
                onTap: () => context.go('/login'),
                child: Text(
                  'Use a different email?  Sign out',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
              ).animate().fadeIn(delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }
}
