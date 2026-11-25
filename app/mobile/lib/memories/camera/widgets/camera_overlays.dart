import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/camera/camera_strings.dart';
import 'package:immich_mobile/memories/camera/capture_queue.dart';

/// Rule-of-thirds 3x3 grid.
class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _GridPainter(), size: Size.infinite));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Horizon level: a line that rotates with the phone tilt and turns yellow with a hint
/// when the phone is noticeably tilted.
class LevelIndicator extends StatelessWidget {
  const LevelIndicator({super.key, required this.tiltDegrees, required this.warning, this.threshold = 4});

  /// Roll angle in degrees; 0 = level. `null` = unknown (hidden).
  final double? tiltDegrees;
  final String warning;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final tilt = tiltDegrees;
    if (tilt == null) {
      return const SizedBox.shrink();
    }
    final tilted = tilt.abs() > threshold;
    final color = tilted ? const Color(0xFFFFD60A) : Colors.white.withValues(alpha: 0.7);
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -tilt * 3.1415926535 / 180,
            child: Container(width: 140, height: tilted ? 3 : 2, color: color),
          ),
          AnimatedOpacity(
            opacity: tilted ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _Pill(
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  warning,
                  style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big countdown number for the self-timer.
class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.secondsLeft});

  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween<double>(begin: 1.6, end: 1).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            '$secondsLeft',
            key: ValueKey(secondsLeft),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 160,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(blurRadius: 24, color: Colors.black54)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small chip showing upload status of the capture queue. Tap to retry failures.
class UploadStatusChip extends StatelessWidget {
  const UploadStatusChip({super.key, required this.queue, required this.strings});

  final CaptureUploadQueue queue;
  final CameraStrings strings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final Widget icon;
        final String label;
        if (queue.failed > 0 && queue.pending == 0) {
          icon = const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF453A), size: 20);
          label = strings.uploadFailed;
        } else if (queue.pending > 0) {
          icon = SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: (queue.progress ?? 0) > 0.02 ? queue.progress : null,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          );
          label = queue.pending > 1 ? strings.uploadingCount(queue.pending) : strings.uploading;
        } else if (queue.done > 0) {
          icon = const Icon(Icons.cloud_done_rounded, color: Color(0xFF30D158), size: 20);
          label = strings.uploaded;
        } else {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: queue.failed > 0 ? queue.retryFailed : null,
          child: _Pill(
            color: Colors.black.withValues(alpha: 0.55),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "N moments from M people".
class MomentsCounter extends StatelessWidget {
  const MomentsCounter({super.key, required this.moments, required this.strings});

  final AlbumMoments? moments;
  final CameraStrings strings;

  @override
  Widget build(BuildContext context) {
    final m = moments;
    if (m == null) {
      return const SizedBox.shrink();
    }
    return _Pill(
      color: Colors.black.withValues(alpha: 0.45),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            strings.moments(m.moments, m.people),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Round translucent control with a large icon and optional badge text (e.g. "3s").
class CameraControlButton extends StatelessWidget {
  const CameraControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.badge,
    this.active = false,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final String? badge;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.black : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: active ? const Color(0xFFFFD60A) : Colors.black.withValues(alpha: 0.42),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: onPressed == null ? fg.withValues(alpha: 0.4) : fg, size: size * 0.5),
                  if (badge != null)
                    Positioned(
                      bottom: 5,
                      child: Text(
                        badge!,
                        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: child),
    );
  }
}
