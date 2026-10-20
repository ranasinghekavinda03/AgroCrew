import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/data/auth_session.dart';
import 'features/home/data/health_service.dart';
import 'features/home/presentation/home_screen.dart';

class AgroCrewApp extends StatefulWidget {
  const AgroCrewApp({super.key, this.healthService, this.authService});

  final HealthService? healthService;
  final AuthService? authService;

  @override
  State<AgroCrewApp> createState() => _AgroCrewAppState();
}

class _AgroCrewAppState extends State<AgroCrewApp> {
  late final AuthService _authService;
  late final bool _ownsAuthService;
  final AuthSession _session = AuthSession();

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? AuthService(ApiClient());
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
      home: HomeScreen(
        healthService: widget.healthService,
        authService: _authService,
        session: _session,
      ),
    );
  }
}
