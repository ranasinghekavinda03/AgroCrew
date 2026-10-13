import 'package:agrocrew/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the AgroCrew foundation screen', (tester) async {
    await tester.pumpWidget(const AgroCrewApp());

    expect(find.text('AgroCrew'), findsNWidgets(2));
    expect(find.text('Multi-Agent Smart Farming Assistant'), findsOneWidget);
    expect(
      find.text(
        'AI-powered crop monitoring, plant disease detection, and farming assistance.',
      ),
      findsOneWidget,
    );
    expect(find.text('Project Foundation'), findsOneWidget);
    expect(
      find.text('Flutter application initialized successfully.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
  });
}
