import 'dart:convert';

import 'package:agrocrew/features/crops/data/models/crop_cycle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final verifier = _CropCycleWebVerifier();
  late final String result;
  try {
    verifier.verify();
    result = 'STEP27B2_CROP_CYCLE_WEB_PASS_${verifier.summary}';
  } on Object catch (error) {
    result = 'STEP27B2_CROP_CYCLE_WEB_FAIL_${error.runtimeType}';
  }
  debugPrint(result);
  runApp(_VerificationApp(result: result));
}

class _VerificationApp extends StatelessWidget {
  const _VerificationApp({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: result,
    home: Title(
      title: result,
      color: Colors.white,
      child: Scaffold(body: Center(child: SelectableText(result))),
    ),
  );
}

class _CropCycleWebVerifier {
  final Map<String, int> _counts = {
    'runtime': 0,
    'numeric': 0,
    'unicode': 0,
    'date': 0,
    'timestamp': 0,
    'payload': 0,
  };

  String get summary => _counts.entries
      .map((entry) => '${entry.key.toUpperCase()}_${entry.value}')
      .join('_');

  final Map<String, Object?> _complete = {
    'id': 34,
    'farm_id': 12,
    'crop_type': 'Tomato',
    'variety': 'Roma',
    'planting_date': '2026-11-17',
    'expected_harvest_date': '2027-02-15',
    'status': 'active',
    'plant_count': 120,
    'notes': 'North field',
    'created_at': '2026-11-17T10:30:00Z',
    'updated_at': '2026-11-18T11:45:00+00:00',
  };

  void verify() {
    _check('runtime', kIsWeb, 'kIsWeb must be true');
    _verifyNumericValidation();
    _verifyUnicodeValidation();
    _verifyCalendarDates();
    _verifyTimestamps();
    _verifyPayloads();
  }

  void _verifyNumericValidation() {
    final decodedInteger = jsonDecode('{"id":1}') as Map<String, dynamic>;
    final decodedDecimal = jsonDecode('{"id":1.0}') as Map<String, dynamic>;
    final decodedFraction = jsonDecode('{"id":1.5}') as Map<String, dynamic>;
    _check('numeric', decodedInteger['id'] is int, 'JSON integer type');
    _check('numeric', decodedDecimal['id'] is int, 'JSON decimal Web type');
    _check(
      'numeric',
      CropCycle.fromJson({..._complete, 'id': decodedInteger['id']}).id == 1,
      'positive JSON integer',
    );
    _check(
      'numeric',
      CropCycle.fromJson({..._complete, 'id': decodedDecimal['id']}).id == 1,
      'whole-valued JSON decimal',
    );
    _check(
      'numeric',
      CropCycle.fromJson({..._complete, 'plant_count': 12}).plantCount == 12,
      'positive plant count',
    );
    _throws('numeric', {'id': 0}, 'zero');
    _throws('numeric', {'id': -1}, 'negative');
    _throws('numeric', {'id': decodedFraction['id']}, 'fraction');
    _throws('numeric', {'id': '1'}, 'numeric string');
    _throws('numeric', {'id': true}, 'boolean');
    _throws('numeric', {'id': double.nan}, 'NaN');
    _throws('numeric', {'id': double.infinity}, 'infinity');
    _throws('numeric', {'id': double.negativeInfinity}, 'negative infinity');
  }

  void _verifyUnicodeValidation() {
    const plant = '\u{1F331}';
    final crop = CropCycle.fromJson({
      ..._complete,
      'crop_type': 'c' * 128,
      'variety': _repeat(plant, 128),
      'notes': _repeat(plant, 10000),
    });
    _check('unicode', crop.cropType.runes.length == 128, 'ASCII boundary');
    _check('unicode', crop.variety!.runes.length == 128, 'emoji boundary');
    _check('unicode', crop.variety!.length == 256, 'UTF-16 distinction');
    _check('unicode', crop.notes!.runes.length == 10000, 'notes boundary');
    _throws('unicode', {'crop_type': 'c' * 129}, 'ASCII overflow');
    _throws('unicode', {'variety': _repeat(plant, 129)}, 'emoji overflow');
    _throws('unicode', {'notes': _repeat(plant, 10001)}, 'notes overflow');
    final multilingual = CropCycle.fromJson({
      ..._complete,
      'crop_type': 'තක්කාලි',
      'variety': 'දේශීය',
      'notes': 'සිංහල தமிழ் English',
    });
    _check('unicode', multilingual.variety == 'දේශීය', 'multilingual text');
    final nullable = CropCycle.fromJson({
      ..._complete,
      'variety': null,
      'notes': null,
    });
    _check(
      'unicode',
      nullable.variety == null && nullable.notes == null,
      'nullable text',
    );
  }

