//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AuthCodeCreateDto {
  /// Returns a new [AuthCodeCreateDto] instance.
  AuthCodeCreateDto({
    required this.codeChallenge,
  });

  /// PKCE code challenge (S256, base64url)
  String codeChallenge;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AuthCodeCreateDto &&
    other.codeChallenge == codeChallenge;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (codeChallenge.hashCode);

  @override
  String toString() => 'AuthCodeCreateDto[codeChallenge=$codeChallenge]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'codeChallenge'] = this.codeChallenge;
    return json;
  }

  /// Returns a new [AuthCodeCreateDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AuthCodeCreateDto? fromJson(dynamic value) {
    upgradeDto(value, "AuthCodeCreateDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return AuthCodeCreateDto(
        codeChallenge: mapValueOfType<String>(json, r'codeChallenge')!,
      );
    }
    return null;
  }

  static List<AuthCodeCreateDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AuthCodeCreateDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AuthCodeCreateDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AuthCodeCreateDto> mapFromJson(dynamic json) {
    final map = <String, AuthCodeCreateDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AuthCodeCreateDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AuthCodeCreateDto-objects as value to a dart map
  static Map<String, List<AuthCodeCreateDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AuthCodeCreateDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AuthCodeCreateDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'codeChallenge',
  };
}

