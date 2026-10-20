import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuthService login', () {
    test(
      'normalizes email without modifying the password on HTTP 200',
      () async {
        const password = '  Exact Password  ';
        final service = _serviceWith((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/auth/login');
          expect(jsonDecode(request.body), {
            'email': 'farmer@example.com',
            'password': password,
          });
          return _loginResponse();
        });

        final result = await service.login(
          email: '  FARMER@EXAMPLE.COM ',
          password: password,
        );

        expect(result.accessToken, 'signed.jwt.value');
        expect(result.refreshToken, 'opaque-refresh-value');
        expect(result.expiresIn, const Duration(seconds: 1800));
        expect(result.refreshExpiresIn, const Duration(seconds: 604800));
      },
    );

    for (final scenario in [
      (401, LoginFailureType.invalidCredentials, 'Invalid email or password.'),
      (422, LoginFailureType.validation, 'review your email and password'),
      (500, LoginFailureType.server, 'could not log you in'),
    ]) {
      test('maps HTTP ${scenario.$1} to a safe error', () async {
        final service = _serviceWith(
          (_) async => http.Response('{"detail":"private"}', scenario.$1),
        );
        await expectLater(
          _login(service),
          throwsA(
            isA<LoginException>()
                .having((error) => error.type, 'type', scenario.$2)
                .having(
                  (error) => error.message,
                  'safe message',
                  contains(scenario.$3),
                ),
          ),
        );
      });
    }

    test('maps a network failure safely', () async {
      final service = _serviceWith((request) async {
        throw http.ClientException('password=SecretValue', request.url);
      });
      await expectLater(
        _login(service, password: 'SecretValue'),
        throwsA(
          isA<LoginException>()
              .having((error) => error.type, 'type', LoginFailureType.network)
              .having(
                (error) => error.message,
                'message',
                isNot(contains('SecretValue')),
              ),
        ),
      );
    });

    test('maps a timeout safely', () async {
      final service = AuthService(
        ApiClient(
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return _loginResponse();
          }),
          timeout: const Duration(milliseconds: 1),
        ),
      );
      await expectLater(
        _login(service),
        throwsA(
          isA<LoginException>().having(
            (error) => error.type,
            'type',
            LoginFailureType.timeout,
          ),
        ),
      );
    });

    test('rejects invalid JSON', () async {
      final service = _serviceWith((_) async => http.Response('not-json', 200));
      await expectLater(
        _login(service),
        throwsA(
          isA<LoginException>().having(
            (error) => error.type,
            'type',
            LoginFailureType.invalidResponse,
          ),
        ),
      );
    });

    for (final invalidBody in [
      {
        'refresh_token': 'refresh',
        'token_type': 'bearer',
        'expires_in': 1800,
        'refresh_expires_in': 604800,
      },
      {
        'access_token': 'access',
        'token_type': 'bearer',
        'expires_in': 1800,
        'refresh_expires_in': 604800,
      },
      {
        'access_token': 'access',
        'refresh_token': 'refresh',
        'token_type': 'basic',
        'expires_in': 1800,
        'refresh_expires_in': 604800,
      },
      {
        'access_token': 'access',
        'refresh_token': 'refresh',
        'token_type': 'bearer',
        'expires_in': 0,
        'refresh_expires_in': -1,
      },
    ]) {
      test('rejects malformed login response $invalidBody', () async {
        final service = _serviceWith(
          (_) async => http.Response(jsonEncode(invalidBody), 200),
        );
        await expectLater(_login(service), throwsA(isA<LoginException>()));
      });
    }
  });

  group('AuthService current profile', () {
    test('sends only the bearer access token and parses the profile', () async {
      final service = _serviceWith((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/auth/me');
        expect(request.headers['authorization'], 'Bearer signed.jwt.value');
        expect(request.headers.toString(), isNot(contains('opaque-refresh')));
        return _profileResponse();
      });

      final profile = await service.getCurrentUser('signed.jwt.value');
      expect(profile.name, 'Test Farmer');
      expect(profile.email, 'farmer@example.com');
      expect(profile.isActive, isTrue);
    });

    test('maps HTTP 401 to unauthorized', () async {
      final service = _serviceWith(
        (_) async => http.Response('{"detail":"invalid"}', 401),
      );
      await expectLater(
        service.getCurrentUser('rejected-token'),
        throwsA(
          isA<ProfileException>().having(
            (error) => error.type,
            'type',
            ProfileFailureType.unauthorized,
          ),
        ),
      );
    });

    test('does not invent a profile after a network failure', () async {
      final service = _serviceWith((request) async {
        throw http.ClientException('offline', request.url);
      });
      await expectLater(
        service.getCurrentUser('access-token'),
        throwsA(
          isA<ProfileException>().having(
            (error) => error.type,
            'type',
            ProfileFailureType.network,
          ),
        ),
      );
    });
  });
}

Future<dynamic> _login(
  AuthService service, {
  String password = 'StrongTestPassword123!',
}) => service.login(email: 'farmer@example.com', password: password);

AuthService _serviceWith(MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
);

http.Response _loginResponse() => http.Response(
  jsonEncode({
    'access_token': 'signed.jwt.value',
    'refresh_token': 'opaque-refresh-value',
    'token_type': 'bearer',
    'expires_in': 1800,
    'refresh_expires_in': 604800,
  }),
  200,
);

http.Response _profileResponse() => http.Response(
  jsonEncode({
    'id': 7,
    'name': 'Test Farmer',
    'email': 'farmer@example.com',
    'preferred_language': 'English',
    'is_active': true,
    'created_at': '2026-10-20T12:00:00Z',
  }),
  200,
);