  void _verifyCalendarDates() {
    final leap = CropCycle.fromJson({
      ..._complete,
      'planting_date': '2024-02-29',
    });
    _check(
      'date',
      leap.plantingDate == DateTime.utc(2024, 2, 29),
      'valid leap day',
    );
    for (final invalid in [
      '2023-02-29',
      '2026-02-30',
      ' 2026-11-17',
      '2026-11-17\n',
      '2026-11-17x',
    ]) {
      _throws('date', {'planting_date': invalid}, 'invalid date $invalid');
    }
    final roundTrip = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: leap.plantingDate,
    ).toJson();
    _check('date', roundTrip['planting_date'] == '2024-02-29', 'round trip');
    _check(
      'date',
      CropCycleCreate(
            farmId: 1,
            cropType: 'Tea',
            plantingDate: DateTime(2026, 1, 2, 23, 59),
          ).toJson()['planting_date'] ==
          '2026-01-02',
      'no timezone shift',
    );
    _check(
      'date',
      CropCycleCreate(
            farmId: 1,
            cropType: 'Tea',
            plantingDate: DateTime.utc(1, 1, 1),
          ).toJson()['planting_date'] ==
          '0001-01-01',
      'minimum year',
    );
    _check(
      'date',
      CropCycleCreate(
            farmId: 1,
            cropType: 'Tea',
            plantingDate: DateTime.utc(9999, 12, 31),
          ).toJson()['planting_date'] ==
          '9999-12-31',
      'maximum year',
    );
  }

  void _verifyTimestamps() {
    final utc = CropCycle.fromJson({
      ..._complete,
      'created_at': '2026-11-17T10:30:12.345678Z',
    });
    _check(
      'timestamp',
      utc.createdAt == DateTime.utc(2026, 11, 17, 10, 30, 12, 345, 678),
      'UTC microseconds',
    );
    final offset = CropCycle.fromJson({
      ..._complete,
      'created_at': '2026-11-17T10:30:12.5+05:30',
    });
    _check(
      'timestamp',
      offset.createdAt == DateTime.utc(2026, 11, 17, 5, 0, 12, 500),
      'offset normalization',
    );
    final naive = CropCycle.fromJson({
      ..._complete,
      'created_at': '2026-11-17T10:30:12',
    });
    _check(
      'timestamp',
      naive.createdAt == DateTime.utc(2026, 11, 17, 10, 30, 12),
      'SQLite naive timestamp',
    );
    for (final invalid in [
      '2026-11-17',
      '2026-02-30T10:30:00Z',
      '2026-11-17T24:00:00Z',
      '2026-11-17T10:60:00Z',
      '2026-11-17T10:30:60Z',
      '2026-11-17T10:30:00+24:00',
    ]) {
      _throws('timestamp', {
        'created_at': invalid,
      }, 'invalid timestamp $invalid');
    }
  }

  void _verifyPayloads() {
    final create = CropCycleCreate(
      farmId: 12,
      cropType: ' Tomato ',
      plantingDate: DateTime.utc(2026, 11, 17),
    ).toJson();
    _check('payload', create['status'] == 'planned', 'default status');
    _check(
      'payload',
      create.keys.join(',') == 'farm_id,crop_type,planting_date,status',
      'create field names and omissions',
    );
    _check('payload', create['crop_type'] == 'Tomato', 'normalization');
    final update = CropCycleUpdate(
      cropType: 'Rice',
      variety: null,
      plantingDate: DateTime.utc(2026, 7, 1),
      expectedHarvestDate: null,
      status: CropStatus.active,
      plantCount: null,
      notes: null,
    ).toJson();
    _check(
      'payload',
      update['variety'] == null &&
          update['expected_harvest_date'] == null &&
          update['plant_count'] == null &&
          update['notes'] == null,
      'explicit update nulls',
    );
    _check('payload', update['status'] == 'active', 'required update status');
    _check('payload', !update.containsKey('farm_id'), 'no farm reassignment');
    _check(
      'payload',
      !update.containsKey('user_id') &&
          !update.containsKey('id') &&
          !update.containsKey('created_at') &&
          !update.containsKey('updated_at'),
      'no owner or generated fields',
    );
  }

  void _throws(String category, Map<String, Object?> replacement, String name) {
    var threw = false;
    try {
      CropCycle.fromJson({..._complete, ...replacement});
    } on FormatException {
      threw = true;
    }
    _check(category, threw, name);
  }

  void _check(String category, bool condition, String name) {
    if (!condition) throw StateError('$category: $name');
    _counts[category] = _counts[category]! + 1;
  }
}

String _repeat(String value, int count) => List.filled(count, value).join();
