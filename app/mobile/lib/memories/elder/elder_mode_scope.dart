import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/elder/elder_mode_controller.dart';
import 'package:immich_mobile/memories/elder/elder_settings.dart';

/// Applies elder-mode sizing to [child]: larger text (never smaller than the
/// user's system setting) and roomier tap targets.
///
/// Wrap the app (`MaterialApp.router(builder: ...)`) or any subtree.
class ElderModeScope extends ConsumerWidget {
  final Widget child;

  /// Overrides the provider, mostly for tests and previews.
  final ElderSettings? settings;

  const ElderModeScope({super.key, required this.child, this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ElderSettings s = settings ?? ref.watch<ElderSettings>(elderSettingsProvider);
    if (!s.enabled || s.textScale <= 1.0) {
      return child;
    }
    final media = MediaQuery.of(context);
    final systemScale = media.textScaler.scale(1);
    final scale = systemScale > s.textScale ? systemScale : s.textScale;
    final theme = Theme.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale)),
      child: Theme(
        data: theme.copyWith(
          visualDensity: VisualDensity.comfortable,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          iconTheme: theme.iconTheme.copyWith(size: (theme.iconTheme.size ?? 24) * 1.2),
        ),
        child: child,
      ),
    );
  }
}
