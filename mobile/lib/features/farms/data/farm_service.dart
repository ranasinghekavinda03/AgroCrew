import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/auth_session.dart';
import 'models/farm.dart';

class FarmService {
  FarmService({
    required this.apiClient,
    required this.session,
    required this.authService,
  });

  final ApiClient apiClient;
  final AuthSession session;
  final AuthService authService;

  Future<FarmPage> listFarms({int limit = 20, int offset = 0}) async {
    if (limit < 1 || limit > 100 || offset < 0) {
      throw const FarmException(
        FarmFailureType.validation,
        'The farm page request is invalid.',
      );
    }
    final response = await _authenticatedGet(
      ApiConfig.endpoint('/api/v1/farms')
          .replace(queryParameters: {'limit': '$limit', 'offset': '$offset'}),
    );
    if (response.statusCode != 200) {
      throw _statusException(response.statusCode, listing: true);
    }
    try {
      final body = response.body;
      if (body is! List) throw const FormatException();
      final farms = body.map(Farm.fromJson).toList(growable: false);
      return FarmPage(
        farms: farms,
        offset: offset,
        hasMore: farms.length == limit,
      );
    } on FormatException {
      throw const FarmException(
        FarmFailureType.invalidResponse,
        'AgroCrew returned invalid farm information.',
      );
    }
  }

  Future<Farm> getFarm(int farmId) async {
    if (farmId <= 0) {
      throw const FarmException(
        FarmFailureType.validation,
        'The farm ID is invalid.',
      );
    }
    final response = await _authenticatedGet(
      ApiConfig.endpoint('/api/v1/farms/$farmId'),
    );
    if (response.statusCode != 200) {
      throw _statusException(response.statusCode);
    }
    return _parseFarm(response.body);
  }

  Future<Farm> createFarm(FarmCreate request) async {
    final access = await _access();
    try {
      final response = await apiClient.postJsonWithHeaders(
        ApiConfig.endpoint('/api/v1/farms'),
        request.toJson(),
        headers: _authorization(access.accessToken),
      );
      _ensureCurrent(access.generation);
      if (response.statusCode != 201) {
        throw _statusException(response.statusCode);
      }
      return _parseFarm(response.body);
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout) {
        throw const FarmException(
          FarmFailureType.ambiguousCreation,
          'The result could not be confirmed. Review My Farms before trying again.',
        );
      }
      throw _transportException(error);
    }
  }

  Future<ApiDecodedResponse> _authenticatedGet(Uri uri) async {
    var access = await _access();
    try {
      var response = await apiClient.getDecodedResponse(
        uri,
        headers: _authorization(access.accessToken),
      );
      _ensureCurrent(access.generation);
      if (response.statusCode == 401) {
        access = await _refresh(access.generation);
        response = await apiClient.getDecodedResponse(
          uri,
          headers: _authorization(access.accessToken),
        );
        _ensureCurrent(access.generation);
      }
      return response;
    } on ApiException catch (error) {
      throw _transportException(error);
    }
  }

  Future<AuthenticatedAccess> _access() async {
    try {
      return await session.authenticatedAccess(authService);
    } on RefreshException catch (error) {
      throw _refreshException(error);
    } on Object {
      throw const FarmException(
        FarmFailureType.unauthorized,
        'Your session has expired. Please log in again.',
      );
    }
  }

  Future<AuthenticatedAccess> _refresh(int generation) async {
    try {
      return await session.refreshAuthenticatedAccess(authService, generation);
    } on RefreshException catch (error) {
      throw _refreshException(error);
    } on Object {
      throw const FarmException(
        FarmFailureType.unauthorized,
        'Your session has expired. Please log in again.',
      );
    }
  }

  void _ensureCurrent(int generation) {
    if (!session.isCurrentGeneration(generation)) {
      throw const FarmException(
        FarmFailureType.staleSession,
        'This farm response belongs to an earlier session.',
      );
    }
  }

  Farm _parseFarm(Object? body) {
    try {
      return Farm.fromJson(body);
    } on FormatException {
      throw const FarmException(
        FarmFailureType.invalidResponse,
        'AgroCrew returned invalid farm information.',
      );
    }
  }

  FarmException _transportException(ApiException error) => switch (error.kind) {
    ApiErrorKind.network => const FarmException(
      FarmFailureType.network,
      'Unable to load your farms. Check your connection and try again.',
    ),
    ApiErrorKind.timeout => const FarmException(
      FarmFailureType.timeout,
      'The farm request took too long. Please try again.',
    ),
    ApiErrorKind.http || ApiErrorKind.invalidResponse => const FarmException(
      FarmFailureType.invalidResponse,
      'AgroCrew returned an unexpected farm response.',
    ),
  };

  FarmException _refreshException(
    RefreshException error,
  ) => switch (error.type) {
    RefreshFailureType.network => const FarmException(
      FarmFailureType.network,
      'Unable to refresh your session. Check your connection and try again.',
    ),
    RefreshFailureType.timeout => const FarmException(
      FarmFailureType.timeout,
      'The session refresh took too long. Please try again.',
    ),
    RefreshFailureType.server ||
    RefreshFailureType.invalidResponse => const FarmException(
      FarmFailureType.server,
      'AgroCrew could not refresh your session. Please try again.',
    ),
    RefreshFailureType.unauthorized ||
    RefreshFailureType.validation => const FarmException(
      FarmFailureType.unauthorized,
      'Your session has expired. Please log in again.',
    ),
  };

  FarmException _statusException(
    int status, {
    bool listing = false,
  }) => switch (status) {
    401 => const FarmException(
      FarmFailureType.unauthorized,
      'Your session has expired. Please log in again.',
    ),
    404 => const FarmException(FarmFailureType.notFound, 'Farm not found.'),
    422 => const FarmException(
      FarmFailureType.validation,
      'Please review the farm information and try again.',
    ),
    _ => FarmException(
      FarmFailureType.server,
      listing
          ? 'Unable to load your farms. Check your connection and try again.'
          : 'AgroCrew could not complete the farm request. Please try again.',
    ),
  };

  static Map<String, String> _authorization(String token) => {
    'Authorization': 'Bearer $token',
  };
}

class FarmPage {
  const FarmPage({
    required this.farms,
    required this.offset,
    required this.hasMore,
  });

  final List<Farm> farms;
  final int offset;
  final bool hasMore;
}

enum FarmFailureType {
  unauthorized,
  notFound,
  validation,
  server,
  network,
  timeout,
  invalidResponse,
  ambiguousCreation,
  staleSession,
}

class FarmException implements Exception {
  const FarmException(this.type, this.message);

  final FarmFailureType type;
  final String message;

  @override
  String toString() => message;
}
