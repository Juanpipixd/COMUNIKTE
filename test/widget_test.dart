import 'package:flutter_test/flutter_test.dart';
import 'package:comunikte/main.dart';

void main() {
  testWidgets('ComunikteApp smoke test - verifies title renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ComunikteApp());
    expect(find.text('COMUNIKTE'), findsOneWidget);
  });
}
