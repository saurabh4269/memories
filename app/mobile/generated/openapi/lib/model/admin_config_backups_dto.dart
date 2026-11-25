//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AdminConfigBackupsDto {
  /// Returns a new [AdminConfigBackupsDto] instance.
  AdminConfigBackupsDto({
    this.beta = const Optional.absent(),
    required this.database,
  });

  /// Whether the backups feature is enabled
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  Optional<bool?> beta;

  AdminConfigDatabaseBackupDto database;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AdminConfigBackupsDto &&
    other.beta == beta &&
    other.database == database;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (beta == null ? 0 : beta!.hashCode) +
    (database.hashCode);

  @override
  String toString() => 'AdminConfigBackupsDto[beta=$beta, database=$database]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.beta.isPresent) {
      final value = this.beta.value;
      json[r'beta'] = value;
    }
      json[r'database'] = this.database;
    return json;
  }

  /// Returns a new [AdminConfigBackupsDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AdminConfigBackupsDto? fromJson(dynamic value) {
    upgradeDto(value, "AdminConfigBackupsDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return AdminConfigBackupsDto(
        beta: json.containsKey(r'beta') ? Optional.present(mapValueOfType<bool>(json, r'beta')) : const Optional.absent(),
        database: AdminConfigDatabaseBackupDto.fromJson(json[r'database'])!,
      );
    }
    return null;
  }

  static List<AdminConfigBackupsDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AdminConfigBackupsDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AdminConfigBackupsDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AdminConfigBackupsDto> mapFromJson(dynamic json) {
    final map = <String, AdminConfigBackupsDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AdminConfigBackupsDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AdminConfigBackupsDto-objects as value to a dart map
  static Map<String, List<AdminConfigBackupsDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AdminConfigBackupsDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AdminConfigBackupsDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'database',
  };
}

