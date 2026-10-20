import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('INTEGRATION_TEST_EMAIL');
const _password = 'DisposableStep18Password123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rotates and restores a real backend session', (tester) async {
    expect(_email, isNotEmpty);
    var clock = DateTime.now().toUtc();
    final service = AuthService(ApiClient(), clock: () => clock);
    final store = createAuthTokenStore();
    await store.clearSession();

    try {
      await service.register(
        name: 'Step 18 Refresh Farmer',
        email: _email,
        password: _password,
      );
      final original = await service.login(email: _email, password: _password);
      final profile = await service.getCurrentUser(original.accessToken);
      final session = AuthSession(tokenStore: store, clock: () => clock);
      await session.establishVerified(original, profile);

      clock = clock.add(const Duration(minutes: 31));
      final refreshedProfile = await session.getCurrentUser(service);
      expect(refreshedProfile.email, _email.toLowerCase());
      expect(session.accessToken, isNot(original.accessToken));
      expect(session.refreshToken, isNot(original.refreshToken));

      final persisted = await store.readSession();
      expect(persisted?.accessToken, session.accessToken);
      expect(persisted?.refreshToken, session.refreshToken);

      clock = DateTime.now().toUtc();
      final restoredStore = createAuthTokenStore();
      final restored = AuthSession(
        tokenStore: restoredStore,
        clock: () => clock,
      );
      await restored.restore(service);
      if (kIsWeb) {
        expect(restored.state, AuthSessionState.unauthenticated);
      } else {
        expect(restored.state, AuthSessionState.authenticated);
        expect(restored.profile?.email, _email.toLowerCase());
      }

      await expectLater(
        service.refreshSession(original.refreshToken),
        throwsA(
          isA<RefreshException>().having(
            (error) => error.type,
            'type',
            RefreshFailureType.unauthorized,
          ),
        ),
      );
    } finally {
      service.close();
    }
  });
}
