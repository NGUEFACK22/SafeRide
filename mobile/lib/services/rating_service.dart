import '../models/trip_rating.dart';
import 'api_service.dart';

class RatingService {
  final ApiService _api = ApiService();

  Future<TripRating> rateTrip(int tripId, int rating, {String? comment}) async {
    final data = await _api.post('/trips/$tripId/rate', {
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
    return TripRating.fromJson(data['rating'] as Map<String, dynamic>);
  }

  Future<TripRating> updateRating(int tripId, int rating, {String? comment}) async {
    final data = await _api.put('/trips/$tripId/rate', {
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
    return TripRating.fromJson(data['rating'] as Map<String, dynamic>);
  }

  Future<List<TripRating>> getTripRatings(int tripId) async {
    final data = await _api.get('/trips/$tripId/ratings');
    final list = data['ratings'] as List<dynamic>? ?? [];
    return list.map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getTripRatingsWithMeta(int tripId) async {
    return _api.get('/trips/$tripId/ratings');
  }

  Future<List<TripRating>> getReceived() async {
    final data = await _api.get('/ratings/received');
    final items = data['ratings']['data'] as List<dynamic>? ?? data['ratings'] as List<dynamic>? ?? [];
    // paginated
    if (data['ratings'] is Map && data['ratings']['data'] is List) {
      return (data['ratings']['data'] as List).map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
    }
    return items.map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RatingStats> getReceivedStats() async {
    final data = await _api.get('/ratings/received');
    return RatingStats.fromJson(data['stats'] as Map<String, dynamic>);
  }

  Future<List<TripRating>> getGiven() async {
    final data = await _api.get('/ratings/given');
    if (data['ratings'] is Map && data['ratings']['data'] is List) {
      return (data['ratings']['data'] as List).map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
    }
    final list = data['ratings'] as List<dynamic>? ?? [];
    return list.map((e) => TripRating.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getUserStats(int userId) async {
    return _api.get('/users/$userId/ratings/stats');
  }
}
