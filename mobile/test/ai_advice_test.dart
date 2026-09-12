import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saferide_mobile/models/trip.dart';
import 'package:saferide_mobile/services/ai_advice_service.dart';
import 'package:saferide_mobile/services/weather_service.dart';

Trip _trip({
  int id = 1,
  double? destLat,
  double? destLon,
  String? destAddr,
}) {
  return Trip(
    id: id,
    passagerId: 1,
    transporteurId: 2,
    vehicleId: 3,
    destinationLatitude: destLat,
    destinationLongitude: destLon,
    destinationAddress: destAddr,
    statut: 'TERMINE',
  );
}

void main() {
  group('AiAdviceService.frequentDestinations', () {
    test('regroupe par coordonnées et garde les plus fréquentes', () {
      final trips = [
        _trip(id: 1, destLat: 4.0511, destLon: 9.7171, destAddr: 'Bonanjo'),
        _trip(id: 2, destLat: 4.0512, destLon: 9.7172, destAddr: 'Bonanjo'),
        _trip(id: 3, destLat: 4.0606, destLon: 9.7801, destAddr: 'Akwa'),
        _trip(id: 4, destLat: 4.0447, destLon: 9.6977, destAddr: 'Douala'),
        _trip(id: 5, destLat: 4.0448, destLon: 9.6978, destAddr: 'Deido'),
      ];

      final result = AiAdviceService.frequentDestinations(trips);

      expect(result, hasLength(3));
      // La destination Bonanjo (2 trajets proches) doit être n°1.
      expect(result.first.label, 'Bonanjo');
      expect(result.first.count, 2);
      // Météo absente à ce stade de l'analyse.
      expect(result.first.weather, isNull);
    });

    test('ignore les trajets sans destination', () {
      final trips = [
        _trip(id: 1, destLat: null, destLon: null),
        _trip(id: 2, destLat: 4.05, destLon: 9.71, destAddr: 'Akwa'),
      ];
      final result = AiAdviceService.frequentDestinations(trips);
      expect(result, hasLength(1));
      expect(result.first.label, 'Akwa');
    });

    test('retourne vide avec un historique vide ou sans coordonnées', () {
      expect(AiAdviceService.frequentDestinations([]), isEmpty);
    });
  });

  group('AiAdviceService.buildRecap', () {
    test('signale la pluie et l\'heure de pointe du matin', () {
      final dest = FrequentDestination(
        latitude: 4.05,
        longitude: 9.71,
        label: 'Akwa',
        count: 3,
        weather: const WeatherData(
          weatherCode: 63,
          description: 'Pluie modérée',
          icon: Icons.water_drop,
          precipitationProbability: 80,
          temperature: 25,
        ),
      );
      final recap = AiAdviceService.buildRecap(
        [dest],
        now: DateTime(2026, 9, 10, 8, 0),
      );

      expect(recap, contains('pluie'));
      expect(recap, contains('Akwa'));
      expect(recap, contains('heure de pointe'));
    });

    test('temps dégagé et circulation fluide hors heure de pointe', () {
      final dest = FrequentDestination(
        latitude: 4.05,
        longitude: 9.71,
        label: 'Akwa',
        count: 1,
        weather: const WeatherData(
          weatherCode: 0,
          description: 'Ciel dégagé',
          icon: Icons.wb_sunny,
          precipitationProbability: 0,
          temperature: 28,
        ),
      );
      final recap = AiAdviceService.buildRecap(
        [dest],
        now: DateTime(2026, 9, 10, 14, 0),
      );

      expect(recap, contains('ciel'));
      expect(recap, contains('Bonne route'));
      expect(recap, isNot(contains('heure de pointe')));
    });
  });
}