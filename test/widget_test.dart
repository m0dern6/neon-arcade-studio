import 'package:flutter_test/flutter_test.dart';
import 'package:game/main.dart';

void main() {
  testWidgets('Neon App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NeonApp());

    // Verify that the game title exists (it's in the start overlay)
    expect(find.text('NEON GRAVITY'), findsOneWidget);
  });
}
