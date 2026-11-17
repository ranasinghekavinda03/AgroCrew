/// Crop-cycle states accepted by the backend.
///
/// These values represent wire-format membership only. They do not impose
/// lifecycle transition rules in the Flutter client.
enum CropStatus {
  planned,
  active,
  harvested,
  cancelled;

  String get wireValue => name;

  static CropStatus fromWire(Object? value) => switch (value) {
    'planned' => CropStatus.planned,
    'active' => CropStatus.active,
    'harvested' => CropStatus.harvested,
    'cancelled' => CropStatus.cancelled,
    _ => throw const FormatException('Crop status is invalid.'),
  };
}

class CropCycle {
  const CropCycle({
    required this.id,
    required this.farmId,
    required this.cropType,
    required this.variety,
    required this.plantingDate,
    required this.expectedHarvestDate,
    required this.status,
    required this.plantCount,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int farmId;
  final String cropType;
  final String? variety;
  final DateTime plantingDate;
  final DateTime? expectedHarvestDate;
  final CropStatus status;
  final int? plantCount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CropCycle.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Crop cycle must be a JSON object.');
    }
    const requiredFields = {
      'id',
      'farm_id',
      'crop_type',
      'variety',
      'planting_date',
      'expected_harvest_date',
      'status',
      'plant_count',
      'notes',
      'created_at',
      'updated_at',
    };
    if (!requiredFields.every(value.containsKey)) {
      throw const FormatException('Crop cycle response is incomplete.');
    }

    final id = _positiveInteger(value['id'], 'id');
    final farmId = _positiveInteger(value['farm_id'], 'farm_id');
    final cropType = value['crop_type'];
    if (cropType is! String ||
        cropType.trim().isEmpty ||
        cropType.runes.length > 128) {
      throw const FormatException('crop_type is invalid.');
    }
    final variety = _nullableString(value['variety'], 'variety');
    if (variety != null &&
        (variety.trim().isEmpty || variety.runes.length > 128)) {
      throw const FormatException('variety is invalid.');
    }
    final plantingDate = _CropDateOnly.parse(
      value['planting_date'],
      'planting_date',
    );
    final expectedHarvestDate = value['expected_harvest_date'] == null
        ? null
        : _CropDateOnly.parse(
            value['expected_harvest_date'],
            'expected_harvest_date',
          );
    if (expectedHarvestDate != null &&
        expectedHarvestDate.isBefore(plantingDate)) {
      throw const FormatException('expected_harvest_date is invalid.');
    }
    final plantCount = value['plant_count'] == null
        ? null
        : _positiveInteger(value['plant_count'], 'plant_count');
    final notes = _nullableString(value['notes'], 'notes');
    if (notes != null && notes.runes.length > 10000) {
      throw const FormatException('notes is invalid.');
    }

    return CropCycle(
      id: id,
      farmId: farmId,
      cropType: cropType,
      variety: variety,
      plantingDate: plantingDate,
      expectedHarvestDate: expectedHarvestDate,
      status: CropStatus.fromWire(value['status']),
      plantCount: plantCount,
      notes: notes,
      createdAt: _timestamp(value['created_at'], 'created_at'),
      updatedAt: _timestamp(value['updated_at'], 'updated_at'),
    );
  }

  static int _positiveInteger(Object? value, String field) {
    // On JavaScript targets, a whole-valued double can also satisfy `is int`
    // after JSON decoding. Lexical `1` versus `1.0` information is no longer
    // available at this layer. The finite check is still required because
    // JavaScript targets can also report infinity as an int.
    if (value is int && value.isFinite && value > 0) return value;
    throw FormatException('$field is invalid.');
  }

  static String? _nullableString(Object? value, String field) {
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('$field is invalid.');
  }

