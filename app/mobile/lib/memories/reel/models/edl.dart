import 'dart:math' as math;

import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/json.dart';

/// Edit decision list for one cut of a reel, as returned by
/// `GET /v1/reels/{id}/cuts/{cut}/edl`.
///
/// Parsing is lenient and normalises the timeline: missing or inconsistent
/// `start_s` values are rebuilt from clip durations, missing durations are
/// derived from `hold_s` / `out_s - in_s`, and per-boundary fades are resolved
/// from `transitions` (or from overlapping clip starts) into [fades].
class Edl {
  Edl({
    required this.cut,
    required this.title,
    required this.durationS,
    required this.music,
    required this.clips,
    required this.captions,
    required this.fades,
  });

  factory Edl.fromJson(Map<String, dynamic> json) {
    final rawClips = asList(json['clips']).map(asMap).where((m) => m.isNotEmpty).toList();
    final clips = _normaliseStarts(rawClips.map(EdlClip.fromJson).toList());
    final clipsEnd = clips.isEmpty ? 0.0 : clips.map((c) => c.endS).reduce(math.max);
    final declared = asDouble(json['duration_s']);
    final duration = declared != null && declared > 0 ? declared : clipsEnd;

    var captions = asList(json['captions']).map(asMap).map(EdlCaption.tryParse).whereType<EdlCaption>().toList();
    if (captions.isEmpty) {
      captions = [
        for (final c in clips)
          if (c.caption != null) EdlCaption(text: c.caption!, startS: c.startS, durationS: c.durationS),
      ];
    }
    captions.sort((a, b) => a.startS.compareTo(b.startS));

    return Edl(
      cut: asInt(json['cut']) ?? 0,
      title: asString(json['title']) ?? '',
      durationS: duration,
      music: EdlMusic.tryParse(asMap(json['music'])),
      clips: List.unmodifiable(clips),
      captions: List.unmodifiable(captions),
      fades: Map.unmodifiable(resolveFades(json['transitions'], clips)),
    );
  }

  final int cut;
  final String title;

  /// Length of the reel in seconds (also the loop length).
  final double durationS;
  final EdlMusic? music;
  final List<EdlClip> clips;
  final List<EdlCaption> captions;

  /// Fade length in seconds keyed by boundary index: `fades[i]` is the fade
  /// from clip `i` into clip `i + 1`. Boundaries not present are hard cuts.
  final Map<int, double> fades;

  bool get isEmpty => clips.isEmpty || durationS <= 0;

  /// Rebuilds start times when the server omitted them or they go backwards.
  static List<EdlClip> _normaliseStarts(List<EdlClip> clips) {
    var ok = clips.isNotEmpty && clips.every((c) => c.declaredStartS != null);
    for (var i = 1; ok && i < clips.length; i++) {
      if (clips[i].declaredStartS! < clips[i - 1].declaredStartS!) {
        ok = false;
      }
    }
    var cursor = 0.0;
    final out = <EdlClip>[];
    for (final c in clips) {
      final start = ok ? c.declaredStartS! : cursor;
      out.add(c.withStart(start));
      cursor = start + c.durationS;
    }
    return out;
  }

  static const _cutWords = {'cut', 'none', 'hard', 'hardcut', 'hard_cut', ''};

  static double? _fadeLength(Object? spec) {
    if (spec == null) {
      return null;
    }
    if (spec is String) {
      return _cutWords.contains(spec.toLowerCase().trim()) ? null : kDefaultFadeS;
    }
    if (spec is num) {
      return spec > 0 ? spec.toDouble() : null;
    }
    final m = asMap(spec);
    final type = (asString(m['type']) ?? asString(m['kind']) ?? 'fade').toLowerCase();
    if (_cutWords.contains(type)) {
      return null;
    }
    final d = asDouble(m['duration_s']) ?? asDouble(m['duration']) ?? kDefaultFadeS;
    return d > 0 ? d : null;
  }

