//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

/// Email template name
enum EmailTemplate {
  test._(r'test'),
  welcome._(r'welcome'),
  resetPassword._(r'reset-password'),
  albumInvite._(r'album-invite'),
  albumUpdate._(r'album-update'),
  ;

  /// Instantiate a new enum with the provided value.
  const EmailTemplate._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [EmailTemplate] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static EmailTemplate? fromJson(dynamic value) => EmailTemplateTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [EmailTemplate]
  /// that were successfully decoded from the passed [JSON][json].
  static List<EmailTemplate> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailTemplate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailTemplate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [EmailTemplate] to String,
/// and [decode] dynamic data back to [EmailTemplate].
class EmailTemplateTypeTransformer {
  factory EmailTemplateTypeTransformer() => _instance ??= const EmailTemplateTypeTransformer._();

  const EmailTemplateTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(EmailTemplate data) => data._value;

  /// Returns the instance of [EmailTemplate] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  EmailTemplate? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailTemplate) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'test': return EmailTemplate.test;
        case r'welcome': return EmailTemplate.welcome;
        case r'reset-password': return EmailTemplate.resetPassword;
        case r'album-invite': return EmailTemplate.albumInvite;
        case r'album-update': return EmailTemplate.albumUpdate;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static EmailTemplateTypeTransformer? _instance;
}

