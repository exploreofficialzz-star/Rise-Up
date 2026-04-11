// frontend/lib/screens/auth/splash_screen.dart
//
// Changes vs original:
//  • Navigation logic removed from _navigate() — the GoRouter redirect
//    callback (refreshListenable: authService) now owns all navigation
//    decisions. Splash just shows the branded animation for 1500ms then
//    lets the router redirect fire. If auth status was already set by
//    authService.initialize() in main(), the redirect fires immediately
//    and the user goes straight to /home — no extra delay.
//  • Web: same 1500ms splash, router handles the rest.
//  • Token check still exists as a fallback so the splash works even if
//    authService hasn't finished initialize() (extremely rare).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
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
    _navigate();
  }

  @override
  void dispose() {
    _dotsCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    // Always show the splash for at least 1500ms for brand visibility
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // If authService already knows the status (set in main() before runApp),
    // the GoRouter redirect will have already handled navigation.
    // This manual push is a safety net for the rare case where
    // authService.initialize() is still running.
    if (authService.status == AuthStatus.unknown) {
      // Still loading — read token directly as fast fallback
      final token = await storageService.read(key: 'access_token');
      if (!mounted) return;
      context.go(
          (token != null && token.isNotEmpty) ? '/home' : '/login');
    }
    // If status is known, GoRouter's refreshListenable already navigated.
    // Doing nothing here avoids a double-navigation flicker.
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor    = isDark ? Colors.black : Colors.white;
    final footerColor = isDark ? Colors.white30 : Colors.black26;
    final screenH    = MediaQuery.of(context).size.height;

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
                _Dot(ctrl: _dotsCtrl, delay: 0.0, color: const Color(0xFFFF9AA2)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.2, color: const Color(0xFF81ECEC)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.4, color: const Color(0xFFFFD700)),
                const SizedBox(width: 10),
                _Dot(ctrl: _dotsCtrl, delay: 0.6, color: const Color(0xFF74B9FF)),
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
  const _Dot({required this.ctrl, required this.delay, required this.color});

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
