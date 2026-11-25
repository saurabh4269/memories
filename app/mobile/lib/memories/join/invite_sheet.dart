import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/join/join_api.dart';
import 'package:immich_mobile/memories/join/member_profile.dart';
import 'package:immich_mobile/memories/join/memories_ui.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows [InviteSheet] as a modal bottom sheet.
Future<void> showInviteSheet(BuildContext context, String albumId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (_) => InviteSheet(albumId: albumId),
);

/// Host-side sheet: creates an invite for [albumId] and shows a big QR for
/// family members to scan, plus a link to send on WhatsApp etc.
class InviteSheet extends ConsumerStatefulWidget {
  final String albumId;

  const InviteSheet({super.key, required this.albumId});

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  late Future<JoinInvite> _invite;

  @override
  void initState() {
    super.initState();
    _invite = _create();
  }

  Future<JoinInvite> _create() {
    final profileName = ref.read(memberProfileProvider).valueOrNull?.name;
    final authName = ref.read(authProvider).name;
    final createdBy = (profileName != null && profileName.isNotEmpty) ? profileName : authName;
    return ref.read(joinApiProvider).createInvite(widget.albumId, createdBy: createdBy);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: FutureBuilder<JoinInvite>(
        future: _invite,
        builder: (context, snapshot) {
          final children = <Widget>[
            const MemoriesSheetHeader(
              title: 'Invite family',
              subtitle: 'Ask them to open Memories and tap “Scan the QR”.',
            ),
            const SizedBox(height: 20),
          ];
          if (snapshot.connectionState != ConnectionState.done) {
            children.add(const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())));
          } else if (snapshot.hasError || !snapshot.hasData) {
            final err = snapshot.error;
            children.addAll([
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    err is DirectorException ? err.message : 'Could not create an invite.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
              ),
              MemoriesBigButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: () => setState(() => _invite = _create()),
              ),
            ]);
          } else {
            children.addAll(_buildInvite(context, snapshot.data!));
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildInvite(BuildContext context, JoinInvite invite) {
    final theme = Theme.of(context);
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: SizedBox.square(
            dimension: 260,
            child: invite.qrPngUrl == null
                ? const Center(child: Icon(Icons.qr_code_2_rounded, size: 200, color: Colors.black))
                : Image.network(
                    invite.qrPngUrl!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stack) =>
                        const Center(child: Icon(Icons.qr_code_2_rounded, size: 200, color: Colors.black)),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text('Or tell them this code', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      SelectableText(
        invite.code,
        textAlign: TextAlign.center,
        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6),
      ),
      if (invite.expiresAt != null)
        Text(
          'Valid until ${_formatExpiry(invite.expiresAt!.toLocal())}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      const SizedBox(height: 24),
      MemoriesBigButton(
        label: 'Send invite link',
        icon: Icons.ios_share_rounded,
        onPressed: () async {
          final box = context.findRenderObject() as RenderBox?;
          await Share.share(
            'Join our family album on Memories 📸\n${invite.shareUrl}\nCode: ${invite.code}',
            subject: 'Join our family album',
            sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
          );
        },
      ),
      const SizedBox(height: 12),
      MemoriesBigButton(
        label: 'Copy link',
        icon: Icons.copy_rounded,
        secondary: true,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: invite.shareUrl));
          if (context.mounted) {
            showMemoriesSnack(context, 'Link copied');
          }
        },
      ),
    ];
  }

  static String _formatExpiry(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
