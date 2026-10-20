import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_service.dart';
import '../data/auth_session.dart';
import 'authenticated_profile_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService, this.session});

  final AuthService? authService;
  final AuthSession? session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService;
  late final AuthSession _session;
  late final bool _ownsAuthService;
  late final bool _ownsSession;
  bool _isSubmitting = false;
  bool _isFormValid = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? AuthService(ApiClient());
    _ownsSession = widget.session == null;
    _session = widget.session ?? AuthSession();
    _emailController.addListener(_updateFormValidity);
    _passwordController.addListener(_updateFormValidity);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    if (_ownsAuthService) _authService.close();
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (email.length > 320) {
      return 'Email address must be 320 characters or fewer.';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  void _updateFormValidity() {
    final valid =
        _validateEmail(_emailController.text) == null &&
        _validatePassword(_passwordController.text) == null;
    if (mounted && valid != _isFormValid) setState(() => _isFormValid = valid);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final response = await _authService.login(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      _session.begin(response);
      _passwordController.clear();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AuthenticatedProfileScreen(
            authService: _authService,
            session: _session,
          ),
        ),
      );
    } on LoginException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on Object {
      if (mounted) {
        setState(() {
          _errorMessage =
              'AgroCrew could not log you in right now. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RegisterScreen(authService: _authService, session: _session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Log In')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 600 ? 48 : 20,
              20,
              constraints.maxWidth >= 600 ? 48 : 20,
              32 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.eco_outlined,
                            color: colors.onPrimaryContainer,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome Back',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Log in to continue your smart farming journey.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        key: const Key('login-email-field'),
                        controller: _emailController,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const Key('login-password-field'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        onFieldSubmitted: (_) {
                          if (_isFormValid && !_isSubmitting) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            key: const Key('login-toggle-password-visibility'),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      if (_errorMessage case final message?) ...[
                        const SizedBox(height: 22),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              message,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          key: const Key('login-submit'),
                          onPressed: _isSubmitting || !_isFormValid
                              ? null
                              : _submit,
                          icon: _isSubmitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            _isSubmitting ? 'Logging In...' : 'Log In',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        key: const Key('login-create-account'),
                        onPressed: _isSubmitting ? null : _openRegistration,
                        child: const Text('Create Account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
