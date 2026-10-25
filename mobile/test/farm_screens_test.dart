import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:agrocrew/features/farms/presentation/add_farm_screen.dart';
import 'package:agrocrew/features/farms/presentation/edit_farm_screen.dart';
import 'package:agrocrew/features/farms/presentation/farm_details_screen.dart';
import 'package:agrocrew/features/farms/presentation/my_farms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('My Farms shows loading then successful empty state', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final fixture = await _fixture((_) => response.future);
    await _pumpFarms(tester, fixture);
    expect(find.byKey(const Key('farms-loading')), findsOneWidget);
    response.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farms-empty')), findsOneWidget);
    expect(find.text('Manage your farming locations.'), findsOneWidget);
    expect(find.text("You haven't added any farms yet."), findsOneWidget);
  });

  testWidgets('My Farms displays returned farms without fake fields', (
    tester,
  ) async {
    final fixture = await _fixture(
      (_) async => http.Response(jsonEncode([_farm(1)]), 200),
    );
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.text('Green Valley Farm'), findsOneWidget);
    expect(find.text('Area: 2.5 acres'), findsOneWidget);
    expect(find.text('Location: Available'), findsOneWidget);
    expect(find.textContaining('Weather'), findsNothing);
  });

  testWidgets('error state retries and loads farms', (tester) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      return calls == 1
          ? http.Response('{"detail":"error"}', 500)
          : http.Response('[]', 200);
    });
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farms-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farms-empty')), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('refresh action reloads the list', (tester) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      return http.Response(calls == 1 ? '[]' : jsonEncode([_farm(2)]), 200);
    });
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farms-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Green Valley Farm'), findsOneWidget);
  });

  testWidgets('farm card opens API-backed details', (tester) async {
    final fixture = await _fixture((request) async {
      return http.Response(
        request.url.path == '/api/v1/farms'
            ? jsonEncode([_farm(4)])
            : jsonEncode(_farm(4)),
        200,
      );
    });
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-card-4')));
    await tester.pumpAndSettle();
    expect(find.text('Farm Details'), findsOneWidget);
    expect(find.byKey(const Key('farm-details-content')), findsOneWidget);
    expect(find.text('Near the river'), findsOneWidget);
  });

  testWidgets('details displays 404 safely and supports Retry', (tester) async {
    final fixture = await _fixture(
      (_) async => http.Response('{"detail":"hidden"}', 404),
    );
    await _pump(
      tester,
      FarmDetailsScreen(farmId: 99, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    expect(find.text('Farm not found.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Add Farm renders every requested field', (tester) async {
    final fixture = await _fixture((_) async => http.Response('{}', 500));
    await _pump(tester, AddFarmScreen(farmService: fixture.service));
    for (final key in [
      'farm-name-field',
      'farm-area-field',
      'farm-area-unit-field',
      'farm-latitude-field',
      'farm-longitude-field',
      'farm-notes-field',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.byKey(const Key('save-farm-button')), findsOneWidget);
  });

  testWidgets('Save remains disabled until a name is entered', (tester) async {
    final fixture = await _fixture((_) async => http.Response('{}', 500));
    await _pump(tester, AddFarmScreen(farmService: fixture.service));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-farm-button')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('farm-name-field')), 'Farm');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-farm-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('form rejects invalid area and coordinates', (tester) async {
    final fixture = await _fixture((_) async => http.Response('{}', 500));
    await _pump(tester, AddFarmScreen(farmService: fixture.service));
    await tester.enterText(find.byKey(const Key('farm-name-field')), 'Farm');
    await tester.enterText(find.byKey(const Key('farm-area-field')), '0');
    await tester.enterText(
      find.byKey(const Key('farm-latitude-field')),
      '90.1',
    );
    await tester.enterText(
      find.byKey(const Key('farm-longitude-field')),
      '-180.1',
    );
    await tester.tap(find.byKey(const Key('save-farm-button')));
    await tester.pump();
    expect(find.text('Area must be greater than zero.'), findsOneWidget);
    expect(find.textContaining('Latitude must be between'), findsOneWidget);
    expect(find.textContaining('Longitude must be between'), findsOneWidget);
  });

  testWidgets('duplicate Save is prevented while POST is pending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var calls = 0;
    final fixture = await _fixture((_) {
      calls += 1;
      return response.future;
    });
    await _pump(tester, AddFarmScreen(farmService: fixture.service));
    await tester.enterText(find.byKey(const Key('farm-name-field')), 'Farm');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-farm-button')));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-farm-button')))
          .onPressed,
      isNull,
    );
    expect(calls, 1);
    response.complete(http.Response(jsonEncode(_farm(8)), 201));
    await tester.pumpAndSettle();
  });

  testWidgets('successful creation returns and refreshes My Farms', (
    tester,
  ) async {
    var listCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') {
        return http.Response(jsonEncode(_farm(10)), 201);
      }
      listCalls += 1;
      return http.Response(
        listCalls == 1 ? '[]' : jsonEncode([_farm(10)]),
        200,
      );
    });
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-farm-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('farm-name-field')),
      'Green Valley Farm',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-farm-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-card-10')), findsOneWidget);
  });

  testWidgets('Edit Farm loads and prefills every current value', (
    tester,
  ) async {
    final fixture = await _fixture(
      (_) async => http.Response(jsonEncode(_farm(4)), 200),
    );
    await _pump(
      tester,
      EditFarmScreen(farmId: 4, farmService: fixture.service),
    );
    expect(find.byKey(const Key('edit-farm-loading')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Update your farming location details.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('edit-farm-name-field')))
          .controller!
          .text,
      'Green Valley Farm',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('edit-farm-area-field')))
          .controller!
          .text,
      '2.5',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('edit-farm-notes-field')))
          .controller!
          .text,
      'Near the river',
    );
  });

  testWidgets('editing refreshes Farm Details with the server response', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Green Valley Organic Farm');
        expect(body['latitude'], 6.927079);
        expect(body['area_unit'], 'acres');
        return http.Response(
          jsonEncode({..._farm(4), 'name': 'Green Valley Organic Farm'}),
          200,
        );
      }
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      FarmDetailsScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-farm-button')));
    await tester.tap(find.byKey(const Key('edit-farm-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-farm-name-field')),
      'Green Valley Organic Farm',
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-farm-changes-button')),
    );
    await tester.tap(find.byKey(const Key('save-farm-changes-button')));
    await tester.pumpAndSettle();
    expect(find.text('Green Valley Organic Farm'), findsOneWidget);
    expect(find.text('Farm updated successfully.'), findsOneWidget);
  });

  testWidgets('Edit Farm validates fields and preserves entered values', (
    tester,
  ) async {
    var puts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') puts += 1;
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      EditFarmScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-farm-name-field')), ' ');
    await tester.enterText(find.byKey(const Key('edit-farm-area-field')), '0');
    await tester.enterText(
      find.byKey(const Key('edit-farm-latitude-field')),
      '91',
    );
    await tester.enterText(
      find.byKey(const Key('edit-farm-longitude-field')),
      '-181',
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-farm-changes-button')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('save-farm-changes-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('edit-farm-name-field')),
      'Still Entered',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-farm-changes-button')));
    await tester.pump();
    expect(find.text('Area must be greater than zero.'), findsOneWidget);
    expect(find.textContaining('Latitude must be between'), findsOneWidget);
    expect(find.textContaining('Longitude must be between'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('edit-farm-name-field')))
          .controller!
          .text,
      'Still Entered',
    );
    expect(puts, 0);
  });

  testWidgets('Edit Farm prevents duplicate Save while PUT is pending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var puts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') {
        puts += 1;
        return response.future;
      }
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      EditFarmScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('save-farm-changes-button')),
    );
    await tester.tap(find.byKey(const Key('save-farm-changes-button')));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(puts, 1);
    response.complete(http.Response(jsonEncode(_farm(4)), 200));
    await tester.pumpAndSettle();
  });

  testWidgets('delete confirmation Cancel sends no DELETE', (tester) async {
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') deletes += 1;
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      FarmDetailsScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-farm-button')));
    await tester.tap(find.byKey(const Key('delete-farm-button')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Farm?'), findsOneWidget);
    expect(find.textContaining('"Green Valley Farm"'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-farm-cancel')));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.byType(FarmDetailsScreen), findsOneWidget);
  });

  testWidgets('confirmed deletion removes only that farm and refreshes list', (
    tester,
  ) async {
    var listCalls = 0;
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        deletes += 1;
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/farms') {
        listCalls += 1;
        return http.Response(
          jsonEncode(
            listCalls == 1
                ? [
                    _farm(4),
                    {..._farm(5), 'name': 'Hill Farm'},
                  ]
                : [
                    {..._farm(5), 'name': 'Hill Farm'},
                  ],
          ),
          200,
        );
      }
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pumpFarms(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-card-4')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-farm-button')));
    await tester.tap(find.byKey(const Key('delete-farm-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-farm-confirm')));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.byKey(const Key('farm-card-4')), findsNothing);
    expect(find.text('Hill Farm'), findsOneWidget);
    expect(find.text('Farm deleted successfully.'), findsOneWidget);
    expect(fixture.session.state, AuthSessionState.authenticated);
  });

  testWidgets('delete conflict keeps Farm Details visible', (tester) async {
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        return http.Response('{"detail":"constraint"}', 409);
      }
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      FarmDetailsScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-farm-button')));
    await tester.tap(find.byKey(const Key('delete-farm-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-farm-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(FarmDetailsScreen), findsOneWidget);
    expect(
      find.text('This farm cannot be deleted because it has related records.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed deletion cannot be submitted twice', (tester) async {
    final response = Completer<http.Response>();
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        deletes += 1;
        return response.future;
      }
      return http.Response(jsonEncode(_farm(4)), 200);
    });
    await _pump(
      tester,
      FarmDetailsScreen(farmId: 4, farmService: fixture.service),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-farm-button')));
    await tester.tap(find.byKey(const Key('delete-farm-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-farm-confirm')));
    await tester.pump();
    expect(find.text('Deleting...'), findsOneWidget);
    expect(deletes, 1);
    response.complete(http.Response('', 204));
    await tester.pumpAndSettle();
  });

  testWidgets('logout clears a protected farm screen', (tester) async {
    final fixture = await _fixture((request) async {
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      return http.Response('[]', 200);
    });
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Profile')),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => MyFarmsScreen(
          farmService: fixture.service,
          session: fixture.session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await fixture.session.logout(fixture.authService);
    await tester.pumpAndSettle();
    expect(find.byType(MyFarmsScreen), findsNothing);
  });
}

Future<void> _pumpFarms(WidgetTester tester, _Fixture fixture) => _pump(
  tester,
  MyFarmsScreen(farmService: fixture.service, session: fixture.session),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
}

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 10, 24, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(seconds: 1),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(
    LoginResponse(
      accessToken: 'access',
      refreshToken: 'refresh',
      issuedAt: now,
      expiresIn: const Duration(minutes: 30),
      refreshExpiresIn: const Duration(days: 7),
    ),
    UserProfile(
      id: 7,
      name: 'Farmer',
      email: 'farmer@example.com',
      preferredLanguage: 'English',
      isActive: true,
      createdAt: now,
    ),
  );
  return _Fixture(
    service: FarmService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
    session: session,
    authService: auth,
  );
}

Map<String, Object?> _farm(int id) => {
  'id': id,
  'user_id': 7,
  'name': 'Green Valley Farm',
  'latitude': 6.927079,
  'longitude': 79.861244,
  'area_value': 2.5,
  'area_unit': 'acres',
  'notes': 'Near the river',
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T11:00:00Z',
};

class _Fixture {
  const _Fixture({
    required this.service,
    required this.session,
    required this.authService,
  });
  final FarmService service;
  final AuthSession session;
  final AuthService authService;
}
