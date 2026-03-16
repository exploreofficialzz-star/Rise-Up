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
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await api.signUp(_emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim());
      // Auto sign in after registration
      await api.signIn(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      context.go('/onboarding');
    } catch (e) {
      setState(() {
        _error = e.toString().contains('already') ? 'Email already registered. Try signing in.' : 'Registration failed. Please try again.';
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
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text('RiseUp', style: AppTextStyles.h3),
                ],
              ).animate().fadeIn(),

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
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
                    ],
                  ),
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
                hint: 'At least 6 characters',
                obscureText: true,
                prefixIcon: Icons.lock_outline_rounded,
                onSubmitted: (_) => _register(),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 8),
              Text(
                '🔒 Your data is secured and private',
                style: AppTextStyles.caption.copyWith(color: AppColors.success),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 32),

              GradientButton(
                text: _loading ? 'Creating account...' : 'Create Free Account',
                onTap: _loading ? null : _register,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account? ',
                      style: AppTextStyles.label,
                      children: [
                        TextSpan(
                          text: 'Sign In',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}
