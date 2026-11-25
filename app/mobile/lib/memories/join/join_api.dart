import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/director_client.dart';

/// Response of `POST /v1/join/{album_id}/invite`.
class JoinInvite {
  final String code;
  final String joinUrl;
  final String? webUrl;
  final String? qrPngUrl;
  final DateTime? expiresAt;

  const JoinInvite({required this.code, required this.joinUrl, this.webUrl, this.qrPngUrl, this.expiresAt});

  /// Link to share in chat apps: prefer the https web url (clickable everywhere).
  String get shareUrl => (webUrl != null && webUrl!.isNotEmpty) ? webUrl! : joinUrl;

  factory JoinInvite.fromJson(Map<String, dynamic> json) => JoinInvite(
    code: asString(json['code']) ?? '',
    joinUrl: asString(json['join_url']) ?? '',
    webUrl: asString(json['web_url']),
    qrPngUrl: asString(json['qr_png_url']),
    expiresAt: DateTime.tryParse(asString(json['expires_at']) ?? ''),
  );
}

/// Response of `POST /v1/join/redeem`.
class JoinRedeemResult {
  final String serverUrl;
  final String email;
  final String password;
  final String albumId;
  final String memberId;

  const JoinRedeemResult({
    required this.serverUrl,
    required this.email,
    required this.password,
    required this.albumId,
    required this.memberId,
  });

  factory JoinRedeemResult.fromJson(Map<String, dynamic> json) {
    final r = JoinRedeemResult(
      serverUrl: asString(json['server_url']) ?? '',
      email: asString(json['email']) ?? '',
      password: asString(json['password']) ?? '',
      albumId: asString(json['album_id']) ?? '',
      memberId: asString(json['member_id']) ?? '',
    );
    if (r.serverUrl.isEmpty || r.email.isEmpty || r.password.isEmpty) {
      throw const DirectorException('This invite could not be used. Ask the host for a new QR code.');
    }
    return r;
  }
}

class JoinApi {
  final DirectorClient _client;

  const JoinApi(this._client);

  Future<JoinInvite> createInvite(String albumId, {String? createdBy}) async {
    final json = await _client.postJson('/v1/join/${Uri.encodeComponent(albumId)}/invite', {
      if (createdBy != null && createdBy.isNotEmpty) 'created_by': createdBy,
    });
    return JoinInvite.fromJson(json);
  }

  /// Redeems [code]. When [directorBaseUrl] (from the QR) differs from the
  /// default director, it is tried first and the default is used as fallback.
  Future<JoinRedeemResult> redeem({
    required String code,
    required String name,
    required String language,
    required String role,
    String? directorBaseUrl,
  }) async {
    final body = {'code': code, 'name': name, 'language': language, 'role': role};
    if (directorBaseUrl != null && directorBaseUrl != _client.baseUrl) {
      try {
        return JoinRedeemResult.fromJson(await _client.withBaseUrl(directorBaseUrl).postJson('/v1/join/redeem', body));
      } on DirectorException catch (e) {
        // A real "bad code" answer from the right server should not be retried.
        if (e.statusCode != null && e.statusCode != 404) {
          rethrow;
        }
      }
    }
    return JoinRedeemResult.fromJson(await _client.postJson('/v1/join/redeem', body));
  }
}

final joinApiProvider = Provider<JoinApi>((ref) => JoinApi(ref.watch(directorClientProvider)));
