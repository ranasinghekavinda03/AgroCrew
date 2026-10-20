import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'auth_token_store.dart';
import 'models/login_response.dart';
import 'models/user_profile.dart';

enum AuthSessionState {
  unauthenticated,
  restoring,
  authenticated,
  requiresLogin,
  verificationError,
}

class AuthSession extends ChangeNotifier {
  AuthSession({
    AuthTokenStore? tokenStore,
    DateTime Function()? clock,
    this.refreshSkew = const Duration(seconds: 45),
  }) : _tokenStore = tokenStore ?? MemoryAuthTokenStore(),
       _clock = clock ?? _utcNow;

  final AuthTokenStore _tokenStore;
  final DateTime Function() _clock;
  final Duration refreshSkew;
  LoginResponse? _tokens;
  UserProfile? _profile;
  AuthSessionState _state = AuthSessionState.unauthenticated;
  String? _message;
  Future<void>? _restoreOperation;
  Future<LoginResponse>? _refreshOperation;
  int _generation = 0;

  static DateTime _utcNow() => DateTime.now().toUtc();

  AuthSessionState get state => _state;
  String? get message => _message;
  bool get hasTokens => _tokens != null;
  String? get accessToken => _tokens?.accessToken;
  String? get refreshToken => _tokens?.refreshToken;
  DateTime? get accessTokenExpiresAt => _tokens?.accessTokenExpiresAt;
  DateTime? get refreshTokenExpiresAt => _tokens?.refreshTokenExpiresAt;
  UserProfile? get profile => _profile;
  bool get isVerified => _tokens != null && _profile != null;

  Future<void> establishVerified(
    LoginResponse response,
    UserProfile profile,
  ) async {
    _generation += 1;
    final refresh = _refreshOperation;
    if (refresh != null) {
      try {
        await refresh;
      } on Object {
        // A new verified login supersedes any older refresh result.
      }
    }
    await _tokenStore.saveSession(response);
    _tokens = response;
    _profile = profile;
    _state = AuthSessionState.authenticated;
    _message = null;
    notifyListeners();
  }

  Future<void> restore(AuthService authService, {DateTime? now}) {
    return _restoreOperation ??= _restore(
      authService,
      now?.toUtc(),
    ).whenComplete(() => _restoreOperation = null);
  }

  Future<LoginResponse> refresh(AuthService authService) {
    final tokens = _tokens;
    if (tokens == null) {
      return Future<LoginResponse>.error(
        const RefreshException(
          RefreshFailureType.validation,
          'Your session has expired. Please log in again.',
        ),
      );
    }
    return _refreshSingleFlight(authService, tokens, _generation);
  }

  /// Performs the current safe protected request with proactive refresh and a
  /// single refresh-and-retry on an unexpected 401.
  Future<UserProfile> getCurrentUser(AuthService authService) =>
      _verifyCurrentUser(authService, _generation);

  Future<void> _restore(AuthService authService, DateTime? suppliedNow) async {
    final generation = ++_generation;
    _state = AuthSessionState.restoring;
    _message = 'Restoring your session...';
    notifyListeners();
    try {
      final saved = await _tokenStore.readSession();
      if (generation != _generation) return;
      if (saved == null) {
        _setUnauthenticated();
        return;
      }
      _tokens = saved;
      final profile = await _verifyCurrentUser(
        authService,
        generation,
        suppliedNow: suppliedNow,
      );
      if (generation != _generation) return;
      _profile = profile;
      _state = AuthSessionState.authenticated;
      _message = null;
      notifyListeners();
    } on _StaleSessionException {
      return;
    } on RefreshException catch (error) {
      if (generation != _generation) return;
      if (error.isPermanent) {
        await _clearAndRequireLogin(error.message, generation);
      } else {
        _setVerificationError(
          'Unable to verify your session. Please check your connection and try again.',
        );
      }
    } on ProfileException catch (error) {
      if (generation != _generation) return;
      if (error.type == ProfileFailureType.unauthorized) {
        await _clearAndRequireLogin(error.message, generation);
      } else {
        _setVerificationError(error.message);
      }
    } on AuthTokenStoreException catch (error) {
      if (generation == _generation &&
          _state != AuthSessionState.requiresLogin) {
        _setVerificationError(error.message);
      }
    } on Object {
      if (generation == _generation) {
        _setVerificationError(
          'Your session could not be verified. Please try again.',
        );
      }
    }
  }

