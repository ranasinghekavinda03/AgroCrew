import 'dart:convert';

import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonAuthTokenStore', () {
    late FakeKeyValueStore backend;
    late JsonAuthTokenStore store;

    setUp(() {
      backend = FakeKeyValueStore();
      store = JsonAuthTokenStore(backend);
    });

    test('saves and reads one complete versioned session record', () async {
      final session = _session();
      await store.saveSession(session);

      expect(backend.values, hasLength(1));
      final raw = backend.values[JsonAuthTokenStore.sessionKey]!;
      expect(raw, contains('access-value'));
      expect(raw, contains('refresh-value'));
      expect(raw, isNot(contains('NeverPersistThisPassword')));

      final restored = await store.readSession();
      expect(restored?.accessToken, session.accessToken);
      expect(restored?.refreshToken, session.refreshToken);
      expect(restored?.accessTokenExpiresAt, session.accessTokenExpiresAt);
      expect(restored?.refreshTokenExpiresAt, session.refreshTokenExpiresAt);
    });

    test('clears a stored session', () async {
      await store.saveSession(_session());
      await store.clearSession();
      expect(await store.readSession(), isNull);
    });

    test('returns null when no session exists', () async {
      expect(await store.readSession(), isNull);
    });

    test('clears corrupted data without crashing', () async {
      backend.values[JsonAuthTokenStore.sessionKey] = '{broken';
      expect(await store.readSession(), isNull);
      expect(backend.values, isEmpty);
    });

    test('rejects and clears incomplete data', () async {
      backend.values[JsonAuthTokenStore.sessionKey] = jsonEncode({
        'version': 1,
        'access_token': 'only-one-token',
      });
      expect(await store.readSession(), isNull);
      expect(backend.values, isEmpty);
    });

    test('sanitizes secure-storage read, write, and clear failures', () async {
      backend.failRead = true;
      await expectLater(
        store.readSession(),
        throwsA(isA<AuthTokenStoreException>()),
      );
      backend.failRead = false;
      backend.failWrite = true;
      await expectLater(
        store.saveSession(_session()),
        throwsA(isA<AuthTokenStoreException>()),
      );
      backend.failWrite = false;
      backend.failDelete = true;
      await expectLater(
        store.clearSession(),
        throwsA(isA<AuthTokenStoreException>()),
      );
    });
  });

  test('new memory stores do not restore a prior web-style session', () async {
    final firstPage = MemoryAuthTokenStore();
    await firstPage.saveSession(_session());
    expect(await firstPage.readSession(), isNotNull);

    final reloadedPage = MemoryAuthTokenStore();
    expect(await reloadedPage.readSession(), isNull);
  });
}

LoginResponse _session() => LoginResponse(
  accessToken: 'access-value',
  refreshToken: 'refresh-value',
  issuedAt: DateTime.utc(2026, 10, 21, 10),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

class FakeKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = {};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('secret read detail');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('secret write detail');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('secret clear detail');
    values.remove(key);
  }
}
