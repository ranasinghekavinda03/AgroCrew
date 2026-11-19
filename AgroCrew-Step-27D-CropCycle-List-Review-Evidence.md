# AgroCrew Step 27D — CropCycle List Review Evidence

## Scope and repository state

Initial verified state on 2026-11-19:

- Branch: `main`
- HEAD: `f95a3a3ae4a093fedd38e4e4d3c0baf572bd82c1`
- Subject: `fix(auth): serialize session persistence`
- Existing untracked evidence files: Step 27C, Step 27C.1, and Step 27C.2 documents.
- No Step 27C.2 source modifications remained uncommitted.
- Native Flutter baseline: 343 passing tests.

Final source state:

- Modified: `mobile/lib/features/auth/presentation/authenticated_profile_screen.dart`
- Created: `mobile/lib/features/crops/presentation/my_crop_cycles_screen.dart`
- Created: `mobile/test/crop_cycle_screens_test.dart`
- Created: `AgroCrew-Step-27D-CropCycle-List-Review-Evidence.md`
- Earlier evidence documents remain preserved and unmodified.
- No backend, model, service, session, dependency, lockfile, schema, or migration file was changed.

## Architecture and navigation decisions

The implementation follows the existing constructor-injection and `MaterialPageRoute` conventions. The authenticated profile owns one feature `ApiClient` and shares it between `FarmService` and `CropCycleService`; an optional injected client supports deterministic widget tests, and only an internally-created client is disposed by the profile.

`MyCropCyclesScreen` accepts existing `CropCycleService`, `FarmService`, and `AuthSession` instances. It performs no HTTP or credential-storage access directly. Crop records and paginated farm metadata load independently.

Screen request serials, the route's captured session generation, filter identity checks, mounted checks, and a removable session listener reject delayed responses after refresh, filter changes, disposal, logout, or account replacement. Protected state is cleared before the route is popped to the root.

Pagination advances with the server page's `nextOffset`. Duplicate IDs are omitted in first-appearance order without changing the server-derived offset. Offset pagination remains inherently unable to provide a stable snapshot when records change concurrently.

## User interface behavior

The read-only list includes crop type, explicit status text plus icon, farm name or `Farm #id` fallback, planting date, and optional variety, expected harvest date, and plant count. Notes are intentionally excluded. Date-only values are formatted from their year/month/day components without local-time conversion.

The screen provides initial loading, empty all-farm and filtered states, sanitized initial errors, retry, manual and pull refresh, append failure recovery, farm metadata loading/error/retry, paginated farm choices, safe unavailable-farm recovery, and responsive constrained content. No Add, Details, Edit, or Delete affordances were introduced.

## Test inventory

The new widget file contains 17 deterministic tests covering:

- concurrent initial crop/farm loading and exact default query;
- all status labels, optional values, calendar dates, Unicode, and fallback farm identity;
- empty, initial failure, retry, farm metadata failure, and selected-farm 404;
- farm filtering, filter race rejection, crop and farm pagination, append failure, retry, and deduplication;
- manual and pull refresh, retained data after refresh failure, and stale pagination rejection;
- pending-response disposal and session replacement route clearing;
- authenticated navigation, back navigation, retained My Farms navigation, and unauthenticated hiding;
- narrow responsive layout and long multilingual values.

All fixtures use local `MockClient` responses; no external network or database was used.

## Verification results

Commands were executed from `mobile/` unless noted. Every listed command exited 0.

| Command | Result |
|---|---|
| `flutter test test/crop_cycle_screens_test.dart` | 17 passed |
| `flutter test test/crop_cycle_service_test.dart` | 70 passed |
| `flutter test test/crop_cycle_model_test.dart` | 95 passed |
| `flutter test test/farm_screens_test.dart` | 20 passed |
| `flutter test test/farm_service_test.dart` | 27 passed |
| `flutter test test/automatic_token_refresh_test.dart` | 17 passed |
| `flutter test test/logout_session_test.dart` | 11 passed |
| `flutter analyze` | No issues found |
| `flutter test --reporter compact` | 360 passed, 0 failed, 0 skipped |
| `git diff --check` (repository root) | Passed; only Git's existing LF/CRLF advisory was printed |
| `git diff --stat` (repository root) | Tracked profile change reported; untracked source inspected separately |

The complete native suite increased from 343 to 360 tests, exactly matching the 17 new widget tests.

## Runtime verification and limitations

