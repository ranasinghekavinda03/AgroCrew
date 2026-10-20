import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);

  test('comfortable access lifetime verifies without refresh', () async {
    final store = _Store(session: _tokens(now, accessMinutes: 10));
    var refreshes = 0;
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (request) async {
        if (request.url.path.endsWith('/refresh')) refreshes += 1;
        return _profileResponse();
      }),
    );

    expect(refreshes, 0);
    expect(session.state, AuthSessionState.authenticated);
  });

  for (final lifetime in [const Duration(seconds: 30), Duration.zero]) {
    test('access lifetime $lifetime refreshes before /auth/me', () async {
      final store = _Store(session: _tokens(now, accessLifetime: lifetime));
      final paths = <String>[];
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.restore(
        _service(now, (request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/refresh')) return _refreshResponse();
          expect(request.headers['authorization'], 'Bearer new-access');
          return _profileResponse();
        }),
      );

      expect(paths, ['/api/v1/auth/refresh', '/api/v1/auth/me']);
      expect(store.saveCount, 1);
      expect(store.session?.refreshToken, 'new-refresh');
      expect(session.state, AuthSessionState.authenticated);
    });
  }

  test('expired refresh token clears credentials and requires login', () async {
    final store = _Store(
      session: _tokens(
        now,
        accessLifetime: Duration.zero,
        refreshLifetime: Duration.zero,
      ),
    );
    var requests = 0;
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (_) async {
        requests += 1;
        return _refreshResponse();
      }),
    );

    expect(requests, 0);
    expect(store.clearCount, 1);
    expect(session.state, AuthSessionState.requiresLogin);
  });

  test('missing refresh token requires login without a request', () async {
    final stored = _tokens(now, accessLifetime: Duration.zero);
    final store = _Store(
      session: LoginResponse(
        accessToken: stored.accessToken,
        refreshToken: '',
        issuedAt: stored.issuedAt,
        expiresIn: stored.expiresIn,
        refreshExpiresIn: stored.refreshExpiresIn,
      ),
    );
    var requests = 0;
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (_) async {
        requests += 1;
        return _refreshResponse();
      }),
    );

    expect(requests, 0);
    expect(session.state, AuthSessionState.requiresLogin);
  });

  test('/auth/me 401 refreshes and retries exactly once', () async {
    final store = _Store(session: _tokens(now, accessMinutes: 10));
    var profiles = 0;
    var refreshes = 0;
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes += 1;
          return _refreshResponse();
        }
        profiles += 1;
        return profiles == 1
            ? http.Response('{"detail":"expired"}', 401)
            : _profileResponse();
      }),
    );

    expect(refreshes, 1);
    expect(profiles, 2);
    expect(session.state, AuthSessionState.authenticated);
  });

  test('second /auth/me 401 stops without a refresh loop', () async {
    final store = _Store(session: _tokens(now, accessMinutes: 10));
    var profiles = 0;
    var refreshes = 0;
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes += 1;
          return _refreshResponse();
        }
        profiles += 1;
        return http.Response('{"detail":"rejected"}', 401);
      }),
    );

    expect(refreshes, 1);
    expect(profiles, 2);
    expect(store.clearCount, 1);
    expect(session.state, AuthSessionState.requiresLogin);
  });

  for (final status in [401, 422]) {
    test('permanent refresh HTTP $status clears invalid session', () async {
      final store = _Store(session: _tokens(now));
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.restore(
        _service(
          now,
          (_) async => http.Response('{"detail":"private"}', status),
        ),
      );
      expect(store.clearCount, 1);
      expect(session.state, AuthSessionState.requiresLogin);
      expect(session.message, isNot(contains('old-refresh')));
    });
  }

  test('server refresh failure preserves recoverable stored session', () async {
    final original = _tokens(now);
    final store = _Store(session: original);
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.restore(
      _service(now, (_) async => http.Response('{"detail":"private"}', 500)),
    );

    expect(store.clearCount, 0);
    expect(store.session, same(original));
    expect(session.state, AuthSessionState.verificationError);
  });

  test(
    'refresh timeout preserves credentials and offers retry state',
    () async {
      final original = _tokens(now);
      final store = _Store(session: original);
      final service = AuthService(
        ApiClient(
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return _refreshResponse();
          }),
          timeout: const Duration(milliseconds: 1),
        ),
        clock: () => now,
      );
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.restore(service);

      expect(store.session, same(original));
      expect(store.clearCount, 0);
      expect(session.state, AuthSessionState.verificationError);
      expect(session.message, isNot(contains('old-refresh')));
    },
  );

  test('simultaneous startup callers perform only one refresh', () async {
    final store = _Store(session: _tokens(now));
    final response = Completer<http.Response>();
    var refreshes = 0;
    final service = _service(now, (request) {
      if (request.url.path.endsWith('/refresh')) {
        refreshes += 1;
        return response.future;
      }
      return Future.value(_profileResponse());
    });
    final session = AuthSession(tokenStore: store, clock: () => now);

    final first = session.restore(service);
    final second = session.restore(service);
    response.complete(_refreshResponse());
    await Future.wait([first, second]);

    expect(refreshes, 1);
    expect(store.saveCount, 1);
  });

  test(
    'three concurrent refresh callers share request and persistence',
    () async {
      final store = _Store();
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.establishVerified(
        _tokens(now, accessMinutes: 10),
        _profile(),
      );
      final response = Completer<http.Response>();
      var refreshes = 0;
      final service = _service(now, (_) {
        refreshes += 1;
        return response.future;
      });

      final calls = [
        session.refresh(service),
        session.refresh(service),
        session.refresh(service),
      ];
      response.complete(_refreshResponse());
      final results = await Future.wait(calls);

      expect(refreshes, 1);
      expect(
        results.every((value) => value.accessToken == 'new-access'),
        isTrue,
      );
      expect(store.saveCount, 2); // Initial login plus one rotation.
    },
  );

  test('failed refresh releases the single-flight operation', () async {
    final store = _Store();
    final session = AuthSession(tokenStore: store, clock: () => now);
    await session.establishVerified(
      _tokens(now, accessMinutes: 10),
      _profile(),
    );
    var attempts = 0;
    final service = _service(now, (_) async {
      attempts += 1;
      return attempts == 1
          ? http.Response('{"detail":"temporary"}', 500)
          : _refreshResponse();
    });

    await expectLater(
      session.refresh(service),
      throwsA(isA<RefreshException>()),
    );
    expect((await session.refresh(service)).accessToken, 'new-access');
    expect(attempts, 2);
  });

  test(
    'new login prevents a delayed old refresh from overwriting tokens',
    () async {
      final store = _Store();
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.establishVerified(
        _tokens(now, accessMinutes: 10),
        _profile(),
      );
      final response = Completer<http.Response>();
      final oldRefresh = session.refresh(_service(now, (_) => response.future));
      final newer = LoginResponse(
        accessToken: 'new-login-access',
        refreshToken: 'new-login-refresh',
        issuedAt: now,
        expiresIn: const Duration(minutes: 30),
        refreshExpiresIn: const Duration(days: 7),
      );
      final newLogin = session.establishVerified(newer, _profile());
      response.complete(_refreshResponse());

      await expectLater(oldRefresh, throwsA(anything));
      await newLogin;
      expect(store.session?.refreshToken, 'new-login-refresh');
      expect(session.refreshToken, 'new-login-refresh');
    },
  );

  test(
    'rotation storage failure clears obsolete pair and fails closed',
    () async {
      final store = _Store(session: _tokens(now))..failSave = true;
      final session = AuthSession(tokenStore: store, clock: () => now);
      await session.restore(_service(now, (_) async => _refreshResponse()));

      expect(store.saveCount, 1);
      expect(store.clearCount, 1);
      expect(store.session, isNull);
      expect(session.state, AuthSessionState.requiresLogin);
      expect(session.hasTokens, isFalse);
    },
  );
}

