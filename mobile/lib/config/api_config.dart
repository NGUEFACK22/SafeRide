class ApiConfig {
  // URL de base de l'API. Configurable à la compilation pour fonctionner
  // sur n'importe quel client :
  //   - Émulateur Android : 10.0.2.2 pointe vers le localhost de la machine hôte
  //   - Appareil physique / web : --dart-define=API_BASE_URL=http://<IP_LAN>:8000/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  // OAuth Google "Continuer avec Google" :
  //   GOOGLE_CLIENT_ID        → OAuth client ID Web (audience de l'ID token,
  //                             doit correspondre à services.google.client_id du backend)
  //   GOOGLE_ANDROID_CLIENT_ID→ OAuth client ID Android (optionnel sur Android,
  //                             auto-détecté via google-services.json s'il est présent)
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
}
