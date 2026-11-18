import 'dart:convert';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/auth_session.dart';
import 'models/crop_cycle.dart';

class CropCycleService {
  CropCycleService({
    required this.apiClient,
    required this.session,
    required this.authService,
  });

  final ApiClient apiClient;
  final AuthSession session;
  final AuthService authService;

  Future<CropCyclePage> listCropCycles({
    int limit = 20,
    int offset = 0,
    int? farmId,
  }) async {
    if (limit < 1 ||
        limit > 100 ||
        offset < 0 ||
        (farmId != null && farmId <= 0)) {
      throw const CropCycleException(
        CropCycleFailureType.validation,
        'The crop cycle page request is invalid.',
      );
    }
    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (farmId != null) 'farm_id': '$farmId',
    };
    final response = await _authenticatedGet(
      ApiConfig.endpoint('/api/v1/crops').replace(queryParameters: query),
    );
    if (response.statusCode != 200) {
      throw _statusException(response.statusCode, listing: true);
    }
    try {
      final body = response.body;
      if (body is! List) throw const FormatException();
      final crops = body.map(CropCycle.fromJson).toList(growable: false);
      if (farmId != null && crops.any((crop) => crop.farmId != farmId)) {
        throw const FormatException();
      }
      return CropCyclePage(crops: crops, limit: limit, offset: offset);
    } on FormatException {
      throw _invalidResponse();
    }
  }

  Future<CropCycle> getCropCycle(int cropCycleId) async {
    _validateId(cropCycleId);
    final response = await _authenticatedGet(
      ApiConfig.endpoint('/api/v1/crops/$cropCycleId'),
    );
    if (response.statusCode != 200) {
      throw _statusException(response.statusCode);
    }
    final crop = _parseCrop(response.body);
    if (crop.id != cropCycleId) throw _invalidResponse();
    return crop;
  }

  Future<CropCycle> createCropCycle(CropCycleCreate request) async {
    final payload = _serializePayload(request.toJson);
    final access = await _access();
    try {
      final response = await apiClient.postJsonWithHeaders(
        ApiConfig.endpoint('/api/v1/crops'),
        payload,
        headers: _authorization(access.accessToken),
      );
      _ensureCurrent(access.generation);
      if (response.statusCode != 201) {
        throw _statusException(response.statusCode);
      }
      try {
        final crop = CropCycle.fromJson(response.body);
        if (crop.farmId != request.farmId) throw const FormatException();
        return crop;
      } on FormatException {
        throw const CropCycleException(
          CropCycleFailureType.ambiguousCreation,
          'The creation result could not be confirmed. Refresh crop cycles before trying again.',
        );
      }
    } on ApiException catch (error) {
      _ensureCurrent(access.generation);
      if (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.invalidResponse) {
        throw const CropCycleException(
          CropCycleFailureType.ambiguousCreation,
          'The creation result could not be confirmed. Refresh crop cycles before trying again.',
        );
      }
      throw _transportException(error);
    }
  }

  Future<CropCycle> updateCropCycle(
    int cropCycleId,
    CropCycleUpdate request,
  ) async {
    _validateId(cropCycleId);
    final payload = _serializePayload(request.toJson);
    final access = await _access();
    try {
      final response = await apiClient.putJsonWithHeaders(
        ApiConfig.endpoint('/api/v1/crops/$cropCycleId'),
        payload,
        headers: _authorization(access.accessToken),
      );
      _ensureCurrent(access.generation);
      if (response.statusCode != 200) {
        throw _statusException(response.statusCode);
      }
      try {
        final crop = CropCycle.fromJson(response.body);
        if (crop.id != cropCycleId) throw const FormatException();
        return crop;
      } on FormatException {
        throw const CropCycleException(
          CropCycleFailureType.ambiguousUpdate,
          'The update result could not be confirmed. Reload the crop cycle before trying again.',
        );
      }
    } on ApiException catch (error) {
      _ensureCurrent(access.generation);
      if (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.invalidResponse) {
        throw const CropCycleException(
          CropCycleFailureType.ambiguousUpdate,
          'The update result could not be confirmed. Reload the crop cycle before trying again.',
        );
      }
      throw _transportException(error);
    }
  }

  Future<void> deleteCropCycle(int cropCycleId) async {
    _validateId(cropCycleId);
    final access = await _access();
    try {
      final response = await apiClient.deleteWithHeaders(
        ApiConfig.endpoint('/api/v1/crops/$cropCycleId'),
        headers: _authorization(access.accessToken),
      );
      _ensureCurrent(access.generation);
      if (response.statusCode != 204) {
        throw _statusException(response.statusCode);
      }
    } on ApiException catch (error) {
      _ensureCurrent(access.generation);
      if (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.invalidResponse) {
        throw const CropCycleException(
          CropCycleFailureType.ambiguousDeletion,
          'The deletion result could not be confirmed. Refresh crop cycles before trying again.',
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
      _ensureCurrent(access.generation);
      throw _transportException(error);
    }
  }

  Future<AuthenticatedAccess> _access() async {
    final generation = session.generation;
    final beganAuthenticated = session.isCurrentGeneration(generation);
    try {
      return await session.authenticatedAccess(authService);
    } on RefreshException catch (error) {
      if (beganAuthenticated && !session.isCurrentGeneration(generation)) {
        throw _staleSession();
      }
      throw _refreshException(error);
    } on Object {
      if (beganAuthenticated && !session.isCurrentGeneration(generation)) {
        throw _staleSession();
      }
      throw const CropCycleException(
        CropCycleFailureType.unauthorized,
        'Your session has expired. Please log in again.',
      );
    }
  }

  Future<AuthenticatedAccess> _refresh(int generation) async {
    try {
      return await session.refreshAuthenticatedAccess(authService, generation);
    } on RefreshException catch (error) {
      if (!session.isCurrentGeneration(generation)) throw _staleSession();
      throw _refreshException(error);
    } on Object {
      if (!session.isCurrentGeneration(generation)) throw _staleSession();
      throw const CropCycleException(
        CropCycleFailureType.unauthorized,
        'Your session has expired. Please log in again.',
      );
    }
  }

  void _ensureCurrent(int generation) {
    if (!session.isCurrentGeneration(generation)) throw _staleSession();
  }

  void _validateId(int id) {
    if (id <= 0) {
      throw const CropCycleException(
        CropCycleFailureType.validation,
        'The crop cycle ID is invalid.',
      );
    }
  }

  Map<String, Object?> _serializePayload(
    Map<String, Object?> Function() serialize,
  ) {
    try {
      final payload = serialize();
      jsonEncode(payload);
      return payload;
    } on Object {
      throw const CropCycleException(
        CropCycleFailureType.validation,
        'The crop cycle information is invalid.',
      );
    }
  }

  CropCycle _parseCrop(Object? body) {
    try {
      return CropCycle.fromJson(body);
    } on FormatException {
      throw _invalidResponse();
    }
  }

  CropCycleException _transportException(ApiException error) =>
      switch (error.kind) {
        ApiErrorKind.network => const CropCycleException(
          CropCycleFailureType.network,
          'Unable to load crop cycles. Check your connection and try again.',
        ),
        ApiErrorKind.timeout => const CropCycleException(
          CropCycleFailureType.timeout,
          'The crop cycle request took too long. Please try again.',
        ),
        ApiErrorKind.http || ApiErrorKind.invalidResponse => _invalidResponse(),
      };

  CropCycleException _refreshException(
    RefreshException error,
  ) => switch (error.type) {
    RefreshFailureType.network => const CropCycleException(
      CropCycleFailureType.network,
      'Unable to refresh your session. Check your connection and try again.',
    ),
    RefreshFailureType.timeout => const CropCycleException(
      CropCycleFailureType.timeout,
      'The session refresh took too long. Please try again.',
    ),
    RefreshFailureType.server ||
    RefreshFailureType.invalidResponse => const CropCycleException(
      CropCycleFailureType.server,
      'AgroCrew could not refresh your session. Please try again.',
    ),
    RefreshFailureType.unauthorized ||
    RefreshFailureType.validation => const CropCycleException(
      CropCycleFailureType.unauthorized,
      'Your session has expired. Please log in again.',
    ),
  };

  CropCycleException _statusException(int status, {bool listing = false}) =>
      switch (status) {
        401 => const CropCycleException(
          CropCycleFailureType.unauthorized,
          'Your session has expired. Please log in again.',
        ),
        404 => const CropCycleException(
          CropCycleFailureType.notFound,
          'Crop cycle or farm not found.',
        ),
        409 => const CropCycleException(
          CropCycleFailureType.conflict,
          'This crop cycle cannot be deleted because it has related records.',
        ),
        422 => const CropCycleException(
          CropCycleFailureType.validation,
          'Please review the crop cycle information and try again.',
        ),
        >= 200 && < 300 => _invalidResponse(),
        _ => CropCycleException(
          CropCycleFailureType.server,
          listing ? 'Unable to load crop cycles. Please try again.' : 'AgroCrew could not complete the crop cycle request. Please try again.',
        ),
      };

  static CropCycleException _invalidResponse() => const CropCycleException(
    CropCycleFailureType.invalidResponse,
    'AgroCrew returned invalid crop cycle information.',
  );

  static CropCycleException _staleSession() => const CropCycleException(
    CropCycleFailureType.staleSession,
    'This crop cycle response belongs to an earlier session.',
  );

  static Map<String, String> _authorization(String token) => {
    'Authorization': 'Bearer $token',
  };
}

class CropCyclePage {
  CropCyclePage({
    required List<CropCycle> crops,
    required this.limit,
    required this.offset,
  }) : crops = List<CropCycle>.unmodifiable(crops);

  final List<CropCycle> crops;
  final int limit;
  final int offset;

  int get nextOffset => offset + crops.length;
  bool get hasMore => crops.length == limit;
}

enum CropCycleFailureType {
  unauthorized,
  notFound,
  validation,
  server,
  network,
  timeout,
  invalidResponse,
  ambiguousCreation,
  ambiguousUpdate,
  ambiguousDeletion,
  conflict,
  staleSession,
}

class CropCycleException implements Exception {
  const CropCycleException(this.type, this.message);

  final CropCycleFailureType type;
  final String message;

  @override
  String toString() => message;
}