No Android emulator or Chrome runtime session was executed, and no screenshots were captured. Responsive behavior was verified with mocked Flutter widget tests, including a narrow viewport and multilingual long text. Real-backend integration was not required for this isolated UI step.

The farm selector exposes additional pages through an explicit “Load more farms” action rather than prefetching an unbounded farm list. Offset pagination cannot guarantee snapshot consistency under concurrent server changes; UI deduplication mitigates repeated IDs while preserving server offsets.

## Complete source — mobile/lib/features/crops/presentation/my_crop_cycles_screen.dart

```dart
import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../../farms/data/farm_service.dart';
import '../data/crop_cycle_service.dart';
import '../data/models/crop_cycle.dart';

class MyCropCyclesScreen extends StatefulWidget {
  const MyCropCyclesScreen({
    super.key,
    required this.cropCycleService,
    required this.farmService,
    required this.session,
  });

  final CropCycleService cropCycleService;
  final FarmService farmService;
  final AuthSession session;

  @override
  State<MyCropCyclesScreen> createState() => _MyCropCyclesScreenState();
}

class _MyCropCyclesScreenState extends State<MyCropCyclesScreen> {
  static const _pageSize = 20;
  final List<CropCycle> _crops = [];
  final Map<int, String> _farmNames = {};

  late final int _sessionGeneration;
  int _cropRequestSerial = 0;
  int _farmRequestSerial = 0;
  int? _selectedFarmId;
  int _nextOffset = 0;
  int _farmNextOffset = 0;
  bool _initialLoading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _farmLoading = true;
  bool _farmLoadingMore = false;
  bool _farmHasMore = false;
  String? _initialError;
  String? _listMessage;
  String? _loadMoreError;
  String? _farmError;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.session.generation;
    widget.session.addListener(_sessionChanged);
    _loadFirstPage();
    _loadFarmPage(reset: true);
  }

  @override
  void dispose() {
    _cropRequestSerial += 1;
    _farmRequestSerial += 1;
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  bool get _sessionIsCurrent =>
      widget.session.isCurrentGeneration(_sessionGeneration);

  void _sessionChanged() {
    if (_sessionIsCurrent) return;
    _invalidateProtectedRoute();
  }

  void _invalidateProtectedRoute() {
    _cropRequestSerial += 1;
    _farmRequestSerial += 1;
    if (mounted) {
      setState(() {
        _crops.clear();
        _farmNames.clear();
        _selectedFarmId = null;
        _initialError = null;
        _listMessage = null;
        _loadMoreError = null;
        _farmError = null;
        _initialLoading = true;
        _loadingMore = false;
        _farmLoading = false;
        _farmLoadingMore = false;
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

  bool _acceptCropResult(int serial, int? farmId) =>
      mounted &&
      serial == _cropRequestSerial &&
      farmId == _selectedFarmId &&
      _sessionIsCurrent;

  bool _acceptFarmResult(int serial) =>
      mounted && serial == _farmRequestSerial && _sessionIsCurrent;

  Future<void> _loadFirstPage({bool refresh = false}) async {
    if (!_sessionIsCurrent) return;
    final serial = ++_cropRequestSerial;
    final farmId = _selectedFarmId;
    setState(() {
      _initialError = null;
      _listMessage = null;
      _loadMoreError = null;
      _loadingMore = false;
      if (refresh && _crops.isNotEmpty) {
        _refreshing = true;
      } else {
        _initialLoading = true;
      }
    });
    try {
      final page = await widget.cropCycleService.listCropCycles(
        limit: _pageSize,
        farmId: farmId,
      );
      if (!_acceptCropResult(serial, farmId)) return;
      setState(() {
        _crops
          ..clear()
          ..addAll(page.crops);
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _initialLoading = false;
        _refreshing = false;
      });
    } on CropCycleException catch (error) {
      if (!_acceptCropResult(serial, farmId)) return;
      if (error.type == CropCycleFailureType.staleSession ||
          error.type == CropCycleFailureType.unauthorized) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _initialLoading = false;
        _refreshing = false;
        if (_crops.isEmpty) {
          _initialError = error.message;
        } else {
          _listMessage = error.message;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !_sessionIsCurrent) return;
    final serial = _cropRequestSerial;
    final farmId = _selectedFarmId;
    final offset = _nextOffset;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.cropCycleService.listCropCycles(
        limit: _pageSize,
        offset: offset,
        farmId: farmId,
      );
      if (!_acceptCropResult(serial, farmId)) return;
      final existingIds = _crops.map((crop) => crop.id).toSet();
      setState(() {
        for (final crop in page.crops) {
          if (existingIds.add(crop.id)) _crops.add(crop);
        }
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on CropCycleException catch (error) {
      if (!_acceptCropResult(serial, farmId)) return;
      if (error.type == CropCycleFailureType.staleSession ||
          error.type == CropCycleFailureType.unauthorized) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _loadingMore = false;
        _loadMoreError = error.message;
      });
    }
  }

  Future<void> _changeFarm(int? farmId) async {
    if (farmId == _selectedFarmId || !_sessionIsCurrent) return;
    _cropRequestSerial += 1;
    setState(() {
      _selectedFarmId = farmId;
      _crops.clear();
      _initialError = null;
      _listMessage = null;
      _loadMoreError = null;
      _nextOffset = 0;
      _hasMore = false;
      _initialLoading = true;
      _refreshing = false;
      _loadingMore = false;
    });
    await _loadFirstPage();
  }

  Future<void> _loadFarmPage({bool reset = false}) async {
    if (!_sessionIsCurrent || _farmLoadingMore) return;
    final serial = reset ? ++_farmRequestSerial : _farmRequestSerial;
    final offset = reset ? 0 : _farmNextOffset;
    setState(() {
      _farmError = null;
      if (reset) {
        _farmLoading = true;
      } else {
        _farmLoadingMore = true;
      }
    });
    try {
      final page = await widget.farmService.listFarms(
        limit: _pageSize,
        offset: offset,
      );
      if (!_acceptFarmResult(serial)) return;
      setState(() {
        if (reset) _farmNames.clear();
        for (final farm in page.farms) {
          _farmNames[farm.id] = farm.name;
        }
        _farmNextOffset = offset + page.farms.length;
        _farmHasMore = page.hasMore;
        _farmLoading = false;
        _farmLoadingMore = false;
      });
    } on FarmException catch (error) {
      if (!_acceptFarmResult(serial)) return;
      if (error.type == FarmFailureType.staleSession ||
          error.type == FarmFailureType.unauthorized) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _farmLoading = false;
        _farmLoadingMore = false;
        _farmError = error.message;
      });
    }
  }

  String _farmLabel(int farmId) => _farmNames[farmId] ?? 'Farm #$farmId';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Crop Cycles'),
      actions: [
        IconButton(
          key: const Key('crop-cycles-refresh'),
          tooltip: 'Refresh crop cycles',
          onPressed: _initialLoading || _refreshing
              ? null
              : () => _loadFirstPage(refresh: true),
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
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _FarmFilterPanel(
                selectedFarmId: _selectedFarmId,
                farmNames: _farmNames,
                loading: _farmLoading,
                loadingMore: _farmLoadingMore,
                hasMore: _farmHasMore,
                error: _farmError,
                onChanged: _changeFarm,
                onLoadMore: () => _loadFarmPage(),
                onRetry: () => _loadFarmPage(reset: _farmNames.isEmpty),
                onRefresh: () => _loadFarmPage(reset: true),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_initialLoading) {
      return const Center(
        child: Column(
          key: Key('crop-cycles-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your crop cycles...'),
          ],
        ),
      );
    }
    if (_initialError != null) {
      final unavailableFarm =
          _selectedFarmId != null &&
          _initialError == 'Crop cycle or farm not found.';
      return _RefreshableMessage(
        key: const Key('crop-cycles-error'),
        icon: unavailableFarm
            ? Icons.location_off_outlined
            : Icons.cloud_off_outlined,
        title: unavailableFarm ? 'This farm is unavailable.' : _initialError!,
        subtitle: unavailableFarm
            ? 'Refresh farms or return to All Farms.'
            : null,
        primaryLabel: unavailableFarm ? 'All Farms' : 'Retry',
        onPrimary: unavailableFarm
            ? () => _changeFarm(null)
            : () => _loadFirstPage(),
        onRefresh: () => _loadFirstPage(refresh: true),
      );
    }
    if (_crops.isEmpty) {
      return _RefreshableMessage(
        key: const Key('crop-cycles-empty'),
        icon: Icons.spa_outlined,
        title: _selectedFarmId == null
            ? 'No crop cycles yet.'
            : 'No crop cycles found for this farm.',
        subtitle: _selectedFarmId == null
            ? 'Crop cycles will appear here when they are available.'
            : 'Choose another farm or refresh this list.',
        primaryLabel: _selectedFarmId == null ? 'Refresh' : 'All Farms',
        onPrimary: _selectedFarmId == null
            ? () => _loadFirstPage(refresh: true)
            : () => _changeFarm(null),
        onRefresh: () => _loadFirstPage(refresh: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(refresh: true),
      child: ListView.builder(
        key: const Key('crop-cycles-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount:
            _crops.length +
            (_listMessage == null ? 0 : 1) +
            (_hasMore || _loadMoreError != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < _crops.length) {
            final crop = _crops[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CropCycleCard(
                crop: crop,
                farmLabel: _farmLabel(crop.farmId),
              ),
            );
          }
          var extraIndex = index - _crops.length;
          if (_listMessage != null) {
            if (extraIndex == 0) {
              return _InlineNotice(
                key: const Key('crop-cycles-refresh-error'),
                message: _listMessage!,
                actionLabel: 'Retry',
                onAction: () => _loadFirstPage(refresh: true),
              );
            }
            extraIndex -= 1;
          }
          if (_loadMoreError != null) {
            return _InlineNotice(
              key: const Key('crop-cycles-load-more-error'),
              message: _loadMoreError!,
              actionLabel: 'Retry',
              onAction: _loadMore,
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                key: const Key('crop-cycles-load-more'),
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? 'Loading...' : 'Load More'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FarmFilterPanel extends StatelessWidget {
  const _FarmFilterPanel({
    required this.selectedFarmId,
    required this.farmNames,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onChanged,
    required this.onLoadMore,
    required this.onRetry,
    required this.onRefresh,
  });

  final int? selectedFarmId;
  final Map<int, String> farmNames;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final ValueChanged<int?> onChanged;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final selectedValue = selectedFarmId ?? -1;
    final entries = farmNames.entries.toList(growable: false);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('crop-cycles-farm-filter'),
                    initialValue: selectedValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Farm filter',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('All Farms'),
                      ),
                      if (selectedFarmId != null &&
                          !farmNames.containsKey(selectedFarmId))
                        DropdownMenuItem(
                          value: selectedFarmId,
                          child: Text('Farm #$selectedFarmId'),
                        ),
                      for (final entry in entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            '${entry.value} (Farm #${entry.key})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => onChanged(value == -1 ? null : value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('farm-metadata-refresh'),
                  tooltip: 'Refresh farms',
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  key: Key('farm-metadata-loading'),
                ),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error!,
                        key: const Key('farm-metadata-error'),
                      ),
                    ),
                    TextButton(
                      key: const Key('farm-metadata-retry'),
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('farm-metadata-load-more'),
                  onPressed: loadingMore ? null : onLoadMore,
                  icon: loadingMore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_location_alt_outlined),
                  label: Text(
                    loadingMore ? 'Loading farms...' : 'Load more farms',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CropCycleCard extends StatelessWidget {
  const _CropCycleCard({required this.crop, required this.farmLabel});

  final CropCycle crop;
  final String farmLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusPresentation(crop.status, theme.colorScheme);
    return Card(
      key: Key('crop-cycle-card-${crop.id}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    crop.cropType,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  avatar: Icon(status.icon, size: 18, color: status.foreground),
                  label: Text(status.label),
                  labelStyle: TextStyle(color: status.foreground),
                  backgroundColor: status.background,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (crop.variety != null) ...[
              const SizedBox(height: 6),
              Text(
                crop.variety!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 10),
            _InfoLine(icon: Icons.agriculture_outlined, text: farmLabel),
            _InfoLine(
              icon: Icons.event_available_outlined,
              text: 'Planting: ${_formatDate(crop.plantingDate)}',
            ),
            if (crop.expectedHarvestDate != null)
              _InfoLine(
                icon: Icons.event_note_outlined,
                text:
                    'Expected harvest: ${_formatDate(crop.expectedHarvestDate!)}',
              ),
            if (crop.plantCount != null)
              _InfoLine(
                icon: Icons.numbers_outlined,
                text: 'Plant count: ${crop.plantCount}',
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _RefreshableMessage extends StatelessWidget {
  const _RefreshableMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onRefresh,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

String _formatDate(DateTime value) {
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${pad(value.month)}-${pad(value.day)}';
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
```

