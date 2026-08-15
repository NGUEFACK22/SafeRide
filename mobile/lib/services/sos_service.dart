import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class SosService {
  final ApiService _api = ApiService();

  /// Déclenchement par bouton (fallback immédiat, Point 9).
  Future<Map<String, dynamic>> triggerButton(
    int tripId,
    double latitude,
    double longitude,
  ) async {
    return await _api.post('/sos', {
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'declenchement': 'BOUTON',
    });
  }

  /// Déclenchement vocal : mot-clé détecté + empreinte vocale.
  /// [empreinte] est soit l'embedding de voix (`List<double>`, biométrie ECAPA-TDNN),
  /// soit un token (repli si le modèle ONNX est absent).
  Future<Map<String, dynamic>> triggerVocal(
    int tripId,
    double latitude,
    double longitude,
    String keyword,
    Object empreinte,
  ) async {
    return await _api.post('/sos', {
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'declenchement': 'VOCAL',
      'keyword': keyword,
      'empreinte': empreinte,
    });
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
}
