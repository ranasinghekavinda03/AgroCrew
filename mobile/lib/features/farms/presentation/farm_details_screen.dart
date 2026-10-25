import 'package:flutter/material.dart';

import '../data/farm_service.dart';
import '../data/models/farm.dart';
import 'edit_farm_screen.dart';

class FarmDetailsScreen extends StatefulWidget {
  const FarmDetailsScreen({
    super.key,
    required this.farmId,
    required this.farmService,
  });

  final int farmId;
  final FarmService farmService;

  @override
  State<FarmDetailsScreen> createState() => _FarmDetailsScreenState();
}

class _FarmDetailsScreenState extends State<FarmDetailsScreen> {
  Farm? _farm;
  String? _error;
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final farm = await widget.farmService.getFarm(widget.farmId);
      if (!mounted) return;
      setState(() {
        _farm = farm;
        _loading = false;
      });
    } on FarmException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Farm>(
      MaterialPageRoute(
        builder: (_) => EditFarmScreen(
          farmId: widget.farmId,
          farmService: widget.farmService,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _farm = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Farm updated successfully.')));
  }

  Future<void> _confirmDelete() async {
    if (_deleting || _farm == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Farm?'),
        content: Text(
          'Are you sure you want to delete "${_farm!.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-farm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-farm-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Farm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.farmService.deleteFarm(widget.farmId);
      if (mounted) Navigator.of(context).pop(true);
    } on FarmException catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Farm Details')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    key: Key('farm-details-loading'),
                  ),
                )
              : _error != null
              ? Center(
                  key: const Key('farm-details-error'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline, size: 52),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _details(context, _farm!),
        ),
      ),
    ),
  );

  Widget _details(BuildContext context, Farm farm) => ListView(
    key: const Key('farm-details-content'),
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.grass,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(farm.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              _row('Farm ID', '${farm.id}'),
              _row(
                'Area',
                farm.areaValue == null
                    ? 'Not provided'
                    : '${farm.areaValue}${farm.areaUnit == null ? '' : ' ${farm.areaUnit}'}',
              ),
              _row('Latitude', farm.latitude?.toString() ?? 'Not provided'),
              _row('Longitude', farm.longitude?.toString() ?? 'Not provided'),
              _row(
                'Notes',
                farm.notes?.trim().isNotEmpty == true
                    ? farm.notes!
                    : 'Not provided',
              ),
              _row('Created', _date(farm.createdAt)),
              _row('Last updated', _date(farm.updatedAt)),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('edit-farm-button'),
                onPressed: _deleting ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Farm'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('delete-farm-button'),
                onPressed: _deleting ? null : _confirmDelete,
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
                label: Text(_deleting ? 'Deleting...' : 'Delete Farm'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
