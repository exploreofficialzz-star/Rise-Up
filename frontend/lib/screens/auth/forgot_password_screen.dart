import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/app_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address');
      return;
    }
    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await api.forgotPassword(email);
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (_) {
      // Show success even on error (prevents email enumeration)
      if (mounted) setState(() { _sent = true; _loading = false; });
    }
  }

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _sent ? _SuccessView(email: _emailCtrl.text.trim()) : _FormView(
            emailCtrl: _emailCtrl,
            loading: _loading,
            error: _error,
            onSend: _send,
          ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final TextEditingController emailCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSend;
  const _FormView({required this.emailCtrl, required this.loading, this.error, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 32),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text('Reset Password', style: AppTextStyles.h2).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 8),
        Text(
          'Enter your email and we\'ll send you a link to reset your password.',
          style: AppTextStyles.label,
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 40),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.15),
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
            ]),
          ).animate().shake(),
        AppTextField(
          controller: emailCtrl,
          label: 'Email address',
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.mail_outline_rounded,
          onSubmitted: (_) => onSend(),
        ).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 32),
        GradientButton(
          text: loading ? 'Sending...' : 'Send Reset Link',
          onTap: loading ? null : onSend,
          isLoading: loading,
        ).animate().fadeIn(delay: 400.ms),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => context.go('/login'),
            child: Text('Back to Sign In',
              style: AppTextStyles.label.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ).animate().fadeIn(delay: 500.ms),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String email;
  const _SuccessView({required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_rounded, color: AppColors.success, size: 40),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 32),
        Text('Check Your Email', style: AppTextStyles.h2, textAlign: TextAlign.center)
            .animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 12),
        Text(
          'We\'ve sent a password reset link to\n$email',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 16),
        Text(
          'Check your spam folder if you don\'t see it within a few minutes.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 400.ms),
        const SizedBox(height: 48),
        GradientButton(
          text: 'Back to Sign In',
          onTap: () => context.go('/login'),
        ).animate().fadeIn(delay: 500.ms),
      ],
    );
  }
}
