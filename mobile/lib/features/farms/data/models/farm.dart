class Farm {
  const Farm({
    required this.id,
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.areaValue,
    required this.areaUnit,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final String name;
  final num? latitude;
  final num? longitude;
  final num? areaValue;
  final String? areaUnit;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Farm.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Farm must be a JSON object.');
    }
    final id = value['id'];
    final userId = value['user_id'];
    final name = value['name'];
    final createdAt = _timestamp(value['created_at'], 'created_at');
    final updatedAt = _timestamp(value['updated_at'], 'updated_at');
    if (id is! int || id <= 0 || userId is! int || userId <= 0) {
      throw const FormatException('Farm IDs are invalid.');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Farm name is invalid.');
    }
    return Farm(
      id: id,
      userId: userId,
      name: name,
      latitude: _nullableNumber(value['latitude'], 'latitude'),
      longitude: _nullableNumber(value['longitude'], 'longitude'),
      areaValue: _nullableNumber(value['area_value'], 'area_value'),
      areaUnit: _nullableString(value['area_unit'], 'area_unit'),
      notes: _nullableString(value['notes'], 'notes'),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static num? _nullableNumber(Object? value, String field) {
    if (value == null) return null;
    if (value is num && value.isFinite) return value;
    throw FormatException('$field is invalid.');
  }

  static String? _nullableString(Object? value, String field) {
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('$field is invalid.');
  }

  static DateTime _timestamp(Object? value, String field) {
    if (value is! String) throw FormatException('$field is invalid.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$field is invalid.');
    return parsed.toUtc();
  }
}

class FarmCreate {
  const FarmCreate({
    required this.name,
    this.latitude,
    this.longitude,
    this.areaValue,
    this.areaUnit,
    this.notes,
  });

  final String name;
  final num? latitude;
  final num? longitude;
  final num? areaValue;
  final String? areaUnit;
  final String? notes;

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (areaValue != null) 'area_value': areaValue,
    if (areaUnit != null) 'area_unit': areaUnit!.trim(),
    if (notes != null) 'notes': notes,
  };
}
