import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:saferide_mobile/models/trip.dart';
import 'package:saferide_mobile/models/user.dart';
import 'package:saferide_mobile/services/background_location_service.dart';
import 'package:saferide_mobile/services/osrm_service.dart';

void main() {
  group('OsrmService.decodePolyline', () {
    test('décode une polyline Google encodée', () {
      // Exemple canonique de la doc Google (encoders) :
      // `_p~iF~ps|U` → (38.5, -120.2)
      const encoded = '_p~iF~ps|U';
      final points = OsrmService.decodePolyline(encoded);
      expect(points.length, 1);
      expect(points.first.latitude, closeTo(38.5, 0.0001));
      expect(points.first.longitude, closeTo(-120.2, 0.0001));
    });

    test('gère une chaîne vide sans erreur', () {
      expect(OsrmService.decodePolyline(''), isEmpty);
    });
  });

  group('Trip.fromJson', () {
    test('parse tous les champs du trajet', () {
      final trip = Trip.fromJson({
        'id': 42,
        'passager_id': 1,
        'transporteur_id': 2,
        'vehicle_id': 7,
        'start_latitude': '3.8480',
        'start_longitude': '11.5021',
        'destination_latitude': '3.8700',
        'destination_longitude': '11.5210',
        'destination_address': 'Yaoundé Centre',
        'started_at': '2026-08-15T10:00:00',
        'ended_at': '2026-08-15T10:30:00',
        'distance_km': '4.2',
        'duration_seconds': 1800,
        'deviation_km': '0.1',
        'statut': 'EN_COURS',
        'end_method': null,
        'planned_route_polyline': null,
        'actual_route_polyline': null,
        'transporteur': {'nom': 'Mbarga', 'prenom': 'Paul'},
      });

      expect(trip.id, 42);
      expect(trip.destinationAddress, 'Yaoundé Centre');
      expect(trip.distanceKm, 4.2);
      expect(trip.statut, 'EN_COURS');
      expect(trip.transporteurFullName, 'Paul Mbarga');
    });

    test('gère les valeurs numériques en double', () {
      final trip = Trip.fromJson({
        'id': 1,
        'passager_id': 1,
        'transporteur_id': 2,
        'vehicle_id': 3,
        'distance_km': 5.75,
        'statut': 'TERMINE',
      });

      expect(trip.distanceKm, 5.75);
      expect(trip.startLatitude, isNull);
    });

    test('isActive et hasDestination', () {
      final active = Trip.fromJson({
        'id': 1,
        'passager_id': 1,
        'transporteur_id': 2,
        'vehicle_id': 3,
        'statut': 'EN_COURS',
        'destination_latitude': 3.8,
        'destination_longitude': 11.5,
      });
      expect(active.isActive, isTrue);
      expect(active.hasDestination, isTrue);

      final done = Trip.fromJson({
        'id': 2,
        'passager_id': 1,
        'transporteur_id': 2,
        'vehicle_id': 3,
        'statut': 'TERMINE',
      });
      expect(done.isActive, isFalse);
      expect(done.hasDestination, isFalse);
    });
  });

  group('User.fromJson', () {
    test('parse les rôles et le nom complet', () {
      final user = User.fromJson({
        'id': 9,
        'nom': 'Fouda',
        'prenom': 'Aline',
        'email': 'aline@ex.com',
        'telephone': '690000001',
        'photo_url': null,
        'statut': 'ACTIF',
        'roles': ['passager', 'transporteur'],
      });

      expect(user.fullName, 'Aline Fouda');
      expect(user.hasRole('transporteur'), isTrue);
      expect(user.hasRole('admin'), isFalse);
      expect(user.roles, ['passager', 'transporteur']);
    });

    test('rôles vides par défaut', () {
      final user = User.fromJson({
        'id': 1,
        'nom': 'X',
        'prenom': 'Y',
        'email': 'x@y.com',
        'telephone': '690000002',
        'statut': 'ACTIF',
      });
      expect(user.roles, isEmpty);
    });
  });

  group('BackgroundLocationService.flushSosQueueInBackground', () {
    test('file vide -> 0 envoyé', () async {
      final sent = await BackgroundLocationService.flushSosQueueInBackground(
        openDbForTest: () async => _FakeDb([]),
        postForTest: (_, __, ___) async => http.Response('{}', 201),
        skipTokenForTest: true,
      );
      expect(sent, 0);
    });

    test('1 SOS en file + réseau OK -> envoyé et purgé', () async {
      final db = _FakeDb([
        {
          'id': 7,
          'endpoint': '/sos',
          'payload':
              '{"latitude":3.848,"longitude":11.5021,"declenchement":"BOUTON"}',
        },
      ]);
      final sent = await BackgroundLocationService.flushSosQueueInBackground(
        openDbForTest: () async => db,
        postForTest: (_, __, ___) async => http.Response('{"sos":{}}', 201),
        skipTokenForTest: true,
      );
      expect(sent, 1);
      expect(db.deletedIds, [7]);
    });

    test('erreur 422 (refus définitif) -> purgé sans bloquer, 0 envoyé',
        () async {
      final db = _FakeDb([
        {'id': 9, 'endpoint': '/sos', 'payload': '{}'},
      ]);
      final sent = await BackgroundLocationService.flushSosQueueInBackground(
        openDbForTest: () async => db,
        postForTest: (_, __, ___) async => http.Response('{}', 422),
        skipTokenForTest: true,
      );
      expect(sent, 0);
      expect(db.deletedIds, [9]);
    });

    test('panne réseau (exception) -> conservé pour le prochain tick',
        () async {
      final db = _FakeDb([
        {'id': 11, 'endpoint': '/sos', 'payload': '{}'},
      ]);
      final sent = await BackgroundLocationService.flushSosQueueInBackground(
        openDbForTest: () async => db,
        postForTest: (_, __, ___) async => throw Exception('no network'),
        skipTokenForTest: true,
      );
      expect(sent, 0);
      expect(db.deletedIds, isEmpty);
    });

    test('coupure 5 min simulée (20 échecs) puis retour -> SOS part', () async {
      // Reproduit : réseau coupé 5 min (20 ticks x 15s) puis rétabli.
      // Le SOS ne doit JAMAIS être purgé pour "trop de tentatives".
      final db = _FakeDb([
        {
          'id': 21,
          'endpoint': '/sos',
          'payload':
              '{"latitude":3.848,"longitude":11.5021,"declenchement":"BOUTON"}',
        },
      ]);
      var calls = 0;
      Future<http.Response> flaky(
          Uri uri, Map<String, String> headers, String body) async {
        calls++;
        if (calls <= 20) throw Exception('no network 5 min');
        return http.Response('{"sos":{}}', 201);
      }

      for (var i = 0; i < 20; i++) {
        final sent = await BackgroundLocationService.flushSosQueueInBackground(
          openDbForTest: () async => db,
          postForTest: flaky,
          skipTokenForTest: true,
        );
        expect(sent, 0);
        expect(db.deletedIds, isEmpty,
            reason: 'tick ${i + 1}/20 : le SOS doit rester en file');
      }
      final sent = await BackgroundLocationService.flushSosQueueInBackground(
        openDbForTest: () async => db,
        postForTest: flaky,
        skipTokenForTest: true,
      );
      expect(sent, 1);
      expect(db.deletedIds, [21]);
    });
  });
}

/// Faux SQLite minimal pour tester la logique de rejeu sans plugin natif.
class _FakeDb {
  _FakeDb(this.rows);
  final List<Map<String, Object?>> rows;
  final List<Object?> deletedIds = [];
  bool closed = false;

  Future<List<Map<String, Object?>>> query(String table,
      {String? orderBy, int? limit}) async {
    var out = List<Map<String, Object?>>.from(rows);
    if (limit != null && out.length > limit) out = out.sublist(0, limit);
    return out;
  }

  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    if (whereArgs != null) deletedIds.addAll(whereArgs);
    return whereArgs?.length ?? 0;
  }

  Future<void> close() async {
    closed = true;
  }
}