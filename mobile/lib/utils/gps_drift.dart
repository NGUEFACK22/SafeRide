/// Filtre anti-dérive GPS (fonction pure, testée).
///
/// À l'arrêt, le capteur erre de ±15 m et chaque tick dessinait un faux
/// déplacement (fil bleu en spaghetti + marqueur qui bouge sur place).
/// Règle : en dessous de 15 m ET sous 11 km/h, le point est du bruit —
/// l'affichage reste figé. Premier point toujours accepté.
class GpsDrift {
  /// Déplacement minimal (mètres) pour parler de vrai mouvement.
  static const double thresholdM = 15;

  /// Allure (km/h) qui prouve le mouvement même sur petit déplacement.
  static const double movingSpeedKmh = 11;

  /// true = vrai déplacement (marqueur + fil bleu mis à jour),
  /// false = bruit à l'arrêt (affichage figé, pas de setState).
  static bool acceptPoint({
    required bool hasReference,
    required double movedMeters,
    required double speedKmh,
  }) {
    if (!hasReference) return true;
    if (movedMeters < thresholdM && speedKmh < movingSpeedKmh) {
      return false;
    }
    return true;
  }
}
