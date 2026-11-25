import 'package:flutter/material.dart';

/// Memories design tokens. Source of truth: docs/BRAND.md.
@immutable
class MemoriesPalette {
  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color line;
  final Color ink;
  final Color inkMuted;
  final Color marigold;
  final Color onMarigold;
  final Color diya;
  final Color plum;
  final Color indigoNight;
  final Color sindoor;
  final Color leaf;

  const MemoriesPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.marigold,
    required this.onMarigold,
    required this.diya,
    required this.plum,
    required this.indigoNight,
    required this.sindoor,
    required this.leaf,
  });

  bool get isDark => brightness == Brightness.dark;

  static const light = MemoriesPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFFBF6EE),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4ECDF),
    line: Color(0xFFE8DCCB),
    ink: Color(0xFF24161D),
    inkMuted: Color(0xFF6E5B63),
    marigold: Color(0xFFF2A20C),
    onMarigold: Color(0xFF24161D),
    diya: Color(0xFFD9661A),
    plum: Color(0xFF4B1F4F),
    indigoNight: Color(0xFF1D1A38),
    sindoor: Color(0xFFB8332B),
    leaf: Color(0xFF2E7A57),
  );

  static const dark = MemoriesPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF110D19),
    surface: Color(0xFF1B1626),
    surfaceMuted: Color(0xFF251E33),
    line: Color(0xFF352B45),
    ink: Color(0xFFF8EFE2),
    inkMuted: Color(0xFFBBAEBD),
    marigold: Color(0xFFF7B23B),
    onMarigold: Color(0xFF24161D),
    diya: Color(0xFFF28A3E),
    plum: Color(0xFFD2A3DC),
    indigoNight: Color(0xFF0B0912),
    sindoor: Color(0xFFF07468),
    leaf: Color(0xFF6CC79C),
  );

  static MemoriesPalette of(BuildContext context) =>
      Theme.of(context).extension<MemoriesThemeExt>()?.palette ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
}

/// Spacing scale (8-pt).
abstract final class MSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double gutter = 20;
  static const double section = 32;
}

/// Corner radii.
abstract final class MRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion.
abstract final class MMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasised = Duration(milliseconds: 360);
  static const Duration stagger = Duration(milliseconds: 40);
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasisedCurve = Curves.easeOutQuart;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Warm, low shadows (instead of Material elevation).
abstract final class MElevation {
  static List<BoxShadow> e1(MemoriesPalette p) => [
    BoxShadow(
      color: p.isDark ? const Color(0x66000000) : const Color(0x0F24161D),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> e2(MemoriesPalette p) => [
    BoxShadow(
      color: p.isDark ? const Color(0x66000000) : const Color(0x1F24161D),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];

  static List<BoxShadow> glow(MemoriesPalette p) => [
    BoxShadow(color: p.marigold.withValues(alpha: 0.35), blurRadius: 32, spreadRadius: 2),
  ];
}

/// Minimum sizes (elder-friendly).
abstract final class MSize {
  static const double minTarget = 48;
  static const double button = 60;
  static const double buttonElder = 64;
}

/// Photo scrim: keeps white text AA on any photo.
const LinearGradient kPhotoScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.0, 0.35, 1.0],
  colors: [Color(0x14000000), Color(0x00000000), Color(0xB8000000)],
);

/// ThemeExtension so components can read the palette from Theme.
@immutable
class MemoriesThemeExt extends ThemeExtension<MemoriesThemeExt> {
  final MemoriesPalette palette;
  const MemoriesThemeExt(this.palette);

  @override
  MemoriesThemeExt copyWith({MemoriesPalette? palette}) => MemoriesThemeExt(palette ?? this.palette);

  @override
  MemoriesThemeExt lerp(ThemeExtension<MemoriesThemeExt>? other, double t) =>
      t < 0.5 ? this : (other as MemoriesThemeExt? ?? this);
}
