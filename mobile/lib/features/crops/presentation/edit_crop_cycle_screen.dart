import 'package:flutter/material.dart';

import '../../auth/data/auth_session.dart';
import '../data/crop_cycle_service.dart';
import '../data/models/crop_cycle.dart';

enum EditCropCycleOutcome { confirmed, uncertain, unavailable }

class EditCropCycleResult {
  const EditCropCycleResult.confirmed(this.cropCycle)
    : outcome = EditCropCycleOutcome.confirmed;
  const EditCropCycleResult.uncertain()
    : outcome = EditCropCycleOutcome.uncertain,
      cropCycle = null;
  const EditCropCycleResult.unavailable()
    : outcome = EditCropCycleOutcome.unavailable,
      cropCycle = null;

  final EditCropCycleOutcome outcome;
  final CropCycle? cropCycle;
}

class EditCropCycleScreen extends StatefulWidget {
  const EditCropCycleScreen({
    super.key,
    required this.cropCycleService,
    required this.session,
    required this.cropCycle,
    required this.farmLabel,
  });

  final CropCycleService cropCycleService;
  final AuthSession session;
  final CropCycle cropCycle;
  final String farmLabel;

  @override
  State<EditCropCycleScreen> createState() => _EditCropCycleScreenState();
}

class _EditCropCycleScreenState extends State<EditCropCycleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cropType = TextEditingController();
  final _variety = TextEditingController();
  final _plantingDate = TextEditingController();
  final _expectedHarvestDate = TextEditingController();
  final _plantCount = TextEditingController();
  final _notes = TextEditingController();

  late final int _sessionGeneration;
  late CropStatus _status;
  bool _submitting = false;
  bool _routeInvalidating = false;
  bool _requiresInspection = false;
  bool _returningForInspection = false;
  EditCropCycleOutcome? _inspectionOutcome;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.session.generation;
    final crop = widget.cropCycle;
    _cropType.text = crop.cropType;
    _variety.text = crop.variety ?? '';
    _plantingDate.text = _formatDate(crop.plantingDate);
    _expectedHarvestDate.text = crop.expectedHarvestDate == null
        ? ''
        : _formatDate(crop.expectedHarvestDate!);
    _plantCount.text = crop.plantCount?.toString() ?? '';
    _notes.text = crop.notes ?? '';
    _status = crop.status;
    widget.session.addListener(_sessionChanged);
    if (!_sessionIsCurrent) _invalidateProtectedRoute();
  }

  @override
  void dispose() {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    });
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

  Future<void> _submit() async {
    if (_submitting ||
        _requiresInspection ||
        _routeInvalidating ||
        !_sessionIsCurrent) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;
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
      final crop = await widget.cropCycleService.updateCropCycle(
        widget.cropCycle.id,
        CropCycleUpdate(
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
      Navigator.of(context).pop(EditCropCycleResult.confirmed(crop));
    } on CropCycleException catch (error) {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      if (error.type == CropCycleFailureType.unauthorized ||
          error.type == CropCycleFailureType.staleSession) {
        _invalidateProtectedRoute();
        return;
      }
      final uncertain = error.type == CropCycleFailureType.ambiguousUpdate;
      final unavailable = error.type == CropCycleFailureType.notFound;
      setState(() {
        _submitting = false;
        _requiresInspection = uncertain || unavailable;
        _inspectionOutcome = uncertain
            ? EditCropCycleOutcome.uncertain
            : unavailable
            ? EditCropCycleOutcome.unavailable
            : null;
        _submitError = uncertain
            ? 'The update outcome could not be confirmed. To avoid overwriting current data, return to Crop Cycle Details and inspect the authoritative record before trying again.'
            : unavailable
            ? 'This crop cycle is unavailable. Return to Crop Cycle Details to refresh the list safely.'
            : error.type == CropCycleFailureType.conflict
            ? 'This crop cycle could not be updated because it conflicts with current data. Refresh details and try again.'
            : error.message;
      });
    } on Object {
      if (!mounted || !_sessionIsCurrent || _routeInvalidating) return;
      setState(() {
        _submitting = false;
        _requiresInspection = true;
        _inspectionOutcome = EditCropCycleOutcome.uncertain;
        _submitError =
            'The update outcome could not be confirmed. To avoid overwriting current data, return to Crop Cycle Details and inspect the authoritative record before trying again.';
      });
    }
  }

  void _cancel() {
    if (!_submitting && !_requiresInspection) Navigator.of(context).pop();
  }

  void _returnForInspection() {
    if (_returningForInspection) return;
    setState(() => _returningForInspection = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final result = _inspectionOutcome == EditCropCycleOutcome.unavailable
          ? const EditCropCycleResult.unavailable()
          : const EditCropCycleResult.uncertain();
      Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting && (!_requiresInspection || _returningForInspection),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit Crop Cycle'),
        actions: [
          TextButton(
            key: const Key('cancel-edit-crop-cycle-button'),
            onPressed: _submitting || _requiresInspection ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            key: const Key('edit-crop-cycle-form'),
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InputDecorator(
                        key: const Key('edit-crop-farm-read-only'),
                        decoration: const InputDecoration(
                          labelText: 'Farm',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.agriculture_outlined),
                        ),
                        child: Text(widget.farmLabel),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('edit-crop-type-field'),
                        controller: _cropType,
                        validator: _requiredCropType,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Crop type *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('edit-crop-variety-field'),
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
                        key: const Key('edit-planting-date-field'),
                        controller: _plantingDate,
                        label: 'Planting date *',
                        validator: _plantingDateValidator,
                      ),
                      const SizedBox(height: 16),
                      _dateField(
                        key: const Key('edit-expected-harvest-date-field'),
                        controller: _expectedHarvestDate,
                        label: 'Expected harvest date (optional)',
                        validator: _harvestDateValidator,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<CropStatus>(
                        key: const Key('edit-crop-status-field'),
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
                        onChanged: _submitting || _requiresInspection
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _status = value);
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('edit-plant-count-field'),
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
                        key: const Key('edit-crop-notes-field'),
                        controller: _notes,
                        validator: (value) =>
                            _optionalLength(value, 10000, 'Notes'),
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_submitError != null) ...[
                        const SizedBox(height: 16),
                        Material(
                          key: const Key('edit-crop-cycle-submit-error'),
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_submitError!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_requiresInspection)
                        FilledButton.icon(
                          key: const Key('inspect-crop-cycle-button'),
                          onPressed: _returningForInspection
                              ? null
                              : _returnForInspection,
                          icon: const Icon(Icons.manage_search_outlined),
                          label: const Text('Return to Crop Cycle Details'),
                        )
                      else
                        FilledButton.icon(
                          key: const Key('save-crop-cycle-changes-button'),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _submitting ? 'Saving...' : 'Save Changes',
                          ),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('cancel-edit-crop-cycle-bottom-button'),
                        onPressed: _submitting || _requiresInspection
                            ? null
                            : _cancel,
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
      hintText: 'YYYY-MM-DD',
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: label,
        onPressed: _submitting || _requiresInspection
            ? null
            : () => _pickDate(controller),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