  static int? _boundaryOf(Map<String, dynamic> m, List<EdlClip> clips) {
    for (final key in const ['after', 'boundary', 'index', 'clip', 'from', 'i']) {
      final v = asInt(m[key]);
      if (v != null) {
        return v;
      }
    }
    final at = asDouble(m['at_s']) ?? asDouble(m['start_s']) ?? asDouble(m['at']);
    if (at != null && clips.length > 1) {
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < clips.length - 1; i++) {
        final d = (clips[i + 1].startS - at).abs();
        if (d < bestDist) {
          best = i;
          bestDist = d;
        }
      }
      return best;
    }
    return null;
  }

  /// Resolves the EDL `transitions` field (string, map or list) to fades per boundary.
  static Map<int, double> resolveFades(Object? transitions, List<EdlClip> clips) {
    final boundaries = math.max(0, clips.length - 1);
    final out = <int, double>{};
    void put(int i, double? d) {
      if (d != null && i >= 0 && i < boundaries) {
        out[i] = math.min(d, math.min(clips[i].durationS, clips[i + 1].durationS) * 0.5);
      }
    }

    // Overlapping starts imply a cross-fade (server xfade join).
    for (var i = 0; i < boundaries; i++) {
      final overlap = clips[i].endS - clips[i + 1].startS;
      if (overlap > 0.05) {
        put(i, overlap);
      }
    }

    if (transitions is String || transitions is num) {
      final d = _fadeLength(transitions);
      if (d == null) {
        return out;
      }
      for (var i = 0; i < boundaries; i++) {
        put(i, out[i] ?? d);
      }
    } else if (transitions is Map) {
      final m = asMap(transitions);
      final hasBoundaryKeys = m.keys.isNotEmpty && m.keys.every((k) => int.tryParse(k) != null);
      if (hasBoundaryKeys) {
        m.forEach((k, v) => put(int.parse(k), _fadeLength(v)));
      } else {
        final d = _fadeLength(m);
        for (var i = 0; d != null && i < boundaries; i++) {
          put(i, out[i] ?? d);
        }
      }
    } else if (transitions is List) {
      for (var j = 0; j < transitions.length; j++) {
        final t = transitions[j];
        if (t is Map) {
          final m = asMap(t);
          final b = _boundaryOf(m, clips) ?? j;
          final d = _fadeLength(m);
          if (d == null) {
            out.remove(b);
          } else {
            put(b, d);
          }
        } else {
          put(j, _fadeLength(t));
        }
      }
    }
    return out;
  }
}

enum EdlClipType { photo, video }

class EdlClip {
  const EdlClip({
    required this.assetId,
    required this.type,
    required this.mediaUrl,
    required this.posterUrl,
    required this.inS,
    required this.outS,
    required this.holdS,
    required this.startS,
    required this.durationS,
    required this.caption,
    required this.kenBurns,
    this.declaredStartS,
    this.why,
  });

  factory EdlClip.fromJson(Map<String, dynamic> json) {
    final type = (asString(json['type']) ?? 'photo').toLowerCase() == 'video' ? EdlClipType.video : EdlClipType.photo;
    final inS = asDouble(json['in_s']) ?? 0.0;
    final outS = asDouble(json['out_s']);
    final holdS = asDouble(json['hold_s']);
    final span = outS != null && outS > inS ? outS - inS : null;
    var duration = asDouble(json['duration_s']);
    if (duration == null || duration <= 0) {
      duration = (type == EdlClipType.video ? (span ?? holdS) : (holdS ?? span)) ?? 2.5;
    }
    final media = asString(json['media_url']) ?? asString(json['url']) ?? '';
    return EdlClip(
      assetId: asString(json['asset_id']) ?? '',
      type: type,
      mediaUrl: media,
      posterUrl: asString(json['poster_url']) ?? asString(json['thumbnail_url']) ?? (type == EdlClipType.photo ? media : ''),
      inS: inS,
      outS: outS,
      holdS: holdS,
      startS: asDouble(json['start_s']) ?? 0,
      declaredStartS: asDouble(json['start_s']),
      durationS: math.max(0.1, duration),
      caption: asString(json['caption']),
      kenBurns: KenBurns.fromJson(json['kenburns'] ?? json['ken_burns']),
      why: asString(json['why']),
    );
  }

  final String assetId;
  final EdlClipType type;
  final String mediaUrl;
  final String posterUrl;
  final double inS;
  final double? outS;
  final double? holdS;
  final double startS;
  final double durationS;
  final String? caption;
  final KenBurns kenBurns;
  final double? declaredStartS;
  final String? why;

  bool get isVideo => type == EdlClipType.video;
  double get endS => startS + durationS;

  EdlClip withStart(double start) => EdlClip(
    assetId: assetId,
    type: type,
    mediaUrl: mediaUrl,
    posterUrl: posterUrl,
    inS: inS,
    outS: outS,
    holdS: holdS,
    startS: start,
    declaredStartS: declaredStartS,
    durationS: durationS,
    caption: caption,
    kenBurns: kenBurns,
    why: why,
  );
}

class EdlCaption {
  const EdlCaption({required this.text, required this.startS, required this.durationS});

  static EdlCaption? tryParse(Map<String, dynamic> json) {
    final text = asString(json['text']) ?? asString(json['caption']);
    final start = asDouble(json['start_s']);
    if (text == null || start == null) {
      return null;
    }
    final end = asDouble(json['end_s']);
    final duration = asDouble(json['duration_s']) ?? (end != null ? end - start : null) ?? 2.5;
    if (duration <= 0) {
      return null;
    }
    return EdlCaption(text: text, startS: start, durationS: duration);
  }

  final String text;
  final double startS;
  final double durationS;
  double get endS => startS + durationS;
}

