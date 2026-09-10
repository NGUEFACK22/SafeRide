import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'offline_service.dart';

class SosService {
  final ApiService _api = ApiService();

  /// Déclenchement par bouton (fallback immédiat, Point 9).
  /// [tripId] null autorisé : alerte SOS hors trajet (destination + position
  /// GPS du téléphone envoyées aux contacts).
  ///
  /// Si le réseau est indisponible, l'alerte est mise en file d'attente locale
  /// (SQLite via [OfflineService.enqueue], Point 12) et rejouée dès le retour
  /// de la connexion. Le retour contient alors `{queued: true}`.
  Future<Map<String, dynamic>> triggerButton(
    int? tripId,
    double latitude,
    double longitude, {
    String? destination,
  }) async {
    final payload = <String, dynamic>{
      'trip_id': ?tripId,
      if (destination != null && destination.trim().isNotEmpty)
        'destination': destination.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'declenchement': 'BOUTON',
    };
    return await _postOrEnqueue(payload);
  }

  /// Déclenchement vocal : mot-clé détecté + empreinte vocale.
  /// [empreinte] est soit l'embedding de voix (`List<double>`, biométrie ECAPA-TDNN),
  /// soit un token (repli si le modèle ONNX est absent).
  /// [tripId] null autorisé : alerte SOS hors trajet.
  ///
  /// Même file d'attente hors-ligne que [triggerButton] sur panne réseau.
  Future<Map<String, dynamic>> triggerVocal(
    int? tripId,
    double latitude,
    double longitude,
    String keyword,
    Object empreinte, {
    String? destination,
  }) async {
    final payload = <String, dynamic>{
      'trip_id': ?tripId,
      if (destination != null && destination.trim().isNotEmpty)
        'destination': destination.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'declenchement': 'VOCAL',
      'keyword': keyword,
      'empreinte': empreinte,
    };
    return await _postOrEnqueue(payload);
  }

  Future<Map<String, dynamic>> setSecurityWord(String mot) async {
    return await _api.post('/voice/security-word', {'mot_securite': mot});
  }

  /// Enrôle l'embedding de voix (`List<double>`) ou un token de repli.
  Future<Map<String, dynamic>> enroll(Object empreinte) async {
    return await _api.post('/voice/enroll', {'empreinte': empreinte});
  }

  Future<Map<String, dynamic>> profile() async {
    return await _api.get('/voice/profile');
  }

  Future<Map<String, dynamic>> contacts() async {
    return await _api.get('/emergency-contacts');
  }

  /// Sel device persistant permettant de (re)générer un token d'empreinte reproductible.
  Future<String> deviceSalt() async {
    final prefs = await SharedPreferences.getInstance();
    var salt = prefs.getString('voice_device_salt');
    if (salt == null) {
      final rnd = List<int>.generate(16, (_) => Random().nextInt(256));
      salt = base64UrlEncode(rnd);
      await prefs.setString('voice_device_salt', salt);
    }
    return salt;
  }

  /// Token d'empreinte vocale = sha256(mot_securite : sel_device).
  /// Partagé entre l'enrôlement et le déclenchement pour que le backend valide.
  Future<String> voiceprintToken(String securityWord) async {
    final salt = await deviceSalt();
    final bytes = utf8.encode('$securityWord:$salt');
    return sha256.convert(bytes).toString();
  }

  /// POST /sos avec repli hors-ligne : toute panne réseau (pas une erreur de
  /// validation du serveur) met l'alerte en file d'attente SQLite.
  Future<Map<String, dynamic>> _postOrEnqueue(Map<String, dynamic> payload) async {
    try {
      return await _api.post('/sos', payload);
    } on ApiException {
      rethrow; // l'API a répondu (ex : 422) : vraie erreur, pas de file
    } catch (_) {
      await OfflineService.instance.enqueue('/sos', 'POST', payload);
      return const {'queued': true, 'sms_message': null, 'emergency_contacts': <dynamic>[]};
    }
  }

  /// Message de résultat honnête basé sur les canaux réellement actifs
  /// (alerts_sent du backend) — jamais "SMS envoyés" si l'opérateur SMS
  /// n'est pas configuré. Partagé entre l'écran SOS et l'accueil.
  String resultMessage(Map<String, dynamic> data, {required bool bouton}) {
    final summary = (data['alerts_sent'] as Map<String, dynamic>?)?['summary']
        as Map<String, dynamic>?;
    if (summary == null) {
      return bouton
          ? 'Alerte SOS déclenchée et transmise.'
          : 'Alerte vocale déclenchée et transmise.';
    }

    final emailSent = (summary['email_sent'] as num?)?.toInt() ?? 0;
    final smsSent = (summary['sms_sent'] as num?)?.toInt() ?? 0;
    final waSent = (summary['whatsapp_sent'] as num?)?.toInt() ?? 0;
    final contacts = (summary['contacts_total'] as num?)?.toInt() ?? 0;

    final canaux = <String>[
      if (smsSent > 0) 'SMS',
      if (waSent > 0) 'WhatsApp',
      if (emailSent > 0) 'email',
    ];

    if (canaux.isEmpty) {
      return contacts > 0
          ? 'Alerte enregistrée — aucun canal de transmission n\'a abouti. '
              'Vérifiez vos contacts (email requis).'
          : 'Alerte enregistrée — aucun contact d\'urgence enregistré. '
              'Ajoutez-en pour être notifié.';
    }

    final prefix = bouton ? 'Alerte SOS transmise' : 'Alerte vocale transmise';
    return '$prefix (${canaux.join(', ')}) • gestionnaire et litige notifiés.';
  }
}
