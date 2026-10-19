import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/home/data/health_service.dart';
import 'features/home/presentation/home_screen.dart';

class AgroCrewApp extends StatelessWidget {
  const AgroCrewApp({super.key, this.healthService, this.authService});

  final HealthService? healthService;
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroCrew',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: HomeScreen(healthService: healthService, authService: authService),
    );
  }
}
