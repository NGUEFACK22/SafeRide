import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferide_mobile/utils/gps_drift.dart';

/// Preuve : immobile = point bleu figé ; en mouvement = tracé mis à jour.
void main() {
  group('GpsDrift.acceptPoint', () {
    test('premier point toujours accepté (pas de référence)', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: false, movedMeters: 0, speedKmh: 0),
        isTrue,
      );
    });

    test('immobile : jitter 3 m, vitesse nulle → rejeté (figé)', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 3, speedKmh: 0),
        isFalse,
      );
    });

    test('immobile : dérive 12 m à 2 km/h → rejeté (figé)', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 12, speedKmh: 2),
        isFalse,
      );
    });

    test('limite : 14,9 m → rejeté, 15,1 m → accepté', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 14.9, speedKmh: 0),
        isFalse,
      );
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 15.1, speedKmh: 0),
        isTrue,
      );
    });

    test('vrai déplacement 50 m → accepté', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 50, speedKmh: 0),
        isTrue,
      );
    });

    test('petit déplacement mais allure avérée (15 km/h) → accepté', () {
      expect(
        GpsDrift.acceptPoint(
            hasReference: true, movedMeters: 8, speedKmh: 15),
        isTrue,
      );
    });

    test('Distance() : 0,0001° de latitude ≈ 11,1 m (seuil cohérent)', () {
      const d = Distance();
      final m = d(const LatLng(4.05, 9.76), const LatLng(4.0501, 9.76));
      expect(m, greaterThan(10));
      expect(m, lessThan(12));
      // Donc un pas GPS typique à l'arrêt (< 15 m) est bien filtré :
      expect(
        GpsDrift.acceptPoint(hasReference: true, movedMeters: m, speedKmh: 1),
        isFalse,
      );
    });
  });
}
