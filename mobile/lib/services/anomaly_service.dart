import '../services/api_service.dart';

class AnomalyService {
  final ApiService _api = ApiService();

  /// Récupère les vérifications d'anomalies en attente pour l'utilisateur.
  Future<List<Map<String, dynamic>>> getPending() async {
    try {
      final data = await _api.get('/anomaly-verifications');
      final list = data['verifications'] as List<dynamic>? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Répond à une vérification d'anomalie.
  /// [response] : 'normal' (course continue) ou 'abnormal' (SOS déclenché).
  Future<Map<String, dynamic>> respond(int id, String response) async {
    return await _api.post('/anomaly-verifications/$id/respond', {
      'response': response,
    });
  }
}
