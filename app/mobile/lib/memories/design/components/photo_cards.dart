import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/photo.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

/// Slow Ken Burns drift for hero photos (off with reduced motion).
class KenBurns extends StatefulWidget {
  final Widget child;
  const KenBurns({super.key, required this.child});

  @override
  State<KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<KenBurns> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(scale: 1.0 + 0.06 * t, alignment: const Alignment(0.2, -0.1), child: child);
      },
      child: widget.child,
    );
  }
}

/// Big photo-first hero: real cover, gradient scrim, kicker, serif title, date, chips, optional action.
class PhotoHeroCard extends StatelessWidget {
  final MPhotoSource? photo;
  final String title;
  final String? kicker;
  final String? subtitle;
  final List<Widget> chips;
  final Widget? action;
  final VoidCallback? onTap;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final bool kenBurns;

  const PhotoHeroCard({
    super.key,
    required this.photo,
    required this.title,
    this.kicker,
    this.subtitle,
    this.chips = const [],
    this.action,
    this.onTap,
    this.aspectRatio = 4 / 5,
    this.borderRadius = MRadius.xlAll,
    this.kenBurns = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final image = MPhoto(source: photo, fallback: MStockPhotos.diwali);
    return Semantics(
      label: [kicker, title, subtitle].whereType<String>().join(', '),
      button: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: MElevation.e2(p)),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Material(
              color: p.indigoNight,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (kenBurns) KenBurns(child: image) else image,
                    const DecoratedBox(decoration: BoxDecoration(gradient: kPhotoScrim)),
                    if (chips.isNotEmpty)
                      Positioned(
                        top: MSpace.md,
                        left: MSpace.md,
                        right: MSpace.md,
                        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
                      ),
                    Positioned(
                      left: MSpace.xl,
                      right: MSpace.xl,
                      bottom: MSpace.xl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (kicker != null)
                            Text(kicker!.toUpperCase(), style: type.overline.copyWith(color: const Color(0xFFFFD58A))),
                          if (kicker != null) const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: type.display.copyWith(color: Colors.white, fontSize: 36, height: 1.08),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(subtitle!, style: type.body.copyWith(color: Colors.white.withValues(alpha: 0.88))),
                          ],
                          if (action != null) ...[const SizedBox(height: MSpace.lg), action!],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Event album card: tall photo with title + count on the scrim.
class MemoryAlbumCard extends StatelessWidget {
  final MPhotoSource? cover;
  final String title;
  final String? meta;
  final VoidCallback? onTap;
  final double width;
  final double aspectRatio;

  const MemoryAlbumCard({
    super.key,
    required this.cover,
    required this.title,
    this.meta,
    this.onTap,
    this.width = 168,
    this.aspectRatio = 3 / 4,
  });

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '$title${meta != null ? ', $meta' : ''}',
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: MRadius.lgAll, boxShadow: MElevation.e1(p)),
          child: ClipRRect(
            borderRadius: MRadius.lgAll,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Material(
                color: p.surfaceMuted,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MPhoto(source: cover, fallback: MStockPhotos.marigold),
                      const DecoratedBox(decoration: BoxDecoration(gradient: kPhotoScrim)),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: type.title.copyWith(color: Colors.white, fontSize: 19, height: 1.15),
                            ),
                            if (meta != null) ...[
                              const SizedBox(height: 4),
                              Text(meta!, style: type.label.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state with a real festive photograph and a warm wash.
class EmptyState extends StatelessWidget {
  final MPhotoSource photo;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    this.photo = MStockPhotos.diwali,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: MRadius.xlAll,
          child: AspectRatio(
            aspectRatio: 16 / 11,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MPhoto(source: photo),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, p.canvas.withValues(alpha: 0.0), p.canvas],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: MSpace.md),
        Text(title, textAlign: TextAlign.center, style: type.headline.copyWith(fontSize: 26)),
        const SizedBox(height: MSpace.xs),
        Text(message, textAlign: TextAlign.center, style: type.bodyMuted.copyWith(fontSize: 16)),
        if (action != null) ...[const SizedBox(height: MSpace.xl), action!],
      ],
    );
  }
}
