import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/core/theme/app_theme.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/presentation/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _nameKey = Key('register-name-field');
const _emailKey = Key('register-email-field');
const _passwordKey = Key('register-password-field');
const _confirmationKey = Key('register-confirm-password-field');
const _submitKey = Key('create-account-submit');

void main() {
  testWidgets('registration screen renders all required controls', (
    tester,
  ) async {
    await _pumpScreen(tester, _successfulService());

    expect(find.text('Create Account'), findsNWidgets(3));
    expect(
      find.text('Start your smart farming journey with AgroCrew.'),
      findsOneWidget,
    );
    expect(find.byKey(_nameKey), findsOneWidget);
    expect(find.byKey(_emailKey), findsOneWidget);
    expect(find.byKey(_passwordKey), findsOneWidget);
    expect(find.byKey(_confirmationKey), findsOneWidget);
  });

  testWidgets('validates a blank name', (tester) async {
    await _pumpScreen(tester, _successfulService());
    await tester.enterText(find.byKey(_nameKey), '   ');
    await tester.pump();
    expect(find.text('Enter your full name.'), findsOneWidget);
  });

  testWidgets('validates an invalid email address', (tester) async {
    await _pumpScreen(tester, _successfulService());
    await tester.enterText(find.byKey(_emailKey), 'not-an-email');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('validates minimum password length', (tester) async {
    await _pumpScreen(tester, _successfulService());
    await tester.enterText(find.byKey(_passwordKey), 'TooShort1!');
    await tester.pump();
    expect(
      find.text('Password must be at least 12 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('validates maximum password length', (tester) async {
    await _pumpScreen(tester, _successfulService());
    await tester.enterText(find.byKey(_passwordKey), 'x' * 129);
    await tester.pump();
    expect(
      find.text('Password must be 128 characters or fewer.'),
      findsOneWidget,
    );
  });

  testWidgets('validates password confirmation mismatch', (tester) async {
    await _pumpScreen(tester, _successfulService());
    await tester.enterText(find.byKey(_passwordKey), 'StrongTestPassword123!');
    await tester.enterText(
      find.byKey(_confirmationKey),
      'DifferentPassword123!',
    );
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('toggles password visibility independently', (tester) async {
    await _pumpScreen(tester, _successfulService());
    expect(_isObscured(tester, _passwordKey), isTrue);
    expect(_isObscured(tester, _confirmationKey), isTrue);

    await tester.tap(find.byKey(const Key('toggle-password-visibility')));
    await tester.pump();
    expect(_isObscured(tester, _passwordKey), isFalse);
    expect(_isObscured(tester, _confirmationKey), isTrue);

    await tester.tap(
      find.byKey(const Key('toggle-confirm-password-visibility')),
    );
    await tester.pump();
    expect(_isObscured(tester, _confirmationKey), isFalse);
  });

  testWidgets('valid form enables submission', (tester) async {
    await _pumpScreen(tester, _successfulService());
    expect(
      tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed,
      isNull,
    );

    await _fillValidForm(tester);

    expect(
      tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('success confirms registration and clears password fields', (
    tester,
  ) async {
    late Map<String, dynamic> requestBody;
    final service = _serviceWith((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _successResponse;
    });
    await _pumpScreen(tester, service);
    await _fillValidForm(tester);

    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Account created successfully. You can now log in.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('registration-login')), findsOneWidget);
    expect(requestBody.keys, containsAll(['name', 'email', 'password']));
    expect(requestBody['name'], 'Test Farmer');
    expect(requestBody['email'], 'farmer@example.com');
    expect(requestBody['password'], 'StrongTestPassword123!');
    expect(requestBody, isNot(contains('confirm_password')));
    expect(requestBody, isNot(contains('confirmPassword')));
    expect(
      tester.widget<TextFormField>(find.byKey(_passwordKey)).controller!.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(_confirmationKey))
          .controller!
          .text,
      isEmpty,
    );
  });

  for (final scenario in [
    (status: 409, message: 'This email address is already registered.'),
    (
      status: 422,
      message: 'Please review your registration information and try again.',
    ),
    (
      status: 500,
      message:
          'AgroCrew could not create your account right now. Please try again.',
    ),
  ]) {
    testWidgets('shows safe HTTP ${scenario.status} feedback', (tester) async {
      final service = _serviceWith(
        (_) async =>
            http.Response('{"detail":"unsafe server detail"}', scenario.status),
      );
      await _pumpScreen(tester, service);
      await _fillValidForm(tester);

      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(scenario.message), findsOneWidget);
      expect(find.textContaining('unsafe server detail'), findsNothing);
    });
  }

  testWidgets('shows loading and prevents duplicate submission', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var requestCount = 0;
    final service = _serviceWith((_) {
      requestCount += 1;
      return response.future;
    });
    await _pumpScreen(tester, service);
    await _fillValidForm(tester);

    await _tapSubmit(tester);
    await tester.pump();

    expect(find.text('Creating Account...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed,
      isNull,
    );
    expect(requestCount, 1);

    response.complete(_successResponse);
    await tester.pumpAndSettle();
    expect(requestCount, 1);
  });
}

Future<void> _pumpScreen(WidgetTester tester, AuthService service) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RegisterScreen(authService: service),
    ),
  );
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(_nameKey), '  Test Farmer  ');
  await tester.enterText(find.byKey(_emailKey), '  FARMER@EXAMPLE.COM  ');
  await tester.enterText(find.byKey(_passwordKey), 'StrongTestPassword123!');
  await tester.enterText(
    find.byKey(_confirmationKey),
    'StrongTestPassword123!',
  );
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_submitKey));
  await tester.tap(find.byKey(_submitKey));
}

AuthService _successfulService() {
  return _serviceWith((_) async => _successResponse);
}

AuthService _serviceWith(MockClientHandler handler) {
  return AuthService(
    ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  );
}

final _successResponse = http.Response(
  jsonEncode({
    'id': 7,
    'name': 'Test Farmer',
    'email': 'farmer@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-19T12:00:00Z',
  }),
  201,
);

bool _isObscured(WidgetTester tester, Key fieldKey) {
  final editableText = find.descendant(
    of: find.byKey(fieldKey),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editableText).obscureText;
}
