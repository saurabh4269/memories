import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/elder/elder_settings.dart';
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/join/member_profile.dart';
import 'package:logging/logging.dart';

/// Resolves elder mode for the current member from
/// `GET /v1/members/flags?member=&language=&role=` (Flagsmith-backed on the
/// director). Falls back to role-based defaults when offline.
class ElderModeController extends AsyncNotifier<ElderSettings> {
  final _log = Logger('ElderMode');

  @override
  Future<ElderSettings> build() async {
    final profile = await ref.watch(memberProfileProvider.future);
    if (profile == null) {
      return ElderSettings.off;
    }
    final role = profile.role.wire;
    try {
      final json = await ref.read(directorClientProvider).getJson('/v1/members/flags', {
        'member': profile.identity,
        'language': profile.language,
        'role': role,
      });
      return ElderSettings.fromFlagsResponse(json, role: role, language: profile.language);
    } catch (e) {
      _log.warning('Could not load member flags, using defaults: $e');
      return ElderSettings.fallbackFor(role: role, language: profile.language);
    }
  }

  /// Re-fetch flags (e.g. on app resume or after a Flagsmith change).
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final elderModeProvider = AsyncNotifierProvider<ElderModeController, ElderSettings>(ElderModeController.new);

/// Synchronous view: last known settings (off while loading).
final elderSettingsProvider = Provider<ElderSettings>(
  (ref) => ref.watch(elderModeProvider).valueOrNull ?? ElderSettings.off,
);

final elderTextScaleProvider = Provider<double>((ref) => ref.watch(elderSettingsProvider).textScale);
final elderVoiceFirstProvider = Provider<bool>((ref) => ref.watch(elderSettingsProvider).voiceFirst);
final elderLanguageProvider = Provider<String?>((ref) => ref.watch(elderSettingsProvider).language);
