import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/data/auth_session.dart';
import 'features/auth/data/auth_token_store.dart';
import 'features/auth/presentation/authenticated_profile_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/data/health_service.dart';
import 'features/home/presentation/home_screen.dart';

class AgroCrewApp extends StatefulWidget {
  const AgroCrewApp({
    super.key,
    this.healthService,
    this.authService,
    this.tokenStore,
  });

  final HealthService? healthService;
  final AuthService? authService;
  final AuthTokenStore? tokenStore;

  @override
  State<AgroCrewApp> createState() => _AgroCrewAppState();
}

class _AgroCrewAppState extends State<AgroCrewApp> {
  late final AuthService _authService;
  late final bool _ownsAuthService;
  late final AuthSession _session;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? AuthService(ApiClient());
    _session = AuthSession(
      tokenStore: widget.tokenStore ?? createAuthTokenStore(),
    );
    _session.restore(_authService);
  }

  @override
  void dispose() {
    _session.dispose();
    if (_ownsAuthService) _authService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroCrew',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => switch (_session.state) {
          AuthSessionState.restoring => const _SessionLoadingScreen(),
          AuthSessionState.authenticated => AuthenticatedProfileScreen(
            authService: _authService,
            session: _session,
          ),
          AuthSessionState.verificationError ||
          AuthSessionState.requiresLogin => _SessionProblemScreen(
            session: _session,
            authService: _authService,
            healthService: widget.healthService,
          ),
          AuthSessionState.unauthenticated => HomeScreen(
            healthService: widget.healthService,
            authService: _authService,
            session: _session,
          ),
        },
      ),
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Checking your session',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eco_outlined, size: 56),
              SizedBox(height: 20),
              Text('AgroCrew', style: TextStyle(fontSize: 28)),
              SizedBox(height: 18),
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Checking your session...'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SessionProblemScreen extends StatelessWidget {
  const _SessionProblemScreen({
    required this.session,
    required this.authService,
    required this.healthService,
  });

  final AuthSession session;
  final AuthService authService;
  final HealthService? healthService;

  @override
  Widget build(BuildContext context) {
    final canRetry = session.state == AuthSessionState.verificationError;
    return Scaffold(
      appBar: AppBar(title: const Text('AgroCrew')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    canRetry ? Icons.cloud_off_outlined : Icons.lock_clock,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    session.message ?? 'Please log in again.',
                    textAlign: TextAlign.center,
                  ),
                  if (canRetry) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('session-retry-verification'),
                      onPressed: () => session.restore(authService),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Verification'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('session-login'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LoginScreen(
                            authService: authService,
                            session: session,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Log In'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('session-home'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeScreen(
                            healthService: healthService,
                            authService: authService,
                            session: session,
                          ),
                        ),
                      );
                    },
                    child: const Text('Continue to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
