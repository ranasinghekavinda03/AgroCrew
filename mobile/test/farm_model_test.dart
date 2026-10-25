import 'package:agrocrew/features/farms/data/models/farm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final complete = <String, Object?>{
    'id': 11,
    'user_id': 7,
    'name': 'Green Valley Farm',
    'latitude': 6.927079,
    'longitude': 79.861244,
    'area_value': 2.5,
    'area_unit': 'acres',
    'notes': 'Near the river',
    'created_at': '2026-10-24T10:30:00Z',
    'updated_at': '2026-10-24T11:45:00+00:00',
  };

  test('parses a complete backend farm response', () {
    final farm = Farm.fromJson(complete);
    expect(farm.id, 11);
    expect(farm.userId, 7);
    expect(farm.name, 'Green Valley Farm');
    expect(farm.areaValue, 2.5);
    expect(farm.createdAt, DateTime.utc(2026, 10, 24, 10, 30));
    expect(farm.updatedAt.isUtc, isTrue);
  });

  test('supports a farm containing only required values', () {
    final farm = Farm.fromJson({
      ...complete,
      'latitude': null,
      'longitude': null,
      'area_value': null,
      'area_unit': null,
      'notes': null,
    });
    expect(farm.latitude, isNull);
    expect(farm.areaValue, isNull);
    expect(farm.notes, isNull);
  });

  test('preserves integer and fractional numeric JSON values', () {
    expect(Farm.fromJson({...complete, 'area_value': 12}).areaValue, 12);
    expect(
      Farm.fromJson({...complete, 'area_value': 12.3456}).areaValue,
      12.3456,
    );
  });

  for (final invalid in [
    <String, Object?>{'id': 0},
    <String, Object?>{'user_id': '7'},
    <String, Object?>{'name': '   '},
    <String, Object?>{'latitude': '6.9'},
    <String, Object?>{'created_at': 'not-a-date'},
  ]) {
    test('rejects malformed field ${invalid.keys.single}', () {
      expect(
        () => Farm.fromJson({...complete, ...invalid}),
        throwsFormatException,
      );
    });
  }

  test('rejects non-object farm responses', () {
    expect(() => Farm.fromJson(<Object?>[]), throwsFormatException);
  });

  test('create payload never contains user_id and omits absent values', () {
    const request = FarmCreate(
      name: '  Hill Farm  ',
      areaValue: 3,
      areaUnit: ' acres ',
    );
    expect(request.toJson(), {
      'name': 'Hill Farm',
      'area_value': 3,
      'area_unit': 'acres',
    });
    expect(request.toJson(), isNot(contains('user_id')));
  });

  test('update payload is a complete replacement with explicit nulls', () {
    const request = FarmUpdate(
      name: '  Hill Farm  ',
      latitude: null,
      longitude: 79.8,
      areaValue: null,
      areaUnit: null,
      notes: null,
    );
    expect(request.toJson(), {
      'name': 'Hill Farm',
      'latitude': null,
      'longitude': 79.8,
      'area_value': null,
      'area_unit': null,
      'notes': null,
    });
    expect(request.toJson(), isNot(contains('user_id')));
    expect(request.toJson(), isNot(contains('created_at')));
  });
}
