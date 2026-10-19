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
        throw ApiException(
          'The backend returned HTTP ${response.statusCode}.',
          kind: ApiErrorKind.http,
        );
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (error) {
        throw ApiException(
          'The backend returned invalid JSON.',
          cause: error,
          kind: ApiErrorKind.invalidResponse,
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const ApiException(
          'The backend returned an unexpected response.',
          kind: ApiErrorKind.invalidResponse,
        );
      }

      return decoded;
    } on TimeoutException catch (error) {
      throw ApiException(
        'The backend request timed out.',
        cause: error,
        kind: ApiErrorKind.timeout,
      );
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw ApiException(
        'Unable to connect to the backend.',
        cause: error,
        kind: ApiErrorKind.network,
      );
    }
  }

  Future<ApiResponse> postJson(Uri uri, Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (error) {
        throw ApiException(
          'The backend returned invalid JSON.',
          cause: error,
          kind: ApiErrorKind.invalidResponse,
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const ApiException(
          'The backend returned an unexpected response.',
          kind: ApiErrorKind.invalidResponse,
        );
      }

      return ApiResponse(statusCode: response.statusCode, body: decoded);
    } on TimeoutException catch (error) {
      throw ApiException(
        'The backend request timed out.',
        cause: error,
        kind: ApiErrorKind.timeout,
      );
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw ApiException(
        'Unable to connect to the backend.',
        cause: error,
        kind: ApiErrorKind.network,
      );
    }
  }

  void close() => _client.close();
}

class ApiResponse {
  const ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;
}

enum ApiErrorKind { http, network, timeout, invalidResponse }

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.cause,
    this.kind = ApiErrorKind.invalidResponse,
  });

  final String message;
  final Object? cause;
  final ApiErrorKind kind;

  @override
  String toString() => message;
}
