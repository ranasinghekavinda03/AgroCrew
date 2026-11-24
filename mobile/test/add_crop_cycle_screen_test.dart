import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/presentation/add_crop_cycle_screen.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:agrocrew/features/farms/presentation/my_farms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('synchronizes a verified async initial farm into form state', (
    tester,
  ) async {
    final remoteFarm = Completer<http.Response>();
    final posts = <Map<String, Object?>>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms/25') {
        return remoteFarm.future;
      }
      if (request.method == 'POST') {
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        posts.add(payload);
        return _jsonResponse(_cropFromPayload(payload, id: 25), status: 201);
      }
      return _jsonResponse(
        List.generate(20, (index) => _farm(index + 1, 'Farm')),
      );
    });
    await _pumpAdd(tester, fixture, initialFarmId: 25);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .state<FormFieldState<int>>(find.byKey(const Key('crop-farm-field')))
          .value,
      isNull,
    );
    remoteFarm.complete(_jsonResponse(_farm(25, 'Remote Farm')));
    await tester.pumpAndSettle();
    expect(find.text('Remote Farm (Farm #25)'), findsOneWidget);
    expect(
      tester
          .state<FormFieldState<int>>(find.byKey(const Key('crop-farm-field')))
          .value,
      25,
    );
    await _fillRequired(tester, selectFarm: false);
    await _tapCreate(tester);
    expect(posts, hasLength(1));
    expect(posts.single['farm_id'], 25);
  });

  testWidgets('requires an explicit farm when no initial filter is supplied', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => _jsonResponse([_farm(1, 'One')]),
    );
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _fillRequired(tester, selectFarm: false);
    await _tapCreate(tester);
    expect(find.text('Choose a farm.'), findsOneWidget);
  });

  testWidgets('cancel and back do not issue a POST', (tester) async {
    var posts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') posts++;
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-crop-cycle-button')));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(find.byType(AddCropCycleScreen), findsNothing);
  });

  testWidgets('no farms offers My Farms and reloads after returning', (
    tester,
  ) async {
    var listCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        listCalls++;
        return _jsonResponse(listCalls < 3 ? [] : [_farm(8, 'Created Farm')]);
      }
      return _jsonResponse({});
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    expect(
      find.text('Create a farm first before adding a crop cycle.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Go to My Farms'));
    await tester.pumpAndSettle();
    expect(find.byType(MyFarmsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-farm-field')));
    await tester.pumpAndSettle();
    expect(find.text('Created Farm (Farm #8)'), findsOneWidget);
  });

  testWidgets('loads later farm pages and disambiguates duplicate names', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      final offset = request.url.queryParameters['offset'];
      return offset == '0'
          ? _jsonResponse(
              List.generate(20, (index) => _farm(index + 1, 'Same')),
            )
          : _jsonResponse([_farm(21, 'Same')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-farms-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-farm-field')));
    await tester.pumpAndSettle();
    expect(find.text('Same (Farm #1)'), findsOneWidget);
    expect(find.text('Same (Farm #21)'), findsOneWidget);
  });

  testWidgets('farm metadata error is sanitized and retryable', (tester) async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      calls++;
      return calls == 1
          ? http.Response('{"detail":"private"}', 500)
          : _jsonResponse([_farm(1, 'Recovered')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-farms-error')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-farm-field')));
    await tester.pumpAndSettle();
    expect(find.text('Recovered (Farm #1)'), findsOneWidget);
  });

  testWidgets('unavailable initial farm clears visual and form state', (
    tester,
  ) async {
    final unavailable = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms/99') {
        return unavailable.future;
      }
      return _jsonResponse([_farm(1, 'Available'), _farm(99, 'Removed')]);
    });
    await _pumpAdd(tester, fixture, initialFarmId: 99);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .state<FormFieldState<int>>(find.byKey(const Key('crop-farm-field')))
          .value,
      99,
    );
    unavailable.complete(http.Response('{}', 404));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The selected farm is no longer available. Choose another farm.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .state<FormFieldState<int>>(find.byKey(const Key('crop-farm-field')))
          .value,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const Key('crop-farm-field')),
          )
          .initialValue,
      isNull,
    );
    expect(find.text('Removed (Farm #99)'), findsNothing);
  });

  testWidgets('validates required, calendar, ordering, count, and lengths', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => _jsonResponse([_farm(1, 'One')]),
    );
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)');
    await _enter(tester, const Key('crop-type-field'), '   ');
    await _enter(tester, const Key('planting-date-field'), '2025-02-29');
    await _enter(
      tester,
      const Key('expected-harvest-date-field'),
      '2025-02-28',
    );
    await _enter(tester, const Key('plant-count-field'), '-1.5');
    await _enter(tester, const Key('crop-variety-field'), 'v' * 129);
    await _enter(tester, const Key('crop-notes-field'), 'n' * 10001);
    await _tapCreate(tester);
    expect(find.text('Crop type is required.'), findsOneWidget);
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    expect(
      find.text('Plant count must be a positive whole number.'),
      findsOneWidget,
    );
    expect(
      find.text('Variety must be 128 characters or fewer.'),
      findsOneWidget,
    );
    expect(
      find.text('Notes must be 10000 characters or fewer.'),
      findsOneWidget,
    );
  });

  testWidgets('validates missing dates, ordering, and invalid count shapes', (
    tester,
  ) async {
    var posts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') posts++;
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)');
    await _enter(tester, const Key('crop-type-field'), 'c' * 129);
    await _tapCreate(tester);
    expect(
      find.text('Crop type must be 128 characters or fewer.'),
      findsOneWidget,
    );
    expect(find.text('Planting date is required.'), findsOneWidget);

    await _enter(tester, const Key('crop-type-field'), 'Rice');
    await _enter(tester, const Key('planting-date-field'), '2024-02-29');
    await _enter(
      tester,
      const Key('expected-harvest-date-field'),
      '2024-02-28',
    );
    for (final count in ['0', '-2', '1.5']) {
      await _enter(tester, const Key('plant-count-field'), count);
      await _tapCreate(tester);
      expect(
        find.text('Plant count must be a positive whole number.'),
        findsOneWidget,
      );
    }
    expect(
      find.text('Expected harvest cannot be before planting.'),
      findsOneWidget,
    );
    expect(posts, 0);
  });

  testWidgets('accepts exact variety and notes Unicode boundaries', (
    tester,
  ) async {
    Map<String, Object?>? payload;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') {
        payload = jsonDecode(request.body) as Map<String, Object?>;
        return _jsonResponse(_cropFromPayload(payload!, id: 45), status: 201);
      }
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _fillRequired(tester);
    await _enter(tester, const Key('crop-variety-field'), '🌾' * 128);
    await _enter(tester, const Key('crop-notes-field'), 'අ' * 10000);
    await _tapCreate(tester);
    await tester.pumpAndSettle();
    expect((payload!['variety']! as String).runes.length, 128);
    expect((payload!['notes']! as String).runes.length, 10000);
    expect(payload, isNot(contains('plant_count')));
    expect(payload, isNot(contains('expected_harvest_date')));
  });

  testWidgets(
    'accepts leap day, future planting, Unicode limits, and exact JSON',
    (tester) async {
      Map<String, Object?>? payload;
      var posts = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'POST') {
          posts++;
          payload = jsonDecode(request.body) as Map<String, Object?>;
          expect(request.url.path, '/api/v1/crops');
          expect(request.headers['authorization'], 'Bearer access');
          return _jsonResponse(_cropFromPayload(payload!, id: 44), status: 201);
        }
        return _jsonResponse([_farm(4, 'Unicode Farm')]);
      });
      await _pumpAdd(tester, fixture);
      await tester.pumpAndSettle();
      await _fillRequired(
        tester,
        farmLabel: 'Unicode Farm (Farm #4)',
        cropType: '🌱' * 128,
        plantingDate: '2032-02-29',
      );
      await _enter(tester, const Key('crop-variety-field'), '   ');
      await _enter(tester, const Key('plant-count-field'), '12');
      await _selectStatus(tester, 'Harvested');
      await _tapCreate(tester);
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(payload, {
        'farm_id': 4,
        'crop_type': '🌱' * 128,
        'planting_date': '2032-02-29',
        'status': 'harvested',
        'plant_count': 12,
      });
      expect(payload, isNot(contains('user_id')));
      expect(payload, isNot(contains('id')));
      expect(payload, isNot(contains('created_at')));
    },
  );

  for (final status in ['Planned', 'Active', 'Harvested', 'Cancelled']) {
    testWidgets('submits valid $status status', (tester) async {
      String? wireStatus;
      final fixture = await _fixture((request) async {
        if (request.method == 'POST') {
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          wireStatus = payload['status']! as String;
          return _jsonResponse(_cropFromPayload(payload, id: 3), status: 201);
        }
        return _jsonResponse([_farm(1, 'One')]);
      });
      await _pumpAdd(tester, fixture);
      await tester.pumpAndSettle();
      await _fillRequired(tester);
      await _selectStatus(tester, status);
      await _tapCreate(tester);
      await tester.pumpAndSettle();
      expect(wireStatus, status.toLowerCase());
    });
  }

  testWidgets('definite rejection remains actionable and can be corrected', (
    tester,
  ) async {
    var posts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') {
        posts++;
        return http.Response('{"detail":"private"}', posts == 1 ? 422 : 404);
      }
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _fillRequired(tester);
    await _tapCreate(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Please review the crop cycle information and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private'), findsNothing);
    await _tapCreate(tester);
    await tester.pumpAndSettle();
    expect(find.text('Crop cycle or farm not found.'), findsOneWidget);
  });

  for (final scenario in ['network', 'timeout', 'server', 'malformed']) {
    testWidgets('$scenario outcome is ambiguous and is never replayed', (
      tester,
    ) async {
      var posts = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'POST') {
          posts++;
          if (scenario == 'network') throw http.ClientException('private');
          if (scenario == 'timeout') {
            return Completer<http.Response>().future;
          }
          if (scenario == 'server') return http.Response('private', 500);
          return _jsonResponse({'id': 1}, status: 201);
        }
        return _jsonResponse([_farm(1, 'One')]);
      });
      await _pumpAdd(tester, fixture);
      await tester.pumpAndSettle();
      await _fillRequired(tester);
      await _tapCreate(tester);
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(
        find.byKey(const Key('inspect-crop-cycles-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('create-crop-cycle-button')), findsNothing);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
    });
  }

  testWidgets(
    'ambiguous create blocks cancel and back then returns uncertain result',
    (tester) async {
      var posts = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'POST') {
          posts++;
          return http.Response('private', 500);
        }
        return _jsonResponse([_farm(1, 'One')]);
      });
      await _pumpRoute(tester, fixture);
      await tester.tap(find.text('Open Add'));
      await tester.pumpAndSettle();
      await _fillRequired(tester);
      await _tapCreate(tester);

      expect(posts, 1);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('cancel-crop-cycle-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('cancel-crop-cycle-bottom-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AddCropCycleScreen), findsOneWidget);
      expect(posts, 1);

      final inspect = find.byKey(const Key('inspect-crop-cycles-button'));
      await tester.drag(
        find.byKey(const Key('add-crop-cycle-form')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(inspect);
      await tester.pumpAndSettle();
      expect(find.byType(AddCropCycleScreen), findsNothing);
      expect(find.text('Uncertain result'), findsOneWidget);
      expect(posts, 1);
    },
  );

  testWidgets('synchronous submit guard allows only one pending POST', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var posts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') {
        posts++;
        return response.future;
      }
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _fillRequired(tester);
    final button = find.byKey(const Key('create-crop-cycle-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(posts, 1);
    expect(find.text('Creating...'), findsOneWidget);
    response.complete(
      _jsonResponse(
        _cropFromPayload({
          'farm_id': 1,
          'crop_type': 'Tomato',
          'planting_date': '2030-01-02',
          'status': 'planned',
        }, id: 7),
        status: 201,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'logout during POST invalidates route and ignores delayed success',
    (tester) async {
      final response = Completer<http.Response>();
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/logout')) return http.Response('', 204);
        if (request.method == 'POST') return response.future;
        return _jsonResponse([_farm(1, 'One')]);
      });
      await _pumpRoute(tester, fixture);
      await tester.tap(find.text('Open Add'));
      await tester.pumpAndSettle();
      await _fillRequired(tester);
      await _tapCreate(tester, settle: false);
      await fixture.session.logout(fixture.auth);
      await tester.pumpAndSettle();
      expect(find.text('Open Add'), findsOneWidget);
      response.complete(http.Response('{}', 201));
      await tester.pumpAndSettle();
      expect(find.byType(AddCropCycleScreen), findsNothing);
    },
  );

  testWidgets('account replacement cannot confirm an old account POST', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') return response.future;
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Add'));
    await tester.pumpAndSettle();
    await _fillRequired(tester);
    await _tapCreate(tester, settle: false);
    await fixture.session.establishVerified(
      _tokens('replacement'),
      _profile(99),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open Add'), findsOneWidget);
    response.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
  });

  testWidgets('delayed completion after disposal causes no UI exception', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.method == 'POST') return response.future;
      return _jsonResponse([_farm(1, 'One')]);
    });
    await _pumpAdd(tester, fixture);
    await tester.pumpAndSettle();
    await _fillRequired(tester);
    await _tapCreate(tester, settle: false);
    await tester.pumpWidget(const MaterialApp(home: Text('Disposed')));
    response.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final configuration in <(Size, double)>[
    (const Size(320, 700), 1),
    (const Size(1600, 1000), 1),
    (const Size(900, 1400), 1.8),
  ]) {
    testWidgets(
      'form is responsive at ${configuration.$1} scale ${configuration.$2}',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = configuration.$2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = await _fixture(
          (request) async =>
              _jsonResponse([_farm(1, 'සිංහල தமிழ் English farm')]),
        );
        await _pumpAdd(tester, fixture, size: configuration.$1);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('add-crop-cycle-form')), findsOneWidget);
      },
    );
  }
}

