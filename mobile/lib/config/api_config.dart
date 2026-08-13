class ApiConfig {
  // URL de base de l'API. Configurable à la compilation pour fonctionner
  // sur n'importe quel client :
  //   - Émulateur Android : 10.0.2.2 pointe vers le localhost de la machine hôte
  //   - Appareil physique / web : --dart-define=API_BASE_URL=http://<IP_LAN>:8000/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
