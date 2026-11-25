import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/reel/config.dart';
import 'package:immich_mobile/memories/reel/models/edl.dart';
import 'package:immich_mobile/memories/reel/models/reel_draft.dart';
import 'package:immich_mobile/memories/reel/models/reel_models.dart';
import 'package:immich_mobile/memories/reel/reel_strings.dart';
import 'package:immich_mobile/memories/reel/services/reel_api.dart';
import 'package:immich_mobile/memories/reel/widgets/live_reel_preview.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum _Busy { none, updating, sharing, exporting }

/// Simple editor for one cut of a reel: live preview on top, a timeline strip
/// of clips (long-press to drag, tap to select), per-clip swap / remove /
/// caption, music mood chips, then "Update reel", "Share" and an OTIO export.
///
/// Plain widget (no auto_route annotation) so the integration layer can wrap it
/// in whatever route it likes.
class ReelEditorPage extends ConsumerStatefulWidget {
  const ReelEditorPage({
    super.key,
    required this.reelId,
    required this.cut,
    this.language = kReelDefaultLanguage,
    this.memberName,
    this.previewUrl,
    this.finalUrl,
    this.api,
    this.onUpdated,
    this.onShared,
  });

  final String reelId;

  /// Cut index (0-based) as used by `/v1/reels/{id}/cuts/{cut}`.
  final int cut;
  final String language;

  /// Sent with `POST /shared` for analytics.
  final String? memberName;

  /// Server preview mp4 for the fallback player.
  final String? previewUrl;

  /// Known final mp4 URL; otherwise Share asks the server to render it.
  final String? finalUrl;
  final ReelApi? api;

  /// Called after a successful "Update reel" with the new cut URLs.
  final ValueChanged<ReelCutResult>? onUpdated;

  /// Called after the share sheet closes with a share (target = app id if known).
  final ValueChanged<String>? onShared;

  @override
  ConsumerState<ReelEditorPage> createState() => _ReelEditorPageState();
}

class _ReelEditorPageState extends ConsumerState<ReelEditorPage> {
  static final Logger _log = Logger('MemoriesReelEditor');

  final LiveReelPreviewController _preview = LiveReelPreviewController();
  final Map<int, TextEditingController> _captionControllers = {};

  late int _cut = widget.cut;
  late String? _previewUrl = widget.previewUrl;
  late String? _finalUrl = widget.finalUrl;
  Edl? _edl;
  ReelDraft? _draft;
  Object? _loadError;
  int? _selected;
  List<ClipAlternative>? _alternatives;
  bool _loadingAlternatives = false;
  _Busy _busy = _Busy.none;

