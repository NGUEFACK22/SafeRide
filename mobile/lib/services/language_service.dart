import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService extends ChangeNotifier {
  static final LanguageService instance = LanguageService._();
  LanguageService._();
  String _lang = 'fr'; // fr | en
  String get lang => _lang;
  bool get isFr => _lang == 'fr';

  static const _key = 'app_lang';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _lang = p.getString(_key) ?? 'fr';
    notifyListeners();
  }

  Future<void> toggle() async {
    _lang = _lang == 'fr' ? 'en' : 'fr';
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, _lang);
    notifyListeners();
  }

  Future<void> setLang(String v) async {
    _lang = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, v);
    notifyListeners();
  }

  String t(String key) {
    return _translations[key]?[_lang] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'app_title': {'fr': 'SafeRide AI', 'en': 'SafeRide AI'},
    'home': {'fr': 'Accueil', 'en': 'Home'},
    'trips': {'fr': 'Trajets', 'en': 'Trips'},
    'map': {'fr': 'Carte', 'en': 'Map'},
    'profile': {'fr': 'Profil', 'en': 'Profile'},
    'assistance': {'fr': 'ASSISTANCE', 'en': 'SUPPORT'},
    'sos': {'fr': 'SOS URGENCE', 'en': 'SOS EMERGENCY'},
    'scan_qr': {'fr': 'Scanner un QR Code', 'en': 'Scan QR Code'},
    'services': {'fr': 'Mes services', 'en': 'My services'},
    'history': {'fr': 'Historique', 'en': 'History'},
    'login': {'fr': 'Se connecter', 'en': 'Sign in'},
    'register': {'fr': 'S\'inscrire', 'en': 'Sign up'},
    'guest': {'fr': 'Invité', 'en': 'Guest'},
    'translate_tooltip': {'fr': 'Langue : Français ↔ English', 'en': 'Language: English ↔ French'},
    'language': {'fr': 'Français', 'en': 'English'},
  };
}
