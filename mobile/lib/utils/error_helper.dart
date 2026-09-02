import '../services/api_service.dart';

/// Transforme les erreurs techniques en messages compréhensibles
/// pour un utilisateur non informaticien.
String friendlyError(dynamic e) {
  final raw = e.toString().toLowerCase();

  // Réseau
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection refused') ||
      raw.contains('no internet') ||
      raw.contains('errno = 7') ||
      raw.contains('errno=7')) {
    return 'Pas de connexion internet. Vérifiez votre Wi-Fi ou données mobiles et réessayez.';
  }
  if (raw.contains('timeout') ||
      raw.contains('timed out') ||
      raw.contains('deadline exceeded')) {
    return 'Le serveur met trop de temps à répondre. Réessayez dans quelques instants.';
  }
  if (raw.contains('handshake') || raw.contains('ssl') || raw.contains('certificate')) {
    return 'Connexion sécurisée impossible. Vérifiez la date de votre téléphone et votre connexion.';
  }

  // ApiException avec statusCode
  if (e is ApiException) {
    switch (e.statusCode) {
      case 400:
        if (raw.contains('validation') || raw.contains('422')) {
          return _firstValidationMessage(e.message);
        }
        return 'Informations invalides. Vérifiez vos saisies.';
      case 401:
        if (raw.contains('unauthenticated') || raw.contains('unauthorized')) {
          return 'E-mail ou mot de passe incorrect.';
        }
        if (raw.contains('suspendu') || raw.contains('suspended')) {
          return 'Votre compte est suspendu. Contactez le support : support@saferide.app';
        }
        return 'Vous devez vous connecter pour continuer.';
      case 403:
        return 'Vous n\'avez pas la permission d\'effectuer cette action.';
      case 404:
        return 'Service introuvable. Mettez l\'application à jour ou réessayez.';
      case 409:
        return 'Cette action a déjà été effectuée.';
      case 422:
        return _firstValidationMessage(e.message);
      case 429:
        return 'Trop de tentatives. Patientez 1 minute avant de réessayer.';
      case 500:
      case 502:
      case 503:
        return 'Nos serveurs sont momentanément indisponibles. Réessayez dans quelques minutes.';
    }
    // Message déjà friendly venant du backend
    if (e.message.length < 120 && !e.message.toLowerCase().contains('exception')) {
      return e.message;
    }
  }

  // Messages backend courants
  if (raw.contains('email') && raw.contains('déjà') || raw.contains('already')) {
    return 'Cet e-mail est déjà utilisé. Essayez de vous connecter.';
  }
  if (raw.contains('mot de passe') || raw.contains('password')) {
    return 'Mot de passe incorrect ou trop faible.';
  }
  if (raw.contains('permission') && raw.contains('refus')) {
    return 'Permission refusée. Activez-la dans Paramètres > SafeRide.';
  }
  if (raw.contains('aucun trajet actif') || raw.contains('no active trip')) {
    return 'Aucun trajet en cours. Scannez le QR du transporteur pour commencer.';
  }
  if (raw.contains('empreinte') || raw.contains('192')) {
    return 'Voix non reconnue. Réenregistrez votre voix 30s au calme.';
  }
  if (raw.contains('camera') || raw.contains('caméra')) {
    return 'Caméra indisponible. Vérifiez la permission ou redémarrez l\'application.';
  }

  // Fallback générique — jamais de jargon
  return 'Une erreur est survenue. Réessayez. Si ça persiste, contactez support@saferide.app';
}

String _firstValidationMessage(String msg) {
  // msg peut être JSON {"email":["..."]} ou texte
  if (msg.contains('email')) return 'Adresse e-mail invalide ou déjà utilisée.';
  if (msg.contains('password') || msg.contains('mot de passe')) return 'Mot de passe invalide (min 8 caractères).';
  if (msg.contains('telephone') || msg.contains('phone')) return 'Numéro de téléphone invalide.';
  if (msg.contains('nom') || msg.contains('prenom')) return 'Vérifiez vos nom et prénom.';
  // extraire premier message lisible
  final short = msg.replaceAll(RegExp(r'[\{\}\[\]"]'), ' ').trim();
  if (short.length > 5 && short.length < 100) return short[0].toUpperCase() + short.substring(1);
  return 'Vérifiez vos informations et réessayez.';
}
