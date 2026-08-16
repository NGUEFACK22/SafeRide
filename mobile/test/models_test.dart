import 'package:flutter_test/flutter_test.dart';
import 'package:saferide_mobile/models/trip.dart';
import 'package:saferide_mobile/models/user.dart';

void main() {
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
}