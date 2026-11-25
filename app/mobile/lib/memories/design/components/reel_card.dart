import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/basics.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

/// Vertical 9:16 reel frame with title, the director's "why", duration and actions.
/// [media] is the player or cover (supplied by the page so playback logic stays where it is).
class ReelCard extends StatelessWidget {
  final Widget media;
  final String title;
  final String why;
  final String? badge;
  final Duration? duration;
  final VoidCallback? onUse;
  final VoidCallback? onEdit;
  final VoidCallback? onPost;
  final bool busy;
  final bool highlighted;
  final String useLabel;
  final String editLabel;
  final String postLabel;

  const ReelCard({
    super.key,
    required this.media,
    required this.title,
    required this.why,
    this.badge,
    this.duration,
    this.onUse,
    this.onEdit,
    this.onPost,
    this.busy = false,
    this.highlighted = false,
    this.useLabel = 'Use this',
    this.editLabel = 'Edit',
    this.postLabel = 'Post',
  });

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: MMotion.standard,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(MRadius.lg + 3)),
            gradient: highlighted
                ? LinearGradient(colors: [p.marigold, p.diya], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
            boxShadow: MElevation.e2(p),
          ),
          child: ClipRRect(
            borderRadius: MRadius.lgAll,
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.indigoNight),
                  media,
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.22, 0.7, 1],
                          colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      children: [
                        if (badge != null) Flexible(child: FrostedChip(label: badge!)),
                        const Spacer(),
                        if (duration != null) FrostedChip(icon: Icons.play_arrow_rounded, label: _fmt(duration!)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: MSpace.sm),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.title.copyWith(fontSize: 20, height: 1.2),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 3), child: DirectorSpark(size: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                why,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: type.bodyMuted.copyWith(fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: MSpace.sm),
        PillButton(label: useLabel, icon: Icons.ios_share_rounded, onPressed: onUse, busy: busy, height: 52),
        if (onEdit != null || onPost != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (onEdit != null)
                Expanded(
                  child: PillButton(
                    label: editLabel,
                    icon: Icons.tune_rounded,
                    onPressed: onEdit,
                    variant: PillVariant.ghost,
                  ),
                ),
              if (onPost != null)
                Expanded(
                  child: PillButton(
                    label: postLabel,
                    icon: Icons.send_rounded,
                    onPressed: onPost,
                    variant: PillVariant.ghost,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Destination choice card with a platform-hued rounded tile (not an official logo).
class DestinationCard extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final List<Color> tileColors;
  final bool selected;
  final VoidCallback onTap;

  const DestinationCard({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.tileColors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return Semantics(
      selected: selected,
      button: true,
      label: '$label, $hint',
      child: AnimatedContainer(
        duration: MMotion.standard,
        curve: MMotion.standardCurve,
        decoration: BoxDecoration(
          color: selected ? p.marigold.withValues(alpha: p.isDark ? 0.16 : 0.12) : p.surface,
          borderRadius: MRadius.lgAll,
          border: Border.all(color: selected ? p.marigold : p.line, width: selected ? 2 : 1.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: MRadius.lgAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: tileColors.length > 1 ? tileColors : [tileColors.first, tileColors.first],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: MMotion.standard,
                        opacity: selected ? 1 : 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: p.marigold, shape: BoxShape.circle),
                          child: Icon(Icons.check_rounded, size: 16, color: p.onMarigold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.titleSans.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyMuted.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
