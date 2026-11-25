import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/timeline.dart';
import 'package:immich_mobile/memories/reel/reel_strings.dart';
import 'package:immich_mobile/memories/reel/services/reel_api.dart';
import 'package:immich_mobile/memories/reel/services/reel_clock.dart';
import 'package:logging/logging.dart';
import 'package:video_player/video_player.dart';

/// Lets a parent (e.g. the editor) play, pause or reload a [LiveReelPreview].
class LiveReelPreviewController extends ChangeNotifier {
  _LiveReelPreviewState? _state;

  bool get isPlaying => _state?._clock?.isPlaying ?? _state?._fallback?.value.isPlaying ?? false;

  /// EDL currently on screen (null in mp4 fallback mode or while loading).
  Edl? get edl => _state?._timeline?.edl;

  Future<void> play() async => _state?._play();
  Future<void> pause() async => _state?._pause();
  Future<void> toggle() async => isPlaying ? pause() : play();

  /// Re-fetches the EDL (or uses [edl]) and restarts from the beginning.
  /// [previewUrl] replaces the mp4 used if the EDL can't be fetched.
  Future<void> reload({Edl? edl, String? previewUrl}) async => _state?._reload(edl: edl, previewUrl: previewUrl);

  void _notify() => notifyListeners();
}

/// Instant on-device preview of one cut, rendered from its EDL: the music
/// drives the timeline, photos move with a Ken Burns zoom toward their focus
/// point, videos play from their in-point, captions sit in the safe area.
/// Tap to play/pause; loops. Falls back to the server's preview mp4 if the
/// EDL can't be fetched.
class LiveReelPreview extends ConsumerStatefulWidget {
  const LiveReelPreview({
    super.key,
    required this.reelId,
    required this.cut,
    this.previewUrl,
    this.edl,
    this.api,
    this.controller,
    this.autoplay = true,
    this.loop = true,
    this.showCaptions = true,
    this.language = kReelDefaultLanguage,
    this.aspectRatio = 9 / 16,
    this.borderRadius = 20,
    this.onEdlLoaded,
  });

  final String reelId;
  final int cut;

  /// Server-rendered preview mp4, used when the EDL is unavailable.
  final String? previewUrl;

  /// Pre-fetched EDL; skips the network call.
  final Edl? edl;
  final ReelApi? api;
  final LiveReelPreviewController? controller;
  final bool autoplay;
  final bool loop;
  final bool showCaptions;
  final String language;
  final double aspectRatio;
  final double borderRadius;
  final ValueChanged<Edl>? onEdlLoaded;

  @override
  ConsumerState<LiveReelPreview> createState() => _LiveReelPreviewState();
}

enum _Phase { loading, live, fallback, error }

class _VideoSlot {
  _VideoSlot(this.controller);

  final VideoPlayerController controller;
  bool ready = false;
  DateTime lastSync = DateTime.fromMillisecondsSinceEpoch(0);
}