  ReelStrings get _s => ReelStrings.of(widget.language);
  ReelApi get _api => widget.api ?? ref.read(memoriesReelApiProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadEdl());
  }

  @override
  void dispose() {
    for (final c in _captionControllers.values) {
      c.dispose();
    }
    _preview.dispose();
    super.dispose();
  }

  Future<void> _loadEdl() async {
    setState(() => _loadError = null);
    try {
      final edl = await _api.fetchEdl(widget.reelId, _cut);
      if (!mounted) {
        return;
      }
      _applyEdl(edl);
    } catch (e) {
      _log.info('EDL load failed: $e');
      if (mounted) {
        setState(() => _loadError = e);
      }
    }
  }

  void _applyEdl(Edl edl) {
    for (final c in _captionControllers.values) {
      c.dispose();
    }
    _captionControllers.clear();
    setState(() {
      _edl = edl;
      _draft = ReelDraft.fromEdl(edl);
      _selected = null;
      _alternatives = null;
    });
  }

  // ------------------------------------------------------------------ actions

  void _select(int index) {
    setState(() {
      _selected = _selected == index ? null : index;
      _alternatives = null;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    final draft = _draft!;
    final selectedUid = _selected != null ? draft.clips[_selected!].uid : null;
    setState(() {
      draft.moveTo(oldIndex, newIndex);
      if (selectedUid != null) {
        _selected = draft.clips.indexWhere((c) => c.uid == selectedUid);
      }
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _remove(int index) {
    final draft = _draft!;
    final removed = draft.remove(index);
    final messenger = ScaffoldMessenger.of(context);
    if (removed == null) {
      _snack(_s.cantRemoveLast);
      return;
    }
    setState(() {
      _selected = null;
      _alternatives = null;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_s.removed, style: const TextStyle(fontSize: 18)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: _s.undo,
            onPressed: () {
              if (mounted) {
                setState(() => draft.restore(index, removed));
              }
            },
          ),
        ),
      );
  }

  Future<void> _loadAlternatives(int index) async {
    final draft = _draft!;
    setState(() {
      _loadingAlternatives = true;
      _alternatives = null;
    });
    try {
      final alts = await _api.alternatives(widget.reelId, _cut, draft.clips[index].slot);
      if (mounted && _selected == index) {
        setState(() => _alternatives = alts.where((a) => a.assetId != draft.clips[index].assetId).toList());
      }
    } catch (e) {
      if (mounted) {
        _snack(_s.error(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAlternatives = false);
      }
    }
  }

  void _swap(int index, ClipAlternative alt) {
    setState(() {
      _draft!.swap(index, alt);
      _alternatives = _alternatives?.where((a) => a.assetId != alt.assetId).toList();
    });
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _update() async {
    final draft = _draft;
    if (draft == null || _busy != _Busy.none) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = _Busy.updating);
    await _preview.pause();
    try {
      final res = await _api.edit(widget.reelId, cut: _cut, clips: draft.toEdits(), musicMood: draft.moodToSend);
      _cut = res.cut;
      _previewUrl = res.previewUrl ?? _previewUrl;
      _finalUrl = res.finalReady ? res.finalUrl : null;
      widget.onUpdated?.call(res);
      Edl? fresh;
      try {
        fresh = await _api.fetchEdl(widget.reelId, _cut);
      } catch (e) {
        _log.info('EDL refresh failed after edit: $e');
      }
      if (!mounted) {
        return;
      }
      if (fresh != null) {
        _applyEdl(fresh); // LiveReelPreview reloads when its edl changes.
      } else {
        draft.dirty = false;
        await _preview.reload(previewUrl: _previewUrl);
      }
      _snack(_s.updated);
    } catch (e) {
      if (mounted) {
        _snack(_s.error(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = _Busy.none);
      }
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final o = box.localToGlobal(Offset.zero);
      return Rect.fromLTWH(o.dx, o.dy + box.size.height - 120, box.size.width, 120);
    }
    return null;
  }

  Future<void> _share() async {
    if (_busy != _Busy.none) {
      return;
    }
    if (_draft?.dirty ?? false) {
      // Apply pending edits first so we share what the user sees.
      await _update();
      if (!mounted || (_draft?.dirty ?? false)) {
        return;
      }
    }
    setState(() => _busy = _Busy.sharing);
    await _preview.pause();
    try {
      var url = _finalUrl;
      if (url == null) {
        final res = await _api.renderFinal(widget.reelId, _cut);
        url = res.finalUrl!;
        _finalUrl = url;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/memories_reel_${_safe(widget.reelId)}_${_cut}_${url.hashCode.toUnsigned(32)}.mp4');
      if (!file.existsSync() || file.lengthSync() == 0) {
        await _api.downloadTo(Uri.parse(url), file);
      }
      if (!mounted) {
        return;
      }
      final title = _edl?.title;
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'video/mp4')],
        text: title != null && title.isNotEmpty ? title : null,
        sharePositionOrigin: _shareOrigin(),
      );
      if (result.status != ShareResultStatus.dismissed) {
        final target = result.raw.isNotEmpty ? result.raw : 'share_sheet';
        unawaited(_api.markShared(widget.reelId, cut: _cut, target: target, memberName: widget.memberName));
        widget.onShared?.call(target);
      }
    } catch (e) {
      _log.info('share failed: $e');
      if (mounted) {
        _snack(_s.error(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = _Busy.none);
      }
    }
  }

  Future<void> _exportOtio() async {
    if (_busy != _Busy.none) {
      return;
    }
    setState(() => _busy = _Busy.exporting);
    try {
      final dir = await getTemporaryDirectory();
      final name = _safe(_edl?.title.isNotEmpty == true ? _edl!.title : 'memories_reel');
      final file = await _api.downloadOtio(widget.reelId, _cut, File('${dir.path}/${name}_cut${_cut + 1}.otio'));
      if (!mounted) {
        return;
      }
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '${_edl?.title ?? 'Memories'} (.otio)',
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (e) {
      _log.info('otio export failed: $e');
      if (mounted) {
        _snack(_s.error(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = _Busy.none);
      }
    }
  }

  static String _safe(String s) {
    final out = s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return out.length > 40 ? out.substring(0, 40) : out;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontSize: 18))));
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_s.discardTitle),
        content: Text(_s.discardBody, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(_s.keepEditing)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(_s.discard)),
        ],
      ),
    );
    return ok ?? false;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final dirty = _draft?.dirty ?? false;
    return PopScope(
      canPop: !dirty || _busy == _Busy.updating,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_s.editTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 28),
              onSelected: (v) {
                if (v == 'otio') {
                  unawaited(_exportOtio());
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'otio',
                  child: ListTile(
                    leading: const Icon(Icons.movie_edit),
                    title: Text(_s.exportOtio, style: const TextStyle(fontSize: 18)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(bottom: false, child: _content(context)),
        // As bottomNavigationBar so SnackBars (e.g. "Undo") float above the buttons.
        bottomNavigationBar: SafeArea(top: false, child: _bottomBar(context, dirty)),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final draft = _draft;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: SizedBox(
            height: (height * 0.42).clamp(260.0, 520.0),
            child: _edl == null && _loadError == null
                ? const AspectRatio(
                    aspectRatio: 9 / 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                  )
                : LiveReelPreview(
                    reelId: widget.reelId,
                    cut: _cut,
                    edl: _edl,
                    previewUrl: _previewUrl,
                    api: widget.api,
                    controller: _preview,
                    language: widget.language,
                  ),
          ),
        ),
        if (_loadError != null) _loadErrorCard(theme),
        if (draft != null) ...[
          _sectionTitle(theme, '${_s.clip} · ${draft.clips.length}', _s.reorderHint),
          _timelineStrip(theme, draft),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _selected != null && _selected! < draft.clips.length
                ? _clipPanel(theme, draft, _selected!)
                : const SizedBox(width: double.infinity),
          ),
          _sectionTitle(theme, _s.music, null),
          _moodChips(theme, draft),
        ],
      ],
    );
  }

  Widget _loadErrorCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(_s.error(_loadError!), style: const TextStyle(fontSize: 18))),
              TextButton(onPressed: () => unawaited(_loadEdl()), child: Text(_s.tryAgain, style: const TextStyle(fontSize: 18))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, String? hint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 22)),
          const Spacer(),
          if (hint != null)
            Flexible(
              flex: 3,
              child: Text(
                hint,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timelineStrip(ThemeData theme, ReelDraft draft) {
    return SizedBox(
      height: 142,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: draft.clips.length,
        onReorderItem: _reorder,
        proxyDecorator: (child, _, animation) => ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.08).animate(animation),
          child: Material(color: Colors.transparent, elevation: 8, child: child),
        ),
        itemBuilder: (context, i) {
          final clip = draft.clips[i];
          final selected = _selected == i;
          return Padding(
            key: ValueKey(clip.uid),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Semantics(
              button: true,
              selected: selected,
              label: '${_s.clip} ${i + 1}${clip.isVideo ? ', ${_s.video}' : ''}${clip.caption != null ? ', ${clip.caption}' : ''}',
              child: GestureDetector(
                onTap: () => _select(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 86,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? theme.colorScheme.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _poster(clip.posterUrl, theme),
                        Positioned(left: 6, top: 6, child: _badge('${i + 1}')),
                        if (clip.isVideo)
                          const Positioned(
                            right: 6,
                            bottom: 6,
                            child: Icon(Icons.videocam_rounded, color: Colors.white, size: 22, shadows: [Shadow(blurRadius: 4)]),
                          ),
                        if (clip.caption != null)
                          const Positioned(
                            left: 6,
                            bottom: 6,
                            child: Icon(Icons.subtitles_rounded, color: Colors.white, size: 20, shadows: [Shadow(blurRadius: 4)]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badge(String text) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _poster(String url, ThemeData theme) {
    if (url.isEmpty) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_outlined, size: 32),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined, size: 32),
      ),
    );
  }

  TextEditingController _captionController(DraftClip clip) =>
      _captionControllers.putIfAbsent(clip.uid, () => TextEditingController(text: clip.caption ?? ''));

  Widget _clipPanel(ThemeData theme, ReelDraft draft, int index) {
    final clip = draft.clips[index];
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('panel${clip.uid}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_s.clip} ${index + 1}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _captionController(clip),
                style: const TextStyle(fontSize: 20, height: 1.3),
                minLines: 1,
                maxLines: 3,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _s.caption,
                  hintText: _s.captionHint,
                  labelStyle: const TextStyle(fontSize: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onChanged: (v) => setState(() => draft.setCaption(index, v)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: _bigButton,
                      onPressed: _loadingAlternatives ? null : () => unawaited(_loadAlternatives(index)),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: Text(_s.swap),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _bigButton.copyWith(foregroundColor: WidgetStatePropertyAll(scheme.error)),
                      onPressed: () => _remove(index),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(_s.remove),
                    ),
                  ),
                ],
              ),
              if (_loadingAlternatives)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_alternatives != null) ...[
                const SizedBox(height: 14),
                if (_alternatives!.isEmpty)
                  Text(_s.noAlternatives, style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant))
                else
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _alternatives!.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final alt = _alternatives![i];
                        return Tooltip(
                          message: alt.why ?? '',
                          child: Semantics(
                            button: true,
                            label: '${_s.swap} ${i + 1}${alt.why != null ? ', ${alt.why}' : ''}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _swap(index, alt),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(width: 88, child: _poster(alt.posterUrl, theme)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final ButtonStyle _bigButton = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );

  Widget _moodChips(ThemeData theme, ReelDraft draft) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final m in kReelMusicMoods)
            ChoiceChip(
              label: Text(_s.mood(m)),
              labelStyle: const TextStyle(fontSize: 18),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              selected: draft.mood == m,
              onSelected: (on) => setState(() => draft.setMood(on ? m : draft.initialMood)),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, bool dirty) {
    final theme = Theme.of(context);
    final ready = _draft != null;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: _bigButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60))),
                onPressed: ready && dirty && _busy == _Busy.none ? () => unawaited(_update()) : null,
                icon: _busy == _Busy.updating ? _spinner(theme.colorScheme.onPrimary) : const Icon(Icons.auto_awesome_rounded),
                label: Text(_busy == _Busy.updating ? _s.updating : _s.updateReel, style: const TextStyle(fontSize: 19)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: _bigButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60))),
                onPressed: _busy == _Busy.none ? () => unawaited(_share()) : null,
                icon: _busy == _Busy.sharing || _busy == _Busy.exporting
                    ? _spinner(theme.colorScheme.primary)
                    : const Icon(Icons.ios_share_rounded),
                label: Text(_s.share, style: const TextStyle(fontSize: 19)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner(Color color) =>
      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: color));
}
