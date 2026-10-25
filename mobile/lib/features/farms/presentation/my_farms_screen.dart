import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../data/farm_service.dart';
import '../data/models/farm.dart';
import 'add_farm_screen.dart';
import 'farm_details_screen.dart';

class MyFarmsScreen extends StatefulWidget {
  const MyFarmsScreen({
    super.key,
    required this.farmService,
    required this.session,
  });

  final FarmService farmService;
  final AuthSession session;

  @override
  State<MyFarmsScreen> createState() => _MyFarmsScreenState();
}

class _MyFarmsScreenState extends State<MyFarmsScreen> {
  static const _pageSize = 20;
  final List<Farm> _farms = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    _load();
  }

  @override
  void dispose() {
    _requestSerial += 1;
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (widget.session.state == AuthSessionState.authenticated) return;
    _requestSerial += 1;
    if (mounted) {
      setState(() {
        _farms.clear();
        _loading = true;
        _error = null;
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

  Future<void> _load({bool refresh = false}) async {
    final serial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        if (refresh) _farms.clear();
      });
    }
    try {
      final page = await widget.farmService.listFarms(limit: _pageSize);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _farms
          ..clear()
          ..addAll(page.farms);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on FarmException catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final serial = _requestSerial;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.farmService.listFarms(
        limit: _pageSize,
        offset: _farms.length,
      );
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _farms.addAll(page.farms);
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on FarmException catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _addFarm() async {
    final created = await Navigator.of(context).push<Farm>(
      MaterialPageRoute(
        builder: (_) => AddFarmScreen(farmService: widget.farmService),
      ),
    );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Farm added successfully.')));
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Farms'),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(32),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Manage your farming locations.'),
          ),
        ),
      ),
      actions: [
        IconButton(
          key: const Key('farms-refresh'),
          tooltip: 'Refresh farms',
          onPressed: _loading ? null : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: _loading || _error != null
        ? null
        : FloatingActionButton.extended(
            key: const Key('add-farm-button'),
            onPressed: _addFarm,
            icon: const Icon(Icons.add),
            label: const Text('Add Farm'),
          ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _body(),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(
          key: Key('farms-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your farms...'),
          ],
        ),
      );
    }
    if (_error != null) {
      return _MessageState(
        key: const Key('farms-error'),
        icon: Icons.cloud_off_outlined,
        title: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_farms.isEmpty) {
      return _MessageState(
        key: const Key('farms-empty'),
        icon: Icons.agriculture_outlined,
        title: "You haven't added any farms yet.",
        subtitle: 'Create your first farm to get started.',
        actionLabel: 'Add Farm',
        onAction: _addFarm,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView.separated(
        key: const Key('farms-list'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        itemCount: _farms.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _farms.length) {
            return Center(
              child: OutlinedButton.icon(
                key: const Key('farms-load-more'),
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? 'Loading...' : 'Load More'),
              ),
            );
          }
          return _FarmCard(
            farm: _farms[index],
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FarmDetailsScreen(
                  farmId: _farms[index].id,
                  farmService: widget.farmService,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FarmCard extends StatelessWidget {
  const _FarmCard({required this.farm, required this.onTap});

  final Farm farm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      key: Key('farm-card-${farm.id}'),
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(
                Icons.grass,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farm.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    farm.areaValue == null
                        ? 'Area not provided.'
                        : 'Area: ${farm.areaValue}${farm.areaUnit == null ? '' : ' ${farm.areaUnit}'}',
                  ),
                  Text(
                    farm.latitude != null && farm.longitude != null
                        ? 'Location: Available'
                        : 'Location not provided.',
                  ),
                  const SizedBox(height: 6),
                  const Text('Tap to view details'),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
