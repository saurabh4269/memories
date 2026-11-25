import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/join/member_profile.dart';
import 'package:immich_mobile/memories/join/memories_ui.dart';
import 'package:immich_mobile/memories/post/post_api.dart';
import 'package:immich_mobile/memories/post/post_models.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows [PostToSocialsSheet] as a modal bottom sheet.
Future<void> showPostToSocialsSheet(
  BuildContext context, {
  required String reelId,
  required int cut,
  String caption = '',
  String? finalUrl,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (_) => PostToSocialsSheet(reelId: reelId, cut: cut, caption: caption, finalUrl: finalUrl),
);

/// Post a finished reel to connected Postiz channels (Bluesky/Telegram/
/// Discord…) and/or share the mp4 via the OS share sheet (WhatsApp/Instagram).
class PostToSocialsSheet extends ConsumerStatefulWidget {
  final String reelId;
  final int cut;
  final String caption;

  /// Final mp4 url if already known; otherwise it is requested from the director.
  final String? finalUrl;

  const PostToSocialsSheet({super.key, required this.reelId, required this.cut, this.caption = '', this.finalUrl});

  @override
  ConsumerState<PostToSocialsSheet> createState() => _PostToSocialsSheetState();
}

class _PostToSocialsSheetState extends ConsumerState<PostToSocialsSheet> {
  late final TextEditingController _caption = TextEditingController(text: widget.caption);
  late Future<List<PostChannel>> _channels;
  final Set<String> _selected = {};
  bool _posting = false;
  List<PostOutcome>? _results;
  String? _postError;
  String? _sharingTarget;

  @override
  void initState() {
    super.initState();
    _channels = _loadChannels();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<List<PostChannel>> _loadChannels() async {
    final list = await ref.read(postApiProvider).channels();
    if (_selected.isEmpty) {
      _selected.addAll(list.map((c) => c.id));
    }
    return list;
  }

  Future<void> _postNow(List<PostChannel> channels) async {
    setState(() {
      _posting = true;
      _postError = null;
      _results = null;
    });
    try {
      final results = await ref
          .read(postApiProvider)
          .post(reelId: widget.reelId, cut: widget.cut, channelIds: _selected.toList(), caption: _caption.text.trim());
      if (mounted) {
        setState(() => _results = results);
      }
    } on DirectorException catch (e) {
      if (mounted) {
        setState(() => _postError = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _postError = 'Could not post right now. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  Future<void> _shareVideo(String target) async {
    if (_sharingTarget != null) {
      return;
    }
    setState(() => _sharingTarget = target);
    final api = ref.read(postApiProvider);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final url = widget.finalUrl ?? await api.finalUrl(widget.reelId, widget.cut);
      final file = await api.downloadVideo(url, fileName: 'memories_${widget.reelId}_${widget.cut}.mp4');
      final text = _caption.text.trim();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'video/mp4')],
        text: text.isEmpty ? null : text,
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
      final member = ref.read(memberProfileProvider).valueOrNull?.name;
      unawaited(api.markShared(widget.reelId, widget.cut, target, memberName: member));
    } on DirectorException catch (e) {
      if (mounted) {
        showMemoriesSnack(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        showMemoriesSnack(context, 'Could not share the video. Please try again.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _sharingTarget = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MemoriesSheetHeader(title: 'Share your reel'),
            const MemoriesSectionTitle('Send to family'),
            _ShareRow(busyTarget: _sharingTarget, onShare: _shareVideo),
            const MemoriesSectionTitle('Post to socials'),
            FutureBuilder<List<PostChannel>>(
              future: _channels,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  final err = snapshot.error;
                  return _Notice(
                    icon: Icons.cloud_off_rounded,
                    text: err is DirectorException ? err.message : 'Could not load your channels.',
                    action: 'Try again',
                    onAction: () => setState(() => _channels = _loadChannels()),
                  );
                }
                final channels = snapshot.data ?? const <PostChannel>[];
                if (channels.isEmpty) {
                  return _Notice(
                    icon: Icons.link_off_rounded,
                    text:
                        'No channels connected yet.\nConnect channels in Postiz (Bluesky, Telegram, Discord…), then come back.',
                    action: 'Check again',
                    onAction: () => setState(() => _channels = _loadChannels()),
                  );
                }
                return _buildChannels(context, channels);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannels(BuildContext context, List<PostChannel> channels) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in channels)
          _ChannelTile(
            channel: c,
            selected: _selected.contains(c.id),
            outcome: results == null ? null : _outcomeFor(c, results),
            posting: _posting && _selected.contains(c.id),
            onChanged: _posting
                ? null
                : (v) => setState(() {
                    if (v) {
                      _selected.add(c.id);
                    } else {
                      _selected.remove(c.id);
                    }
                  }),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _caption,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 19),
          decoration: InputDecoration(
            labelText: 'Caption',
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        if (_postError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_postError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 18)),
          ),
        const SizedBox(height: 16),
        MemoriesBigButton(
          label: results == null ? 'Post now' : 'Post again',
          icon: Icons.send_rounded,
          busy: _posting,
          onPressed: _selected.isEmpty ? null : () => _postNow(channels),
        ),
      ],
    );
  }

  static PostOutcome? _outcomeFor(PostChannel c, List<PostOutcome> results) {
    for (final r in results) {
      if (r.channel == c.id || r.channel == c.name || r.channel.toLowerCase() == c.provider) {
        return r;
      }
    }
    return null;
  }
}

class _ShareRow extends StatelessWidget {
  final String? busyTarget;
  final void Function(String target) onShare;

  const _ShareRow({required this.busyTarget, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ShareTile(
            label: 'WhatsApp',
            icon: Icons.chat_rounded,
            color: const Color(0xFF25D366),
            busy: busyTarget == 'whatsapp',
            onTap: () => onShare('whatsapp'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShareTile(
            label: 'Instagram',
            icon: Icons.camera_alt_rounded,
            color: const Color(0xFFE1306C),
            busy: busyTarget == 'instagram',
            onTap: () => onShare('instagram'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShareTile(
            label: 'More',
            icon: Icons.ios_share_rounded,
            color: Theme.of(context).colorScheme.primary,
            busy: busyTarget == 'other',
            onTap: () => onShare('other'),
          ),
        ),
      ],
    );
  }
}

class _ShareTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool busy;
  final VoidCallback onTap;

  const _ShareTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color,
                child: busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                      )
                    : Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final PostChannel channel;
  final bool selected;
  final bool posting;
  final PostOutcome? outcome;
  final ValueChanged<bool>? onChanged;

  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.posting,
    required this.outcome,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = channel.avatar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onChanged == null ? null : () => onChanged!(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  child: avatar == null || avatar.isEmpty ? Text(channel.providerLabel.substring(0, 1)) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(channel.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                      Text(channel.providerLabel, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                      if (outcome != null) _OutcomeLine(outcome: outcome!),
                    ],
                  ),
                ),
                if (posting)
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
                else
                  Transform.scale(
                    scale: 1.4,
                    child: Checkbox(
                      value: selected,
                      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeLine extends StatelessWidget {
  final PostOutcome outcome;

  const _OutcomeLine({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String text) = switch (outcome.state) {
      PostState.success => (Icons.check_circle_rounded, Colors.green.shade700, 'Posted'),
      PostState.posting => (Icons.schedule_rounded, scheme.primary, 'Posting…'),
      PostState.failed => (Icons.error_rounded, scheme.error, outcome.error ?? 'Failed (${outcome.status})'),
    };
    final url = outcome.url;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(
                'Open',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  const _Notice({required this.icon, required this.text, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            MemoriesBigButton(label: action, secondary: true, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}
