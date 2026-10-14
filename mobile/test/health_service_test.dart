import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/home/data/health_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HealthService', () {
    test('accepts an HTTP 200 response with the expected JSON', () async {
      final service = _serviceWith((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/health');
        return http.Response('{"status":"ok","service":"agrocrew-api"}', 200);
      });

      final result = await service.checkHealth();

      expect(result.status, 'ok');
      expect(result.service, 'agrocrew-api');
    });

    test('rejects a server error response', () async {
      final service = _serviceWith(
        (_) async => http.Response('Server error', 500),
      );

      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });

    test('rejects invalid JSON', () async {
      final service = _serviceWith((_) async => http.Response('not-json', 200));

      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('invalid JSON'),
          ),
        ),
      );
    });

    test('rejects unexpected health values', () async {
      final service = _serviceWith((_) async {
        return http.Response(
          '{"status":"degraded","service":"another-api"}',
          200,
        );
      });

      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('unexpected values'),
          ),
        ),
      );
    });

    test('wraps a network connection failure', () async {
      final service = _serviceWith((request) async {
        throw http.ClientException('Connection refused', request.url);
      });

      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Unable to connect'),
          ),
        ),
      );
    });

    test('reports a request timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      });
      final service = HealthService(
        ApiClient(client: client, timeout: const Duration(milliseconds: 1)),
      );

      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });
}

HealthService _serviceWith(MockClientHandler handler) {
  return HealthService(
    ApiClient(client: MockClient(handler), timeout: const Duration(seconds: 1)),
  );
}
