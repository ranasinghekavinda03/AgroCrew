import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/auth/presentation/authenticated_profile_screen.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/presentation/my_crop_cycles_screen.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('authenticated CropCycle CRUD navigation uses one mutation each', (
    tester,
  ) async {
    final transport = _CrudTransport();
    final fixture = await _fixture(transport.handle);
    addTearDown(fixture.close);
    await _pumpProfile(tester, fixture);

    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-crop-cycles-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(
      find.byKey(const Key('crop-cycle-card-21')),
      findsOneWidget,
      reason:
          'requests=${transport.requests}; '
          'texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
    );

    await _select(
      tester,
      const Key('crop-cycles-farm-filter'),
      'South Farm (Farm #2)',
    );
    expect(transport.lastCropQuery['farm_id'], '2');
    await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
    await tester.pumpAndSettle();
    expect(find.text('Add Crop Cycle'), findsWidgets);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const Key('crop-farm-field')),
          )
          .initialValue,
      2,
    );
    await _enter(tester, const Key('crop-type-field'), 'Chilli · மிளகாய் 🌱');
    await _enter(tester, const Key('crop-variety-field'), 'Kochchi');
    await _enter(tester, const Key('planting-date-field'), '2026-11-26');
    await _enter(
      tester,
      const Key('expected-harvest-date-field'),
      '2027-02-01',
    );
    await _enter(tester, const Key('plant-count-field'), '40');
    await _enter(tester, const Key('crop-notes-field'), 'සිංහල Tamil English');
    await _tapVisible(tester, const Key('create-crop-cycle-button'));
    await tester.pumpAndSettle();

    expect(transport.posts, 1);
    expect(transport.authorizations, everyElement('Bearer synthetic-access'));
    expect(transport.postBodies.single['farm_id'], 2);
    expect(transport.postBodies.single['planting_date'], '2026-11-26');
    expect(find.byKey(const Key('crop-cycle-card-22')), findsOneWidget);
    expect(_farmFilterValue(tester), 2);

    await tester.tap(find.byKey(const Key('open-crop-cycle-22')));
    await tester.pumpAndSettle();
    expect(find.text('Crop Cycle Details'), findsOneWidget);
    expect(find.text('Chilli · மிளகாய் 🌱'), findsOneWidget);
    expect(find.text('South Farm (Farm #2)'), findsOneWidget);
    await _assertVisibleText(tester, '2026-11-26');
    final detailGetsBeforeRefresh = transport.detailGets;
    await tester.tap(find.byKey(const Key('crop-cycle-details-refresh')));
    await tester.pumpAndSettle();
    expect(transport.detailGets, detailGetsBeforeRefresh + 1);

    await _tapVisible(tester, const Key('edit-crop-cycle-button'));
    await tester.pumpAndSettle();
    expect(
      _fieldText(tester, const Key('edit-crop-type-field')),
      contains('Chilli'),
    );
    expect(find.text('South Farm (Farm #2)'), findsOneWidget);
    await _enter(tester, const Key('edit-crop-type-field'), 'Updated Chilli');
    await _enter(tester, const Key('edit-crop-variety-field'), '');
    await _enter(tester, const Key('edit-expected-harvest-date-field'), '');
    await _enter(tester, const Key('edit-plant-count-field'), '');
    await _enter(tester, const Key('edit-crop-notes-field'), '');
    await _tapVisible(tester, const Key('save-crop-cycle-changes-button'));
    await tester.pumpAndSettle();

    expect(transport.puts, 1);
    final update = transport.putBodies.single;
    expect(update['variety'], isNull);
    expect(update['expected_harvest_date'], isNull);
    expect(update['plant_count'], isNull);
    expect(update['notes'], isNull);
    expect(update, isNot(contains('farm_id')));
    expect(find.text('Updated Chilli'), findsOneWidget);

    await _tapVisible(tester, const Key('delete-crop-cycle-button'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-cancel')));
    await tester.pumpAndSettle();
    expect(transport.deletes, 0);
    await _tapVisible(tester, const Key('delete-crop-cycle-button'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-confirm')));
    await tester.pumpAndSettle();

    expect(transport.deletes, 1);
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(_farmFilterValue(tester), 2);
    expect(find.byKey(const Key('crop-cycle-card-22')), findsNothing);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination deduplicates overlaps and preserves filtering', (
    tester,
  ) async {
    final transport = _PaginationTransport();
    final fixture = await _fixture(transport.handle);
    addTearDown(fixture.close);
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
    final cropScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: cropScrollable,
    );
    await tester.drag(cropScrollable, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(transport.cropOffsets, containsAllInOrder(['0', '20']));

    await _select(
      tester,
      const Key('crop-cycles-farm-filter'),
      'South Farm (Farm #2)',
    );
    expect(transport.lastFarmId, '2');
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(transport.lastFarmId, '2');
    await _select(tester, const Key('crop-cycles-farm-filter'), 'All Farms');
    expect(transport.lastFarmId, isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpProfile(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AuthenticatedProfileScreen(
        authService: fixture.auth,
        session: fixture.session,
        featureApiClient: fixture.client,
      ),
    ),
  );
}

Future<void> _pumpCrops(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MyCropCyclesScreen(
        cropCycleService: fixture.crops,
        farmService: fixture.farms,
        session: fixture.session,
      ),
    ),
  );
}

Future<void> _select(WidgetTester tester, Key key, String label) async {
  final field = find.byKey(key);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key);
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
}

