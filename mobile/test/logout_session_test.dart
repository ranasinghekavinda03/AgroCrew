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
  final now = DateTime.utc(2026, 10, 22, 12);

  test('logout clears memory, profile, and persisted credentials', () async {
    final store = _Store();
    final session = await _verifiedSession(store, now);
    final result = await session.logout(
      _service((_) async => http.Response('', 204)),
    );

    expect(result.localCleanupSucceeded, isTrue);
    expect(result.remoteLogoutConfirmed, isTrue);
    expect(session.state, AuthSessionState.unauthenticated);
    expect(session.accessToken, isNull);
    expect(session.refreshToken, isNull);
    expect(session.profile, isNull);
    expect(store.session, isNull);
    expect((await _restored(store)).state, AuthSessionState.unauthenticated);
  });

  test(
    'remote failure still signs out locally and communicates uncertainty',
    () async {
      final store = _Store();
      final session = await _verifiedSession(store, now);
      final result = await session.logout(
        _service((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );

      expect(result.localCleanupSucceeded, isTrue);
      expect(result.remoteLogoutConfirmed, isFalse);
      expect(session.state, AuthSessionState.unauthenticated);
      expect(session.message, contains('could not be confirmed'));
      expect(session.message, isNot(contains('old-refresh')));
    },
  );

  test(
    'secure deletion failure fails closed and retry completes cleanup',
    () async {
      final store = _Store()..failClear = true;
      final session = await _verifiedSession(store, now);
      final result = await session.logout(
        _service((_) async => http.Response('', 204)),
      );

      expect(result.localCleanupSucceeded, isFalse);
      expect(session.state, AuthSessionState.cleanupError);
      expect(session.hasTokens, isFalse);
      expect(session.profile, isNull);

      store.failClear = false;
      await session.retryLogoutCleanup();
      expect(session.state, AuthSessionState.unauthenticated);
      expect(store.session, isNull);
    },
  );

  test('concurrent logout callers share one request and cleanup', () async {
    final store = _Store();
    final session = await _verifiedSession(store, now);
    final response = Completer<http.Response>();
    var requests = 0;
    final service = _service((_) {
      requests += 1;
      return response.future;
    });

    final first = session.logout(service);
    final second = session.logout(service);
    expect(identical(first, second), isTrue);
    response.complete(http.Response('', 204));
    await Future.wait([first, second]);

    expect(requests, 1);
    expect(store.clearCount, 1);
  });

  test(
    'logout during refresh revokes successor and never persists it',
    () async {
      final store = _Store();
      final session = await _verifiedSession(store, now);
      final refreshResponse = Completer<http.Response>();
      final revokedBodies = <Object?>[];
      final service = _service((request) {
        if (request.url.path.endsWith('/refresh')) {
          return refreshResponse.future;
        }
        revokedBodies.add(jsonDecode(request.body));
        return Future.value(http.Response('', 204));
      }, now: now);

      final refresh = session.refresh(service);
      final logout = session.logout(service);
      expect(session.state, AuthSessionState.signingOut);
      expect(session.hasTokens, isFalse);
      refreshResponse.complete(_refreshResponse());
      await refresh;
      final result = await logout;

      expect(result.remoteLogoutConfirmed, isTrue);
      expect(revokedBodies, [
        {'refresh_token': 'rotated-refresh'},
      ]);
      expect(store.session, isNull);
      expect(session.state, AuthSessionState.unauthenticated);
    },
  );

  test(
    'lost refresh response makes remote revocation explicitly uncertain',
    () async {
      final store = _Store();
      final session = await _verifiedSession(store, now);
      final lostResponse = Completer<http.Response>();
      final service = _service((request) {
        if (request.url.path.endsWith('/refresh')) {
          return lostResponse.future;
        }
        return Future.value(http.Response('', 204));
      }, now: now);

      final refresh = session.refresh(service);
      final refreshExpectation = expectLater(
        refresh,
        throwsA(isA<RefreshException>()),
      );
      final logout = session.logout(service);
      lostResponse.complete(http.Response('{"detail":"response lost"}', 500));
      await refreshExpectation;
      final result = await logout;

      expect(result.remoteLogoutConfirmed, isFalse);
      expect(result.message, contains('could not be confirmed'));
    },
  );

  test('delayed profile response cannot restore logged-out session', () async {
    final store = _Store();
    final session = await _verifiedSession(store, now);
    final profileResponse = Completer<http.Response>();
    final service = _service((request) {
      if (request.url.path.endsWith('/me')) return profileResponse.future;
      return Future.value(http.Response('', 204));
    });

    final profile = session.getCurrentUser(service);
    await session.logout(service);
    profileResponse.complete(_profileResponse());
    await profile;

    expect(session.state, AuthSessionState.unauthenticated);
    expect(session.profile, isNull);
  });

  test('a new verified login works after logout', () async {
    final store = _Store();
    final session = await _verifiedSession(store, now);
    await session.logout(_service((_) async => http.Response('', 204)));

    final newer = _tokens(now, refresh: 'new-login-refresh');
    await session.establishVerified(newer, _profile());
    expect(session.state, AuthSessionState.authenticated);
    expect(session.refreshToken, 'new-login-refresh');
    expect(store.session?.refreshToken, 'new-login-refresh');
  });
}

Future<AuthSession> _verifiedSession(_Store store, DateTime now) async {
  final session = AuthSession(tokenStore: store, clock: () => now);
  await session.establishVerified(_tokens(now), _profile());
  return session;
}

Future<AuthSession> _restored(_Store store) async {
  final session = AuthSession(tokenStore: store);
  await session.restore(_service((_) async => _profileResponse()));
  return session;
}

AuthService _service(MockClientHandler handler, {DateTime? now}) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  clock: now == null ? null : () => now,
);

LoginResponse _tokens(DateTime now, {String refresh = 'old-refresh'}) =>
    LoginResponse(
      accessToken: 'old-access',
      refreshToken: refresh,
      issuedAt: now,
      expiresIn: const Duration(minutes: 30),
      refreshExpiresIn: const Duration(days: 7),
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

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 12,
    'name': 'Logout Farmer',
    'email': 'logout@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);

UserProfile _profile() => UserProfile(
  id: 12,
  name: 'Logout Farmer',
  email: 'logout@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 10, 20),
);

class _Store implements AuthTokenStore {
  LoginResponse? session;
  int clearCount = 0;
  bool failClear = false;

  @override
  Future<void> clearSession() async {
    clearCount += 1;
    if (failClear) {
      throw const AuthTokenStoreException('private storage failure');
    }
    session = null;
  }

  @override
  Future<LoginResponse?> readSession() async => session;

  @override
  Future<void> saveSession(LoginResponse value) async => session = value;
}
