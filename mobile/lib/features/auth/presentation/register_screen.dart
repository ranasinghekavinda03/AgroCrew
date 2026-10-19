import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final AuthService _authService;
  late final bool _ownsAuthService;
  bool _isSubmitting = false;
  bool _isFormValid = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _statusMessage;
  bool _registrationSucceeded = false;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? AuthService(ApiClient());
    for (final controller in [
      _nameController,
      _emailController,
      _passwordController,
      _confirmPasswordController,
    ]) {
      controller.addListener(_updateFormValidity);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    if (_ownsAuthService) {
      _authService.close();
    }
    super.dispose();
  }

  void _updateFormValidity() {
    final isValid =
        _validateName(_nameController.text) == null &&
        _validateEmail(_emailController.text) == null &&
        _validatePassword(_passwordController.text) == null &&
        _validateConfirmation(_confirmPasswordController.text) == null;
    if (mounted && isValid != _isFormValid) {
      setState(() => _isFormValid = isValid);
    }
  }

  String? _validateName(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Enter your full name.';
    if (normalized.length > 255) {
      return 'Full name must be 255 characters or fewer.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Enter your email address.';
    if (normalized.length > 320) {
      return 'Email address must be 320 characters or fewer.';
    }
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < 12) {
      return 'Password must be at least 12 characters.';
    }
    if (password.length > 128) {
      return 'Password must be 128 characters or fewer.';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    final confirmation = value ?? '';
    if (confirmation.isEmpty) return 'Confirm your password.';
    if (confirmation != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _registrationSucceeded = false;
    });

    try {
      await _authService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      _passwordController.clear();
      _confirmPasswordController.clear();
      setState(() {
        _registrationSucceeded = true;
        _statusMessage =
            'Account created successfully. You can log in when the login '
            'feature is available.';
      });
    } on RegistrationException catch (error) {
      if (!mounted) return;
      setState(() {
        _registrationSucceeded = false;
        _statusMessage = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _registrationSucceeded = false;
        _statusMessage = 'AgroCrew could not create your account right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 48.0 : 20.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
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
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_add_alt_1_rounded,
                            color: colors.onPrimaryContainer,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Create Account',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start your smart farming journey with AgroCrew.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          key: const Key('register-name-field'),
                          controller: _nameController,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: _validateName,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('register-email-field'),
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
                          key: const Key('register-password-field'),
                          controller: _passwordController,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              key: const Key('toggle-password-visibility'),
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
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('register-confirm-password-field'),
                          controller: _confirmPasswordController,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          enableSuggestions: false,
                          autocorrect: false,
                          onFieldSubmitted: (_) {
                            if (_isFormValid && !_isSubmitting) _submit();
                          },
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock_reset_rounded),
                            suffixIcon: IconButton(
                              key: const Key(
                                'toggle-confirm-password-visibility',
                              ),
                              tooltip: _obscureConfirmPassword
                                  ? 'Show password confirmation'
                                  : 'Hide password confirmation',
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: _validateConfirmation,
                        ),
                        if (_statusMessage case final message?) ...[
                          const SizedBox(height: 22),
                          _RegistrationMessage(
                            message: message,
                            isSuccess: _registrationSucceeded,
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            key: const Key('create-account-submit'),
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
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              _isSubmitting
                                  ? 'Creating Account...'
                                  : 'Create Account',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RegistrationMessage extends StatelessWidget {
  const _RegistrationMessage({required this.message, required this.isSuccess});

  final String message;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isSuccess
        ? colors.primaryContainer
        : colors.errorContainer;
    final foreground = isSuccess
        ? colors.onPrimaryContainer
        : colors.onErrorContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              color: foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
