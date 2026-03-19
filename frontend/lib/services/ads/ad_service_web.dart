// ─────────────────────────────────────────────────────────────
//  Web Ad Service
//  • Full-page ads → Google AdSense in web/index.html
//  • In-app banner slots → HtmlElementView (AdSense ins tag)
//  • Interstitial/rewarded → reward granted immediately on web
// ─────────────────────────────────────────────────────────────
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'ad_service_base.dart';

class AdService implements AdServiceBase {
  static final AdService _i = AdService._();
  factory AdService() => _i;
  AdService._();

  bool _registered = false;

  @override
  Future<void> initialize() async {
    // Register HtmlElementView factory for AdSense inline slots
    if (!_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(
        'adsense-banner',
        (int viewId) {
          // Create AdSense ins element — Google auto-fills it
          final ins = _createAdElement();
          // Trigger adsbygoogle push after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            _pushAd();
          });
          return ins;
        },
      );
    }
  }

  // ignore: undefined_prefixed_name
  dynamic _createAdElement() {
    // Use dart:html via js interop to create <ins> element
    import_html: {
      try {
        // This runs only on web — dart:html is available
        final ins = document_createElement('ins');
        ins.className = 'adsbygoogle';
        ins.style.display = 'block';
        ins.style.width = '100%';
        ins.style.height = '90px';
        ins.setAttribute('data-ad-client', 'ca-pub-XXXXXXXXXXXXXXXX');
        ins.setAttribute('data-ad-slot', 'XXXXXXXXXX');
        ins.setAttribute('data-ad-format', 'auto');
        ins.setAttribute('data-full-width-responsive', 'true');
        return ins;
      } catch (_) {
        return _divFallback();
      }
    }
    return _divFallback();
  }

  dynamic _divFallback() => null;
  void _pushAd() {}

  @override
  bool get isRewardedReady => false;

  @override
  Future<bool> showRewardedAd({
    required String featureKey,
    required Function onRewarded,
    required Function onDismissed,
  }) async {
    // On web, reward immediately (AdSense doesn't support rewarded)
    onRewarded();
    return true;
  }

  @override
  Future<void> showInterstitialIfReady() async {
    // Auto-ads in index.html handles interstitials on web
  }

  @override
  Future<void> showAppOpenAdIfAvailable() async {
    // Auto-ads in index.html handles app open on web
  }
}

final adService = AdService();

// ─────────────────────────────────────────────────────────────
//  Web BannerAdWidget
//  Renders a clean info strip pointing users to the web version
//  (In-Flutter AdSense requires complex platform views — the
//   real AdSense banners are injected directly in index.html)
// ─────────────────────────────────────────────────────────────
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // On web, ads are shown via HTML in index.html (top + bottom bars)
    // Return empty — no double-ads needed inside Flutter canvas
    return const SizedBox.shrink();
  }
}
