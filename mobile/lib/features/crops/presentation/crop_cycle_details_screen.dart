import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../data/crop_cycle_service.dart';
import '../data/models/crop_cycle.dart';
import 'edit_crop_cycle_screen.dart';

enum CropCycleDetailsResult { updated, deleted, unavailable, uncertain }

class CropCycleDetailsScreen extends StatefulWidget {
  const CropCycleDetailsScreen({
    super.key,
    required this.cropCycleService,
    required this.session,
    required this.cropCycleId,
    this.knownFarmId,
    this.knownFarmName,
  });

  final CropCycleService cropCycleService;
  final AuthSession session;
  final int cropCycleId;
  final int? knownFarmId;
  final String? knownFarmName;

  @override
  State<CropCycleDetailsScreen> createState() => _CropCycleDetailsScreenState();
}

class _CropCycleDetailsScreenState extends State<CropCycleDetailsScreen> {
  late final int _sessionGeneration;
  int _requestSerial = 0;
  CropCycle? _crop;
  CropCycleFailureType? _errorType;
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _routeInvalidating = false;
  bool _deleting = false;
  bool _uncertainDeletion = false;
  bool _returningResult = false;
  String? _mutationError;
  CropCycleDetailsResult? _pendingResult;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.session.generation;
    widget.session.addListener(_sessionChanged);
    if (widget.cropCycleId <= 0) {
      _loading = false;
      _errorType = CropCycleFailureType.validation;
      _error = 'The crop cycle ID is invalid.';
    } else if (!_sessionIsCurrent) {
      _invalidateProtectedRoute();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _requestSerial += 1;
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  bool get _sessionIsCurrent =>
      widget.session.isCurrentGeneration(_sessionGeneration);

  void _sessionChanged() {
    if (_sessionIsCurrent || _routeInvalidating) return;
    _invalidateProtectedRoute();
  }

  void _invalidateProtectedRoute() {
    if (_routeInvalidating) return;
    _routeInvalidating = true;
    _requestSerial += 1;
    if (mounted) {
      setState(() {
        _crop = null;
        _error = null;
        _errorType = null;
        _loading = true;
        _refreshing = false;
        _deleting = false;
        _uncertainDeletion = false;
        _mutationError = null;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    });
  }

  bool _acceptResult(int serial) =>
      mounted &&
      serial == _requestSerial &&
      !_routeInvalidating &&
      _sessionIsCurrent;

  Future<void> _load() async {
    if (_routeInvalidating || !_sessionIsCurrent || widget.cropCycleId <= 0) {
      return;
    }
    final serial = ++_requestSerial;
    setState(() {
      _error = null;
      _errorType = null;
      if (_crop == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    try {
      final crop = await widget.cropCycleService.getCropCycle(
        widget.cropCycleId,
      );
      if (!_acceptResult(serial)) return;
      setState(() {
        _crop = crop;
        _loading = false;
        _refreshing = false;
        _uncertainDeletion = false;
        _mutationError = null;
      });
    } on CropCycleException catch (error) {
      if (!_acceptResult(serial)) return;
      if (error.type == CropCycleFailureType.unauthorized ||
          error.type == CropCycleFailureType.staleSession) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        if (error.type == CropCycleFailureType.notFound) {
          _crop = null;
          _pendingResult ??= CropCycleDetailsResult.unavailable;
        }
        _loading = false;
        _refreshing = false;
        _errorType = error.type;
        _error = error.type == CropCycleFailureType.notFound
            ? 'This crop cycle is unavailable.'
            : error.message;
      });
    } on Object {
      if (!_acceptResult(serial)) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorType = CropCycleFailureType.server;
        _error = 'AgroCrew could not load this crop cycle. Please try again.';
      });
    }
  }

  Future<void> _edit() async {
    final crop = _crop;
    if (crop == null ||
        _deleting ||
        _uncertainDeletion ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    final result = await Navigator.of(context).push<EditCropCycleResult>(
      MaterialPageRoute(
        builder: (_) => EditCropCycleScreen(
          cropCycleService: widget.cropCycleService,
          session: widget.session,
          cropCycle: crop,
          farmLabel: _farmLabel(crop),
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    switch (result.outcome) {
      case EditCropCycleOutcome.confirmed:
        setState(() {
          _crop = result.cropCycle!;
          _pendingResult = CropCycleDetailsResult.updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Crop cycle updated successfully.')),
        );
      case EditCropCycleOutcome.uncertain:
        setState(() => _pendingResult = CropCycleDetailsResult.uncertain);
      case EditCropCycleOutcome.unavailable:
        setState(() => _pendingResult = CropCycleDetailsResult.unavailable);
    }
    await _load();
  }

  Future<void> _confirmDelete() async {
    final crop = _crop;
    if (crop == null ||
        _deleting ||
        _uncertainDeletion ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Crop Cycle?'),
        content: Text(
          'Delete the "${crop.cropType}" CropCycle record? This removes this CropCycle record and cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-crop-cycle-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-crop-cycle-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Crop Cycle'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _deleting ||
        !_sessionIsCurrent ||
        _routeInvalidating) {
      return;
    }
    setState(() {
      _deleting = true;
      _mutationError = null;
    });
    try {
      await widget.cropCycleService.deleteCropCycle(widget.cropCycleId);
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      setState(() => _deleting = false);
      _returnWithResult(CropCycleDetailsResult.deleted);
    } on CropCycleException catch (error) {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      if (error.type == CropCycleFailureType.unauthorized ||
          error.type == CropCycleFailureType.staleSession) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _deleting = false;
        if (error.type == CropCycleFailureType.notFound) {
          _crop = null;
          _errorType = CropCycleFailureType.notFound;
          _error = 'This crop cycle is unavailable.';
          _pendingResult = CropCycleDetailsResult.unavailable;
          _mutationError = null;
        } else if (error.type == CropCycleFailureType.ambiguousDeletion) {
          _uncertainDeletion = true;
          _pendingResult = CropCycleDetailsResult.uncertain;
          _mutationError = 'The deletion outcome could not be confirmed. Refresh authoritative details or return to My Crop Cycles for inspection before trying again.';
        } else {
          _mutationError = error.message;
        }
      });
    } on Object {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      setState(() {
        _deleting = false;
        _mutationError = 'AgroCrew could not delete the crop cycle. Try again.';
      });
    }
  }

  void _returnWithResult(CropCycleDetailsResult result) {
    if (_returningResult) return;
    setState(() => _returningResult = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting && (_pendingResult == null || _returningResult),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_deleting && _pendingResult != null) {
        _returnWithResult(_pendingResult!);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Crop Cycle Details'),
        actions: [
          IconButton(
            key: const Key('crop-cycle-details-refresh'),
            tooltip: 'Refresh crop cycle details',
            onPressed:
                _routeInvalidating || widget.cropCycleId <= 0 || _deleting
                ? null
                : _load,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _body(),
          ),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_loading && _crop == null) {
      return const Center(
        child: Column(
          key: Key('crop-cycle-details-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading crop cycle details...'),
          ],
        ),
      );
    }
    if (_crop == null) return _errorBody();
    return _details(_crop!);
  }

  Widget _errorBody() {
    final unavailable = _errorType == CropCycleFailureType.notFound;
    return ListView(
      key: Key(
        unavailable
            ? 'crop-cycle-details-unavailable'
            : 'crop-cycle-details-error',
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  unavailable
                      ? Icons.hide_source_outlined
                      : Icons.cloud_off_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Unable to load this crop cycle.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (unavailable)
                  FilledButton.icon(
                    key: const Key('return-to-crop-cycles-button'),
                    onPressed: () => _returnWithResult(
                      _pendingResult ?? CropCycleDetailsResult.unavailable,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Return to My Crop Cycles'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('crop-cycle-details-retry'),
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _details(CropCycle crop) {
    final status = _statusPresentation(
      crop.status,
      Theme.of(context).colorScheme,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('crop-cycle-details-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.spa_outlined,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    crop.cropType,
                    key: const Key('crop-cycle-details-crop-type'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    key: const Key('crop-cycle-details-status'),
                    avatar: Icon(
                      status.icon,
                      size: 18,
                      color: status.foreground,
                    ),
                    label: Text(status.label),
                    labelStyle: TextStyle(color: status.foreground),
                    backgroundColor: status.background,
                    side: BorderSide.none,
                  ),
                ],
              ),
            ),
          ),
          if (_refreshing) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              key: Key('crop-cycle-details-refreshing'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _InlineError(message: _error!, onRetry: _load),
          ],
          if (_mutationError != null) ...[
            const SizedBox(height: 12),
            Material(
              key: const Key('crop-cycle-mutation-error'),
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_mutationError!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Crop information',
            children: [
              _DetailRow(label: 'Farm', value: _farmLabel(crop)),
              _DetailRow(label: 'Variety', value: _optional(crop.variety)),
              _DetailRow(
                label: 'Plant count',
                value: crop.plantCount?.toString() ?? 'Not provided',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Dates',
            children: [
              _DetailRow(
                label: 'Planting date',
                value: _formatCalendarDate(crop.plantingDate),
              ),
              _DetailRow(
                label: 'Expected harvest date',
                value: crop.expectedHarvestDate == null
                    ? 'Not provided'
                    : _formatCalendarDate(crop.expectedHarvestDate!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Notes',
            children: [
              _DetailRow(label: 'Notes', value: _optional(crop.notes)),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Record information',
            children: [
              _DetailRow(label: 'Crop cycle ID', value: '${crop.id}'),
              _DetailRow(
                label: 'Created (UTC)',
                value: _formatTimestamp(crop.createdAt),
              ),
              _DetailRow(
                label: 'Last updated (UTC)',
                value: _formatTimestamp(crop.updatedAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_uncertainDeletion) ...[
            FilledButton.icon(
              key: const Key('inspect-after-delete-button'),
              onPressed: _refreshing ? null : _load,
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('Refresh Authoritative Details'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('return-after-uncertain-delete-button'),
              onPressed: () =>
                  _returnWithResult(CropCycleDetailsResult.uncertain),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Return to My Crop Cycles'),
            ),
          ] else ...[
            FilledButton.icon(
              key: const Key('edit-crop-cycle-button'),
              onPressed: _deleting || _refreshing ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Crop Cycle'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('delete-crop-cycle-button'),
              onPressed: _deleting || _refreshing ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: _deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_deleting ? 'Deleting...' : 'Delete Crop Cycle'),
            ),
          ],
        ],
      ),
    );
  }

  String _farmLabel(CropCycle crop) {
    final name = widget.knownFarmName?.trim();
    if (widget.knownFarmId == crop.farmId && name != null && name.isNotEmpty) {
      return '$name (Farm #${crop.farmId})';
    }
    return 'Farm #${crop.farmId}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('crop-cycle-details-refresh-error'),
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

String _optional(String? value) =>
    value?.trim().isNotEmpty == true ? value! : 'Not provided';

String _formatCalendarDate(DateTime value) {
  String pad(int number, int width) => number.toString().padLeft(width, '0');
  return '${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)}';
}

String _formatTimestamp(DateTime value) {
  final utc = value.toUtc();
  String pad(int number, int width) => number.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)} '
      '${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)} UTC';
}

_StatusPresentation _statusPresentation(
  CropStatus status,
  ColorScheme colors,
) => switch (status) {
  CropStatus.planned => _StatusPresentation(
    'Planned',
    Icons.schedule_outlined,
    colors.secondaryContainer,
    colors.onSecondaryContainer,
  ),
  CropStatus.active => _StatusPresentation(
    'Active',
    Icons.eco_outlined,
    colors.primaryContainer,
    colors.onPrimaryContainer,
  ),
  CropStatus.harvested => _StatusPresentation(
    'Harvested',
    Icons.task_alt_outlined,
    colors.tertiaryContainer,
    colors.onTertiaryContainer,
  ),
  CropStatus.cancelled => _StatusPresentation(
    'Cancelled',
    Icons.cancel_outlined,
    colors.errorContainer,
    colors.onErrorContainer,
  ),
};

class _StatusPresentation {
  const _StatusPresentation(
    this.label,
    this.icon,
    this.background,
    this.foreground,
  );

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
}
