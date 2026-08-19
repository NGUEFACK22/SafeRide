import 'api_service.dart';

class AiService {
  final ApiService _api = ApiService();

  /// Résumé / statistiques adaptés au rôle de l'utilisateur connecté.
  Future<Map<String, dynamic>> summary({bool refresh = false}) async {
    final suffix = refresh ? '?refresh=1' : '';
    return await _api.get('/ai/summary$suffix');
  }

  /// Résumé hebdomadaire IA (semaine en cours, généré le dimanche).
  Future<Map<String, dynamic>> weekly({bool refresh = false}) async {
    final suffix = refresh ? '?refresh=1' : '';
    return await _api.get('/ai/weekly$suffix');
  }

  /// Résumé d'un trajet donné (propriétaire ou transporteur).
  Future<Map<String, dynamic>> tripSummary(int tripId) async {
    return await _api.get('/ai/trips/$tripId');
  }

  /// Anomalies détectées (gestionnaire / admin).
  Future<Map<String, dynamic>> anomalies() async {
    return await _api.get('/ai/anomalies');
  }
}
