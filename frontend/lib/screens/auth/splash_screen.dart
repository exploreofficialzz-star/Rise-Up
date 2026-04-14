// frontend/lib/screens/auth/splash_screen.dart
// v3.0 — Adaptive splash timing (Facebook/Instagram model)
//
// Timing strategy:
//  • Returning authenticated user → 1 500 ms  (fast path to content)
//  • Unknown status (resolving)   → waits for auth + minimum 1 500 ms
//  • New / unauthenticated user   → 2 000 ms  (shows brand before login)
//
// Auth resolution runs in parallel with the timer so there is zero idle
// wait — the user always navigates the instant both complete.

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
  late Animation<double>   _fadeIn;

  @override
  void initState() {
    super.initState();

    _dotsCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fadeIn = CurvedAnimation(
      parent: AnimationController(
        vsync:    this,
        duration: const Duration(milliseconds: 600),
      )..forward(),
      curve: Curves.easeOut,
    );

    _navigate();
  }

  @override
  void dispose() {
    _dotsCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    // Determine the minimum display time based on current auth state.
    // Returning users see a short splash; new users see a full brand moment.
    final minDisplay = _minDisplayDuration();

    // Run timer and auth resolution in parallel — navigate when both done.
    final results = await Future.wait([
      Future.delayed(minDisplay),
      _resolveDestination(),
    ]);

    if (!mounted) return;
    context.go(results[1] as String);
  }

  /// Minimum time the splash is shown.
  Duration _minDisplayDuration() {
    switch (authService.status) {
      case AuthStatus.authenticated:
        // User is already verified — brief splash before jumping to feed
        return const Duration(milliseconds: 1500);
      case AuthStatus.unauthenticated:
        // New or logged-out user — show brand moment before login screen
        return const Duration(milliseconds: 2000);
      case AuthStatus.unknown:
        // Auth is still resolving — wait long enough for it to finish
        return const Duration(milliseconds: 1500);
    }
  }

  /// Determines the target route. initialize() in main() will have already
  /// resolved the status in most cases; the polls below are a safety net
  /// for any startup race conditions on slower devices.
  Future<String> _resolveDestination() async {
    // Fast path — already resolved before splash rendered
    if (authService.status == AuthStatus.authenticated) return '/home';
    if (authService.status == AuthStatus.unauthenticated) return '/login';

    // Status still unknown — poll with short intervals (max ~3 s total)
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (authService.status == AuthStatus.authenticated) return '/home';
      if (authService.status == AuthStatus.unauthenticated) return '/login';
    }

    // Timeout fallback — check raw token presence
    final access  = await storageService.read(key: 'access_token');
    final refresh = await storageService.read(key: 'refresh_token');

    // Prefer keeping the user in if any token exists (offline-first)
    if (refresh != null || access != null) return '/home';
    return '/login';
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.white;
    final footerColor = isDark ? Colors.white30 : Colors.black26;
    final screenH     = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: bgColor,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          children: [
            // ── Logo + wordmark ─────────────────────────────────────────
            Positioned(
              top:   screenH * 0.28,
              left:  0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/riseup_logo.png',
                    width:  130,
                    height: 130,
                    fit:    BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xFFFF6B00),
                      size:  100,
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -12),
                    child: ShaderMask(
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
                          fontSize:      48,
                          fontWeight:    FontWeight.w900,
                          color:         Colors.white,
                          letterSpacing: -1,
                          height:        1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Animated loading dots ───────────────────────────────────
            Positioned(
              bottom: 100,
              left:   0,
              right:  0,
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

            // ── Footer ──────────────────────────────────────────────────
            Positioned(
              bottom: 40,
              left:   0,
              right:  0,
              child: Text(
                'By chAs',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:         footerColor,
                  fontSize:      13,
                  fontWeight:    FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bouncing dot ───────────────────────────────────────────────────────────
class _Dot extends StatelessWidget {
  final AnimationController ctrl;
  final double delay;
  final Color  color;
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
            width:  10,
            height: 10,
            decoration: BoxDecoration(
              color:  color,
              shape:  BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:        color.withOpacity(0.5),
                  blurRadius:   6,
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
