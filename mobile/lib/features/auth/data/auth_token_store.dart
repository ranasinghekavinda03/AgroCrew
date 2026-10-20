import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/login_response.dart';

/// Persistent authentication boundary. Implementations must never store a
/// password or log the values passed to them.
abstract interface class AuthTokenStore {
  Future<void> saveSession(LoginResponse session);

  Future<LoginResponse?> readSession();

  Future<void> clearSession();
}

/// Creates secure native storage and deliberately uses process memory on web.
/// Consequently, web sessions never survive a browser reload.
AuthTokenStore createAuthTokenStore() => kIsWeb
    ? MemoryAuthTokenStore()
    : JsonAuthTokenStore(FlutterSecureKeyValueStore());

class MemoryAuthTokenStore implements AuthTokenStore {
  LoginResponse? _session;

  @override
  Future<void> saveSession(LoginResponse session) async => _session = session;

  @override
  Future<LoginResponse?> readSession() async => _session;

  @override
  Future<void> clearSession() async => _session = null;
}

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'agrocrew_auth'),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class JsonAuthTokenStore implements AuthTokenStore {
  JsonAuthTokenStore(this._storage);

  static const sessionKey = 'auth_session_v1';
  static const _version = 1;
  final SecureKeyValueStore _storage;

  @override
  Future<void> saveSession(LoginResponse session) async {
    final record = jsonEncode({
      'version': _version,
      'access_token': session.accessToken,
      'refresh_token': session.refreshToken,
      'issued_at': session.issuedAt.toUtc().toIso8601String(),
      'access_expires_at': session.accessTokenExpiresAt.toIso8601String(),
      'refresh_expires_at': session.refreshTokenExpiresAt.toIso8601String(),
    });
    try {
      await _storage.write(sessionKey, record);
    } on Object {
      throw const AuthTokenStoreException(
        'Your session could not be stored securely. Please try again.',
      );
    }
  }

  @override
  Future<LoginResponse?> readSession() async {
    final String? raw;
    try {
      raw = await _storage.read(sessionKey);
    } on Object {
      throw const AuthTokenStoreException(
        'Your saved session could not be read securely.',
      );
    }
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != _version) {
        throw const FormatException();
      }
      final accessToken = _requiredString(decoded['access_token']);
      final refreshToken = _requiredString(decoded['refresh_token']);
      final issuedAt = _requiredDate(decoded['issued_at']);
      final accessExpiresAt = _requiredDate(decoded['access_expires_at']);
      final refreshExpiresAt = _requiredDate(decoded['refresh_expires_at']);
      if (!accessExpiresAt.isAfter(issuedAt) ||
          !refreshExpiresAt.isAfter(issuedAt)) {
        throw const FormatException();
      }
      return LoginResponse(
        accessToken: accessToken,
        refreshToken: refreshToken,
        issuedAt: issuedAt,
        expiresIn: accessExpiresAt.difference(issuedAt),
        refreshExpiresIn: refreshExpiresAt.difference(issuedAt),
      );
    } on FormatException {
      await _clearCorruptSession();
      return null;
    } on TypeError {
      await _clearCorruptSession();
      return null;
    }
  }

  static String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  static DateTime _requiredDate(Object? value) {
    if (value is! String) throw const FormatException();
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException();
    return parsed.toUtc();
  }

  Future<void> _clearCorruptSession() async {
    try {
      await _storage.delete(sessionKey);
    } on Object {
      throw const AuthTokenStoreException(
        'The unusable saved session could not be removed securely.',
      );
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _storage.delete(sessionKey);
    } on Object {
      throw const AuthTokenStoreException(
        'Your saved session could not be removed securely.',
      );
    }
  }
}

class AuthTokenStoreException implements Exception {
  const AuthTokenStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
