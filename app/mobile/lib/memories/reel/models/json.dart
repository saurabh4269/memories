// Lenient JSON readers: the director API is being built concurrently, so every
// field is optional and numbers may arrive as int, double or numeric strings.

double? asDouble(Object? v) {
  if (v is num) {
    return v.toDouble();
  }
  if (v is String) {
    return double.tryParse(v.trim());
  }
  return null;
}

int? asInt(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.round();
  }
  if (v is String) {
    return int.tryParse(v.trim());
  }
  return null;
}

String? asString(Object? v) {
  if (v == null) {
    return null;
  }
  final s = v is String ? v : v.toString();
  return s.trim().isEmpty ? null : s;
}

Map<String, dynamic> asMap(Object? v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

List<Object?> asList(Object? v) => v is List ? v : const [];

List<String> asStringList(Object? v) => asList(v).map(asString).whereType<String>().toList(growable: false);
