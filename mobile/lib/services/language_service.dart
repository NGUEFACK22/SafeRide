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
    'sos_desc': {'fr': 'Appuyez pour alerter vos contacts', 'en': 'Tap to alert your contacts'},
    'scan_qr': {'fr': 'Scanner un QR Code', 'en': 'Scan QR Code'},
    'scan_qr_desc': {'fr': 'Appuyez ici pour démarrer ou vérifier une course sécurisée.', 'en': 'Tap here to start or verify a secure ride.'},
    'scan_instruction': {'fr': 'Scannez le QR Code du\ntransporteur pour démarrer\nvotre trajet', 'en': 'Scan the driver\'s QR Code\nto start your ride'},
    'mode_scan_active': {'fr': 'Mode scan actif', 'en': 'Scan mode active'},
    'align_qr': {'fr': 'Alignez le QR code du transporteur', 'en': 'Align the driver QR code'},
    'services': {'fr': 'Mes services', 'en': 'My services'},
    'services_sub': {'fr': 'Trajet • Litige • Identité', 'en': 'Ride • Dispute • Identity'},
    'trip': {'fr': 'Trajet', 'en': 'Ride'},
    'trip_tracking': {'fr': 'Suivi GPS', 'en': 'GPS Tracking'},
    'dispute': {'fr': 'Litige', 'en': 'Dispute'},
    'dispute_sub': {'fr': 'Objets & SOS', 'en': 'Lost & SOS'},
    'identity': {'fr': 'Identité', 'en': 'Identity'},
    'identity_sub': {'fr': 'Vérifier', 'en': 'Verify'},
    'vehicle': {'fr': 'Véhicule', 'en': 'Vehicle'},
    'vehicle_qr': {'fr': 'QR unique', 'en': 'Unique QR'},
    'history': {'fr': 'Historique', 'en': 'History'},
    'history_full': {'fr': 'Voir l\'historique complet', 'en': 'View full history'},
    'login': {'fr': 'Se connecter', 'en': 'Sign in'},
    'register': {'fr': 'S\'inscrire', 'en': 'Sign up'},
    'logout': {'fr': 'Déconnexion', 'en': 'Sign out'},
    'guest': {'fr': 'Invité', 'en': 'Guest'},
    'guest_mode': {'fr': 'Mode invité — explorez librement. Inscrivez-vous pour interagir.', 'en': 'Guest mode — explore freely. Sign up to interact.'},
    'guest_locked': {'fr': 'Fonctionnalité verrouillée — inscrivez-vous', 'en': 'Feature locked — sign up'},
    'welcome': {'fr': 'Bienvenue sur SafeRide AI', 'en': 'Welcome to SafeRide AI'},
    'welcome_sub': {'fr': 'Rejoignez SafeRide AI pour des trajets sécurisés.', 'en': 'Join SafeRide AI for secure rides.'},
    'hello': {'fr': 'Bonjour', 'en': 'Hello'},
    'verified_secure': {'fr': 'VOTRE COMPTE EST VÉRIFIÉ ET SÉCURISÉ', 'en': 'YOUR ACCOUNT IS VERIFIED AND SECURE'},
    'verified_carrier': {'fr': 'VOTRE COMPTE TRANSPORTEUR EST VÉRIFIÉ', 'en': 'YOUR DRIVER ACCOUNT IS VERIFIED'},
    'email': {'fr': 'Adresse e-mail', 'en': 'Email address'},
    'password': {'fr': 'Mot de passe', 'en': 'Password'},
    'email_hint': {'fr': 'jean.dupont@exemple.com', 'en': 'john.doe@example.com'},
    'phone': {'fr': 'Téléphone', 'en': 'Phone'},
    'name': {'fr': 'Nom complet', 'en': 'Full name'},
    'first_name': {'fr': 'Prénom', 'en': 'First name'},
    'or_continue': {'fr': 'OU CONTINUER AVEC', 'en': 'OR CONTINUE WITH'},
    'no_account': {'fr': 'Pas de compte ? ', 'en': 'No account? '},
    'has_account': {'fr': 'Déjà inscrit ? Se connecter', 'en': 'Already have an account? Sign in'},
    'continue_guest': {'fr': 'Continuer en tant qu\'invité — explorer', 'en': 'Continue as guest — explore'},
    'guest_info': {'fr': 'Visiteur : consultez toutes les fonctionnalités. L\'interaction nécessite une inscription.', 'en': 'Visitor: browse all features. Interaction requires sign up.'},
    'forgot_password': {'fr': 'Mot de passe oublié ?', 'en': 'Forgot password?'},
    'create_account': {'fr': 'Créer un compte', 'en': 'Create account'},
    'create_account_btn': {'fr': 'Créer mon compte', 'en': 'Create my account'},
    'accept_terms': {'fr': 'J\'accepte les Conditions d\'utilisation et la Politique de confidentialité', 'en': 'I accept the Terms and Privacy Policy'},
    'you_are': {'fr': 'Vous êtes :', 'en': 'You are:'},
    'passenger': {'fr': 'Passager', 'en': 'Passenger'},
    'driver': {'fr': 'Transporteur', 'en': 'Driver'},
    'searching': {'fr': 'Je cherche', 'en': 'I need a ride'},
    'offering': {'fr': 'Je propose', 'en': 'I offer rides'},
    'translate_tooltip': {'fr': 'Langue : Français ↔ English', 'en': 'Language: English ↔ French'},
    'language': {'fr': 'Français', 'en': 'English'},
    'notifications': {'fr': 'Notifications', 'en': 'Notifications'},
    'my_qr': {'fr': 'Mon QR Code', 'en': 'My QR Code'},
    'present_qr': {'fr': 'Présentez ce QR au passager pour démarrer la course', 'en': 'Show this QR to the passenger to start the ride'},
    'qr_active': {'fr': 'QR actif • régénération auto après chaque scan', 'en': 'QR active • auto-regenerates after each scan'},
    'no_vehicle': {'fr': 'Aucun véhicule', 'en': 'No vehicle'},
    'add_vehicle': {'fr': 'Ajouter mon véhicule', 'en': 'Add my vehicle'},
    'dashboard': {'fr': 'Tableau de bord', 'en': 'Dashboard'},
    'stats_notes': {'fr': 'Stats & notes', 'en': 'Stats & ratings'},
    'hearing_course': {'fr': 'Course', 'en': 'Ride'},
    'auto_listening': {'fr': 'Écoute auto', 'en': 'Auto listening'},
  };
}
