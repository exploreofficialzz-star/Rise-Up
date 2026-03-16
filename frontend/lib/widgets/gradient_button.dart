// ============================================================
// Reusable Widgets — gradient_button.dart
// ============================================================
import 'package:flutter/material.dart';
import 'config/app_constants.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final List<Color>? colors;
  const GradientButton({super.key, required this.text, this.onTap, this.isLoading = false, this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: onTap == null ? [AppColors.textMuted, AppColors.textMuted] : (colors ?? [AppColors.primary, AppColors.accent]),
          ),
          borderRadius: AppRadius.md,
          boxShadow: onTap != null ? AppShadows.glow : [],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(text, style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 15)),
        ),
      ),
    );
  }
}
