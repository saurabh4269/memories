import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

enum PillVariant { primary, secondary, ghost, dark }

/// Pill-shaped button. Primary is marigold; 60 dp tall by default (48 dp min).
class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PillVariant variant;
  final bool busy;
  final bool expand;
  final double? height;
  final bool glow;

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = PillVariant.primary,
    this.busy = false,
    this.expand = true,
    this.height,
    this.glow = false,
  });

  const PillButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.expand = true,
    this.height,
  }) : variant = PillVariant.secondary,
       glow = false;

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final (Color bg, Color fg, BorderSide? side) = switch (variant) {
      PillVariant.primary => (p.marigold, p.onMarigold, null),
      PillVariant.secondary => (p.surface, p.ink, BorderSide(color: p.line, width: 1.5)),
      PillVariant.ghost => (Colors.transparent, p.isDark ? p.marigold : p.plum, null),
      PillVariant.dark => (p.isDark ? p.ink : p.indigoNight, p.isDark ? p.canvas : Colors.white, null),
    };
    final disabled = onPressed == null && !busy;
    final h = height ?? (variant == PillVariant.ghost ? MSize.minTarget : MSize.button);
    final content = busy
        ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: MSpace.xs)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.titleSans.copyWith(color: fg, fontSize: variant == PillVariant.ghost ? 15 : 17),
                ),
              ),
            ],
          );
    final button = AnimatedOpacity(
      duration: MMotion.standard,
      opacity: disabled ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: MRadius.pillAll,
          boxShadow: glow && !disabled ? MElevation.glow(p) : null,
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: MRadius.pillAll, side: side ?? BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h, minWidth: MSize.minTarget),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: variant == PillVariant.ghost ? MSpace.xs : MSpace.xl),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Small translucent chip for metadata on top of photos.
class FrostedChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? tint;

  const FrostedChip({super.key, required this.label, this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final type = MemoriesType.ofContext(context);
    return ClipRRect(
      borderRadius: MRadius.pillAll,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (tint ?? Colors.white).withValues(alpha: tint == null ? 0.22 : 0.9),
            borderRadius: MRadius.pillAll,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 5)],
              Text(label, style: type.label.copyWith(color: Colors.white, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable pill (language, mood). Shows a check when selected so colour is not the only cue.
class MemoriesChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const MemoriesChoiceChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final fg = selected ? (p.isDark ? p.canvas : Colors.white) : p.ink;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: AnimatedContainer(
        duration: MMotion.standard,
        curve: MMotion.standardCurve,
        decoration: BoxDecoration(
          color: selected ? (p.isDark ? p.ink : p.plum) : p.surface,
          borderRadius: MRadius.pillAll,
          border: Border.all(color: selected ? Colors.transparent : p.line, width: 1.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: MRadius.pillAll,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, minWidth: MSize.minTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: MMotion.standard,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.check_rounded, size: 18, color: fg),
                            )
                          : (icon != null
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(icon, size: 18, color: p.inkMuted),
                                  )
                                : const SizedBox.shrink()),
                    ),
                    Text(label, style: type.titleSans.copyWith(color: fg, fontSize: 16)),
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

/// Section header: small overline kicker + serif title + optional action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? kicker;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.kicker,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: MSpace.gutter),
  });

  @override
  Widget build(BuildContext context) {
    final type = MemoriesType.ofContext(context);
    final p = MemoriesPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null) ...[Text(kicker!.toUpperCase(), style: type.overline), const SizedBox(height: 4)],
                Text(title, style: type.title),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: p.isDark ? p.marigold : p.plum),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The director's spark: a small four-point star used only next to AI actions.
class DirectorSpark extends StatelessWidget {
  final double size;
  final Color? color;
  const DirectorSpark({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? MemoriesPalette.of(context).diya;
    return CustomPaint(size: Size.square(size), painter: _SparkPainter(c));
  }
}

class _SparkPainter extends CustomPainter {
  final Color color;
  _SparkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(w * 0.56, h * 0.44, w, h / 2)
      ..quadraticBezierTo(w * 0.56, h * 0.56, w / 2, h)
      ..quadraticBezierTo(w * 0.44, h * 0.56, 0, h / 2)
      ..quadraticBezierTo(w * 0.44, h * 0.44, w / 2, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    final small = Path()..addOval(Rect.fromCircle(center: Offset(w * 0.86, h * 0.14), radius: w * 0.08));
    canvas.drawPath(small, Paint()..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color;
}

/// Staggered fade + rise entrance. Off when reduced motion is on.
class FadeRise extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeRise({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    if (MMotion.reduced(context)) return child;
    final delay = (index.clamp(0, 6)) * MMotion.stagger.inMilliseconds;
    final total = MMotion.emphasised.inMilliseconds + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, v, child) {
        final t = total == 0 ? 1.0 : ((v * total - delay) / MMotion.emphasised.inMilliseconds).clamp(0.0, 1.0);
        final e = MMotion.emphasisedCurve.transform(t);
        return Opacity(
          opacity: e,
          child: Transform.translate(offset: Offset(0, 12 * (1 - e)), child: child),
        );
      },
      child: child,
    );
  }
}
