import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../config/app_constants.dart';

class VersionCheckService {
  static final VersionCheckService _i = VersionCheckService._();
  factory VersionCheckService() => _i;
  VersionCheckService._();

  Future<void> checkAndPrompt(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final result = await api.checkVersion(info.version);
      final updateRequired = result['update_required'] ?? false;
      if (updateRequired && context.mounted) {
        _showUpdateDialog(context, result);
      }
    } catch (_) {
      // Silent fail — never block the user because of a version check
    }
  }

  void _showUpdateDialog(BuildContext context, Map data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 32),
                ),
                const SizedBox(height: 20),
                Text('Update Required', style: AppTextStyles.h3, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  data['update_message'] ?? 'A new version of RiseUp is available. Please update to continue.',
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openStore(data),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                    ),
                    child: Text('Update Now', style: AppTextStyles.h4.copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStore(Map data) async {
    final url = data['store_url_android'] ?? 'https://play.google.com/store/apps/details?id=com.chastech.riseup';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final versionCheckService = VersionCheckService();
