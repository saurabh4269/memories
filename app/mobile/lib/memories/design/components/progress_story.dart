import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/basics.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

/// One step the director narrates while working.
class StoryStep {
  final String label;
  final String? sublabel;

  /// Server stage names (from `timings.stages_ms`) that belong to this step.
  final List<String> stages;

  /// Used until we have real timings from a previous run.
  final Duration fallback;

  const StoryStep(this.label, {this.sublabel, this.stages = const [], required this.fallback});
}

/// Remembers the director's real stage timings from the last run so the next
/// ProgressStory paces itself on reality, not guesses.
abstract final class StoryPacing {
  static final Map<String, int> _lastStagesMs = {};

  static void record(Map<String, int> stagesMs) {
    if (stagesMs.isEmpty) return;
    _lastStagesMs
      ..clear()
      ..addAll(stagesMs);
  }

  static Duration expected(StoryStep step) {
    final ms = step.stages.fold<int>(0, (sum, s) => sum + (_lastStagesMs[s] ?? 0));
    if (ms <= 0) return step.fallback;
    return Duration(milliseconds: math.max(1200, ms));
  }
}

/// The director's steps for making a reel (stage names match server/src/memories/pipeline.py).
const List<StoryStep> kReelStorySteps = [
  StoryStep(
    'Reading the album…',
    sublabel: 'Looking at every photo and video',
    stages: ['album_list', 'voice_prompt', 'analysis'],
    fallback: Duration(seconds: 14),
  ),
  StoryStep(
    'Finding your people…',
    sublabel: 'Faces, smiles, the best takes',
    stages: ['phash', 'team'],
    fallback: Duration(seconds: 9),
  ),
  StoryStep(
    'Writing the story…',
    sublabel: 'Two different moods, one family',
    stages: ['plan'],
    fallback: Duration(seconds: 10),
  ),
  StoryStep(
    'Cutting to the beat…',
    sublabel: 'Rendering your two reels',
    stages: ['render_preview'],
    fallback: Duration(seconds: 24),
  ),
];

/// Animated, honest progress: steps advance on real (last-run) stage timings,
/// hold on the final step until [done], then finish quickly and call [onFinished].
class ProgressStory extends StatefulWidget {
  final List<StoryStep> steps;
  final bool done;
  final VoidCallback? onFinished;
  final Widget? header;

  const ProgressStory({super.key, this.steps = kReelStorySteps, this.done = false, this.onFinished, this.header});

  @override
  State<ProgressStory> createState() => _ProgressStoryState();
}

