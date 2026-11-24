import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../../farms/data/farm_service.dart';
import '../data/crop_cycle_service.dart';
import '../data/models/crop_cycle.dart';
import 'add_crop_cycle_screen.dart';
import 'crop_cycle_details_screen.dart';

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
  bool _refreshAfterFirstPage = false;
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
  bool _refreshFarmsAfterCurrentPage = false;
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
        _refreshFarmsAfterCurrentPage = false;
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
      await _runDeferredRefresh();
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
      await _runDeferredRefresh();
    }
  }

  Future<void> _runDeferredRefresh() async {
    if (!_refreshAfterFirstPage ||
        !mounted ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    _refreshAfterFirstPage = false;
    await _loadFirstPage(refresh: true);
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
    if (_routeInvalidating || !_sessionIsCurrent) {
      return;
    }
    if (_farmLoading || _farmLoadingMore) {
      if (kind == _FarmRequestKind.refresh) {
        _refreshFarmsAfterCurrentPage = true;
      }
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
      await _runDeferredFarmRefresh();
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
      await _runDeferredFarmRefresh();
    }
  }

  Future<void> _runDeferredFarmRefresh() async {
    if (!_refreshFarmsAfterCurrentPage ||
        !mounted ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    _refreshFarmsAfterCurrentPage = false;
    await _loadFarmPage(_FarmRequestKind.refresh);
  }

  void _retryFarmPage() {
    final kind = _failedFarmRequestKind;
    if (kind == null) return;
    _loadFarmPage(kind, retryOffset: _failedFarmOffset);
  }

  String _farmLabel(int farmId) => _farmNames[farmId] ?? 'Farm #$farmId';

  Future<void> _openCropCycle(CropCycle crop) async {
    if (_routeInvalidating || !_sessionIsCurrent) return;
    final refreshList = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CropCycleDetailsScreen(
          cropCycleService: widget.cropCycleService,
          session: widget.session,
          cropCycleId: crop.id,
          knownFarmId: crop.farmId,
          knownFarmName: _farmNames[crop.farmId],
        ),
      ),
    );
    if (!mounted ||
        refreshList != true ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    await _loadFirstPage(refresh: true);
  }

  Future<void> _addCropCycle() async {
    if (_routeInvalidating || !_sessionIsCurrent) return;
    final result = await Navigator.of(context).push<AddCropCycleResult>(
      MaterialPageRoute(
        builder: (_) => AddCropCycleScreen(
          cropCycleService: widget.cropCycleService,
          farmService: widget.farmService,
          session: widget.session,
          initialFarmId: _selectedFarmId,
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    final farmRefresh = _loadFarmPage(_FarmRequestKind.refresh);
    if (_firstPageRequestActive) {
      _refreshAfterFirstPage = true;
    } else {
      await _loadFirstPage(refresh: true);
    }
    await farmRefresh;
    if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
    final created = result.cropCycle;
    final hiddenByFilter =
        created != null &&
        _selectedFarmId != null &&
        created.farmId != _selectedFarmId;
    final message = result.uncertain
        ? 'Crop cycle creation was not confirmed. Review My Crop Cycles before trying again.'
        : hiddenByFilter
        ? 'Crop cycle created, but it is hidden by the current farm filter.'
        : 'Crop cycle created successfully.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Crop Cycles'),
      actions: [
        IconButton(
          key: const Key('add-crop-cycle-button'),
          tooltip: 'Add Crop Cycle',
          onPressed: _routeInvalidating ? null : _addCropCycle,
          icon: const Icon(Icons.add_circle_outline),
        ),
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
                onTap: () => _openCropCycle(crop),
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
  const _CropCycleCard({
    required this.crop,
    required this.farmLabel,
    required this.onTap,
  });

  final CropCycle crop;
  final String farmLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusPresentation(crop.status, theme.colorScheme);
    return Card(
      key: Key('crop-cycle-card-${crop.id}'),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'View ${crop.cropType} crop cycle details',
        child: InkWell(
          key: Key('open-crop-cycle-${crop.id}'),
          onTap: onTap,
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
                      avatar: Icon(
                        status.icon,
                        size: 18,
                        color: status.foreground,
                      ),
                      label: Text(status.label),
                      labelStyle: TextStyle(color: status.foreground),
                      backgroundColor: status.background,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
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
