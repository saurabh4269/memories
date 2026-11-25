import 'package:immich_mobile/memories/join/config.dart';

/// A parsed invite link.
///
/// Accepts any of:
/// - `memories://join?code=ABC123&server=https://...`
/// - the web fallback, e.g. `https://host/director/join?code=ABC123` or
///   `https://host/director/join/ABC123`
/// - a bare code typed by hand, e.g. `abc-123`
class JoinLink {
  final String code;

  /// Director base URL the invite came from, if the link carried one.
  final String? server;

  const JoinLink({required this.code, this.server});

  static final RegExp _bareCode = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$');

  /// True when [uri] is a `memories://join` link (used by the deep link hook).
  static bool isJoinUri(Uri uri) => uri.scheme.toLowerCase() == kJoinScheme && uri.host.toLowerCase() == kJoinHost;

  static JoinLink? tryParse(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      return tryParseUri(uri);
    }

    if (_bareCode.hasMatch(text)) {
      return JoinLink(code: text);
    }
    return null;
  }

  static JoinLink? tryParseUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final server = _cleanServer(uri.queryParameters['server']);

    if (scheme == kJoinScheme) {
      if (uri.host.toLowerCase() != kJoinHost) {
        return null;
      }
      final code = _cleanCode(uri.queryParameters['code']) ?? _lastSegment(uri);
      return code == null ? null : JoinLink(code: code, server: server);
    }

    if (scheme == 'http' || scheme == 'https') {
      final queryCode = _cleanCode(uri.queryParameters['code']);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final joinIndex = segments.lastIndexOf('join');
      String? code = queryCode;
      if (code == null && joinIndex >= 0 && joinIndex + 1 < segments.length) {
        code = _cleanCode(segments[joinIndex + 1]);
      }
      if (code == null) {
        return null;
      }
      return JoinLink(code: code, server: server);
    }

    return null;
  }

  /// The director base URL to redeem against.
  String get directorBaseUrl => server ?? kDirectorBaseUrl;

  static String? _cleanCode(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty || !_bareCode.hasMatch(v)) {
      return null;
    }
    return v;
  }

  static String? _lastSegment(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? null : _cleanCode(segments.last);
  }

  static String? _cleanServer(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(v);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
      return null;
    }
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  @override
  bool operator ==(Object other) => other is JoinLink && other.code == code && other.server == server;

  @override
  int get hashCode => Object.hash(code, server);

  @override
  String toString() => 'JoinLink(code: $code, server: $server)';
}
