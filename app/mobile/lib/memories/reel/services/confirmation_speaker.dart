import 'dart:async';

import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/services/reel_api.dart';
import 'package:logging/logging.dart';
import 'package:video_player/video_player.dart';

/// Speaks "aapki reel taiyaar hai" (from `POST /v1/extras/confirmation`) when a
/// reel is ready. Audio URLs are cached per language/name, so repeat calls play
/// instantly. Never throws: a failure is logged and the call returns `false`.
///
/// ```dart
/// final speaker = ConfirmationSpeaker(api);
/// await speaker.prefetch(language: 'hi-IN', name: 'Dadi'); // while rendering
/// await speaker.speak(language: 'hi-IN', name: 'Dadi');    // when ready
/// ```
class ConfirmationSpeaker {
  ConfirmationSpeaker(this._api);

  final ReelApi _api;
  final Map<String, Future<String>> _urls = {};
  VideoPlayerController? _player;
  final Logger _log = Logger('MemoriesConfirmationSpeaker');

  Future<String> _url(String language, String? name) {
    final key = '$language|${name ?? ''}';
    return _urls.putIfAbsent(key, () async {
      try {
        return await _api.confirmationAudioUrl(language: language, name: name);
      } catch (_) {
        _urls.removeWhere((k, _) => k == key); // Don't cache failures.
        rethrow;
      }
    });
  }

  /// Fetches (and caches) the confirmation audio URL ahead of time.
  Future<void> prefetch({String language = kReelDefaultLanguage, String? name}) async {
    try {
      await _url(language, name);
    } catch (e) {
      _log.fine('prefetch failed: $e');
    }
  }

  /// Plays the confirmation; completes when playback finishes (or fails).
  Future<bool> speak({String language = kReelDefaultLanguage, String? name}) async {
    try {
      final url = await _url(language, name);
      await stop();
      final p = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _player = p;
      await p.initialize().timeout(const Duration(seconds: 10));
      final done = Completer<void>();
      void listener() {
        final v = p.value;
        if (!done.isCompleted && (v.hasError || (v.isCompleted) || (!v.isPlaying && v.position >= v.duration))) {
          done.complete();
        }
      }

      await p.setVolume(1);
      await p.play();
      p.addListener(listener);
      await done.future.timeout(p.value.duration + const Duration(seconds: 3), onTimeout: () {});
      p.removeListener(listener);
      if (_player == p) {
        await stop();
      }
      return true;
    } catch (e) {
      _log.info('confirmation audio failed: $e');
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    final p = _player;
    _player = null;
    await p?.dispose();
  }

  Future<void> dispose() => stop();
}
