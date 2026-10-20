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
  test('no saved session becomes unauthenticated without /auth/me', () async {
    final store = FakeTokenStore();
    var requests = 0;
    final session = AuthSession(tokenStore: store);
    await session.restore(
      _service((_) async {
        requests += 1;
        return _profileResponse();
      }),
    );

    expect(session.state, AuthSessionState.unauthenticated);
    expect(requests, 0);
  });

  test(
    'valid saved session is verified with bearer token and restored',
    () async {
      final store = FakeTokenStore(session: _validSession());
      var requests = 0;
      final session = AuthSession(tokenStore: store);
      await session.restore(
        _service((request) async {
          requests += 1;
          expect(request.url.path, '/api/v1/auth/me');
          expect(request.headers['authorization'], 'Bearer restored-access');
          return _profileResponse();
        }),
      );

      expect(requests, 1);
      expect(session.state, AuthSessionState.authenticated);
      expect(session.profile?.name, 'Restored Farmer');
      expect(session.accessToken, 'restored-access');
    },
  );

  test(
    'expired access token is refreshed before profile verification',
    () async {
      final store = FakeTokenStore(session: _expiredSession());
      var refreshRequests = 0;
      var profileRequests = 0;
      final session = AuthSession(tokenStore: store);
      await session.restore(
        _service((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshRequests += 1;
            expect(jsonDecode(request.body), {
              'refresh_token': 'still-not-refreshed',
            });
            return _refreshResponse();
          }
          profileRequests += 1;
          expect(request.headers['authorization'], 'Bearer rotated-access');
          return _profileResponse();
        }),
        now: DateTime.utc(2026, 10, 21, 12),
      );

      expect(refreshRequests, 1);
      expect(profileRequests, 1);
      expect(store.saveCount, 1);
      expect(session.state, AuthSessionState.authenticated);
      expect(session.accessToken, 'rotated-access');
    },
  );

  test('401 clears saved and in-memory authentication', () async {
    final store = FakeTokenStore(session: _validSession());
    final session = AuthSession(tokenStore: store);
    await session.restore(
      _service((_) async => http.Response('{"detail":"invalid"}', 401)),
    );

    expect(store.clearCount, 1);
    expect(session.state, AuthSessionState.requiresLogin);
    expect(session.hasTokens, isFalse);
    expect(session.profile, isNull);
  });

  test(
    'network failure preserves saved credentials and retry succeeds',
    () async {
      final store = FakeTokenStore(session: _validSession());
      var requests = 0;
      final session = AuthSession(tokenStore: store);
      final service = _service((_) async {
        requests += 1;
        if (requests == 1) throw http.ClientException('offline');
        return _profileResponse();
      });

      await session.restore(service);
      expect(session.state, AuthSessionState.verificationError);
      expect(store.clearCount, 0);
      expect(store.session, isNotNull);

      await session.restore(service);
      expect(session.state, AuthSessionState.authenticated);
      expect(requests, 2);
    },
  );

  test('simultaneous restore calls share one profile request', () async {
    final store = FakeTokenStore(session: _validSession());
    final response = Completer<http.Response>();
    var requests = 0;
    final session = AuthSession(tokenStore: store);
    final service = _service((_) {
      requests += 1;
      return response.future;
    });

    final first = session.restore(service);
    final second = session.restore(service);
    response.complete(_profileResponse());
    await Future.wait([first, second]);
    expect(requests, 1);
  });

  test(
    'verified login persists exactly once after profile validation',
    () async {
      final store = FakeTokenStore();
      final session = AuthSession(tokenStore: store);
      await session.establishVerified(_validSession(), _profile());

      expect(store.saveCount, 1);
      expect(session.state, AuthSessionState.authenticated);
    },
  );

  test('write failure does not create a false authenticated state', () async {
    final store = FakeTokenStore()..failSave = true;
    final session = AuthSession(tokenStore: store);
    await expectLater(
      session.establishVerified(_validSession(), _profile()),
      throwsA(isA<AuthTokenStoreException>()),
    );
    expect(session.state, AuthSessionState.unauthenticated);
    expect(session.hasTokens, isFalse);
  });

  test('secure read failure becomes a safe verification error', () async {
    final store = FakeTokenStore()..failRead = true;
    final session = AuthSession(tokenStore: store);
    await session.restore(_service((_) async => _profileResponse()));
    expect(session.state, AuthSessionState.verificationError);
    expect(session.message, isNot(contains('secret')));
  });
}

AuthService _service(MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
);

LoginResponse _validSession() => LoginResponse(
  accessToken: 'restored-access',
  refreshToken: 'restored-refresh',
  issuedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

LoginResponse _expiredSession() => LoginResponse(
  accessToken: 'expired-access',
  refreshToken: 'still-not-refreshed',
  issuedAt: DateTime.utc(2026, 10, 21, 10),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 7,
    'name': 'Restored Farmer',
    'email': 'restored@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);

http.Response _refreshResponse() => http.Response(
  jsonEncode({
    'access_token': 'rotated-access',
    'refresh_token': 'rotated-refresh',
    'token_type': 'bearer',
    'expires_in': 1800,
    'refresh_expires_in': 604800,
  }),
  200,
);

UserProfile _profile() => UserProfile(
  id: 7,
  name: 'Restored Farmer',
  email: 'restored@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 10, 20, 12),
);

class FakeTokenStore implements AuthTokenStore {
  FakeTokenStore({this.session});

  LoginResponse? session;
  int saveCount = 0;
  int clearCount = 0;
  bool failRead = false;
  bool failSave = false;

  @override
  Future<void> saveSession(LoginResponse value) async {
    saveCount += 1;
    if (failSave) {
      throw const AuthTokenStoreException('Secure storage unavailable.');
    }
    session = value;
  }

  @override
  Future<LoginResponse?> readSession() async {
    if (failRead) {
      throw const AuthTokenStoreException('Saved session could not be read.');
    }
    return session;
  }

  @override
  Future<void> clearSession() async {
    clearCount += 1;
    session = null;
  }
}