  static DateTime _timestamp(Object? value, String field) {
    if (value is! String) throw FormatException('$field is invalid.');
    final match = _timestampPattern.firstMatch(value);
    if (match == null || match.start != 0 || match.end != value.length) {
      throw FormatException('$field is invalid.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    if (year < 1 ||
        year > 9999 ||
        !_isValidCalendarDate(year, month, day) ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw FormatException('$field is invalid.');
    }
    final offsetHour = match.group(8);
    final offsetMinute = match.group(9);
    if (offsetHour != null &&
        (int.parse(offsetHour) > 23 || int.parse(offsetMinute!) > 59)) {
      throw FormatException('$field is invalid.');
    }
    // SQLite test data can be timezone-naive while PostgreSQL/Pydantic emits
    // Z or an explicit offset. Naive server timestamps represent UTC here.
    final normalized = match.group(7) == null ? '${value}Z' : value;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) throw FormatException('$field is invalid.');
    return parsed.toUtc();
  }

  static final _timestampPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.\d{1,6})?(Z|[+-](\d{2}):(\d{2}))?$',
  );
}

class CropCycleCreate {
  const CropCycleCreate({
    required this.farmId,
    required this.cropType,
    this.variety,
    required this.plantingDate,
    this.expectedHarvestDate,
    this.status = CropStatus.planned,
    this.plantCount,
    this.notes,
  });

  final int farmId;
  final String cropType;
  final String? variety;
  final DateTime plantingDate;
  final DateTime? expectedHarvestDate;
  final CropStatus status;
  final int? plantCount;
  final String? notes;

  Map<String, Object?> toJson() => {
    'farm_id': farmId,
    'crop_type': cropType.trim(),
    if (variety != null) 'variety': _normalizeVariety(variety),
    'planting_date': _CropDateOnly.format(plantingDate),
    if (expectedHarvestDate != null)
      'expected_harvest_date': _CropDateOnly.format(expectedHarvestDate!),
    'status': status.wireValue,
    if (plantCount != null) 'plant_count': plantCount,
    if (notes != null) 'notes': notes,
  };
}

class CropCycleUpdate {
  const CropCycleUpdate({
    required this.cropType,
    required this.variety,
    required this.plantingDate,
    required this.expectedHarvestDate,
    required this.status,
    required this.plantCount,
    required this.notes,
  });

  final String cropType;
  final String? variety;
  final DateTime plantingDate;
  final DateTime? expectedHarvestDate;
  final CropStatus status;
  final int? plantCount;
  final String? notes;

  Map<String, Object?> toJson() => {
    'crop_type': cropType.trim(),
    'variety': _normalizeVariety(variety),
    'planting_date': _CropDateOnly.format(plantingDate),
    'expected_harvest_date': expectedHarvestDate == null
        ? null
        : _CropDateOnly.format(expectedHarvestDate!),
    'status': status.wireValue,
    'plant_count': plantCount,
    'notes': notes,
  };
}

String? _normalizeVariety(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// Converts calendar-only API values without applying timezone conversion.
///
/// Parsed dates use UTC midnight as a stable container, but only their year,
/// month, and day are meaningful. Serialization reads those components exactly
/// as supplied, whether the input [DateTime] is local or UTC.
abstract final class _CropDateOnly {
  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static DateTime parse(Object? value, String field) {
    if (value is! String || value.length != 10) {
      throw FormatException('$field is invalid.');
    }
    final match = _pattern.firstMatch(value);
    if (match == null || match.start != 0 || match.end != value.length) {
      throw FormatException('$field is invalid.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1 || year > 9999 || !_isValidCalendarDate(year, month, day)) {
      throw FormatException('$field is invalid.');
    }
    return DateTime.utc(year, month, day);
  }

  static String format(DateTime value) {
    if (value.year < 1 || value.year > 9999) {
      throw const FormatException('Calendar date is invalid.');
    }
    String pad(int component, int width) =>
        component.toString().padLeft(width, '0');
    return '${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)}';
  }
}

bool _isValidCalendarDate(int year, int month, int day) {
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}
