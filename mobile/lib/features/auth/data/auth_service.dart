import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';

class AuthService {
  AuthService(this._apiClient);

  final ApiClient _apiClient;

  Future<RegisteredUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final ApiResponse response;
    try {
      response = await _apiClient.postJson(
        ApiConfig.endpoint('/api/v1/auth/register'),
        {'name': name, 'email': email, 'password': password},
      );
    } on ApiException catch (error) {
      switch (error.kind) {
        case ApiErrorKind.network:
          throw const RegistrationException(
            RegistrationFailureType.network,
            'Unable to connect to AgroCrew. Check your connection and try again.',
          );
        case ApiErrorKind.timeout:
          throw const RegistrationException(
            RegistrationFailureType.timeout,
            'The request took too long. Check your connection and try again.',
          );
        case ApiErrorKind.http:
        case ApiErrorKind.invalidResponse:
          throw const RegistrationException(
            RegistrationFailureType.invalidResponse,
            'AgroCrew returned an unexpected response. Please try again.',
          );
      }
    }

    switch (response.statusCode) {
      case 201:
        return _parseRegisteredUser(response.body);
      case 409:
        throw const RegistrationException(
          RegistrationFailureType.duplicateEmail,
          'This email address is already registered.',
        );
      case 422:
        throw const RegistrationException(
          RegistrationFailureType.validation,
          'Please review your registration information and try again.',
        );
      default:
        throw const RegistrationException(
          RegistrationFailureType.server,
          'AgroCrew could not create your account right now. Please try again.',
        );
    }
  }

  RegisteredUser _parseRegisteredUser(Map<String, dynamic> body) {
    final id = body['id'];
    final name = body['name'];
    final email = body['email'];
    final preferredLanguage = body['preferred_language'];
    final isActive = body['is_active'];
    final createdAtValue = body['created_at'];
    final createdAt = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)
        : null;

    if (id is! int ||
        id <= 0 ||
        name is! String ||
        name.isEmpty ||
        email is! String ||
        email.isEmpty ||
        preferredLanguage is! String ||
        preferredLanguage.isEmpty ||
        isActive is! bool ||
        createdAt == null) {
      throw const RegistrationException(
        RegistrationFailureType.invalidResponse,
        'AgroCrew returned an unexpected response. Please try again.',
      );
    }

    return RegisteredUser(
      id: id,
      name: name,
      email: email,
      preferredLanguage: preferredLanguage,
      isActive: isActive,
      createdAt: createdAt,
    );
  }

  void close() => _apiClient.close();
}

class RegisteredUser {
  const RegisteredUser({
    required this.id,
    required this.name,
    required this.email,
    required this.preferredLanguage,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String preferredLanguage;
  final bool isActive;
  final DateTime createdAt;
}

enum RegistrationFailureType {
  duplicateEmail,
  validation,
  server,
  network,
  timeout,
  invalidResponse,
}

class RegistrationException implements Exception {
  const RegistrationException(this.type, this.message);

  final RegistrationFailureType type;
  final String message;

  @override
  String toString() => message;
}
