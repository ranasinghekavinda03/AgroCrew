import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/core/theme/app_theme.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('login screen renders all required controls', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(
      find.text('Log in to continue your smart farming journey.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('login-email-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('login-create-account')), findsOneWidget);
  });

  testWidgets('validates required email', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'farmer@example.com',
    );
    await tester.enterText(find.byKey(const Key('login-email-field')), '');
    await tester.pump();
    expect(find.text('Enter your email address.'), findsOneWidget);
  });

  testWidgets('validates email format', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'not-an-email',
    );
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('validates required password without a minimum length', (
    tester,
  ) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    final field = find.byKey(const Key('login-password-field'));
    await tester.enterText(field, 'x');
    await tester.enterText(field, '');
    await tester.pump();
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'farmer@example.com',
    );
    await tester.enterText(field, 'x');
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('toggles password visibility', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    TextField passwordField() => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('login-password-field')),
        matching: find.byType(TextField),
      ),
    );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byKey(const Key('login-toggle-password-visibility')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('valid form enables submission', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    expect(_submitButton(tester).onPressed, isNull);
    await _fillValidForm(tester);
    expect(_submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('shows loading and prevents duplicate submissions', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var requestCount = 0;
    final service = _serviceWith((_) {
      requestCount += 1;
      return response.future;
    });
    await _pumpLogin(tester, service);
    await _fillValidForm(tester);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Logging In...'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('login-submit')),
      warnIfMissed: false,
    );
    expect(requestCount, 1);

    response.complete(http.Response('{"detail":"invalid"}', 401));
    await tester.pumpAndSettle();
  });

  testWidgets('shows generic invalid-credentials feedback', (tester) async {
    final service = _serviceWith(
      (_) async => http.Response('{"detail":"account exists"}', 401),
    );
    await _pumpLogin(tester, service);
    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.textContaining('account exists'), findsNothing);
  });

  testWidgets('successful login verifies and displays the backend profile', (
    tester,
  ) async {
    final service = _successfulService();
    await _pumpLogin(tester, service);
    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
    expect(find.text('Welcome to AgroCrew!'), findsOneWidget);
    expect(find.text('Hello, Real Farmer'), findsOneWidget);
    expect(find.text('Email: real.farmer@example.com'), findsOneWidget);
    expect(find.text('Status: Authenticated'), findsOneWidget);
    expect(find.textContaining('signed.jwt.value'), findsNothing);
    expect(find.textContaining('opaque-refresh-value'), findsNothing);
  });

  testWidgets('shows profile loading before verification completes', (
    tester,
  ) async {
    final profileResponse = Completer<http.Response>();
    final service = _serviceWith((request) async {
      if (request.method == 'POST') return _loginResponse();
      return profileResponse.future;
    });
    await _pumpLogin(tester, service);
    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('profile-loading')), findsOneWidget);
    profileResponse.complete(_profileResponse());
    await tester.pumpAndSettle();
  });

  testWidgets('rejected access token clears the session and requires login', (
    tester,
  ) async {
    final session = AuthSession();
    final service = _serviceWith((request) async {
      if (request.method == 'POST') return _loginResponse();
      return http.Response('{"detail":"invalid"}', 401);
    });
    await _pumpLogin(tester, service, session: session);
    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-login-again')), findsOneWidget);
    expect(session.hasTokens, isFalse);
    expect(session.profile, isNull);
  });

  testWidgets('login can navigate to registration', (tester) async {
    await _pumpLogin(tester, _serviceWith((_) async => _loginResponse()));
    await tester.tap(find.byKey(const Key('login-create-account')));
    await tester.pumpAndSettle();
    expect(
      find.text('Start your smart farming journey with AgroCrew.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpLogin(
  WidgetTester tester,
  AuthService service, {
  AuthSession? session,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: LoginScreen(authService: service, session: session ?? AuthSession()),
  ),
);

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email-field')),
    'farmer@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login-password-field')),
    'DisposablePassword123!',
  );
  await tester.pump();
}

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('login-submit')));

AuthService _serviceWith(MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
);

AuthService _successfulService() => _serviceWith((request) async {
  if (request.method == 'POST') return _loginResponse();
  expect(request.headers['authorization'], 'Bearer signed.jwt.value');
  return _profileResponse();
});

http.Response _loginResponse() => http.Response(
  jsonEncode({
    'access_token': 'signed.jwt.value',
    'refresh_token': 'opaque-refresh-value',
    'token_type': 'bearer',
    'expires_in': 1800,
    'refresh_expires_in': 604800,
  }),
  200,
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 42,
    'name': 'Real Farmer',
    'email': 'real.farmer@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);
