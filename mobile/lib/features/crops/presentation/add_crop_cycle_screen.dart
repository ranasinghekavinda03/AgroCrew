import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../../farms/data/farm_service.dart';
import '../../farms/data/models/farm.dart';
import '../../farms/presentation/my_farms_screen.dart';
import '../data/crop_cycle_service.dart';
import '../data/models/crop_cycle.dart';

class AddCropCycleResult {
  const AddCropCycleResult.confirmed(this.cropCycle) : uncertain = false;
  const AddCropCycleResult.uncertain() : cropCycle = null, uncertain = true;

  final CropCycle? cropCycle;
  final bool uncertain;
}

class AddCropCycleScreen extends StatefulWidget {
  const AddCropCycleScreen({
    super.key,
    required this.cropCycleService,
    required this.farmService,
    required this.session,
    this.initialFarmId,
  });

  final CropCycleService cropCycleService;
  final FarmService farmService;
  final AuthSession session;
  final int? initialFarmId;

  @override
  State<AddCropCycleScreen> createState() => _AddCropCycleScreenState();
}

class _AddCropCycleScreenState extends State<AddCropCycleScreen> {
  static const _farmPageSize = 20;
  final _formKey = GlobalKey<FormState>();
  final _cropType = TextEditingController();
  final _variety = TextEditingController();
  final _plantingDate = TextEditingController();
  final _expectedHarvestDate = TextEditingController();
  final _plantCount = TextEditingController();
  final _notes = TextEditingController();
  final Map<int, Farm> _farms = {};
  Farm? _verifiedInitialFarm;

