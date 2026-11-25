import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';
import 'package:immich_mobile/memories/reel/reel_strings.dart';
import 'package:immich_mobile/memories/reel/services/reel_api.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum VoicePromptState { idle, recording, uploading, heard, error }

/// Big round mic button for speaking a reel request.
///
/// Tap to start and tap again to stop, or press-and-hold and release. Records
/// up to [maxDuration] of AAC (m4a), shows a live level meter and timer, sends
/// it to `POST /v1/extras/voice-prompt` with [familyNames] (helps the ASR spell
/// names) and [language], then calls [onIntent]. What was heard is shown in a
/// chip under the button; errors are shown in plain, kind words.
class VoicePromptButton extends ConsumerStatefulWidget {
  const VoicePromptButton({
    super.key,
    required this.onIntent,
    this.familyNames = const [],
    this.language = kReelDefaultLanguage,
    this.api,
    this.size = 132,
    this.maxDuration = kVoicePromptMaxDuration,
    this.enabled = true,
    this.showTranscript = true,
    this.onStateChanged,
    this.onError,
  });

  final ValueChanged<VoiceIntent> onIntent;
  final List<String> familyNames;

  /// BCP-47 code sent to the server, e.g. `hi-IN` or `en-IN`; also picks the UI language.
  final String language;
  final ReelApi? api;

  /// Diameter of the mic button (keep >= 96 for elders).
  final double size;
  final Duration maxDuration;
  final bool enabled;
  final bool showTranscript;
  final ValueChanged<VoicePromptState>? onStateChanged;

  /// Called with the user-facing message when something goes wrong.
  final ValueChanged<String>? onError;

  @override
  ConsumerState<VoicePromptButton> createState() => _VoicePromptButtonState();
}

class _VoicePromptButtonState extends ConsumerState<VoicePromptButton> {
  static final Logger _log = Logger('MemoriesVoicePrompt');
  static const _meterBars = 28;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _elapsed = Stopwatch();
  final List<double> _levels = [];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  VoicePromptState _state = VoicePromptState.idle;
  bool _holdMode = false;
  bool _starting = false;
  bool _stopWhenStarted = false;
  String? _transcript;
  String? _error;

