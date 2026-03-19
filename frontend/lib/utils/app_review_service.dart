import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_constants.dart';

class AppReviewService {
  static const _keyTaskCount   = 'completed_task_count';
  static const _keyReviewShown = 'review_dialog_shown';
  static const _triggerCount   = 3;

  static final AppReviewService _i = AppReviewService._();
  factory AppReviewService() => _i;
  AppReviewService._();

  final _inAppReview = InAppReview.instance;

  Future<void> onTaskCompleted(BuildContext context) async {
    if (kIsWeb) return;
    final prefs  = await SharedPreferences.getInstance();
    final shown  = prefs.getBool(_keyReviewShown) ?? false;
    if (shown) return;

    final count = (prefs.getInt(_keyTaskCount) ?? 0) + 1;
    await prefs.setInt(_keyTaskCount, count);

    if (count < _triggerCount || !context.mounted) return;
    await prefs.setBool(_keyReviewShown, true);

    // Small delay so it feels natural, not immediate
    await Future.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) return;

    // Try native in-app review first (won't always show — OS decides)
    try {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
        return;
      }
    } catch (_) {}

    // Fallback: show custom dialog
    if (context.mounted) _showFallbackDialog(context);
  }

  void _showFallbackDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌟', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text('Loving RiseUp?', style: AppTextStyles.h3, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'You\'ve been making progress! A quick review helps us reach more people who need this.',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); _openStore(); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                  ),
                  child: Text('⭐  Rate on Play Store',
                      style: AppTextStyles.h4.copyWith(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Maybe later',
                    style: AppTextStyles.label.copyWith(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStore() async {
    const url = 'https://play.google.com/store/apps/details?id=com.chastech.riseup';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final appReviewService = AppReviewService();
