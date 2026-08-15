import 'package:flutter_test/flutter_test.dart';
import 'package:saferide_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SafeRideApp se lance sans erreur', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SafeRideApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    // Laisse le timer du splash se déclencher puis ignore l'exception
    // attendue des plugins (Firebase) non disponibles en test.
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
  });
}