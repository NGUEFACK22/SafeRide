import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<User> login(String email, String password, String? telephone) async {
    final body = {
      'email': email,
      'password': password,
      'telephone': ?telephone,
    };

    final data = await _api.post('/auth/login', body, auth: false);

    await _api.saveToken(data['token']);
    await _api.saveUser(data['user']);

    return User.fromJson(data['user']);
  }

  Future<User> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  }) async {
    final body = {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': telephone,
      'password': password,
    };

    final data = await _api.post('/auth/register', body, auth: false);

    await _api.saveToken(data['token']);
    await _api.saveUser(data['user']);

    return User.fromJson(data['user']);
  }

  Future<User?> currentUser() async {
    final raw = await _api.getUser();
    if (raw == null) return null;
    return User.fromJson(raw);
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout', {});
    } catch (_) {
      // ignorer les erreurs réseau, la session locale est quand même supprimée
    }
    await _api.clearSession();
  }
}