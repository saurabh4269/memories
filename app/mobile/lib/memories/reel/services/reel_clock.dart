import 'dart:async';
import 'dart:math' as math;

import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:logging/logging.dart';
import 'package:video_player/video_player.dart';

/// Master clock for the live preview.
///
/// The music track is the source of truth: the clock follows the music
/// player's reported position and interpolates between its ~100 ms updates
/// with a [Stopwatch], so Ken Burns and cuts stay smooth and in sync. When
/// there is no music (or it fails to load, or it ends before the reel does) the
/// stopwatch alone keeps time.
class ReelClock {
  ReelClock._(this.durationS, this._music, this._musicOffsetS);

  static final Logger _log = Logger('MemoriesReelClock');

  /// Creates a clock and pre-loads [music]. Never throws: a broken music URL
  /// produces a silent clock.
  static Future<ReelClock> create({required double durationS, EdlMusic? music, bool loop = true}) async {
    VideoPlayerController? player;
    if (music != null) {
      try {
        player = VideoPlayerController.networkUrl(
          Uri.parse(music.url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        await player.initialize().timeout(const Duration(seconds: 12));
        await player.seekTo(_dur(music.startS));
      } catch (e) {
        _log.info('music unavailable, playing silently: $e');
        unawaited(player?.dispose());
        player = null;
      }
    }
    final clock = ReelClock._(durationS, player, music?.startS ?? 0)..loop = loop;
    player?.addListener(clock._onMusic);
    return clock;
  }

  final double durationS;
  final VideoPlayerController? _music;
  final double _musicOffsetS;
  bool loop = true;

  final Stopwatch _sw = Stopwatch();
  double _anchorS = 0;
  bool _playing = false;
  bool _stalled = false;
  bool _disposed = false;

  bool get isPlaying => _playing;
  bool get hasMusic => _music != null;

  /// Current reel time in seconds (`0..durationS`).
  double get positionS => math.min(durationS, _anchorS + (_sw.isRunning ? _sw.elapsedMicroseconds / 1e6 : 0));

  static Duration _dur(double s) => Duration(microseconds: (s * 1e6).round());

  bool get _musicUsable {
    final m = _music;
    if (m == null || !m.value.isInitialized || m.value.hasError) {
      return false;
    }
    final musicDur = m.value.duration.inMicroseconds / 1e6;
    return musicDur <= 0 || positionS + _musicOffsetS < musicDur - 0.05;
  }

  void _onMusic() {
    final m = _music;
    if (m == null || _disposed || !_playing || !_musicUsable) {
      return;
    }
    final v = m.value;
    // Buffering: hold the picture until the music resumes, so cuts stay on the beat.
    if (v.isBuffering && !_stalled) {
      _stalled = true;
      _anchorS = positionS;
      _sw
        ..stop()
        ..reset();
      return;
    }
    if (!v.isBuffering && _stalled) {
      _stalled = false;
      _sw.start();
    }
    final musicS = v.position.inMicroseconds / 1e6 - _musicOffsetS;
    // Re-anchor only on real drift so the 100 ms update granularity doesn't cause jitter.
    if ((musicS - positionS).abs() > 0.15 && musicS >= 0) {
      _anchorS = musicS;
      _sw
        ..reset()
        ..start();
    }
  }

  /// Call once per frame. Handles looping; returns the current position.
  double tick() {
    if (_playing && positionS >= durationS - 0.001) {
      if (loop) {
        unawaited(seek(0));
      } else {
        unawaited(pause());
      }
    }
    return positionS;
  }

  Future<void> play() async {
    if (_playing || _disposed) {
      return;
    }
    if (positionS >= durationS - 0.001) {
      await seek(0);
    }
    _playing = true;
    _sw.start();
    if (_musicUsable) {
      await _music!.play();
    }
  }

  Future<void> pause() async {
    if (!_playing || _disposed) {
      return;
    }
    _anchorS = positionS;
    _sw
      ..stop()
      ..reset();
    _playing = false;
    _stalled = false;
    await _music?.pause();
  }

  Future<void> seek(double s) async {
    if (_disposed) {
      return;
    }
    _anchorS = s.clamp(0.0, durationS);
    _sw.reset();
    final m = _music;
    if (m != null && m.value.isInitialized) {
      await m.seekTo(_dur(_anchorS + _musicOffsetS));
      if (_playing && !m.value.isPlaying && _musicUsable) {
        await m.play();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _sw.stop();
    _music?.removeListener(_onMusic);
    await _music?.dispose();
  }
}
