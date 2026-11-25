// Raw JSON-shaped literals are intentional here (they mimic decoded responses).

// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/memories/camera/camera_strings.dart';
import 'package:immich_mobile/memories/camera/coach_models.dart';
import 'package:immich_mobile/memories/camera/coach_service.dart';
import 'package:immich_mobile/memories/camera/widgets/coach_cards.dart';

const _sample = '''
{
  "cards": [
    {"title": "Dadi with the kids", "tip": "Ask the kids to sit around Dadi near the diyas.", "lang": "en"},
    {"title": "The rangoli", "tip": "Shoot from above, phone flat.", "lang": "en"},
    {"title": "", "tip": ""},
    {"title": "Group photo", "tip": "Use the 10 s timer.", "lang": "en"},
    {"title": "A fourth one", "tip": "Should be dropped (max 3)."}
  ]
}
''';

void main() {
  group('CoachResponse.fromJson', () {
    test('parses cards, skips empty ones and caps at 3', () {
      final res = CoachResponse.fromJson(jsonDecode(_sample));
      expect(res.disabled, isFalse);
      expect(res.isVisible, isTrue);
      expect(res.cards, hasLength(3));
      expect(res.cards.first, const CoachCard(title: 'Dadi with the kids', tip: 'Ask the kids to sit around Dadi near the diyas.', lang: 'en'));
      expect(res.cards.map((c) => c.title), ['Dadi with the kids', 'The rangoli', 'Group photo']);
    });

    test('disabled:true hides the coach even if cards are present', () {
      final res = CoachResponse.fromJson({
        'disabled': true,
        'cards': [
          {'title': 'x', 'tip': 'y'},
        ],
      });
      expect(res.disabled, isTrue);
      expect(res.cards, isEmpty);
      expect(res.isVisible, isFalse);
    });

    test('tolerates malformed payloads', () {
      expect(CoachResponse.fromJson(null).isVisible, isFalse);
      expect(CoachResponse.fromJson('nope').isVisible, isFalse);
      expect(CoachResponse.fromJson({'cards': 'nope'}).cards, isEmpty);
      expect(CoachResponse.fromJson({'cards': [1, null, {}]}).cards, isEmpty);
      // Tip-only card and numeric fields are accepted.
      final res = CoachResponse.fromJson([
        {'tip': 'Only a tip', 'title': 42},
      ]);
      expect(res.cards.single.title, '42');
      expect(res.cards.single.tip, 'Only a tip');
    });

    test('parses non-latin text (member language)', () {
      final res = CoachResponse.fromJson(
        jsonDecode('{"cards":[{"title":"दादी बच्चों के साथ","tip":"दीयों के पास बैठाएँ","lang":"hi"}]}'),
      );
      expect(res.cards.single.title, 'दादी बच्चों के साथ');
      expect(res.cards.single.lang, 'hi');
    });
  });

  group('CoachService', () {
    test('builds the contract URL and parses the body', () async {
      late Uri requested;
      final service = CoachService(
        baseUrl: 'https://example.test/director/',
        client: MockClient((req) async {
          requested = req.url;
          return http.Response.bytes(utf8.encode(_sample), 200, headers: {'content-type': 'application/json'});
        }),
      );
      final res = await service.fetch(albumId: 'album-1', member: 'Asha Devi', language: 'hi');
      expect(requested.toString(), 'https://example.test/director/v1/albums/album-1/coach?member=Asha+Devi&lang=hi');
      expect(res!.cards, hasLength(3));
    });

    test('returns null on HTTP errors and exceptions', () async {
      final failing = CoachService(client: MockClient((_) async => http.Response('boom', 500)));
      expect(await failing.fetch(albumId: 'a', member: 'm', language: 'en'), isNull);
      final throwing = CoachService(client: MockClient((_) async => throw Exception('offline')));
      expect(await throwing.fetch(albumId: 'a', member: 'm', language: 'en'), isNull);
    });
  });

  group('CoachCardsOverlay', () {
    testWidgets('shows "Missing: <title>" and tip, swipes to the next card', (tester) async {
      final res = CoachResponse.fromJson(jsonDecode(_sample));
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CoachCardsOverlay(
                cards: res.cards,
                missingLabel: CameraStrings.of('en').missing,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Missing: Dadi with the kids'), findsOneWidget);
      expect(find.text('Ask the kids to sit around Dadi near the diyas.'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Missing: The rangoli'), findsOneWidget);

      final currentCard = find.ancestor(of: find.text('Missing: The rangoli'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: currentCard, matching: find.byIcon(Icons.close_rounded)));
      expect(dismissed, isTrue);
    });

    testWidgets('renders nothing without cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CoachCardsOverlay(cards: [], missingLabel: 'Missing'),
        ),
      );
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('uses the member language label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachCardsOverlay(
              cards: const [CoachCard(title: 'दादी', tip: '')],
              missingLabel: CameraStrings.of('hi').missing,
            ),
          ),
        ),
      );
      expect(find.text('छूट गया: दादी'), findsOneWidget);
    });
  });
}
