import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/reel_draft.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';

Edl _edl() => Edl.fromJson({
  'music': {'url': 'm', 'mood': 'joyful'},
  'clips': [
    {'asset_id': 'a', 'type': 'photo', 'media_url': 'a', 'poster_url': 'pa', 'hold_s': 2.5, 'caption': 'Hi'},
    {'asset_id': 'b', 'type': 'video', 'media_url': 'b', 'poster_url': 'pb', 'in_s': 1, 'out_s': 4},
    {'asset_id': 'c', 'type': 'photo', 'media_url': 'c', 'poster_url': 'pc', 'duration_s': 2},
  ],
});

List<String> _ids(ReelDraft d) => d.clips.map((c) => c.assetId).toList();

void main() {
  test('starts clean with EDL order and slots', () {
    final d = ReelDraft.fromEdl(_edl());
    expect(_ids(d), ['a', 'b', 'c']);
    expect(d.clips.map((c) => c.slot), [0, 1, 2]);
    expect(d.dirty, isFalse);
    expect(d.moodToSend, isNull);
  });

  test('moveTo and legacy reorder agree', () {
    final d = ReelDraft.fromEdl(_edl())..moveTo(0, 2);
    expect(_ids(d), ['b', 'c', 'a']);
    expect(d.dirty, isTrue);
    final legacy = ReelDraft.fromEdl(_edl())..reorder(0, 3); // onReorder counts the moving item
    expect(_ids(legacy), ['b', 'c', 'a']);
    final back = ReelDraft.fromEdl(_edl())..reorder(2, 0);
    expect(_ids(back), ['c', 'a', 'b']);
    final noop = ReelDraft.fromEdl(_edl())..moveTo(1, 1);
    expect(noop.dirty, isFalse);
  });

  test('remove keeps at least one clip and supports undo', () {
    final d = ReelDraft.fromEdl(_edl());
    final removed = d.remove(1)!;
    expect(_ids(d), ['a', 'c']);
    d.restore(1, removed);
    expect(_ids(d), ['a', 'b', 'c']);
    d
      ..remove(0)
      ..remove(0);
    expect(d.remove(0), isNull);
    expect(_ids(d), ['c']);
  });

  test('swap keeps slot, length and caption; clears video window', () {
    final d = ReelDraft.fromEdl(_edl())
      ..swap(0, const ClipAlternative(assetId: 'z', posterUrl: 'pz', type: 'video'))
      ..swap(1, const ClipAlternative(assetId: 'y', posterUrl: 'py'));
    final z = d.clips[0];
    expect(z.assetId, 'z');
    expect(z.slot, 0);
    expect(z.caption, 'Hi');
    expect(z.toEdit().toJson(), {'asset_id': 'z', 'caption': 'Hi'});
    final y = d.clips[1];
    expect(y.isVideo, isFalse);
    expect(y.toEdit().toJson(), {'asset_id': 'y', 'hold_s': 3.0});
  });

  test('edits payload: video window, photo hold, cleared caption', () {
    final d = ReelDraft.fromEdl(_edl())
      ..setCaption(0, '  ')
      ..setCaption(2, 'नमस्ते');
    expect(d.toEdits().map((e) => e.toJson()).toList(), [
      {'asset_id': 'a', 'hold_s': 2.5, 'caption': ''},
      {'asset_id': 'b', 'in_s': 1.0, 'out_s': 4.0},
      {'asset_id': 'c', 'hold_s': 2.0, 'caption': 'नमस्ते'},
    ]);
  });

  test('mood is sent only when changed', () {
    final d = ReelDraft.fromEdl(_edl())..setMood('joyful');
    expect(d.dirty, isFalse);
    d.setMood('calm');
    expect(d.moodToSend, 'calm');
    d.setMood('joyful');
    expect(d.moodToSend, isNull);
  });
}
