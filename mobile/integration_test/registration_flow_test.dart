import 'package:agrocrew/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _integrationEmail = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _integrationPassword = 'DisposableStep15Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('registers a disposable farmer through the real Flutter UI', (
    tester,
  ) async {
    expect(_integrationEmail, isNotEmpty);
    app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );

    expect(find.text('Backend Connected'), findsOneWidget);
    final homeCreateAccount = find.byKey(const Key('home-create-account'));
    await tester.ensureVisible(homeCreateAccount);
    await tester.tap(homeCreateAccount);
    await tester.pumpAndSettle();

    expect(
      find.text('Start your smart farming journey with AgroCrew.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('register-name-field')), '   ');
    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      'short',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password-field')),
      'different',
    );
    await tester.pump();

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Password must be at least 12 characters.'),
      findsOneWidget,
    );
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('register-name-field')),
      'Step 16 Disposable Farmer',
    );
    await tester.enterText(
      find.byKey(const Key('register-email-field')),
      _integrationEmail.toUpperCase(),
    );
    await tester.enterText(
      find.byKey(const Key('register-password-field')),
      _integrationPassword,
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password-field')),
      _integrationPassword,
    );
    await tester.pump();

    final submit = find.byKey(const Key('create-account-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );

    expect(
      find.text('Account created successfully. You can now log in.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('registration-login')));
    await tester.tap(find.byKey(const Key('registration-login')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      _integrationEmail.toUpperCase(),
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      '${_integrationPassword}wrong',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Logging In...'), findsOneWidget);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
    expect(find.text('Invalid email or password.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Backend Connected'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('home-login')));
    await tester.tap(find.byKey(const Key('home-login')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      _integrationEmail.toUpperCase(),
    );

    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      _integrationPassword,
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Logging In...'), findsOneWidget);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );

    expect(find.text('Welcome to AgroCrew!'), findsOneWidget);
    expect(find.text('Hello, Step 16 Disposable Farmer'), findsOneWidget);
    expect(
      find.text('Email: ${_integrationEmail.toLowerCase()}'),
      findsOneWidget,
    );
    expect(find.text('Status: Authenticated'), findsOneWidget);
    expect(find.textContaining(_integrationPassword), findsNothing);
  });
}
