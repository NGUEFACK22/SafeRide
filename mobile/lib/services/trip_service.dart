import '../models/trip.dart';
import 'api_service.dart';
import 'offline_service.dart';

class TripService {
  final ApiService _api = ApiService();

  Future<Trip> startTrip(String token, double latitude, double longitude) async {
    final data = await _api.post('/trips/start', {
      'token': token,
      'latitude': latitude,
      'longitude': longitude,
    });
    return Trip.fromJson(data['trip']);
  }

  Future<Trip?> currentTrip() async {
    final data = await _api.get('/trips/current');
    final trip = data['trip'];
    if (trip == null) return null;
    return Trip.fromJson(trip);
  }

  Future<Trip> setDestination(
    int tripId,
    String address,
    double latitude,
    double longitude,
  ) async {
    final data = await _api.post('/trips/$tripId/destination', {
      'destination_address': address,
      'latitude': latitude,
      'longitude': longitude,
    });
    return Trip.fromJson(data['trip']);
  }

  Future<Trip> confirmEmbarquement(int tripId) async {
    final data = await _api.post('/trips/$tripId/confirm-embarquement', {});
    return Trip.fromJson(data['trip']);
  }

  Future<Trip> confirmDestination(int tripId, bool confirmed) async {
    final data = await _api.post('/trips/$tripId/confirm-destination', {
      'confirmed': confirmed,
    });
    return Trip.fromJson(data['trip']);
  }

  Future<void> sendLocation(
    int tripId,
    double latitude,
    double longitude,
    double? speed,
  ) async {
    // Stockage local + file d'attente de synchronisation (hors-ligne first)
    await OfflineService.instance.sendLocation(tripId, latitude, longitude, speed);
  }

  Future<Trip> endTrip(int tripId) async {
    final data = await _api.post('/trips/$tripId/end', {});
    return Trip.fromJson(data['trip']);
  }

  Future<List<Trip>> history() async {
    final data = await _api.get('/trips/history');
    final items = data['trips']['data'] as List<dynamic>? ?? [];
    return items.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
  }
}