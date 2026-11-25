import 'package:flutter/foundation.dart';

/// A reel the director made in this session (shown on the Memories home).
class RecentReel {
  final String reelId;
  final String title;
  final String why;
  final String coverUrl;
  final String previewUrl;
  final String albumName;
  final DateTime at;

  const RecentReel({
    required this.reelId,
    required this.title,
    required this.why,
    required this.coverUrl,
    required this.previewUrl,
    required this.albumName,
    required this.at,
  });
}

/// In-memory list of recent reels, newest first.
final ValueNotifier<List<RecentReel>> recentReels = ValueNotifier(const []);

void addRecentReels(Iterable<RecentReel> reels) {
  final ids = reels.map((r) => '${r.reelId}/${r.title}').toSet();
  recentReels.value = [
    ...reels,
    ...recentReels.value.where((r) => !ids.contains('${r.reelId}/${r.title}')),
  ].take(12).toList();
}
