import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/post/post_models.dart';
import 'package:path_provider/path_provider.dart';

class PostApi {
  final DirectorClient _client;

  const PostApi(this._client);

  Future<List<PostChannel>> channels() async =>
      PostChannel.listFromResponse(await _client.getJson('/v1/post/channels'));

  Future<List<PostOutcome>> post({
    required String reelId,
    required int cut,
    required List<String> channelIds,
    required String caption,
  }) async {
    final json = await _client.postJson('/v1/reels/${Uri.encodeComponent(reelId)}/post', {
      'cut': cut,
      'channel_ids': channelIds,
      'caption': caption,
    });
    return PostOutcome.listFromResponse(json);
  }

  /// Returns the final mp4 url for [cut], waiting while the server renders it.
  Future<String> finalUrl(String reelId, int cut, {Duration maxWait = const Duration(seconds: 90)}) async {
    final deadline = DateTime.now().add(maxWait);
    while (true) {
      final json = await _client.postJson('/v1/reels/${Uri.encodeComponent(reelId)}/final/$cut');
      final url = asString(json['final_url']);
      if (url != null && url.isNotEmpty) {
        return url;
      }
      final error = asString(json['error']);
      if (error != null && error.isNotEmpty) {
        throw DirectorException('The video could not be prepared: $error');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const DirectorException('The video is still being prepared. Please try again in a minute.');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// Downloads [url] to a temp file named [fileName] (cached per session).
  Future<File> downloadVideo(String url, {required String fileName}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw DirectorException('Could not download the video (${res.statusCode}).', statusCode: res.statusCode);
    }
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  }

  /// Best-effort analytics (`reel_shared` Flagsmith event).
  Future<void> markShared(String reelId, int cut, String target, {String? memberName}) async {
    try {
      await _client.postJson('/v1/reels/${Uri.encodeComponent(reelId)}/shared', {
        'cut': cut,
        'target': target,
        'member_name': ?memberName,
      });
    } catch (_) {}
  }
}

final postApiProvider = Provider<PostApi>((ref) => PostApi(ref.watch(directorClientProvider)));
