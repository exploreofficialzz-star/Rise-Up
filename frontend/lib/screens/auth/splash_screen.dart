// frontend/lib/screens/auth/splash_screen.dart
// v4.0 — Token-First Routing
//
// CHANGE vs v3:
//  The old _resolveDestination() polled authService.status, which could briefly
//  be 'unauthenticated' right after an update while Supabase was validating the
//  restored session. If the poll caught that brief dip, the user was sent to
//  /login. GoRouter then also saw 'unauthenticated' and confirmed the redirect.
//
//  Fix — token-first approach:
//    If tokens exist in storage → go to /home, unconditionally.
//    The auth service validates in background. If truly invalid, GoRouter
//    redirects to /login AFTER the user is at /home (rare, graceful).
//    Only send to /login when storage is confirmed empty AND status is
//    unauthenticated (or timed out after 3 s).
//
//  This mirrors how Facebook/Instagram/YouTube work: the stored credential
//  IS the login — no server round-trip is needed before showing the feed.
//
// Timing strategy (unchanged):
//  • Returning user (tokens found)  → 800 ms  (very fast: straight to feed)
//  • New / logged-out user          → 2 000 ms (brand moment before /login)

import 'dart:async';
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
  late final AnimationController _dotsCtrl;
  late final Animation<double>   _fadeIn;

  String? _cachedFirstName;   // populated from profile cache for returning users
  bool    _hasTokens = false;

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

    _loadCachedName();
    _navigate();
  }

  @override
  void dispose() {
    _dotsCtrl.dispose();
    super.dispose();
  }

  /// Reads the profile cache so we can show "Welcome back, [name]" instantly.
  Future<void> _loadCachedName() async {
    final refresh = await storageService.read(key: 'refresh_token');
    final access  = await storageService.read(key: 'access_token');
    if (refresh == null && access == null) return; // new user — no greeting

    final profile = await storageService.getCachedProfile();
    if (profile == null) return;

    final name = (profile['full_name'] as String? ?? profile['username'] as String? ?? '').trim();
    final first = name.split(' ').first.trim();
    if (first.isNotEmpty && mounted) {
      setState(() {
        _cachedFirstName = first;
        _hasTokens = true;
      });
    }
  }

  Future<void> _navigate() async {
    // Check tokens and decide route in parallel with minimum display timer.
    final results = await Future.wait([
      _resolveDestination(),
      _minTimer(),
    ]);

    if (!mounted) return;
    context.go(results[0] as String);
  }

  // ── Token-first routing ────────────────────────────────────────────────────
  //
  // Priority order:
  //  1. Tokens in storage → /home  (offline-first, like Facebook)
  //  2. authService says authenticated → /home
  //  3. authService says unauthenticated + no tokens → /login
  //  4. Timeout (3 s) + no tokens → /login
  //
  // Why tokens take priority over authService.status:
  //   After a new deploy, Supabase can fire signedOut within the first
  //   few seconds while validating the session. If the backend is cold-
  //   starting, the refresh request times out and status briefly shows
  //   as unauthenticated — even though the user IS authenticated and has
  //   valid tokens in storage. Routing based on tokens avoids this race.
  Future<String> _resolveDestination() async {
    // Step 1: Read tokens from storage — this is the ground truth.
    // Uses the dual-storage (secure + SharedPreferences backup on web)
    // so tokens are found even during a service worker swap.
    final refresh = await storageService.read(key: 'refresh_token');
    final access  = await storageService.read(key: 'access_token');
    final hasTokens = refresh != null || access != null;

    if (hasTokens) {
      // Tokens exist → the user is authenticated.
      // Wait briefly for authService to confirm (fast path), but
      // never send them to /login even if the status is briefly wrong.
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (authService.status == AuthStatus.authenticated) return '/home';
        // Even if status says unauthenticated here, tokens exist — go home.
        // The auth service's startup grace period + background refresh
        // will validate the session without the user ever seeing /login.
        if (authService.status == AuthStatus.unauthenticated) return '/home';
      }
      // Status stayed 'unknown' for 1 s but tokens exist — still go home.
      return '/home';
    }

    // Step 2: No tokens in storage.
    // Fast path if auth service has already resolved.
    if (authService.status == AuthStatus.authenticated)   return '/home';
    if (authService.status == AuthStatus.unauthenticated) return '/login';

    // Step 3: No tokens + status still unknown → poll up to 3 s.
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (authService.status == AuthStatus.authenticated)   return '/home';
      if (authService.status == AuthStatus.unauthenticated) return '/login';
    }

    // Step 4: 3-second timeout, no tokens, status never resolved → new user.
    return '/login';
  }

  // Minimum display duration so the splash doesn't flash by too quickly.
  Future<void> _minTimer() async {
    // Returning users (tokens found) feel fastest; new users see the brand.
    final hasTokens =
        await storageService.read(key: 'refresh_token') != null ||
        await storageService.read(key: 'access_token')  != null;

    await Future.delayed(
      hasTokens
          ? const Duration(milliseconds: 800)   // fast path to feed
          : const Duration(milliseconds: 2000),  // brand moment for new user
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
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
            // ── Logo + wordmark ──────────────────────────────────────────
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

                  // ── Personalised welcome-back for returning users ──────
                  if (_cachedFirstName != null) ...[
                    const SizedBox(height: 14),
                    AnimatedOpacity(
                      opacity: _cachedFirstName != null ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        'Welcome back, $_cachedFirstName 👋',
                        style: TextStyle(
                          color:      isDark ? Colors.white54 : Colors.black45,
                          fontSize:   15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Animated loading dots ────────────────────────────────────
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

            // ── Footer ───────────────────────────────────────────────────
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

// ── Bouncing dot (unchanged) ──────────────────────────────────────────────────
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