  Future<UserProfile> _verifyCurrentUser(
    AuthService authService,
    int generation, {
    DateTime? suppliedNow,
  }) async {
    var tokens = _requireCurrentTokens(generation);
    var refreshed = false;
    final now = suppliedNow ?? _clock().toUtc();
    if (_needsRefresh(tokens, now)) {
      if (!_canRefresh(tokens, now)) {
        throw const RefreshException(
          RefreshFailureType.unauthorized,
          'Your session has expired. Please log in again.',
        );
      }
      _message = 'Refreshing your session...';
      notifyListeners();
      tokens = await _refreshSingleFlight(authService, tokens, generation);
      refreshed = true;
    }

    try {
      return await authService.getCurrentUser(tokens.accessToken);
    } on ProfileException catch (error) {
      if (error.type != ProfileFailureType.unauthorized || refreshed) rethrow;
      tokens = _requireCurrentTokens(generation);
      if (!_canRefresh(tokens, _clock().toUtc())) {
        throw const RefreshException(
          RefreshFailureType.unauthorized,
          'Your session has expired. Please log in again.',
        );
      }
      _message = 'Refreshing your session...';
      notifyListeners();
      final rotated = await _refreshSingleFlight(
        authService,
        tokens,
        generation,
      );
      return authService.getCurrentUser(rotated.accessToken);
    }
  }

  bool _needsRefresh(LoginResponse tokens, DateTime now) =>
      !tokens.accessTokenExpiresAt.isAfter(now.add(refreshSkew));

  bool _canRefresh(LoginResponse tokens, DateTime now) =>
      tokens.refreshToken.trim().isNotEmpty &&
      tokens.refreshTokenExpiresAt.isAfter(now);

  LoginResponse _requireCurrentTokens(int generation) {
    final tokens = _tokens;
    if (generation != _generation || tokens == null) {
      throw const _StaleSessionException();
    }
    return tokens;
  }

  Future<LoginResponse> _refreshSingleFlight(
    AuthService authService,
    LoginResponse source,
    int generation,
  ) async {
    final active = _refreshOperation;
    if (active != null) return active;

    late final Future<LoginResponse> operation;
    operation = _performRefresh(authService, source, generation);
    _refreshOperation = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshOperation, operation)) _refreshOperation = null;
    }
  }

  Future<LoginResponse> _performRefresh(
    AuthService authService,
    LoginResponse source,
    int generation,
  ) async {
    if (!_canRefresh(source, _clock().toUtc())) {
      throw const RefreshException(
        RefreshFailureType.unauthorized,
        'Your session has expired. Please log in again.',
      );
    }
    final rotated = await authService.refreshSession(source.refreshToken);
    final current = _requireCurrentTokens(generation);
    if (current.refreshToken != source.refreshToken) {
      throw const _StaleSessionException();
    }
    try {
      await _tokenStore.saveSession(rotated);
    } on AuthTokenStoreException {
      try {
        await _tokenStore.clearSession();
      } on AuthTokenStoreException {
        // Memory is still failed closed even if secure cleanup also fails.
      }
      if (generation == _generation) {
        _tokens = null;
        _profile = null;
        _state = AuthSessionState.requiresLogin;
        _message = 'Your refreshed session could not be saved securely. Please log in again.';
        notifyListeners();
      }
      throw const AuthTokenStoreException(
        'Your refreshed session could not be saved securely. Please log in again.',
      );
    }
    _requireCurrentTokens(generation);
    _tokens = rotated;
    return rotated;
  }

  Future<void> _clearAndRequireLogin(String message, int generation) async {
    try {
      await _tokenStore.clearSession();
    } on AuthTokenStoreException {
      if (generation != _generation) return;
      _tokens = null;
      _profile = null;
      _state = AuthSessionState.requiresLogin;
      _message = '$message Saved credentials could not be removed securely.';
      notifyListeners();
      return;
    }
    if (generation != _generation) return;
    _tokens = null;
    _profile = null;
    _state = AuthSessionState.requiresLogin;
    _message = message;
    notifyListeners();
  }

  void _setUnauthenticated() {
    _tokens = null;
    _profile = null;
    _state = AuthSessionState.unauthenticated;
    _message = null;
    notifyListeners();
  }

  void _setVerificationError(String message) {
    _profile = null;
    _state = AuthSessionState.verificationError;
    _message = message;
    notifyListeners();
  }
}

class _StaleSessionException implements Exception {
  const _StaleSessionException();
}
