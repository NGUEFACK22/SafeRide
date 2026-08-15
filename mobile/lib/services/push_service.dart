import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final ApiService _api = ApiService();
  final List<void Function()> _refreshListeners = [];
  bool _initialized = false;

  void addRefreshListener(void Function() listener) {
    _refreshListeners.add(listener);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) => _notify());
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _notify());

    messaging.onTokenRefresh.listen(_register);

    final token = await messaging.getToken();
    if (token != null) await _register(token);
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