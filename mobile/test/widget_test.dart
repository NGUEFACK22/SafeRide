import 'package:flutter_test/flutter_test.dart';
import 'package:saferide_mobile/main.dart';

void main() {
  testWidgets('SafeRideApp se lance sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeRideApp());
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}