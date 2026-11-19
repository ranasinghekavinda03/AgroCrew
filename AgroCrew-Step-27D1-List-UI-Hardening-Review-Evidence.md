# AgroCrew Step 27D.1 — CropCycle List UI Hardening Review Evidence

## Initial repository state

- Date: 2026-11-19
- Branch: `main`
- HEAD: `c82ef32aab0175af131d826484f759f112073067`
- Subject: `docs(crops): add Step 27D review evidence`
- Native Flutter baseline: 360 passing tests.
- CropCycle widget baseline: 17 passing tests.
- Three earlier Step 27C evidence documents were untracked and preserved.
- Step 27D source and evidence were already committed and pushed.

## Confirmed defects and reproduction evidence

Source inspection confirmed four state-safety defects:

1. `_loadMore()` did not reject pagination during first-page loading or refresh. A deterministic pending-refresh test now attempts Load More, verifies that no request is dispatched, completes the refresh, and verifies that later pagination uses the refreshed page offset.
2. Farm metadata retry inferred reset behavior from whether cached names were empty. Deterministic tests now distinguish failed initial loading, offset-zero refresh, and same-offset additional-page retry.
3. Selected-farm unavailability depended on exact message text and only affected initial errors. Typed `CropCycleFailureType.notFound` handling is now tested during initial filtered loading, refresh, and additional-page loading.
4. Protected-route invalidation had no terminal screen-local flag. Logout, account replacement, delayed failure, pending pagination, pending crop/farm metadata, replacement credentials, and terminal unauthorized cases now have deterministic coverage.

The existing 17-test suite passed before correction, showing these were uncovered concurrency/state gaps rather than existing regression failures. During development, one expanded-suite run reported 31 passes and one failure because a test attempted to tap a Load More button whose center was just outside the test viewport. The test scrolling helper was corrected; this was a test-harness visibility issue, not a product-state failure. An intermediate `flutter analyze` run also reported one braces lint in a new test; it was corrected before final verification.

## Corrections

### Refresh and crop pagination

- First-page requests are single-flight for the current filter.
- Filter changes can supersede an older first-page request.
- Load More is guarded in the method and disabled in the UI during initial loading or refresh.
- Refresh still invalidates an older pending pagination response.
- Failed refresh preserves same-account records and valid pagination metadata.
- Pagination continues using the service page's `nextOffset`.
- Deduplication preserves first appearance without deriving offsets from the UI list.

### Farm metadata retry semantics

- Farm requests record explicit operation kind: initial, refresh, or additional page.
- Failed operations retain the exact retry offset.
- Initial and refresh retries use offset zero.
- Additional-page retry repeats the failed offset.
- Metadata refresh replaces cached metadata only after success.
- Recoverable failure keeps existing metadata.
- Failed pagination does not advance the next offset.
- Refresh Farms is disabled while additional farm pagination is pending.

### Selected-farm unavailability

- UI decisions use `CropCycleFailureType.notFound`, not message equality.
- Initial, refresh, and additional-page 404 responses clear incompatible crop records and pagination.
- The selected farm ID remains until explicit user recovery.
- The safe unavailable-farm state provides an All Farms action.
- The controlled dropdown rebuilds to match programmatic recovery.
- Returning to All Farms omits `farm_id`.
- A selected farm missing from one refreshed metadata page remains selected and is shown with the neutral ID fallback.

### Protected-route safety

- A one-way screen-local invalidation flag prevents repeated invalidation and navigation callbacks.
- All crop and farm action guards reject work after invalidation starts.
- Result acceptance checks reject all delayed successes and failures.
- Crop data, farm metadata, filter state, errors, and request flags are cleared.
- The session listener is removed on disposal.
- Deferred root navigation checks `mounted`.
- Terminal unauthorized service responses invalidate the protected route even when the session generation did not change.
- Account replacement coverage uses distinct synthetic profile IDs and verifies the old route never dispatches with replacement credentials.

