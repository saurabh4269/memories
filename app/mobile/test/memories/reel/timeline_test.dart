import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/timeline.dart';

/// photo 0..2, video 2..5 (source 10..13), photo 5..7, video 7..9 (source 0..2)
Edl _edl({Object? transitions}) => Edl.fromJson({
  'duration_s': 9,
  'clips': [
    {
      'asset_id': 'p0',
      'type': 'photo',
      'media_url': 'p0',
      'duration_s': 2,
      'kenburns': {
        'from': 1.0,
        'to': 1.1,
        'focus': [0.2, 0.8],
      },
    },
    {'asset_id': 'v1', 'type': 'video', 'media_url': 'v1', 'in_s': 10, 'out_s': 13},
    {'asset_id': 'p2', 'type': 'photo', 'media_url': 'p2', 'hold_s': 2},
    {'asset_id': 'v3', 'type': 'video', 'media_url': 'v3', 'in_s': 0, 'out_s': 2},
  ],
  'captions': [
    {'text': 'one', 'start_s': 0.5, 'duration_s': 1},
    {'text': 'two', 'start_s': 5, 'end_s': 6.5},
  ],
  'transitions': transitions,
});

void main() {
  group('ReelTimeline', () {
    final tl = ReelTimeline(_edl());

    test('normalised starts', () {
      expect(tl.edl.clips.map((c) => c.startS), [0, 2, 5, 7]);
      expect(tl.durationS, 9);
    });

    test('wrap loops and handles negatives', () {
      expect(tl.wrap(0), 0);
      expect(tl.wrap(9), 0);
      expect(tl.wrap(10.5), closeTo(1.5, 1e-9));
      expect(tl.wrap(-1), closeTo(8, 1e-9));
    });

    test('indexAt at boundaries', () {
      expect(tl.indexAt(0), 0);
      expect(tl.indexAt(1.999), 0);
      expect(tl.indexAt(2), 1);
      expect(tl.indexAt(4.99), 1);
      expect(tl.indexAt(5), 2);
      expect(tl.indexAt(8.9), 3);
      expect(tl.indexAt(-0.5), 0);
    });

    test('frameAt gives local time, progress and caption', () {
      final f = tl.frameAt(3.5);
      expect(f.index, 1);
      expect(f.localS, closeTo(1.5, 1e-9));
      expect(f.progress, closeTo(0.5, 1e-9));
      expect(f.outgoingIndex, isNull);
      expect(f.incomingOpacity, 1);
      expect(f.caption, isNull);
      expect(tl.frameAt(1).caption, 'one');
      expect(tl.frameAt(1.6).caption, isNull);
      expect(tl.frameAt(6.4).caption, 'two');
      expect(tl.frameAt(9 + 1).caption, 'one', reason: 'loops');
    });

    test('ken burns pose follows clip progress', () {
      final start = tl.kenBurnsAt(0, 0);
      final mid = tl.kenBurnsAt(0, 1);
      final end = tl.kenBurnsAt(0, 1.999);
      expect(start.scale, closeTo(1.0, 1e-9));
      expect(mid.scale, closeTo(1.05, 1e-9));
      expect(end.scale, closeTo(1.1, 1e-3));
      expect(mid.fx, 0.2);
      expect(mid.fy, 0.8);
    });

    test('video source position maps clock to in/out', () {
      expect(tl.videoSourceS(1, 2), 10);
      expect(tl.videoSourceS(1, 3.25), closeTo(11.25, 1e-9));
      expect(tl.videoSourceS(1, 4.999), closeTo(12.999, 1e-9));
      expect(tl.videoSourceS(3, 8), closeTo(1, 1e-9));
    });

    test('videosToKeep preloads ~1.5 s ahead and around the loop', () {
      // Showing photo 0; the next clip (video 1) is always kept warm.
      expect(tl.videosToKeep(0), {1});
      // During video 1: keep it.
      expect(tl.videosToKeep(3), {1});
      // Photo 2 at 5.6: video 3 starts at 7 (1.4 s ahead) and is the next clip.
      expect(tl.videosToKeep(5.6), {3});
      // Video 3 near the loop end: nothing to add for clip 0 (photo).
      expect(tl.videosToKeep(8.5), {3});
    });

    test('videosToKeep honours lookahead beyond the next clip', () {
      final dense = ReelTimeline(
        Edl.fromJson({
          'clips': [
            {'asset_id': 'a', 'type': 'photo', 'media_url': 'a', 'duration_s': 0.5},
            {'asset_id': 'b', 'type': 'photo', 'media_url': 'b', 'duration_s': 0.5},
            {'asset_id': 'c', 'type': 'video', 'media_url': 'c', 'duration_s': 2},
            {'asset_id': 'd', 'type': 'video', 'media_url': 'd', 'duration_s': 2},
          ],
        }),
      );
      expect(dense.videosToKeep(0), {2}, reason: 'c starts at 1.0, within 1.5 s');
      expect(dense.videosToKeep(0, aheadS: 0.5), isEmpty);
      // Near the end with a video first clip, clip 0 is pre-warmed for the loop.
      final loopy = ReelTimeline(
        Edl.fromJson({
          'clips': [
            {'asset_id': 'v', 'type': 'video', 'media_url': 'v', 'duration_s': 2},
            {'asset_id': 'p', 'type': 'photo', 'media_url': 'p', 'duration_s': 3},
          ],
        }),
      );
      expect(loopy.videosToKeep(4), {0});
      expect(loopy.videosToKeep(4, loop: false), isEmpty);
    });

    test('secondsUntil wraps around the loop', () {
      expect(tl.secondsUntil(1, 0.5), closeTo(1.5, 1e-9));
      expect(tl.secondsUntil(1, 3), 0);
      expect(tl.secondsUntil(0, 8), closeTo(1, 1e-9));
    });
  });

  group('fades in frames', () {
    test('hard cut has no outgoing clip', () {
      final tl = ReelTimeline(_edl(transitions: 'cut'));
      final f = tl.frameAt(2.05);
      expect(f.index, 1);
      expect(f.outgoingIndex, isNull);
      expect(f.incomingOpacity, 1);
    });

    test('fade where the EDL says so', () {
      final tl = ReelTimeline(
        _edl(
          transitions: [
            {'after': 1, 'type': 'fade', 'duration_s': 0.4},
          ],
        ),
      );
      // Boundary 0 (2 s) stays a hard cut.
      expect(tl.frameAt(2.1).outgoingIndex, isNull);
      // Boundary 1 (5 s) fades over 0.4 s.
      final f = tl.frameAt(5.1);
      expect(f.index, 2);
      expect(f.outgoingIndex, 1);
      expect(f.incomingOpacity, closeTo(0.25, 1e-9));
      expect(tl.frameAt(5.4).outgoingIndex, isNull);
      expect(tl.videosToKeep(5.1), containsAll([1, 3]), reason: 'outgoing video stays alive while fading');
    });
  });
}
