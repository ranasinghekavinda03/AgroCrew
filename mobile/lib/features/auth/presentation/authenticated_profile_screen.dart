import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/auth_session.dart';
import '../data/auth_token_store.dart';
import '../data/models/login_response.dart';

class AuthenticatedProfileScreen extends StatefulWidget {
  const AuthenticatedProfileScreen({
    super.key,
    required this.authService,
    required this.session,
    this.pendingTokens,
  });

  final AuthService authService;
  final AuthSession session;
  final LoginResponse? pendingTokens;

  @override
  State<AuthenticatedProfileScreen> createState() =>
      _AuthenticatedProfileScreenState();
}

class _AuthenticatedProfileScreenState
    extends State<AuthenticatedProfileScreen> {
  late bool _isLoading;
  bool _requiresLogin = false;
  bool _isLoggingOut = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isLoading = widget.pendingTokens != null;
    if (_isLoading) _verifyPendingLogin();
  }

  Future<void> _verifyPendingLogin() async {
    final tokens = widget.pendingTokens;
    if (tokens == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await widget.authService.getCurrentUser(
        tokens.accessToken,
      );
      await widget.session.establishVerified(tokens, profile);
      if (mounted) setState(() => _isLoading = false);
    } on ProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _requiresLogin = error.type == ProfileFailureType.unauthorized;
        _errorMessage = error.message;
      });
    } on AuthTokenStoreException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Your session could not be verified. Please try again.';
      });
    }
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of AgroCrew?'),
        content: const Text('Your session on this device will end.'),
        actions: [
          TextButton(
            key: const Key('logout-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    final result = await widget.session.logout(widget.authService);
    if (!mounted) return;
    if (result.localCleanupSucceeded) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.session.profile;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your Profile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _isLoading
                  ? const Column(
                      key: Key('profile-loading'),
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Verifying your profile...'),
                      ],
                    )
                  : profile != null
                  ? Card(
                      key: const Key('authenticated-profile'),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 52,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Welcome to AgroCrew!',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 20),
                            Text('Hello, ${profile.name}'),
                            const SizedBox(height: 8),
                            Text('Email: ${profile.email}'),
                            const SizedBox(height: 8),
                            const Text('Status: Authenticated'),
                            const SizedBox(height: 20),
                            Text(
                              'On Android, this verified session can be securely restored and refreshed. Web sessions end on reload.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            OutlinedButton.icon(
                              key: const Key('logout-button'),
                              onPressed: _isLoggingOut ? null : _confirmLogout,
                              icon: _isLoggingOut
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.logout_rounded),
                              label: Text(
                                _isLoggingOut ? 'Logging Out...' : 'Log Out',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      key: const Key('profile-error'),
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(_errorMessage ?? 'Unable to verify your profile.'),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: Key(
                            _requiresLogin
                                ? 'profile-login-again'
                                : 'profile-retry',
                          ),
                          onPressed: _requiresLogin
                              ? () => Navigator.of(context).pop()
                              : _verifyPendingLogin,
                          icon: Icon(
                            _requiresLogin ? Icons.login : Icons.refresh,
                          ),
                          label: Text(
                            _requiresLogin ? 'Return to Log In' : 'Retry',
                          ),
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
