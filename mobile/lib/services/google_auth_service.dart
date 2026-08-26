import 'dart:developer' as developer;

import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_config.dart';

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  Future<GoogleSignIn> _instance() async {
    if (_initialized) return _googleSignIn;
    try {
      // Vérification préalable de la configuration
      if (ApiConfig.googleClientId.isEmpty && ApiConfig.googleAndroidClientId.isEmpty) {
        throw Exception(
          'Google Sign-In non configuré. '
          'Buildz avec --dart-define=GOOGLE_CLIENT_ID=<votre-web-client-id> '
          'pour activer la connexion Google.',
        );
      }

      // serverClientId (Web) est obligatoire pour obtenir un idToken vérifiable côté backend.
      // clientId (Android) est optionnel — on ne le passe que s'il est renseigné via --dart-define.
      if (ApiConfig.googleAndroidClientId.isNotEmpty) {
        developer.log('Initialisation GoogleSignIn avec clientId Android + serverClientId Web');
        await _googleSignIn.initialize(
          clientId: ApiConfig.googleAndroidClientId,
          serverClientId: ApiConfig.googleClientId,
        );
      } else if (ApiConfig.googleClientId.isNotEmpty) {
        developer.log('Initialisation GoogleSignIn avec serverClientId Web uniquement');
        await _googleSignIn.initialize(serverClientId: ApiConfig.googleClientId);
      } else {
        await _googleSignIn.initialize();
      }
      _initialized = true;
      developer.log('GoogleSignIn initialisé avec succès');
    } on UnimplementedError catch (e) {
      developer.log('GoogleSignIn non supporté sur cet appareil: $e');
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
      developer.log('GoogleSignInException: code=$code, description=${e.description}');
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
    final idToken = auth.idToken;

    if (idToken == null || idToken.isEmpty) {
      developer.log('⚠️ GoogleSignIn: auth.idToken est NULL — vérifiez la configuration OAuth dans Google Cloud Console');
      throw Exception(
        'Google a retourné un token vide. '
        'Vérifiez que l\'API "Google+ ID" ou "Google Identity" est activée '
        'dans Google Cloud Console pour ce Client ID.',
      );
    }

    developer.log('GoogleSignIn: idToken obtenu (${idToken.length} caractères)');
    return idToken;
  }

  Future<void> signOut() async {
    final signIn = await _instance();
    await signIn.signOut();
  }
}
