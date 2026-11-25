import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/memories/join/config.dart';

/// Error thrown by director calls, with a message that is safe to show.
class DirectorException implements Exception {
  final int? statusCode;
  final String message;

  const DirectorException(this.message, {this.statusCode});

  @override
  String toString() => 'DirectorException($statusCode): $message';
}

/// Tiny JSON client for the Memories director API (shared by join/elder/post).
class DirectorClient {
  final http.Client _http;
  final String baseUrl;

  DirectorClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      baseUrl = _trimSlash(baseUrl ?? kDirectorBaseUrl);

  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  DirectorClient withBaseUrl(String url) => DirectorClient(httpClient: _http, baseUrl: url);

  Uri uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    final u = Uri.parse('$baseUrl$path');
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Future<Map<String, dynamic>> getJson(String path, [Map<String, String?>? query]) async {
    return _send(() => _http.get(uri(path, query), headers: const {'Accept': 'application/json'}));
  }

  Future<Map<String, dynamic>> postJson(String path, [Map<String, Object?>? body]) async {
    return _send(
      () => _http.post(
        uri(path),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(kDirectorTimeout);
    } catch (e) {
      throw const DirectorException('Could not reach Memories. Check your internet and try again.');
    }
    final decoded = _decode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = decoded is Map ? (decoded['detail'] ?? decoded['error'] ?? decoded['message']) : null;
      throw DirectorException(
        detail is String && detail.isNotEmpty ? detail : 'Something went wrong (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{'data': decoded};
  }

  static Object? _decode(String body) {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

final directorClientProvider = Provider<DirectorClient>((ref) => DirectorClient());

String? asString(Object? v) => v == null ? null : (v is String ? v : v.toString());
