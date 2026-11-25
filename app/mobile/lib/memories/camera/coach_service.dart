import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/memories/camera/coach_models.dart';
import 'package:immich_mobile/memories/camera/config.dart';
import 'package:logging/logging.dart';

/// Talks to the Memories director's shot-coach endpoint.
class CoachService {
  CoachService({http.Client? client, this.baseUrl = kMemoriesDirectorBaseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Logger _log = Logger('MemoriesCoachService');

  Uri coachUri({required String albumId, required String member, required String language}) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse(
      '$base/v1/albums/${Uri.encodeComponent(albumId)}/coach',
    ).replace(queryParameters: {'member': member, 'lang': language});
  }

  /// Fetches coach cards. Never throws; returns `null` on network/HTTP failure so callers
  /// can keep showing the previous cards.
  Future<CoachResponse?> fetch({required String albumId, required String member, required String language}) async {
    try {
      final res = await _client
          .get(coachUri(albumId: albumId, member: member, language: language))
          .timeout(kDirectorTimeout);
      if (res.statusCode != 200) {
        _log.fine('coach HTTP ${res.statusCode}');
        return null;
      }
      return CoachResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (e) {
      _log.fine('coach fetch failed: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}

final memoriesCoachServiceProvider = Provider<CoachService>((ref) {
  final service = CoachService();
  ref.onDispose(service.dispose);
  return service;
});
