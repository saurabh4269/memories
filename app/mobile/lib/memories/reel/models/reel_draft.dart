import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';

/// One clip in the editor's working copy.
class DraftClip {
  DraftClip({
    required this.uid,
    required this.assetId,
    required this.isVideo,
    required this.posterUrl,
    required this.slot,
    this.inS,
    this.outS,
    this.holdS,
    this.durationS,
    this.caption,
    this.originalCaption,
  });

  factory DraftClip.fromEdl(EdlClip c, int slot, int uid) => DraftClip(
    uid: uid,
    assetId: c.assetId,
    isVideo: c.isVideo,
    posterUrl: c.posterUrl,
    slot: slot,
    inS: c.isVideo ? c.inS : null,
    outS: c.isVideo ? c.outS : null,
    holdS: c.isVideo ? null : (c.holdS ?? c.durationS),
    durationS: c.durationS,
    caption: c.caption,
    originalCaption: c.caption,
  );

  /// Stable identity for reorderable list keys.
  final int uid;
  String assetId;
  bool isVideo;
  String posterUrl;

  /// Position of this clip in the last saved EDL (the `slot` for alternatives).
  final int slot;
  double? inS;
  double? outS;
  double? holdS;
  double? durationS;
  String? caption;
  final String? originalCaption;

  ClipEdit toEdit() => ClipEdit(
    assetId: assetId,
    inS: isVideo ? inS : null,
    outS: isVideo ? outS : null,
    holdS: isVideo ? null : holdS,
    // Send the caption only if it exists or was cleared, so the server keeps its own otherwise.
    caption: caption ?? (originalCaption != null ? '' : null),
  );
}

/// The editor's mutable working copy of a cut (pure Dart, unit tested).
class ReelDraft {
  ReelDraft.fromEdl(Edl edl) : clips = [for (var i = 0; i < edl.clips.length; i++) DraftClip.fromEdl(edl.clips[i], i, i)], _nextUid = edl.clips.length,
      initialMood = edl.music?.mood,
      mood = edl.music?.mood;

  final List<DraftClip> clips;
  int _nextUid;
  final String? initialMood;
  String? mood;
  bool dirty = false;

  /// Applies a legacy `onReorder` move (its `newIndex` counts the item still in place).
  void reorder(int oldIndex, int newIndex) => moveTo(oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex);

  /// Moves clip [oldIndex] so it ends up at [targetIndex] (`onReorderItem` semantics).
  void moveTo(int oldIndex, int targetIndex) {
    if (oldIndex < 0 || oldIndex >= clips.length) {
      return;
    }
    final target = targetIndex.clamp(0, clips.length - 1);
    if (target == oldIndex) {
      return;
    }
    clips.insert(target, clips.removeAt(oldIndex));
    dirty = true;
  }

  /// Removes clip [index]; returns it (for undo) or null if it is the last one.
  DraftClip? remove(int index) {
    if (clips.length <= 1 || index < 0 || index >= clips.length) {
      return null;
    }
    dirty = true;
    return clips.removeAt(index);
  }

  void restore(int index, DraftClip clip) {
    clips.insert(index.clamp(0, clips.length), clip);
    dirty = true;
  }

  /// Replaces the asset in clip [index] with [alt], keeping its slot, length and caption.
  void swap(int index, ClipAlternative alt) {
    final c = clips[index];
    if (c.assetId == alt.assetId) {
      return;
    }
    final altIsVideo = alt.type == 'video';
    final length = c.durationS ?? c.holdS;
    c
      ..assetId = alt.assetId
      ..posterUrl = alt.posterUrl
      ..isVideo = altIsVideo
      // Server picks the best window of a new video; a new photo keeps the slot's length.
      ..inS = null
      ..outS = null
      ..holdS = altIsVideo ? null : length;
    dirty = true;
  }

  void setCaption(int index, String text) {
    final t = text.trim();
    clips[index].caption = t.isEmpty ? null : text;
    dirty = true;
  }

  void setMood(String? m) {
    if (m == mood) {
      return;
    }
    mood = m;
    dirty = true;
  }

  int newUid() => _nextUid++;

  /// Mood to send with the edit, or null to keep the current music.
  String? get moodToSend => mood != initialMood ? mood : null;

  List<ClipEdit> toEdits() => [for (final c in clips) c.toEdit()];
}