  ReelStrings get _s => ReelStrings.of(widget.language);
  ReelApi get _api => widget.api ?? ref.read(memoriesReelApiProvider);

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_ampSub?.cancel());
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
    await _recorder.dispose();
  }

  void _set(VoicePromptState s, {String? error, String? transcript}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _state = s;
      _error = error;
      if (transcript != null || s == VoicePromptState.recording) {
        _transcript = transcript;
      }
    });
    widget.onStateChanged?.call(s);
    if (error != null) {
      widget.onError?.call(error);
    }
  }

  // ------------------------------------------------------------------ recording

  Future<void> _start({required bool hold}) async {
    if (!widget.enabled || _starting || _state == VoicePromptState.recording || _state == VoicePromptState.uploading) {
      return;
    }
    _starting = true;
    _stopWhenStarted = false;
    _holdMode = hold;
    try {
      if (!await _recorder.hasPermission()) {
        _set(VoicePromptState.error, error: _s.micDenied);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/memories_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
          autoGain: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      unawaited(HapticFeedback.mediumImpact());
      _levels.clear();
      _elapsed
        ..reset()
        ..start();
      _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen(_onAmplitude);
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_elapsed.elapsed >= widget.maxDuration) {
          unawaited(_stop());
        } else if (mounted) {
          setState(() {});
        }
      });
      _set(VoicePromptState.recording);
    } catch (e) {
      _log.warning('could not start recording: $e');
      _set(VoicePromptState.error, error: _s.genericError);
    } finally {
      _starting = false;
    }
    if (_stopWhenStarted) {
      // Finger lifted while the recorder was still starting.
      await _stop();
    }
  }

  void _onAmplitude(Amplitude a) {
    if (!mounted) {
      return;
    }
    // dBFS: ~-50 is room tone, 0 is clipping.
    final level = ((a.current + 50) / 50).clamp(0.0, 1.0);
    setState(() {
      _levels.add(level.isNaN ? 0 : level);
      if (_levels.length > _meterBars) {
        _levels.removeAt(0);
      }
    });
  }

  Future<void> _stop() async {
    if (_state != VoicePromptState.recording) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    _elapsed.stop();
    final took = _elapsed.elapsed;
    unawaited(HapticFeedback.lightImpact());
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      _log.warning('stop failed: $e');
    }
    if (path == null) {
      _set(VoicePromptState.error, error: _s.genericError);
      return;
    }
    final file = File(path);
    if (took < kVoicePromptMinDuration) {
      _set(VoicePromptState.error, error: _s.tooShort);
      unawaited(_delete(file));
      return;
    }
    _set(VoicePromptState.uploading);
    try {
      final intent = await _api.voicePrompt(file, names: widget.familyNames, language: widget.language);
      if (intent.isEmpty) {
        _set(VoicePromptState.error, error: _s.couldNotHear);
        return;
      }
      _set(VoicePromptState.heard, transcript: intent.transcript.isNotEmpty ? intent.transcript : intent.request);
      if (mounted) {
        widget.onIntent(intent);
      }
    } on ReelApiException catch (e) {
      _log.info('voice prompt failed: $e');
      _set(
        VoicePromptState.error,
        error: e.kind == ReelApiErrorKind.badInput ? _s.couldNotHear : _s.error(e),
      );
    } catch (e) {
      _log.warning('voice prompt failed: $e');
      _set(VoicePromptState.error, error: _s.genericError);
    } finally {
      unawaited(_delete(file));
    }
  }

  Future<void> _delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  void _onTap() {
    if (_state == VoicePromptState.recording) {
      unawaited(_stop());
    } else {
      unawaited(_start(hold: false));
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = _state == VoicePromptState.recording;
    final uploading = _state == VoicePromptState.uploading;
    final level = recording && _levels.isNotEmpty ? _levels.last : 0.0;
    final color = recording ? const Color(0xFFE5484D) : scheme.primary;
    final onColor = recording ? Colors.white : scheme.onPrimary;
    final ring = widget.size * (1.12 + level * 0.3);

    final label = switch (_state) {
      VoicePromptState.recording => _holdMode ? _s.listening : '${_s.listening}  ${_s.tapToStop}',
      VoicePromptState.uploading => _s.understanding,
      _ => _s.tapToSpeak,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size * 1.5,
          height: widget.size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: recording ? ring : widget.size,
                height: recording ? ring : widget.size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
              ),
              Semantics(
                button: true,
                enabled: widget.enabled && !uploading,
                label: recording ? _s.tapToStop : _s.tapToSpeak,
                child: GestureDetector(
                  onTap: widget.enabled && !uploading ? _onTap : null,
                  onLongPressStart: widget.enabled && !uploading && !recording ? (_) => unawaited(_start(hold: true)) : null,
                  onLongPressEnd: (_) {
                    if (_starting) {
                      _stopWhenStarted = true;
                    } else if (_holdMode) {
                      unawaited(_stop());
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.enabled ? color : scheme.surfaceContainerHighest,
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Center(
                      child: uploading
                          ? SizedBox(
                              width: widget.size * 0.36,
                              height: widget.size * 0.36,
                              child: CircularProgressIndicator(color: onColor, strokeWidth: 4),
                            )
                          : Icon(
                              recording ? Icons.stop_rounded : Icons.mic_rounded,
                              size: widget.size * 0.46,
                              color: widget.enabled ? onColor : scheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 22),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: recording ? _meter(color) : const SizedBox(width: double.infinity),
        ),
        AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _footer(theme)),
      ],
    );
  }

  Widget _meter(Color color) {
    final secs = _elapsed.elapsed.inSeconds;
    final max = widget.maxDuration.inSeconds;
    final nearEnd = max - secs <= 5;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 44,
            child: CustomPaint(painter: _LevelsPainter(List.of(_levels), _meterBars, color)),
          ),
          const SizedBox(height: 6),
          Text(
            '${_fmt(secs)} / ${_fmt(max)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: nearEnd ? const Color(0xFFE5484D) : null,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _footer(ThemeData theme) {
    final scheme = theme.colorScheme;
    if (_state == VoicePromptState.error && _error != null) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 14, left: 16, right: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 18, color: scheme.onErrorContainer, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final transcript = _transcript;
    if (widget.showTranscript && transcript != null && transcript.isNotEmpty && _state != VoicePromptState.recording) {
      return Padding(
        key: ValueKey('t$transcript'),
        padding: const EdgeInsets.only(top: 14, left: 16, right: 16),
        child: Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.record_voice_over_rounded, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '“$transcript”',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 19, color: scheme.onSecondaryContainer, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox(key: ValueKey('none'));
  }
}

class _LevelsPainter extends CustomPainter {
  _LevelsPainter(this.levels, this.bars, this.color);

  final List<double> levels;
  final int bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final w = (size.width - gap * (bars - 1)) / bars;
    final paint = Paint()..color = color;
    final offset = bars - levels.length;
    for (var i = 0; i < bars; i++) {
      final li = i - offset;
      final v = li >= 0 ? levels[li] : 0.0;
      final h = math.max(4.0, v * size.height);
      final x = i * (w + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, w, h),
        Radius.circular(w / 2),
      );
      paint.color = color.withValues(alpha: li >= 0 ? 0.9 : 0.25);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LevelsPainter old) => true;
}
