import 'dart:convert';

import 'package:agrocrew/app.dart';
import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/home/data/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('logout button renders and cancel preserves authentication', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(find.text('Log out of AgroCrew?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logout-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
    expect(harness.logoutRequests, 0);
  });

  testWidgets('confirming logout returns home and back cannot reopen profile', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout-confirm')));
    await tester.pumpAndSettle();

    expect(harness.logoutRequests, 1);
    expect(find.byKey(const Key('home-login')), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byKey(const Key('authenticated-profile')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authenticated-profile')), findsNothing);
  });

  testWidgets('remote failure shows safe local sign-out message', (
    tester,
  ) async {
    final harness = _Harness(remoteFailure: true);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Server sign-out could not be confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('widget-refresh'), findsNothing);
  });
}

class _Harness {
  _Harness({this.remoteFailure = false});

  final bool remoteFailure;
  int logoutRequests = 0;

  late final MockClient client = MockClient((request) async {
    if (request.url.path.endsWith('/auth/me')) return _profileResponse();
    if (request.url.path.endsWith('/auth/logout')) {
      logoutRequests += 1;
      if (remoteFailure) throw http.ClientException('offline', request.url);
      return http.Response('', 204);
    }
    return http.Response('{"status":"ok","service":"agrocrew-api"}', 200);
  });

  Widget app() {
    final apiClient = ApiClient(
      client: client,
      timeout: const Duration(seconds: 1),
    );
    return AgroCrewApp(
      authService: AuthService(apiClient),
      healthService: HealthService(apiClient),
      tokenStore: _Store(_session()),
    );
  }
}

LoginResponse _session() => LoginResponse(
  accessToken: 'widget-access',
  refreshToken: 'widget-refresh',
  issuedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 12,
    'name': 'Logout Farmer',
    'email': 'logout@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);

class _Store implements AuthTokenStore {
  _Store(this.session);
  LoginResponse? session;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<LoginResponse?> readSession() async => session;

  @override
  Future<void> saveSession(LoginResponse value) async => session = value;
}
