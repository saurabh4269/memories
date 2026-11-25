//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AuthCodeResponseDto {
  /// Returns a new [AuthCodeResponseDto] instance.
  AuthCodeResponseDto({
    required this.code,
  });

  /// One-time code
  String code;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AuthCodeResponseDto &&
    other.code == code;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (code.hashCode);

  @override
  String toString() => 'AuthCodeResponseDto[code=$code]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'code'] = this.code;
    return json;
  }

  /// Returns a new [AuthCodeResponseDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AuthCodeResponseDto? fromJson(dynamic value) {
    upgradeDto(value, "AuthCodeResponseDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return AuthCodeResponseDto(
        code: mapValueOfType<String>(json, r'code')!,
      );
    }
    return null;
  }

  static List<AuthCodeResponseDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AuthCodeResponseDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AuthCodeResponseDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AuthCodeResponseDto> mapFromJson(dynamic json) {
    final map = <String, AuthCodeResponseDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AuthCodeResponseDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AuthCodeResponseDto-objects as value to a dart map
  static Map<String, List<AuthCodeResponseDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AuthCodeResponseDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AuthCodeResponseDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
  };
}

