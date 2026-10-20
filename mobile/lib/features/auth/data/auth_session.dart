import 'package:flutter/foundation.dart';

import 'models/login_response.dart';
import 'models/user_profile.dart';

class AuthSession extends ChangeNotifier {
  LoginResponse? _tokens;
  UserProfile? _profile;

  bool get hasTokens => _tokens != null;
  String? get accessToken => _tokens?.accessToken;
  String? get refreshToken => _tokens?.refreshToken;
  DateTime? get accessTokenExpiresAt => _tokens?.accessTokenExpiresAt;
  DateTime? get refreshTokenExpiresAt => _tokens?.refreshTokenExpiresAt;
  UserProfile? get profile => _profile;
  bool get isVerified => _tokens != null && _profile != null;

  void begin(LoginResponse response) {
    _tokens = response;
    _profile = null;
    notifyListeners();
  }

  void verify(UserProfile profile) {
    if (_tokens == null) return;
    _profile = profile;
    notifyListeners();
  }

  void clear() {
    _tokens = null;
    _profile = null;
    notifyListeners();
  }
}
