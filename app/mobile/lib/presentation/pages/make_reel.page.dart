import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/memories/design/design.dart';
import 'package:immich_mobile/memories/home/recent_reels.dart';
import 'package:immich_mobile/memories/post/post_to_socials_sheet.dart';
import 'package:immich_mobile/memories/reel/reel.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const String kDirectorBaseUrl = String.fromEnvironment(
  'DIRECTOR_URL',
  defaultValue: 'https://memories-3870f5.centralindia.cloudapp.azure.com/director',
);

class ReelCut {
  final String title;
  final String why;
  final String previewUrl;
  final String coverUrl;
  final String? finalUrl;

  const ReelCut({
    required this.title,
    required this.why,
    required this.previewUrl,
    required this.coverUrl,
    this.finalUrl,
  });

  factory ReelCut.fromJson(Map<String, dynamic> json) => ReelCut(
    title: json['title']?.toString() ?? '',
    why: json['why']?.toString() ?? '',
    previewUrl: _absolute(json['preview_url']?.toString() ?? ''),
    coverUrl: _absolute(json['cover_url']?.toString() ?? ''),
    finalUrl: json['final_url'] == null ? null : _absolute(json['final_url'].toString()),
  );
}

String _absolute(String url) {
  if (url.isEmpty || url.startsWith('http')) {
    return url;
  }
  return '$kDirectorBaseUrl${url.startsWith('/') ? '' : '/'}$url';
}

class ReelResult {
  final String reelId;
  final List<ReelCut> cuts;
  final Map<String, dynamic> timings;
  final List<dynamic> trace;
  final String mode;

  const ReelResult({
    required this.reelId,
    required this.cuts,
    required this.timings,
    required this.trace,
    required this.mode,
  });

  factory ReelResult.fromJson(Map<String, dynamic> json) => ReelResult(
    reelId: json['reel_id']?.toString() ?? '',
    cuts: ((json['cuts'] as List?) ?? const [])
        .map((c) => ReelCut.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
    timings: _flattenTimings(json['timings']),
    trace: _flattenTrace(json['trace']),
    mode: json['mode']?.toString() ?? 'normal',
  );
}

Map<String, dynamic> _flattenTimings(dynamic raw) {
  final out = <String, dynamic>{};
  if (raw is! Map) {
    return out;
  }
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is num || value is String) {
      out[entry.key.toString()] = value;
    } else if (value is Map && entry.key == 'stages_ms') {
      for (final stage in value.entries) {
        out['${stage.key}'] = '${stage.value} ms';
      }
    } else if (value is List && entry.key == 'sarvam_calls') {
      for (final call in value) {
        if (call is Map) {
          out['Sarvam ${call['kind']} (${call['model']})'] = '${call['ms']} ms';
        }
      }
    }
  }
  return out;
}

List<dynamic> _flattenTrace(dynamic raw) {
  if (raw is List) {
    return raw;
  }
  if (raw is! Map) {
    return const [];
  }
  final out = <dynamic>[];
  final events = raw['events'];
  if (events is List) {
    out.addAll(events);
  }
  for (final entry in raw.entries) {
    if (entry.key == 'events' || entry.value == null) {
      continue;
    }
    final value = entry.value;
    if (value is Map) {
      final parts = value.entries
          .where((e) => e.value != null && e.value is! Map && !(e.value is List && (e.value as List).isEmpty))
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      out.add({'step': entry.key, 'detail': parts});
    } else {
      out.add({'step': entry.key, 'detail': value.toString()});
    }
  }
  return out;
}

class DirectorClient {
  final http.Client _client = http.Client();

  Uri _uri(String path) => Uri.parse('$kDirectorBaseUrl$path');

