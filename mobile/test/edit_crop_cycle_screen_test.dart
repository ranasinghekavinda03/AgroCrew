import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/data/models/crop_cycle.dart';
import 'package:agrocrew/features/crops/presentation/edit_crop_cycle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('prepopulates every field and displays a read-only farm', (
    tester,
  ) async {
    final fixture = await _fixture((_) async => http.Response('{}', 500));
    await _pumpEdit(tester, fixture, crop: _cropModel());

    expect(_text(tester, const Key('edit-crop-type-field')), 'Tomato');
    expect(_text(tester, const Key('edit-crop-variety-field')), 'Roma');
    expect(_text(tester, const Key('edit-planting-date-field')), '2026-11-03');
    expect(
      _text(tester, const Key('edit-expected-harvest-date-field')),
      '2027-01-10',
    );
    expect(_text(tester, const Key('edit-plant-count-field')), '25');
    expect(_text(tester, const Key('edit-crop-notes-field')), 'Original');
    expect(find.text('Demo Farm (Farm #4)'), findsOneWidget);
    expect(find.byKey(const Key('edit-crop-farm-read-only')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
  });

  testWidgets('sends exact full replacement with cleared nullable fields', (
    tester,
  ) async {
    Map<String, Object?>? payload;
    var puts = 0;
    final fixture = await _fixture((request) async {
      expect(request.url.path, '/api/v1/crops/8');
      expect(request.headers['authorization'], 'Bearer access');
      expect(request.method, 'PUT');
      puts++;
      payload = jsonDecode(request.body) as Map<String, Object?>;
      return _jsonResponse(
        _cropJson(
          cropType: 'Rice',
          variety: null,
          plantingDate: '2032-02-29',
          expectedHarvestDate: null,
          status: 'harvested',
          plantCount: null,
          notes: null,
        ),
      );
    });
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _enter(tester, const Key('edit-crop-type-field'), ' Rice ');
    await _enter(tester, const Key('edit-crop-variety-field'), '');
    await _enter(tester, const Key('edit-planting-date-field'), '2032-02-29');
    await _enter(tester, const Key('edit-expected-harvest-date-field'), '');
    await _selectStatus(tester, 'Harvested');
    await _enter(tester, const Key('edit-plant-count-field'), '');
    await _enter(tester, const Key('edit-crop-notes-field'), '   ');
    await _tapSave(tester);

    expect(puts, 1);
    expect(payload, {
      'crop_type': 'Rice',
      'variety': null,
      'planting_date': '2032-02-29',
      'expected_harvest_date': null,
      'status': 'harvested',
      'plant_count': null,
      'notes': null,
    });
    for (final forbidden in [
      'farm_id',
      'user_id',
      'id',
      'created_at',
      'updated_at',
    ]) {
      expect(payload, isNot(contains(forbidden)));
    }
    expect(find.text('Confirmed result'), findsOneWidget);
  });

  for (final status in ['Planned', 'Active', 'Harvested', 'Cancelled']) {
    testWidgets('submits supported $status status', (tester) async {
      String? wireStatus;
      final fixture = await _fixture((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        wireStatus = body['status'] as String;
        return _jsonResponse(
          _cropJson(status: wireStatus!, expectedHarvestDate: '2027-01-10'),
        );
      });
      await _pumpHost(tester, fixture);
      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();
      await _selectStatus(tester, status);
      await _tapSave(tester);
      expect(wireStatus, status.toLowerCase());
    });
  }

  testWidgets('validation rejects bad dates, count, and Unicode limits', (
    tester,
  ) async {
    var puts = 0;
    final fixture = await _fixture((_) async {
      puts++;
      return _jsonResponse(_cropJson());
    });
    await _pumpEdit(tester, fixture, crop: _cropModel());
    await _enter(tester, const Key('edit-crop-type-field'), ' ');
    await _enter(tester, const Key('edit-crop-variety-field'), '🌾' * 129);
    await _enter(tester, const Key('edit-planting-date-field'), '2025-02-29');
    await _enter(
      tester,
      const Key('edit-expected-harvest-date-field'),
      '2024-01-01',
    );
    await _enter(tester, const Key('edit-plant-count-field'), '-1.5');
    await _enter(tester, const Key('edit-crop-notes-field'), 'ந' * 10001);
    await _tapSave(tester);
    expect(find.text('Crop type is required.'), findsOneWidget);
    expect(find.textContaining('128 characters'), findsOneWidget);
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    expect(
      find.text('Plant count must be a positive whole number.'),
      findsOneWidget,
    );
    expect(find.textContaining('10000 characters'), findsOneWidget);
    expect(puts, 0);
  });

  testWidgets('accepts Unicode boundaries and a future leap date', (
    tester,
  ) async {
    var puts = 0;
    final fixture = await _fixture((request) async {
      puts++;
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _jsonResponse(
        _cropJson(
          cropType: body['crop_type']! as String,
          variety: body['variety'] as String?,
          plantingDate: body['planting_date']! as String,
          expectedHarvestDate: body['expected_harvest_date'] as String?,
          notes: body['notes'] as String?,
        ),
      );
    });
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _enter(tester, const Key('edit-crop-type-field'), '🌾' * 128);
    await _enter(tester, const Key('edit-crop-variety-field'), 'வி' * 64);
    await _enter(tester, const Key('edit-planting-date-field'), '2032-02-29');
    await _enter(
      tester,
      const Key('edit-expected-harvest-date-field'),
      '2032-03-01',
    );
    await _enter(tester, const Key('edit-crop-notes-field'), 'ක' * 10000);
    await _tapSave(tester);
    expect(puts, 1);
  });

  testWidgets('Cancel dispatches zero PUT requests', (tester) async {
    var puts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') puts++;
      return _jsonResponse(_cropJson());
    });
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-edit-crop-cycle-button')));
    await tester.pumpAndSettle();
    expect(puts, 0);
    expect(find.text('Open Edit'), findsOneWidget);
  });

  testWidgets('duplicate Save dispatches only one pending PUT', (tester) async {
    final response = Completer<http.Response>();
    var puts = 0;
    final fixture = await _fixture((_) async {
      puts++;
      return response.future;
    });
    await _pumpEdit(tester, fixture, crop: _cropModel());
    final save = find.byKey(const Key('save-crop-cycle-changes-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(puts, 1);
    expect(find.text('Saving...'), findsOneWidget);
    response.complete(_jsonResponse(_cropJson()));
    await tester.pumpAndSettle();
  });

  for (final scenario in [
    'server',
    'network',
    'timeout',
    'malformed',
    'wrong-id',
  ]) {
    testWidgets('$scenario update is ambiguous and requires inspection', (
      tester,
    ) async {
      var puts = 0;
      final fixture = await _fixture((_) async {
        puts++;
        if (scenario == 'server') return http.Response('private', 500);
        if (scenario == 'network') throw http.ClientException('private');
        if (scenario == 'timeout') return Completer<http.Response>().future;
        if (scenario == 'malformed') return _jsonResponse({'id': 8});
        return _jsonResponse(_cropJson(id: 9));
      });
      await _pumpHost(tester, fixture);
      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      expect(puts, 1);
      expect(
        find.byKey(const Key('inspect-crop-cycle-button')),
        findsOneWidget,
      );
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(EditCropCycleScreen), findsOneWidget);
      final inspect = find.byKey(const Key('inspect-crop-cycle-button'));
      await tester.ensureVisible(inspect);
      await tester.tap(inspect);
      await tester.pumpAndSettle();
      expect(find.text('Uncertain result'), findsOneWidget);
      expect(puts, 1);
    });
  }

  testWidgets('unexpected post-dispatch PUT exception requires inspection', (
    tester,
  ) async {
    var puts = 0;
    final fixture = await _fixture((request) async {
      puts++;
      throw StateError('private transport detail');
    });
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(puts, 1);
    expect(find.byKey(const Key('inspect-crop-cycle-button')), findsOneWidget);
    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(
      find.byKey(const Key('save-crop-cycle-changes-button')),
      findsNothing,
    );
  });

  testWidgets('404 requires unavailable inspection result', (tester) async {
    final fixture = await _fixture((_) async => http.Response('{}', 404));
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    expect(
      find.textContaining('This crop cycle is unavailable.'),
      findsOneWidget,
    );
    final inspect = find.byKey(const Key('inspect-crop-cycle-button'));
    await tester.ensureVisible(inspect);
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    expect(find.text('Unavailable result'), findsOneWidget);
  });

  for (final rejection in [409, 422]) {
    testWidgets('HTTP $rejection is definite and remains actionable', (
      tester,
    ) async {
      var puts = 0;
      final fixture = await _fixture((_) async {
        puts++;
        return http.Response('{"detail":"private"}', rejection);
      });
      await _pumpEdit(tester, fixture, crop: _cropModel());
      await _tapSave(tester);
      expect(puts, 1);
      expect(find.textContaining('private'), findsNothing);
      expect(
        find.byKey(const Key('save-crop-cycle-changes-button')),
        findsOneWidget,
      );
    });
  }

  testWidgets('terminal PUT 401 closes the protected route', (tester) async {
    final fixture = await _fixture((_) async => http.Response('{}', 401));
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    expect(find.byType(EditCropCycleScreen), findsNothing);
  });

  testWidgets('logout during PUT closes route and ignores delayed success', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      return pending.future;
    });
    await _pumpHost(tester, fixture);
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    await _tapSave(tester, settle: false);
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.byType(EditCropCycleScreen), findsNothing);
    pending.complete(_jsonResponse(_cropJson()));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed result'), findsNothing);
  });

  testWidgets('delayed PUT completion after disposal is ignored', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((_) async => pending.future);
    await _pumpEdit(tester, fixture, crop: _cropModel());
    await _tapSave(tester, settle: false);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(_jsonResponse(_cropJson()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final configuration in [
    (const Size(320, 700), 1.0),
    (const Size(1500, 1000), 1.0),
    (const Size(900, 1400), 1.8),
  ]) {
    testWidgets(
      'responsive edit form ${configuration.$1} scale ${configuration.$2}',
      (tester) async {
        final fixture = await _fixture((_) async => http.Response('{}', 500));
        await _pumpEdit(
          tester,
          fixture,
          crop: _cropModel(
            cropType: 'மிக நீளமான பயிர் பெயர்',
            variety: 'දිගු ප්‍රභේදය',
            notes: ('தமிழ் සිංහල English ' * 30).trim(),
          ),
          size: configuration.$1,
          textScale: configuration.$2,
        );
        expect(find.byKey(const Key('edit-crop-cycle-form')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<TextFormField>(find.byKey(key)).controller!.text;

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _selectStatus(WidgetTester tester, String label) async {
  final field = find.byKey(const Key('edit-crop-status-field'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester, {bool settle = true}) async {
  final save = find.byKey(const Key('save-crop-cycle-changes-button'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpEdit(
  WidgetTester tester,
  _Fixture fixture, {
  required CropCycle crop,
  Size size = const Size(900, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: EditCropCycleScreen(
        cropCycleService: fixture.crops,
        session: fixture.session,
        cropCycle: crop,
        farmLabel: 'Demo Farm (Farm #4)',
      ),
    ),
  );
}

Future<void> _pumpHost(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: _EditHost(fixture: fixture)));
}

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 24, 12);
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
  );
}

CropCycle _cropModel({
  String cropType = 'Tomato',
  String? variety = 'Roma',
  String? notes = 'Original',
}) => CropCycle.fromJson(
  _cropJson(cropType: cropType, variety: variety, notes: notes),
);

Map<String, Object?> _cropJson({
  int id = 8,
  int farmId = 4,
  String cropType = 'Tomato',
  String? variety = 'Roma',
  String plantingDate = '2026-11-03',
  String? expectedHarvestDate = '2027-01-10',
  String status = 'active',
  int? plantCount = 25,
  String? notes = 'Original',
}) => {
  'id': id,
  'farm_id': farmId,
  'crop_type': cropType,
  'variety': variety,
  'planting_date': plantingDate,
  'expected_harvest_date': expectedHarvestDate,
  'status': status,
  'plant_count': plantCount,
  'notes': notes,
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:30:00Z',
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'refresh-$access',
  issuedAt: DateTime.utc(2026, 11, 24, 12),
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

class _Fixture {
  const _Fixture({
    required this.auth,
    required this.session,
    required this.crops,
  });

  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
}

class _EditHost extends StatefulWidget {
  const _EditHost({required this.fixture});

  final _Fixture fixture;

  @override
  State<_EditHost> createState() => _EditHostState();
}

class _EditHostState extends State<_EditHost> {
  EditCropCycleResult? _result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<EditCropCycleResult>(
                    MaterialPageRoute(
                      builder: (_) => EditCropCycleScreen(
                        cropCycleService: widget.fixture.crops,
                        session: widget.fixture.session,
                        cropCycle: _cropModel(),
                        farmLabel: 'Demo Farm (Farm #4)',
                      ),
                    ),
                  );
              if (mounted) setState(() => _result = result);
            },
            child: const Text('Open Edit'),
          ),
          if (_result?.outcome == EditCropCycleOutcome.confirmed)
            const Text('Confirmed result'),
          if (_result?.outcome == EditCropCycleOutcome.uncertain)
            const Text('Uncertain result'),
          if (_result?.outcome == EditCropCycleOutcome.unavailable)
            const Text('Unavailable result'),
        ],
      ),
    ),
  );
}
