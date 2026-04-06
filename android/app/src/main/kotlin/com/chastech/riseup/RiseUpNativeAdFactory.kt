// android/app/src/main/kotlin/com/chastech/riseup/RiseUpNativeAdFactory.kt
// ─────────────────────────────────────────────────────────────────────────────
//  RiseUp — Native Ad Factory
//  Inflates native_ad.xml and binds all NativeAd assets into the view.
//  This class is required by google_mobile_ads for native ads to render.
// ─────────────────────────────────────────────────────────────────────────────

package com.chastech.riseup   

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class RiseUpNativeAdFactory(
    private val layoutInflater: LayoutInflater
) : GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {

        val adView = layoutInflater.inflate(
            R.layout.native_ad, null
        ) as NativeAdView

        // ── Media (hero image / video) ────────────────────────────────────
        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        adView.mediaView = mediaView

        // ── Headline ─────────────────────────────────────────────────────
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        adView.headlineView = headlineView
        headlineView.text = nativeAd.headline

        // ── Body ─────────────────────────────────────────────────────────
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        adView.bodyView = bodyView
        if (nativeAd.body != null) {
            bodyView.text = nativeAd.body
            bodyView.visibility = View.VISIBLE
        } else {
            bodyView.visibility = View.INVISIBLE
        }

        // ── Call-to-Action ────────────────────────────────────────────────
        val callToActionView = adView.findViewById<Button>(R.id.ad_call_to_action)
        adView.callToActionView = callToActionView
        if (nativeAd.callToAction != null) {
            callToActionView.text = nativeAd.callToAction
            callToActionView.visibility = View.VISIBLE
        } else {
            callToActionView.visibility = View.INVISIBLE
        }

        // ── Icon ──────────────────────────────────────────────────────────
        val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
        adView.iconView = iconView
        if (nativeAd.icon != null) {
            iconView.setImageDrawable(nativeAd.icon!!.drawable)
            iconView.visibility = View.VISIBLE
        } else {
            iconView.visibility = View.GONE
        }

        // ── Price ─────────────────────────────────────────────────────────
        val priceView = adView.findViewById<TextView>(R.id.ad_price)
        adView.priceView = priceView
        if (nativeAd.price != null) {
            priceView.text = nativeAd.price
            priceView.visibility = View.VISIBLE
        } else {
            priceView.visibility = View.INVISIBLE
        }

        // ── Store ─────────────────────────────────────────────────────────
        val storeView = adView.findViewById<TextView>(R.id.ad_store)
        adView.storeView = storeView
        if (nativeAd.store != null) {
            storeView.text = nativeAd.store
            storeView.visibility = View.VISIBLE
        } else {
            storeView.visibility = View.INVISIBLE
        }

        // ── Star Rating ───────────────────────────────────────────────────
        val starRatingView = adView.findViewById<RatingBar>(R.id.ad_stars)
        adView.starRatingView = starRatingView
        if (nativeAd.starRating != null) {
            starRatingView.rating = nativeAd.starRating!!.toFloat()
            starRatingView.visibility = View.VISIBLE
        } else {
            starRatingView.visibility = View.INVISIBLE
        }

        // ── Advertiser ────────────────────────────────────────────────────
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        adView.advertiserView = advertiserView
        if (nativeAd.advertiser != null) {
            advertiserView.text = nativeAd.advertiser
            advertiserView.visibility = View.VISIBLE
        } else {
            advertiserView.visibility = View.INVISIBLE
        }

        // Bind the NativeAd object last — triggers tracking.
        adView.setNativeAd(nativeAd)

        return adView
    }
}
