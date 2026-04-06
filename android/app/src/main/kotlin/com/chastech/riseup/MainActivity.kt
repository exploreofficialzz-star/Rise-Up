// android/app/src/main/kotlin/com/chastech/riseup/MainActivity.kt
// ─────────────────────────────────────────────────────────────────────────────
//  RiseUp — Android Main Activity
//  Registers the NativeAdFactory with the Google Mobile Ads Flutter plugin.
//  WITHOUT this registration, all NativeAd loads fail silently.
// ─────────────────────────────────────────────────────────────────────────────

package com.chastech.riseup

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the native ad factory.
        // "riseup_native" must match the factoryId used in ad_service.dart:
        //   NativeAd(factoryId: 'riseup_native', ...)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "riseup_native",
            RiseUpNativeAdFactory(layoutInflater)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Always unregister on cleanup to prevent memory leaks.
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "riseup_native")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
