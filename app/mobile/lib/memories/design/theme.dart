import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

/// ThemeData for Memories screens. Wrap a Memories page in [MemoriesTheme]
/// so it gets the brand regardless of the host (Immich) theme.
abstract final class MemoriesThemes {
  static ThemeData light() => _build(MemoriesPalette.light);
  static ThemeData dark() => _build(MemoriesPalette.dark);

  static ThemeData _build(MemoriesPalette p) {
    final type = MemoriesType.of(p);
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.marigold,
      onPrimary: p.onMarigold,
      primaryContainer: p.marigold.withValues(alpha: 0.18),
      onPrimaryContainer: p.ink,
      secondary: p.plum,
      onSecondary: p.isDark ? p.canvas : Colors.white,
      secondaryContainer: p.surfaceMuted,
      onSecondaryContainer: p.ink,
      tertiary: p.diya,
      onTertiary: Colors.white,
      tertiaryContainer: p.diya.withValues(alpha: 0.16),
      onTertiaryContainer: p.ink,
      error: p.sindoor,
      onError: Colors.white,
      surface: p.canvas,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.line,
      outlineVariant: p.line,
      inverseSurface: p.ink,
      onInverseSurface: p.canvas,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    final textTheme = type.toTextTheme();
    final pillShape = RoundedRectangleBorder(borderRadius: MRadius.pillAll);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      fontFamily: MFonts.sans,
      fontFamilyFallback: MFonts.fallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: [MemoriesThemeExt(p)],
      iconTheme: IconThemeData(color: p.ink, size: 24),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.title,
        systemOverlayStyle: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: MRadius.lgAll,
          side: p.isDark ? BorderSide(color: p.line) : BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.marigold,
          foregroundColor: p.onMarigold,
          minimumSize: const Size(MSize.minTarget, MSize.button),
          shape: pillShape,
          textStyle: type.titleSans,
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(MSize.minTarget, MSize.button),
          shape: pillShape,
          side: BorderSide(color: p.line, width: 1.5),
          textStyle: type.titleSans,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.isDark ? p.marigold : p.plum,
          minimumSize: const Size(MSize.minTarget, MSize.minTarget),
          textStyle: type.label.copyWith(fontSize: 15),
          shape: pillShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: type.body.copyWith(color: p.inkMuted.withValues(alpha: 0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.md),
        border: OutlineInputBorder(
          borderRadius: MRadius.mdAll,
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MRadius.mdAll,
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MRadius.mdAll,
          borderSide: BorderSide(color: p.diya, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: type.body.copyWith(color: p.canvas),
        shape: RoundedRectangleBorder(borderRadius: MRadius.mdAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.diya, linearTrackColor: p.surfaceMuted),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        iconColor: p.ink,
        collapsedIconColor: p.inkMuted,
      ),
    );
  }
}

/// Applies the Memories brand theme (light/dark following the platform) to [child].
class MemoriesTheme extends StatelessWidget {
  final Widget child;
  final Brightness? brightness;

  const MemoriesTheme({super.key, required this.child, this.brightness});

  @override
  Widget build(BuildContext context) {
    final b = brightness ?? Theme.of(context).brightness;
    return Theme(data: b == Brightness.dark ? MemoriesThemes.dark() : MemoriesThemes.light(), child: child);
  }
}
