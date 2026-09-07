import 'package:shared_preferences/shared_preferences.dart';

/// Compteur persistant d'alertes SOS déclenchées par l'utilisateur.
/// Stocké localement (SharedPreferences) : survit au redémarrage de l'app.
class AlertCounterService {
  AlertCounterService._();

  static const _key = 'sos_alert_count';

  /// Nombre total d'alertes SOS déjà déclenchées.
  static Future<int> getCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  /// Incrémente le compteur et renvoie la nouvelle valeur.
  static Future<int> increment() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_key) ?? 0) + 1;
    await prefs.setInt(_key, next);
    return next;
  }

  /// Remet le compteur à zéro (utile en développement / tests).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}