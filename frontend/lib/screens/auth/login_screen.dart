import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../utils/storage_service.dart';
import '../../widgets/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool   _loading  = false;
  bool   _obscure  = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

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

      if (data['email_confirmed'] == false) {
        context.go('/verify-email?email=${Uri.encodeComponent(email)}');
        return;
      }

      try {
        final profile = await api.getProfile();
        final onboarded = profile['profile']?['onboarding_completed'] ?? false;
        await storageService.write(
            key: 'onboarding_completed',
            value: onboarded.toString());
      } catch (_) {}

      if (!mounted) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;
    final inputFill = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Logo + RiseUp — top left ───────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width: 65,
                    height: 65,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xFFFF6B00),
                      size: 65,
                    ),
                  ),
                  const SizedBox(width: 7),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
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
                        fontSize: 55,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 500.ms),

              const SizedBox(height: 40),

              // ── Welcome header ─────────────────────────
              Text(
                'Welcome back 👋',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 4),

              Text(
                'Sign in to continue your wealth journey',
                style: TextStyle(fontSize: 12, color: subColor),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 24),

              // ── Error ──────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: AppRadius.md,
                    border: Border.all(
                        color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: TextStyle(
                            color: AppColors.error, fontSize: 13))),
                  ]),
                ).animate().fadeIn().shake(),

              // ── Email ──────────────────────────────────
              Text('Email address',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subColor)),
              const SizedBox(height: 6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle: TextStyle(color: subColor, fontSize: 14),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.mail_outline_rounded,
                      color: subColor, size: 18),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 14),

              // ── Password ───────────────────────────────
              Text('Password',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subColor)),
              const SizedBox(height: 6),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: TextStyle(fontSize: 14, color: textColor),
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: TextStyle(color: subColor, fontSize: 14),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: subColor, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: subColor,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 10),

              // ── Forgot password ────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: Text('Forgot password?',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 24),

              // ── Sign In button ─────────────────────────
              GradientButton(
                text: _loading ? 'Signing in...' : 'Sign In',
                onTap: _loading ? null : _login,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 20),

              // ── Sign up link ───────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: subColor, fontSize: 14),
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

              const SizedBox(height: 24),

              // ── Legal ──────────────────────────────────
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    Text('By continuing you agree to our',
                        style: TextStyle(
                            color: subColor, fontSize: 11)),
                    GestureDetector(
                      onTap: () => context.go('/terms'),
                      child: Text('Terms',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              decoration: TextDecoration.underline)),
                    ),
                    Text('and',
                        style:
                            TextStyle(color: subColor, fontSize: 11)),
                    GestureDetector(
                      onTap: () => context.go('/privacy'),
                      child: Text('Privacy Policy',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              decoration: TextDecoration.underline)),
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
