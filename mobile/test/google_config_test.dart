import 'package:flutter_test/flutter_test.dart';
import 'package:saferide_mobile/config/api_config.dart';

/// Preuve : le bouton "Continuer avec Google" est actif sans --dart-define
/// (ID client Web Firebase intégré par défaut, pas un secret).
void main() {
  group('Configuration Google Sign-In', () {
    test('ID client Web présent par défaut', () {
      expect(ApiConfig.googleClientId, isNotEmpty);
      expect(
        ApiConfig.googleClientId,
        endsWith('.apps.googleusercontent.com'),
      );
    });

    test('aucun message "non configuré" (bouton actif)', () {
      expect(ApiConfig.googleNotConfiguredMessage, isNull);
    });
  });
}
