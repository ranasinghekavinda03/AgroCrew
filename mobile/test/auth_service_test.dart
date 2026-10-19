import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuthService', () {
    test('returns a validated user for HTTP 201', () async {
      final service = _serviceWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/register');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'name': 'Test Farmer',
          'email': 'farmer@example.com',
          'password': 'StrongTestPassword123!',
        });
        expect(request.body, isNot(contains('confirm')));
        return http.Response(
          jsonEncode({
            'id': 7,
            'name': 'Test Farmer',
            'email': 'farmer@example.com',
            'preferred_language': 'English',
            'is_active': true,
            'created_at': '2026-10-19T12:00:00Z',
          }),
          201,
        );
      });

      final user = await service.register(
        name: 'Test Farmer',
        email: 'farmer@example.com',
        password: 'StrongTestPassword123!',
      );

      expect(user.id, 7);
      expect(user.name, 'Test Farmer');
      expect(user.email, 'farmer@example.com');
      expect(user.preferredLanguage, 'English');
      expect(user.isActive, isTrue);
      expect(user.createdAt.isUtc, isTrue);
    });

    test('maps HTTP 409 to the duplicate-email result', () async {
      final service = _serviceWith(
        (_) async => http.Response('{"detail":"duplicate"}', 409),
      );

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>()
              .having(
                (error) => error.type,
                'type',
                RegistrationFailureType.duplicateEmail,
              )
              .having(
                (error) => error.message,
                'message',
                'This email address is already registered.',
              ),
        ),
      );
    });

    test('maps HTTP 422 without exposing rejected values', () async {
      const sensitiveValue = 'SensitiveRejectedPassword';
      final service = _serviceWith(
        (_) async =>
            http.Response('{"detail":[{"input":"$sensitiveValue"}]}', 422),
      );

      await expectLater(
        _register(service, password: sensitiveValue),
        throwsA(
          isA<RegistrationException>()
              .having(
                (error) => error.type,
                'type',
                RegistrationFailureType.validation,
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains(sensitiveValue)),
              ),
        ),
      );
    });

    test('maps HTTP 500 to a safe server error', () async {
      final service = _serviceWith(
        (_) async => http.Response('{"detail":"internal details"}', 500),
      );

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>().having(
            (error) => error.type,
            'type',
            RegistrationFailureType.server,
          ),
        ),
      );
    });

    test('maps connection failures to a safe network error', () async {
      final service = _serviceWith((request) async {
        throw http.ClientException('Connection refused', request.url);
      });

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>()
              .having(
                (error) => error.type,
                'type',
                RegistrationFailureType.network,
              )
              .having(
                (error) => error.message,
                'message',
                'Unable to connect to AgroCrew. Check your connection and try again.',
              ),
        ),
      );
    });

    test('maps request timeouts to a safe timeout error', () async {
      final service = AuthService(
        ApiClient(
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return http.Response('{}', 201);
          }),
          timeout: const Duration(milliseconds: 1),
        ),
      );

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>().having(
            (error) => error.type,
            'type',
            RegistrationFailureType.timeout,
          ),
        ),
      );
    });

    test('rejects invalid JSON responses safely', () async {
      final service = _serviceWith((_) async => http.Response('not-json', 201));

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>().having(
            (error) => error.type,
            'type',
            RegistrationFailureType.invalidResponse,
          ),
        ),
      );
    });

    test('rejects malformed HTTP 201 response objects', () async {
      final service = _serviceWith(
        (_) async => http.Response('{"id":7,"name":"Incomplete"}', 201),
      );

      await expectLater(
        _register(service),
        throwsA(
          isA<RegistrationException>().having(
            (error) => error.type,
            'type',
            RegistrationFailureType.invalidResponse,
          ),
        ),
      );
    });
  });
}

Future<RegisteredUser> _register(
  AuthService service, {
  String password = 'StrongTestPassword123!',
}) {
  return service.register(
    name: 'Test Farmer',
    email: 'farmer@example.com',
    password: password,
  );
}

AuthService _serviceWith(MockClientHandler handler) {
  return AuthService(
    ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  );
}
