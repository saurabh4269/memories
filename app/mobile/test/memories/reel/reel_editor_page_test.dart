import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';
import 'package:immich_mobile/memories/reel/reel_editor_page.dart';
import 'package:immich_mobile/memories/reel/reel_strings.dart';
import 'package:immich_mobile/memories/reel/services/reel_api.dart';

class _FakeApi extends ReelApi {
  int edlCalls = 0;
  List<ClipEdit>? lastEdit;
  String? lastMood;

  @override
  Future<Edl> fetchEdl(String reelId, int cut) async {
    edlCalls++;
    return Edl.fromJson({
      'cut': cut,
      'title': 'Test',
      'clips': [
        for (final id in ['a', 'b', 'c']) {'asset_id': id, 'type': 'photo', 'media_url': '', 'hold_s': 2},
      ],
    });
  }

  @override
  Future<List<ClipAlternative>> alternatives(String reelId, int cut, int slot) async => [
    const ClipAlternative(assetId: 'z', posterUrl: '', why: 'Brighter'),
  ];

  @override
  Future<ReelCutResult> edit(
    String reelId, {
    required int cut,
    required List<ClipEdit> clips,
    String? musicMood,
    String? title,
  }) async {
    lastEdit = clips;
    lastMood = musicMood;
    return ReelCutResult(cut: cut, previewUrl: 'p');
  }
}

void main() {
  testWidgets('editor: select, swap, remove, mood, update', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _FakeApi();
    // The preview ticker never settles, so step frames explicitly.
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    const s = ReelStrings.en;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReelEditorPage(reelId: 'r1', cut: 0, language: 'en-IN', api: api),
        ),
      ),
    );
    await settle();
    await settle();

    expect(find.text('${s.clip} · 3'), findsOneWidget);
    final update = find.widgetWithText(FilledButton, s.updateReel);
    expect(tester.widget<FilledButton>(update).onPressed, isNull, reason: 'nothing to update yet');

    // Select clip 2, swap it for the alternative.
    await tester.tap(find.bySemanticsLabel(RegExp('^${s.clip} 2')));
    await settle();
    await tester.ensureVisible(find.text(s.swap));
    await settle();
    await tester.tap(find.text(s.swap));
    await settle();
    await tester.ensureVisible(find.bySemanticsLabel(RegExp('^${s.swap} 1')));
    await settle();
    await tester.tap(find.bySemanticsLabel(RegExp('^${s.swap} 1')));
    await settle();

    // Caption on clip 2.
    await tester.enterText(find.byType(TextField), 'नमस्ते');
    await settle();

    // Remove clip 1.
    await tester.ensureVisible(find.bySemanticsLabel(RegExp('^${s.clip} 1')));
    await settle();
    await tester.tap(find.bySemanticsLabel(RegExp('^${s.clip} 1')));
    await settle();
    await tester.ensureVisible(find.text(s.remove));
    await settle();
    await tester.tap(find.text(s.remove));
    await settle();
    expect(find.text('${s.clip} · 2'), findsOneWidget);

    // Change mood.
    await tester.ensureVisible(find.text(s.mood('calm')));
    await settle();
    await tester.tap(find.text(s.mood('calm')));
    await settle();

    expect(tester.widget<FilledButton>(update).onPressed, isNotNull);
    await tester.tap(update);
    await settle();
    await settle();

    expect(api.lastEdit!.map((e) => e.toJson()).toList(), [
      {'asset_id': 'z', 'hold_s': 2.0, 'caption': 'नमस्ते'},
      {'asset_id': 'c', 'hold_s': 2.0},
    ]);
    expect(api.lastMood, 'calm');
    expect(api.edlCalls, greaterThanOrEqualTo(2), reason: 'EDL refetched after the edit');

    // Dispose the page (stops the preview ticker).
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
