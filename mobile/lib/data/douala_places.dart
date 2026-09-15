/// Liste locale des destinations possibles (autocomplete hors-ligne).
///
/// Villes couvertes : DOUALA (74+) et YAOUNDÉ (40+) — quartiers, marchés,
/// hôpitaux, universités, gares, port/aéroport, lieux d'intérêt. Les
/// coordonnées sont approximatives (centre du lieu) — elles sont utilisées
/// pour tracer le circuit sur la carte et sont envoyées au backend comme
/// destination.
class DoualaPlace {
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String ville;

  const DoualaPlace({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.ville = 'Douala',
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

    // ── YAOUNDÉ — Quartiers ─────────────────────────────────────
    DoualaPlace(name: 'Centre-ville (Obidjam)', category: 'Quartier', latitude: 3.8666, longitude: 11.5173, ville: 'Yaoundé'),
    DoualaPlace(name: 'Bastos', category: 'Quartier', latitude: 3.8803, longitude: 11.5270, ville: 'Yaoundé'),
    DoualaPlace(name: 'Nsam', category: 'Quartier', latitude: 3.8889, longitude: 11.5175, ville: 'Yaoundé'),
    DoualaPlace(name: 'Mvan', category: 'Quartier', latitude: 3.9008, longitude: 11.5236, ville: 'Yaoundé'),
    DoualaPlace(name: 'Etoug-Ebe', category: 'Quartier', latitude: 3.9206, longitude: 11.5253, ville: 'Yaoundé'),
    DoualaPlace(name: 'Melen', category: 'Quartier', latitude: 3.9167, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Odza', category: 'Quartier', latitude: 3.9067, longitude: 11.5397, ville: 'Yaoundé'),
    DoualaPlace(name: 'Biya', category: 'Quartier', latitude: 3.9075, longitude: 11.5322, ville: 'Yaoundé'),
    DoualaPlace(name: 'Essos', category: 'Quartier', latitude: 3.9167, longitude: 11.5667, ville: 'Yaoundé'),
    DoualaPlace(name: 'Nkonbessou', category: 'Quartier', latitude: 3.9333, longitude: 11.5667, ville: 'Yaoundé'),
    DoualaPlace(name: 'Mokolo', category: 'Quartier', latitude: 3.9367, longitude: 11.5433, ville: 'Yaoundé'),
    DoualaPlace(name: 'Ngousso', category: 'Quartier', latitude: 3.9667, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Nkolbisson', category: 'Quartier', latitude: 3.9000, longitude: 11.4833, ville: 'Yaoundé'),
    DoualaPlace(name: 'Obobaba', category: 'Quartier', latitude: 3.8500, longitude: 11.4833, ville: 'Yaoundé'),
    DoualaPlace(name: 'Silia', category: 'Quartier', latitude: 3.8517, longitude: 11.4972, ville: 'Yaoundé'),
    DoualaPlace(name: 'Mendong', category: 'Quartier', latitude: 3.8575, longitude: 11.5028, ville: 'Yaoundé'),
    DoualaPlace(name: 'Emana', category: 'Quartier', latitude: 3.8133, longitude: 11.5000, ville: 'Yaoundé'),
    DoualaPlace(name: 'Nyom', category: 'Quartier', latitude: 3.7167, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Akom II', category: 'Quartier', latitude: 3.8333, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Nkolondom', category: 'Quartier', latitude: 3.8833, longitude: 11.4917, ville: 'Yaoundé'),
    // ── YAOUNDÉ — Marchés ───────────────────────────────────────
    DoualaPlace(name: 'Marché du Centre (Versach)', category: 'Marché', latitude: 3.8722, longitude: 11.5169, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Mokolo', category: 'Marché', latitude: 3.9000, longitude: 11.5433, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Mvan', category: 'Marché', latitude: 3.8992, longitude: 11.5244, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Nsam', category: 'Marché', latitude: 3.8875, longitude: 11.5194, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Etoug-Ebe', category: 'Marché', latitude: 3.9233, longitude: 11.5247, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Biyem-Assi', category: 'Marché', latitude: 3.8850, longitude: 11.5400, ville: 'Yaoundé'),
    DoualaPlace(name: 'Marché Nkolbisson', category: 'Marché', latitude: 3.9011, longitude: 11.4850, ville: 'Yaoundé'),
    // ── YAOUNDÉ — Hôpitaux / Santé ──────────────────────────────
    DoualaPlace(name: 'Hôpital Central', category: 'Hôpital', latitude: 3.8731, longitude: 11.5153, ville: 'Yaoundé'),
    DoualaPlace(name: 'Hôpital Général (Yaoundé)', category: 'Hôpital', latitude: 3.8583, longitude: 11.5000, ville: 'Yaoundé'),
    DoualaPlace(name: 'Cardio-Logic Centre', category: 'Hôpital', latitude: 3.8833, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Hôpital de Mvog-Febé', category: 'Hôpital', latitude: 3.8867, longitude: 11.5311, ville: 'Yaoundé'),
    DoualaPlace(name: 'Fondation Chantal Biya', category: 'Hôpital', latitude: 3.8583, longitude: 11.5000, ville: 'Yaoundé'),
    // ── YAOUNDÉ — Universités / Écoles ──────────────────────────
    DoualaPlace(name: 'Université de Yaoundé I (Soa)', category: 'Université', latitude: 3.8667, longitude: 11.5000, ville: 'Yaoundé'),
    DoualaPlace(name: 'Université de Yaoundé II (Soa)', category: 'Université', latitude: 3.8583, longitude: 11.4833, ville: 'Yaoundé'),
    DoualaPlace(name: 'Institut des Relations du Commerce Extérieur (IRIC)', category: 'École', latitude: 3.8767, longitude: 11.5333, ville: 'Yaoundé'),
    DoualaPlace(name: 'Collège Vogbét', category: 'École', latitude: 3.9100, longitude: 11.5200, ville: 'Yaoundé'),
    DoualaPlace(name: 'Lycée Général Leclerc (Yaoundé)', category: 'École', latitude: 3.8739, longitude: 11.5108, ville: 'Yaoundé'),
    // ── YAOUNDÉ — Gares / Transport ─────────────────────────────
    DoualaPlace(name: 'Gare routière (Mvan)', category: 'Gare', latitude: 3.8983, longitude: 11.5272, ville: 'Yaoundé'),
    DoualaPlace(name: 'Gare routière Nkolbisson', category: 'Gare', latitude: 3.9017, longitude: 11.4844, ville: 'Yaoundé'),
    DoualaPlace(name: 'Gare ferroviaire d\'Essos', category: 'Gare', latitude: 3.9167, longitude: 11.5500, ville: 'Yaoundé'),
    DoualaPlace(name: 'Aéroport International de Yaoundé-Nsimalen', category: 'Aéroport', latitude: 3.7225, longitude: 11.5544, ville: 'Yaoundé'),
    // ── YAOUNDÉ — Lieux d'intérêt ───────────────────────────────
    DoualaPlace(name: 'Palais des Congrès', category: 'Lieu d\'intérêt', latitude: 3.8867, longitude: 11.5233, ville: 'Yaoundé'),
    DoualaPlace(name: 'Tour de la Réunification (Obidjam)', category: 'Lieu d\'intérêt', latitude: 3.8667, longitude: 11.5167, ville: 'Yaoundé'),
    DoualaPlace(name: 'Stade Ahmadou Ahidjo', category: 'Sport', latitude: 3.8633, longitude: 11.5067, ville: 'Yaoundé'),
    DoualaPlace(name: 'Place de la Bastille (Bastos)', category: 'Lieu d\'intérêt', latitude: 3.8808, longitude: 11.5264, ville: 'Yaoundé'),
    DoualaPlace(name: 'Parc Zoologique et Botanique (Mvog-Mbi)', category: 'Loisirs', latitude: 3.8917, longitude: 11.5472, ville: 'Yaoundé'),
  ];


  /// Normalise pour la recherche : minuscules + accents retirés
  /// (« Yaounde » trouve « Yaoundé », « Deido » trouve « Déido »…).
  static String fold(String s) {
    const map = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
      'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o',
      'ô': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
    };
    var out = s.toLowerCase();
    map.forEach((from, to) => out = out.replaceAll(from, to));
    return out;
  }

  /// Recherche insensible à la casse/accents sur le nom, la catégorie et la ville.
  static List<DoualaPlace> search(String query, {int limit = 8}) {
    final q = fold(query.trim());
    if (q.isEmpty) return [];
    final results = <DoualaPlace>[];
    for (final place in all) {
      if (fold(place.name).contains(q) ||
          fold(place.category).contains(q) ||
          fold(place.ville).contains(q)) {
        results.add(place);
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}
