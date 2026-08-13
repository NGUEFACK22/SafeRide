import 'dart:convert';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';
import 'database_service.dart';

/// File d'attente de synchronisation hors-ligne (Point 12).
///
/// Les positions GPS sont d'abord persistées localement (SQLite), puis envoyées
/// à l'API. En cas d'échec réseau, elles restent en file d'attente et sont
/// rejouées dès le retour de la connexion. Expose un état de connectivité et le
/// nombre d'éléments en attente pour l'UI ("En attente de connexion" vs "Alerté").
class OfflineService {
  OfflineService._() {
    _connectivity.onConnectivityChanged.listen((result) {
      _online = !result.contains(ConnectivityResult.none);
      _connectivityController.add(_online);
      if (_online) {
        unawaited(flush());
      }
    });
    _init();
  }

  static final OfflineService instance = OfflineService._();

  final ApiService _api = ApiService();
  final Connectivity _connectivity = Connectivity();

  bool _online = true;
  bool get isOnline => _online;

  final _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  Future<void> _init() async {
    final result = await _connectivity.checkConnectivity();
    _online = !result.contains(ConnectivityResult.none);
    _connectivityController.add(_online);
  }

  /// Persiste une position localement puis tente l'envoi immédiat.
  Future<void> sendLocation(
    int tripId,
    double latitude,
    double longitude,
    double? speed,
  ) async {
    final db = await DatabaseService.database;
    final capturedAt = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('trip_locations', {
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'vitesse_km_h': speed,
      'captured_at': capturedAt,
      'retry_count': 0,
    });

    if (!_online) return;

    try {
      await _api.post('/trips/$tripId/locations', {
        'latitude': latitude,
        'longitude': longitude,
        'vitesse_km_h': speed,
        'captured_at': capturedAt,
      });
      await db.update(
        'trip_locations',
        {'synced_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {
      // Reste en file d'attente locale ; sera rejoué par flush().
    }
  }

  /// Rejoue toutes les positions non synchronisées.
  Future<void> flush() async {
    final db = await DatabaseService.database;
    final pending = await db.query(
      'trip_locations',
      where: 'synced_at IS NULL',
      orderBy: 'captured_at ASC',
    );

    for (final row in pending) {
      final tripId = row['trip_id'] as int;
      try {
        await _api.post('/trips/$tripId/locations', {
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'vitesse_km_h': row['vitesse_km_h'],
          'captured_at': row['captured_at'],
        });
        await db.update(
          'trip_locations',
          {'synced_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } catch (e) {
        final retries = (row['retry_count'] as int? ?? 0) + 1;
        if (retries >= 10) {
          // abandon après 10 tentatives pour éviter une croissance infinie
          await db.delete('trip_locations', where: 'id = ?', whereArgs: [row['id']]);
        } else {
          await db.update(
            'trip_locations',
            {'retry_count': retries},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        break; // plus de réseau : on arrête la boucle
      }
    }
  }

  /// Nombre de positions en attente de synchronisation.
  Future<int> pendingLocationCount() async {
    final db = await DatabaseService.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM trip_locations WHERE synced_at IS NULL',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Enfile une opération API générique (ex : déclenchement SOS) pour relecture hors-ligne.
  Future<void> enqueue(String endpoint, String method, Map<String, dynamic> payload) async {
    final db = await DatabaseService.database;
    await db.insert('sync_queue', {
      'endpoint': endpoint,
      'method': method,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'retry_count': 0,
    });
    if (_online) await _flushQueue();
  }

  Future<void> _flushQueue() async {
    final db = await DatabaseService.database;
    final pending = await db.query('sync_queue', orderBy: 'created_at ASC');
    for (final row in pending) {
      try {
        await _api.post(row['endpoint'] as String, jsonDecode(row['payload'] as String));
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [row['id']]);
      } catch (_) {
        break;
      }
    }
  }
}
