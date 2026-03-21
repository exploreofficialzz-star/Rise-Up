import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../utils/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    // Web — go straight to login
    if (kIsWeb) {
      context.go('/login');
      return;
    }

    // Mobile — check token from secure storage
    try {
      final token = await storageService.read(key: 'access_token');
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        try {
          final prefs =
              await storageService.read(key: 'onboarding_completed');
          if (!mounted) return;
          context.go(prefs == 'true' ? '/home' : '/onboarding');
        } catch (_) {
          if (mounted) context.go('/home');
        }
      } else {
        context.go('/login');
      }
    } catch (_) {
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: const Color(0xFFFF6B00).withOpacity(0.2),
                        blurRadius: 60,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/images/riseup_logo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: const Icon(Icons.trending_up_rounded,
                            color: Colors.white, size: 60),
                      ),
                    ),
                  ),
                )
                    .animate()
                    .scale(duration: 700.ms, curve: Curves.elasticOut)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 28),

                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFFF6B00),
                      Color(0xFFFFD700),
                      Color(0xFF6C5CE7),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ).createShader(bounds),
                  child: Text(
                    'RiseUp',
                    style: AppTextStyles.h1.copyWith(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 350.ms, duration: 600.ms)
                    .slideY(begin: 0.3, curve: Curves.easeOut),

                const SizedBox(height: 6),

                Text(
                  'Your AI Wealth Mentor',
                  style: AppTextStyles.label.copyWith(
                    fontSize: 14,
                    letterSpacing: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                const SizedBox(height: 64),

                SizedBox(
                  width: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      backgroundColor: Color(0xFF1F1F3A),
                      valueColor:
                          AlwaysStoppedAnimation(Color(0xFFFF6B00)),
                      minHeight: 3,
                    ),
                  ),
                ).animate().fadeIn(delay: 900.ms),
              ],
            ),
          ),

          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Made with ',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Text('❤️', style: TextStyle(fontSize: 12)),
                    Text(
                      ' by ChAs Tech Group',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn(delay: 1200.ms),
          ),
        ],
      ),
    );
  }
}
