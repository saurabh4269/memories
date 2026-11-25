import 'dart:math' as math;

import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';

/// What the preview should draw at one instant.
class ReelFrame {
  const ReelFrame({
    required this.index,
    required this.localS,
    required this.progress,
    this.outgoingIndex,
    this.incomingOpacity = 1.0,
    this.caption,
  });

  /// Clip on top (the active clip).
  final int index;

  /// Seconds since the active clip started.
  final double localS;

  /// 0..1 through the active clip.
  final double progress;

  /// Clip drawn underneath while [index] fades in, or null for a hard cut.
  final int? outgoingIndex;

  /// Opacity of the active clip (below 1 only during a fade).
  final double incomingOpacity;
  final String? caption;
}

/// Pure timeline math over an [Edl] (no Flutter, unit tested).
class ReelTimeline {
  ReelTimeline(this.edl) : _starts = [for (final c in edl.clips) c.startS];

  final Edl edl;
  final List<double> _starts;

  double get durationS => edl.durationS;
  int get length => edl.clips.length;

  /// Maps any clock time into `[0, durationS)` so the reel loops.
  double wrap(double t) {
    final d = durationS;
    if (d <= 0) {
      return 0;
    }
    final r = t % d;
    return r < 0 ? r + d : r;
  }

  /// Index of the clip that is on screen at [t] (the last clip that has started).
  int indexAt(double t) {
    if (_starts.isEmpty) {
      return -1;
    }
    var lo = 0;
    var hi = _starts.length - 1;
    if (t < _starts[0]) {
      return 0;
    }
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  ReelFrame frameAt(double clockS) {
    final t = wrap(clockS);
    final i = indexAt(t);
    if (i < 0) {
      return const ReelFrame(index: -1, localS: 0, progress: 0);
    }
    final clip = edl.clips[i];
    final local = math.max(0.0, t - clip.startS);
    final fade = i > 0 ? edl.fades[i - 1] : null;
    final fading = fade != null && fade > 0 && local < fade;
    return ReelFrame(
      index: i,
      localS: local,
      progress: (local / clip.durationS).clamp(0.0, 1.0),
      outgoingIndex: fading ? i - 1 : null,
      incomingOpacity: fading ? (local / fade).clamp(0.0, 1.0) : 1.0,
      caption: captionAt(t),
    );
  }

  /// Caption shown at [t] (already wrapped), if any.
  String? captionAt(double t) {
    for (final c in edl.captions) {
      if (t >= c.startS && t < c.endS) {
        return c.text;
      }
      if (c.startS > t) {
        break;
      }
    }
    return null;
  }

  /// Ken Burns pose for clip [index] at clock time [clockS].
  KenBurnsPose kenBurnsAt(int index, double clockS) {
    final clip = edl.clips[index];
    final t = wrap(clockS);
    final local = t >= clip.startS ? t - clip.startS : t + durationS - clip.startS;
    return clip.kenBurns.at(local / clip.durationS);
  }

  /// Where inside the source video clip [index] should be at clock time [clockS].
  double videoSourceS(int index, double clockS) {
    final clip = edl.clips[index];
    final local = math.max(0.0, wrap(clockS) - clip.startS);
    final pos = clip.inS + local;
    final out = clip.outS;
    return out != null && out > clip.inS ? math.min(pos, out) : pos;
  }

  /// Video clips whose players should exist at [clockS]: the active and outgoing
  /// clips, the next clip, and anything starting within [aheadS] (wrapping at the loop).
  Set<int> videosToKeep(double clockS, {double aheadS = kPreviewPreloadAheadS, bool loop = true}) {
    final out = <int>{};
    if (length == 0) {
      return out;
    }
    final frame = frameAt(clockS);
    final t = wrap(clockS);
    void add(int i) {
      if (i >= 0 && i < length && edl.clips[i].isVideo) {
        out.add(i);
      }
    }

    add(frame.index);
    if (frame.outgoingIndex != null) {
      add(frame.outgoingIndex!);
    }
    add(frame.index + 1);
    for (var j = frame.index + 1; j < length; j++) {
      if (edl.clips[j].startS - t > aheadS) {
        break;
      }
      add(j);
    }
    if (loop && durationS - t <= aheadS) {
      add(0);
    }
    return out;
  }

  /// Seconds until clip [index] next starts from [clockS] (0 if it is on screen).
  double secondsUntil(int index, double clockS) {
    final t = wrap(clockS);
    final start = edl.clips[index].startS;
    if (indexAt(t) == index) {
      return 0;
    }
    return start >= t ? start - t : start + durationS - t;
  }
}
