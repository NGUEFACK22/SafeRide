import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Calcul l'itinéraire entre deux points via OSRM (même serveur que le backend).
/// Repli sur une ligne droite si OSRM est indisponible (hors-ligne, timeout).
class OsrmService {
  static const String _base = 'https://router.project-osrm.org';
  static const _userAgent = 'SafeRideApp/1.0 (contact@saferide.app)';

  /// Route complète (overview full) entre [from] et [to], décodée en polyline.
  /// Demande les ALTERNATIVES au moteur et retient la plus COURTE en distance
  /// (le profil driving d'OSRM optimise par défaut le temps ; l'utilisateur
  /// veut le chemin le plus court pour arriver). Repli : 1er itinéraire,
  /// puis ligne droite si OSRM indisponible (hors-ligne, timeout).
  static Future<List<LatLng>> route(LatLng from, LatLng to) async {
    try {
      final uri =
          Uri.parse(
            '$_base/route/v1/driving/${from.longitude},${from.latitude};'
            '${to.longitude},${to.latitude}',
          ).replace(
            queryParameters: {
              'overview': 'full',
              'geometries': 'polyline',
              'alternatives': 'true',
            },
          );

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return _fallback(from, to);

      Object? json;
      try {
        json = jsonDecode(response.body);
      } catch (_) {
        return _fallback(from, to);
      }
      final data = json as Map<String, dynamic>?;
      final routes = data?['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return _fallback(from, to);

      // Itinéraire le plus court en distance parmi les alternatives.
      double bestDist = double.infinity;
      String? bestGeometry;
      for (final r in routes) {
        if (r is! Map<String, dynamic>) continue;
        final geometry = r['geometry'] as String?;
        if (geometry == null || geometry.isEmpty) continue;
        final dist = (r['distance'] as num?)?.toDouble() ?? double.infinity;
        if (dist < bestDist) {
          bestDist = dist;
          bestGeometry = geometry;
        }
      }
      // Sans distance exploitable : 1er itinéraire (comportement historique).
      bestGeometry ??= (routes.first as Map<String, dynamic>?)?['geometry'] as String?;
      if (bestGeometry == null || bestGeometry.isEmpty) {
        return _fallback(from, to);
      }

      final points = decodePolyline(bestGeometry);
      return points.length >= 2 ? points : _fallback(from, to);
    } catch (_) {
      return _fallback(from, to);
    }
  }

  static List<LatLng> _fallback(LatLng from, LatLng to) => [from, to];

  /// Décode une polyline Google encodée en liste de points LatLng.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var b = 0;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}
