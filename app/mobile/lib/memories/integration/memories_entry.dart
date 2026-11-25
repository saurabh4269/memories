import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/camera/memories_camera_page.dart';
import 'package:immich_mobile/memories/join/member_profile.dart';
import 'package:immich_mobile/providers/user.provider.dart';

const String kDefaultEventAlbumId = '47e3d2d0-21fa-4df7-8a2e-44f57597524b';

({String albumId, String memberName, String language}) memoriesIdentity(WidgetRef ref, {String? albumId}) {
  final profile = ref.read(memberProfileProvider).valueOrNull;
  final user = ref.read(currentUserProvider);
  final profileAlbum = profile?.albumId;
  return (
    albumId: albumId ?? (profileAlbum != null && profileAlbum.isNotEmpty ? profileAlbum : kDefaultEventAlbumId),
    memberName: (profile?.name.isNotEmpty ?? false) ? profile!.name : (user?.name ?? ''),
    language: profile?.language ?? 'hi',
  );
}

Future<void> openMemoriesCamera(NavigatorState navigator, WidgetRef ref, {String? albumId}) {
  final id = memoriesIdentity(ref, albumId: albumId);
  return navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => MemoriesCameraPage(albumId: id.albumId, memberName: id.memberName, language: id.language),
    ),
  );
}