class _LiveReelPreviewState extends ConsumerState<LiveReelPreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final Logger _log = Logger('MemoriesLiveReelPreview');

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _clockS = ValueNotifier(0);
  final Map<int, _VideoSlot> _videos = {};
  final Set<String> _precached = {};

  _Phase _phase = _Phase.loading;
  ReelTimeline? _timeline;
  ReelClock? _clock;
  VideoPlayerController? _fallback;
  String? _previewUrl;
  int _generation = 0;
  int _lastIndex = -1;
  bool _showPausedIcon = false;

  ReelApi get _api => widget.api ?? ref.read(memoriesReelApiProvider);
  ReelStrings get _s => ReelStrings.of(widget.language);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._state = this;
    _previewUrl = widget.previewUrl;
    unawaited(_load(widget.edl));
  }

  @override
  void didUpdateWidget(covariant LiveReelPreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.reelId != widget.reelId || old.cut != widget.cut || (widget.edl != null && widget.edl != old.edl)) {
      unawaited(_reload(edl: widget.edl, previewUrl: widget.previewUrl));
    } else if (widget.previewUrl != old.previewUrl && widget.previewUrl != null) {
      _previewUrl = widget.previewUrl;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller?._state == this) {
      widget.controller?._state = null;
    }
    _generation++;
    _ticker.dispose();
    unawaited(_teardown());
    _clockS.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  Future<void> _teardown() async {
    _ticker.stop();
    final clock = _clock;
    final fallback = _fallback;
    final videos = _videos.values.map((v) => v.controller).toList();
    _clock = null;
    _fallback = null;
    _videos.clear();
    _timeline = null;
    _lastIndex = -1;
    await clock?.dispose();
    await fallback?.dispose();
    for (final v in videos) {
      await v.dispose();
    }
  }

  Future<void> _reload({Edl? edl, String? previewUrl}) async {
    if (previewUrl != null) {
      _previewUrl = previewUrl;
    }
    await _teardown();
    if (!mounted) {
      return;
    }
    _clockS.value = 0;
    setState(() => _phase = _Phase.loading);
    await _load(edl);
  }

  Future<void> _load(Edl? given) async {
    final gen = ++_generation;
    Edl? edl = given;
    if (edl == null) {
      try {
        edl = await _api.fetchEdl(widget.reelId, widget.cut);
      } catch (e) {
        _log.info('EDL unavailable, using preview mp4: $e');
      }
    }
    if (!mounted || gen != _generation) {
      return;
    }
    if (edl == null || edl.isEmpty) {
      await _startFallback(gen);
      return;
    }
    widget.onEdlLoaded?.call(edl);
    final timeline = ReelTimeline(edl);
    _timeline = timeline;
    _precacheAround(0);
    final first = edl.clips.first;
    final clockF = ReelClock.create(durationS: edl.durationS, music: edl.music, loop: widget.loop);
    final firstReady = first.isVideo ? _ensureVideo(0, 0) : Future<void>.value();
    final clock = await clockF;
    await firstReady.timeout(const Duration(seconds: 4), onTimeout: () {});
    if (!mounted || gen != _generation) {
      await clock.dispose();
      return;
    }
    _clock = clock;
    setState(() {
      _phase = _Phase.live;
      _showPausedIcon = !widget.autoplay;
    });
    widget.controller?._notify();
    _ticker.start();
    if (widget.autoplay) {
      await _play();
    }
  }

  Future<void> _startFallback(int gen) async {
    final url = _previewUrl;
    if (url == null) {
      setState(() => _phase = _Phase.error);
      return;
    }
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
      await c.setLooping(widget.loop);
    } catch (e) {
      _log.warning('preview mp4 failed: $e');
      await c.dispose();
      if (mounted && gen == _generation) {
        setState(() => _phase = _Phase.error);
      }
      return;
    }
    if (!mounted || gen != _generation) {
      await c.dispose();
      return;
    }
    _fallback = c;
    c.addListener(_onFallbackChanged);
    setState(() => _phase = _Phase.fallback);
    if (widget.autoplay) {
      await c.play();
    }
    widget.controller?._notify();
  }

  void _onFallbackChanged() {
    final v = _fallback?.value;
    if (v != null && v.isInitialized) {
      final d = v.duration.inMicroseconds;
      _clockS.value = d > 0 ? v.position.inMicroseconds / d : 0;
    }
  }

  // ------------------------------------------------------------------ playback

  Future<void> _play() async {
    if (_phase == _Phase.fallback) {
      await _fallback?.play();
    } else {
      await _clock?.play();
      final f = _timeline?.frameAt(_clock?.positionS ?? 0);
      if (f != null) {
        await _videos[f.index]?.controller.play();
      }
    }
    if (mounted) {
      setState(() => _showPausedIcon = false);
    }
    widget.controller?._notify();
  }

  Future<void> _pause() async {
    if (_phase == _Phase.fallback) {
      await _fallback?.pause();
    } else {
      await _clock?.pause();
      for (final v in _videos.values) {
        await v.controller.pause();
      }
    }
    if (mounted) {
      setState(() => _showPausedIcon = true);
    }
    widget.controller?._notify();
  }

  void _onTick(Duration _) {
    final clock = _clock;
    final timeline = _timeline;
    if (clock == null || timeline == null) {
      return;
    }
    final t = clock.tick();
    _clockS.value = t;
    final frame = timeline.frameAt(t);
    if (frame.index != _lastIndex) {
      _lastIndex = frame.index;
      _precacheAround(frame.index);
    }
    _syncVideos(t, frame);
  }

  void _precacheAround(int index) {
    final timeline = _timeline;
    if (timeline == null || !mounted) {
      return;
    }
    final clips = timeline.edl.clips;
    for (var k = 0; k <= 2 && clips.isNotEmpty; k++) {
      final c = clips[(index + k) % clips.length];
      final url = c.isVideo ? c.posterUrl : c.mediaUrl;
      if (url.isNotEmpty && _precached.add(url)) {
        unawaited(precacheImage(NetworkImage(url), context, onError: (_, _) {}));
      }
    }
  }

  Future<void> _ensureVideo(int index, double clockS) async {
    final timeline = _timeline;
    if (timeline == null || _videos.containsKey(index)) {
      return;
    }
    final clip = timeline.edl.clips[index];
    final c = VideoPlayerController.networkUrl(
      Uri.parse(clip.mediaUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    final slot = _VideoSlot(c);
    _videos[index] = slot;
    try {
      await c.initialize();
      await c.setVolume(0);
      if (_videos[index] != slot) {
        return;
      }
      final active = timeline.frameAt(_clock?.positionS ?? clockS).index == index;
      await c.seekTo(_dur(active ? timeline.videoSourceS(index, _clock?.positionS ?? clockS) : clip.inS));
      slot.ready = true;
      if (active && (_clock?.isPlaying ?? false)) {
        await c.play();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _log.info('video clip $index failed, showing poster: $e');
    }
  }

  void _syncVideos(double t, ReelFrame frame) {
    final timeline = _timeline!;
    final keep = timeline.videosToKeep(t, loop: widget.loop);
    for (final i in keep) {
      if (!_videos.containsKey(i)) {
        unawaited(_ensureVideo(i, t));
      }
    }
    final drop = _videos.keys.where((i) => !keep.contains(i)).toList();
    for (final i in drop) {
      final slot = _videos.remove(i)!;
      unawaited(slot.controller.dispose());
    }
    final playing = _clock?.isPlaying ?? false;
    final now = DateTime.now();
    for (final entry in _videos.entries) {
      final slot = entry.value;
      if (!slot.ready) {
        continue;
      }
      final c = slot.controller;
      final onScreen = entry.key == frame.index || entry.key == frame.outgoingIndex;
      if (onScreen) {
        if (playing && !c.value.isPlaying) {
          unawaited(c.play());
        } else if (!playing && c.value.isPlaying) {
          unawaited(c.pause());
        }
        if (entry.key == frame.index && now.difference(slot.lastSync).inMilliseconds > 500) {
          slot.lastSync = now;
          final want = timeline.videoSourceS(entry.key, t);
          final have = c.value.position.inMicroseconds / 1e6;
          if ((want - have).abs() > kVideoResyncThresholdS) {
            unawaited(c.seekTo(_dur(want)));
          }
        }
      } else if (c.value.isPlaying) {
        // Upcoming clip: park on its first frame so the cut is instant.
        unawaited(c.pause().then((_) => c.seekTo(_dur(timeline.edl.clips[entry.key].inS))));
      }
    }
  }

  static Duration _dur(double s) => Duration(microseconds: (s * 1e6).round());

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _s.previewLabel,
      button: true,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: ColoredBox(
            color: Colors.black,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _phase == _Phase.error ? null : () => unawaited(_toggle()),
              child: LayoutBuilder(builder: (context, box) => _stage(context, box.biggest)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final playing = _clock?.isPlaying ?? _fallback?.value.isPlaying ?? false;
    await (playing ? _pause() : _play());
  }

  Widget _stage(BuildContext context, Size size) {
    switch (_phase) {
      case _Phase.loading:
        return _loading(size);
      case _Phase.error:
        return _error();
      case _Phase.fallback:
        final c = _fallback!;
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
            _progressBar(),
            _pausedOverlay(),
          ],
        );
      case _Phase.live:
        return Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _clockS,
              builder: (context, t, _) => _liveFrame(t, size),
            ),
            _progressBar(),
            _pausedOverlay(),
          ],
        );
    }
  }

  Widget _loading(Size size) {
    final first = widget.edl?.clips.firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (first != null && first.posterUrl.isNotEmpty)
          Image.network(first.posterUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
        const Center(
          child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _error() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              _s.previewFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_reload()),
              icon: const Icon(Icons.refresh),
              label: Text(_s.tryAgain, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveFrame(double t, Size size) {
    final timeline = _timeline;
    if (timeline == null) {
      return const SizedBox();
    }
    final frame = timeline.frameAt(t);
    if (frame.index < 0) {
      return const SizedBox();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (frame.outgoingIndex != null) _clipLayer(frame.outgoingIndex!, t),
        Opacity(opacity: frame.incomingOpacity, child: _clipLayer(frame.index, t)),
        if (widget.showCaptions) _caption(frame.caption, size),
      ],
    );
  }

  Widget _clipLayer(int index, double t) {
    final timeline = _timeline!;
    final clip = timeline.edl.clips[index];
    if (clip.isVideo) {
      final slot = _videos[index];
      final c = slot?.controller;
      if (slot != null && slot.ready && c != null && c.value.isInitialized) {
        return FittedBox(
          key: ValueKey('v$index'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
        );
      }
      return _image(clip.posterUrl, const KenBurnsPose(1, 0.5, 0.5), key: ValueKey('p$index'));
    }
    return _image(clip.mediaUrl, timeline.kenBurnsAt(index, t), key: ValueKey('i$index'));
  }

  Widget _image(String url, KenBurnsPose pose, {Key? key}) {
    if (url.isEmpty) {
      return const SizedBox();
    }
    final align = Alignment(pose.fx * 2 - 1, pose.fy * 2 - 1);
    return Transform.scale(
      key: key,
      scale: pose.scale,
      alignment: align,
      filterQuality: FilterQuality.medium,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        alignment: align,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      ),
    );
  }

  Widget _caption(String? text, Size size) {
    final fontSize = (size.width * 0.064).clamp(16.0, 34.0);
    return Positioned(
      left: size.width * 0.07,
      right: size.width * 0.07,
      // Reels/Status overlay their own UI on the bottom ~15%: keep captions above it.
      bottom: size.height * 0.16,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: text == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey(text),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _progressBar() {
    final total = _timeline?.durationS ?? 1;
    return Positioned(
      left: 12,
      right: 12,
      top: 10,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _clockS,
          builder: (context, t, _) => ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _phase == _Phase.fallback ? t : (total > 0 ? (t / total).clamp(0.0, 1.0) : 0),
              minHeight: 3,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pausedOverlay() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showPausedIcon ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56, semanticLabel: _s.play),
            ),
          ),
        ),
      ),
    );
  }
}
