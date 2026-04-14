// lib/services/notification_service.dart
//
// Full FCM push notification service — replaces the local-only version.
// Uses the user's default notification sound exactly like WhatsApp/YouTube.
//
// What this does:
//  • Requests OS permission on first launch (Android 13+ / iOS)
//  • Creates a high-importance Android channel (default device sound)
//  • Shows foreground notifications via flutter_local_notifications
//  • Handles background + terminated notification taps via GoRouter
//  • Registers/refreshes the FCM token with your backend automatically
//  • Deletes the token on logout

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../config/router.dart';        // for router.go() on tap
import 'api_service.dart';             // for registerFcmToken / deleteFcmToken

// ─── Background handler ────────────────────────────────────────────────────
// MUST be a top-level function (not a class method).
// FCM calls this when the app is in the background / terminated.
// The OS shows the notification automatically using the device default sound.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Nothing extra needed — the OS already shows the notification.
  // Add data-only message handling here if required.
}

// ─── Android notification channel ─────────────────────────────────────────
// No `sound` parameter → device default notification tone (same as WhatsApp).
const _channel = AndroidNotificationChannel(
  'riseup_main',          // id  — must match what FCM server sends
  'RiseUp Notifications', // visible name in Android Settings
  description: 'Likes, messages, streaks and reminders from RiseUp',
  importance: Importance.high,
  playSound: true,        // true + no custom sound = OS default tone
  enableVibration: true,
  showBadge: true,
);

// ─── Service ───────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  // Stores a deep-link route from a notification tap that arrived while the
  // app was terminated. router.dart reads this after the Navigator is ready.
  String? pendingRoute;

  // ── initialize() ─────────────────────────────────────────────────────────
  // Call this once in main.dart AFTER Firebase.initializeApp().
  Future<void> initialize() async {
    if (kIsWeb) return; // Web uses a separate service worker flow

    // 1. Register the background handler before anything else
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 2. Request permission (Android 13+ / iOS)
    final settings = await _fcm.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false, // provisional = silent delivery on iOS until tapped
    );

    // Silent exit if user denied — do not crash
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // 3. Create the Android channel
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 4. Init flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentSound:    true, // iOS foreground: use device default tone
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        // Notification tapped while app is in foreground
        _handleTap(response.payload);
      },
    );

    // 5. iOS: show notifications while app is in foreground
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 6. Foreground message listener
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleTap(msg.data['route'] as String?);
    });

    // 8. App launched from terminated state via notification tap
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      pendingRoute = initial.data['route'] as String?;
    }

    // 9. Register token with backend
    await _registerToken();

    // 10. Auto-refresh token
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  // ── Foreground notification display ──────────────────────────────────────
  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;

    _local.show(
      // Stable unique ID — prevents duplicate banners for the same event
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance:    Importance.high,
          priority:      Priority.high,
          icon:          '@mipmap/ic_launcher',
          playSound:     true,   // no sound = OS default tone
          enableVibration: true,
          // Heads-up banner (like WhatsApp)
          fullScreenIntent: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // sound: null → default iOS notification tone
        ),
      ),
      payload: message.data['route'] as String?,
    );
  }

  // ── Tap routing ──────────────────────────────────────────────────────────
  void _handleTap(String? route) {
    if (route == null || route.isEmpty) return;
    // Try to navigate immediately; if navigator isn't ready yet, store it
    try {
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null) {
        router.go(route);
      } else {
        pendingRoute = route;
      }
    } catch (_) {
      pendingRoute = route;
    }
  }

  // Consume pendingRoute once the first authenticated screen loads
  void consumePendingRoute() {
    if (pendingRoute == null) return;
    final route = pendingRoute!;
    pendingRoute = null;
    try {
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null) router.go(route);
    } catch (_) {}
  }

  // ── Token management ─────────────────────────────────────────────────────
  Future<void> _registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (e) {
      // Non-fatal — app works without push
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService().registerFcmToken(token: token, platform: platform);
    } catch (_) {}
  }

  /// Call on logout so the user stops receiving notifications on this device
  Future<void> onLogout() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) await ApiService().unregisterFcmToken(token);
      await _fcm.deleteToken();
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Future<String?> getToken() => _fcm.getToken();

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _local.cancelAll();
  }
}

final notificationService = NotificationService();
