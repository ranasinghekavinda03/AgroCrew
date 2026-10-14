import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 8)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode != 200) {
        throw ApiException('The backend returned HTTP ${response.statusCode}.');
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (error) {
        throw ApiException('The backend returned invalid JSON.', error);
      }

      if (decoded is! Map<String, dynamic>) {
        throw const ApiException(
          'The backend returned an unexpected response.',
        );
      }

      return decoded;
    } on TimeoutException catch (error) {
      throw ApiException('The backend request timed out.', error);
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw ApiException('Unable to connect to the backend.', error);
    }
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  const ApiException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
