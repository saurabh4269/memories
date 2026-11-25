//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class StorageTemplatePresetDto {
  /// Returns a new [StorageTemplatePresetDto] instance.
  StorageTemplatePresetDto({
    required this.preview,
    required this.template,
  });

  /// Example path rendered from the preset
  String preview;

  /// Preset storage template
  String template;

  @override
  bool operator ==(Object other) => identical(this, other) || other is StorageTemplatePresetDto &&
    other.preview == preview &&
    other.template == template;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (preview.hashCode) +
    (template.hashCode);

  @override
  String toString() => 'StorageTemplatePresetDto[preview=$preview, template=$template]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'preview'] = this.preview;
      json[r'template'] = this.template;
    return json;
  }

  /// Returns a new [StorageTemplatePresetDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static StorageTemplatePresetDto? fromJson(dynamic value) {
    upgradeDto(value, "StorageTemplatePresetDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return StorageTemplatePresetDto(
        preview: mapValueOfType<String>(json, r'preview')!,
        template: mapValueOfType<String>(json, r'template')!,
      );
    }
    return null;
  }

  static List<StorageTemplatePresetDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StorageTemplatePresetDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StorageTemplatePresetDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, StorageTemplatePresetDto> mapFromJson(dynamic json) {
    final map = <String, StorageTemplatePresetDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = StorageTemplatePresetDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of StorageTemplatePresetDto-objects as value to a dart map
  static Map<String, List<StorageTemplatePresetDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<StorageTemplatePresetDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = StorageTemplatePresetDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'preview',
    'template',
  };
}

