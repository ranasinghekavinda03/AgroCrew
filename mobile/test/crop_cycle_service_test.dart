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
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('successful CRUD and pagination', () {
    test('list uses defaults, bearer auth, and omits farm filter', () async {
      final fixture = await _fixture((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/crops');
        expect(request.url.queryParameters, {'limit': '20', 'offset': '0'});
        expect(request.headers['authorization'], 'Bearer access-a');
        return http.Response(jsonEncode([_cropJson(1)]), 200);
      });
      final page = await fixture.service.listCropCycles();
      expect(page.crops.single.id, 1);
      expect(page.limit, 20);
      expect(page.offset, 0);
      expect(page.nextOffset, 1);
      expect(page.hasMore, isFalse);
      expect(() => page.crops.add(_crop(2)), throwsUnsupportedError);
    });

    test('list safely encodes explicit pagination and farm filter', () async {
      final fixture = await _fixture((request) async {
        expect(request.url.queryParameters, {
          'limit': '2',
          'offset': '4',
          'farm_id': '12',
        });
        return http.Response(
          jsonEncode([_cropJson(5, farmId: 12), _cropJson(6, farmId: 12)]),
          200,
        );
      });
      final page = await fixture.service.listCropCycles(
        limit: 2,
        offset: 4,
        farmId: 12,
      );
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 6);
    });

    test('empty and partial pages expose conservative metadata', () async {
      var calls = 0;
      final fixture = await _fixture((_) async {
        calls += 1;
        return http.Response(
          calls == 1 ? '[]' : jsonEncode([_cropJson(3)]),
          200,
        );
      });
      final empty = await fixture.service.listCropCycles(limit: 2, offset: 8);
      expect(empty.crops, isEmpty);
      expect(empty.nextOffset, 8);
      expect(empty.hasMore, isFalse);
      final partial = await fixture.service.listCropCycles(limit: 2, offset: 8);
      expect(partial.nextOffset, 9);
      expect(partial.hasMore, isFalse);
    });

    test('get validates returned ID', () async {
      final fixture = await _fixture((request) async {
        expect(request.url.path, '/api/v1/crops/9');
        return http.Response(jsonEncode(_cropJson(9)), 200);
      });
      expect((await fixture.service.getCropCycle(9)).id, 9);
    });

    test('create sends exact owner-free create payload', () async {
      final fixture = await _fixture((request) async {
        expect(request.method, 'POST');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['authorization'], 'Bearer access-a');
        expect(jsonDecode(request.body), {
          'farm_id': 12,
          'crop_type': 'Tomato',
          'planting_date': '2026-10-15',
          'status': 'planned',
        });
        expect(request.body, isNot(contains('user_id')));
        return http.Response(jsonEncode(_cropJson(3, farmId: 12)), 201);
      });
      final crop = await fixture.service.createCropCycle(
        CropCycleCreate(
          farmId: 12,
          cropType: ' Tomato ',
          plantingDate: DateTime.utc(2026, 10, 15),
        ),
      );
      expect(crop.id, 3);
    });

    test('create preserves optional fields and calendar dates', () async {
      final fixture = await _fixture((request) async {
        expect(jsonDecode(request.body), {
          'farm_id': 2,
          'crop_type': 'Rice',
          'variety': 'Basmati',
          'planting_date': '2026-01-02',
          'expected_harvest_date': '2026-04-03',
          'status': 'active',
          'plant_count': 40,
          'notes': 'North field',
        });
        return http.Response(jsonEncode(_cropJson(4, farmId: 2)), 201);
      });
      await fixture.service.createCropCycle(
        CropCycleCreate(
          farmId: 2,
          cropType: 'Rice',
          variety: ' Basmati ',
          plantingDate: DateTime(2026, 1, 2),
          expectedHarvestDate: DateTime(2026, 4, 3),
          status: CropStatus.active,
          plantCount: 40,
          notes: 'North field',
        ),
      );
    });

    test(
      'update sends full replacement with explicit nulls and no farm ID',
      () async {
        final fixture = await _fixture((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/v1/crops/8');
          expect(jsonDecode(request.body), {
            'crop_type': 'Maize',
            'variety': null,
            'planting_date': '2026-02-01',
            'expected_harvest_date': null,
            'status': 'harvested',
            'plant_count': null,
            'notes': null,
          });
          expect(request.body, isNot(contains('farm_id')));
          return http.Response(jsonEncode(_cropJson(8)), 200);
        });
        expect((await fixture.service.updateCropCycle(8, _update())).id, 8);
      },
    );

    test('delete accepts documented empty 204', () async {
      var calls = 0;
      final fixture = await _fixture((request) async {
        calls += 1;
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/v1/crops/4');
        expect(request.headers['authorization'], 'Bearer access-a');
        return http.Response('', 204);
      });
      await fixture.service.deleteCropCycle(4);
      expect(calls, 1);
    });
  });

  group('local validation', () {
    for (final values in [
      (limit: 0, offset: 0, farmId: null),
      (limit: 101, offset: 0, farmId: null),
      (limit: 20, offset: -1, farmId: null),
      (limit: 20, offset: 0, farmId: 0),
    ]) {
      test('invalid list parameters $values do not dispatch', () async {
        var calls = 0;
        final fixture = await _fixture((_) async {
          calls += 1;
          return http.Response('[]', 200);
        });
        await expectLater(
          fixture.service.listCropCycles(
            limit: values.limit,
            offset: values.offset,
            farmId: values.farmId,
          ),
          _failure(CropCycleFailureType.validation),
        );
        expect(calls, 0);
      });
    }

    for (final id in [0, -1]) {
      test('invalid crop ID $id does not dispatch', () async {
        var calls = 0;
        final fixture = await _fixture((_) async {
          calls += 1;
          return http.Response('{}', 200);
        });
        await expectLater(
          fixture.service.getCropCycle(id),
          _failure(CropCycleFailureType.validation),
        );
        await expectLater(
          fixture.service.updateCropCycle(id, _update()),
          _failure(CropCycleFailureType.validation),
        );
        await expectLater(
          fixture.service.deleteCropCycle(id),
          _failure(CropCycleFailureType.validation),
        );
        expect(calls, 0);
      });
    }

    test(
      'payload serialization failure is local and is not dispatched',
      () async {
        var calls = 0;
        final fixture = await _fixture((_) async {
          calls += 1;
          return http.Response('{}', 201);
        });
        await expectLater(
          fixture.service.createCropCycle(
            CropCycleCreate(
              farmId: 1,
              cropType: 'Crop',
              plantingDate: DateTime.utc(10000),
            ),
          ),
          _failure(CropCycleFailureType.validation),
        );
        expect(calls, 0);
      },
    );
  });

  group('authentication and refresh', () {
    test('missing session does not dispatch', () async {
      var calls = 0;
      final client = ApiClient(
        client: MockClient((_) async {
          calls += 1;
          return http.Response('[]', 200);
        }),
      );
      final session = AuthSession(tokenStore: MemoryAuthTokenStore());
      final service = CropCycleService(
        apiClient: client,
        session: session,
        authService: AuthService(client),
      );
      await expectLater(
        service.listCropCycles(),
        _failure(CropCycleFailureType.unauthorized),
      );
      expect(calls, 0);
    });

    test('proactive refresh happens before a mutation', () async {
      var mutationCalls = 0;
      final now = DateTime.utc(2026, 10, 24, 12);
      final fixture = await _fixture(
        (request) async {
          if (request.url.path.endsWith('/refresh')) return _refreshResponse();
          mutationCalls += 1;
          expect(request.headers['authorization'], 'Bearer access-b');
          return http.Response(jsonEncode(_cropJson(2)), 201);
        },
        now: now,
        accessLifetime: const Duration(seconds: 1),
      );
      await fixture.service.createCropCycle(_create());
      expect(mutationCalls, 1);
    });

    test('GET 401 refreshes once and retries with refreshed token', () async {
      var cropCalls = 0;
      var refreshCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshCalls += 1;
          return _refreshResponse();
        }
        cropCalls += 1;
        if (cropCalls == 1) return http.Response('{}', 401);
        expect(request.headers['authorization'], 'Bearer access-b');
        return http.Response('[]', 200);
      });
      await fixture.service.listCropCycles();
      expect((cropCalls, refreshCalls), (2, 1));
    });

    test('second GET 401 is terminal without an infinite loop', () async {
      var cropCalls = 0;
      var refreshCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshCalls += 1;
          return _refreshResponse();
        }
        cropCalls += 1;
        return http.Response('{}', 401);
      });
      await expectLater(
        fixture.service.listCropCycles(),
        _failure(CropCycleFailureType.unauthorized),
      );
      expect((cropCalls, refreshCalls), (2, 1));
    });

    test('GET refresh failure is sanitized and not retried', () async {
      var cropCalls = 0;
      var refreshCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshCalls += 1;
          return http.Response('{"detail":"private"}', 500);
        }
        cropCalls += 1;
        return http.Response('{}', 401);
      });
      await expectLater(
        fixture.service.listCropCycles(),
        _failure(CropCycleFailureType.server),
      );
      expect((cropCalls, refreshCalls), (1, 1));
    });

    test('concurrent GET 401 responses share one refresh', () async {
      var refreshCalls = 0;
      final refresh = Completer<http.Response>();
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshCalls += 1;
          return refresh.future;
        }
        if (request.headers['authorization'] == 'Bearer access-a') {
          return http.Response('{}', 401);
        }
        return http.Response('[]', 200);
      });
      final first = fixture.service.listCropCycles();
      final second = fixture.service.listCropCycles(offset: 1);
      await Future<void>.delayed(Duration.zero);
      refresh.complete(_refreshResponse());
      await Future.wait([first, second]);
      expect(refreshCalls, 1);
    });

    for (final method in ['POST', 'PUT', 'DELETE']) {
      test('$method 401 is never replayed', () async {
        var calls = 0;
        final fixture = await _fixture((request) async {
          calls += 1;
          return http.Response('{}', 401);
        });
        final operation = switch (method) {
          'POST' => fixture.service.createCropCycle(_create()),
          'PUT' => fixture.service.updateCropCycle(1, _update()),
          _ => fixture.service.deleteCropCycle(1),
        };
        await expectLater(
          operation,
          _failure(CropCycleFailureType.unauthorized),
        );
        expect(calls, 1);
      });
    }
  });

  group('HTTP and response failures', () {
    for (final entry in <int, CropCycleFailureType>{
      404: CropCycleFailureType.notFound,
      409: CropCycleFailureType.conflict,
      422: CropCycleFailureType.validation,
      500: CropCycleFailureType.server,
      418: CropCycleFailureType.server,
    }.entries) {
      test('maps HTTP ${entry.key} without exposing response detail', () async {
        final fixture = await _fixture(
          (_) async =>
              http.Response('{"detail":"secret database text"}', entry.key),
        );
        await expectLater(
          fixture.service.deleteCropCycle(4),
          throwsA(
            isA<CropCycleException>()
                .having((e) => e.type, 'type', entry.value)
                .having((e) => e.message, 'message', isNot(contains('secret'))),
          ),
        );
      });
    }

    test('list rejects non-array and malformed entries', () async {
      var calls = 0;
      final fixture = await _fixture((_) async {
        calls += 1;
        return http.Response(calls == 1 ? '{}' : '[{"id":1}]', 200);
      });
      await expectLater(
        fixture.service.listCropCycles(),
        _failure(CropCycleFailureType.invalidResponse),
      );
      await expectLater(
        fixture.service.listCropCycles(),
        _failure(CropCycleFailureType.invalidResponse),
      );
    });

    test('filtered list rejects inconsistent farm IDs', () async {
      final fixture = await _fixture(
        (_) async => http.Response(jsonEncode([_cropJson(1, farmId: 9)]), 200),
      );
      await expectLater(
        fixture.service.listCropCycles(farmId: 8),
        _failure(CropCycleFailureType.invalidResponse),
      );
    });

    test('details rejects wrong ID and empty or invalid JSON', () async {
      var calls = 0;
      final replies = [jsonEncode(_cropJson(2)), '', 'not-json'];
      final fixture = await _fixture(
        (_) async => http.Response(replies[calls++], 200),
      );
      for (var i = 0; i < replies.length; i++) {
        await expectLater(
          fixture.service.getCropCycle(1),
          _failure(CropCycleFailureType.invalidResponse),
        );
      }
    });

    test('create rejects wrong farm as ambiguous success', () async {
      final fixture = await _fixture(
        (_) async => http.Response(jsonEncode(_cropJson(1, farmId: 99)), 201),
      );
      await expectLater(
        fixture.service.createCropCycle(_create()),
        _failure(CropCycleFailureType.ambiguousCreation),
      );
    });

    test('update rejects wrong ID and malformed model as ambiguous', () async {
      var calls = 0;
      final fixture = await _fixture((_) async {
        calls += 1;
        return http.Response(
          calls == 1 ? jsonEncode(_cropJson(2)) : '{"id":1}',
          200,
        );
      });
      await expectLater(
        fixture.service.updateCropCycle(1, _update()),
        _failure(CropCycleFailureType.ambiguousUpdate),
      );
      await expectLater(
        fixture.service.updateCropCycle(1, _update()),
        _failure(CropCycleFailureType.ambiguousUpdate),
      );
    });

    for (final mutation in ['create', 'update']) {
      test(
        '$mutation rejects unknown status, invalid date, and empty success',
        () async {
          var calls = 0;
          final bodies = [
            jsonEncode({..._cropJson(1), 'status': 'growing'}),
            jsonEncode({..._cropJson(1), 'planting_date': '2026-02-30'}),
            '',
          ];
          final fixture = await _fixture(
            (_) async => http.Response(
              bodies[calls++],
              mutation == 'create' ? 201 : 200,
            ),
          );
          final expected = mutation == 'create'
              ? CropCycleFailureType.ambiguousCreation
              : CropCycleFailureType.ambiguousUpdate;
          for (var i = 0; i < bodies.length; i++) {
            final operation = mutation == 'create'
                ? fixture.service.createCropCycle(_create())
                : fixture.service.updateCropCycle(1, _update());
            await expectLater(operation, _failure(expected));
          }
        },
      );
    }
  });

  group('transport uncertainty and stale sessions', () {
    test('GET network and timeout remain ordinary read failures', () async {
      final network = await _fixture(
        (request) async => throw http.ClientException('private', request.url),
      );
      await expectLater(
        network.service.listCropCycles(),
        _failure(CropCycleFailureType.network),
      );
      final timeout = await _fixture((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('[]', 200);
      }, timeout: const Duration(milliseconds: 1));
      await expectLater(
        timeout.service.listCropCycles(),
        _failure(CropCycleFailureType.timeout),
      );
    });

    for (final entry in <String, CropCycleFailureType>{
      'POST': CropCycleFailureType.ambiguousCreation,
      'PUT': CropCycleFailureType.ambiguousUpdate,
      'DELETE': CropCycleFailureType.ambiguousDeletion,
    }.entries) {
      test('${entry.key} timeout is ambiguous and sent once', () async {
        var calls = 0;
        final fixture = await _fixture((_) async {
          calls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{}', 200);
        }, timeout: const Duration(milliseconds: 1));
        final operation = switch (entry.key) {
          'POST' => fixture.service.createCropCycle(_create()),
          'PUT' => fixture.service.updateCropCycle(1, _update()),
          _ => fixture.service.deleteCropCycle(1),
        };
        await expectLater(operation, _failure(entry.value));
        expect(calls, 1);
      });
    }

    for (final entry in <String, CropCycleFailureType>{
      'POST': CropCycleFailureType.ambiguousCreation,
      'PUT': CropCycleFailureType.ambiguousUpdate,
      'DELETE': CropCycleFailureType.ambiguousDeletion,
    }.entries) {
      test(
        '${entry.key} connection failure is ambiguous and sent once',
        () async {
          var calls = 0;
          final fixture = await _fixture((request) async {
            calls += 1;
            throw http.ClientException('private transport detail', request.url);
          });
          final operation = switch (entry.key) {
            'POST' => fixture.service.createCropCycle(_create()),
            'PUT' => fixture.service.updateCropCycle(1, _update()),
            _ => fixture.service.deleteCropCycle(1),
          };
          await expectLater(operation, _failure(entry.value));
          expect(calls, 1);
        },
      );
    }

    test('logout makes delayed list success stale', () async {
      final response = Completer<http.Response>();
      final fixture = await _fixture((request) {
        if (request.url.path.endsWith('/logout')) {
          return Future.value(http.Response('', 204));
        }
        return response.future;
      });
      final pending = fixture.service.listCropCycles();
      await fixture.session.logout(fixture.authService);
      response.complete(http.Response('[]', 200));
      await expectLater(pending, _failure(CropCycleFailureType.staleSession));
    });

    test('logout makes delayed mutation and delayed error stale', () async {
      for (final responseValue in [
        http.Response(jsonEncode(_cropJson(1)), 200),
        http.Response('', 500),
      ]) {
        final response = Completer<http.Response>();
        final fixture = await _fixture((request) {
          if (request.url.path.endsWith('/logout')) {
            return Future.value(http.Response('', 204));
          }
          return response.future;
        });
        final pending = fixture.service.updateCropCycle(1, _update());
        await fixture.session.logout(fixture.authService);
        response.complete(responseValue);
        await expectLater(pending, _failure(CropCycleFailureType.staleSession));
      }
    });

    test('logout makes a delayed transport error stale', () async {
      final response = Completer<http.Response>();
      final fixture = await _fixture((request) {
        if (request.url.path.endsWith('/logout')) {
          return Future.value(http.Response('', 204));
        }
        return response.future;
      });
      final pending = fixture.service.listCropCycles();
      await fixture.session.logout(fixture.authService);
      response.completeError(http.ClientException('private'));
      await expectLater(pending, _failure(CropCycleFailureType.staleSession));
    });

    test('account replacement discards an old delayed response', () async {
      final response = Completer<http.Response>();
      final fixture = await _fixture((_) => response.future);
      final pending = fixture.service.listCropCycles();
      await fixture.session.establishVerified(
        _tokens('new-access'),
        _profile(99),
      );
      response.complete(http.Response('[]', 200));
      await expectLater(pending, _failure(CropCycleFailureType.staleSession));
    });

    test('account replacement before a 401 retry prevents replay', () async {
      var cropCalls = 0;
      final first = Completer<http.Response>();
      final fixture = await _fixture((request) async {
        if (request.url.path.endsWith('/refresh')) return _refreshResponse();
        cropCalls += 1;
        return first.future;
      });
      final pending = fixture.service.listCropCycles();
      await fixture.session.establishVerified(
        _tokens('new-access'),
        _profile(99),
      );
      first.complete(http.Response('{}', 401));
      await expectLater(pending, _failure(CropCycleFailureType.staleSession));
      expect(cropCalls, 1);
    });
  });
}

