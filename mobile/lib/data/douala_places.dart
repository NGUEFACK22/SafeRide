/// Liste locale des destinations possibles à Douala (autocomplete hors-ligne).
///
/// Catégories: quartiers, marchés, hôpitaux, universités, gares, port/aéroport,
/// lieux d'intérêt. Les coordonnées sont approximatives (centre du lieu) —
/// elles sont utilisées pour tracer le circuit sur la carte et sont envoyées
/// au backend comme destination.
class DoualaPlace {
  final String name;
  final String category;
  final double latitude;
  final double longitude;

  const DoualaPlace({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
  });
}

class DoualaPlaces {
  /// Point de secours = centre de Douala (Akwa), pour initMap/fallbacks GPS
  /// quand aucune position réelle n'est disponible. L'app fonctionne à Douala :
  /// un fallback sur Yaoundé afficherait la mauvaise position/vile.
  static const double centerLatitude = 4.0428;
  static const double centerLongitude = 9.7003;

  static const List<DoualaPlace> all = [
    // ── Quartiers ───────────────────────────────────────────────
    DoualaPlace(
      name: 'Akwa',
      category: 'Quartier',
      latitude: 4.0428,
      longitude: 9.7003,
    ),
    DoualaPlace(
      name: 'Bonanjo',
      category: 'Quartier',
      latitude: 4.0383,
      longitude: 9.6896,
    ),
    DoualaPlace(
      name: 'Bonapriso',
      category: 'Quartier',
      latitude: 4.0332,
      longitude: 9.6984,
    ),
    DoualaPlace(
      name: 'Bali',
      category: 'Quartier',
      latitude: 4.0510,
      longitude: 9.6709,
    ),
    DoualaPlace(
      name: 'Bonamoussadi',
      category: 'Quartier',
      latitude: 4.0846,
      longitude: 9.7234,
    ),
    DoualaPlace(
      name: 'Makepe',
      category: 'Quartier',
      latitude: 4.0670,
      longitude: 9.7380,
    ),
    DoualaPlace(
      name: 'Yassa',
      category: 'Quartier',
      latitude: 4.0310,
      longitude: 9.7638,
    ),
    DoualaPlace(
      name: 'Logbessou',
      category: 'Quartier',
      latitude: 4.1033,
      longitude: 9.7525,
    ),
    DoualaPlace(
      name: 'Bépanda',
      category: 'Quartier',
      latitude: 4.0770,
      longitude: 9.7134,
    ),
    DoualaPlace(
      name: 'Ndokoti',
      category: 'Quartier',
      latitude: 4.0820,
      longitude: 9.7210,
    ),
    DoualaPlace(
      name: 'Deido',
      category: 'Quartier',
      latitude: 4.0708,
      longitude: 9.7099,
    ),
    DoualaPlace(
      name: 'Ange-Raphaël',
      category: 'Quartier',
      latitude: 4.0698,
      longitude: 9.7085,
    ),
    DoualaPlace(
      name: 'Bilingue',
      category: 'Quartier',
      latitude: 4.0918,
      longitude: 9.7233,
    ),
    DoualaPlace(
      name: 'Tergal',
      category: 'Quartier',
      latitude: 4.0960,
      longitude: 9.7310,
    ),
    DoualaPlace(
      name: 'Bonabéri',
      category: 'Quartier',
      latitude: 4.0592,
      longitude: 9.6632,
    ),
    DoualaPlace(
      name: 'Village',
      category: 'Quartier',
      latitude: 4.0571,
      longitude: 9.6689,
    ),
    DoualaPlace(
      name: 'Ngodi Bakoko',
      category: 'Quartier',
      latitude: 4.0640,
      longitude: 9.6760,
    ),
    DoualaPlace(
      name: 'Ndogbong',
      category: 'Quartier',
      latitude: 4.0710,
      longitude: 9.6890,
    ),
    DoualaPlace(
      name: 'Nkololoun',
      category: 'Quartier',
      latitude: 4.0900,
      longitude: 9.7330,
    ),
    DoualaPlace(
      name: 'Logpom',
      category: 'Quartier',
      latitude: 4.1000,
      longitude: 9.7350,
    ),
    DoualaPlace(
      name: 'Ndogpassi',
      category: 'Quartier',
      latitude: 4.0680,
      longitude: 9.7050,
    ),
    DoualaPlace(
      name: 'Bessengue',
      category: 'Quartier',
      latitude: 4.0435,
      longitude: 9.6990,
    ),
    DoualaPlace(
      name: 'Point du Jour',
      category: 'Quartier',
      latitude: 4.0470,
      longitude: 9.7100,
    ),
    DoualaPlace(
      name: 'Bonakouamouang',
      category: 'Quartier',
      latitude: 4.0600,
      longitude: 9.6700,
    ),
    DoualaPlace(
      name: 'Koumassi',
      category: 'Quartier',
      latitude: 4.0410,
      longitude: 9.6950,
    ),
    DoualaPlace(
      name: 'Petit Paris',
      category: 'Quartier',
      latitude: 4.0300,
      longitude: 9.6920,
    ),
    DoualaPlace(
      name: 'Manoka',
      category: 'Quartier',
      latitude: 4.1250,
      longitude: 9.6400,
    ),
    DoualaPlace(
      name: 'Nyalla',
      category: 'Quartier',
      latitude: 4.0100,
      longitude: 9.7440,
    ),

    // ── Marchés ─────────────────────────────────────────────────
    DoualaPlace(
      name: 'Marché Central',
      category: 'Marché',
      latitude: 4.0462,
      longitude: 9.6883,
    ),
    DoualaPlace(
      name: 'Marché Sandaga',
      category: 'Marché',
      latitude: 4.0455,
      longitude: 9.6859,
    ),
    DoualaPlace(
      name: 'Mboppi',
      category: 'Marché',
      latitude: 4.0575,
      longitude: 9.7040,
    ),
    DoualaPlace(
      name: 'Marché de Bonabéri (Chicoco)',
      category: 'Marché',
      latitude: 4.0595,
      longitude: 9.6615,
    ),
    DoualaPlace(
      name: 'Marché des Fleurs',
      category: 'Marché',
      latitude: 4.0488,
      longitude: 9.7030,
    ),
    DoualaPlace(
      name: 'Marché de Bépanda',
      category: 'Marché',
      latitude: 4.0770,
      longitude: 9.7120,
    ),
    DoualaPlace(
      name: 'Marché de Yassa',
      category: 'Marché',
      latitude: 4.0310,
      longitude: 9.7650,
    ),
    DoualaPlace(
      name: 'Grand Marché de Douala',
      category: 'Marché',
      latitude: 4.0470,
      longitude: 9.6900,
    ),
    DoualaPlace(
      name: 'Marché Wood',
      category: 'Marché',
      latitude: 4.0440,
      longitude: 9.7010,
    ),
    DoualaPlace(
      name: 'Marché de Deido',
      category: 'Marché',
      latitude: 4.0715,
      longitude: 9.7090,
    ),

    // ── Hôpitaux / santé ────────────────────────────────────────
    DoualaPlace(
      name: 'Hôpital Laquintinie',
      category: 'Hôpital',
      latitude: 4.0481,
      longitude: 9.6975,
    ),
    DoualaPlace(
      name: 'Hôpital Général de Douala',
      category: 'Hôpital',
      latitude: 4.0562,
      longitude: 9.7082,
    ),
    DoualaPlace(
      name: 'Hôpital de District de Bonassama',
      category: 'Hôpital',
      latitude: 4.0595,
      longitude: 9.6610,
    ),
    DoualaPlace(
      name: 'Hôpital de District de Deido',
      category: 'Hôpital',
      latitude: 4.0710,
      longitude: 9.7100,
    ),
    DoualaPlace(
      name: 'Hôpital de District de Bonapriso',
      category: 'Hôpital',
      latitude: 4.0330,
      longitude: 9.6980,
    ),
    DoualaPlace(
      name: 'Polyclinique Bonanjo',
      category: 'Hôpital',
      latitude: 4.0386,
      longitude: 9.6902,
    ),
    DoualaPlace(
      name: 'Centre Médico-Social de Bali',
      category: 'Hôpital',
      latitude: 4.0512,
      longitude: 9.6712,
    ),

    // ── Universités / grandes écoles ────────────────────────────
    DoualaPlace(
      name: 'Université de Douala',
      category: 'Université',
      latitude: 4.0465,
      longitude: 9.6995,
    ),
    DoualaPlace(
      name: 'Campus Carrefour Sotrac',
      category: 'Université',
      latitude: 4.0830,
      longitude: 9.7330,
    ),
    DoualaPlace(
      name: 'IUT de Douala',
      category: 'Université',
      latitude: 4.0605,
      longitude: 9.6970,
    ),
    DoualaPlace(
      name: 'ENSPD Campus Bonabéri',
      category: 'Université',
      latitude: 4.0590,
      longitude: 9.6638,
    ),
    DoualaPlace(
      name: 'Institut Siantou',
      category: 'École',
      latitude: 4.0430,
      longitude: 9.6935,
    ),
    DoualaPlace(
      name: 'Lycée Joss',
      category: 'École',
      latitude: 4.0460,
      longitude: 9.6960,
    ),
    DoualaPlace(
      name: 'Lycée Général Leclerc',
      category: 'École',
      latitude: 4.0390,
      longitude: 9.6880,
    ),
    DoualaPlace(
      name: 'College de la Salle',
      category: 'École',
      latitude: 4.0540,
      longitude: 9.7060,
    ),

    // ── Gares / transports ──────────────────────────────────────
    DoualaPlace(
      name: 'Gare routière de Bonabéri',
      category: 'Gare',
      latitude: 4.0590,
      longitude: 9.6618,
    ),
    DoualaPlace(
      name: 'Gare ferroviaire Bessengue',
      category: 'Gare',
      latitude: 4.0539,
      longitude: 9.7117,
    ),
    DoualaPlace(
      name: 'Gare routière de la Liberté',
      category: 'Gare',
      latitude: 4.0590,
      longitude: 9.7020,
    ),
    DoualaPlace(
      name: 'Terminus camion Bonabéri',
      category: 'Gare',
      latitude: 4.0620,
      longitude: 9.6590,
    ),

    // ── Aéroport / Port ─────────────────────────────────────────
    DoualaPlace(
      name: 'Aéroport international de Douala',
      category: 'Aéroport',
      latitude: 4.0060,
      longitude: 9.7190,
    ),
    DoualaPlace(
      name: 'Port Autonome de Douala',
      category: 'Port',
      latitude: 4.0040,
      longitude: 9.7080,
    ),
    DoualaPlace(
      name: 'Terminal à conteneurs Bonabéri',
      category: 'Port',
      latitude: 4.0000,
      longitude: 9.7060,
    ),

    // ── Lieux d'intérêt / commerce ──────────────────────────────
    DoualaPlace(
      name: 'Place de l\'Indépendance',
      category: 'Lieu d\'intérêt',
      latitude: 4.0440,
      longitude: 9.6962,
    ),
    DoualaPlace(
      name: 'Stade de la Réunification',
      category: 'Sport',
      latitude: 4.0552,
      longitude: 9.6832,
    ),
    DoualaPlace(
      name: 'Palais des Sports',
      category: 'Sport',
      latitude: 4.0558,
      longitude: 9.6838,
    ),
    DoualaPlace(
      name: 'Cathédrale Saint-Pierre-et-Paul',
      category: 'Lieu d\'intérêt',
      latitude: 4.0480,
      longitude: 9.6955,
    ),
    DoualaPlace(
      name: 'Basilique Marie-Reine-des-Apôtres',
      category: 'Lieu d\'intérêt',
      latitude: 4.0490,
      longitude: 9.7010,
    ),
    DoualaPlace(
      name: 'Mosquée centrale d\'Akwa',
      category: 'Lieu d\'intérêt',
      latitude: 4.0432,
      longitude: 9.7020,
    ),
    DoualaPlace(
      name: 'Douala Grand Mall',
      category: 'Centre commercial',
      latitude: 4.0340,
      longitude: 9.6940,
    ),
    DoualaPlace(
      name: 'Casino Douala Bonapriso',
      category: 'Centre commercial',
      latitude: 4.0335,
      longitude: 9.6965,
    ),
    DoualaPlace(
      name: 'Sawa Beach',
      category: 'Loisirs',
      latitude: 4.0500,
      longitude: 9.7900,
    ),
    DoualaPlace(
      name: 'Parc zoologique de Douala',
      category: 'Loisirs',
      latitude: 4.0485,
      longitude: 9.7040,
    ),
    DoualaPlace(
      name: 'Rond-point Deido',
      category: 'Lieu d\'intérêt',
      latitude: 4.0642,
      longitude: 9.7069,
    ),
    DoualaPlace(
      name: 'Rond-point Bonamoussadi',
      category: 'Lieu d\'intérêt',
      latitude: 4.0850,
      longitude: 9.7230,
    ),
    DoualaPlace(
      name: 'Quali Bathie',
      category: 'Loisirs',
      latitude: 4.0750,
      longitude: 9.7460,
    ),
  ];

  /// Recherche insensible à la casse/accents légers sur le nom ET la catégorie.
  static List<DoualaPlace> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final results = <DoualaPlace>[];
    for (final place in all) {
      final name = place.name.toLowerCase();
      final category = place.category.toLowerCase();
      if (name.contains(q) || category.contains(q)) {
        results.add(place);
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}
