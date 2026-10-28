import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:flutter/material.dart';

const _email = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _password = 'DisposableStep18Password123!';

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
  String _result = 'STEP18_WEB_REFRESH_RUNNING';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    var clock = DateTime.now().toUtc();
    var stage = 'start';
    final service = AuthService(ApiClient(), clock: () => clock);
    try {
      if (_email.isEmpty) throw StateError('Missing integration email.');
      stage = 'register';
      try {
        await service.register(
          name: 'Step 18 Web Refresh Farmer',
          email: _email,
          password: _password,
        );
      } on RegistrationException catch (error) {
        if (error.type != RegistrationFailureType.duplicateEmail) rethrow;
      }
      stage = 'login';
      final original = await service.login(email: _email, password: _password);
      stage = 'initial-profile';
      final profile = await service.getCurrentUser(original.accessToken);
      final store = createAuthTokenStore();
      final session = AuthSession(tokenStore: store, clock: () => clock);
      await session.establishVerified(original, profile);

      stage = 'refresh';
      clock = clock.add(const Duration(minutes: 31));
      final refreshedProfile = await session.getCurrentUser(service);
      if (refreshedProfile.email != _email.toLowerCase() ||
          session.accessToken == original.accessToken ||
          session.refreshToken == original.refreshToken) {
        throw StateError('Rotation verification failed.');
      }

      stage = 'reload';
      final reloadSession = AuthSession(
        tokenStore: createAuthTokenStore(),
        clock: () => clock,
      );
      await reloadSession.restore(service);
      if (reloadSession.state != AuthSessionState.unauthenticated) {
        throw StateError('Web session persisted unexpectedly.');
      }

      if (mounted) setState(() => _result = 'STEP18_WEB_REFRESH_PASS');
    } on Object catch (error) {
      if (mounted) {
        setState(
          () =>
              _result = 'STEP18_WEB_REFRESH_FAIL_${stage}_${error.runtimeType}',
        );
      }
    } finally {
      service.close();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: _result,
    home: Title(
      title: _result,
      color: Colors.white,
      child: Scaffold(body: Center(child: Text(_result))),
    ),
  );
}
