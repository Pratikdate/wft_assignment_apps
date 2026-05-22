import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Trainer App dummy smoke test', (WidgetTester tester) async {
    // Render a simple widget to ensure the test framework is working.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('WTF Trainer App'),
        ),
      ),
    );

    expect(find.text('WTF Trainer App'), findsOneWidget);
  });
}