Future<void> _fillRequired(
  WidgetTester tester, {
  bool selectFarm = true,
  String farmLabel = 'One (Farm #1)',
  String cropType = 'Tomato',
  String plantingDate = '2030-01-02',
}) async {
  if (selectFarm) await _selectFarm(tester, farmLabel);
  await _enter(tester, const Key('crop-type-field'), cropType);
  await _enter(tester, const Key('planting-date-field'), plantingDate);
}

Future<void> _selectFarm(WidgetTester tester, String label) async {
  final field = find.byKey(const Key('crop-farm-field'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _selectStatus(WidgetTester tester, String label) async {
  final field = find.byKey(const Key('crop-status-field'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _tapCreate(WidgetTester tester, {bool settle = true}) async {
  final button = find.byKey(const Key('create-crop-cycle-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpAdd(
  WidgetTester tester,
  _Fixture fixture, {
  int? initialFarmId,
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push<AddCropCycleResult>(
              MaterialPageRoute(
                builder: (_) => AddCropCycleScreen(
                  cropCycleService: fixture.crops,
                  farmService: fixture.farms,
                  session: fixture.session,
                  initialFarmId: initialFarmId,
                ),
              ),
            ),
            child: const Text('Open Add'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Add'));
  await tester.pump();
}

Future<void> _pumpRoute(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(MaterialApp(home: _AddRouteHost(fixture: fixture)));
}

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 20, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(milliseconds: 100),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(_tokens('access'), _profile(7));
  return _Fixture(
    auth: auth,
    session: session,
    crops: CropCycleService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
    farms: FarmService(apiClient: client, session: session, authService: auth),
  );
}

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'refresh-$access',
  issuedAt: DateTime.utc(2026, 11, 20, 12),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

UserProfile _profile(int id) => UserProfile(
  id: id,
  name: 'Farmer $id',
  email: 'farmer$id@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

Map<String, Object?> _farm(int id, String name) => {
  'id': id,
  'user_id': 7,
  'name': name,
  'latitude': null,
  'longitude': null,
  'area_value': null,
  'area_unit': null,
  'notes': null,
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T11:00:00Z',
};

Map<String, Object?> _cropFromPayload(
  Map<String, Object?> payload, {
  required int id,
}) => {
  'id': id,
  'farm_id': payload['farm_id'],
  'crop_type': payload['crop_type'],
  'variety': payload['variety'],
  'planting_date': payload['planting_date'],
  'expected_harvest_date': payload['expected_harvest_date'],
  'status': payload['status'],
  'plant_count': payload['plant_count'],
  'notes': payload['notes'],
  'created_at': '2026-11-20T10:00:00Z',
  'updated_at': '2026-11-20T10:00:00Z',
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _Fixture {
  const _Fixture({
    required this.auth,
    required this.session,
    required this.crops,
    required this.farms,
  });

  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
  final FarmService farms;
}

class _AddRouteHost extends StatefulWidget {
  const _AddRouteHost({required this.fixture});

  final _Fixture fixture;

  @override
  State<_AddRouteHost> createState() => _AddRouteHostState();
}

class _AddRouteHostState extends State<_AddRouteHost> {
  AddCropCycleResult? _result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<AddCropCycleResult>(
                    MaterialPageRoute(
                      builder: (_) => AddCropCycleScreen(
                        cropCycleService: widget.fixture.crops,
                        farmService: widget.fixture.farms,
                        session: widget.fixture.session,
                      ),
                    ),
                  );
              if (mounted) setState(() => _result = result);
            },
            child: const Text('Open Add'),
          ),
          if (_result?.uncertain == true) const Text('Uncertain result'),
        ],
      ),
    ),
  );
}