  Future<ReelResult> createReel({
    required String albumId,
    required String prompt,
    required String destination,
    required String memberName,
    required String language,
  }) async {
    final response = await _client
        .post(
          _uri('/v1/reels'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'album_id': albumId,
            'prompt': prompt,
            'destination': destination,
            'member_name': memberName,
            'language': language,
          }),
        )
        .timeout(const Duration(minutes: 5));
    if (response.statusCode >= 300) {
      throw HttpException('Director returned ${response.statusCode}');
    }
    return ReelResult.fromJson(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<String> finalizeCut(String reelId, int cut) async {
    final response = await _client.post(_uri('/v1/reels/$reelId/final/$cut')).timeout(const Duration(minutes: 3));
    if (response.statusCode >= 300) {
      throw HttpException('Director returned ${response.statusCode}');
    }
    final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final url = body is Map ? (body['url'] ?? body['final_url'] ?? body['video_url'])?.toString() : null;
    return _absolute(url ?? '');
  }

  Future<File> download(String url, String name) async {
    final response = await _client.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
    if (response.statusCode >= 300) {
      throw HttpException('Download failed ${response.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  Future<void> markShared(String reelId, {required int cut, required String target, String? memberName}) async {
    await _client
        .post(
          _uri('/v1/reels/$reelId/shared'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'cut': cut, 'target': target, 'member_name': memberName}),
        )
        .timeout(const Duration(seconds: 20));
  }
}

const _destinations = {'wa_status': 'WA Status', 'insta_reel': 'Insta Reel', 'insta_story': 'Insta Story'};
const _languages = {'hi': 'हिंदी', 'en': 'English'};

/// Visual metadata for destinations (platform-hued tiles, not official logos).
const _destinationStyle = <String, (String, String, IconData, List<Color>)>{
  'wa_status': ('WhatsApp Status', '30s · 9:16', Icons.chat_rounded, [Color(0xFF1FA855), Color(0xFF25D366)]),
  'insta_reel': (
    'Instagram Reel',
    'Up to 90s',
    Icons.movie_filter_rounded,
    [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
  ),
  'insta_story': ('Instagram Story', '15s · 9:16', Icons.amp_stories_rounded, [Color(0xFF8134AF), Color(0xFF515BD4)]),
};

/// Pulls `stage -> ms` out of the flattened timings map (values look like "1234 ms").
Map<String, int> _stagesFrom(Map<String, dynamic> timings) {
  final out = <String, int>{};
  final re = RegExp(r'^(\d+)\s*ms$');
  for (final e in timings.entries) {
    if (e.key.startsWith('Sarvam')) continue;
    final m = re.firstMatch(e.value.toString().trim());
    if (m != null) out[e.key] = int.parse(m.group(1)!);
  }
  return out;
}

class MakeReelPage extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;

  const MakeReelPage({super.key, required this.albumId, this.albumName = ''});

  @override
  ConsumerState<MakeReelPage> createState() => _MakeReelPageState();
}

class _MakeReelPageState extends ConsumerState<MakeReelPage> {
  final _director = DirectorClient();
  final _speaker = ConfirmationSpeaker(ReelApi());
  final _promptController = TextEditingController();
  String _destination = 'wa_status';
  String _language = 'hi';
  bool _loading = false;
  bool _done = false;
  ReelResult? _result;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  String? get _coverAssetId {
    final albums = ref.read(remoteAlbumProvider).albums;
    for (final a in albums) {
      if (a.id == widget.albumId) return a.thumbnailAssetId;
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _done = false;
      _result = null;
      _error = null;
    });
    final speakLanguage = _language == 'hi' ? 'hi-IN' : 'en-IN';
    final memberName = ref.read(currentUserProvider)?.name;
    unawaited(_speaker.prefetch(language: speakLanguage, name: memberName));
    try {
      final user = ref.read(currentUserProvider);
      final result = await _director.createReel(
        albumId: widget.albumId,
        prompt: _promptController.text.trim(),
        destination: _destination,
        memberName: user?.name ?? '',
        language: _language,
      );
      if (!mounted) return;
      StoryPacing.record(_stagesFrom(result.timings));
      addRecentReels([
        for (final c in result.cuts)
          RecentReel(
            reelId: result.reelId,
            title: c.title,
            why: c.why,
            coverUrl: c.coverUrl,
            previewUrl: c.previewUrl,
            albumName: widget.albumName,
            at: DateTime.now(),
          ),
      ]);
      unawaited(_speaker.speak(language: speakLanguage, name: memberName));
      // ProgressStory finishes its last steps, then calls _openResult.
      setState(() {
        _result = result;
        _done = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openResult() async {
    final result = _result;
    if (result == null || !mounted) return;
    final speakLanguage = _language == 'hi' ? 'hi-IN' : 'en-IN';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReelCutsPage(result: result, director: _director, destination: _destination, language: speakLanguage),
      ),
    );
    if (mounted) {
      setState(() {
        _loading = false;
        _done = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MemoriesTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final coverId = _coverAssetId;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(
          children: [
            if (coverId != null) ...[
              ClipRRect(
                borderRadius: MRadius.smAll,
                child: SizedBox(width: 40, height: 40, child: MPhoto(source: MPhotoSource.immich(coverId))),
              ),
              const SizedBox(width: MSpace.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MAKE A MEMORY', style: type.overline),
                  Text(
                    widget.albumName.isEmpty ? 'Your album' : widget.albumName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.title.copyWith(fontSize: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: MMotion.emphasised,
          child: _loading
              ? ListView(
                  key: const ValueKey('progress'),
                  padding: const EdgeInsets.fromLTRB(MSpace.gutter, MSpace.xs, MSpace.gutter, MSpace.xxl),
                  children: [
                    ProgressStory(
                      done: _done,
                      onFinished: _openResult,
                      header: PhotoHeroCard(
                        photo: coverId == null ? MStockPhotos.diwali : MPhotoSource.immich(coverId, large: true),
                        aspectRatio: 16 / 11,
                        kicker: 'In the edit',
                        title: 'Your memory is being cut',
                        subtitle: _promptController.text.trim().isEmpty ? null : '“${_promptController.text.trim()}”',
                      ),
                    ),
                  ],
                )
              : ListView(
                  key: const ValueKey('form'),
                  padding: const EdgeInsets.fromLTRB(MSpace.gutter, MSpace.xs, MSpace.gutter, MSpace.xxl),
                  children: [
                    _VoiceHero(
                      child: VoicePromptButton(
                        language: _language == 'hi' ? 'hi-IN' : 'en-IN',
                        onIntent: (intent) => setState(() {
                          final text = intent.request.isNotEmpty ? intent.request : intent.transcript;
                          if (text.isNotEmpty) {
                            _promptController.text = text;
                          }
                          final destination = intent.destination;
                          if (destination != null && _destinations.containsKey(destination)) {
                            _destination = destination;
                          }
                          if (_promptController.text.trim().isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: MSpace.lg),
                    Row(
                      children: [
                        Expanded(child: Divider(color: p.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: MSpace.sm),
                          child: Text('OR TYPE IT', style: type.overline),
                        ),
                        Expanded(child: Divider(color: p.line)),
                      ],
                    ),
                    const SizedBox(height: MSpace.md),
                    TextField(
                      controller: _promptController,
                      minLines: 2,
                      maxLines: 4,
                      style: type.body.copyWith(fontSize: 17),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Fun Diwali reel of the family dancing',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(left: 14, right: 8, bottom: 22),
                          child: Icon(Icons.edit_note_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: MSpace.section),
                    const SectionHeader(title: 'Where will you post it?', padding: EdgeInsets.zero),
                    const SizedBox(height: MSpace.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final key in _destinations.keys) ...[
                          if (key != _destinations.keys.first) const SizedBox(width: MSpace.xs + 2),
                          Expanded(
                            child: DestinationCard(
                              label: _destinationStyle[key]!.$1,
                              hint: _destinationStyle[key]!.$2,
                              icon: _destinationStyle[key]!.$3,
                              tileColors: _destinationStyle[key]!.$4,
                              selected: _destination == key,
                              onTap: () => setState(() => _destination = key),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: MSpace.section),
                    const SectionHeader(title: 'Language', padding: EdgeInsets.zero),
                    const SizedBox(height: MSpace.sm),
                    Wrap(
                      spacing: MSpace.xs + 2,
                      runSpacing: MSpace.xs + 2,
                      children: [
                        for (final entry in _languages.entries)
                          MemoriesChoiceChip(
                            label: entry.value,
                            selected: _language == entry.key,
                            onTap: () => setState(() => _language = entry.key),
                          ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: MSpace.lg),
                      Container(
                        padding: const EdgeInsets.all(MSpace.md),
                        decoration: BoxDecoration(color: p.sindoor.withValues(alpha: 0.1), borderRadius: MRadius.mdAll),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: p.sindoor),
                            const SizedBox(width: MSpace.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('The director could not finish', style: type.titleSans.copyWith(fontSize: 16)),
                                  const SizedBox(height: 2),
                                  Text(_error!, style: type.bodyMuted.copyWith(fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: MSpace.xxl),
                    PillButton(
                      label: 'Make my reels',
                      icon: Icons.auto_awesome_rounded,
                      glow: true,
                      height: 64,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: MSpace.sm),
                    Center(
                      child: Text('Two cuts, ready in about a minute', style: type.bodyMuted.copyWith(fontSize: 14)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Voice-first hero: warm glow panel that frames the mic.
class _VoiceHero extends StatelessWidget {
  final Widget child;
  const _VoiceHero({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return Container(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xl, MSpace.lg, MSpace.lg),
      decoration: BoxDecoration(
        borderRadius: MRadius.xlAll,
        border: Border.all(color: p.line),
        gradient: RadialGradient(
          center: const Alignment(0, 0.15),
          radius: 0.9,
          colors: [
            p.marigold.withValues(alpha: p.isDark ? 0.22 : 0.20),
            p.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DirectorSpark(size: 14),
              const SizedBox(width: 6),
              Text('YOUR DIRECTOR IS LISTENING', style: type.overline.copyWith(color: p.diya)),
            ],
          ),
          const SizedBox(height: MSpace.sm),
          Text(
            'What should your\nmemory feel like?',
            textAlign: TextAlign.center,
            style: type.headline.copyWith(fontSize: 28, height: 1.15),
          ),
          const SizedBox(height: 6),
          Text('बोलिए या लिखिए · Speak in Hindi or English', textAlign: TextAlign.center, style: type.bodyMuted),
          const SizedBox(height: MSpace.xl),
          child,
        ],
      ),
    );
  }
}

const _stageNames = <String, String>{
  'album_list': 'Opened the album',
  'voice_prompt': 'Understood your voice',
  'analysis': 'Watched every photo & video',
  'phash': 'Set aside near-duplicates',
  'team': 'Found your people',
  'plan': 'Wrote two storylines',
  'render_preview': 'Cut to the beat & rendered',
};

String _prettyStage(String key) {
  final known = _stageNames[key];
  if (known != null) return known;
  if (key.startsWith('render_segments_')) return 'Rendered clips · ${key.substring(16)}';
  if (key.startsWith('render_join_')) return 'Joined with music · ${key.substring(12)}';
  if (key.startsWith('analysis_')) return 'Analysis · ${key.substring(9).replaceAll('_', ' ')}';
  return key.replaceAll('_', ' ');
}

class ReelCutsPage extends StatefulWidget {
  final ReelResult result;
  final DirectorClient director;
  final String destination;
  final String language;

  const ReelCutsPage({
    super.key,
    required this.result,
    required this.director,
    required this.destination,
    this.language = 'hi-IN',
  });

  @override
  State<ReelCutsPage> createState() => _ReelCutsPageState();
}

class _ReelCutsPageState extends State<ReelCutsPage> {
  int? _busyCut;

  Future<void> _useCut(int index) async {
    final result = widget.result;
    setState(() => _busyCut = index);
    try {
      String url = '';
      try {
        url = await widget.director.finalizeCut(result.reelId, index);
      } catch (_) {}
      if (url.isEmpty) {
        url = result.cuts[index].previewUrl;
      }
      final file = await widget.director.download(url, 'memories_${result.reelId}_$index.mp4');
      unawaited(
        widget.director.markShared(result.reelId, cut: index, target: widget.destination).catchError((Object _) {}),
      );
      await Share.shareXFiles([XFile(file.path, mimeType: 'video/mp4')], text: result.cuts[index].title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyCut = null);
    }
  }

  void _openEditor(int i) {
    final result = widget.result;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReelEditorPage(
            reelId: result.reelId,
            cut: i,
            language: widget.language,
            previewUrl: result.cuts[i].previewUrl,
            finalUrl: result.cuts[i].finalUrl,
          ),
        ),
      ),
    );
  }

  void _openPreview(int i) {
    final result = widget.result;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(result.cuts[i].title),
              actions: [
                Builder(
                  builder: (ctx) => TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReelEditorPage(
                          reelId: result.reelId,
                          cut: i,
                          language: widget.language,
                          previewUrl: result.cuts[i].previewUrl,
                          finalUrl: result.cuts[i].finalUrl,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
            body: Center(
              child: LiveReelPreview(reelId: result.reelId, cut: i, previewUrl: result.cuts[i].previewUrl),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MemoriesTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final result = widget.result;
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - MSpace.gutter * 2 - MSpace.sm) / 2;
    final destination = _destinationStyle[widget.destination]?.$1 ?? 'your story';

    final stages = _stagesFrom(result.timings);
    final totalRaw = result.timings['total_ms'];
    final totalMs = totalRaw is num ? totalRaw.round() : null;
    final events = <TimelineEntry>[];
    for (final step in result.trace) {
      if (step is Map) {
        final title = (step['msg'] ?? step['step'] ?? step['name'] ?? step['stage'] ?? '').toString();
        final extras = step.entries
            .where(
              (e) => !const {'msg', 'step', 'name', 'stage', 'ms', 'duration_ms'}.contains(e.key) && e.value != null,
            )
            .map((e) => e.key == 'detail' ? '${e.value}' : '${e.key}: ${e.value}')
            .join(' · ');
        final ms = step['ms'] ?? step['duration_ms'];
        if (title.isEmpty && extras.isEmpty) continue;
        events.add(TimelineEntry(title.replaceAll('_', ' '), detail: extras, ms: ms is num ? ms.round() : null));
      } else {
        events.add(TimelineEntry(step.toString()));
      }
    }
    for (final e in result.timings.entries) {
      if (e.key.startsWith('Sarvam')) {
        final m = RegExp(r'^(\d+)').firstMatch(e.value.toString());
        events.add(TimelineEntry(e.key, ms: m == null ? null : int.parse(m.group(1)!)));
      }
    }

    return Scaffold(
      appBar: AppBar(toolbarHeight: 56),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.gutter, 0, MSpace.gutter, MSpace.xxxl),
        children: [
          FadeRise(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DirectorSpark(size: 14),
                    const SizedBox(width: 6),
                    Text('CUT FOR ${destination.toUpperCase()}', style: type.overline.copyWith(color: p.diya)),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Your two ', style: type.headline),
                      TextSpan(
                        text: 'reels',
                        style: type.headline.copyWith(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                          color: p.isDark ? p.marigold : p.plum,
                        ),
                      ),
                      TextSpan(text: ' are ready', style: type.headline),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('Same family, two moods. Pick one to post, or tweak it.', style: type.bodyMuted),
              ],
            ),
          ),
          if (result.mode != 'normal') ...[
            const SizedBox(height: MSpace.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: MSpace.sm),
              decoration: BoxDecoration(color: p.marigold.withValues(alpha: 0.16), borderRadius: MRadius.mdAll),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: p.diya),
                  const SizedBox(width: 10),
                  Text('Busy night: quick mode', style: type.titleSans.copyWith(fontSize: 15)),
                ],
              ),
            ),
          ],
          const SizedBox(height: MSpace.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < result.cuts.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: MSpace.sm),
                SizedBox(
                  width: cardWidth,
                  child: FadeRise(
                    index: i + 1,
                    child: ReelCard(
                      media: GestureDetector(
                        onTap: () => _openPreview(i),
                        child: AbsorbPointer(
                          child: _NetworkVideo(url: result.cuts[i].previewUrl, coverUrl: result.cuts[i].coverUrl),
                        ),
                      ),
                      badge: i == 0 ? 'Cut A' : 'Cut B',
                      title: result.cuts[i].title,
                      why: result.cuts[i].why,
                      highlighted: _busyCut == i,
                      busy: _busyCut == i,
                      onUse: _busyCut == null ? () => _useCut(i) : null,
                      onEdit: () => _openEditor(i),
                      onPost: () => showPostToSocialsSheet(
                        context,
                        reelId: result.reelId,
                        cut: i,
                        caption: result.cuts[i].title,
                        finalUrl: result.cuts[i].finalUrl,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: MSpace.xl),
          FadeRise(
            index: 3,
            child: DirectorTimeline(
              stages: [
                for (final e in stages.entries)
                  if (!e.key.startsWith('render_segments_') &&
                      !e.key.startsWith('render_join_') &&
                      !e.key.startsWith('analysis_'))
                    TimelineEntry(_prettyStage(e.key), ms: e.value),
              ],
              events: events,
              totalMs: totalMs,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkVideo extends StatefulWidget {
  final String url;
  final String coverUrl;

  const _NetworkVideo({required this.url, required this.coverUrl});

  @override
  State<_NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<_NetworkVideo> {
  bool _ready = false;

  Future<void> _onViewReady(NativeVideoPlayerController controller) async {
    controller.onPlaybackReady.addListener(() {
      if (mounted) setState(() => _ready = true);
      controller.play();
    });
    await controller.setLoop(true);
    await controller.setVolume(0);
    final source = await VideoSource.init(path: widget.url, type: VideoSourceType.network);
    await controller.loadVideoSource(source);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (widget.url.isNotEmpty) NativeVideoPlayerView(onViewReady: _onViewReady),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: _ready ? 0 : 1,
            child: widget.coverUrl.isNotEmpty
                ? Image.network(
                    widget.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ShimmerPlaceholder(borderRadius: BorderRadius.zero),
                  )
                : const ShimmerPlaceholder(borderRadius: BorderRadius.zero),
          ),
        ),
      ],
    );
  }
}
