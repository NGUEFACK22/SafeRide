import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final ApiService _api = ApiService();
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final List<void Function()> _refreshListeners = [];
  bool _initialized = false;

  void addRefreshListener(void Function() listener) {
    _refreshListeners.add(listener);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Local notifications for foreground
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      _showForeground(message);
      _notify();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _notify());

    messaging.onTokenRefresh.listen(_register);

    final token = await messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'SafeRide';
    final body = notification?.body ?? message.data['body'] ?? 'Nouvelle notification';
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'SafeRide Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _local.show(0, title, body, details);
  }

  void _notify() {
    for (final listener in _refreshListeners) {
      listener();
    }
  }

  Future<void> _register(String token) async {
    try {
      await _api.post('/push-token', {
        'token': token,
        'device': Platform.isAndroid ? 'android' : 'ios',
      });
    } catch (_) {}
  }
}