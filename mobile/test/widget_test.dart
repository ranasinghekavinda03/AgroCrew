import 'dart:async';

import 'package:agrocrew/app.dart';
import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/home/data/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows AgroCrew branding and the connected backend state', (
    tester,
  ) async {
    final service = _serviceWith((_) async {
      return http.Response('{"status":"ok","service":"agrocrew-api"}', 200);
    });

    await tester.pumpWidget(AgroCrewApp(healthService: service));
    await tester.pumpAndSettle();

    expect(find.text('AgroCrew'), findsNWidgets(2));
    expect(find.text('Multi-Agent Smart Farming Assistant'), findsOneWidget);
    expect(find.text('Backend Connection'), findsOneWidget);
    expect(find.text('Backend Connected'), findsOneWidget);
    expect(find.text('Service: agrocrew-api'), findsOneWidget);
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('shows unavailable state and retries the connection', (
    tester,
  ) async {
    var requestCount = 0;
    final service = _serviceWith((_) async {
      requestCount += 1;
      if (requestCount == 1) {
        return http.Response('Server error', 500);
      }
      return http.Response('{"status":"ok","service":"agrocrew-api"}', 200);
    });

    await tester.pumpWidget(AgroCrewApp(healthService: service));
    await tester.pumpAndSettle();

    expect(find.text('Backend Unavailable'), findsOneWidget);
    expect(
      find.text('Unable to connect to the AgroCrew backend.'),
      findsOneWidget,
    );
    expect(find.text('Retry Connection'), findsOneWidget);

    final retryButton = find.text('Retry Connection');
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(find.text('Backend Connected'), findsOneWidget);
    expect(find.text('Service: agrocrew-api'), findsOneWidget);
    expect(requestCount, 2);
  });

  testWidgets('shows the checking state while the request is pending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final service = _serviceWith((_) => response.future);

    await tester.pumpWidget(AgroCrewApp(healthService: service));
    await tester.pump();

    expect(find.text('Checking connection...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    response.complete(
      http.Response('{"status":"ok","service":"agrocrew-api"}', 200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend Connected'), findsOneWidget);
  });

  testWidgets('opens registration from home and supports back navigation', (
    tester,
  ) async {
    final service = _serviceWith((_) async {
      return http.Response('{"status":"ok","service":"agrocrew-api"}', 200);
    });

    await tester.pumpWidget(AgroCrewApp(healthService: service));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('home-create-account')));
    await tester.tap(find.byKey(const Key('home-create-account')));
    await tester.pumpAndSettle();

    expect(
      find.text('Start your smart farming journey with AgroCrew.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Backend Connected'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });
}

HealthService _serviceWith(MockClientHandler handler) {
  return HealthService(
    ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  );
}
