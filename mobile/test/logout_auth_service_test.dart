import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('logout posts refresh token without access authentication and accepts empty 204', () async {
    final service = _service((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/logout');
      expect(jsonDecode(request.body), {'refresh_token': 'logout-refresh'});
      expect(request.headers['authorization'], isNull);
      return http.Response('', 204);
    });

    await service.logout('logout-refresh');
  });

  for (final scenario in [
    (422, LogoutFailureType.validation),
    (500, LogoutFailureType.server),
    (418, LogoutFailureType.server),
  ]) {
    test(
      'logout maps HTTP ${scenario.$1} without exposing credentials',
      () async {
        final service = _service(
          (_) async =>
              http.Response('{"detail":"secret-refresh"}', scenario.$1),
        );

        await expectLater(
          service.logout('secret-refresh'),
          throwsA(
            isA<LogoutException>()
                .having((error) => error.type, 'type', scenario.$2)
                .having(
                  (error) => error.message,
                  'safe message',
                  isNot(contains('secret-refresh')),
                ),
          ),
        );
      },
    );
  }

  test('logout maps network failure without exposing credentials', () async {
    final service = _service((request) async {
      throw http.ClientException('secret-refresh', request.url);
    });

    await expectLater(
      service.logout('secret-refresh'),
      throwsA(
        isA<LogoutException>()
            .having((error) => error.type, 'type', LogoutFailureType.network)
            .having(
              (error) => error.message,
              'safe message',
              isNot(contains('secret-refresh')),
            ),
      ),
    );
  });

  test('logout maps timeout safely', () async {
    final service = AuthService(
      ApiClient(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('', 204);
        }),
        timeout: const Duration(milliseconds: 1),
      ),
    );

    await expectLater(
      service.logout('secret-refresh'),
      throwsA(
        isA<LogoutException>().having(
          (error) => error.type,
          'type',
          LogoutFailureType.timeout,
        ),
      ),
    );
  });
}

AuthService _service(MockClientHandler handler) => AuthService(
  ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
);
