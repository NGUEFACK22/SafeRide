import 'dart:convert';

import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const String _userAgent = 'SafeRideApp/1.0 (contact@saferide.app)';

  Future<({double latitude, double longitude})?> geocode(String address) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': address,
      'format': 'json',
      'limit': '1',
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) return null;
    final list = jsonDecode(response.body) as List<dynamic>;
    if (list.isEmpty) return null;

    final first = list.first as Map<String, dynamic>;
    return (
      latitude: double.parse(first['lat'] as String),
      longitude: double.parse(first['lon'] as String),
    );
  }
}