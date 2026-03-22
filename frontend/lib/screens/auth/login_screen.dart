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
          value: onboarded.toString(),
        );
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

    /// ✅ THEME-AWARE COLORS (THIS IS THE MAIN FIX)
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor   = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor  = isDark ? Colors.white60 : Colors.black54;
    final inputFill = isDark ? const Color(0xFF121212) : Colors.grey.shade100;
    final borderColor = isDark ? Colors.white24 : Colors.black12;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Logo + RiseUp ─────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width: 55,
                    height: 55,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.trending_up_rounded,
                      color: textColor,
                      size: 55,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFFFF6B00),
                        Color(0xFFFFD700),
                        Color(0xFF6C5CE7),
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'RiseUp',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 500.ms),

              const SizedBox(height: 40),

              // ── Welcome ───────────────────────────────
              Text(
                'Welcome back 👋',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 4),

              Text(
                'Sign in to continue your wealth journey',
                style: TextStyle(fontSize: 13, color: subColor),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 24),

              // ── Error ─────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: AppRadius.md,
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ]),
                ).animate().fadeIn().shake(),

              // ── Email ────────────────────────────────
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
                    borderSide: BorderSide(color: borderColor, width: 1.2),
                  ),
                  prefixIcon: Icon(Icons.mail_outline_rounded,
                      color: subColor, size: 18),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 14),

              // ── Password ─────────────────────────────
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
                    borderSide: BorderSide(color: borderColor, width: 1.2),
                  ),
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

              // ── Forgot password ──────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.go('/forgot-password'),
                  child: const Text('Forgot password?',
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 24),

              // ── Button ───────────────────────────────
              GradientButton(
                text: _loading ? 'Signing in...' : 'Sign In',
                onTap: _loading ? null : _login,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 20),

              // ── Sign up ──────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: subColor, fontSize: 14),
                      children: const [
                        TextSpan(
                          text: 'Sign Up Free',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 24),

              // ── Legal ────────────────────────────────
              Center(
                child: Text(
                  'By continuing you agree to our Terms and Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subColor, fontSize: 11),
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
