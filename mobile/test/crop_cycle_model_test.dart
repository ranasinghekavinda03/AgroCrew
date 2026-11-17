import 'package:agrocrew/features/crops/data/models/crop_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final complete = <String, Object?>{
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

  test('parses all eleven fields in a complete backend response', () {
    final crop = CropCycle.fromJson(complete);
    expect(crop.id, 34);
    expect(crop.farmId, 12);
    expect(crop.cropType, 'Tomato');
    expect(crop.variety, 'Roma');
    expect(crop.plantingDate, DateTime.utc(2026, 11, 17));
    expect(crop.expectedHarvestDate, DateTime.utc(2027, 2, 15));
    expect(crop.status, CropStatus.active);
    expect(crop.plantCount, 120);
    expect(crop.notes, 'North field');
    expect(crop.createdAt, DateTime.utc(2026, 11, 17, 10, 30));
    expect(crop.updatedAt, DateTime.utc(2026, 11, 18, 11, 45));
  });

  test('preserves every nullable response field as null', () {
    final crop = CropCycle.fromJson({
      ...complete,
      'variety': null,
      'expected_harvest_date': null,
      'plant_count': null,
      'notes': null,
    });
    expect(crop.variety, isNull);
    expect(crop.expectedHarvestDate, isNull);
    expect(crop.plantCount, isNull);
    expect(crop.notes, isNull);
  });

  for (final status in CropStatus.values) {
    test('deserializes and serializes ${status.name}', () {
      final crop = CropCycle.fromJson({...complete, 'status': status.name});
      expect(crop.status, status);
      expect(status.wireValue, status.name);
    });
  }

  test('rejects unsupported status values instead of defaulting', () {
    expect(
      () => CropCycle.fromJson({...complete, 'status': 'growing'}),
      throwsFormatException,
    );
  });

  test('rejects non-object crop cycle responses', () {
    for (final value in <Object?>[null, <Object?>[], 'crop', 12]) {
      expect(() => CropCycle.fromJson(value), throwsFormatException);
    }
  });

  for (final field in complete.keys) {
    test('rejects response missing required field $field', () {
      final incomplete = Map<String, Object?>.from(complete)..remove(field);
      expect(() => CropCycle.fromJson(incomplete), throwsFormatException);
    });
  }

  for (final invalid in [
    <String, Object?>{'id': 0},
    <String, Object?>{'id': 1.0},
    <String, Object?>{'farm_id': -1},
    <String, Object?>{'farm_id': '12'},
    <String, Object?>{'crop_type': '   '},
    <String, Object?>{'crop_type': 'x' * 129},
    <String, Object?>{'variety': 10},
    <String, Object?>{'variety': ''},
    <String, Object?>{'plant_count': 0},
    <String, Object?>{'plant_count': -1},
    <String, Object?>{'plant_count': 12.0},
    <String, Object?>{'notes': 42},
    <String, Object?>{'notes': 'x' * 10001},
    <String, Object?>{'created_at': 'not-a-timestamp'},
    <String, Object?>{'updated_at': 123},
  ]) {
    test('rejects malformed response field ${invalid.keys.single}', () {
      expect(
        () => CropCycle.fromJson({...complete, ...invalid}),
        throwsFormatException,
      );
    });
  }

  test('rejects an expected harvest date before planting', () {
    expect(
      () => CropCycle.fromJson({
        ...complete,
        'expected_harvest_date': '2026-11-16',
      }),
      throwsFormatException,
    );
  });

  test('ignores unexpected response fields like the existing Farm model', () {
    final crop = CropCycle.fromJson({...complete, 'future_field': true});
    expect(crop.id, 34);
  });

  test('parses a standard date-only value at UTC midnight', () {
    final crop = CropCycle.fromJson(complete);
    expect(crop.plantingDate, DateTime.utc(2026, 11, 17));
    expect(crop.plantingDate.isUtc, isTrue);
  });

  test('serializes date components with zero padding', () {
    final request = CropCycleCreate(
      farmId: 12,
      cropType: 'Rice',
      plantingDate: DateTime.utc(6, 2, 3),
    );
    expect(request.toJson()['planting_date'], '0006-02-03');
  });

  test('accepts a valid leap-year date', () {
    final crop = CropCycle.fromJson({
      ...complete,
      'planting_date': '2024-02-29',
    });
    expect(crop.plantingDate, DateTime.utc(2024, 2, 29));
  });

  for (final invalidDate in [
    '2023-02-29',
    '2026-00-10',
    '2026-13-10',
    '2026-01-00',
    '2026-01-32',
    '2026-02-30',
    '2026-11-17T00:00:00Z',
    '17-11-2026',
    '2026-1-2',
    '0000-01-01',
  ]) {
    test('rejects invalid date-only value $invalidDate', () {
      expect(
        () => CropCycle.fromJson({...complete, 'planting_date': invalidDate}),
        throwsFormatException,
      );
    });
  }

  test('rejects an invalid optional expected harvest date', () {
    expect(
      () => CropCycle.fromJson({
        ...complete,
        'expected_harvest_date': '2027-02-29',
      }),
      throwsFormatException,
    );
  });

  test('preserves a calendar date through parse and serialization', () {
    final crop = CropCycle.fromJson(complete);
    final payload = CropCycleCreate(
      farmId: crop.farmId,
      cropType: crop.cropType,
      plantingDate: crop.plantingDate,
    ).toJson();
    expect(payload['planting_date'], complete['planting_date']);
  });

  test('does not shift local or UTC DateTime calendar components', () {
    final localRequest = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: DateTime(2026, 1, 2, 23, 59),
    );
    final utcRequest = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: DateTime.utc(2026, 1, 2, 0, 1),
    );
    expect(localRequest.toJson()['planting_date'], '2026-01-02');
    expect(utcRequest.toJson()['planting_date'], '2026-01-02');
  });

  test('supports backend calendar year boundaries', () {
    final earliest = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: DateTime.utc(1, 1, 1),
    );
    final latest = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: DateTime.utc(9999, 12, 31),
    );
    expect(earliest.toJson()['planting_date'], '0001-01-01');
    expect(latest.toJson()['planting_date'], '9999-12-31');
  });

  test('rejects serialization outside backend calendar year boundaries', () {
    final request = CropCycleCreate(
      farmId: 1,
      cropType: 'Tea',
      plantingDate: DateTime.utc(10000, 1, 1),
    );
    expect(request.toJson, throwsFormatException);
  });

  test('create payload has minimum fields and planned status by default', () {
    final request = CropCycleCreate(
      farmId: 12,
      cropType: '  Tomato  ',
      plantingDate: DateTime.utc(2026, 11, 17),
    );
    expect(request.toJson(), {
      'farm_id': 12,
      'crop_type': 'Tomato',
      'planting_date': '2026-11-17',
      'status': 'planned',
    });
  });

  for (final status in CropStatus.values) {
    test('create payload writes ${status.name} status exactly', () {
      final request = CropCycleCreate(
        farmId: 12,
        cropType: 'Tomato',
        plantingDate: DateTime.utc(2026, 11, 17),
        status: status,
      );
      expect(request.toJson()['status'], status.name);
    });
  }

  test('create payload serializes every optional field', () {
    final request = CropCycleCreate(
      farmId: 12,
      cropType: '  Tomato ',
      variety: ' Roma ',
      plantingDate: DateTime.utc(2026, 11, 17),
      expectedHarvestDate: DateTime.utc(2027, 2, 15),
      status: CropStatus.harvested,
      plantCount: 120,
      notes: 'North field',
    );
    expect(request.toJson(), {
      'farm_id': 12,
      'crop_type': 'Tomato',
      'variety': 'Roma',
      'planting_date': '2026-11-17',
      'expected_harvest_date': '2027-02-15',
      'status': 'harvested',
      'plant_count': 120,
      'notes': 'North field',
    });
  });

  test('create payload omits absent nullable fields and generated fields', () {
    final request = CropCycleCreate(
      farmId: 12,
      cropType: 'Tomato',
      plantingDate: DateTime.utc(2026, 11, 17),
    );
    final json = request.toJson();
    for (final field in [
      'variety',
      'expected_harvest_date',
      'plant_count',
      'notes',
      'id',
      'user_id',
      'created_at',
      'updated_at',
    ]) {
      expect(json, isNot(contains(field)));
    }
  });

  test('create payload normalizes a blank provided variety to null', () {
    final request = CropCycleCreate(
      farmId: 12,
      cropType: 'Tomato',
      variety: '   ',
      plantingDate: DateTime.utc(2026, 11, 17),
    );
    expect(request.toJson()['variety'], isNull);
  });

  test('update payload is a complete replacement with explicit nulls', () {
    final request = CropCycleUpdate(
      cropType: '  Tomato ',
      variety: null,
      plantingDate: DateTime.utc(2026, 11, 18),
      expectedHarvestDate: null,
      status: CropStatus.active,
      plantCount: null,
      notes: null,
    );
    expect(request.toJson(), {
      'crop_type': 'Tomato',
      'variety': null,
      'planting_date': '2026-11-18',
      'expected_harvest_date': null,
      'status': 'active',
      'plant_count': null,
      'notes': null,
    });
  });

  test('update payload serializes non-null optional values', () {
    final request = CropCycleUpdate(
      cropType: 'Rice',
      variety: ' Basmati ',
      plantingDate: DateTime.utc(2026, 7, 1),
      expectedHarvestDate: DateTime.utc(2026, 11, 9),
      status: CropStatus.cancelled,
      plantCount: 80,
      notes: 'Replacement values',
    );
    expect(request.toJson(), {
      'crop_type': 'Rice',
      'variety': 'Basmati',
      'planting_date': '2026-07-01',
      'expected_harvest_date': '2026-11-09',
      'status': 'cancelled',
      'plant_count': 80,
      'notes': 'Replacement values',
    });
  });

  test('update payload never contains farm, owner, or generated fields', () {
    final request = CropCycleUpdate(
      cropType: 'Rice',
      variety: null,
      plantingDate: DateTime.utc(2026, 7, 1),
      expectedHarvestDate: null,
      status: CropStatus.planned,
      plantCount: null,
      notes: null,
    );
    final json = request.toJson();
    for (final field in [
      'farm_id',
      'user_id',
      'id',
      'created_at',
      'updated_at',
    ]) {
      expect(json, isNot(contains(field)));
    }
  });
}
