import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/join/config.dart';
import 'package:immich_mobile/memories/join/join_link.dart';

void main() {
  group('JoinLink.tryParse', () {
    test('parses memories://join with code and server', () {
      final link = JoinLink.tryParse(
        'memories://join?code=AB12CD&server=https%3A%2F%2Fmemories-3870f5.centralindia.cloudapp.azure.com%2Fdirector%2F',
      );
      expect(link, isNotNull);
      expect(link!.code, 'AB12CD');
      expect(link.server, 'https://memories-3870f5.centralindia.cloudapp.azure.com/director');
      expect(link.directorBaseUrl, link.server);
    });

    test('parses memories://join with only a code and falls back to default director', () {
      final link = JoinLink.tryParse('memories://join?code=xyz-789');
      expect(link, const JoinLink(code: 'xyz-789'));
      expect(link!.directorBaseUrl, kDirectorBaseUrl);
    });

    test('accepts upper-case scheme/host and path-style code', () {
      expect(JoinLink.tryParse('MEMORIES://JOIN/ABC123')?.code, 'ABC123');
    });

    test('ignores a non-http server value', () {
      final link = JoinLink.tryParse('memories://join?code=ABC123&server=javascript:alert(1)');
      expect(link?.code, 'ABC123');
      expect(link?.server, isNull);
    });

    test('parses https web_url with ?code=', () {
      final link = JoinLink.tryParse(
        'https://memories-3870f5.centralindia.cloudapp.azure.com/director/join?code=Q1W2E3',
      );
      expect(link?.code, 'Q1W2E3');
      expect(link?.server, isNull);
    });

    test('parses https web_url with /join/<code>', () {
      expect(JoinLink.tryParse('https://example.com/director/join/Q1W2E3')?.code, 'Q1W2E3');
    });

    test('parses a bare typed code with whitespace', () {
      expect(JoinLink.tryParse('  FAM2026  '), const JoinLink(code: 'FAM2026'));
    });

    test('rejects other schemes, hosts and junk', () {
      expect(JoinLink.tryParse(null), isNull);
      expect(JoinLink.tryParse(''), isNull);
      expect(JoinLink.tryParse('immich://album?id=1'), isNull);
      expect(JoinLink.tryParse('memories://album?code=ABC123'), isNull);
      expect(JoinLink.tryParse('memories://join'), isNull);
      expect(JoinLink.tryParse('https://example.com/photos/1'), isNull);
      expect(JoinLink.tryParse('hello world'), isNull);
      expect(JoinLink.tryParse('a'), isNull);
    });
  });

  group('JoinLink.isJoinUri', () {
    test('only matches memories://join', () {
      expect(JoinLink.isJoinUri(Uri.parse('memories://join?code=ABC')), isTrue);
      expect(JoinLink.isJoinUri(Uri.parse('memories://other?code=ABC')), isFalse);
      expect(JoinLink.isJoinUri(Uri.parse('immich://join?code=ABC')), isFalse);
      expect(JoinLink.isJoinUri(Uri.parse('https://my.immich.app/join')), isFalse);
    });
  });
}
