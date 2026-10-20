import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import 'models/login_response.dart';
import 'models/user_profile.dart';

class AuthService {
  AuthService(this._apiClient, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final ApiClient _apiClient;
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  Future<RegisteredUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final ApiResponse response;
    try {
      response = await _apiClient.postJson(
        ApiConfig.endpoint('/api/v1/auth/register'),
        {
          'name': name,
          'email': email.trim().toLowerCase(),
          'password': password,
        },
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

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final ApiResponse response;
    try {
      response = await _apiClient.postJson(
        ApiConfig.endpoint('/api/v1/auth/login'),
        {'email': email.trim().toLowerCase(), 'password': password},
      );
    } on ApiException catch (error) {
      throw _loginTransportException(error);
    }

    switch (response.statusCode) {
      case 200:
        return _parseLoginResponse(response.body);
      case 401:
        throw const LoginException(
          LoginFailureType.invalidCredentials,
          'Invalid email or password.',
        );
      case 422:
        throw const LoginException(
          LoginFailureType.validation,
          'Please review your email and password and try again.',
        );
      default:
        throw const LoginException(
          LoginFailureType.server,
          'AgroCrew could not log you in right now. Please try again.',
        );
    }
  }

  Future<LoginResponse> refreshSession(String refreshToken) async {
    final ApiResponse response;
    try {
      response = await _apiClient.postJson(
        ApiConfig.endpoint('/api/v1/auth/refresh'),
        {'refresh_token': refreshToken},
      );
    } on ApiException catch (error) {
      throw switch (error.kind) {
        ApiErrorKind.network => const RefreshException(
          RefreshFailureType.network,
          'Unable to refresh your session. Check your connection and retry.',
        ),
        ApiErrorKind.timeout => const RefreshException(
          RefreshFailureType.timeout,
          'Session refresh took too long. Check your connection and retry.',
        ),
        ApiErrorKind.http ||
        ApiErrorKind.invalidResponse => const RefreshException(
          RefreshFailureType.invalidResponse,
          'AgroCrew returned an unexpected refresh response. Please retry.',
        ),
      };
    }

    switch (response.statusCode) {
      case 200:
        try {
          return _parseLoginResponse(response.body);
        } on LoginException {
          throw const RefreshException(
            RefreshFailureType.invalidResponse,
            'AgroCrew returned an unexpected refresh response. Please retry.',
          );
        }
      case 401:
        throw const RefreshException(
          RefreshFailureType.unauthorized,
          'Your session has expired. Please log in again.',
        );
      case 422:
        throw const RefreshException(
          RefreshFailureType.validation,
          'Your saved session is invalid. Please log in again.',
        );
      default:
        throw const RefreshException(
          RefreshFailureType.server,
          'AgroCrew could not refresh your session right now. Please retry.',
        );
    }
  }

  Future<UserProfile> getCurrentUser(String accessToken) async {
    final ApiResponse response;
    try {
      response = await _apiClient.getJsonResponse(
        ApiConfig.endpoint('/api/v1/auth/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } on ApiException catch (error) {
      switch (error.kind) {
        case ApiErrorKind.network:
          throw const ProfileException(
            ProfileFailureType.network,
            'Unable to verify your profile. Check your connection and retry.',
          );
        case ApiErrorKind.timeout:
          throw const ProfileException(
            ProfileFailureType.timeout,
            'Profile verification took too long. Please retry.',
          );
        case ApiErrorKind.http:
        case ApiErrorKind.invalidResponse:
          throw const ProfileException(
            ProfileFailureType.invalidResponse,
            'AgroCrew returned an unexpected profile response. Please retry.',
          );
      }
    }

    switch (response.statusCode) {
      case 200:
        return _parseUserProfile(response.body);
      case 401:
        throw const ProfileException(
          ProfileFailureType.unauthorized,
          'Your session is no longer valid. Please log in again.',
        );
      default:
        throw const ProfileException(
          ProfileFailureType.server,
          'AgroCrew could not verify your profile right now. Please retry.',
        );
    }
  }

  LoginResponse _parseLoginResponse(Map<String, dynamic> body) {
    final accessToken = body['access_token'];
    final refreshToken = body['refresh_token'];
    final tokenType = body['token_type'];
    final expiresIn = body['expires_in'];
    final refreshExpiresIn = body['refresh_expires_in'];
    if (accessToken is! String ||
        accessToken.trim().isEmpty ||
        refreshToken is! String ||
        refreshToken.trim().isEmpty ||
        tokenType is! String ||
        tokenType.toLowerCase() != 'bearer' ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        refreshExpiresIn is! int ||
        refreshExpiresIn <= 0) {
      throw const LoginException(
        LoginFailureType.invalidResponse,
        'AgroCrew returned an unexpected login response. Please try again.',
      );
    }
    return LoginResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: Duration(seconds: expiresIn),
      refreshExpiresIn: Duration(seconds: refreshExpiresIn),
      issuedAt: _clock().toUtc(),
    );
  }

  UserProfile _parseUserProfile(Map<String, dynamic> body) {
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
      throw const ProfileException(
        ProfileFailureType.invalidResponse,
        'AgroCrew returned an unexpected profile response. Please retry.',
      );
    }
    return UserProfile(
      id: id,
      name: name,
      email: email,
      preferredLanguage: preferredLanguage,
      isActive: isActive,
      createdAt: createdAt,
    );
  }

  LoginException _loginTransportException(ApiException error) {
    return switch (error.kind) {
      ApiErrorKind.network => const LoginException(
        LoginFailureType.network,
        'Unable to connect to AgroCrew. Check your connection and try again.',
      ),
      ApiErrorKind.timeout => const LoginException(
        LoginFailureType.timeout,
        'The login request took too long. Check your connection and try again.',
      ),
      ApiErrorKind.http || ApiErrorKind.invalidResponse => const LoginException(
        LoginFailureType.invalidResponse,
        'AgroCrew returned an unexpected login response. Please try again.',
      ),
    };
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

enum LoginFailureType {
  invalidCredentials,
  validation,
  server,
  network,
  timeout,
  invalidResponse,
}

class LoginException implements Exception {
  const LoginException(this.type, this.message);

  final LoginFailureType type;
  final String message;

  @override
  String toString() => message;
}

enum RefreshFailureType {
  unauthorized,
  validation,
  server,
  network,
  timeout,
  invalidResponse,
}

class RefreshException implements Exception {
  const RefreshException(this.type, this.message);

  final RefreshFailureType type;
  final String message;

  bool get isPermanent =>
      type == RefreshFailureType.unauthorized ||
      type == RefreshFailureType.validation;

  @override
  String toString() => message;
}

enum ProfileFailureType {
  unauthorized,
  server,
  network,
  timeout,
  invalidResponse,
}

class ProfileException implements Exception {
  const ProfileException(this.type, this.message);

  final ProfileFailureType type;
  final String message;

  @override
  String toString() => message;
}
