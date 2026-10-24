import 'package:agrocrew/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _phase = String.fromEnvironment('INTEGRATION_RESTART_PHASE');
const _password = 'DisposableStep22Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android restart preserves session and farm access', (
    tester,
  ) async {
    expect(_email, isNotEmpty);
    expect(_phase, anyOf('prepare', 'verify'));
    app.main();
    await _settle(tester);

    if (_phase == 'prepare') {
      expect(find.byKey(const Key('home-login')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('home-login')));
      await tester.tap(find.byKey(const Key('home-login')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login-email-field')),
        _email,
      );
      await tester.enterText(
        find.byKey(const Key('login-password-field')),
        _password,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('login-submit')));
      await _settle(tester);
    }

    expect(find.text('Hello, Step 22 Android Farmer A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-farms-button')));
    await _settle(tester);
    expect(find.text('Green Valley Farm'), findsOneWidget);

    if (_phase == 'verify') {
      final title = find.text('My Farms');
      Navigator.of(tester.element(title)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('home-login')), findsOneWidget);
    }
  });
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 25),
);
