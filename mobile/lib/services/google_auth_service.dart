import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_config.dart';

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  Future<GoogleSignIn> _instance() async {
    if (!_initialized) {
      await _googleSignIn.initialize(
        clientId: ApiConfig.googleAndroidClientId,
        serverClientId: ApiConfig.googleClientId,
      );
      _initialized = true;
    }
    return _googleSignIn;
  }

  /// Ouvre le sélecteur de compte Google et retourne l'ID token
  /// (null si l'utilisateur annule ou si Google n'est pas configuré).
  Future<String?> getIdToken() async {
    final signIn = await _instance();

    GoogleSignInAccount? account;
    try {
      account = await signIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
    } on GoogleSignInException catch (e) {
      final code = e.code;
      if (code == GoogleSignInExceptionCode.canceled ||
          code == GoogleSignInExceptionCode.interrupted ||
          code == GoogleSignInExceptionCode.uiUnavailable) {
        return null;
      }
      rethrow;
    }

    final auth = account.authentication;
    return auth.idToken;
  }

  Future<void> signOut() async {
    final signIn = await _instance();
    await signIn.signOut();
  }
}