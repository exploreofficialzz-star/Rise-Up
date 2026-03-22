import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../utils/storage_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.signIn(email, pass);
      if (!mounted) return;

      if (data['email_confirmed'] == false) {
        context.go(
            '/verify-email?email=${Uri.encodeComponent(email)}');
        return;
      }

      // Save auth state and go directly to home
      try {
        final profile = await api.getProfile();
        final onboarded =
            profile['profile']?['onboarding_completed'] ?? false;
        await storageService.write(
            key: 'onboarding_completed',
            value: onboarded.toString());
      } catch (_) {}

      if (!mounted) return;
      // ← Always go to home — social feed is the main screen
      context.go('/home');
    } catch (e) {
      setState(() {
        _error = 'Invalid email or password. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor =
        isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Logo + RiseUp ─────────────────────────
              Row(
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xFFFF6B00),
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        const LinearGradient(
                      colors: [
                        Color(0xFFFF6B00),
                        Color(0xFFFFD700),
                        Color(0xFF6C5CE7),
                      ],
                      stops: [0.0, 0.4, 1.0],
                    ).createShader(bounds),
                    child: const Text(
                      'RiseUp',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 500.ms),

              const SizedBox(height: 48),

              Text(
                'Welcome back 👋',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2),

              const SizedBox(height: 6),

              Text(
                'Sign in to continue your wealth journey',
                style: TextStyle(
                    fontSize: 14, color: subColor),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 36),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: AppRadius.md,
                    border: Border.all(
                        color:
                            AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: AppColors.error,
                                fontSize: 13))),
                  ]),
                ).animate().fadeIn().shake(),

              AppTextField(
                controller: _emailCtrl,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 16),

              AppTextField(
                controller: _passCtrl,
                label: 'Password',
                hint: '••••••••',
                obscureText: true,
                prefixIcon: Icons.lock_outline_rounded,
                onSubmitted: (_) => _login(),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
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
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(
                          color: subColor, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Sign Up Free',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 32),

              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    Text('By continuing you agree to our',
                        style: TextStyle(
                            color: subColor, fontSize: 12)),
                    GestureDetector(
                      onTap: () => context.go('/terms'),
                      child: Text('Terms',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                    Text('and',
                        style: TextStyle(
                            color: subColor, fontSize: 12)),
                    GestureDetector(
                      onTap: () => context.go('/privacy'),
                      child: Text('Privacy Policy',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 700.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