class EdlMusic {
  const EdlMusic({required this.url, this.bpm, this.startS = 0, this.title, this.mood});

  static EdlMusic? tryParse(Map<String, dynamic> json) {
    final url = asString(json['url']) ?? asString(json['audio_url']);
    if (url == null) {
      return null;
    }
    return EdlMusic(
      url: url,
      bpm: asDouble(json['bpm']),
      startS: asDouble(json['start_s']) ?? 0,
      title: asString(json['title']),
      mood: asString(json['mood']),
    );
  }

  final String url;
  final double? bpm;

  /// Offset into the music file where the reel starts.
  final double startS;
  final String? title;

  /// Music mood (e.g. `joyful`) when the server reports it.
  final String? mood;
}

/// A Ken Burns pose: zoom factor and the point (0..1 of the frame) that stays fixed.
class KenBurnsPose {
  const KenBurnsPose(this.scale, this.fx, this.fy);

  final double scale;
  final double fx;
  final double fy;

  static KenBurnsPose lerp(KenBurnsPose a, KenBurnsPose b, double t) => KenBurnsPose(
    a.scale + (b.scale - a.scale) * t,
    a.fx + (b.fx - a.fx) * t,
    a.fy + (b.fy - a.fy) * t,
  );

  @override
  String toString() => 'KenBurnsPose(${scale.toStringAsFixed(3)}, ${fx.toStringAsFixed(3)}, ${fy.toStringAsFixed(3)})';
}

/// Ken Burns move for a photo, matching the server renderer: zoom from
/// [from] to [to] with the focus point (faces) held fixed, linear speed.
///
/// Accepts `from`/`to` as a zoom number (`1.0`), a map (`{scale|zoom, x, y}`)
/// or a normalised crop rect list (`[x, y, w, h]`); `focus` as `[x, y]` or `{x, y}`.
class KenBurns {
  const KenBurns({required this.from, required this.to});

  static const fallback = KenBurns(from: KenBurnsPose(1.0, 0.5, 0.5), to: KenBurnsPose(1.08, 0.5, 0.5));

  factory KenBurns.fromJson(Object? raw) {
    if (raw is! Map) {
      return fallback;
    }
    final m = asMap(raw);
    final focus = _point(m['focus']) ?? (0.5, 0.5);
    final from = _pose(m['from'], focus) ?? KenBurnsPose(1.0, focus.$1, focus.$2);
    final to = _pose(m['to'], focus) ?? KenBurnsPose(1.08, focus.$1, focus.$2);
    return KenBurns(from: from, to: to);
  }

  final KenBurnsPose from;
  final KenBurnsPose to;

  /// Pose at progress [t] (0..1, clamped) through the clip.
  KenBurnsPose at(double t) => KenBurnsPose.lerp(from, to, t.clamp(0.0, 1.0));

  static double _unit(double v) => v.clamp(0.0, 1.0);

  static (double, double)? _point(Object? v) {
    if (v is List && v.length >= 2) {
      final x = asDouble(v[0]);
      final y = asDouble(v[1]);
      return x != null && y != null ? (_unit(x), _unit(y)) : null;
    }
    if (v is Map) {
      final m = asMap(v);
      final x = asDouble(m['x']);
      final y = asDouble(m['y']);
      return x != null && y != null ? (_unit(x), _unit(y)) : null;
    }
    return null;
  }

  static KenBurnsPose? _pose(Object? v, (double, double) focus) {
    if (v is num) {
      return KenBurnsPose(math.max(1.0, v.toDouble()), focus.$1, focus.$2);
    }
    if (v is Map) {
      final m = asMap(v);
      final s = asDouble(m['scale']) ?? asDouble(m['zoom']) ?? asDouble(m['z']) ?? 1.0;
      final p = _point(m) ?? _point(m['focus']) ?? focus;
      return KenBurnsPose(math.max(1.0, s), p.$1, p.$2);
    }
    if (v is List && v.length >= 4) {
      // Normalised crop window [x, y, w, h]: zoom = 1/w; the fixed point is where
      // the window's offset sits within the available slack.
      final x = asDouble(v[0]) ?? 0;
      final y = asDouble(v[1]) ?? 0;
      final w = (asDouble(v[2]) ?? 1).clamp(0.05, 1.0);
      final h = (asDouble(v[3]) ?? 1).clamp(0.05, 1.0);
      final fx = w < 0.999 ? _unit(x / (1 - w)) : focus.$1;
      final fy = h < 0.999 ? _unit(y / (1 - h)) : focus.$2;
      return KenBurnsPose(1 / w, fx, fy);
    }
    if (v is List && v.length == 1) {
      final s = asDouble(v[0]);
      return s == null ? null : KenBurnsPose(math.max(1.0, s), focus.$1, focus.$2);
    }
    return null;
  }
}
