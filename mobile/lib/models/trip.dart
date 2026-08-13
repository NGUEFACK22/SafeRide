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
  final String? plannedRoutePolyline;
  final String? actualRoutePolyline;
  final String? transporteurNom;
  final String? transporteurPrenom;

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
    this.plannedRoutePolyline,
    this.actualRoutePolyline,
    this.transporteurNom,
    this.transporteurPrenom,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    final transporteur = json['transporteur'] as Map<String, dynamic>?;
    return Trip(
      id: json['id'],
      passagerId: json['passager_id'],
      transporteurId: json['transporteur_id'],
      vehicleId: json['vehicle_id'],
      startLatitude: _toDouble(json['start_latitude']),
      startLongitude: _toDouble(json['start_longitude']),
      destinationLatitude: _toDouble(json['destination_latitude']),
      destinationLongitude: _toDouble(json['destination_longitude']),
      destinationAddress: json['destination_address'],
      startedAt: json['started_at'],
      endedAt: json['ended_at'],
      distanceKm: _toDouble(json['distance_km']),
      durationSeconds: json['duration_seconds'],
      deviationKm: _toDouble(json['deviation_km']),
      statut: json['statut'],
      endMethod: json['end_method'],
      plannedRoutePolyline: json['planned_route_polyline'],
      actualRoutePolyline: json['actual_route_polyline'],
      transporteurNom: transporteur?['nom'],
      transporteurPrenom: transporteur?['prenom'],
    );
  }

  bool get isActive => statut == 'EN_COURS';
  bool get hasDestination => destinationLatitude != null;

  String get transporteurFullName {
    if (transporteurNom == null && transporteurPrenom == null) return '';
    return '${transporteurPrenom ?? ''} ${transporteurNom ?? ''}'.trim();
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }
}