AuthService _service(DateTime now, MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  clock: () => now,
);

LoginResponse _tokens(
  DateTime now, {
  int? accessMinutes,
  Duration? accessLifetime,
  Duration refreshLifetime = const Duration(days: 7),
}) => LoginResponse(
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  issuedAt: now,
  expiresIn: accessLifetime ?? Duration(minutes: accessMinutes ?? -1),
  refreshExpiresIn: refreshLifetime,
);

http.Response _refreshResponse() => http.Response(
  jsonEncode({
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'token_type': 'bearer',
    'expires_in': 1800,
    'refresh_expires_in': 604800,
  }),
  200,
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 4,
    'name': 'Refresh Farmer',
    'email': 'refresh@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);

UserProfile _profile() => UserProfile(
  id: 4,
  name: 'Refresh Farmer',
  email: 'refresh@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 10, 20, 12),
);

class _Store implements AuthTokenStore {
  _Store({this.session});

  LoginResponse? session;
  int saveCount = 0;
  int clearCount = 0;
  bool failSave = false;

  @override
  Future<LoginResponse?> readSession() async => session;

  @override
  Future<void> saveSession(LoginResponse value) async {
    saveCount += 1;
    if (failSave) {
      throw const AuthTokenStoreException('Secure storage unavailable.');
    }
    session = value;
  }

  @override
  Future<void> clearSession() async {
    clearCount += 1;
    session = null;
  }
}
