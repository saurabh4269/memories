import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Big, elder-friendly shutter: tap = photo, press-and-hold = video.
///
/// While recording, a red ring fills up to show progress towards the max duration.
class ShutterButton extends StatelessWidget {
  const ShutterButton({
    super.key,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.isRecording,
    required this.recordProgress,
    this.enabled = true,
    this.size = 96,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool isRecording;

  /// 0..1 progress of the current recording.
  final Animation<double> recordProgress;
  final bool enabled;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                unawaited(HapticFeedback.mediumImpact());
                onTap();
              }
            : null,
        onLongPressStart: enabled
            ? (_) {
                unawaited(HapticFeedback.heavyImpact());
                onHoldStart();
              }
            : null,
        onLongPressEnd: enabled ? (_) => onHoldEnd() : null,
        onLongPressCancel: enabled && isRecording ? onHoldEnd : null,
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: recordProgress,
            builder: (context, _) => CustomPaint(
              painter: _ShutterPainter(
                progress: isRecording ? recordProgress.value : 0,
                recording: isRecording,
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  _ShutterPainter({required this.progress, required this.recording, required this.enabled});

  final double progress;
  final bool recording;
  final bool enabled;

  static const _red = Color(0xFFFF3B30);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const ring = 6.0;

    // Outer white ring.
    canvas.drawCircle(
      center,
      radius - ring / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = Colors.white.withValues(alpha: enabled ? 1 : 0.4),
    );

    // Red progress ring while recording.
    if (recording && progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - ring / 2),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring
          ..strokeCap = StrokeCap.round
          ..color = _red,
      );
    }

    // Inner disc: white for photo, red rounded square while recording.
    if (recording) {
      final side = radius * 0.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: side, height: side),
          Radius.circular(side * 0.2),
        ),
        Paint()..color = _red,
      );
    } else {
      canvas.drawCircle(center, radius - ring - 6, Paint()..color = Colors.white.withValues(alpha: enabled ? 1 : 0.4));
    }
  }

  @override
  bool shouldRepaint(_ShutterPainter old) =>
      old.progress != progress || old.recording != recording || old.enabled != enabled;
}
