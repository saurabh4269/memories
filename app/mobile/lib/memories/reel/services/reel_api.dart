import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/json.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';
import 'package:logging/logging.dart';

/// Why a director call failed, so the UI can say something kind and specific.
enum ReelApiErrorKind { offline, timeout, notFound, badInput, server }

class ReelApiException implements Exception {
  const ReelApiException(this.kind, this.message, {this.statusCode});

  final ReelApiErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ReelApiException($kind, $statusCode): $message';
}

/// Client for the Memories director reel endpoints (see docs/API-CONTRACT.md).
class ReelApi {
  ReelApi({http.Client? client, this.baseUrl = kMemoriesDirectorBaseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Logger _log = Logger('MemoriesReelApi');

  Uri uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final u = Uri.parse('$base$path');
    return query == null || query.isEmpty ? u : u.replace(queryParameters: query);
  }

  String _reel(String reelId) => '/v1/reels/${Uri.encodeComponent(reelId)}';

  // ---------------------------------------------------------------- reels

  /// `GET /v1/reels/{id}/cuts/{cut}/edl`
  Future<Edl> fetchEdl(String reelId, int cut) async {
    final json = await _getJson(uri('${_reel(reelId)}/cuts/$cut/edl'));
    final edl = Edl.fromJson(json);
    if (edl.isEmpty) {
      throw const ReelApiException(ReelApiErrorKind.server, 'EDL has no clips');
    }
    return edl;
  }

  /// `GET /v1/reels/{id}/cuts/{cut}/alternatives?slot=`
  Future<List<ClipAlternative>> alternatives(String reelId, int cut, int slot) async {
    final json = await _getJson(uri('${_reel(reelId)}/cuts/$cut/alternatives', {'slot': '$slot'}));
    return ClipAlternative.listFromJson(json);
  }

  /// `POST /v1/reels/{id}/edit` -> the re-rendered cut.
  Future<ReelCutResult> edit(
    String reelId, {
    required int cut,
    required List<ClipEdit> clips,
    String? musicMood,
    String? title,
  }) async {
    final json = await _postJson(uri('${_reel(reelId)}/edit'), {
      'cut': cut,
      'clips': [for (final c in clips) c.toJson()],
      'music_mood': ?musicMood,
      'title': ?title,
    }, timeout: kReelSlowHttpTimeout);
    return ReelCutResult.fromJson(json, fallbackCut: cut);
  }

  /// `POST /v1/reels/{id}/final/{cut}` - waits for the final mp4 render.
  Future<ReelCutResult> renderFinal(String reelId, int cut) async {
    final json = await _postJson(uri('${_reel(reelId)}/final/$cut'), const {}, timeout: kReelSlowHttpTimeout);
    final res = ReelCutResult.fromJson(json, fallbackCut: cut);
    if (res.finalUrl == null) {
      throw ReelApiException(ReelApiErrorKind.server, res.error ?? 'final render not ready');
    }
    return res;
  }

  /// `POST /v1/reels/{id}/shared` - analytics only; never throws.
  Future<void> markShared(String reelId, {required int cut, required String target, String? memberName}) async {
    try {
      await _postJson(uri('${_reel(reelId)}/shared'), {
        'cut': cut,
        'target': target,
        'member_name': ?memberName,
      });
    } catch (e) {
      _log.fine('markShared failed: $e');
    }
  }

  /// `GET /v1/reels/{id}/cuts/{cut}/otio` saved to [into].
  Future<File> downloadOtio(String reelId, int cut, File into) =>
      downloadTo(uri('${_reel(reelId)}/cuts/$cut/otio'), into);

  // ---------------------------------------------------------------- extras

  /// `POST /v1/extras/voice-prompt` (multipart `audio`, `names`, `language`).
  Future<VoiceIntent> voicePrompt(File audio, {List<String> names = const [], String language = kReelDefaultLanguage}) async {
    final req = http.MultipartRequest('POST', uri('/v1/extras/voice-prompt'))
      ..fields['language'] = language
      ..files.add(await http.MultipartFile.fromPath('audio', audio.path, filename: 'prompt.m4a'));
    if (names.isNotEmpty) {
      req.fields['names'] = jsonEncode(names);
    }
    final res = await _send(() async => http.Response.fromStream(await _client.send(req)), kReelSlowHttpTimeout);
    return VoiceIntent.fromJson(_decode(res));
  }

  /// `POST /v1/extras/confirmation` -> URL of the spoken "your reel is ready" audio.
  Future<String> confirmationAudioUrl({String language = kReelDefaultLanguage, String? name}) async {
    final json = await _postJson(uri('/v1/extras/confirmation'), {
      'language': language,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    }, timeout: kReelSlowHttpTimeout);
    final url = asString(json['audio_url']);
    if (url == null) {
      throw const ReelApiException(ReelApiErrorKind.server, 'no audio_url');
    }
    return url;
  }

  // ---------------------------------------------------------------- plumbing

  /// Streams [url] to [into] (used for .otio and the final mp4).
  Future<File> downloadTo(Uri url, File into, {Duration timeout = kReelSlowHttpTimeout}) async {
    try {
      final res = await _client.send(http.Request('GET', url)).timeout(timeout);
      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        throw _statusError(res.statusCode, 'download failed');
      }
      final sink = into.openWrite();
      try {
        await res.stream.pipe(sink).timeout(timeout);
      } finally {
        await sink.close();
      }
      return into;
    } on ReelApiException {
      rethrow;
    } on TimeoutException {
      throw const ReelApiException(ReelApiErrorKind.timeout, 'download timed out');
    } on SocketException catch (e) {
      throw ReelApiException(ReelApiErrorKind.offline, e.message);
    } on http.ClientException catch (e) {
      throw ReelApiException(ReelApiErrorKind.offline, e.message);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri u) async =>
      _decode(await _send(() => _client.get(u, headers: const {'accept': 'application/json'}), kReelHttpTimeout));

  Future<Map<String, dynamic>> _postJson(Uri u, Map<String, dynamic> body, {Duration timeout = kReelHttpTimeout}) async =>
      _decode(
        await _send(
          () => _client.post(
            u,
            headers: const {'content-type': 'application/json', 'accept': 'application/json'},
            body: jsonEncode(body),
          ),
          timeout,
        ),
      );

  Future<http.Response> _send(Future<http.Response> Function() call, Duration timeout) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const ReelApiException(ReelApiErrorKind.timeout, 'request timed out');
    } on SocketException catch (e) {
      throw ReelApiException(ReelApiErrorKind.offline, e.message);
    } on http.ClientException catch (e) {
      throw ReelApiException(ReelApiErrorKind.offline, e.message);
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var detail = 'HTTP ${res.statusCode}';
      try {
        final j = asMap(jsonDecode(utf8.decode(res.bodyBytes)));
        detail = asString(j['detail']) ?? asString(j['error']) ?? detail;
      } catch (_) {}
      _log.fine('${res.request?.url}: $detail');
      throw _statusError(res.statusCode, detail);
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is Map ? asMap(decoded) : {'data': decoded};
    } on FormatException {
      throw const ReelApiException(ReelApiErrorKind.server, 'unexpected response');
    }
  }

  ReelApiException _statusError(int status, String detail) {
    final kind = switch (status) {
      404 => ReelApiErrorKind.notFound,
      400 || 413 || 415 || 422 => ReelApiErrorKind.badInput,
      504 => ReelApiErrorKind.timeout,
      _ => ReelApiErrorKind.server,
    };
    return ReelApiException(kind, detail, statusCode: status);
  }

  void dispose() => _client.close();
}

/// Shared [ReelApi] for the app; widgets also accept an explicit instance.
final memoriesReelApiProvider = Provider<ReelApi>((ref) {
  final api = ReelApi();
  ref.onDispose(api.dispose);
  return api;
});
