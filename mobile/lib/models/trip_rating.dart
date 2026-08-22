class TripRating {
  final int id;
  final int tripId;
  final int raterId;
  final int ratedId;
  final int rating;
  final String? comment;
  final String? createdAt;
  final Map<String, dynamic>? rater;
  final Map<String, dynamic>? rated;
  final Map<String, dynamic>? trip;

  TripRating({
    required this.id,
    required this.tripId,
    required this.raterId,
    required this.ratedId,
    required this.rating,
    this.comment,
    this.createdAt,
    this.rater,
    this.rated,
    this.trip,
  });

  factory TripRating.fromJson(Map<String, dynamic> json) {
    return TripRating(
      id: json['id'],
      tripId: json['trip_id'],
      raterId: json['rater_id'],
      ratedId: json['rated_id'],
      rating: json['rating'] as int,
      comment: json['comment'],
      createdAt: json['created_at'],
      rater: json['rater'] as Map<String, dynamic>?,
      rated: json['rated'] as Map<String, dynamic>?,
      trip: json['trip'] as Map<String, dynamic>?,
    );
  }
}

class RatingStats {
  final int count;
  final double average;
  final Map<String, int> distribution;

  RatingStats({required this.count, required this.average, required this.distribution});

  factory RatingStats.fromJson(Map<String, dynamic> json) {
    final dist = <String, int>{};
    final raw = json['distribution'] as Map<String, dynamic>? ?? {};
    for (final e in raw.entries) {
      dist[e.key] = (e.value as num).toInt();
    }
    return RatingStats(
      count: (json['count'] as num).toInt(),
      average: (json['average'] as num).toDouble(),
      distribution: dist,
    );
  }
}
