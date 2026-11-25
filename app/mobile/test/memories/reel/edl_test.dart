import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';

Map<String, dynamic> _contractEdl() => {
  'cut': 1,
  'title': 'Diwali at Nani’s',
  'duration_s': 7.5,
  'music': {'url': 'https://x/music.mp3', 'bpm': 96, 'start_s': 12.0, 'mood': 'festive'},
  'clips': [
    {
      'asset_id': 'a1',
      'type': 'photo',
      'media_url': 'https://x/a1.jpg',
      'poster_url': 'https://x/a1_t.jpg',
      'in_s': 0,
      'out_s': 0,
      'hold_s': 2.5,
      'start_s': 0,
      'duration_s': 2.5,
      'caption': 'दादी की मुस्कान',
      'kenburns': {
        'from': 1.0,
        'to': 1.08,
        'focus': [0.3, 0.25],
      },
    },
    {
      'asset_id': 'v1',
      'type': 'video',
      'media_url': 'https://x/v1.mp4',
      'poster_url': 'https://x/v1.jpg',
      'in_s': 4.0,
      'out_s': 7.0,
      'start_s': 2.5,
      'duration_s': 3.0,
    },
    {
      'asset_id': 'a2',
      'type': 'photo',
      'media_url': 'https://x/a2.jpg',
      'poster_url': 'https://x/a2_t.jpg',
      'hold_s': 2.0,
      'start_s': 5.5,
      'duration_s': 2.0,
    },
  ],
  'captions': [
    {'text': 'दादी की मुस्कान', 'start_s': 0.2, 'duration_s': 2.0},
  ],
  'transitions': 'cut',
};

