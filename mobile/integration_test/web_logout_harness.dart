import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:flutter/material.dart';

const _email = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _password = 'DisposableStep19Password123!';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _VerificationApp());
}

class _VerificationApp extends StatefulWidget {
  const _VerificationApp();

  @override
  State<_VerificationApp> createState() => _VerificationAppState();
}

class _VerificationAppState extends State<_VerificationApp> {
  String _result = 'STEP19_WEB_LOGOUT_RUNNING';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    var stage = 'start';
    final service = AuthService(ApiClient());
    try {
      if (_email.isEmpty) throw StateError('Missing integration email.');
      stage = 'register';
      await service.register(
        name: 'Step 19 Web Logout Farmer',
        email: _email,
        password: _password,
      );
      stage = 'login';
      final tokens = await service.login(email: _email, password: _password);
      final independent = await service.login(
        email: _email,
        password: _password,
      );
      stage = 'profile';
      final profile = await service.getCurrentUser(tokens.accessToken);
      final session = AuthSession(tokenStore: createAuthTokenStore());
      await session.establishVerified(tokens, profile);

      stage = 'logout';
      final result = await session.logout(service);
      if (!result.localCleanupSucceeded ||
          !result.remoteLogoutConfirmed ||
          session.state != AuthSessionState.unauthenticated ||
          session.hasTokens ||
          session.profile != null) {
        throw StateError('Logout state verification failed.');
      }

      stage = 'reload';
      final reloaded = AuthSession(tokenStore: createAuthTokenStore());
      await reloaded.restore(service);
      if (reloaded.state != AuthSessionState.unauthenticated) {
        throw StateError('Web session persisted unexpectedly.');
      }

      stage = 'revocation';
      try {
        await service.refreshSession(tokens.refreshToken);
        throw StateError('Logged-out token unexpectedly refreshed.');
      } on RefreshException {
        // Expected: logout revoked this refresh token.
      }
      final surviving = await service.refreshSession(independent.refreshToken);
      await service.logout(surviving.refreshToken);

      if (mounted) setState(() => _result = 'STEP19_WEB_LOGOUT_PASS');
    } on Object catch (error) {
      if (mounted) {
        setState(
          () =>
              _result = 'STEP19_WEB_LOGOUT_FAIL_${stage}_${error.runtimeType}',
        );
      }
    } finally {
      service.close();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: _result,
    home: Scaffold(body: Center(child: Text(_result))),
  );
}
