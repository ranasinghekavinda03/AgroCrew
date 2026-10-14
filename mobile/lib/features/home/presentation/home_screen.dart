import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/health_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.healthService});

  final HealthService? healthService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HealthService _healthService;
  late final bool _ownsHealthService;
  HealthStatus? _healthStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ownsHealthService = widget.healthService == null;
    _healthService = widget.healthService ?? HealthService(ApiClient());
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isLoading = true;
      _healthStatus = null;
    });

    try {
      final healthStatus = await _healthService.checkHealth();
      if (!mounted) return;
      setState(() {
        _healthStatus = healthStatus;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _healthStatus = null;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    if (_ownsHealthService) {
      _healthService.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 48.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BrandMark(colors: colors),
                        const SizedBox(height: 48),
                        _StatusBadge(colors: colors),
                        const SizedBox(height: 24),
                        Text('AgroCrew', style: theme.textTheme.displayLarge),
                        const SizedBox(height: 14),
                        Text(
                          'Multi-Agent Smart Farming Assistant',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'AI-powered crop monitoring, plant disease detection, '
                          'and farming assistance.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          'Backend Connection',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 14),
                        _BackendConnectionCard(
                          isLoading: _isLoading,
                          healthStatus: _healthStatus,
                          onRetry: _checkConnection,
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

class _BackendConnectionCard extends StatelessWidget {
  const _BackendConnectionCard({
    required this.isLoading,
    required this.healthStatus,
    required this.onRetry,
  });

  final bool isLoading;
  final HealthStatus? healthStatus;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isConnected = healthStatus != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isLoading
                    ? colors.surfaceContainerHighest
                    : isConnected
                    ? colors.primaryContainer
                    : colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(
                      isConnected ? Icons.check_rounded : Icons.cloud_off,
                      color: isConnected
                          ? colors.onPrimaryContainer
                          : colors.onErrorContainer,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoading
                        ? 'Checking connection...'
                        : isConnected
                        ? 'Backend Connected'
                        : 'Backend Unavailable',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLoading
                        ? 'Contacting the AgroCrew backend.'
                        : isConnected
                        ? 'Service: ${healthStatus!.service}'
                        : 'Unable to connect to the AgroCrew backend.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (!isLoading) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Connection'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.eco_outlined, color: colors.onPrimary, size: 28),
        ),
        const SizedBox(width: 14),
        Text(
          'AgroCrew',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          'Project Foundation',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}
