import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:agrocrew/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _emailA = String.fromEnvironment('INTEGRATION_EMAIL_A');
const _emailB = String.fromEnvironment('INTEGRATION_EMAIL_B');
const _password = 'DisposableStep22Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Android two-farmer Farm flow', (tester) async {
    expect(_emailA, isNotEmpty);
    expect(_emailB, isNotEmpty);
    final apiClient = ApiClient();
    final authService = AuthService(apiClient);
    await createAuthTokenStore().clearSession();

    try {
      final registeredA = await authService.register(
        name: 'Step 22 Android Farmer A',
        email: _emailA,
        password: _password,
      );
      final registeredB = await authService.register(
        name: 'Step 22 Android Farmer B',
        email: _emailB,
        password: _password,
      );

      app.main();
      await _settle(tester);
      expect(find.text('Backend Connected'), findsOneWidget);

      await _login(tester, _emailA);
      expect(find.text('Hello, Step 22 Android Farmer A'), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-farms-button')));
      await _settle(tester);
      expect(find.byKey(const Key('farms-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-farm-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('farm-name-field')),
        'Green Valley Farm',
      );
      await tester.enterText(find.byKey(const Key('farm-area-field')), '2.5');
      await tester.enterText(
        find.byKey(const Key('farm-area-unit-field')),
        'acres',
      );
      await tester.enterText(
        find.byKey(const Key('farm-latitude-field')),
        '6.927079',
      );
      await tester.enterText(
        find.byKey(const Key('farm-longitude-field')),
        '79.861244',
      );
      await tester.enterText(
        find.byKey(const Key('farm-notes-field')),
        'Created by real Android integration',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('save-farm-button')));
      await tester.tap(find.byKey(const Key('save-farm-button')));
      await _settle(tester);
      expect(find.text('Green Valley Farm'), findsOneWidget);

      final greenCard = find.ancestor(
        of: find.text('Green Valley Farm'),
        matching: find.byType(InkWell),
      );
      await tester.tap(greenCard);
      await _settle(tester);
      expect(find.text('Farm Details'), findsOneWidget);
      expect(find.text('2.5 acres'), findsOneWidget);
      expect(find.text('6.927079'), findsOneWidget);
      expect(find.text('79.861244'), findsOneWidget);
      expect(find.text('Created by real Android integration'), findsOneWidget);

      final aTokens = await authService.login(
        email: _emailA,
        password: _password,
      );
      final aProfile = await authService.getCurrentUser(aTokens.accessToken);
      final restoredA = AuthSession(tokenStore: createAuthTokenStore());
      await restoredA.restore(authService);
      expect(restoredA.state, AuthSessionState.authenticated);
      expect(restoredA.profile?.id, registeredA.id);
      final aSession = AuthSession(tokenStore: MemoryAuthTokenStore());
      await aSession.establishVerified(aTokens, aProfile);
      final aFarmService = FarmService(
        apiClient: apiClient,
        session: aSession,
        authService: authService,
      );
      final aFarms = (await aFarmService.listFarms()).farms;
      expect(aFarms.map((farm) => farm.name), contains('Green Valley Farm'));
      expect(aFarms.single.userId, registeredA.id);

      await _popRoute(tester, 'Farm Details');
      await _popRoute(tester, 'My Farms');
      await _logout(tester);
      await _login(tester, _emailB);
      expect(find.text('Hello, Step 22 Android Farmer B'), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-farms-button')));
      await _settle(tester);
      expect(find.text('Green Valley Farm'), findsNothing);
      expect(find.byKey(const Key('farms-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-farm-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('farm-name-field')),
        'Hill Farm',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-farm-button')));
      await _settle(tester);
      expect(find.text('Hill Farm'), findsOneWidget);
      expect(find.text('Green Valley Farm'), findsNothing);

      final bTokens = await authService.login(
        email: _emailB,
        password: _password,
      );
      final bProfile = await authService.getCurrentUser(bTokens.accessToken);
      final bSession = AuthSession(tokenStore: MemoryAuthTokenStore());
      await bSession.establishVerified(bTokens, bProfile);
      final bFarmService = FarmService(
        apiClient: apiClient,
        session: bSession,
        authService: authService,
      );
      final bFarms = (await bFarmService.listFarms()).farms;
      expect(bFarms.map((farm) => farm.name), ['Hill Farm']);
      expect(bFarms.single.userId, registeredB.id);

      await _popRoute(tester, 'My Farms');
      await _logout(tester);
      expect(find.byKey(const Key('my-farms-button')), findsNothing);
      await _login(tester, _emailB);
      expect(find.text('Hello, Step 22 Android Farmer B'), findsOneWidget);
      await _logout(tester);
      await authService.logout(aSession.refreshToken!);
      await authService.logout(bSession.refreshToken!);
      await createAuthTokenStore().clearSession();
    } finally {
      apiClient.close();
    }
  });
}

Future<void> _login(WidgetTester tester, String email) async {
  await tester.ensureVisible(find.byKey(const Key('home-login')));
  await tester.tap(find.byKey(const Key('home-login')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-email-field')), email);
  await tester.enterText(
    find.byKey(const Key('login-password-field')),
    _password,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('login-submit')));
  await _settle(tester);
  expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
}

Future<void> _logout(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('logout-button')));
  await tester.tap(find.byKey(const Key('logout-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('logout-confirm')));
  await _settle(tester);
  expect(find.byKey(const Key('home-login')), findsOneWidget);
}

Future<void> _popRoute(WidgetTester tester, String appBarTitle) async {
  final title = find.text(appBarTitle);
  expect(title, findsOneWidget);
  Navigator.of(tester.element(title)).pop();
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 25),
);
