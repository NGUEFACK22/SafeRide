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
    return User(
      id: json['id'],
      nom: json['nom'],
      prenom: json['prenom'],
      email: json['email'],
      telephone: json['telephone'],
      photoUrl: json['photo_url'],
      statut: json['statut'],
      roles: List<String>.from(json['roles'] ?? []),
    );
  }

  String get fullName => '$prenom $nom';

  bool hasRole(String role) => roles.contains(role);
}