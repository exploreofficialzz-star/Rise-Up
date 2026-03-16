import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_constants.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService().showLocalNotification(
    title: message.notification?.title ?? 'RiseUp',
    body: message.notification?.body ?? '',
    payload: message.data.toString(),
  );
}

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'riseup_channel';
  static const _channelName = 'RiseUp Notifications';

  Future<void> initialize() async {
    // Request permission
    await _fcm.requestPermission(
      alert: true, badge: true, sound: true,
    );

    // Init local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel
    const channel = AndroidNotificationChannel(
      _channelId, _channelName,
      description: 'RiseUp income tasks, milestones and tips',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Foreground handler
    FirebaseMessaging.onMessage.listen((message) {
      showLocalNotification(
        title: message.notification?.title ?? 'RiseUp',
        body: message.notification?.body ?? '',
        payload: message.data.toString(),
      );
    });

    // Get and store FCM token
    final token = await _fcm.getToken();
    if (token != null) {
      // TODO: Send token to backend for targeted notifications
      print('FCM Token: $token');
    }
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.high,
          priority: Priority.high,
          color: AppColors.primary,
          enableLights: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    // Handle tap — navigate to relevant screen
    final payload = response.payload;
    if (payload != null) {
      // TODO: Parse payload and navigate accordingly
    }
  }

  Future<void> scheduleMotivationalReminder() async {
    // Daily morning reminder
    await _localNotifications.periodicallyShow(
      1,
      '⚡ Income Task Waiting!',
      'Check your RiseUp tasks — your AI mentor has new opportunities for you.',
      RepeatInterval.daily,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.defaultImportance,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

final notificationService = NotificationService();
