class ApiConfig {
  // URL de base de l'API. Configurable à la compilation pour fonctionner
  // sur n'importe quel client :
  //   - Émulateur Android : 10.0.2.2 pointe vers le localhost de la machine hôte
  //   - Appareil physique / web : --dart-define=API_BASE_URL=http://<IP_LAN>:8000/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://saferide-api-udra.onrender.com/api/v1',
  );

  // OAuth Google "Continuer avec Google" :
  //   GOOGLE_CLIENT_ID        → OAuth client ID Web (audience de l'ID token,
  //                             doit correspondre à services.google.client_id du backend)
  //   GOOGLE_ANDROID_CLIENT_ID→ OAuth client ID Android (optionnel sur Android,
  //                             auto-détecté via google-services.json s'il est présent)
  //
  // IMPORTANT : Sans ces valeurs, le bouton Google affichera un message d'erreur.
  // Build avec :
  //   flutter run --dart-define=GOOGLE_CLIENT_ID=<web-client-id> --dart-define=GOOGLE_ANDROID_CLIENT_ID=<android-client-id>
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '841219332616-ib3ge6r9a3n6nrpt9pp7q7u7ia5mi60a.apps.googleusercontent.com',
  );

  static const String googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '841219332616-007e6v8ho3jdnkbr2pfo0v50jnbujd2e.apps.googleusercontent.com',
  );

  /// Vérifie si la connexion Google est configurée.
  /// Retourne un message d'erreur si non configuré, null sinon.
  static String? get googleNotConfiguredMessage {
    if (googleClientId.isEmpty && googleAndroidClientId.isEmpty) {
      return 'Google non configuré. Build avec --dart-define=GOOGLE_CLIENT_ID=<id> pour activer.';
    }
    return null;
  }
}
