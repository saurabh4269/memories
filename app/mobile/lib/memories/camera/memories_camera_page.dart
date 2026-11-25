// Memories in-app camera with a live shot coach.
//
// Camera controller handling (lifecycle teardown/restore on background, lens flip via
// setDescription, flash modes, pinch zoom bounded by min/max zoom, tap-to-focus/exposure,
// hold-to-record) is adapted from LibreCamera (https://github.com/iakmds/librecamera,
// lib/src/pages/camera_page.dart), Copyright (C) LibreCamera contributors, GPL-3.0-or-later.
// GPL-3.0 code may be combined with this AGPL-3.0 project (GPLv3 §13).

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/camera/camera_strings.dart';
import 'package:immich_mobile/memories/camera/capture_queue.dart';
import 'package:immich_mobile/memories/camera/capture_uploader.dart';
import 'package:immich_mobile/memories/camera/coach_models.dart';
import 'package:immich_mobile/memories/camera/coach_service.dart';
import 'package:immich_mobile/memories/camera/config.dart';
import 'package:immich_mobile/memories/camera/widgets/camera_overlays.dart';
import 'package:immich_mobile/memories/camera/widgets/coach_cards.dart';
import 'package:immich_mobile/memories/camera/widgets/shutter_button.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:sensors_plus/sensors_plus.dart';

/// Full-screen camera for an event album.
///
/// Tap the shutter for a photo, hold it for a video (max [kMaxVideoDuration]).
/// Every capture is saved to the device gallery, uploaded to Immich and added to [albumId].
/// A shot coach (director service) suggests missing shots in the member's [language].
class MemoriesCameraPage extends ConsumerStatefulWidget {
  const MemoriesCameraPage({super.key, required this.albumId, required this.memberName, required this.language});

  final String albumId;
  final String memberName;

  /// Member's language code, e.g. `en`, `hi`.
  final String language;

  @override
  ConsumerState<MemoriesCameraPage> createState() => _MemoriesCameraPageState();
}

