import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/app_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool   _loading  = false;
  bool   _agreed   = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields'); return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters'); return;
    }
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(pass)) {
      setState(() => _error = 'Password must contain letters and numbers'); return;
    }
    if (!_agreed) {
      setState(() => _error = 'Please accept the Terms and Privacy Policy to continue'); return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.signUp(email, pass, name);
      if (!mounted) return;
      // Always go to verify email screen — Supabase requires it
      context.go('/verify-email?email=${Uri.encodeComponent(email)}');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      setState(() {
        _error = msg.contains('already')
            ? 'An account with this email already exists. Try signing in.'
            : msg.contains('password')
                ? 'Password is too weak. Use at least 8 characters with letters and numbers.'
                : 'Registration failed. Please check your details and try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/images/riseup_logo.jpg',
                      width: 44, height: 44, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 24),
                      )),
                ),
                const SizedBox(width: 12),
                Text('RiseUp', style: AppTextStyles.h3),
              ]).animate().fadeIn(),

              const SizedBox(height: 48),
              Text('Start your journey 🚀', style: AppTextStyles.h2).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 8),
              Text('Free forever. Upgrade when you start earning.', style: AppTextStyles.label)
                  .animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 40),

              if (_error != null)
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
                    Expanded(child: Text(_error!,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
                  ]),
                ).animate().shake(),

              AppTextField(
                controller: _nameCtrl,
                label: 'Full name',
                hint: 'Your full name',
                prefixIcon: Icons.person_outline_rounded,
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 16),

              AppTextField(
                controller: _emailCtrl,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ).animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 16),

              AppTextField(
                controller: _passCtrl,
                label: 'Password',
                hint: 'Min 8 chars, include numbers',
                obscureText: true,
                prefixIcon: Icons.lock_outline_rounded,
                onSubmitted: (_) => _register(),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.shield_outlined, size: 13, color: AppColors.success),
                const SizedBox(width: 4),
                Text('Your data is encrypted & private',
                    style: AppTextStyles.caption.copyWith(color: AppColors.success)),
              ]).animate().fadeIn(delay: 430.ms),

              const SizedBox(height: 20),

              // Terms checkbox
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: _agreed ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _agreed ? AppColors.primary : AppColors.textMuted,
                          width: 1.5,
                        ),
                      ),
                      child: _agreed
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(spacing: 4, children: [
                        Text('I agree to the', style: AppTextStyles.bodySmall),
                        GestureDetector(
                          onTap: () => context.go('/terms'),
                          child: Text('Terms of Service',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary, decoration: TextDecoration.underline)),
                        ),
                        Text('and', style: AppTextStyles.bodySmall),
                        GestureDetector(
                          onTap: () => context.go('/privacy'),
                          child: Text('Privacy Policy',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary, decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 28),

              GradientButton(
                text: _loading ? 'Creating account...' : 'Create Free Account',
                onTap: _loading ? null : _register,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(text: TextSpan(
                    text: 'Already have an account? ',
                    style: AppTextStyles.label,
                    children: [TextSpan(
                      text: 'Sign In',
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w600),
                    )],
                  )),
                ),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}
