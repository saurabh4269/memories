import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/elder/elder_settings.dart';

void main() {
  group('ElderSettings.fromFlagsResponse', () {
    test('live server shape (nested under flags, font_scale/voice_prompts/ui_language)', () {
      final s = ElderSettings.fromFlagsResponse({
        'member': 'm1',
        'flags': {
          'elder_mode': {
            'enabled': true,
            'value': {
              'large_text': true,
              'font_scale': 1.4,
              'voice_prompts': true,
              'ui_language': 'hi-IN',
              'simple_home': true,
            },
          },
        },
      });
      expect(s.enabled, isTrue);
      expect(s.textScale, 1.4);
      expect(s.voiceFirst, isTrue);
      expect(s.language, 'hi-IN');
      expect(s.simpleHome, isTrue);
    });

    test('contract shape (top-level elder_mode, text_scale/voice_first/prompt_hint_lang/tts_speaker)', () {
      final s = ElderSettings.fromFlagsResponse({
        'elder_mode': {
          'enabled': true,
          'value': {'text_scale': 1.6, 'voice_first': true, 'prompt_hint_lang': 'ta', 'tts_speaker': 'anushka'},
        },
      });
      expect(
        s,
        const ElderSettings(enabled: true, textScale: 1.6, voiceFirst: true, language: 'ta', ttsSpeaker: 'anushka'),
      );
    });

    test('value as JSON string', () {
      final s = ElderSettings.fromFlagsResponse({
        'flags': {
          'elder_mode': {'enabled': true, 'value': '{"text_scale": "1.5", "voice_first": "true"}'},
        },
      });
      expect(s.textScale, 1.5);
      expect(s.voiceFirst, isTrue);
    });

    test('large_text without a scale uses the elder default', () {
      final s = ElderSettings.fromFlagsResponse({
        'elder_mode': {
          'enabled': true,
          'value': {'large_text': true, 'font_scale': 1.0},
        },
      });
      expect(s.textScale, ElderSettings.defaultElderScale);
    });

    test('enabled with large_text=false keeps 1.0', () {
      final s = ElderSettings.fromFlagsResponse({
        'flags': {
          'elder_mode': {
            'enabled': true,
            'value': {'large_text': false, 'font_scale': 1.0, 'voice_prompts': false},
          },
        },
      });
      expect(s.enabled, isTrue);
      expect(s.textScale, 1.0);
      expect(s.voiceFirst, isFalse);
    });

    test('enabled with null value uses elder defaults', () {
      final s = ElderSettings.fromFlagsResponse({
        'elder_mode': {'enabled': true, 'value': null},
      });
      expect(s.enabled, isTrue);
      expect(s.textScale, ElderSettings.defaultElderScale);
    });

    test('disabled flag turns elder mode off but keeps profile language', () {
      final s = ElderSettings.fromFlagsResponse({
        'elder_mode': {
          'enabled': false,
          'value': {'text_scale': 1.8},
        },
      }, language: 'bn');
      expect(s.enabled, isFalse);
      expect(s.textScale, 1.0);
      expect(s.language, 'bn');
    });

    test('scale is clamped to [1, 2]', () {
      expect(ElderSettings.fromFlag(enabled: true, value: {'text_scale': 5}).textScale, ElderSettings.maxScale);
      expect(ElderSettings.fromFlag(enabled: true, value: {'text_scale': 0.5}).textScale, ElderSettings.minScale);
    });

    test('missing elder_mode falls back by role', () {
      final elder = ElderSettings.fromFlagsResponse({'flags': {}}, role: 'elder', language: 'mr');
      expect(elder.enabled, isTrue);
      expect(elder.voiceFirst, isTrue);
      expect(elder.language, 'mr');
      expect(ElderSettings.fromFlagsResponse(null, role: 'kid').enabled, isFalse);
    });
  });
}
