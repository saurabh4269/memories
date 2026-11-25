import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/tokens.dart';

/// Warm shimmer placeholder used while real photos load. No grey boxes.
class ShimmerPlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final bool animate;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius = MRadius.lgAll,
    this.animate = true,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !MMotion.reduced(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final base = p.surfaceMuted;
    final hi = p.isDark ? p.line : const Color(0xFFFFF8EC);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 - 0.5;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * 2, -0.3),
                  end: Alignment(1 + t * 2, 0.3),
                  colors: [base, hi, base],
                  stops: const [0.25, 0.5, 0.75],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