## Complete source — mobile/test/crop_cycle_screens_test.dart

```dart
import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/auth/presentation/authenticated_profile_screen.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/presentation/my_crop_cycles_screen.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'loads crops and farm metadata concurrently with exact defaults',
    (tester) async {
      final crops = Completer<http.Response>();
      var cropCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms') {
          return http.Response(jsonEncode([_farm(1, 'North Farm')]), 200);
        }
        cropCalls++;
        expect(request.url.queryParameters, {'limit': '20', 'offset': '0'});
        return crops.future;
      });
      await _pumpCrops(tester, fixture);
      expect(find.byKey(const Key('crop-cycles-loading')), findsOneWidget);
      expect(find.byKey(const Key('farm-metadata-loading')), findsOneWidget);
      crops.complete(http.Response(jsonEncode([_crop(1)]), 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
      expect(find.text('North Farm'), findsOneWidget);
      expect(cropCalls, 1);
    },
  );

  testWidgets('renders statuses and only present optional crop fields', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return _jsonResponse([_farm(1, 'மலை பண்ணை')]);
      }
      return _jsonResponse([
        _crop(1, status: 'planned', cropType: 'Tomato', variety: 'Roma'),
        _crop(2, status: 'active', cropType: 'கத்தரிக்காய்'),
        _crop(3, status: 'harvested', cropType: 'Rice', plantCount: 250),
        _crop(4, status: 'cancelled', cropType: 'Beans'),
      ]);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    for (final entry in {
      1: 'Planned',
      2: 'Active',
      3: 'Harvested',
      4: 'Cancelled',
    }.entries) {
      await tester.scrollUntilVisible(
        find.byKey(Key('crop-cycle-card-${entry.key}')),
        350,
        scrollable: _cropScrollable(),
      );
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 1) expect(find.text('Roma'), findsOneWidget);
      if (entry.key == 3) expect(find.text('Plant count: 250'), findsOneWidget);
    }
    expect(find.text('Planting: 2026-11-03'), findsWidgets);
    expect(find.text('Expected harvest: 2027-01-10'), findsWidgets);
    expect(find.textContaining('notes'), findsNothing);
  });

  testWidgets('shows empty, initial error, and successful retry states', (
    tester,
  ) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropCalls++;
      return cropCalls == 1
          ? http.Response('{"detail":"private"}', 500)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-error')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-empty')), findsOneWidget);
    expect(find.text('No crop cycles yet.'), findsOneWidget);
  });

  testWidgets('farm metadata failure does not hide crop cycles', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.url.path == '/api/v1/farms'
          ? http.Response('{}', 500)
          : http.Response(jsonEncode([_crop(7, farmId: 77)]), 200),
    );
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-metadata-error')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-7')), findsOneWidget);
    expect(find.text('Farm #77'), findsOneWidget);
  });

  testWidgets('farm selection sends farm_id and replaces the list', (
    tester,
  ) async {
    final seen = <Map<String, String>>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(2, 'South Farm')]), 200);
      }
      seen.add(request.url.queryParameters);
      return http.Response(
        jsonEncode([
          _crop(
            request.url.queryParameters['farm_id'] == '2' ? 2 : 1,
            farmId: 2,
          ),
        ]),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'South Farm (Farm #2)');
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    expect(seen.last, {'limit': '20', 'offset': '0', 'farm_id': '2'});
  });

  testWidgets('late result from an older farm filter is ignored', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode([_farm(1, 'One'), _farm(2, 'Two')]),
          200,
        );
      }
      final farmId = request.url.queryParameters['farm_id'];
      if (farmId == '1') return first.future;
      if (farmId == '2') return second.future;
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)', settle: false);
    await _selectFarm(tester, 'Two (Farm #2)', settle: false);
    second.complete(http.Response(jsonEncode([_crop(22, farmId: 2)]), 200));
    await tester.pump();
    first.complete(http.Response(jsonEncode([_crop(11, farmId: 1)]), 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-22')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-11')), findsNothing);
  });

  testWidgets('farm and crop pagination use independent offsets', (
    tester,
  ) async {
    final queries = <String>[];
    final fixture = await _fixture((request) async {
      queries.add('${request.url.path}?${request.url.query}');
      final offset = request.url.queryParameters['offset'];
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode(
            offset == '0'
                ? List.generate(20, (i) => _farm(i + 1, 'Farm ${i + 1}'))
                : [_farm(21, 'Farm 21')],
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode(
          offset == '0' ? List.generate(20, (i) => _crop(i + 1)) : [_crop(21)],
        ),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-load-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(queries, contains('/api/v1/farms?limit=20&offset=20'));
    expect(queries, contains('/api/v1/crops?limit=20&offset=20'));
  });

  testWidgets('load-more failure retains records and retry appends once', (
    tester,
  ) async {
    var laterCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      laterCalls++;
      return laterCalls == 1
          ? http.Response('{}', 500)
          : http.Response(jsonEncode([_crop(21), _crop(20)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(
      find.byKey(const Key('crop-cycles-load-more-error')),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
  });

  testWidgets('refresh replaces records and refresh failure retains old data', (
    tester,
  ) async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      calls++;
      if (calls == 1) return http.Response(jsonEncode([_crop(1)]), 200);
      if (calls == 2) return http.Response(jsonEncode([_crop(2)]), 200);
      return http.Response('{}', 500);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-refresh-error')), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads offset zero', (tester) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropCalls++;
      expect(request.url.queryParameters['offset'], '0');
      return http.Response(jsonEncode([_crop(cropCalls)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('crop-cycles-list')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(cropCalls, 2);
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
  });

  testWidgets('stale load-more result cannot overwrite a refresh', (
    tester,
  ) async {
    final oldPage = Completer<http.Response>();
    var firstPages = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '20') return oldPage.future;
      firstPages++;
      return http.Response(
        jsonEncode(
          firstPages == 1
              ? List.generate(20, (i) => _crop(i + 1))
              : [_crop(50)],
        ),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    oldPage.complete(http.Response(jsonEncode([_crop(21)]), 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-50')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsNothing);
  });

  testWidgets('selected farm 404 offers a safe return to All Farms', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(4, 'Removed Farm')]), 200);
      }
      return request.url.queryParameters['farm_id'] == '4'
          ? http.Response('{}', 404)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Removed Farm (Farm #4)');
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    await tester.tap(find.text('All Farms').last);
    await tester.pumpAndSettle();
    expect(find.text('No crop cycles yet.'), findsOneWidget);
  });

  testWidgets('disposing with pending responses does not update state', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((_) => pending.future);
    await _pumpCrops(tester, fixture);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session replacement clears protected data and closes the route',
    (tester) async {
      final fixture = await _fixture(
        (request) async => request.url.path == '/api/v1/farms'
            ? http.Response('[]', 200)
            : http.Response(jsonEncode([_crop(1)]), 200),
      );
      await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
      await fixture.session.establishVerified(
        _tokens('replacement'),
        _profile(8),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    },
  );

  testWidgets('profile provides crop navigation and keeps My Farms entry', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      return http.Response('[]', 200);
    });
    await _pump(
      tester,
      AuthenticatedProfileScreen(
        authService: fixture.auth,
        session: fixture.session,
        featureApiClient: fixture.client,
      ),
    );
    expect(find.byKey(const Key('my-farms-button')), findsOneWidget);
    expect(find.byKey(const Key('my-crop-cycles-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-crop-cycles-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-empty')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-farms-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Farms'), findsOneWidget);
  });

  testWidgets('unauthenticated profile does not expose protected entries', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 19, 12);
    final client = ApiClient(
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    final session = AuthSession(
      tokenStore: MemoryAuthTokenStore(),
      clock: () => now,
    );
    await _pump(
      tester,
      AuthenticatedProfileScreen(
        authService: AuthService(client, clock: () => now),
        session: session,
        featureApiClient: client,
      ),
    );
    expect(find.byKey(const Key('my-crop-cycles-button')), findsNothing);
    expect(find.byKey(const Key('my-farms-button')), findsNothing);
  });

  testWidgets('narrow layout and long multilingual values do not overflow', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.url.path == '/api/v1/farms'
          ? _jsonResponse([_farm(1, 'மிக நீளமான பண்ணை பெயர்')])
          : _jsonResponse([
              _crop(
                1,
                cropType: 'மிக நீளமான காய்கறி பயிர் பெயர்',
                variety: 'විශේෂ දිගු ප්‍රභේදය',
              ),
            ]),
    );
    await _pumpCrops(tester, fixture, size: const Size(320, 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
  });
}

Finder _cropScrollable() => find.descendant(
  of: find.byKey(const Key('crop-cycles-list')),
  matching: find.byType(Scrollable),
);

Future<void> _selectFarm(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(const Key('crop-cycles-farm-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpCrops(
  WidgetTester tester,
  _Fixture fixture, {
  Size size = const Size(900, 1400),
}) => _pump(
  tester,
  MyCropCyclesScreen(
    cropCycleService: fixture.crops,
    farmService: fixture.farms,
    session: fixture.session,
  ),
  size: size,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
}

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 19, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(seconds: 1),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(_tokens('access'), _profile(7));
  return _Fixture(
    client: client,
    auth: auth,
    session: session,
    crops: CropCycleService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
    farms: FarmService(apiClient: client, session: session, authService: auth),
  );
}

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'refresh-$access',
  issuedAt: DateTime.utc(2026, 11, 19, 12),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

UserProfile _profile(int id) => UserProfile(
  id: id,
  name: 'Farmer $id',
  email: 'farmer$id@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

Map<String, Object?> _farm(int id, String name) => {
  'id': id,
  'user_id': 7,
  'name': name,
  'latitude': null,
  'longitude': null,
  'area_value': null,
  'area_unit': null,
  'notes': null,
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T11:00:00Z',
};

Map<String, Object?> _crop(
  int id, {
  int farmId = 1,
  String status = 'active',
  String cropType = 'Tomato',
  String? variety,
  int? plantCount,
}) => {
  'id': id,
  'farm_id': farmId,
  'crop_type': cropType,
  'variety': variety,
  'planting_date': '2026-11-03',
  'expected_harvest_date': '2027-01-10',
  'status': status,
  'plant_count': plantCount,
  'notes': 'must not render',
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:00:00Z',
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _Fixture {
  const _Fixture({
    required this.client,
    required this.auth,
    required this.session,
    required this.crops,
    required this.farms,
  });
  final ApiClient client;
  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
  final FarmService farms;
}

class _RouteHost extends StatelessWidget {
  const _RouteHost({required this.fixture});
  final _Fixture fixture;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MyCropCyclesScreen(
              cropCycleService: fixture.crops,
              farmService: fixture.farms,
              session: fixture.session,
            ),
          ),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}
```

