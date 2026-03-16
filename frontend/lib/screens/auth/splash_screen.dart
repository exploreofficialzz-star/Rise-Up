import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

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
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    final isAuth = await api.isAuthenticated();
    if (!mounted) return;
    if (isAuth) {
      // Check if onboarding done
      try {
        final profile = await api.getProfile();
        final onboarded = profile['profile']?['onboarding_completed'] ?? false;
        if (!mounted) return;
        context.go(onboarded ? '/home' : '/onboarding');
      } catch (_) {
        if (mounted) context.go('/home');
      }
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: AppShadows.glow,
              ),
              child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 52),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

            const SizedBox(height: 24),

            Text('RiseUp', style: AppTextStyles.h1.copyWith(
              fontSize: 40,
              foreground: Paint()..shader = const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
            )).animate().fadeIn(delay: 400.ms, duration: 600.ms).slideY(begin: 0.3),

            const SizedBox(height: 8),

            Text(
              'Your AI Wealth Mentor',
              style: AppTextStyles.label,
            ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

            const SizedBox(height: 60),

            SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                backgroundColor: AppColors.bgCard,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                borderRadius: BorderRadius.circular(4),
              ),
            ).animate().fadeIn(delay: 1000.ms),

            const SizedBox(height: 60),

            Text(
              'ChAs Tech Group',
              style: AppTextStyles.caption.copyWith(letterSpacing: 2),
            ).animate().fadeIn(delay: 1200.ms),
          ],
        ),
      ),
    );
  }
}
