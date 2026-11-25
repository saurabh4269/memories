//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AuthCodeExchangeDto {
  /// Returns a new [AuthCodeExchangeDto] instance.
  AuthCodeExchangeDto({
    required this.code,
    required this.codeVerifier,
  });

  /// One-time code
  String code;

  /// PKCE code verifier (base64url)
  String codeVerifier;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AuthCodeExchangeDto &&
    other.code == code &&
    other.codeVerifier == codeVerifier;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (code.hashCode) +
    (codeVerifier.hashCode);

  @override
  String toString() => 'AuthCodeExchangeDto[code=$code, codeVerifier=$codeVerifier]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'code'] = this.code;
      json[r'codeVerifier'] = this.codeVerifier;
    return json;
  }

  /// Returns a new [AuthCodeExchangeDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AuthCodeExchangeDto? fromJson(dynamic value) {
    upgradeDto(value, "AuthCodeExchangeDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return AuthCodeExchangeDto(
        code: mapValueOfType<String>(json, r'code')!,
        codeVerifier: mapValueOfType<String>(json, r'codeVerifier')!,
      );
    }
    return null;
  }

  static List<AuthCodeExchangeDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AuthCodeExchangeDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AuthCodeExchangeDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AuthCodeExchangeDto> mapFromJson(dynamic json) {
    final map = <String, AuthCodeExchangeDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AuthCodeExchangeDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AuthCodeExchangeDto-objects as value to a dart map
  static Map<String, List<AuthCodeExchangeDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AuthCodeExchangeDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AuthCodeExchangeDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
    'codeVerifier',
  };
}

