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
const _phase = String.fromEnvironment('INTEGRATION_MUTATION_PHASE');
const _password = 'DisposableStep23Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Android Farm update, restart, isolation, and deletion', (
    tester,
  ) async {
    expect(_emailA, isNotEmpty);
    expect(_emailB, isNotEmpty);
    expect(_phase, anyOf('prepare', 'verify', 'verify-login'));
    final apiClient = ApiClient();
    final authService = AuthService(apiClient);

    try {
      if (_phase == 'prepare') {
        await createAuthTokenStore().clearSession();
        await authService.register(
          name: 'Step 23 Android Farmer A',
          email: _emailA,
          password: _password,
        );
        await authService.register(
          name: 'Step 23 Android Farmer B',
          email: _emailB,
          password: _password,
        );
      } else if (_phase == 'verify-login') {
        await createAuthTokenStore().clearSession();
      }

      app.main();
      await _settle(tester);

      if (_phase == 'prepare') {
        await _login(tester, _emailA);
        await _openMyFarms(tester);
        await _addFarm(
          tester,
          name: 'Green Valley Farm',
          area: '2.5',
          notes: 'Original Android note',
        );

        final aFixture = await _authenticatedFixture(
          apiClient,
          authService,
          _emailA,
        );
        final original = (await aFixture.listFarms()).farms.single;

        await _openFarm(tester, 'Green Valley Farm');
        await tester.ensureVisible(find.byKey(const Key('edit-farm-button')));
        await tester.tap(find.byKey(const Key('edit-farm-button')));
        await _settle(tester);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('edit-farm-name-field')),
              )
              .controller!
              .text,
          'Green Valley Farm',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('edit-farm-area-field')),
              )
              .controller!
              .text,
          '2.5',
        );
        await tester.enterText(
          find.byKey(const Key('edit-farm-name-field')),
          'Green Valley Organic Farm',
        );
        await tester.enterText(
          find.byKey(const Key('edit-farm-area-field')),
          '3.5',
        );
        await tester.enterText(
          find.byKey(const Key('edit-farm-notes-field')),
          'Updated vegetable cultivation area',
        );
        await tester.ensureVisible(
          find.byKey(const Key('save-farm-changes-button')),
        );
        await tester.tap(find.byKey(const Key('save-farm-changes-button')));
        await _settle(tester);
        expect(find.text('Green Valley Organic Farm'), findsOneWidget);
        expect(find.text('3.5 acres'), findsOneWidget);
        expect(find.text('Updated vegetable cultivation area'), findsOneWidget);

        final updated = await aFixture.getFarm(original.id);
        expect(updated.name, 'Green Valley Organic Farm');
        expect(updated.areaValue, 3.5);
        expect(updated.userId, original.userId);
        expect(updated.createdAt, original.createdAt);

        await _pop(tester);
        expect(find.text('Green Valley Organic Farm'), findsOneWidget);
        await _returnToProfile(tester);
        await _logout(tester);

        await _login(tester, _emailB);
        await _openMyFarms(tester);
        expect(find.text('Green Valley Organic Farm'), findsNothing);
        await _addFarm(tester, name: 'Hill Farm');
        final bFixture = await _authenticatedFixture(
          apiClient,
          authService,
          _emailB,
        );
        await expectLater(
          bFixture.getFarm(original.id),
          throwsA(
            isA<FarmException>().having(
              (error) => error.type,
              'type',
              FarmFailureType.notFound,
            ),
          ),
        );
        await _returnToProfile(tester);
        await _logout(tester);

        await _login(tester, _emailA);
        expect(find.text('Hello, Step 23 Android Farmer A'), findsOneWidget);
      } else {
        if (_phase == 'verify-login') {
          await _login(tester, _emailA);
        }
        expect(find.text('Hello, Step 23 Android Farmer A'), findsOneWidget);
        await _openMyFarms(tester);
        expect(find.text('Green Valley Organic Farm'), findsOneWidget);
        await _openFarm(tester, 'Green Valley Organic Farm');
        expect(find.text('3.5 acres'), findsOneWidget);
        expect(find.text('Updated vegetable cultivation area'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('delete-farm-button')));
        await tester.tap(find.byKey(const Key('delete-farm-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete-farm-cancel')));
        await tester.pumpAndSettle();
        expect(find.text('Green Valley Organic Farm'), findsOneWidget);

        await tester.tap(find.byKey(const Key('delete-farm-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete-farm-confirm')));
        await _settle(tester);
        expect(find.byKey(const Key('farms-empty')), findsOneWidget);
        expect(find.text('Farm deleted successfully.'), findsOneWidget);

        final aFixture = await _authenticatedFixture(
          apiClient,
          authService,
          _emailA,
        );
        expect((await aFixture.listFarms()).farms, isEmpty);
        await _returnToProfile(tester);
        await _logout(tester);

        await _login(tester, _emailB);
        await _openMyFarms(tester);
        expect(find.text('Hill Farm'), findsOneWidget);
        expect(find.text('Green Valley Organic Farm'), findsNothing);
        final bFixture = await _authenticatedFixture(
          apiClient,
          authService,
          _emailB,
        );
        expect((await bFixture.listFarms()).farms.single.name, 'Hill Farm');
        await _returnToProfile(tester);
        await _logout(tester);
        await createAuthTokenStore().clearSession();
      }
    } finally {
      apiClient.close();
    }
  });
}

Future<FarmService> _authenticatedFixture(
  ApiClient apiClient,
  AuthService authService,
  String email,
) async {
  final tokens = await authService.login(email: email, password: _password);
  final profile = await authService.getCurrentUser(tokens.accessToken);
  final session = AuthSession(tokenStore: MemoryAuthTokenStore());
  await session.establishVerified(tokens, profile);
  return FarmService(
    apiClient: apiClient,
    session: session,
    authService: authService,
  );
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

Future<void> _openMyFarms(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('my-farms-button')));
  await _settle(tester);
}

Future<void> _addFarm(
  WidgetTester tester, {
  required String name,
  String? area,
  String? notes,
}) async {
  await tester.tap(find.byKey(const Key('add-farm-button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('farm-name-field')), name);
  if (area != null) {
    await tester.enterText(find.byKey(const Key('farm-area-field')), area);
    await tester.enterText(
      find.byKey(const Key('farm-area-unit-field')),
      'acres',
    );
  }
  if (notes != null) {
    await tester.enterText(find.byKey(const Key('farm-notes-field')), notes);
  }
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('save-farm-button')));
  await tester.tap(find.byKey(const Key('save-farm-button')));
  await _settle(tester);
  expect(find.text(name), findsOneWidget);
  expect(
    find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
    findsOneWidget,
  );
}

Future<void> _openFarm(WidgetTester tester, String name) async {
  final card = find.ancestor(
    of: find.text(name),
    matching: find.byType(InkWell),
  );
  await tester.tap(card);
  await _settle(tester);
  expect(find.text('Farm Details'), findsOneWidget);
}

Future<void> _pop(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
  await _settle(tester);
}

Future<void> _returnToProfile(WidgetTester tester) async {
  Navigator.of(
    tester.element(find.byType(Scaffold).last),
    rootNavigator: true,
  ).popUntil((route) => route.isFirst);
  await _settle(tester);
  expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 25),
);
