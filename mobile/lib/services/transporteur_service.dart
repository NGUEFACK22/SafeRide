import 'api_service.dart';

class TransporteurService {
  final _api = ApiService();

  Future<Map<String, dynamic>> dashboard() async {
    return _api.get('/transporteur/dashboard');
  }
}
