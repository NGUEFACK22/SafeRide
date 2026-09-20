import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class ApiService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, dynamic>?> getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        // Session corrompue (ancien format) : on purge, pas de crash.
        await prefs.remove(_userKey);
        return null;
      }
      return decoded;
    } catch (_) {
      // JSON illisible : on purge la session corrompue et on repart à zéro.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userKey);
      } catch (_) {}
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (auth) 'Authorization': 'Bearer ${await getToken()}',
    };

    // Timeout anti-blocage : sur réseau faible (2G, Render free qui dort),
    // on échoue vite pour basculer en file d'attente au lieu du spinner infini.
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode, data);
    }

    return data;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (auth) 'Authorization': 'Bearer ${await getToken()}',
    };

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode, data);
    }

    return data;
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body,
      {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (auth) 'Authorization': 'Bearer ${await getToken()}',
    };

    final response = await http
        .put(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode);
    }

    return data;
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (auth) 'Authorization': 'Bearer ${await getToken()}',
    };

    final response = await http
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode, data);
    }

    return data;
  }

  Future<Map<String, dynamic>> fetchNotifications() async {
    return get('/notifications');
  }

  Future<int> fetchUnreadCount() async {
    final data = await get('/notifications/unread-count');
    return (data['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(int id) async {
    await post('/notifications/$id/read', {});
  }

  Future<void> markAllNotificationsRead() async {
    await post('/notifications/read-all', {});
  }

  Future<Map<String, dynamic>> postMultipart(
    String path,
    Map<String, String> fields, {
    File? file,
    String fileField = 'fichier',
    Map<String, File>? files,
    bool auth = true,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri);

    if (auth) {
      final token = await getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }
    request.headers['Accept'] = 'application/json';
    request.fields.addAll(fields);

    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath(fileField, file.path));
    }
    if (files != null) {
      for (final entry in files.entries) {
        request.files.add(await http.MultipartFile.fromPath(entry.key, entry.value.path));
      }
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode, data);
    }

    return data;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      // Le serveur a renvoyé une liste ou un scalaire : on l'enveloppe.
      return {'data': decoded};
    } catch (_) {
      // Réponse non-JSON (page HTML d'erreur Render/Cloudflare, proxy,
      // passerelle) : jamais de crash, l'appelant reçoit une ApiException.
      return {'_raw': response.body};
    }
  }

  String _messageFrom(Map<String, dynamic> data, int statusCode) {
    if (data.containsKey('message')) {
      final message = data['message'];
      if (message is String) return message;
      return jsonEncode(message);
    }
    if (data.containsKey('errors')) {
      return jsonEncode(data['errors']);
    }
    return 'Erreur serveur ($statusCode)';
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? data;

  ApiException(this.message, this.statusCode, [this.data]);

  @override
  String toString() => message;
}