import 'package:flutter/foundation.dart';
import 'package:immich_mobile/memories/camera/config.dart';

/// One "missing shot" suggestion from the director's shot coach.
///
/// Contract: `GET /v1/albums/{id}/coach?member=&lang=` →
/// `{cards:[{title, tip, lang}], disabled?}`.
@immutable
class CoachCard {
  final String title;
  final String tip;
  final String? lang;

  const CoachCard({required this.title, required this.tip, this.lang});

  /// Lenient parser: returns `null` for entries that have no usable text.
  static CoachCard? tryParse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final title = _str(json['title']) ?? _str(json['missing']) ?? '';
    final tip = _str(json['tip']) ?? _str(json['text']) ?? '';
    if (title.isEmpty && tip.isEmpty) {
      return null;
    }
    return CoachCard(title: title, tip: tip, lang: _str(json['lang']));
  }

  static String? _str(Object? v) {
    if (v == null) {
      return null;
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  bool operator ==(Object other) =>
      other is CoachCard && other.title == title && other.tip == tip && other.lang == lang;

  @override
  int get hashCode => Object.hash(title, tip, lang);

  @override
  String toString() => 'CoachCard($title, $tip, $lang)';
}

/// Parsed response of the coach endpoint.
@immutable
class CoachResponse {
  final List<CoachCard> cards;

  /// `true` when the server-side feature flag (`shot_coach`) is off for this member.
  final bool disabled;

  const CoachResponse({this.cards = const [], this.disabled = false});

  static const empty = CoachResponse();

  /// Whether the coach overlay should be shown at all.
  bool get isVisible => !disabled && cards.isNotEmpty;

  factory CoachResponse.fromJson(Object? json) {
    if (json is List) {
      // Tolerate a bare list of cards.
      return CoachResponse(cards: _parseCards(json));
    }
    if (json is! Map) {
      return empty;
    }
    final disabled = json['disabled'] == true || json['disabled'] == 'true' || json['enabled'] == false;
    if (disabled) {
      return const CoachResponse(disabled: true);
    }
    final raw = json['cards'];
    return CoachResponse(cards: raw is List ? _parseCards(raw) : const []);
  }

  static List<CoachCard> _parseCards(List<Object?> raw) =>
      raw.map(CoachCard.tryParse).whereType<CoachCard>().take(kMaxCoachCards).toList(growable: false);
}
