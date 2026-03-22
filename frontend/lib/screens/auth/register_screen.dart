import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  bool _loading = false;
  bool _agreed  = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(pass)) {
      setState(() => _error = 'Password must contain letters and numbers');
      return;
    }
    if (!_agreed) {
      setState(() => _error = 'Please accept the Terms and Privacy Policy');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await api.signUp(email, pass, name);
      if (!mounted) return;
      context.go('/verify-email?email=${Uri.encodeComponent(email)}');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      setState(() {
        _error = msg.contains('already')
            ? 'An account with this email already exists. Try signing in.'
            : 'Registration failed. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    /// ✅ THEME AWARE
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white60 : Colors.black54;
    final inputFill = isDark ? const Color(0xFF121826) : Colors.grey.shade100;
    final borderColor = isDark ? Colors.white24 : Colors.black12;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              /// ── LOGO ───────────────────────────────
              Row(
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width: 55,
                    height: 55,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.trending_up,
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
                        fontSize: 38, // FIXED to match screenshot
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(),

              const SizedBox(height: 36),

              /// ── HEADER TEXT (EXACT) ─────────────────
              Text(
                'Your journey starts here 🔥',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 4),

              Text(
                'Millions worldwide are building wealth — it\'s your turn',
                style: TextStyle(
                  fontSize: 12,
                  color: subColor,
                ),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 24),

              /// ── ERROR ──────────────────────────────
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
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13))),
                  ]),
                ).animate().shake(),

              /// ── FULL NAME ──────────────────────────
              Text('Full name',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subColor)),
              const SizedBox(height: 6),

              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Your full name',
                  hintStyle: TextStyle(color: subColor),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.person_outline,
                      color: subColor, size: 18),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 14),

              /// ── EMAIL ──────────────────────────────
              Text('Email address',
                  style: TextStyle(color: subColor, fontSize: 13)),
              const SizedBox(height: 6),

              TextField(
                controller: _emailCtrl,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle: TextStyle(color: subColor),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.mail_outline,
                      color: subColor, size: 18),
                ),
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 14),

              /// ── PASSWORD ───────────────────────────
              Text('Password',
                  style: TextStyle(color: subColor, fontSize: 13)),
              const SizedBox(height: 6),

              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Min 8 chars, include numbers',
                  hintStyle: TextStyle(color: subColor),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      Icon(Icons.lock_outline, color: subColor, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: subColor,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 8),

              /// ── GREEN TEXT ─────────────────────────
              Row(
                children: const [
                  Icon(Icons.shield_outlined,
                      size: 14, color: Colors.greenAccent),
                  SizedBox(width: 6),
                  Text(
                    'Your data is encrypted & private',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ).animate().fadeIn(delay: 430.ms),

              const SizedBox(height: 16),

              /// ── CHECKBOX ───────────────────────────
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: _agreed
                          ? const Icon(Icons.check, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 10),

                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: TextStyle(color: subColor),
                          children: const [
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 24),

              /// ── BUTTON ─────────────────────────────
              GradientButton(
                text: _loading
                    ? 'Creating account...'
                    : 'Create Free Account',
                onTap: _loading ? null : _register,
                isLoading: _loading,
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 20),

              /// ── SIGN IN ────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: subColor),
                      children: const [
                        TextSpan(
                          text: 'Sign In',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
