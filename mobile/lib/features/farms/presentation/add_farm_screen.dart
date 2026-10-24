import 'package:flutter/material.dart';

import '../data/farm_service.dart';
import '../data/models/farm.dart';

class AddFarmScreen extends StatefulWidget {
  const AddFarmScreen({super.key, required this.farmService});

  final FarmService farmService;

  @override
  State<AddFarmScreen> createState() => _AddFarmScreenState();
}

class _AddFarmScreenState extends State<AddFarmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _unit = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
  }

  void _nameChanged() => setState(() {});

  @override
  void dispose() {
    _name
      ..removeListener(_nameChanged)
      ..dispose();
    _area.dispose();
    _unit.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _name.text.trim().isNotEmpty;

  String? _requiredName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Farm name is required.';
    if (text.length > 255) return 'Farm name must be 255 characters or fewer.';
    return null;
  }

  String? _areaValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{1,10}(\.\d{1,4})?$').hasMatch(text)) {
      return 'Enter a positive area with up to 4 decimal places.';
    }
    final parsed = num.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return 'Area must be greater than zero.';
    }
    return null;
  }

  String? _coordinate(String? value, double min, double max, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed < min || parsed > max) {
      return '$label must be between $min and $max.';
    }
    final decimals = text.contains('.') ? text.split('.').last.length : 0;
    if (decimals > 6) return '$label can have at most 6 decimal places.';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _submitError = null;
    });
    final optionalUnit = _unit.text.trim();
    final optionalNotes = _notes.text.trim();
    try {
      final farm = await widget.farmService.createFarm(
        FarmCreate(
          name: _name.text,
          areaValue: _area.text.trim().isEmpty
              ? null
              : num.parse(_area.text.trim()),
          areaUnit: optionalUnit.isEmpty ? null : optionalUnit,
          latitude: _latitude.text.trim().isEmpty
              ? null
              : num.parse(_latitude.text.trim()),
          longitude: _longitude.text.trim().isEmpty
              ? null
              : num.parse(_longitude.text.trim()),
          notes: optionalNotes.isEmpty ? null : optionalNotes,
        ),
      );
      if (mounted) Navigator.of(context).pop(farm);
    } on FarmException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Farm')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter the details of your farming location.',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('farm-name-field'),
                      controller: _name,
                      maxLength: 255,
                      validator: _requiredName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Farm Name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('farm-area-field'),
                      controller: _area,
                      validator: _areaValidator,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Area (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('farm-area-unit-field'),
                      controller: _unit,
                      maxLength: 32,
                      validator: (value) {
                        if (value != null &&
                            value.isNotEmpty &&
                            value.trim().isEmpty) {
                          return 'Area unit cannot contain only spaces.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Area Unit (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('farm-latitude-field'),
                      controller: _latitude,
                      validator: (value) =>
                          _coordinate(value, -90, 90, 'Latitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitude (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('farm-longitude-field'),
                      controller: _longitude,
                      validator: (value) =>
                          _coordinate(value, -180, 180, 'Longitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('farm-notes-field'),
                      controller: _notes,
                      maxLength: 10000,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    if (_submitError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _submitError!,
                        key: const Key('farm-save-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('save-farm-button'),
                      onPressed: _canSave ? _save : null,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Farm'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
