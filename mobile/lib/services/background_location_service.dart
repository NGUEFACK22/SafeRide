import 'dart:async';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../config/api_config.dart';
import 'offline_service.dart';

/// Service de fond Android (Foreground Service) pour le suivi GPS du trajet
/// en arrière-plan (Point 11). Envoie les positions via la file hors-ligne
/// même si l'écran est verrouillé ou l'app en arrière-plan.
///
/// Extension SOS : rejoue aussi la file `sync_queue` (dont les SOS en attente)
/// toutes les 15s, même app fermée. Dès que le réseau revient, l'alerte part
/// automatiquement sans action de l'utilisateur.
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

  /// Démarre (ou réveille) le service de fond pour surveiller la file SOS,
  /// même sans trajet actif : garantit la reprise automatique après retour réseau.
  Future<void> ensureSosWatchdog() async {
    await initialize();
    final service = FlutterBackgroundService();
    if (await service.isRunning()) return;
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

    // P3-13 : 15s au lieu de 10s pour économiser batterie + adaptatif si immobile
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      // 1) Toujours rejouer la file SOS / sync_queue, avec ou sans trajet.
      // C'est ce qui fait partir l'alerte en attente dès le retour réseau,
      // même si l'utilisateur a fermé l'app.
      try {
        final flushed = await flushSosQueueInBackground();
        if (flushed > 0 && service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'SafeRide AI',
            content: 'Alerte SOS transmise ($flushed)',
          );
        }
      } catch (_) {
        // Silence en fond : on réessaiera au prochain tick.
      }

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

  /// Rejoue la file `sync_queue` (dont les SOS) depuis l'isolat de fond.
  /// Testable en unitaire via [flushSosQueueInBackground].
  static Future<int> flushSosQueueInBackground({
    Future<dynamic> Function()? openDbForTest,
    Future<http.Response> Function(Uri uri, Map<String, String> headers, String body)? postForTest,
    String? tokenForTest,
    bool skipTokenForTest = false,
  }) async {
    try {
      final dynamic db = openDbForTest != null
          ? await openDbForTest()
          : await _openSharedDb();
      if (db == null) return 0;
      try {
        final String? token = skipTokenForTest
            ? null
            : (tokenForTest ?? await _readAuthToken());

        final List<dynamic> pending =
            await db.query('sync_queue', orderBy: 'created_at ASC', limit: 10);
        if (pending.isEmpty) return 0;

        var sent = 0;
        for (final row in pending) {
          final dynamic id = (row as Map)['id'];
          final String endpoint = (row)['endpoint'] as String;
          final String body = (row)['payload'] as String;
          try {
            final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
            final headers = {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            };
            final http.Response response = postForTest != null
                ? await postForTest(uri, headers, body)
                : await http
                    .post(uri, headers: headers, body: body)
                    .timeout(const Duration(seconds: 12));

            if (response.statusCode >= 200 && response.statusCode < 400) {
              await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
              sent++;
            } else if (response.statusCode >= 400 && response.statusCode < 500) {
              // Refus définitif (422/429/401) : purge pour ne pas bloquer.
              await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
            } else {
              break; // 5xx : prochain tick
            }
          } catch (_) {
            break; // toujours pas de réseau : prochain tick dans 15s
          }
        }
        return sent;
      } finally {
        try {
          await db.close();
        } catch (_) {}
      }
    } catch (_) {
      return 0;
    }
  }

  /// Ouvre la base partagée `saferide.db` depuis l'isolat de fond.
  static Future<Database?> _openSharedDb() async {
    try {
      // Sur Android le path standard sqflite est accessible sans plugin :
      // /data/data/<package>/databases/saferide.db
      const candidates = [
        '/data/data/com.tech.saveride/databases/saferide.db',
      ];
      for (final path in candidates) {
        try {
          if (!await File(path).exists()) continue;
          return await openDatabase(path, readOnly: false);
        } catch (_) {
          continue;
        }
      }
      // Repli : chemin sqflite standard via getDatabasesPath indisponible
      // en isolat — on tente quand même le nom seul.
      try {
        final String dir = p.join('/data/data/com.tech.saveride/databases');
        return await openDatabase(p.join(dir, 'saferide.db'));
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Lit le token d'auth hors isolat UI (repli null en test).
  static Future<String?> _readAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token');
    } catch (_) {
      return null;
    }
  }
}