class _MemoriesCameraPageState extends ConsumerState<MemoriesCameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _log = Logger('MemoriesCameraPage');

  late final CameraStrings _strings = CameraStrings.of(widget.language);
  late final CaptureSink _sink;
  late final CoachService _coachService;
  late final CaptureUploadQueue _queue;
  late final AnimationController _recordAnim = AnimationController(vsync: this, duration: kMaxVideoDuration)
    ..addStatusListener(_onRecordAnimStatus);
  late final AnimationController _flashAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // Camera
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  CameraDescription? _description;
  bool _enableAudio = true;
  bool _permissionDenied = false;
  String? _error;
  Future<void> _lifecycleOp = Future.value();

  // Controls
  FlashMode _flashMode = FlashMode.off;
  bool _grid = false;
  int _timerSeconds = 0; // 0, 3, 10
  int? _countdown;
  Timer? _countdownTimer;
  bool _busy = false; // taking a picture / starting or stopping a recording
  bool _recording = false;
  bool _holdActive = false;
  final _recordElapsed = ValueNotifier<Duration>(Duration.zero);
  Timer? _recordTicker;

  // Zoom & focus
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _baseZoom = 1;
  int _pointers = 0;
  Offset? _focusPoint;
  Timer? _focusHideTimer;

  // Level
  final _tilt = ValueNotifier<double?>(null);
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Coach & counter
  CoachResponse _coach = CoachResponse.empty;
  bool _coachDismissed = false;
  Timer? _coachTimer;
  int _capturesSinceCoach = 0;
  AlbumMoments? _moments;
  bool _hasCaptured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sink = ref.read(memoriesCaptureSinkProvider);
    _coachService = ref.read(memoriesCoachServiceProvider);
    _queue = CaptureUploadQueue(
      sink: _sink,
      albumId: widget.albumId,
      memberName: widget.memberName,
      onUploaded: (_) => unawaited(_refreshMoments()),
    );
    _queueLifecycle(_setUpCameras);
    _listenTilt();
    unawaited(_refreshCoach());
    unawaited(_refreshMoments());
    _coachTimer = Timer.periodic(kCoachPollInterval, (_) {
      unawaited(_refreshCoach());
      unawaited(_refreshMoments());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coachTimer?.cancel();
    _countdownTimer?.cancel();
    _recordTicker?.cancel();
    _focusHideTimer?.cancel();
    unawaited(_accelSub?.cancel());
    _recordAnim.dispose();
    _flashAnim.dispose();
    _recordElapsed.dispose();
    _tilt.dispose();
    _queue.dispose(); // pending uploads keep draining in the background
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle (adapted from LibreCamera): only tear down on a real background
  // transition, and serialise dispose/initialise so they never overlap.
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _cancelCountdown();
        _queueLifecycle(() async {
          if (_recording) {
            await _stopRecording();
          }
          await _releaseCamera();
        });
      case AppLifecycleState.resumed:
        _queueLifecycle(() async {
          final description = _description;
          if (_controller == null && description != null) {
            await _initController(description);
          }
        });
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _queueLifecycle(Future<void> Function() op) {
    _lifecycleOp = _lifecycleOp.then((_) => op()).catchError((Object e) => _log.warning('camera op failed', e));
  }

  Future<void> _setUpCameras() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      _setError(e.description ?? e.code);
      return;
    }
    if (_cameras.isEmpty) {
      _setError(_strings.cameraUnavailable);
      return;
    }
    final back = _cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
    await _initController(back ?? _cameras.first);
  }

  Future<void> _releaseCamera() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _controller = null;
    if (mounted) {
      setState(() {});
    }
    await controller.dispose();
  }

  Future<void> _initController(CameraDescription description) async {
    if (!mounted) {
      return;
    }
    final controller = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: _enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _description = description;
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      if (e.code == 'AudioAccessDenied' && _enableAudio) {
        // Still allow photos (and silent videos) without the microphone.
        _enableAudio = false;
        return _initController(description);
      }
      if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt' || e.code == 'CameraAccessRestricted') {
        if (mounted) {
          setState(() => _permissionDenied = true);
        }
        return;
      }
      _setError(e.description ?? e.code);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }

    try {
      final results = await Future.wait([controller.getMinZoomLevel(), controller.getMaxZoomLevel()]);
      _minZoom = results[0];
      _maxZoom = results[1];
    } catch (_) {
      _minZoom = 1;
      _maxZoom = 1;
    }
    _zoom = _minZoom.clamp(1, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(_zoom);
    } catch (_) {}
    await _applyFlash(controller, _flashMode);

    setState(() {
      _controller = controller;
      _error = null;
      _permissionDenied = false;
    });
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _error = message);
    }
  }

  CaptureLens get _lens =>
      _description?.lensDirection == CameraLensDirection.front ? CaptureLens.front : CaptureLens.back;

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _flip() {
    if (_cameras.length < 2 || _recording || _busy) {
      return;
    }
    final targetDir = _lens == CaptureLens.back ? CameraLensDirection.front : CameraLensDirection.back;
    final target =
        _cameras.where((c) => c.lensDirection == targetDir).firstOrNull ??
        _cameras[(_cameras.indexOf(_description ?? _cameras.first) + 1) % _cameras.length];
    unawaited(HapticFeedback.selectionClick());
    _queueLifecycle(() async {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        try {
          await controller.setDescription(target);
          _description = target;
          final results = await Future.wait([controller.getMinZoomLevel(), controller.getMaxZoomLevel()]);
          _minZoom = results[0];
          _maxZoom = results[1];
          _zoom = _minZoom.clamp(1, _maxZoom).toDouble();
          await controller.setZoomLevel(_zoom);
          await _applyFlash(controller, _flashMode);
          if (mounted) {
            setState(() {});
          }
          return;
        } catch (e) {
          _log.fine('setDescription failed, re-initialising: $e');
          await _releaseCamera();
        }
      }
      await _initController(target);
    });
  }

  void _cycleFlash() {
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    setState(() => _flashMode = next);
    final controller = _controller;
    if (controller != null) {
      unawaited(_applyFlash(controller, next));
    }
  }

  Future<void> _applyFlash(CameraController controller, FlashMode mode) async {
    try {
      await controller.setFlashMode(mode);
    } catch (_) {
      // Front cameras often have no flash.
    }
  }

  void _cycleTimer() {
    setState(() => _timerSeconds = switch (_timerSeconds) { 0 => 3, 3 => 10, _ => 0 });
    unawaited(HapticFeedback.selectionClick());
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  void _onShutterTap() {
    if (_countdown != null) {
      _cancelCountdown();
      return;
    }
    if (_timerSeconds > 0) {
      _startCountdown();
    } else {
      unawaited(_takePhoto());
    }
  }

  void _startCountdown() {
    setState(() => _countdown = _timerSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_countdown ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        setState(() => _countdown = null);
        unawaited(_takePhoto());
      } else {
        unawaited(HapticFeedback.lightImpact());
        setState(() => _countdown = left);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != null && mounted) {
      setState(() => _countdown = null);
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture || _busy) {
      return;
    }
    setState(() => _busy = true);
    _queue.hold();
    try {
      unawaited(_flashAnim.forward(from: 0).then((_) => _flashAnim.reverse()));
      final file = await controller.takePicture();
      await _queue.enqueue(file.path, isVideo: false, lens: _lens);
      _afterCapture();
    } on CameraException catch (e) {
      _log.warning('takePicture failed', e);
    } finally {
      _queue.release();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startRecording() async {
    _holdActive = true;
    _cancelCountdown();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _recording || _busy) {
      return;
    }
    setState(() => _busy = true);
    _queue.hold();
    try {
      await controller.startVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() => _recording = true);
      unawaited(_recordAnim.forward(from: 0));
      final started = DateTime.now();
      _recordElapsed.value = Duration.zero;
      _recordTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _recordElapsed.value = DateTime.now().difference(started);
      });
    } on CameraException catch (e) {
      _log.warning('startVideoRecording failed', e);
      _queue.release();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    // Finger lifted while recording was starting.
    if (_recording && !_holdActive) {
      await _stopRecording();
    }
  }

  void _onHoldEnd() {
    _holdActive = false;
    if (_recording && !_busy) {
      unawaited(_stopRecording());
    }
  }

  void _onRecordAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _recording) {
      unawaited(_stopRecording());
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (!_recording || controller == null || _busy) {
      return;
    }
    _busy = true;
    _recordTicker?.cancel();
    _recordAnim.stop();
    try {
      final file = await controller.stopVideoRecording();
      await _queue.enqueue(file.path, isVideo: true, lens: _lens);
      _afterCapture();
    } on CameraException catch (e) {
      _log.warning('stopVideoRecording failed', e);
    } finally {
      _queue.release();
      _busy = false;
      _recording = false;
      _recordAnim.value = 0;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _afterCapture() {
    _hasCaptured = true;
    _capturesSinceCoach++;
    if (_capturesSinceCoach >= kCoachRefreshEveryCaptures) {
      _capturesSinceCoach = 0;
      unawaited(_refreshCoach());
    }
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom / focus (adapted from LibreCamera)
  // ---------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails _) => _baseZoom = _zoom;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final controller = _controller;
    if (controller == null || _pointers != 2) {
      return;
    }
    final next = (_baseZoom * details.scale).clamp(_minZoom, math.min(_maxZoom, 10.0)).toDouble();
    if ((next - _zoom).abs() < 0.01) {
      return;
    }
    setState(() => _zoom = next);
    unawaited(controller.setZoomLevel(next).catchError((Object _) {}));
  }

  void _onPreviewTap(TapUpDetails details, Size viewSize, Size previewSize) {
    final controller = _controller;
    if (controller == null || _pointers >= 2 || !controller.value.focusPointSupported) {
      return;
    }
    final dx = (viewSize.width - previewSize.width) / 2;
    final dy = (viewSize.height - previewSize.height) / 2;
    final point = Offset(
      ((details.localPosition.dx - dx) / previewSize.width).clamp(0.0, 1.0),
      ((details.localPosition.dy - dy) / previewSize.height).clamp(0.0, 1.0),
    );
    setState(() => _focusPoint = details.localPosition);
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _focusPoint = null);
      }
    });
    unawaited(controller.setFocusPoint(point).catchError((Object _) {}));
    if (controller.value.exposurePointSupported) {
      unawaited(controller.setExposurePoint(point).catchError((Object _) {}));
    }
  }

  // ---------------------------------------------------------------------------
  // Level (accelerometer)
  // ---------------------------------------------------------------------------

  void _listenTilt() {
    try {
      _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (e) {
          // Only meaningful when the phone is held upright-ish (not lying flat).
          if (math.sqrt(e.x * e.x + e.y * e.y) < 4) {
            _tilt.value = null;
            return;
          }
          final roll = math.atan2(e.x, e.y) * 180 / math.pi;
          // Deviation from the nearest portrait/landscape axis.
          final dev = roll - 90 * (roll / 90).roundToDouble();
          final prev = _tilt.value;
          final smoothed = prev == null ? dev : prev * 0.8 + dev * 0.2;
          if (prev == null || (smoothed - prev).abs() > 0.2) {
            _tilt.value = smoothed;
          }
        },
        onError: (Object _) => _tilt.value = null,
        cancelOnError: true,
      );
    } catch (_) {
      // Sensors unavailable (e.g. some emulators): level is simply hidden.
    }
  }

  // ---------------------------------------------------------------------------
  // Coach & counter
  // ---------------------------------------------------------------------------

  Future<void> _refreshCoach() async {
    final res = await _coachService.fetch(
      albumId: widget.albumId,
      member: widget.memberName,
      language: widget.language,
    );
    // On failure (null) keep showing the previous cards.
    if (res == null || !mounted) {
      return;
    }
    final changed = res.cards.isNotEmpty && res.cards.first != _coach.cards.firstOrNull;
    setState(() {
      _coach = res;
      if (changed) {
        _coachDismissed = false;
      }
    });
  }

  Future<void> _refreshMoments() async {
    final m = await _sink.fetchMoments(widget.albumId);
    if (m != null && mounted) {
      setState(() => _moments = m);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            if (_grid) const GridOverlay(),
            Center(
              child: ValueListenableBuilder<double?>(
                valueListenable: _tilt,
                builder: (context, tilt, _) =>
                    LevelIndicator(tiltDegrees: _recording ? null : tilt, warning: _strings.holdStraight),
              ),
            ),
            if (_countdown != null) CountdownOverlay(secondsLeft: _countdown!),
            IgnorePointer(
              child: FadeTransition(
                opacity: _flashAnim,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            SafeArea(child: _buildChrome()),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_permissionDenied) {
      return _MessageView(
        icon: Icons.no_photography_rounded,
        message: _strings.permissionNeeded,
        actionLabel: _strings.openSettings,
        onAction: () => unawaited(openAppSettings()),
      );
    }
    if (_error != null) {
      return _MessageView(icon: Icons.videocam_off_rounded, message: _error!);
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final view = Size(box.maxWidth, box.maxHeight);
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        final ratio = controller.value.aspectRatio; // sensor: width / height (landscape)
        final aspect = portrait ? 1 / ratio : ratio;
        // "Cover" the screen while keeping the preview's aspect ratio.
        var w = view.width;
        var h = w / aspect;
        if (h < view.height) {
          h = view.height;
          w = h * aspect;
        }
        final previewSize = Size(w, h);
        return Listener(
          onPointerDown: (_) => _pointers++,
          onPointerUp: (_) => _pointers--,
          onPointerCancel: (_) => _pointers--,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onTapUp: (d) => _onPreviewTap(d, view, previewSize),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: OverflowBox(
                    maxWidth: w,
                    maxHeight: h,
                    child: SizedBox(width: w, height: h, child: CameraPreview(controller)),
                  ),
                ),
                if (_focusPoint != null)
                  Positioned(
                    left: _focusPoint!.dx - 36,
                    top: _focusPoint!.dy - 36,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 1.4, end: 1),
                        duration: const Duration(milliseconds: 220),
                        builder: (context, s, child) => Transform.scale(scale: s, child: child),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFFFD60A), width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChrome() {
    final hasFlash = _lens == CaptureLens.back;
    final showCoach = _coach.isVisible && !_coachDismissed && !_recording && _countdown == null;
    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              CameraControlButton(
                icon: Icons.close_rounded,
                tooltip: _strings.close,
                onPressed: _recording ? null : () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (_recording)
                _RecordingPill(elapsed: _recordElapsed, label: _strings.recording)
              else ...[
                CameraControlButton(
                  icon: switch (_flashMode) {
                    FlashMode.auto => Icons.flash_auto_rounded,
                    FlashMode.always || FlashMode.torch => Icons.flash_on_rounded,
                    FlashMode.off => Icons.flash_off_rounded,
                  },
                  tooltip: _strings.flash,
                  active: _flashMode != FlashMode.off && hasFlash,
                  onPressed: hasFlash ? _cycleFlash : null,
                ),
                const SizedBox(width: 12),
                CameraControlButton(
                  icon: Icons.grid_3x3_rounded,
                  tooltip: _strings.grid,
                  active: _grid,
                  onPressed: () => setState(() => _grid = !_grid),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            MomentsCounter(moments: _moments, strings: _strings),
            UploadStatusChip(queue: _queue, strings: _strings),
          ],
        ),
        const Spacer(),
        if (_zoom > 1.05 && !_recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_zoom.toStringAsFixed(1)}×',
              style: const TextStyle(
                color: Color(0xFFFFD60A),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: showCoach
              ? Padding(
                  key: const ValueKey('coach'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CoachCardsOverlay(
                    cards: _coach.cards,
                    missingLabel: _strings.missing,
                    onDismiss: () => setState(() => _coachDismissed = true),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-coach')),
        ),
        if (!_hasCaptured && !_recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _strings.tapHoldHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
              ),
            ),
          ),
        // Bottom controls
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CameraControlButton(
                icon: Icons.timer_rounded,
                tooltip: _strings.timer,
                size: 64,
                active: _timerSeconds > 0,
                badge: _timerSeconds > 0 ? '${_timerSeconds}s' : null,
                onPressed: _recording ? null : _cycleTimer,
              ),
              ShutterButton(
                enabled: _controller != null && !_permissionDenied,
                isRecording: _recording,
                recordProgress: _recordAnim,
                semanticLabel: _strings.tapHoldHint,
                onTap: _onShutterTap,
                onHoldStart: () => unawaited(_startRecording()),
                onHoldEnd: _onHoldEnd,
              ),
              CameraControlButton(
                icon: Icons.cameraswitch_rounded,
                tooltip: _strings.flip,
                size: 64,
                onPressed: _cameras.length > 1 && !_recording ? _flip : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.elapsed, required this.label});

  final ValueListenable<Duration> elapsed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: elapsed,
      builder: (context, d, _) {
        final left = kMaxVideoDuration - d;
        final secs = left.inSeconds.clamp(0, kMaxVideoDuration.inSeconds);
        return DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(100)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  '$label  0:${secs.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.3),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 56),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
