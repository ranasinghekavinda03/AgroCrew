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
  AuthSession({AuthTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? MemoryAuthTokenStore();

  final AuthTokenStore _tokenStore;
  LoginResponse? _tokens;
  UserProfile? _profile;
  AuthSessionState _state = AuthSessionState.unauthenticated;
  String? _message;
  Future<void>? _restoreOperation;
  int _generation = 0;

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
      now ?? DateTime.now().toUtc(),
    ).whenComplete(() => _restoreOperation = null);
  }

  Future<void> _restore(AuthService authService, DateTime now) async {
    final generation = ++_generation;
    _state = AuthSessionState.restoring;
    _message = null;
    notifyListeners();
    try {
      final saved = await _tokenStore.readSession();
      if (generation != _generation) return;
      if (saved == null) {
        _setUnauthenticated();
        return;
      }
      if (!saved.accessTokenExpiresAt.isAfter(now)) {
        await _tokenStore.clearSession();
        if (generation != _generation) return;
        _tokens = null;
        _profile = null;
        _state = AuthSessionState.requiresLogin;
        _message = 'Your session has expired. Please log in again.';
        notifyListeners();
        return;
      }
      final profile = await authService.getCurrentUser(saved.accessToken);
      if (generation != _generation) return;
      _tokens = saved;
      _profile = profile;
      _state = AuthSessionState.authenticated;
      _message = null;
      notifyListeners();
    } on ProfileException catch (error) {
      if (generation != _generation) return;
      if (error.type == ProfileFailureType.unauthorized) {
        try {
          await _tokenStore.clearSession();
        } on AuthTokenStoreException catch (storageError) {
          _setVerificationError(storageError.message);
          return;
        }
        _tokens = null;
        _profile = null;
        _state = AuthSessionState.requiresLogin;
        _message = error.message;
        notifyListeners();
      } else {
        _setVerificationError(error.message);
      }
    } on AuthTokenStoreException catch (error) {
      if (generation == _generation) _setVerificationError(error.message);
    } on Object {
      if (generation == _generation) {
        _setVerificationError(
          'Your session could not be verified. Please try again.',
        );
      }
    }
  }

  void _setUnauthenticated() {
    _tokens = null;
    _profile = null;
    _state = AuthSessionState.unauthenticated;
    _message = null;
    notifyListeners();
  }

  void _setVerificationError(String message) {
    _tokens = null;
    _profile = null;
    _state = AuthSessionState.verificationError;
    _message = message;
    notifyListeners();
  }
}
