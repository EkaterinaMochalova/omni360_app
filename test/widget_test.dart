import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni360_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: Omni360App()));
    await tester.pump();
    // App starts with a loading/auth spinner or login screen
    expect(find.byType(Omni360App), findsOneWidget);
  });
}