## Test inventory

The CropCycle widget suite now contains 33 tests: the original 17 plus 16 hardening regressions. New coverage includes:

- pending refresh versus Load More, successful recovery, and failed-refresh recovery;
- initial, refresh, and additional farm retry offsets;
- refresh coordination during farm pagination;
- typed selected-farm 404 handling during refresh and pagination;
- synchronized All Farms recovery and omitted `farm_id`;
- selected farm absent from refreshed metadata;
- exactly full page followed by empty final page;
- repeated Load More single-flight behavior;
- server-derived offset after deduplication;
- delayed error from a superseded filter;
- empty filtered state and filter-preserving refresh;
- logout and account replacement during pending initial and pagination requests;
- delayed errors after route invalidation and old credential isolation;
- terminal unauthorized protected-route behavior;
- wide desktop, increased text scale, multilingual content, tooltips, status text, and narrow layout.

## Verification results

Commands were run from `mobile/` unless stated otherwise.

| Command | Exit | Result |
|---|---:|---|
| `flutter test test/crop_cycle_screens_test.dart` | 0 | 33 passed |
| `flutter test test/crop_cycle_service_test.dart` | 0 | 70 passed |
| `flutter test test/crop_cycle_model_test.dart` | 0 | 95 passed |
| `flutter test test/farm_screens_test.dart` | 0 | 20 passed |
| `flutter test test/automatic_token_refresh_test.dart` | 0 | 17 passed |
| `flutter test test/logout_session_test.dart` | 0 | 11 passed |
| `flutter analyze` | 0 | No issues found |
| `flutter test --reporter compact` | 0 | 376 passed, 0 failed, 0 skipped |
| `git diff --check` | 0 | Passed; Git printed only LF/CRLF advisories |
| `git diff --stat` | 0 | Two source files modified before this evidence file was added |

The complete native suite increased from 360 to 376 tests, exactly matching the 16 new hardening tests.

## Final Git state

Modified:

- `mobile/lib/features/crops/presentation/my_crop_cycles_screen.dart`
- `mobile/test/crop_cycle_screens_test.dart`

Created:

- `AgroCrew-Step-27D1-List-UI-Hardening-Review-Evidence.md`

Preserved untracked files:

- `AgroCrew-Step-27C-External-Source-Review-Evidence.md`
- `AgroCrew-Step-27C1-Hardening-Review-Evidence.md`
- `AgroCrew-Step-27C2-Auth-Persistence-Review-Evidence.md`

No authentication, networking, service, model, backend, database, dependency, lockfile, or Flutter SDK file was modified. No commit or push was performed.

## Remaining risks and limitations

Offset pagination cannot provide a stable snapshot while server records change concurrently. ID deduplication prevents duplicate rendering while server-derived offsets preserve the API contract.

