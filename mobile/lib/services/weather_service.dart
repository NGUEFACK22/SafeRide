import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Service météo utilisant l'API Open-Meteo (100% gratuit, pas de clé API).
///
/// Flux : GPS SafeRide (lat/lon) → Open-Meteo → conditions météo
class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  /// Récupère les conditions météo actuelles pour une position GPS.
  Future<WeatherData?> getCurrentWeather(double latitude, double longitude) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,'
        'precipitation,precipitation_probability,weather_code,'
        'wind_speed_10m,wind_direction_10m,cloud_cover'
        '&timezone=auto',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;

      if (current == null) return null;

      final weatherCode = current['weather_code'] as int? ?? 0;

      return WeatherData(
        temperature: (current['temperature_2m'] as num?)?.toDouble(),
        feelsLike: (current['apparent_temperature'] as num?)?.toDouble(),
        humidity: (current['relative_humidity_2m'] as num?)?.toInt(),
        precipitation: (current['precipitation'] as num?)?.toDouble(),
        precipitationProbability: (current['precipitation_probability'] as num?)?.toInt(),
        windSpeed: (current['wind_speed_10m'] as num?)?.toDouble(),
        windDirection: (current['wind_direction_10m'] as num?)?.toDouble(),
        cloudCover: (current['cloud_cover'] as num?)?.toInt(),
        weatherCode: weatherCode,
        description: _weatherDescription(weatherCode),
        icon: _weatherIcon(weatherCode),
      );
    } catch (_) {
      return null;
    }
  }

  /// Description textuelle du code météo WMO.
  static String _weatherDescription(int code) {
    switch (code) {
      case 0: return 'Ciel dégagé';
      case 1: return 'Principalement dégagé';
      case 2: return 'Partiellement nuageux';
      case 3: return 'Couvert';
      case 45: case 48: return 'Brouillard';
      case 51: case 53: case 55: return 'Bruine';
      case 56: case 57: return 'Bruine verglaçante';
      case 61: return 'Pluie légère';
      case 63: return 'Pluie modérée';
      case 65: return 'Pluie forte';
      case 66: case 67: return 'Pluie verglaçante';
      case 71: return 'Neige légère';
      case 73: return 'Neige modérée';
      case 75: return 'Neige forte';
      case 77: return 'Grésil';
      case 80: return 'Averses légères';
      case 81: return 'Averses modérées';
      case 82: return 'Averses violentes';
      case 85: case 86: return 'Averses de neige';
      case 95: return 'Orage';
      case 96: case 99: return 'Orage avec grêle';
      default: return 'Inconnu';
    }
  }

  /// Icône Material correspondant au code météo WMO.
  static IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 2) return Icons.wb_cloudy;
    if (code == 3) return Icons.cloud;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 57) return Icons.grain;
    if (code >= 61 && code <= 67) return Icons.water_drop;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 86) return Icons.water_drop;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.cloud_queue;
  }
}

/// Données météo actuelles.
class WeatherData {
  final double? temperature;
  final double? feelsLike;
  final int? humidity;
  final double? precipitation;
  final int? precipitationProbability;
  final double? windSpeed;
  final double? windDirection;
  final int? cloudCover;
  final int weatherCode;
  final String description;
  final IconData icon;

  const WeatherData({
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.precipitation,
    this.precipitationProbability,
    this.windSpeed,
    this.windDirection,
    this.cloudCover,
    required this.weatherCode,
    required this.description,
    required this.icon,
  });

  /// Température arrondie.
  String get tempDisplay => temperature != null ? '${temperature!.round()}°C' : '—';

  /// Vent arrondi.
  String get windDisplay => windSpeed != null ? '${windSpeed!.round()} km/h' : '—';

  /// Direction du vent en texte.
  String get windDirectionText {
    if (windDirection == null) return '';
    final dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return dirs[((windDirection! + 22.5) / 45).floor() % 8];
  }
}