Future<void> _assertVisibleText(WidgetTester tester, String value) async {
  final text = find.text(value);
  if (text.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      text,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  expect(text, findsOneWidget);
}

String _fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextFormField>(find.byKey(key)).controller!.text;

int? _farmFilterValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )
    .initialValue;

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 26, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(seconds: 2),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(
    LoginResponse(
      accessToken: 'synthetic-access',
      refreshToken: 'synthetic-refresh',
      issuedAt: now,
      expiresIn: const Duration(minutes: 30),
      refreshExpiresIn: const Duration(days: 7),
    ),
    UserProfile(
      id: 7,
      name: 'Integration Farmer',
      email: 'integration@example.test',
      preferredLanguage: 'English',
      isActive: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return _Fixture(
    client: client,
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

class _CrudTransport {
  final List<String> requests = [];
  final List<String?> authorizations = [];
  final List<Map<String, Object?>> postBodies = [];
  final List<Map<String, Object?>> putBodies = [];
  final List<Map<String, Object?>> crops = [
    _crop(21, cropType: 'Tomato', variety: 'Roma'),
  ];
  Map<String, String> lastCropQuery = const {};
  int posts = 0;
  int puts = 0;
  int deletes = 0;
  int detailGets = 0;

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url}');
    authorizations.add(
      request.headers['authorization'] ?? request.headers['Authorization'],
    );
    final path = request.url.path;
    if (path == '/api/v1/farms') return _json([_farm(2, 'South Farm')]);
    if (path == '/api/v1/farms/2') return _json(_farm(2, 'South Farm'));
    if (path == '/api/v1/crops' && request.method == 'GET') {
      lastCropQuery = request.url.queryParameters;
      final farmId = int.tryParse(request.url.queryParameters['farm_id'] ?? '');
      return _json(
        crops
            .where((crop) => farmId == null || crop['farm_id'] == farmId)
            .toList(),
      );
    }
    if (path == '/api/v1/crops' && request.method == 'POST') {
      posts++;
      final body = _body(request);
      postBodies.add(body);
      final created = _cropFromBody(22, body);
      crops.add(created);
      return _json(created, status: 201);
    }
    if (path == '/api/v1/crops/22' && request.method == 'GET') {
      detailGets++;
      return _json(crops.singleWhere((crop) => crop['id'] == 22));
    }
    if (path == '/api/v1/crops/22' && request.method == 'PUT') {
      puts++;
      final body = _body(request);
      putBodies.add(body);
      final index = crops.indexWhere((crop) => crop['id'] == 22);
      crops[index] = {
        ...crops[index],
        ...body,
        'id': 22,
        'farm_id': 2,
        'updated_at': '2026-11-26T13:00:00Z',
      };
      return _json(crops[index]);
    }
    if (path == '/api/v1/crops/22' && request.method == 'DELETE') {
      deletes++;
      crops.removeWhere((crop) => crop['id'] == 22);
      return http.Response('', 204);
    }
    return http.Response('{}', 404);
  }
}

class _PaginationTransport {
  final List<String> cropOffsets = [];
  String? lastFarmId;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/api/v1/farms') {
      return _json([_farm(2, 'South Farm')]);
    }
    if (request.url.path == '/api/v1/crops') {
      final offset = request.url.queryParameters['offset']!;
      cropOffsets.add(offset);
      lastFarmId = request.url.queryParameters['farm_id'];
      if (lastFarmId != null) return _json([_crop(2)]);
      if (offset == '0') {
        return _json(List.generate(20, (index) => _crop(index + 1)));
      }
      if (offset == '20') return _json([_crop(20), _crop(21)]);
      return _json([]);
    }
    return http.Response('{}', 404);
  }
}

Map<String, Object?> _body(http.Request request) =>
    (jsonDecode(request.body) as Map<String, dynamic>).cast<String, Object?>();

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

Map<String, Object?> _crop(
  int id, {
  String cropType = 'Crop',
  String? variety,
}) => {
  'id': id,
  'farm_id': 2,
  'crop_type': '$cropType $id',
  'variety': variety,
  'planting_date': '2026-11-03',
  'expected_harvest_date': '2027-01-10',
  'status': 'active',
  'plant_count': 25,
  'notes': 'Synthetic integration fixture',
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:00:00Z',
};

Map<String, Object?> _cropFromBody(int id, Map<String, Object?> body) => {
  'id': id,
  ...body,
  'created_at': '2026-11-26T12:00:00Z',
  'updated_at': '2026-11-26T12:00:00Z',
};

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  const _Fixture({
    required this.client,
    required this.auth,
    required this.session,
    required this.crops,
    required this.farms,
  });

  final ApiClient client;
  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
  final FarmService farms;

  void close() {
    session.dispose();
    client.close();
  }
}
