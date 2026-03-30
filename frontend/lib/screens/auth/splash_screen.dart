// frontend/lib/screens/auth/splash_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotsCtrl;

  @override
  void initState() {
    super.initState();
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // FIX: Token check and minimum display time run in parallel.
    // Previously: await 2800ms THEN check token → total ≥ 2800ms.
    // Now: both run at the same time → total = max(1500ms, token_check_time).
    // Since flutter_secure_storage reads locally, token check is typically <100ms,
    // making the effective splash exactly 1500ms instead of 2800ms.
    _navigate();
  }

  @override
  void dispose() {
    _dotsCtrl.dispose();
    super.dispose();
  }

  Future<String?> _readToken() async {
    try {
      return await storageService.read(key: 'access_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> _navigate() async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) context.go('/login');
      return;
    }

    // Run minimum display time and token check concurrently.
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 1500)), // min splash display
      _readToken(),                                        // local storage read
    ]);

    if (!mounted) return;

    final token = results[1] as String?;
    context.go(token != null && token.isNotEmpty ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final footerColor = isDark ? Colors.white30 : Colors.black26;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Logo + RiseUp ──────────────────────────────
          Positioned(
            top: screenH * 0.28,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/riseup_logo.png',
                  width: 130,
                  height: 130,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.trending_up_rounded,
                    color: Color(0xFFFF6B00),
                    size: 100,
                  ),
                ),
                const SizedBox(height: 4),
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
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Animated dots ──────────────────────────────
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Dot(ctrl: _dotsCtrl, delay: 0.0,
                    color: const Color(0xFFFF9AA2)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.2,
                    color: const Color(0xFF81ECEC)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.4,
                    color: const Color(0xFFFFD700)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.6,
                    color: const Color(0xFF74B9FF)),
              ],
            ),
          ),

          // ── By chAs ────────────────────────────────────
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'By chAs',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: footerColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final AnimationController ctrl;
  final double delay;
  final Color color;
  const _Dot(
      {required this.ctrl, required this.delay, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final phase = ((ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
        final scale = phase < 0.5
            ? 0.7 + 0.6 * (phase * 2)
            : 1.3 - 0.6 * ((phase - 0.5) * 2);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