void main() {
  group('Edl.fromJson', () {
    test('parses the contract shape', () {
      final edl = Edl.fromJson(_contractEdl());
      expect(edl.cut, 1);
      expect(edl.title, 'Diwali at Nani’s');
      expect(edl.durationS, 7.5);
      expect(edl.music!.url, 'https://x/music.mp3');
      expect(edl.music!.startS, 12.0);
      expect(edl.music!.bpm, 96);
      expect(edl.music!.mood, 'festive');
      expect(edl.clips, hasLength(3));
      expect(edl.clips[1].isVideo, isTrue);
      expect(edl.clips[1].inS, 4.0);
      expect(edl.clips[1].outS, 7.0);
      expect(edl.clips[2].startS, 5.5);
      expect(edl.captions.single.text, 'दादी की मुस्कान');
      expect(edl.captions.single.startS, 0.2);
      expect(edl.fades, isEmpty);
    });

    test('ken burns number form keeps the focus fixed', () {
      final kb = Edl.fromJson(_contractEdl()).clips.first.kenBurns;
      expect(kb.from.scale, 1.0);
      expect(kb.to.scale, closeTo(1.08, 1e-9));
      expect(kb.from.fx, 0.3);
      expect(kb.to.fy, 0.25);
      final mid = kb.at(0.5);
      expect(mid.scale, closeTo(1.04, 1e-9));
      expect(kb.at(2).scale, closeTo(1.08, 1e-9), reason: 'progress is clamped');
    });

    test('ken burns map and crop-rect forms', () {
      final m = KenBurns.fromJson({
        'from': {'scale': 1.2, 'x': 0.1, 'y': 0.9},
        'to': {'zoom': 1.0},
        'focus': {'x': 0.5, 'y': 0.4},
      });
      expect(m.from.scale, 1.2);
      expect(m.from.fx, 0.1);
      expect(m.to.scale, 1.0);
      expect(m.to.fy, 0.4);

      // Crop window [x, y, w, h] = right half-ish: zoom 2, fixed point at the right edge.
      final r = KenBurns.fromJson({
        'from': [0.0, 0.0, 1.0, 1.0],
        'to': [0.5, 0.25, 0.5, 0.5],
      });
      expect(r.from.scale, 1.0);
      expect(r.to.scale, 2.0);
      expect(r.to.fx, 1.0);
      expect(r.to.fy, 0.5);
    });

    test('missing ken burns falls back to a gentle centred zoom', () {
      final kb = KenBurns.fromJson(null);
      expect(kb.from.scale, 1.0);
      expect(kb.to.scale, greaterThan(1.0));
      expect(kb.from.fx, 0.5);
    });

    test('rebuilds start times and durations when missing', () {
      final edl = Edl.fromJson({
        'clips': [
          {'asset_id': 'a', 'type': 'photo', 'media_url': 'u', 'hold_s': 2},
          {'asset_id': 'b', 'type': 'video', 'media_url': 'v', 'in_s': '1.5', 'out_s': 4},
          {'asset_id': 'c', 'media_url': 'w'},
        ],
      });
      expect(edl.clips.map((c) => c.startS), [0, 2, 4.5]);
      expect(edl.clips.map((c) => c.durationS), [2, 2.5, 2.5]);
      expect(edl.durationS, 7.0);
      expect(edl.clips[0].posterUrl, 'u', reason: 'photos use media_url as poster');
      expect(edl.captions, isEmpty);
    });

    test('non-monotonic start_s is rebuilt', () {
      final edl = Edl.fromJson({
        'clips': [
          {'asset_id': 'a', 'media_url': 'u', 'start_s': 3, 'duration_s': 1},
          {'asset_id': 'b', 'media_url': 'u', 'start_s': 0, 'duration_s': 1},
        ],
      });
      expect(edl.clips.map((c) => c.startS), [0, 1]);
    });

    test('derives captions from clips when the list is empty', () {
      final edl = Edl.fromJson({
        'clips': [
          {'asset_id': 'a', 'media_url': 'u', 'duration_s': 2, 'caption': 'Hello'},
          {'asset_id': 'b', 'media_url': 'u', 'duration_s': 2},
          {'asset_id': 'c', 'media_url': 'u', 'duration_s': 2, 'caption': 'Bye'},
        ],
      });
      expect(edl.captions.map((c) => (c.text, c.startS)), [('Hello', 0.0), ('Bye', 4.0)]);
    });

    test('empty or junk input does not throw', () {
      expect(Edl.fromJson({}).isEmpty, isTrue);
      expect(Edl.fromJson({'clips': 'nope', 'music': 3, 'captions': [1, 2]}).isEmpty, isTrue);
    });
  });

  group('transitions -> fades', () {
    List<Map<String, dynamic>> clips() => [
      for (var i = 0; i < 4; i++) {'asset_id': '$i', 'media_url': 'u', 'duration_s': 2},
    ];

    test('"cut" / null mean hard cuts', () {
      expect(Edl.fromJson({'clips': clips(), 'transitions': 'cut'}).fades, isEmpty);
      expect(Edl.fromJson({'clips': clips()}).fades, isEmpty);
    });

    test('"xfade" fades every boundary with the default length', () {
      final f = Edl.fromJson({'clips': clips(), 'transitions': 'xfade'}).fades;
      expect(f, {0: kDefaultFadeS, 1: kDefaultFadeS, 2: kDefaultFadeS});
    });

    test('list entries by index, by position and by time', () {
      final f = Edl.fromJson({
        'clips': clips(),
        'transitions': [
          {'after': 2, 'type': 'fade', 'duration_s': 0.5},
          {'at_s': 2.1, 'type': 'fade'},
        ],
      }).fades;
      expect(f, {2: 0.5, 0: kDefaultFadeS});

      final positional = Edl.fromJson({
        'clips': clips(),
        'transitions': ['cut', 'fade', 'cut'],
      }).fades;
      expect(positional, {1: kDefaultFadeS});
    });

    test('map keyed by boundary', () {
      final f = Edl.fromJson({
        'clips': clips(),
        'transitions': {
          '1': {'type': 'fade', 'duration_s': 0.3},
          '2': 'cut',
        },
      }).fades;
      expect(f, {1: 0.3});
    });

    test('fade length is capped at half the shorter clip', () {
      final f = Edl.fromJson({
        'clips': clips(),
        'transitions': {'type': 'fade', 'duration_s': 5},
      }).fades;
      expect(f[0], 1.0);
    });

    test('overlapping starts imply a cross-fade', () {
      final f = Edl.fromJson({
        'clips': [
          {'asset_id': 'a', 'media_url': 'u', 'start_s': 0, 'duration_s': 2},
          {'asset_id': 'b', 'media_url': 'u', 'start_s': 1.6, 'duration_s': 2},
        ],
      }).fades;
      expect(f[0], closeTo(0.4, 1e-9));
    });
  });

  group('API models', () {
    test('VoiceIntent parses the full response', () {
      final i = VoiceIntent.fromJson({
        'intent': {
          'transcript': 'दादी के साथ वाली फोटो से रील बनाओ',
          'request': 'Reel of photos with Dadi',
          'people': ['Dadi'],
          'include': [],
          'exclude': ['blurry'],
          'mood': 'emotional',
          'music': null,
          'destination': 'wa_status',
        },
        'engine_used': 'dictate',
      });
      expect(i.transcript, startsWith('दादी'));
      expect(i.request, 'Reel of photos with Dadi');
      expect(i.people, ['Dadi']);
      expect(i.exclude, ['blurry']);
      expect(i.destination, 'wa_status');
      expect(i.music, isNull);
      expect(i.engineUsed, 'dictate');
      expect(i.isEmpty, isFalse);
    });

    test('VoiceIntent request falls back to transcript', () {
      final i = VoiceIntent.fromJson({'transcript': 'hello'});
      expect(i.request, 'hello');
    });

    test('ClipEdit omits nulls', () {
      expect(const ClipEdit(assetId: 'a', holdS: 2).toJson(), {'asset_id': 'a', 'hold_s': 2});
      expect(const ClipEdit(assetId: 'b', inS: 1, outS: 3, caption: '').toJson(), {
        'asset_id': 'b',
        'in_s': 1,
        'out_s': 3,
        'caption': '',
      });
    });

    test('ReelCutResult accepts flat or nested cut', () {
      final flat = ReelCutResult.fromJson({
        'cut': 1,
        'preview_url': 'p',
        'final_url': 'f',
        'final_status': 'done',
      });
      expect(flat.cut, 1);
      expect(flat.finalReady, isTrue);
      final nested = ReelCutResult.fromJson({
        'cut': {'cut': 2, 'preview_url': 'p2', 'final_status': 'pending'},
      });
      expect(nested.cut, 2);
      expect(nested.previewUrl, 'p2');
      expect(nested.finalReady, isFalse);
    });

    test('alternatives list', () {
      final alts = ClipAlternative.listFromJson({
        'alternatives': [
          {'asset_id': 'x', 'poster_url': 'px', 'why': 'Same moment, eyes open'},
          {'poster_url': 'no id'},
        ],
      });
      expect(alts.single.assetId, 'x');
      expect(alts.single.why, 'Same moment, eyes open');
    });
  });
}
