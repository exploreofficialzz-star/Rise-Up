// frontend/lib/services/notification_service.dart
// v2.0 — Full FCM + Local notification service
//
// NEW in v2.0:
//  • showLocalNotification() — plays device DEFAULT notification tone
//    (same as WhatsApp/Facebook — no custom sound file needed).
//    Called by CreatePostScreen and HomeScreen's SoundService when a post
//    or status is published successfully.
//  • All v1.0 features preserved: FCM token registration, background handler,
//    Android channel, foreground banners, tap routing, token refresh.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/router.dart';
import 'api_service.dart';

// ─── Background handler (top-level — required by FCM) ────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // OS shows the notification automatically using the device default sound.
}

// ─── Android notification channel ────────────────────────────────────────────
// No `sound` parameter → device DEFAULT notification tone (same as WhatsApp).
const _channel = AndroidNotificationChannel(
  'riseup_main',
  'RiseUp Notifications',
  description: 'Likes, messages, streaks and reminders from RiseUp',
  importance:      Importance.high,
  playSound:       true,    // true + no custom sound = OS default tone
  enableVibration: true,
  showBadge:       true,
);

// ─── v2.0: Dedicated channel for post/status published sounds ────────────────
// Same as above — device default tone, highest importance for immediate banner.
const _publishChannel = AndroidNotificationChannel(
  'riseup_publish',
  'RiseUp Post Published',
  description: 'Sound when your post or status goes live',
  importance:      Importance.high,
  playSound:       true,
  enableVibration: true,
  showBadge:       false,
);

// ─── Service ──────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  bool   _initialized = false;
  String? pendingRoute;

  // ── initialize() ─────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    // 1. Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 2. Request permission
    final settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // 3. Create Android channels
    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_publishChannel);

    // 4. Init flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true,
      defaultPresentSound: true,   // iOS: device default tone
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) => _handleTap(response.payload),
    );

    // 5. iOS foreground
    await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // 6. Listeners
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _handleTap(msg.data['route'] as String?));

    // 7. Terminated tap
    final initial = await _fcm.getInitialMessage();
    if (initial != null) pendingRoute = initial.data['route'] as String?;

    // 8. Token
    await _registerToken();
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  // ── v2.0: showLocalNotification() ────────────────────────────────────────
  /// Show an immediate local notification using the device's DEFAULT
  /// notification sound — no custom audio file required.
  /// Used by SoundService.post() and SoundService.statusPost().
  Future<void> showLocalNotification({
    required int    id,
    required String title,
    required String body,
    String? payload,
    bool    usePublishChannel = true,  // publish channel for post sounds
  }) async {
    if (kIsWeb) return;
    try {
      final channelId   = usePublishChannel ? _publishChannel.id : _channel.id;
      final channelName = usePublishChannel ? _publishChannel.name : _channel.name;

      await _local.show(
        id, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, channelName,
            importance:       Importance.high,
            priority:         Priority.high,
            icon:             '@mipmap/ic_launcher',
            playSound:        true,       // OS default sound
            enableVibration:  true,
            // No `sound` field → falls back to device default ringtone
            styleInformation: const DefaultStyleInformation(true, true),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            // sound: null → iOS default notification tone
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      // Non-fatal — sound failure must never crash the app
    }
  }

  // ── Foreground message → local banner ─────────────────────────────────────
  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _local.show(
      n.hashCode, n.title, n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          channelDescription: _channel.description,
          importance:      Importance.high,
          priority:        Priority.high,
          icon:            '@mipmap/ic_launcher',
          playSound:       true,
          enableVibration: true,
          fullScreenIntent: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: message.data['route'] as String?,
    );
  }

  // ── Tap routing ──────────────────────────────────────────────────────────
  void _handleTap(String? route) {
    if (route == null || route.isEmpty) return;
    try {
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null) { router.go(route); } else { pendingRoute = route; }
    } catch (_) { pendingRoute = route; }
  }

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
    } catch (_) {}
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService().registerFcmToken(token: token, platform: platform);
    } catch (_) {}
  }

  Future<void> onLogout() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) await ApiService().unregisterFcmToken(token);
      await _fcm.deleteToken();
    } catch (_) {}
  }

  Future<String?> getToken()  => _fcm.getToken();
  Future<void>    cancelAll() async { if (!kIsWeb) await _local.cancelAll(); }
}

final notificationService = NotificationService();
