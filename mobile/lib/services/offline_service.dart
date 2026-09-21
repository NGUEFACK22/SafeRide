import 'dart:async';
import 'dart:convert';

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
      if (_online) _replayQueues();
    });
    _init();
    // Garde-fou réseau faible : connectivity_plus ne voit pas toujours le
    // retour d'un réseau dégradé (2G, portail captif). On re-tente la file
    // SOS toutes les 30s tant qu'elle n'est pas vide, même sans changement
    // d'état — garantit la reprise sous 2 à 5 min d'attente.
    _sosRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        if (await pendingSosCount() > 0) await _flushQueue();
      } catch (_) {}
    });
  }

  static final OfflineService instance = OfflineService._();

  final ApiService _api = ApiService();
  final Connectivity _connectivity = Connectivity();
  Timer? _sosRetryTimer;

  /// Libère le timer de reprise SOS (appelé lors d'un éventuel teardown).
  void dispose() {
    _sosRetryTimer?.cancel();
    _sosRetryTimer = null;
    _connectivityController.close();
  }

  bool _online = true;
  bool get isOnline => _online;

  final _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  Future<void> _init() async {
    final result = await _connectivity.checkConnectivity();
    _online = !result.contains(ConnectivityResult.none);
    _connectivityController.add(_online);
    if (_online) _replayQueues();
  }

  /// Rejoue les deux files (positions + opérations génériques) au retour réseau
  /// ou au démarrage : sinon une alerte SOS en file ne partirait jamais.
  void _replayQueues() {
    unawaited(flush());
    unawaited(_flushQueue());
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

  /// Nombre de SOS en attente dans la file (jamais purgés pour échec réseau).
  Future<int> pendingSosCount() async {
    final db = await DatabaseService.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_queue WHERE endpoint LIKE '%/sos%'",
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Rejoue la file d'attente. Distinction cruciale :
  /// - erreur TRANSIENTE (pas de réponse réseau, ou 5xx serveur) → retry_count++,
  ///   JAMAIS d'abandon pour les SOS (ils doivent tenir 2 à 5 min et plus) ;
  ///   les autres endpoints sont abandonnés après 40 tentatives (~20 min) ;
  /// - erreur PERMANENTE (4xx : ex anti-spam 429 SOS, validation 422, 401) →
  ///   l'opération est définitivement refusée par le serveur : on la retire
  ///   de la file (et on note last_error), sinon elle bloquerait toute la queue.
  Future<void> _flushQueue() async {
    final db = await DatabaseService.database;
    final pending = await db.query('sync_queue', orderBy: 'created_at ASC');
    for (final row in pending) {
      final id = row['id'];
      final endpoint = (row['endpoint'] as String?) ?? '';
      final isSos = endpoint.contains('/sos');
      try {
        await _api.post(endpoint, jsonDecode(row['payload'] as String));
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
      } on ApiException catch (e) {
        // Un 5xx est transitoire (serveur surchargé / redéploiement) : on réessaie.
        if (e.statusCode >= 500) {
          final retries = (row['retry_count'] as int? ?? 0) + 1;
          if (!isSos && retries >= 40) {
            await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
          } else {
            await db.update(
              'sync_queue',
              {
                'retry_count': retries,
                'last_error': e.message.substring(0, e.message.length.clamp(0, 250)),
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
          break; // serveur indisponible : on arrête la boucle, on réessaiera
        }
        // 4xx = refus définitif du serveur : rejouer ne changera rien (ex : SOS
        // déjà transmis il y a <30s, validation échouée). On purge la ligne pour
        // ne pas bloquer le reste de la file, en traçant l'erreur.
        await db.update(
          'sync_queue',
          {
            'last_error': 'PERMANENT ${e.statusCode}: ${e.message.substring(0, e.message.length.clamp(0, 220))}',
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
      } catch (e) {
        // Erreur réseau : réessayer plus tard. Les SOS ne sont JAMAIS
        // abandonnés (attente 2-5 min et plus) ; les autres le sont après 40.
        final retries = (row['retry_count'] as int? ?? 0) + 1;
        if (!isSos && retries >= 40) {
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
        } else {
          await db.update(
            'sync_queue',
            {
              'retry_count': retries,
              'last_error': e.toString().substring(0, e.toString().length.clamp(0, 250)),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        break; // plus de réseau : on arrête la boucle
      }
    }
  }
}