Matcher _failure(CropCycleFailureType type) => throwsA(
  isA<CropCycleException>().having((error) => error.type, 'type', type),
);

Future<_Fixture> _fixture(
  MockClientHandler handler, {
  DateTime? now,
  Duration accessLifetime = const Duration(minutes: 30),
  Duration timeout = const Duration(seconds: 1),
}) async {
  final clock = now ?? DateTime.utc(2026, 10, 24, 12);
  final client = ApiClient(client: MockClient(handler), timeout: timeout);
  final auth = AuthService(client, clock: () => clock);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => clock,
  );
  await session.establishVerified(
    LoginResponse(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
      issuedAt: clock,
      expiresIn: accessLifetime,
      refreshExpiresIn: const Duration(days: 7),
    ),
    _profile(7, now: clock),
  );
  return _Fixture(
    service: CropCycleService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
    session: session,
    authService: auth,
  );
}

CropCycleCreate _create() => CropCycleCreate(
  farmId: 1,
  cropType: 'Crop',
  plantingDate: DateTime.utc(2026, 2, 1),
);

CropCycleUpdate _update() => CropCycleUpdate(
  cropType: 'Maize',
  variety: null,
  plantingDate: DateTime.utc(2026, 2, 1),
  expectedHarvestDate: null,
  status: CropStatus.harvested,
  plantCount: null,
  notes: null,
);

Map<String, Object?> _cropJson(int id, {int farmId = 1}) => {
  'id': id,
  'farm_id': farmId,
  'crop_type': 'Crop $id',
  'variety': null,
  'planting_date': '2026-02-01',
  'expected_harvest_date': null,
  'status': 'planned',
  'plant_count': null,
  'notes': null,
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T10:00:00Z',
};

CropCycle _crop(int id) => CropCycle.fromJson(_cropJson(id));

http.Response _refreshResponse() => http.Response(
  jsonEncode({
    'access_token': 'access-b',
    'refresh_token': 'refresh-b',
    'token_type': 'bearer',
    'expires_in': 1800,
    'refresh_expires_in': 604800,
  }),
  200,
);

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'new-refresh',
  issuedAt: DateTime.utc(2026, 10, 24, 12),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

UserProfile _profile(int id, {DateTime? now}) => UserProfile(
  id: id,
  name: 'Farmer $id',
  email: 'farmer$id@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: now ?? DateTime.utc(2026, 10, 24, 12),
);

class _Fixture {
  const _Fixture({
    required this.service,
    required this.session,
    required this.authService,
  });

  final CropCycleService service;
  final AuthSession session;
  final AuthService authService;
}
