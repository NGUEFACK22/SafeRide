class Trip {
  final int id;
  final int passagerId;
  final int transporteurId;
  final int vehicleId;
  final double? startLatitude;
  final double? startLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String? destinationAddress;
  final String? startedAt;
  final String? endedAt;
  final double? distanceKm;
  final int? durationSeconds;
  final double? deviationKm;
  final String statut;
  final String? endMethod;
  final String? finDemandeePar;
  final String? finDemandeeAt;
  final String? plannedRoutePolyline;
  final String? actualRoutePolyline;
  final String? transporteurNom;
  final String? transporteurPrenom;
  final double? transporteurAvgRating;
  final int? transporteurRatingsCount;
  final Map<String, dynamic>? myRating;
  final double? ratingsAvg;
  final int? ratingsCount;
  final Map<String, dynamic>? passager;
  final Map<String, dynamic>? vehicle;

  Trip({
    required this.id,
    required this.passagerId,
    required this.transporteurId,
    required this.vehicleId,
    this.startLatitude,
    this.startLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.destinationAddress,
    this.startedAt,
    this.endedAt,
    this.distanceKm,
    this.durationSeconds,
    this.deviationKm,
    required this.statut,
    this.endMethod,
    this.finDemandeePar,
    this.finDemandeeAt,
    this.plannedRoutePolyline,
    this.actualRoutePolyline,
    this.transporteurNom,
    this.transporteurPrenom,
    this.transporteurAvgRating,
    this.transporteurRatingsCount,
    this.myRating,
    this.ratingsAvg,
    this.ratingsCount,
    this.passager,
    this.vehicle,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    final transporteur = json['transporteur'] is Map<String, dynamic>
        ? json['transporteur'] as Map<String, dynamic>
        : null;
    return Trip(
      id: _toInt(json['id']) ?? 0,
      passagerId: _toInt(json['passager_id']) ?? 0,
      transporteurId: _toInt(json['transporteur_id']) ?? 0,
      vehicleId: _toInt(json['vehicle_id']) ?? 0,
      startLatitude: _toDouble(json['start_latitude']),
      startLongitude: _toDouble(json['start_longitude']),
      destinationLatitude: _toDouble(json['destination_latitude']),
      destinationLongitude: _toDouble(json['destination_longitude']),
      destinationAddress: json['destination_address']?.toString(),
      startedAt: json['started_at']?.toString(),
      endedAt: json['ended_at']?.toString(),
      distanceKm: _toDouble(json['distance_km']),
      durationSeconds: _toInt(json['duration_seconds'], fallback: null),
      deviationKm: _toDouble(json['deviation_km']),
      statut: json['statut']?.toString() ?? '',
      endMethod: json['end_method']?.toString(),
      finDemandeePar: json['fin_demandee_par']?.toString(),
      finDemandeeAt: json['fin_demandee_at']?.toString(),
      plannedRoutePolyline: json['planned_route_polyline']?.toString(),
      actualRoutePolyline: json['actual_route_polyline']?.toString(),
      transporteurNom: transporteur?['nom']?.toString(),
      transporteurPrenom: transporteur?['prenom']?.toString(),
      transporteurAvgRating: _toDouble(transporteur?['average_rating']),
      transporteurRatingsCount:
          _toInt(transporteur?['ratings_count'], fallback: null),
      myRating: json['my_rating'] is Map<String, dynamic>
          ? json['my_rating'] as Map<String, dynamic>
          : null,
      ratingsAvg: _toDouble(json['ratings_avg']),
      ratingsCount: _toInt(json['ratings_count'], fallback: null),
      passager: json['passager'] is Map<String, dynamic>
          ? json['passager'] as Map<String, dynamic>
          : null,
      vehicle: json['vehicle'] is Map<String, dynamic>
          ? json['vehicle'] as Map<String, dynamic>
          : null,
    );
  }

  bool get isActive =>
      statut == 'EN_COURS' || statut == 'FIN_EN_ATTENTE';
  bool get hasDestination => destinationLatitude != null;

  String get transporteurFullName {
    if (transporteurNom == null && transporteurPrenom == null) return '';
    return '${transporteurPrenom ?? ''} ${transporteurNom ?? ''}'.trim();
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  /// Entier tolérant : accepte int, double et String numérique
  /// (ex. COUNT()/AVG() MySQL renvoyés en String). Retourne [fallback]
  /// si la valeur est absente ou illisible — jamais de throw.
  static int? _toInt(dynamic value, {int? fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}