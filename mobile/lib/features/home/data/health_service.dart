import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';

class HealthService {
  HealthService(this._apiClient);

  final ApiClient _apiClient;

  Future<HealthStatus> checkHealth() async {
    final response = await _apiClient.getJson(
      ApiConfig.endpoint('/api/v1/health'),
    );
    final status = response['status'];
    final service = response['service'];

    if (status != 'ok' || service != 'agrocrew-api') {
      throw const ApiException(
        'The backend health response contained unexpected values.',
      );
    }

    return HealthStatus(status: status as String, service: service as String);
  }

  void close() => _apiClient.close();
}

class HealthStatus {
  const HealthStatus({required this.status, required this.service});

  final String status;
  final String service;
}