No Android emulator, Chrome runtime, real backend, or screenshot verification was performed. Responsive and accessibility behavior was verified through mocked Flutter widget tests.

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
  bool _routeInvalidating = false;
  bool _firstPageRequestActive = false;
  int? _firstPageRequestFarmId;
  int? _selectedFarmId;
  int _nextOffset = 0;
  int _farmNextOffset = 0;
  bool _initialLoading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _farmLoading = false;
  bool _farmLoadingMore = false;
  bool _farmHasMore = false;
  String? _initialError;
  CropCycleFailureType? _initialErrorType;
  String? _listMessage;
  String? _loadMoreError;
  String? _farmError;
  _FarmRequestKind? _failedFarmRequestKind;
  int? _failedFarmOffset;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.session.generation;
    widget.session.addListener(_sessionChanged);
    _loadFirstPage();
    _loadFarmPage(_FarmRequestKind.initial);
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
    if (_sessionIsCurrent || _routeInvalidating) return;
    _invalidateProtectedRoute();
  }

  void _invalidateProtectedRoute() {
    if (_routeInvalidating) return;
    _routeInvalidating = true;
    _cropRequestSerial += 1;
    _farmRequestSerial += 1;
    if (mounted) {
      setState(() {
        _crops.clear();
        _farmNames.clear();
        _selectedFarmId = null;
        _initialError = null;
        _initialErrorType = null;
        _listMessage = null;
        _loadMoreError = null;
        _farmError = null;
        _initialLoading = true;
        _refreshing = false;
        _firstPageRequestActive = false;
        _firstPageRequestFarmId = null;
        _loadingMore = false;
        _farmLoading = false;
        _farmLoadingMore = false;
        _failedFarmRequestKind = null;
        _failedFarmOffset = null;
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
      !_routeInvalidating &&
      _sessionIsCurrent;

  bool _acceptFarmResult(int serial) =>
      mounted &&
      serial == _farmRequestSerial &&
      !_routeInvalidating &&
      _sessionIsCurrent;

  Future<void> _loadFirstPage({bool refresh = false}) async {
    if (_routeInvalidating || !_sessionIsCurrent) return;
    final farmId = _selectedFarmId;
    if (_firstPageRequestActive && _firstPageRequestFarmId == farmId) return;
    final serial = ++_cropRequestSerial;
    setState(() {
      _firstPageRequestActive = true;
      _firstPageRequestFarmId = farmId;
      _initialError = null;
      _initialErrorType = null;
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
        _firstPageRequestActive = false;
        _firstPageRequestFarmId = null;
      });
    } on CropCycleException catch (error) {
      if (!_acceptCropResult(serial, farmId)) return;
      if (error.type == CropCycleFailureType.staleSession ||
          error.type == CropCycleFailureType.unauthorized) {
        _invalidateProtectedRoute();
        return;
      }
      if (error.type == CropCycleFailureType.notFound && farmId != null) {
        _showSelectedFarmUnavailable();
        return;
      }
      setState(() {
        _initialLoading = false;
        _refreshing = false;
        _firstPageRequestActive = false;
        _firstPageRequestFarmId = null;
        if (_crops.isEmpty) {
          _initialError = error.message;
          _initialErrorType = error.type;
        } else {
          _listMessage = error.message;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_routeInvalidating ||
        _loadingMore ||
        _initialLoading ||
        _refreshing ||
        !_hasMore ||
        !_sessionIsCurrent) {
      return;
    }
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
      if (error.type == CropCycleFailureType.notFound && farmId != null) {
        _showSelectedFarmUnavailable();
        return;
      }
      setState(() {
        _loadingMore = false;
        _loadMoreError = error.message;
      });
    }
  }

  Future<void> _changeFarm(int? farmId) async {
    if (_routeInvalidating || farmId == _selectedFarmId || !_sessionIsCurrent) {
      return;
    }
    _cropRequestSerial += 1;
    setState(() {
      _firstPageRequestActive = false;
      _firstPageRequestFarmId = null;
      _selectedFarmId = farmId;
      _crops.clear();
      _initialError = null;
      _initialErrorType = null;
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

  void _showSelectedFarmUnavailable() {
    if (!mounted || _routeInvalidating) return;
    setState(() {
      _crops.clear();
      _nextOffset = 0;
      _hasMore = false;
      _initialLoading = false;
      _refreshing = false;
      _firstPageRequestActive = false;
      _firstPageRequestFarmId = null;
      _loadingMore = false;
      _loadMoreError = null;
      _listMessage = null;
      _initialError = 'Crop cycle or farm not found.';
      _initialErrorType = CropCycleFailureType.notFound;
    });
  }

  Future<void> _loadFarmPage(_FarmRequestKind kind, {int? retryOffset}) async {
    if (_routeInvalidating ||
        !_sessionIsCurrent ||
        _farmLoading ||
        _farmLoadingMore) {
      return;
    }
    final reset = kind != _FarmRequestKind.more;
    final serial = reset ? ++_farmRequestSerial : _farmRequestSerial;
    final offset = reset ? 0 : (retryOffset ?? _farmNextOffset);
    setState(() {
      _farmError = null;
      _failedFarmRequestKind = null;
      _failedFarmOffset = null;
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
        _failedFarmRequestKind = null;
        _failedFarmOffset = null;
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
        _failedFarmRequestKind = kind;
        _failedFarmOffset = offset;
      });
    }
  }

  void _retryFarmPage() {
    final kind = _failedFarmRequestKind;
    if (kind == null) return;
    _loadFarmPage(kind, retryOffset: _failedFarmOffset);
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
                onLoadMore: () => _loadFarmPage(_FarmRequestKind.more),
                onRetry: _retryFarmPage,
                onRefresh: () => _loadFarmPage(_FarmRequestKind.refresh),
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
          _initialErrorType == CropCycleFailureType.notFound;
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
                onPressed: _loadingMore || _refreshing || _initialLoading
                    ? null
                    : _loadMore,
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
                  child: KeyedSubtree(
                    key: const Key('crop-cycles-farm-filter'),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('farm-filter-value-$selectedValue'),
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
                      onChanged: (value) =>
                          onChanged(value == -1 ? null : value),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('farm-metadata-refresh'),
                  tooltip: 'Refresh farms',
                  onPressed: loading || loadingMore ? null : onRefresh,
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

enum _FarmRequestKind { initial, refresh, more }
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
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        expect(request.url.queryParameters['offset'], '0');
        return farmCalls == 1
            ? http.Response('{}', 500)
            : http.Response(jsonEncode([_farm(77, 'Recovered Farm')]), 200);
      }
      return http.Response(jsonEncode([_crop(7, farmId: 77)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-metadata-error')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-7')), findsOneWidget);
    expect(find.text('Farm #77'), findsOneWidget);
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(farmCalls, 2);
    expect(find.text('Recovered Farm'), findsOneWidget);
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

  testWidgets('pending refresh blocks pagination then uses refreshed offset', (
    tester,
  ) async {
    final refresh = Completer<http.Response>();
    final cropQueries = <Map<String, String>>[];
    var firstPages = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropQueries.add(request.url.queryParameters);
      if (request.url.queryParameters['offset'] == '20') {
        return http.Response(jsonEncode([_crop(121)]), 200);
      }
      firstPages++;
      if (firstPages == 2) return refresh.future;
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1))),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('crop-cycles-load-more')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    expect(cropQueries.length, 2);
    refresh.complete(
      http.Response(jsonEncode(List.generate(20, (i) => _crop(i + 101))), 200),
    );
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(cropQueries.last['offset'], '20');
    expect(find.byKey(const Key('crop-cycle-card-121')), findsOneWidget);
  });

  testWidgets('failed refresh preserves records and pagination recovery', (
    tester,
  ) async {
    final refresh = Completer<http.Response>();
    var calls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      if (calls == 2) return refresh.future;
      expect(request.url.queryParameters['offset'], '20');
      return http.Response(jsonEncode([_crop(21)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    expect(calls, 2);
    refresh.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
  });

  testWidgets('farm refresh retry requests offset zero and replaces metadata', (
    tester,
  ) async {
    final offsets = <String?>[];
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      offsets.add(request.url.queryParameters['offset']);
      farmCalls++;
      if (farmCalls == 1) {
        return http.Response(jsonEncode([_farm(1, 'Old Farm')]), 200);
      }
      if (farmCalls == 2) return http.Response('{}', 500);
      return http.Response(jsonEncode([_farm(2, 'New Farm')]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets, ['0', '0', '0']);
    await tester.tap(find.byKey(const Key('crop-cycles-farm-filter')));
    await tester.pumpAndSettle();
    expect(find.text('New Farm (Farm #2)'), findsOneWidget);
    expect(find.text('Old Farm (Farm #1)'), findsNothing);
  });

  testWidgets('failed farm pagination retries the same offset', (tester) async {
    final offsets = <String?>[];
    var moreCalls = 0;
    final pending = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      if (offset == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _farm(i + 1, 'Farm ${i + 1}'))),
          200,
        );
      }
      moreCalls++;
      if (moreCalls == 1) return pending.future;
      if (moreCalls == 2) return http.Response('{}', 500);
      return http.Response(jsonEncode([_farm(21, 'Farm 21')]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-load-more')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('farm-metadata-refresh')))
          .onPressed,
      isNull,
    );
    pending.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets.where((offset) => offset == '20').length, 2);
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets.where((offset) => offset == '20').length, 3);
  });

  testWidgets('selected farm refresh 404 clears records and syncs All Farms', (
    tester,
  ) async {
    var filteredCalls = 0;
    final queries = <Map<String, String>>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(4, 'Farm Four')]), 200);
      }
      queries.add(request.url.queryParameters);
      if (request.url.queryParameters['farm_id'] == '4') {
        filteredCalls++;
        return filteredCalls == 1
            ? http.Response(jsonEncode([_crop(4, farmId: 4)]), 200)
            : http.Response('{}', 404);
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Farm Four (Farm #4)');
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-4')), findsNothing);
    expect(_filterValue(tester), 4);
    await tester.tap(find.text('All Farms').last);
    await tester.pumpAndSettle();
    expect(_filterValue(tester), -1);
    expect(queries.last.containsKey('farm_id'), isFalse);
  });

  testWidgets('selected farm load-more 404 invalidates cached pagination', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(3, 'Farm Three')]), 200);
      }
      if (request.url.queryParameters['farm_id'] == '3' &&
          request.url.queryParameters['offset'] == '20') {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1, farmId: 3))),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Farm Three (Farm #3)');
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-load-more')), findsNothing);
    expect(_filterValue(tester), 3);
  });

  testWidgets(
    'full page empty final page and repeated taps stay single-flight',
    (tester) async {
      final finalPage = Completer<http.Response>();
      var moreCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms') {
          return http.Response('[]', 200);
        }
        if (request.url.queryParameters['offset'] == '20') {
          moreCalls++;
          return finalPage.future;
        }
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      });
      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await _scrollToLoadMore(tester);
      await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
      await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
      expect(moreCalls, 1);
      finalPage.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycles-load-more')), findsNothing);
    },
  );

  testWidgets('deduplication advances with the server page offset', (
    tester,
  ) async {
    final offsets = <String?>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      if (offset == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      if (offset == '20') {
        return http.Response(
          jsonEncode([_crop(20), ...List.generate(19, (i) => _crop(i + 21))]),
          200,
        );
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(offsets, ['0', '20', '40']);
  });

  testWidgets('delayed error from superseded farm filter is ignored', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode([_farm(1, 'One'), _farm(2, 'Two')]),
          200,
        );
      }
      if (request.url.queryParameters['farm_id'] == '1') return old.future;
      if (request.url.queryParameters['farm_id'] == '2') {
        return http.Response(jsonEncode([_crop(2, farmId: 2)]), 200);
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)', settle: false);
    await _selectFarm(tester, 'Two (Farm #2)');
    old.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-error')), findsNothing);
  });

  testWidgets('filtered empty state and refresh preserve the farm filter', (
    tester,
  ) async {
    final queries = <Map<String, String>>[];
    var filteredCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(5, 'Filter Farm')]), 200);
      }
      queries.add(request.url.queryParameters);
      if (request.url.queryParameters['farm_id'] == '5') filteredCalls++;
      return http.Response(
        filteredCalls > 1 ? jsonEncode([_crop(5, farmId: 5)]) : '[]',
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Filter Farm (Farm #5)');
    expect(find.text('No crop cycles found for this farm.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(queries.last['farm_id'], '5');
    expect(find.byKey(const Key('crop-cycle-card-5')), findsOneWidget);
  });

  testWidgets('missing selected farm metadata remains a valid selection', (
    tester,
  ) async {
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        return http.Response(
          farmCalls == 1 ? jsonEncode([_farm(6, 'Known Farm')]) : '[]',
          200,
        );
      }
      return request.url.queryParameters['farm_id'] == '6'
          ? http.Response(jsonEncode([_crop(6, farmId: 6)]), 200)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Known Farm (Farm #6)');
    await tester.tap(find.byKey(const Key('farm-metadata-refresh')));
    await tester.pumpAndSettle();
    expect(_filterValue(tester), 6);
    expect(find.text('Farm #6'), findsWidgets);
    expect(find.text('This farm is unavailable.'), findsNothing);
  });

  testWidgets('account replacement rejects pending crop and farm responses', (
    tester,
  ) async {
    final crops = Completer<http.Response>();
    final farms = Completer<http.Response>();
    final headers = <String?>[];
    var cropCalls = 0;
    var farmCalls = 0;
    final fixture = await _fixture((request) {
      headers.add(request.headers['authorization']);
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        return farms.future;
      }
      cropCalls++;
      return crops.future;
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await fixture.session.establishVerified(
      _tokens('replacement'),
      _profile(88),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    crops.complete(http.Response(jsonEncode([_crop(1)]), 200));
    farms.complete(http.Response(jsonEncode([_farm(1, 'Old Farm')]), 200));
    await tester.pumpAndSettle();
    expect(cropCalls, 1);
    expect(farmCalls, 1);
    expect(headers, everyElement('Bearer access'));
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
  });

  testWidgets('logout rejects pending initial crop and farm failures', (
    tester,
  ) async {
    final crops = Completer<http.Response>();
    final farms = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/auth/logout') {
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/farms') return farms.future;
      return crops.future;
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    crops.complete(http.Response('{}', 500));
    farms.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-error')), findsNothing);
    expect(find.byKey(const Key('farm-metadata-error')), findsNothing);
  });

  testWidgets('logout invalidates pending crop pagination and old route', (
    tester,
  ) async {
    final more = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/auth/logout') {
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '20') return more.future;
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1))),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pump();
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    more.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-load-more-error')), findsNothing);
  });

  testWidgets('terminal unauthorized response closes the protected route', (
    tester,
  ) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.path == '/api/v1/auth/refresh') {
        return _jsonResponse({
          'access_token': 'refreshed',
          'refresh_token': 'refresh-refreshed',
          'token_type': 'bearer',
          'expires_in': 1800,
          'refresh_expires_in': 604800,
        });
      }
      cropCalls++;
      return http.Response('{}', 401);
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(cropCalls, 2);
    expect(find.text('Open'), findsOneWidget);
    expect(fixture.session.profile?.id, 7);
  });

  testWidgets('wide and scaled layouts retain accessible controls', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = await _fixture(
      (request) async => request.url.path == '/api/v1/farms'
          ? _jsonResponse([_farm(1, 'Wide multilingual farm')])
          : _jsonResponse([
              _crop(
                1,
                cropType: 'Long English crop name · සිංහල බෝගය · தமிழ் பயிர்',
                variety: 'Accessible multilingual variety',
              ),
            ]),
    );
    await _pumpCrops(tester, fixture, size: const Size(1600, 1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byTooltip('Refresh crop cycles'), findsOneWidget);
    expect(find.byTooltip('Refresh farms'), findsOneWidget);
    expect(find.textContaining('සිංහල'), findsOneWidget);
    expect(find.textContaining('தமிழ்'), findsOneWidget);
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

Future<void> _scrollToLoadMore(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('crop-cycles-load-more')),
    500,
    scrollable: _cropScrollable(),
  );
  await tester.drag(_cropScrollable(), const Offset(0, -120));
  await tester.pump();
}

int? _filterValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )
    .initialValue;

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

## Evidence integrity

After evidence creation, each fenced source block is extracted, line endings are normalized to LF, trailing newlines are normalized, and the result is compared with its corresponding working-tree file.

