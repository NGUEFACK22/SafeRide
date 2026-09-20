class User {
  final int id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String? photoUrl;
  final String statut;
  final List<String> roles;

  User({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    this.photoUrl,
    required this.statut,
    required this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String asStr(dynamic v) => v == null ? '' : v.toString();

    final rolesRaw = json['roles'];
    final roles = rolesRaw is List
        ? rolesRaw.map((e) => e.toString()).toList()
        : <String>[];
    return User(
      id: asInt(json['id']),
      nom: asStr(json['nom']),
      prenom: asStr(json['prenom']),
      email: asStr(json['email']),
      telephone: asStr(json['telephone']),
      photoUrl: json['photo_url']?.toString(),
      statut: asStr(json['statut']),
      roles: roles,
    );
  }

  String get fullName => '$prenom $nom';

  bool hasRole(String role) => roles.contains(role);
}