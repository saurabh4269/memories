import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/languages.dart';
import 'package:path_provider/path_provider.dart';

/// The family member using this phone, saved after joining an event.
class MemberProfile {
  final String name;
  final String language;
  final MemberRole role;
  final String? memberId;
  final String? albumId;
  final String? serverUrl;

  const MemberProfile({
    required this.name,
    required this.language,
    required this.role,
    this.memberId,
    this.albumId,
    this.serverUrl,
  });

  /// Identity used for Flagsmith (via the director): stable member id if we
  /// have one, otherwise the name.
  String get identity => (memberId != null && memberId!.isNotEmpty) ? memberId! : name;

  Map<String, dynamic> toJson() => {
    'name': name,
    'language': language,
    'role': role.wire,
    'member_id': memberId,
    'album_id': albumId,
    'server_url': serverUrl,
  };

  factory MemberProfile.fromJson(Map<String, dynamic> json) => MemberProfile(
    name: json['name'] as String? ?? '',
    language: json['language'] as String? ?? 'en',
    role: MemberRole.fromWire(json['role'] as String?),
    memberId: json['member_id'] as String?,
    albumId: json['album_id'] as String?,
    serverUrl: json['server_url'] as String?,
  );
}

/// Persists the profile as a small JSON file in app support storage.
class MemberProfileStore {
  static const _fileName = 'memories_member_profile.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<MemberProfile?> load() async {
    try {
      final f = await _file();
      final json = jsonDecode(await f.readAsString());
      return json is Map<String, dynamic> ? MemberProfile.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(MemberProfile profile) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }

  Future<void> clear() async {
    try {
      await (await _file()).delete();
    } catch (_) {}
  }
}

final memberProfileStoreProvider = Provider<MemberProfileStore>((ref) => MemberProfileStore());

/// Current member profile (null until the user joins an event).
class MemberProfileNotifier extends AsyncNotifier<MemberProfile?> {
  @override
  Future<MemberProfile?> build() => ref.read(memberProfileStoreProvider).load();

  Future<void> save(MemberProfile profile) async {
    await ref.read(memberProfileStoreProvider).save(profile);
    state = AsyncData(profile);
  }

  Future<void> clear() async {
    await ref.read(memberProfileStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final memberProfileProvider = AsyncNotifierProvider<MemberProfileNotifier, MemberProfile?>(MemberProfileNotifier.new);
