import 'package:immich_mobile/memories/join/director_client.dart';

/// A connected Postiz channel from `GET /v1/post/channels`.
class PostChannel {
  final String id;
  final String provider;
  final String name;
  final String? avatar;

  const PostChannel({required this.id, required this.provider, required this.name, this.avatar});

  factory PostChannel.fromJson(Map<String, dynamic> json) => PostChannel(
    id: asString(json['id']) ?? '',
    provider: (asString(json['provider']) ?? '').toLowerCase(),
    name: asString(json['name']) ?? asString(json['provider']) ?? 'Channel',
    avatar: asString(json['avatar']),
  );

  static List<PostChannel> listFromResponse(Map<String, dynamic> json) {
    final raw = json['channels'] ?? json['data'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => PostChannel.fromJson(e.cast<String, dynamic>()))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  /// Human provider label, e.g. `bluesky` -> `Bluesky`.
  String get providerLabel => switch (provider) {
    'bluesky' => 'Bluesky',
    'telegram' => 'Telegram',
    'discord' => 'Discord',
    'x' || 'twitter' => 'X',
    'mastodon' => 'Mastodon',
    'instagram' || 'instagram-standalone' => 'Instagram',
    'youtube' => 'YouTube',
    'facebook' => 'Facebook',
    'linkedin' || 'linkedin-page' => 'LinkedIn',
    '' => 'Channel',
    _ => provider[0].toUpperCase() + provider.substring(1),
  };
}

enum PostState { posting, success, failed }

/// One entry of `POST /v1/reels/{id}/post` -> `{posts:[{channel, status, url?}]}`.
class PostOutcome {
  final String channel;
  final String status;
  final String? url;
  final String? error;

  const PostOutcome({required this.channel, required this.status, this.url, this.error});

  PostState get state {
    final s = status.toLowerCase();
    if (const {'ok', 'success', 'posted', 'published', 'done', 'sent', 'queued', 'scheduled'}.contains(s)) {
      return PostState.success;
    }
    if (const {'pending', 'posting', 'processing', 'uploading'}.contains(s)) {
      return PostState.posting;
    }
    return PostState.failed;
  }

  factory PostOutcome.fromJson(Map<String, dynamic> json) {
    final channel = json['channel'];
    return PostOutcome(
      channel: channel is Map
          ? (asString(channel['id']) ?? asString(channel['name']) ?? '')
          : (asString(channel) ?? ''),
      status: asString(json['status']) ?? 'unknown',
      url: asString(json['url']),
      error: asString(json['error']) ?? asString(json['detail']),
    );
  }

  static List<PostOutcome> listFromResponse(Map<String, dynamic> json) {
    final raw = json['posts'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map>().map((e) => PostOutcome.fromJson(e.cast<String, dynamic>())).toList();
  }
}
