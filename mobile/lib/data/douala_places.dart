/// Liste locale des destinations possibles (autocomplete hors-ligne).
///
/// Ville couverte : DOUALA (130+) — quartiers, marchés, hôpitaux, écoles,
/// universités, entreprises, administrations, carrefours et avenues,
/// gares, port/aéroport, hôtels, lieux d'intérêt. Les coordonnées sont
/// approximatives (centre du lieu) — elles sont utilisées pour tracer le
/// circuit sur la carte et sont envoyées au backend comme destination.
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

    // ── Quartiers & cités (extension) ───────────────────────────
    DoualaPlace(
      name: 'New-Bell',
      category: 'Quartier',
      latitude: 4.0530,
      longitude: 9.6990,
    ),
    DoualaPlace(
      name: 'Bonassama',
      category: 'Quartier',
      latitude: 4.0585,
      longitude: 9.6595,
    ),
    DoualaPlace(
      name: 'Nkoldop',
      category: 'Quartier',
      latitude: 4.0610,
      longitude: 9.7160,
    ),
    DoualaPlace(
      name: 'Logbassa',
      category: 'Quartier',
      latitude: 4.0930,
      longitude: 9.7450,
    ),
    DoualaPlace(
      name: 'Ndogbatanga',
      category: 'Quartier',
      latitude: 4.0690,
      longitude: 9.7010,
    ),
    DoualaPlace(
      name: 'Cité SIC',
      category: 'Quartier',
      latitude: 4.0755,
      longitude: 9.7160,
    ),
    DoualaPlace(
      name: 'Bépanda Siro',
      category: 'Quartier',
      latitude: 4.0785,
      longitude: 9.7145,
    ),
    DoualaPlace(
      name: 'PK 12',
      category: 'Quartier',
      latitude: 4.0950,
      longitude: 9.7450,
    ),

    // ── Carrefours & avenues ────────────────────────────────────
    DoualaPlace(
      name: 'Carrefour Ndokoti',
      category: 'Carrefour',
      latitude: 4.0823,
      longitude: 9.7205,
    ),
    DoualaPlace(
      name: 'Carrefour Bilingue',
      category: 'Carrefour',
      latitude: 4.0915,
      longitude: 9.7235,
    ),
    DoualaPlace(
      name: 'Carrefour Logpom',
      category: 'Carrefour',
      latitude: 4.1000,
      longitude: 9.7340,
    ),
    DoualaPlace(
      name: 'Carrefour Bépanda',
      category: 'Carrefour',
      latitude: 4.0772,
      longitude: 9.7130,
    ),
    DoualaPlace(
      name: 'Avenue Charles de Gaulle',
      category: 'Avenue',
      latitude: 4.0650,
      longitude: 9.7065,
    ),
    DoualaPlace(
      name: 'Boulevard de la Liberté',
      category: 'Avenue',
      latitude: 4.0830,
      longitude: 9.7220,
    ),

    // ── Entreprises & industrie ─────────────────────────────────
    DoualaPlace(
      name: 'MTN Cameroun',
      category: 'Entreprise',
      latitude: 4.0678,
      longitude: 9.7055,
    ),
    DoualaPlace(
      name: 'Orange Cameroun',
      category: 'Entreprise',
      latitude: 4.0662,
      longitude: 9.7075,
    ),
    DoualaPlace(
      name: 'Nestlé Cameroun',
      category: 'Entreprise',
      latitude: 4.0692,
      longitude: 9.7028,
    ),
    DoualaPlace(
      name: 'Guinness Cameroun (Colosac)',
      category: 'Entreprise',
      latitude: 4.0702,
      longitude: 9.7015,
    ),
    DoualaPlace(
      name: 'SABC - Brasseries du Cameroun',
      category: 'Entreprise',
      latitude: 4.0688,
      longitude: 9.7042,
    ),
    DoualaPlace(
      name: 'Socada',
      category: 'Entreprise',
      latitude: 4.0397,
      longitude: 9.6918,
    ),
    DoualaPlace(
      name: 'SIC CotonCO',
      category: 'Entreprise',
      latitude: 4.0758,
      longitude: 9.7152,
    ),
    DoualaPlace(
      name: 'Bollore Africa Logistics',
      category: 'Entreprise',
      latitude: 4.0115,
      longitude: 9.7095,
    ),
    DoualaPlace(
      name: 'CAMWATER',
      category: 'Entreprise',
      latitude: 4.0782,
      longitude: 9.7095,
    ),
    DoualaPlace(
      name: 'CAMPOWER',
      category: 'Entreprise',
      latitude: 4.0805,
      longitude: 9.7182,
    ),
    DoualaPlace(
      name: 'Zone Industrielle de Bassa',
      category: 'Entreprise',
      latitude: 4.0715,
      longitude: 9.6990,
    ),

    // ── Banques & assurances ────────────────────────────────────
    DoualaPlace(
      name: 'Société Générale Cameroun',
      category: 'Banque',
      latitude: 4.0392,
      longitude: 9.6908,
    ),
    DoualaPlace(
      name: 'Afriland First Bank',
      category: 'Banque',
      latitude: 4.0390,
      longitude: 9.6912,
    ),
    DoualaPlace(
      name: 'ABC',
      category: 'Banque',
      latitude: 4.0388,
      longitude: 9.6905,
    ),
    DoualaPlace(
      name: 'BICEC',
      category: 'Banque',
      latitude: 4.0402,
      longitude: 9.6915,
    ),

    // ── Administrations & établissements publics ────────────────
    DoualaPlace(
      name: 'Hôtel de Ville de Douala',
      category: 'Administration',
      latitude: 4.0393,
      longitude: 9.6910,
    ),
    DoualaPlace(
      name: 'Communauté Urbaine de Douala',
      category: 'Administration',
      latitude: 4.0380,
      longitude: 9.6930,
    ),
    DoualaPlace(
      name: 'Préfecture du Wouri',
      category: 'Administration',
      latitude: 4.0408,
      longitude: 9.6898,
    ),
    DoualaPlace(
      name: 'Conseil Régional du Littoral',
      category: 'Administration',
      latitude: 4.0412,
      longitude: 9.6895,
    ),
    DoualaPlace(
      name: 'Palais de Justice de Bonanjo',
      category: 'Administration',
      latitude: 4.0400,
      longitude: 9.6890,
    ),
    DoualaPlace(
      name: 'Impôts - Direction Régionale du Wouri',
      category: 'Administration',
      latitude: 4.0405,
      longitude: 9.6935,
    ),
    DoualaPlace(
      name: 'Chambre de Commerce du Wouri',
      category: 'Administration',
      latitude: 4.0407,
      longitude: 9.6922,
    ),
    DoualaPlace(
      name: 'CRTV Littoral',
      category: 'Administration',
      latitude: 4.0635,
      longitude: 9.7075,
    ),
    DoualaPlace(
      name: 'Poste Centrale de Douala',
      category: 'Administration',
      latitude: 4.0440,
      longitude: 9.6935,
    ),
    DoualaPlace(
      name: 'CNPS',
      category: 'Administration',
      latitude: 4.0415,
      longitude: 9.6935,
    ),

    // ── Hôpitaux & cliniques (extension) ────────────────────────
    DoualaPlace(
      name: 'Polyclinique de Bonapriso',
      category: 'Hôpital',
      latitude: 4.0345,
      longitude: 9.6975,
    ),
    DoualaPlace(
      name: 'Hôpital Militaire de Douala',
      category: 'Hôpital',
      latitude: 4.0712,
      longitude: 9.7055,
    ),

    // ── Écoles & instituts (extension) ──────────────────────────
    DoualaPlace(
      name: 'Lycée de Bonabéri',
      category: 'École',
      latitude: 4.0605,
      longitude: 9.6640,
    ),
    DoualaPlace(
      name: 'ENSET de Douala',
      category: 'École',
      latitude: 4.0795,
      longitude: 9.7185,
    ),

    // ── Marchés (extension) ─────────────────────────────────────
    DoualaPlace(
      name: 'Marché Ndogpassi',
      category: 'Marché',
      latitude: 4.0683,
      longitude: 9.7048,
    ),
    DoualaPlace(
      name: 'Grand Marché de Ndoro',
      category: 'Marché',
      latitude: 4.0790,
      longitude: 9.7190,
    ),
    DoualaPlace(
      name: 'Marché de Makepe',
      category: 'Marché',
      latitude: 4.0668,
      longitude: 9.7385,
    ),
    DoualaPlace(
      name: 'Marché de Logbessou',
      category: 'Marché',
      latitude: 4.1025,
      longitude: 9.7520,
    ),
    DoualaPlace(
      name: 'Marché de Bonamoussadi',
      category: 'Marché',
      latitude: 4.0845,
      longitude: 9.7240,
    ),
    DoualaPlace(
      name: 'Marché de New-Bell',
      category: 'Marché',
      latitude: 4.0520,
      longitude: 9.7000,
    ),

    // ── Infrastructures & repères ───────────────────────────────
    DoualaPlace(
      name: 'Pont sur le Wouri',
      category: 'Lieu d\'intérêt',
      latitude: 4.0615,
      longitude: 9.6760,
    ),
    DoualaPlace(
      name: 'Grande Mosquée de Bonabéri',
      category: 'Lieu d\'intérêt',
      latitude: 4.0597,
      longitude: 9.6650,
    ),
    DoualaPlace(
      name: 'Palais des Congrès d\'Akwa',
      category: 'Lieu d\'intérêt',
      latitude: 4.0425,
      longitude: 9.7015,
    ),
    DoualaPlace(
      name: 'Hôtel Ibis Douala',
      category: 'Hôtel',
      latitude: 4.0448,
      longitude: 9.7005,
    ),
    DoualaPlace(
      name: 'Stade Omnisports de Japoma',
      category: 'Sport',
      latitude: 4.0105,
      longitude: 9.7270,
    ),

  ];


  /// Normalise pour la recherche : minuscules + accents retirés
  /// (« Deido » trouve « Déido », « independance » trouve « Indépendance »…).
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