  late final int _sessionGeneration;
  int _farmRequestSerial = 0;
  int? _selectedFarmId;
  int _farmNextOffset = 0;
  bool _farmLoading = true;
  bool _farmLoadingMore = false;
  bool _farmHasMore = false;
  bool _initialFarmChecking = false;
  bool _routeInvalidating = false;
  bool _submitting = false;
  bool _ambiguous = false;
  CropStatus _status = CropStatus.planned;
  String? _farmError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.session.generation;
    _selectedFarmId = widget.initialFarmId;
    _initialFarmChecking = widget.initialFarmId != null;
    widget.session.addListener(_sessionChanged);
    _loadFarms(reset: true);
    if (widget.initialFarmId case final farmId?) _verifyInitialFarm(farmId);
  }

  @override
  void dispose() {
    _farmRequestSerial += 1;
    widget.session.removeListener(_sessionChanged);
    _cropType.dispose();
    _variety.dispose();
    _plantingDate.dispose();
    _expectedHarvestDate.dispose();
    _plantCount.dispose();
    _notes.dispose();
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
    _farmRequestSerial += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    });
  }

  bool _acceptFarmResult(int serial) =>
      mounted &&
      serial == _farmRequestSerial &&
      !_routeInvalidating &&
      _sessionIsCurrent;

  Future<void> _loadFarms({required bool reset}) async {
    if (_routeInvalidating ||
        !_sessionIsCurrent ||
        _farmLoadingMore ||
        (!reset && (_farmLoading || !_farmHasMore))) {
      return;
    }
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
        limit: _farmPageSize,
        offset: offset,
      );
      if (!_acceptFarmResult(serial)) return;
      setState(() {
        if (reset) {
          _farms.clear();
          final verified = _verifiedInitialFarm;
          if (verified != null) _farms[verified.id] = verified;
        }
        for (final farm in page.farms) {
          _farms[farm.id] = farm;
        }
        _farmNextOffset = offset + page.farms.length;
        _farmHasMore = page.hasMore;
        _farmLoading = false;
        _farmLoadingMore = false;
      });
    } on FarmException catch (error) {
      if (!_acceptFarmResult(serial)) return;
      if (error.type == FarmFailureType.unauthorized ||
          error.type == FarmFailureType.staleSession) {
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

  Future<void> _verifyInitialFarm(int farmId) async {
    try {
      final farm = await widget.farmService.getFarm(farmId);
      if (!mounted || _routeInvalidating || !_sessionIsCurrent) return;
      setState(() {
        _verifiedInitialFarm = farm;
        _farms[farm.id] = farm;
        _initialFarmChecking = false;
      });
    } on FarmException catch (error) {
      if (!mounted || _routeInvalidating || !_sessionIsCurrent) return;
      if (error.type == FarmFailureType.unauthorized ||
          error.type == FarmFailureType.staleSession) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _initialFarmChecking = false;
        _selectedFarmId = null;
        _farmError = error.type == FarmFailureType.notFound
            ? 'The selected farm is no longer available. Choose another farm.'
            : error.message;
      });
    }
  }

  Future<void> _openMyFarms() async {
    if (_submitting || !_sessionIsCurrent) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MyFarmsScreen(
          farmService: widget.farmService,
          session: widget.session,
        ),
      ),
    );
    if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
    await _loadFarms(reset: true);
  }

  String? _requiredCropType(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Crop type is required.';
    if (normalized.runes.length > 128) {
      return 'Crop type must be 128 characters or fewer.';
    }
    return null;
  }

  String? _optionalLength(String? value, int maximum, String label) {
    if ((value ?? '').runes.length > maximum) {
      return '$label must be $maximum characters or fewer.';
    }
    return null;
  }

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1 || year > 9999) return null;
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }

  String? _plantingDateValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Planting date is required.';
    if (_parseDate(text) == null) return 'Enter a valid date as YYYY-MM-DD.';
    return null;
  }

  String? _harvestDateValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final harvest = _parseDate(text);
    if (harvest == null) return 'Enter a valid date as YYYY-MM-DD.';
    final planting = _parseDate(_plantingDate.text.trim());
    if (planting != null && harvest.isBefore(planting)) {
      return 'Expected harvest cannot be before planting.';
    }
    return null;
  }

  String? _plantCountValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) {
      return 'Plant count must be a positive whole number.';
    }
    final count = int.tryParse(text);
    if (count == null || count <= 0) {
      return 'Plant count must be a positive whole number.';
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final parsed = _parseDate(controller.text.trim());
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(today.year, today.month, today.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: controller == _plantingDate
          ? 'Select planting date'
          : 'Select expected harvest date',
    );
    if (picked == null || !mounted) return;
    controller.text = _formatDate(picked);
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_submitting || _ambiguous || _routeInvalidating || !_sessionIsCurrent) {
      return;
    }
    final farmId = _selectedFarmId;
    if (!_formKey.currentState!.validate() ||
        farmId == null ||
        !_farms.containsKey(farmId) ||
        _initialFarmChecking) {
      if (farmId == null || !_farms.containsKey(farmId)) {
        setState(() => _submitError = 'Choose an available farm.');
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final variety = _variety.text.trim();
    final harvest = _expectedHarvestDate.text.trim();
    final count = _plantCount.text.trim();
    final notes = _notes.text;
    try {
      final crop = await widget.cropCycleService.createCropCycle(
        CropCycleCreate(
          farmId: farmId,
          cropType: _cropType.text,
          variety: variety.isEmpty ? null : variety,
          plantingDate: _parseDate(_plantingDate.text.trim())!,
          expectedHarvestDate: harvest.isEmpty ? null : _parseDate(harvest),
          status: _status,
          plantCount: count.isEmpty ? null : int.parse(count),
          notes: notes.trim().isEmpty ? null : notes,
        ),
      );
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      Navigator.of(context).pop(AddCropCycleResult.confirmed(crop));
    } on CropCycleException catch (error) {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      if (error.type == CropCycleFailureType.unauthorized ||
          error.type == CropCycleFailureType.staleSession) {
        _invalidateProtectedRoute();
        return;
      }
      setState(() {
        _submitting = false;
        _ambiguous = error.type == CropCycleFailureType.ambiguousCreation;
        _submitError = _ambiguous
            ? 'The create outcome could not be confirmed. Return to My Crop Cycles and refresh the list before trying again.'
            : error.message;
      });
    } on Object {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      setState(() {
        _submitting = false;
        _submitError = 'AgroCrew could not create the crop cycle. Try again.';
      });
    }
  }

  void _cancel() {
    if (!_submitting) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Add Crop Cycle'),
        actions: [
          TextButton(
            key: const Key('cancel-crop-cycle-button'),
            onPressed: _submitting ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            key: const Key('add-crop-cycle-form'),
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Record a crop cycle for one of your farms.',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      _farmField(),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('crop-type-field'),
                        controller: _cropType,
                        validator: _requiredCropType,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Crop type *',
                          helperText: 'Required; up to 128 characters.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('crop-variety-field'),
                        controller: _variety,
                        validator: (value) =>
                            _optionalLength(value, 128, 'Variety'),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Variety (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _dateField(
                        key: const Key('planting-date-field'),
                        controller: _plantingDate,
                        label: 'Planting date *',
                        validator: _plantingDateValidator,
                      ),
                      const SizedBox(height: 16),
                      _dateField(
                        key: const Key('expected-harvest-date-field'),
                        controller: _expectedHarvestDate,
                        label: 'Expected harvest date (optional)',
                        validator: _harvestDateValidator,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<CropStatus>(
                        key: const Key('crop-status-field'),
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: CropStatus.planned,
                            child: Text('Planned'),
                          ),
                          DropdownMenuItem(
                            value: CropStatus.active,
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: CropStatus.harvested,
                            child: Text('Harvested'),
                          ),
                          DropdownMenuItem(
                            value: CropStatus.cancelled,
                            child: Text('Cancelled'),
                          ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _status = value);
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('plant-count-field'),
                        controller: _plantCount,
                        validator: _plantCountValidator,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Plant count (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('crop-notes-field'),
                        controller: _notes,
                        validator: (value) =>
                            _optionalLength(value, 10000, 'Notes'),
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          helperText: 'Up to 10,000 characters.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_submitError != null) ...[
                        const SizedBox(height: 16),
                        Material(
                          key: const Key('crop-cycle-submit-error'),
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_submitError!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_ambiguous)
                        FilledButton.icon(
                          key: const Key('inspect-crop-cycles-button'),
                          onPressed: () =>
                              Navigator.of(context)
                                  .pop(const AddCropCycleResult.uncertain()),
                          icon: const Icon(Icons.list_alt_outlined),
                          label: const Text('Return to My Crop Cycles'),
                        )
                      else
                        FilledButton.icon(
                          key: const Key('create-crop-cycle-button'),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_circle_outline),
                          label: Text(
                            _submitting ? 'Creating...' : 'Create Crop Cycle',
                          ),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('cancel-crop-cycle-bottom-button'),
                        onPressed: _submitting ? null : _cancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _farmField() {
    if (_farmLoading && _farms.isEmpty) {
      return const Column(
        key: Key('crop-farms-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Farm *'),
          SizedBox(height: 8),
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('Loading your farms...'),
        ],
      );
    }
    if (_farmError != null && _farms.isEmpty) {
      return _FarmMessage(
        key: const Key('crop-farms-error'),
        message: _farmError!,
        actionLabel: 'Retry',
        onAction: () => _loadFarms(reset: true),
      );
    }
    if (_farms.isEmpty && !_farmHasMore) {
      return _FarmMessage(
        key: const Key('crop-farms-empty'),
        message: 'Create a farm first before adding a crop cycle.',
        actionLabel: 'Go to My Farms',
        onAction: _openMyFarms,
      );
    }
    final farms = _farms.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: const Key('crop-farm-field'),
          initialValue: _farms.containsKey(_selectedFarmId)
              ? _selectedFarmId
              : null,
          isExpanded: true,
          validator: (value) => value == null ? 'Choose a farm.' : null,
          decoration: const InputDecoration(
            labelText: 'Farm *',
            border: OutlineInputBorder(),
          ),
          hint: Text(
            _initialFarmChecking ? 'Checking selected farm...' : 'Choose farm',
          ),
          items: [
            for (final farm in farms)
              DropdownMenuItem(
                value: farm.id,
                child: Text(
                  '${farm.name} (Farm #${farm.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _submitting || _initialFarmChecking
              ? null
              : (value) => setState(() {
                  _selectedFarmId = value;
                  _submitError = null;
                }),
        ),
        if (_farmError != null) ...[
          const SizedBox(height: 8),
          Text(
            _farmError!,
            key: const Key('crop-farms-inline-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _loadFarms(reset: true),
              child: const Text('Retry farm loading'),
            ),
          ),
        ],
        if (_farmHasMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('crop-farms-load-more'),
              onPressed: _farmLoadingMore
                  ? null
                  : () => _loadFarms(reset: false),
              icon: _farmLoadingMore
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(_farmLoadingMore ? 'Loading...' : 'Load More Farms'),
            ),
          ),
      ],
    );
  }

  Widget _dateField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required FormFieldValidator<String> validator,
  }) => TextFormField(
    key: key,
    controller: controller,
    validator: validator,
    keyboardType: TextInputType.datetime,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      helperText: 'YYYY-MM-DD',
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: 'Choose $label',
        onPressed: _submitting ? null : () => _pickDate(controller),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
  );
}

class _FarmMessage extends StatelessWidget {
  const _FarmMessage({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
