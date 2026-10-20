import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/app.dart';
import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows an accessible startup loading state', (tester) async {
    final pending = Completer<LoginResponse?>();
    await tester.pumpWidget(
      AgroCrewApp(
        authService: _service((_) async => _profileResponse()),
        tokenStore: _WidgetStore(readResult: pending.future),
      ),
    );
    await tester.pump();

    expect(find.text('Checking your session...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('restores only the profile returned by the backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      AgroCrewApp(
        authService: _service((request) async {
          expect(request.headers['authorization'], 'Bearer widget-access');
          return _profileResponse();
        }),
        tokenStore: _WidgetStore(session: _session()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
    expect(find.text('Hello, Startup Farmer'), findsOneWidget);
    expect(find.textContaining('widget-access'), findsNothing);
    expect(find.textContaining('widget-refresh'), findsNothing);
  });

  testWidgets('Retry Verification repeats a failed backend check', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      AgroCrewApp(
        authService: _service((_) async {
          requests += 1;
          if (requests == 1) throw http.ClientException('offline');
          return _profileResponse();
        }),
        tokenStore: _WidgetStore(session: _session()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-retry-verification')), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-retry-verification')));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
  });
}

AuthService _service(MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
);

LoginResponse _session() => LoginResponse(
  accessToken: 'widget-access',
  refreshToken: 'widget-refresh',
  issuedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 9,
    'name': 'Startup Farmer',
    'email': 'startup@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);

class _WidgetStore implements AuthTokenStore {
  _WidgetStore({this.session, this.readResult});

  LoginResponse? session;
  final Future<LoginResponse?>? readResult;

  @override
  Future<LoginResponse?> readSession() =>
      readResult ?? Future<LoginResponse?>.value(session);

  @override
  Future<void> saveSession(LoginResponse value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;
}
