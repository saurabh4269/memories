import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/join/join_api.dart';
import 'package:immich_mobile/memories/join/join_link.dart';
import 'package:immich_mobile/memories/join/languages.dart';
import 'package:immich_mobile/memories/join/member_profile.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:logging/logging.dart';

/// Steps shown to the user while joining (plain words, no jargon).
enum JoinStep {
  checkingInvite('Checking your invite…'),
  connecting('Connecting to the family album…'),
  signingIn('Signing you in…'),
  loadingPhotos('Getting the photos ready…'),
  done('All set!');

  final String message;

  const JoinStep(this.message);
}

class JoinOutcome {
  final MemberProfile profile;

  /// The event album, when it is already synced locally. When null the caller
  /// should open the home screen instead.
  final RemoteAlbum? album;

  const JoinOutcome({required this.profile, this.album});
}

/// Redeems an invite and signs in to the returned Immich server using the
/// app's existing auth flow (the member never types a server URL).
class JoinService {
  final Ref _ref;
  final _log = Logger('MemoriesJoin');

  JoinService(this._ref);

  Future<JoinOutcome> join({
    required JoinLink link,
    required String name,
    required String language,
    required MemberRole role,
    void Function(JoinStep step)? onStep,
  }) async {
    onStep?.call(JoinStep.checkingInvite);
    final redeemed = await _ref
        .read(joinApiProvider)
        .redeem(code: link.code, name: name, language: language, role: role.wire, directorBaseUrl: link.server);

    onStep?.call(JoinStep.connecting);
    final auth = _ref.read(authProvider.notifier);
    if (_ref.read(authProvider).isAuthenticated) {
      // One phone, one member: switch accounts to the invited one.
      try {
        await auth.logout();
      } catch (e, s) {
        _log.warning('Logout before join failed', e, s);
      }
    }
    try {
      await auth.validateServerUrl(punycodeEncodeUrl(normalizeServerUrl(redeemed.serverUrl)));
      await _ref.read(serverInfoProvider.notifier).getServerInfo();
    } catch (e, s) {
      _log.severe('Could not reach Immich server ${redeemed.serverUrl}', e, s);
      throw const DirectorException('Could not connect to the family album. Please try again.');
    }

    onStep?.call(JoinStep.signingIn);
    try {
      await auth.login(redeemed.email, redeemed.password);
    } catch (e, s) {
      _log.severe('Login with invite credentials failed', e, s);
      throw const DirectorException('Could not sign you in. Ask the host for a new QR code.');
    }
    if (!_ref.read(authProvider).isAuthenticated) {
      throw const DirectorException('Could not sign you in. Ask the host for a new QR code.');
    }

    final profile = MemberProfile(
      name: name,
      language: language,
      role: role,
      memberId: redeemed.memberId,
      albumId: redeemed.albumId,
      serverUrl: redeemed.serverUrl,
    );
    await _ref.read(memberProfileProvider.notifier).save(profile);

    onStep?.call(JoinStep.loadingPhotos);
    try {
      await _ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
    } catch (e, s) {
      _log.warning('Gallery permission request failed', e, s);
    }
    _ref.read(websocketProvider.notifier).connect();

    RemoteAlbum? album;
    try {
      await _ref.read(backgroundSyncProvider).syncRemote().timeout(const Duration(seconds: 45));
      if (redeemed.albumId.isNotEmpty) {
        album = await _ref.read(remoteAlbumServiceProvider).get(redeemed.albumId);
      }
    } catch (e, s) {
      _log.warning('Initial sync after join did not finish', e, s);
    }
    unawaited(_ref.read(backgroundSyncProvider).syncLocal(full: true).catchError((_) {}));

    onStep?.call(JoinStep.done);
    return JoinOutcome(profile: profile, album: album);
  }
}

final joinServiceProvider = Provider<JoinService>(JoinService.new);
