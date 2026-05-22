import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Guru App dummy smoke test', (WidgetTester tester) async {
    // Render a simple widget to ensure the test framework is working.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('WTF Guru App'),
        ),
      ),
    );

    expect(find.text('WTF Guru App'), findsOneWidget);
  });
}
