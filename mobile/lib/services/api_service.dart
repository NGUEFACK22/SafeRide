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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
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

    final response = await http.post(uri, headers: headers, body: jsonEncode(body));
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode);
    }

    return data;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (auth) 'Authorization': 'Bearer ${await getToken()}',
    };

    final response = await http.get(uri, headers: headers);
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode);
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

    final response = await http.put(uri, headers: headers, body: jsonEncode(body));
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

    final response = await http.delete(uri, headers: headers);
    final data = _decode(response);

    if (response.statusCode >= 400) {
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode);
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
      throw ApiException(_messageFrom(data, response.statusCode), response.statusCode);
    }

    return data;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
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

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}