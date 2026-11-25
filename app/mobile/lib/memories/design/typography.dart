import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/tokens.dart';

/// Font families bundled in pubspec (see lib/memories/design/PUBSPEC_ADDITIONS.md).
abstract final class MFonts {
  static const String display = 'Fraunces';
  static const String sans = 'Manrope';
  static const String devanagari = 'NotoSansDevanagari';
  static const List<String> fallback = [devanagari];
}

/// Memories type scale. Source of truth: docs/BRAND.md section 4.
class MemoriesType {
  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle titleSans;
  final TextStyle body;
  final TextStyle bodyMuted;
  final TextStyle label;
  final TextStyle overline;
  final TextStyle displayItalic;

  const MemoriesType._({
    required this.display,
    required this.headline,
    required this.title,
    required this.titleSans,
    required this.body,
    required this.bodyMuted,
    required this.label,
    required this.overline,
    required this.displayItalic,
  });

  factory MemoriesType.of(MemoriesPalette p) {
    TextStyle serif(double size, double height, FontWeight w, {FontStyle style = FontStyle.normal}) => TextStyle(
      fontFamily: MFonts.display,
      fontFamilyFallback: MFonts.fallback,
      fontSize: size,
      height: height / size,
      fontWeight: w,
      fontStyle: style,
      letterSpacing: -0.3,
      color: p.ink,
    );
    TextStyle sans(double size, double height, FontWeight w, {Color? color, double spacing = 0}) => TextStyle(
      fontFamily: MFonts.sans,
      fontFamilyFallback: MFonts.fallback,
      fontSize: size,
      height: height / size,
      fontWeight: w,
      letterSpacing: spacing,
      color: color ?? p.ink,
    );
    return MemoriesType._(
      display: serif(40, 44, FontWeight.w600),
      headline: serif(30, 36, FontWeight.w600),
      title: serif(22, 28, FontWeight.w600),
      displayItalic: serif(40, 44, FontWeight.w400, style: FontStyle.italic),
      titleSans: sans(18, 24, FontWeight.w700),
      body: sans(16, 24, FontWeight.w500),
      bodyMuted: sans(15, 22, FontWeight.w500, color: p.inkMuted),
      label: sans(14, 18, FontWeight.w700, spacing: 0.2),
      overline: sans(12, 16, FontWeight.w800, color: p.inkMuted, spacing: 1.4),
    );
  }

  static MemoriesType ofContext(BuildContext context) => MemoriesType.of(MemoriesPalette.of(context));

  /// Maps the scale onto a Material TextTheme so stock widgets inherit it.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: display.copyWith(fontSize: 52, height: 1.05),
    displayMedium: display,
    displaySmall: headline.copyWith(fontSize: 34),
    headlineLarge: headline.copyWith(fontSize: 32),
    headlineMedium: headline,
    headlineSmall: title.copyWith(fontSize: 26, height: 1.2),
    titleLarge: title,
    titleMedium: titleSans,
    titleSmall: label.copyWith(fontSize: 15),
    bodyLarge: body.copyWith(fontSize: 17),
    bodyMedium: body,
    bodySmall: bodyMuted.copyWith(fontSize: 14),
    labelLarge: label.copyWith(fontSize: 16),
    labelMedium: label,
    labelSmall: overline,
  );
}
