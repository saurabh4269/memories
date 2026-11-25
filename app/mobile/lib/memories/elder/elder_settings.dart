import 'dart:convert';

/// Elder-mode presentation settings resolved from the `elder_mode` flag.
class ElderSettings {
  /// Whether elder mode is active for this member.
  final bool enabled;

  /// Text scale factor to apply (1.0 = system default).
  final double textScale;

  /// Prefer voice input/prompts over typing.
  final bool voiceFirst;

  /// Language for prompts/hints (e.g. `hi`, `en-IN`), if the flag sets one.
  final String? language;

  /// Sarvam TTS speaker to use for spoken prompts, if set.
  final String? ttsSpeaker;

  /// Show a simplified home screen.
  final bool simpleHome;

  const ElderSettings({
    this.enabled = false,
    this.textScale = 1.0,
    this.voiceFirst = false,
    this.language,
    this.ttsSpeaker,
    this.simpleHome = false,
  });

  static const off = ElderSettings();

  static const double minScale = 1.0;
  static const double maxScale = 2.0;

  /// Scale used for elders when the flag enables elder mode without a size.
  static const double defaultElderScale = 1.3;

  /// Offline fallback used for members who said "I am: elder".
  static ElderSettings fallbackFor({required String? role, String? language}) => role == 'elder'
      ? ElderSettings(enabled: true, textScale: defaultElderScale, voiceFirst: true, language: language)
      : ElderSettings(language: language);

  /// Parses a `GET /v1/members/flags` response.
  ///
  /// Accepts both `{flags: {elder_mode: {enabled, value}}}` (live server) and
  /// `{elder_mode: {enabled, value}}` (contract). `value` may be a map or a
  /// JSON string with any of: `text_scale`/`font_scale`, `large_text`,
  /// `voice_first`/`voice_prompts`, `prompt_hint_lang`/`ui_language`,
  /// `tts_speaker`, `simple_home`.
  static ElderSettings fromFlagsResponse(Object? json, {String? role, String? language}) {
    final root = json is Map ? json : const {};
    final flags = root['flags'] is Map ? root['flags'] as Map : root;
    final elder = flags['elder_mode'];
    if (elder is! Map) {
      return fallbackFor(role: role, language: language);
    }
    return fromFlag(enabled: elder['enabled'] == true, value: elder['value'], language: language);
  }

  static ElderSettings fromFlag({required bool enabled, Object? value, String? language}) {
    final v = _asMap(value);
    if (!enabled) {
      return ElderSettings(language: language);
    }
    var scale = _asDouble(v['text_scale']) ?? _asDouble(v['font_scale']);
    final largeText = v['large_text'] == true;
    if (largeText && (scale == null || scale <= 1.0)) {
      scale = defaultElderScale;
    }
    // Enabled with no size information at all -> sensible elder default.
    if (scale == null && !v.containsKey('large_text')) {
      scale = defaultElderScale;
    }
    final voice = _asBool(v['voice_first']) ?? _asBool(v['voice_prompts']) ?? false;
    final lang = _asString(v['prompt_hint_lang']) ?? _asString(v['ui_language']) ?? language;
    return ElderSettings(
      enabled: true,
      textScale: (scale ?? 1.0).clamp(minScale, maxScale),
      voiceFirst: voice,
      language: lang,
      ttsSpeaker: _asString(v['tts_speaker']),
      simpleHome: _asBool(v['simple_home']) ?? false,
    );
  }

  static Map _asMap(Object? value) {
    if (value is Map) {
      return value;
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        final d = jsonDecode(value);
        if (d is Map) {
          return d;
        }
      } catch (_) {}
    }
    return const {};
  }

  static double? _asDouble(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static bool? _asBool(Object? v) => switch (v) {
    final bool b => b,
    'true' => true,
    'false' => false,
    _ => null,
  };

  static String? _asString(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  @override
  bool operator ==(Object other) =>
      other is ElderSettings &&
      other.enabled == enabled &&
      other.textScale == textScale &&
      other.voiceFirst == voiceFirst &&
      other.language == language &&
      other.ttsSpeaker == ttsSpeaker &&
      other.simpleHome == simpleHome;

  @override
  int get hashCode => Object.hash(enabled, textScale, voiceFirst, language, ttsSpeaker, simpleHome);

  @override
  String toString() =>
      'ElderSettings(enabled: $enabled, textScale: $textScale, voiceFirst: $voiceFirst, language: $language, '
      'ttsSpeaker: $ttsSpeaker, simpleHome: $simpleHome)';
}
