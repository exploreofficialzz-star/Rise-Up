import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool   _loading  = false;
  String? _error;

  @override
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.signIn(email, pass);
      if (!mounted) return;
      // If email not confirmed, send to verify screen
      if (data['email_confirmed'] == false) {
        context.go('/verify-email?email=${Uri.encodeComponent(email)}');
        return;
      }
      final profile  = await api.getProfile();
      final onboarded = profile['profile']?['onboarding_completed'] ?? false;
      if (!mounted) return;
      context.go(onboarded ? '/home' : '/onboarding');
    } catch (e) {
      setState(() {
        _error   = 'Invalid email or password. Please try again.';
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

              // Logo
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
              ]).animate().fadeIn(duration: 500.ms),

              const SizedBox(height: 48),
              Text('Welcome back 👋', style: AppTextStyles.h2).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2),
              const SizedBox(height: 8),
              Text('Sign in to continue your wealth journey', style: AppTextStyles.label)
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
                ).animate().fadeIn().shake(),

              AppTextField(
                controller: _emailCtrl,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

              const SizedBox(height: 16),

              AppTextField(
                controller: _passCtrl,
                label: 'Password',
                hint: '••••••••',
                obscureText: true,
                prefixIcon: Icons.lock_outline_rounded,
                onSubmitted: (_) => _login(),
              ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),

              const SizedBox(height: 12),

              // Forgot password link
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: Text('Forgot password?',
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 28),

              GradientButton(
                text: _loading ? 'Signing in...' : 'Sign In',
                onTap: _loading ? null : _login,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(text: TextSpan(
                    text: "Don't have an account? ",
                    style: AppTextStyles.label,
                    children: [TextSpan(
                      text: 'Sign Up Free',
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w600),
                    )],
                  )),
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 32),

              // Legal links
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    Text('By continuing you agree to our',
                        style: AppTextStyles.caption),
                    GestureDetector(
                      onTap: () => context.go('/terms'),
                      child: Text('Terms',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary, decoration: TextDecoration.underline)),
                    ),
                    Text('and', style: AppTextStyles.caption),
                    GestureDetector(
                      onTap: () => context.go('/privacy'),
                      child: Text('Privacy Policy',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }
}
