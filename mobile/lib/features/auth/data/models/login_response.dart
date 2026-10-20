class LoginResponse {
  LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.refreshExpiresIn,
    DateTime? issuedAt,
  }) : issuedAt = issuedAt ?? DateTime.now().toUtc();

  final String accessToken;
  final String refreshToken;
  final Duration expiresIn;
  final Duration refreshExpiresIn;
  final DateTime issuedAt;

  DateTime get accessTokenExpiresAt => issuedAt.add(expiresIn);
  DateTime get refreshTokenExpiresAt => issuedAt.add(refreshExpiresIn);
}
