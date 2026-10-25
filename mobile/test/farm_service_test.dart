import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:agrocrew/features/farms/data/models/farm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('GET list uses bearer auth and returns typed pagination', () async {
    final fixture = await _fixture((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/farms');
      expect(request.url.queryParameters, {'limit': '20', 'offset': '0'});
      expect(request.headers['authorization'], 'Bearer access-a');
      return http.Response(jsonEncode([_farmJson(1)]), 200);
    });
    final page = await fixture.service.listFarms();
    expect(page.farms.single.name, 'Farm 1');
    expect(page.hasMore, isFalse);
  });

  test('full GET page advertises Load More and honors offset', () async {
    final fixture = await _fixture((request) async {
      expect(request.url.queryParameters['limit'], '2');
      expect(request.url.queryParameters['offset'], '4');
      return http.Response(jsonEncode([_farmJson(5), _farmJson(6)]), 200);
    });
    final page = await fixture.service.listFarms(limit: 2, offset: 4);
    expect(page.hasMore, isTrue);
    expect(page.offset, 4);
  });

  test('GET details returns a validated Farm', () async {
    final fixture = await _fixture((request) async {
      expect(request.url.path, '/api/v1/farms/9');
      return http.Response(jsonEncode(_farmJson(9)), 200);
    });
    expect((await fixture.service.getFarm(9)).id, 9);
  });

  test('POST create sends no owner and parses HTTP 201', () async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      calls += 1;
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer access-a');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {'name': 'Green Valley', 'area_value': 2.5});
      expect(body, isNot(contains('user_id')));
      return http.Response(jsonEncode(_farmJson(3)), 201);
    });
    final farm = await fixture.service.createFarm(
      const FarmCreate(name: 'Green Valley', areaValue: 2.5),
    );
    expect(farm.id, 3);
    expect(calls, 1);
  });

  for (final entry in <int, FarmFailureType>{
    404: FarmFailureType.notFound,
    422: FarmFailureType.validation,
    500: FarmFailureType.server,
  }.entries) {
    test('maps HTTP ${entry.key}', () async {
      final fixture = await _fixture(
        (_) async => http.Response('{"detail":"safe"}', entry.key),
      );
      await expectLater(
        fixture.service.getFarm(7),
        throwsA(
          isA<FarmException>().having((e) => e.type, 'type', entry.value),
        ),
      );
    });
  }

  test('GET 401 refreshes once and safely retries', () async {
    var farmCalls = 0;
    var refreshCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path.endsWith('/refresh')) {
        refreshCalls += 1;
        return _refreshResponse();
      }
      farmCalls += 1;
      if (farmCalls == 1) return http.Response('{"detail":"expired"}', 401);
      expect(request.headers['authorization'], 'Bearer access-b');
      return http.Response(jsonEncode(<Object?>[]), 200);
    });
    expect((await fixture.service.listFarms()).farms, isEmpty);
    expect(refreshCalls, 1);
    expect(farmCalls, 2);
  });

  test('expired token refreshes before POST and POST is sent once', () async {
    var postCalls = 0;
    final now = DateTime.utc(2026, 10, 24, 12);
    final fixture = await _fixture(
      (request) async {
        if (request.url.path.endsWith('/refresh')) {
          return _refreshResponse();
        }
        postCalls += 1;
        expect(request.headers['authorization'], 'Bearer access-b');
        return http.Response(jsonEncode(_farmJson(2)), 201);
      },
      now: now,
      accessLifetime: const Duration(seconds: 1),
    );
    await fixture.service.createFarm(const FarmCreate(name: 'Farm'));
    expect(postCalls, 1);
  });

  test(
    'refresh timeout before POST is surfaced and POST is not sent',
    () async {
      var postCalls = 0;
      final now = DateTime.utc(2026, 10, 24, 12);
      final fixture = await _fixture(
        (request) async {
          if (request.url.path.endsWith('/refresh')) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return _refreshResponse();
          }
          postCalls += 1;
          return http.Response(jsonEncode(_farmJson(2)), 201);
        },
        now: now,
        accessLifetime: const Duration(seconds: 1),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        fixture.service.createFarm(const FarmCreate(name: 'Farm')),
        throwsA(
          isA<FarmException>().having(
            (error) => error.type,
            'type',
            FarmFailureType.timeout,
          ),
        ),
      );
      expect(postCalls, 0);
      expect(fixture.session.state, AuthSessionState.authenticated);
    },
  );

  test('ambiguous POST timeout is not retried', () async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 201);
    }, timeout: const Duration(milliseconds: 1));
    await expectLater(
      fixture.service.createFarm(const FarmCreate(name: 'Farm')),
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.ambiguousCreation,
        ),
      ),
    );
    expect(calls, 1);
  });

  test('maps connection failures safely', () async {
    final fixture = await _fixture(
      (request) async => throw http.ClientException('private', request.url),
    );
    await expectLater(
      fixture.service.listFarms(),
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.network,
        ),
      ),
    );
  });

  test('rejects invalid JSON and malformed list entries', () async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      return calls == 1
          ? http.Response('not-json', 200)
          : http.Response('[{"id":1}]', 200);
    });
    for (var i = 0; i < 2; i++) {
      await expectLater(
        fixture.service.listFarms(),
        throwsA(
          isA<FarmException>().having(
            (e) => e.type,
            'type',
            FarmFailureType.invalidResponse,
          ),
        ),
      );
    }
  });

  test('does not send a protected request without authentication', () async {
    var calls = 0;
    final client = ApiClient(
      client: MockClient((_) async {
        calls += 1;
        return http.Response('[]', 200);
      }),
    );
    final session = AuthSession(tokenStore: MemoryAuthTokenStore());
    final auth = AuthService(client);
    final service = FarmService(
      apiClient: client,
      session: session,
      authService: auth,
    );
    await expectLater(service.listFarms(), throwsA(isA<FarmException>()));
    expect(calls, 0);
  });

  test('logout makes a delayed response stale', () async {
    final response = Completer<http.Response>();
    final fixture = await _fixture((request) {
      if (request.url.path.endsWith('/logout')) {
        return Future.value(http.Response('', 204));
      }
      return response.future;
    });
    final pending = fixture.service.listFarms();
    await fixture.session.logout(fixture.authService);
    response.complete(http.Response('[]', 200));
    await expectLater(
      pending,
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.staleSession,
        ),
      ),
    );
  });

  test(
    'PUT sends a complete owner-free replacement and parses HTTP 200',
    () async {
      final fixture = await _fixture((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/farms/12');
        expect(request.headers['authorization'], 'Bearer access-a');
        expect(jsonDecode(request.body), {
          'name': 'Organic Farm',
          'latitude': 6.9,
          'longitude': null,
          'area_value': 3.5,
          'area_unit': 'acres',
          'notes': null,
        });
        expect(request.body, isNot(contains('user_id')));
        expect(request.body, isNot(contains('created_at')));
        return http.Response(
          jsonEncode({..._farmJson(12), 'name': 'Organic Farm'}),
          200,
        );
      });
      final farm = await fixture.service.updateFarm(
        12,
        const FarmUpdate(
          name: ' Organic Farm ',
          latitude: 6.9,
          longitude: null,
          areaValue: 3.5,
          areaUnit: ' acres ',
          notes: null,
        ),
      );
      expect(farm.name, 'Organic Farm');
    },
  );

  for (final entry in <int, FarmFailureType>{
    401: FarmFailureType.unauthorized,
    404: FarmFailureType.notFound,
    409: FarmFailureType.conflict,
    422: FarmFailureType.validation,
    500: FarmFailureType.server,
  }.entries) {
    test('PUT maps HTTP ${entry.key}', () async {
      final fixture = await _fixture(
        (_) async => http.Response('{"detail":"safe"}', entry.key),
      );
      await expectLater(
        fixture.service.updateFarm(
          7,
          const FarmUpdate(
            name: 'Farm',
            latitude: null,
            longitude: null,
            areaValue: null,
            areaUnit: null,
            notes: null,
          ),
        ),
        throwsA(
          isA<FarmException>().having((e) => e.type, 'type', entry.value),
        ),
      );
    });
  }

  test('DELETE accepts an empty HTTP 204 response', () async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      calls += 1;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/farms/4');
      expect(request.headers['authorization'], 'Bearer access-a');
      return http.Response('', 204);
    });
    await fixture.service.deleteFarm(4);
    expect(calls, 1);
  });

  test('DELETE maps conflict without claiming success', () async {
    final fixture = await _fixture(
      (_) async => http.Response('{"detail":"private"}', 409),
    );
    await expectLater(
      fixture.service.deleteFarm(4),
      throwsA(
        isA<FarmException>()
            .having((e) => e.type, 'type', FarmFailureType.conflict)
            .having(
              (e) => e.message,
              'message',
              'This farm cannot be deleted because it has related records.',
            ),
      ),
    );
  });

  test('expired token refreshes before PUT and DELETE', () async {
    var mutationCalls = 0;
    final now = DateTime.utc(2026, 10, 24, 12);
    final fixture = await _fixture(
      (request) async {
        if (request.url.path.endsWith('/refresh')) return _refreshResponse();
        mutationCalls += 1;
        expect(request.headers['authorization'], 'Bearer access-b');
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(_farmJson(2)), 200);
        }
        return http.Response('', 204);
      },
      now: now,
      accessLifetime: const Duration(seconds: 1),
    );
    await fixture.service.updateFarm(
      2,
      const FarmUpdate(
        name: 'Farm',
        latitude: null,
        longitude: null,
        areaValue: null,
        areaUnit: null,
        notes: null,
      ),
    );
    await fixture.service.deleteFarm(2);
    expect(mutationCalls, 2);
  });

  test('ambiguous PUT and DELETE timeouts are each sent once', () async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 200);
    }, timeout: const Duration(milliseconds: 1));
    await expectLater(
      fixture.service.updateFarm(
        3,
        const FarmUpdate(
          name: 'Farm',
          latitude: null,
          longitude: null,
          areaValue: null,
          areaUnit: null,
          notes: null,
        ),
      ),
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.ambiguousUpdate,
        ),
      ),
    );
    await expectLater(
      fixture.service.deleteFarm(3),
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.ambiguousDeletion,
        ),
      ),
    );
    expect(calls, 2);
  });

  test('PUT rejects invalid JSON and malformed response objects', () async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls += 1;
      return calls == 1
          ? http.Response('not-json', 200)
          : http.Response('{"id":1}', 200);
    });
    for (var index = 0; index < 2; index += 1) {
      await expectLater(
        fixture.service.updateFarm(
          1,
          const FarmUpdate(
            name: 'Farm',
            latitude: null,
            longitude: null,
            areaValue: null,
            areaUnit: null,
            notes: null,
          ),
        ),
        throwsA(
          isA<FarmException>().having(
            (e) => e.type,
            'type',
            FarmFailureType.invalidResponse,
          ),
        ),
      );
    }
  });

  test('logout makes a delayed PUT response stale', () async {
    final response = Completer<http.Response>();
    final fixture = await _fixture((request) {
      if (request.url.path.endsWith('/logout')) {
        return Future.value(http.Response('', 204));
      }
      return response.future;
    });
    final pending = fixture.service.updateFarm(
      1,
      const FarmUpdate(
        name: 'Farm',
        latitude: null,
        longitude: null,
        areaValue: null,
        areaUnit: null,
        notes: null,
      ),
    );
    await fixture.session.logout(fixture.authService);
    response.complete(http.Response(jsonEncode(_farmJson(1)), 200));
    await expectLater(
      pending,
      throwsA(
        isA<FarmException>().having(
          (e) => e.type,
          'type',
          FarmFailureType.staleSession,
        ),
      ),
    );
  });
}

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
    UserProfile(
      id: 7,
      name: 'Farmer',
      email: 'farmer@example.com',
      preferredLanguage: 'English',
      isActive: true,
      createdAt: clock,
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

Map<String, Object?> _farmJson(int id) => {
  'id': id,
  'user_id': 7,
  'name': 'Farm $id',
  'latitude': null,
  'longitude': null,
  'area_value': null,
  'area_unit': null,
  'notes': null,
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T10:00:00Z',
};

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
