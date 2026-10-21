import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _password = 'DisposableStep19Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real UI login, logout, restart state, and login again', (
    tester,
  ) async {
    expect(_email, isNotEmpty);
    final service = AuthService(ApiClient());
    try {
      await service.register(
        name: 'Step 19 Logout Farmer',
        email: _email,
        password: _password,
      );
      await createAuthTokenStore().clearSession();

      app.main();
      await _settle(tester);
      expect(find.text('Backend Connected'), findsOneWidget);

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
      expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
      expect(find.text('Email: ${_email.toLowerCase()}'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('logout-button')));
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      expect(find.text('Log out of AgroCrew?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await _settle(tester);

      expect(find.byKey(const Key('home-login')), findsOneWidget);
      expect(find.byKey(const Key('authenticated-profile')), findsNothing);
      expect(find.text('Signed out securely on this device.'), findsOneWidget);

      final restarted = AuthSession(tokenStore: createAuthTokenStore());
      await restarted.restore(service);
      expect(restarted.state, AuthSessionState.unauthenticated);

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
      expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
      await createAuthTokenStore().clearSession();
    } finally {
      service.close();
    }
  });

  testWidgets(
    'real rotated token is revoked while an independent session survives',
    (tester) async {
      var clock = DateTime.now().toUtc();
      final service = AuthService(ApiClient(), clock: () => clock);
      final store = MemoryAuthTokenStore();
      final session = AuthSession(tokenStore: store, clock: () => clock);
      try {
        final first = await service.login(email: _email, password: _password);
        final independent = await service.login(
          email: _email,
          password: _password,
        );
        final profile = await service.getCurrentUser(first.accessToken);
        await session.establishVerified(first, profile);
        clock = clock.add(const Duration(minutes: 31));
        await session.getCurrentUser(service);
        final rotatedRefresh = session.refreshToken;
        expect(rotatedRefresh, isNot(first.refreshToken));

        final result = await session.logout(service);
        expect(result.localCleanupSucceeded, isTrue);
        expect(result.remoteLogoutConfirmed, isTrue);
        await expectLater(
          service.refreshSession(rotatedRefresh!),
          throwsA(isA<RefreshException>()),
        );
        final independentRotated = await service.refreshSession(
          independent.refreshToken,
        );
        expect(independentRotated.refreshToken, isNotEmpty);
        await service.logout(independentRotated.refreshToken);
      } finally {
        service.close();
      }
    },
  );
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);
