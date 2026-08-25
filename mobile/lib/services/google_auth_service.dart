import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_config.dart';

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  Future<GoogleSignIn> _instance() async {
    if (_initialized) return _googleSignIn;
    try {
      // serverClientId (Web) est obligatoire pour obtenir un idToken vérifiable côté backend.
      // clientId (Android) est optionnel — on ne le passe que s'il est renseigné via --dart-define.
      if (ApiConfig.googleAndroidClientId.isNotEmpty) {
        await _googleSignIn.initialize(
          clientId: ApiConfig.googleAndroidClientId,
          serverClientId: ApiConfig.googleClientId,
        );
      } else if (ApiConfig.googleClientId.isNotEmpty) {
        await _googleSignIn.initialize(serverClientId: ApiConfig.googleClientId);
      } else {
        await _googleSignIn.initialize();
      }
      _initialized = true;
    } on UnimplementedError catch (e) {
      throw Exception('Google Sign-In non disponible sur cet appareil : $e');
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
    } on UnimplementedError catch (e) {
      throw Exception('Google Sign-In non disponible sur cet appareil/émulateur : $e. Utilisez email/mot de passe.');
    } on Error catch (e) {
      // MissingPluginException, etc.
      throw Exception('Google Sign-In erreur système : $e');
    } catch (e) {
      // Tout autre cas (ex: message contenant UnimplementedError)
      final msg = e.toString();
      if (msg.contains('UnimplementedError') || msg.contains('MissingPluginException')) {
        throw Exception('Google Sign-In non disponible sur cet appareil : $msg');
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