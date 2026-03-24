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
  bool _loading    = false;
  bool _obscure    = true;
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
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final bgColor    = isDark ? Colors.black : Colors.white;
    final textColor  = isDark ? Colors.white : Colors.black87;
    final subColor   = isDark ? Colors.white60 : Colors.black54;
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final inputFill  = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final inputText  = isDark ? Colors.white : Colors.black87;
    final iconColor  = isDark ? Colors.white38 : Colors.black38;

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

              // ── Logo + RiseUp — 60x60, 55px, 2px gap ──
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width: 60,
                    height: 60,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xFFFF6B00),
                      size: 60,
                    ),
                  ),
                  const SizedBox(width: 2), // ← 2px gap
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
                    child: Text(
                      'RiseUp',
                      style: TextStyle(
                        fontSize: 55,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.5,
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 1,
                            offset: const Offset(0.5, 0.5),
                          ),
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 3,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 44),

              // ── Welcome back ──────────────────────────
              Text(
                'Welcome back 👋',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 6),

              Text(
                'Sign in to continue your wealth journey',
                style: TextStyle(
                    fontSize: 13, color: subColor, height: 1.4),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 32),

              // ── Error ─────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13))),
                  ]),
                ).animate().fadeIn().shake(),

              // ── Email address ─────────────────────────
              Text('Email address',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: labelColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: 14, color: inputText),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle:
                      TextStyle(color: iconColor, fontSize: 14),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  prefixIcon: Icon(Icons.mail_outline_rounded,
                      color: iconColor, size: 20),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 20),

              // ── Password ──────────────────────────────
              Text('Password',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: labelColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: TextStyle(fontSize: 14, color: inputText),
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle:
                      TextStyle(color: iconColor, fontSize: 14),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: iconColor, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: iconColor,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 12),

              // ── Forgot password ───────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 28),

              // ── Sign In button ────────────────────────
              GradientButton(
                text: _loading ? 'Signing in...' : 'Sign In',
                onTap: _loading ? null : _login,
                isLoading: _loading,
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 24),

              // ── Sign Up Free ──────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style:
                          TextStyle(color: subColor, fontSize: 14),
                      children: const [
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
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 32),

              // ── Legal ─────────────────────────────────
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
                      child: const Text('Terms',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                    Text('and',
                        style:
                            TextStyle(color: subColor, fontSize: 11)),
                    GestureDetector(
                      onTap: () => context.go('/privacy'),
                      child: const Text('Privacy Policy',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
