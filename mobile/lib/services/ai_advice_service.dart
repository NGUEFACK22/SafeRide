import '../models/trip.dart';
import 'trip_service.dart';
import 'weather_service.dart';

/// Destination récurrente détectée dans l'historique de l'utilisateur.
class FrequentDestination {
  final double latitude;
  final double longitude;
  final String label;
  final int count;
  final WeatherData? weather;

  const FrequentDestination({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.count,
    this.weather,
  });
}

/// Résultat du conseil récapitulatif : destinations habituelles + météo + conseils.
class TravelAdvice {
  final List<FrequentDestination> destinations;
  final String recap;

  const TravelAdvice({required this.destinations, required this.recap});
}

/// Analyse l'historique des déplacements (côté mobile) :
/// 1. détecte les destinations les plus fréquentes,
/// 2. récupère la météo Open-Meteo pour chacune,
/// 3. génère un conseil récapitulatif pour éviter les bouchons (heuristique).
class AiAdviceService {
  final TripService _trips = TripService();
  final WeatherService _weather = WeatherService.instance;

  /// Nombre maximum de pages d'historique analysées (15 trajets / page).
  static const int maxPages = 4;

  /// Nombre de destinations retenues.
  static const int topDestinations = 3;

  /// Analyse complète.
  Future<TravelAdvice?> analyze() async {
    final trips = await _collectHistory();
    if (trips.isEmpty) return null;

    final destinations = frequentDestinations(trips);
    if (destinations.isEmpty) return null;

    // Météo en parallèle pour les destinations retenues.
    final weatherList = await Future.wait(
      destinations.map((d) => _weather.getCurrentWeather(d.latitude, d.longitude)),
    );
    for (var i = 0; i < destinations.length; i++) {
      destinations[i] = FrequentDestination(
        latitude: destinations[i].latitude,
        longitude: destinations[i].longitude,
        label: destinations[i].label,
        count: destinations[i].count,
        weather: weatherList[i],
      );
    }

    return TravelAdvice(
      destinations: destinations,
      recap: buildRecap(destinations),
    );
  }

  /// Charge plusieurs pages d'historique (ne s'arrête pas si une page est vide).
  Future<List<Trip>> _collectHistory() async {
    final all = <Trip>[];
    for (var page = 1; page <= maxPages; page++) {
      try {
        final trips = await _trips.history(page: page);
        all.addAll(trips);
        if (trips.length < 15) break;
      } catch (_) {
        break;
      }
    }
    return all;
  }

  /// Agrège par coordonnées (≈ 100 m) et garde les destinations les plus fréquentes.
  static List<FrequentDestination> frequentDestinations(List<Trip> trips) {
    final buckets = <String, _DestinationBucket>{};
    for (final trip in trips) {
      final lat = trip.destinationLatitude;
      final lon = trip.destinationLongitude;
      if (lat == null || lon == null) continue;
      final key = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
      final bucket = buckets.putIfAbsent(
        key,
        () => _DestinationBucket(lat: lat, lon: lon),
      );
      bucket.count++;
      final addr = trip.destinationAddress;
      if (addr != null && addr.trim().isNotEmpty) {
        bucket.addresses[addr.trim()] = (bucket.addresses[addr.trim()] ?? 0) + 1;
      }
    }

    final list = buckets.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return list
        .take(topDestinations)
        .map((b) => FrequentDestination(
              latitude: b.lat,
              longitude: b.lon,
              label: b.label,
              count: b.count,
            ))
        .toList();
  }

  /// Génère le conseil récapitulatif anti-bouchons (heuristique locale).
  static String buildRecap(List<FrequentDestination> destinations,
      {DateTime? now}) {
    now = now ?? DateTime.now();
    final hour = now.hour;
    final isRushMorning = hour >= 7 && hour < 9;
    final isRushEvening = hour >= 17 && hour < 19;
    final isRush = isRushMorning || isRushEvening;

    final rainy = destinations.where((d) {
      final w = d.weather;
      if (w == null) return false;
      final prob = w.precipitationProbability ?? 0;
      return prob >= 50 ||
          w.description.contains('Pluie') ||
          w.description.contains('Averses') ||
          w.description.contains('Orage') ||
          w.description.contains('Bruine');
    }).toList();

    final buffer = StringBuffer('Vous vous déplacez le plus souvent vers ')
      ..write(
        destinations
            .map((d) => '${d.label} (${d.count} fois)')
            .join(', '),
      )
      ..write('. ');

    if (rainy.isNotEmpty) {
      buffer.write(
        'De la pluie est prévue à ${rainy.map((d) => d.label).join(', ')} : '
        'sur chaussée mouillée les embouteillages sont plus denses, '
        'prévoyez de partir un peu plus tôt.',
      );
    } else {
      buffer.write(
        'Le ciel est dégagé sur vos trajets habituels, la chaussée est sèche.',
      );
    }

    if (isRush) {
      buffer.write(
        isRushMorning
            ? " Vous êtes en pleine heure de pointe (7 h – 9 h) : décalez votre départ avant 7 h ou après 9 h pour éviter les bouchons."
            : " Vous êtes en pleine heure de pointe (17 h – 19 h) : si possible, partez plus tôt ou attendez 19 h 30 pour éviter les bouchons.",
      );
    } else if (rainy.isNotEmpty) {
      buffer.write(' La circulation est globalement fluide à cette heure.');
    }

    buffer.write(' Bonne route !');
    return buffer.toString();
  }
}

class _DestinationBucket {
  final double lat;
  final double lon;
  int count = 0;
  final Map<String, int> addresses = {};

  _DestinationBucket({required this.lat, required this.lon});

  String get label {
    if (addresses.isEmpty) return 'Coordonnées (${lat.toStringAsFixed(3)}, ${lon.toStringAsFixed(3)})';
    final best = addresses.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.key;
  }
}