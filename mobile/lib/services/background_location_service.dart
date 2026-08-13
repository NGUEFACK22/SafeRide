import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import 'offline_service.dart';

/// Service de fond Android (Foreground Service) pour le suivi GPS du trajet
/// en arrière-plan (Point 11). Envoie les positions via la file hors-ligne
/// même si l'écran est verrouillé ou l'app en arrière-plan.
class BackgroundLocationService {
  static const _channelId = 'saferide_location';
  static const _notificationId = 888;

  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        foregroundServiceNotificationId: _notificationId,
        initialNotificationTitle: 'SafeRide AI',
        initialNotificationContent: 'Surveillance de votre trajet…',
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Démarre le suivi GPS en arrière-plan pour le trajet donné.
  Future<void> startTripTracking(int tripId) async {
    await initialize();
    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      service.invoke('setTripId', {'tripId': tripId});
      return;
    }

    // On capte l'événement 'ready' avant de démarrer pour éviter une condition de concurrence
    service.on('ready').listen((_) {
      FlutterBackgroundService().invoke('setTripId', {'tripId': tripId});
    });
    service.startService();
  }

  /// Arrête le suivi GPS en arrière-plan.
  Future<void> stopTripTracking() async {
    FlutterBackgroundService().invoke('stop');
  }

  /// Exécuté dans l'isolat de fond.
  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    int? tripId;

    service.on('setTripId').listen((event) {
      tripId = event?['tripId'] as int?;
    });

    service.on('stop').listen((_) {
      service.stopSelf();
    });

    service.invoke('ready', {});

    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (tripId == null) return;

      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }

        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        );

        await OfflineService.instance.sendLocation(
          tripId!,
          position.latitude,
          position.longitude,
          position.speed * 3.6,
        );

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'SafeRide AI',
            content: 'Position envoyée (trajet #$tripId)',
          );
        }
      } catch (_) {
        // hors-ligne ou GPS indispo : la position sera rejouée par la file
      }
    });
  }

  @pragma('vm:entry-point')
  static bool _onIosBackground(ServiceInstance service) {
    return true;
  }
}