class _ProgressStoryState extends State<ProgressStory> with SingleTickerProviderStateMixin {
  final _watch = Stopwatch()..start();
  late final List<Duration> _expected = widget.steps.map(StoryPacing.expected).toList();
  final List<Duration?> _actual = [];
  Timer? _tick;
  int _forcedIndex = -1;
  bool _finishing = false;
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _actual.addAll(List.filled(widget.steps.length, null));
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MMotion.reduced(context) && !_breath.isAnimating) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ProgressStory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done && !oldWidget.done) _finish();
  }

  int get _timeIndex {
    var acc = Duration.zero;
    final elapsed = _watch.elapsed;
    for (var i = 0; i < _expected.length; i++) {
      acc += _expected[i];
      if (elapsed < acc) return i;
    }
    return _expected.length - 1; // hold on the last step until done
  }

  int get _activeIndex => math.max(_timeIndex, _forcedIndex);

  void _onTick() {
    if (!mounted) return;
    final idx = _activeIndex;
    for (var i = 0; i < idx; i++) {
      _actual[i] ??= _watch.elapsed;
    }
    setState(() {});
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    for (var i = _activeIndex; i <= widget.steps.length; i++) {
      if (!mounted) return;
      setState(() {
        _forcedIndex = i;
        for (var j = 0; j < i && j < _actual.length; j++) {
          _actual[j] ??= _watch.elapsed;
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    _tick?.cancel();
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _breath.dispose();
    super.dispose();
  }

  double get _overall {
    final total = _expected.fold<int>(0, (s, d) => s + d.inMilliseconds);
    if (_forcedIndex >= widget.steps.length) return 1;
    final raw = _watch.elapsed.inMilliseconds / math.max(total, 1);
    // Ease towards 95% while waiting; never claim done before the server says so.
    final eased = raw < 0.85 ? raw : 0.85 + 0.1 * (1 - math.exp(-(raw - 0.85) * 3));
    final floor = _forcedIndex < 0 ? 0.0 : _forcedIndex / widget.steps.length;
    return math.max(floor, math.min(eased, 0.95));
  }

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final active = _activeIndex;
    final secs = _watch.elapsed.inSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.header != null) ...[widget.header!, const SizedBox(height: MSpace.xl)],
        Row(
          children: [
            const DirectorSpark(size: 16),
            const SizedBox(width: 8),
            Text('THE DIRECTOR IS AT WORK', style: type.overline.copyWith(color: p.diya)),
            const Spacer(),
            Text(
              '${secs}s',
              style: type.label.copyWith(color: p.inkMuted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: MSpace.sm),
        ClipRRect(
          borderRadius: MRadius.pillAll,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _overall),
            duration: const Duration(milliseconds: 400),
            builder: (context, v, _) =>
                LinearProgressIndicator(value: v, minHeight: 6, color: p.diya, backgroundColor: p.surfaceMuted),
          ),
        ),
        const SizedBox(height: MSpace.xl),
        for (var i = 0; i < widget.steps.length; i++)
          _StepRow(
            step: widget.steps[i],
            state: i < active || _forcedIndex >= widget.steps.length
                ? _StepState.done
                : (i == active ? _StepState.active : _StepState.pending),
            took: _actual[i],
            previous: i == 0 ? Duration.zero : _actual[i - 1],
            breath: _breath,
            isLast: i == widget.steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { pending, active, done }

class _StepRow extends StatelessWidget {
  final StoryStep step;
  final _StepState state;
  final Duration? took;
  final Duration? previous;
  final Animation<double> breath;
  final bool isLast;

  const _StepRow({
    required this.step,
    required this.state,
    required this.took,
    required this.previous,
    required this.breath,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final done = state == _StepState.done;
    final active = state == _StepState.active;
    final tookText = done && took != null
        ? '${((took! - (previous ?? Duration.zero)).inMilliseconds / 1000).toStringAsFixed(1)}s'
        : null;
    Widget dot = AnimatedContainer(
      duration: MMotion.standard,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? p.leaf : (active ? p.marigold : p.surfaceMuted),
        border: Border.all(color: done || active ? Colors.transparent : p.line, width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : (active ? Icon(Icons.auto_awesome_rounded, size: 15, color: p.onMarigold) : null),
    );
    if (active) {
      dot = FadeTransition(opacity: Tween(begin: 0.55, end: 1.0).animate(breath), child: dot);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              dot,
              if (!isLast)
                Expanded(
                  child: AnimatedContainer(
                    duration: MMotion.standard,
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done ? p.leaf.withValues(alpha: 0.5) : p.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: MSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : MSpace.lg, top: 2),
              child: AnimatedOpacity(
                duration: MMotion.standard,
                opacity: state == _StepState.pending ? 0.45 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            step.label,
                            style: (active ? type.title.copyWith(fontSize: 21) : type.titleSans.copyWith(fontSize: 17)),
                          ),
                        ),
                        if (tookText != null) Text(tookText, style: type.label.copyWith(color: p.inkMuted)),
                      ],
                    ),
                    if (step.sublabel != null && (active || done)) ...[
                      const SizedBox(height: 2),
                      Text(step.sublabel!, style: type.bodyMuted.copyWith(fontSize: 14)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
