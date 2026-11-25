import 'package:immich_mobile/memories/reel/models/json.dart';

/// What the director understood from a spoken request (`POST /v1/extras/voice-prompt`).
class VoiceIntent {
  const VoiceIntent({
    required this.transcript,
    required this.request,
    this.people = const [],
    this.include = const [],
    this.exclude = const [],
    this.mood,
    this.music,
    this.destination,
    this.engineUsed,
    this.raw = const {},
  });

  /// Parses either the full response `{intent, engine_used}` or a bare intent map.
  factory VoiceIntent.fromJson(Map<String, dynamic> json) {
    final intent = json['intent'] is Map ? asMap(json['intent']) : json;
    final transcript = asString(intent['transcript']) ?? '';
    return VoiceIntent(
      transcript: transcript,
      request: asString(intent['request']) ?? transcript,
      people: asStringList(intent['people']),
      include: asStringList(intent['include']),
      exclude: asStringList(intent['exclude']),
      mood: asString(intent['mood']),
      music: asString(intent['music']),
      destination: asString(intent['destination']),
      engineUsed: asString(json['engine_used']),
      raw: intent,
    );
  }

  /// Exactly what was heard, in the speaker's language.
  final String transcript;

  /// Cleaned-up request to send as `prompt` to `POST /v1/reels`.
  final String request;
  final List<String> people;
  final List<String> include;
  final List<String> exclude;
  final String? mood;
  final String? music;

  /// `wa_status`, `insta_reel` or `insta_story` when the speaker named one.
  final String? destination;
  final String? engineUsed;
  final Map<String, dynamic> raw;

  bool get isEmpty => transcript.trim().isEmpty && request.trim().isEmpty;
}

/// A candidate replacement for one clip slot (`GET .../alternatives?slot=`).
class ClipAlternative {
  const ClipAlternative({required this.assetId, required this.posterUrl, this.why, this.type, this.mediaUrl});

  factory ClipAlternative.fromJson(Map<String, dynamic> json) => ClipAlternative(
    assetId: asString(json['asset_id']) ?? '',
    posterUrl: asString(json['poster_url']) ?? asString(json['thumbnail_url']) ?? '',
    why: asString(json['why']),
    type: asString(json['type']),
    mediaUrl: asString(json['media_url']),
  );

  static List<ClipAlternative> listFromJson(Object? json) {
    final list = json is Map ? asList(json['alternatives']) : asList(json);
    return list.map(asMap).map(ClipAlternative.fromJson).where((a) => a.assetId.isNotEmpty).toList();
  }

  final String assetId;
  final String posterUrl;
  final String? why;
  final String? type;
  final String? mediaUrl;
}

/// One clip in an edit request (`POST /v1/reels/{id}/edit`).
class ClipEdit {
  const ClipEdit({required this.assetId, this.inS, this.outS, this.holdS, this.caption});

  final String assetId;
  final double? inS;
  final double? outS;
  final double? holdS;
  final String? caption;

  Map<String, dynamic> toJson() => {
    'asset_id': assetId,
    'in_s': ?inS,
    'out_s': ?outS,
    'hold_s': ?holdS,
    'caption': ?caption,
  };
}

/// Result of an edit or a final render request.
class ReelCutResult {
  const ReelCutResult({required this.cut, this.previewUrl, this.finalUrl, this.finalStatus, this.coverUrl, this.error});

  factory ReelCutResult.fromJson(Map<String, dynamic> json, {int fallbackCut = 0}) {
    final inner = json['cut'] is Map ? asMap(json['cut']) : json;
    return ReelCutResult(
      cut: asInt(inner['cut']) ?? asInt(json['cut']) ?? fallbackCut,
      previewUrl: asString(inner['preview_url']),
      finalUrl: asString(inner['final_url']),
      finalStatus: asString(inner['final_status']) ?? asString(inner['status']),
      coverUrl: asString(inner['cover_url']),
      error: asString(inner['error']),
    );
  }

  final int cut;
  final String? previewUrl;
  final String? finalUrl;
  final String? finalStatus;
  final String? coverUrl;
  final String? error;

  bool get finalReady => finalUrl != null && (finalStatus == null || finalStatus == 'ready' || finalStatus == 'done');
}