## Complete source — mobile/lib/features/auth/presentation/authenticated_profile_screen.dart

```dart
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../crops/data/crop_cycle_service.dart';
import '../../crops/presentation/my_crop_cycles_screen.dart';
import '../../farms/data/farm_service.dart';
import '../../farms/presentation/my_farms_screen.dart';
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
    this.featureApiClient,
  });

  final AuthService authService;
  final AuthSession session;
  final LoginResponse? pendingTokens;
  final ApiClient? featureApiClient;

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
  late final ApiClient _featureApiClient;
  late final bool _ownsFeatureApiClient;
  late final FarmService _farmService;
  late final CropCycleService _cropCycleService;

  @override
  void initState() {
    super.initState();
    _ownsFeatureApiClient = widget.featureApiClient == null;
    _featureApiClient = widget.featureApiClient ?? ApiClient();
    _farmService = FarmService(
      apiClient: _featureApiClient,
      session: widget.session,
      authService: widget.authService,
    );
    _cropCycleService = CropCycleService(
      apiClient: _featureApiClient,
      session: widget.session,
      authService: widget.authService,
    );
    _isLoading = widget.pendingTokens != null;
    if (_isLoading) _verifyPendingLogin();
  }

  @override
  void dispose() {
    if (_ownsFeatureApiClient) _featureApiClient.close();
    super.dispose();
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
                            FilledButton.icon(
                              key: const Key('my-farms-button'),
                              onPressed: _isLoggingOut
                                  ? null
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => MyFarmsScreen(
                                          farmService: _farmService,
                                          session: widget.session,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.agriculture_outlined),
                              label: const Text('My Farms'),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              key: const Key('my-crop-cycles-button'),
                              onPressed: _isLoggingOut
                                  ? null
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => MyCropCyclesScreen(
                                          cropCycleService: _cropCycleService,
                                          farmService: _farmService,
                                          session: widget.session,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.spa_outlined),
                              label: const Text('My Crop Cycles'),
                            ),
                            const SizedBox(height: 12),
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
```

## Evidence integrity

After creation, an automated verifier extracted each fenced source block, normalized CRLF/CR line endings to LF, normalized one trailing newline, and compared it with its corresponding working-tree file. All three comparisons passed.

