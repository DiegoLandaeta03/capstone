import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basic widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Mixd smoke test'))),
    );

    expect(find.text('Mixd smoke test'), findsOneWidget);
  });
}
