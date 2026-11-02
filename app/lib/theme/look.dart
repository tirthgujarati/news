import 'package:flutter/material.dart';

import '../data/settings.dart';

/// How the section tabs are drawn.
enum TabShape { underline, pill, block }

/// How the lead story is drawn.
enum LeadShape { card, overlay, fullBleed }

/// How the market ticker is drawn.
enum TickerShape { tiles, strip, inline }

/// Everything a style changes, beyond Material colours. Read with
/// `Look.of(context)`.
class Look extends ThemeExtension<Look> {
  const Look({
    required this.style,
    required this.dark,
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.up,
    required this.down,
    required this.sections,
    required this.tickerBg,
    required this.tickerInk,
    required this.tagBg,
    required this.tagInk,
    required this.brandAccent,
    required this.headlineFont,
    required this.headlineWeight,
    required this.bodyFont,
    required this.numberFont,
    required this.tabShape,
    required this.leadShape,
    required this.tickerShape,
    required this.uppercaseTabs,
  });

  final AppStyle style;
  final bool dark;
  final Color bg;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color line;
  final Color up;
  final Color down;
  final Map<String, Color> sections;
  final Color tickerBg;
  final Color tickerInk;
  final Color tagBg;
  final Color tagInk;

  /// Colour of the dot after "apex" (Night desk) or null for none.
  final Color? brandAccent;
  final String headlineFont;
  final FontWeight headlineWeight;
  final String bodyFont;
  final String numberFont;
  final TabShape tabShape;
  final LeadShape leadShape;
  final TickerShape tickerShape;
  final bool uppercaseTabs;

  static Look of(BuildContext context) => Theme.of(context).extension<Look>()!;

  Color section(String id) => sections[id] ?? ink;

  /// Impact size colour: red = high, orange = medium, yellow = low.
  Color impact(String level) => switch (level) {
        'high' => dark ? const Color(0xFFFF5C66) : const Color(0xFFD62839),
        'medium' => dark ? const Color(0xFFFFA94D) : const Color(0xFFE8740C),
        _ => dark ? const Color(0xFFFFD43B) : const Color(0xFFE0B000),
      };

  Color forDir(String dir) => switch (dir) {
        'up' => up,
        'down' => down,
        _ => muted,
      };

  TextStyle headline(double size, {Color? color, double height = 1.2}) =>
      TextStyle(
        fontFamily: headlineFont,
        fontWeight: headlineWeight,
        fontSize: size,
        height: height,
        letterSpacing: style == AppStyle.bold ? -0.4 : -0.1,
        color: color ?? ink,
      );

  TextStyle body(double size,
          {Color? color, FontWeight weight = FontWeight.w400, double height = 1.45}) =>
      TextStyle(
        fontFamily: bodyFont,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? muted,
      );

  TextStyle label(double size, {Color? color}) => TextStyle(
        fontFamily: style == AppStyle.night ? numberFont : bodyFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: color ?? muted,
      );

  TextStyle number(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: numberFont,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Look copyWith() => this;

  @override
  Look lerp(Look? other, double t) => t < 0.5 ? this : (other ?? this);
}

const _sectionsNight = {
  'india': Color(0xFFFFA94D),
  'world': Color(0xFF6EA8FF),
  'currency': Color(0xFF3EE0C4),
  'markets': Color(0xFFB794FF),
  'built': Color(0xFFFF7AA2),
};

const _sectionsPaper = {
  'india': Color(0xFFE8771E),
  'world': Color(0xFF2F6FDE),
  'currency': Color(0xFF0E9F8E),
  'markets': Color(0xFF7A4DD8),
  'built': Color(0xFFC9184A),
};

const _sectionsBold = {
  'india': Color(0xFFFF6A00),
  'world': Color(0xFF1D4ED8),
  'currency': Color(0xFF0D9488),
  'markets': Color(0xFF6D28D9),
  'built': Color(0xFFE11D48),
};

Look lookFor(AppStyle style, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  switch (style) {
    case AppStyle.night:
      return Look(
        style: style,
        dark: dark,
        bg: dark ? const Color(0xFF0C0E12) : const Color(0xFFF4F6F9),
        surface: dark ? const Color(0xFF161A20) : Colors.white,
        ink: dark ? const Color(0xFFE9EDF2) : const Color(0xFF0C0E12),
        muted: dark ? const Color(0xFF8B95A3) : const Color(0xFF5B6573),
        line: dark ? const Color(0xFF1F242C) : const Color(0xFFE1E6EC),
        up: dark ? const Color(0xFF4CD98A) : const Color(0xFF12924A),
        down: dark ? const Color(0xFFFF5C66) : const Color(0xFFD62839),
        sections: dark ? _sectionsNight : _sectionsPaper,
        tickerBg: dark ? const Color(0xFF12151B) : const Color(0xFFEAEEF3),
        tickerInk: dark ? const Color(0xFFE9EDF2) : const Color(0xFF0C0E12),
        tagBg: dark ? const Color(0xFF2A2414) : const Color(0xFFFFF3D6),
        tagInk: dark ? const Color(0xFFE6C06A) : const Color(0xFF8A6200),
        brandAccent: dark ? const Color(0xFF5EE0A0) : const Color(0xFF12924A),
        headlineFont: 'SpaceGrotesk',
        headlineWeight: FontWeight.w700,
        bodyFont: 'Inter',
        numberFont: 'JetBrainsMono',
        tabShape: TabShape.pill,
        leadShape: LeadShape.overlay,
        tickerShape: TickerShape.strip,
        uppercaseTabs: false,
      );
    case AppStyle.paper:
      return Look(
        style: style,
        dark: dark,
        bg: dark ? const Color(0xFF141310) : const Color(0xFFFAFAF7),
        surface: dark ? const Color(0xFF1D1C18) : Colors.white,
        ink: dark ? const Color(0xFFF1EFE9) : const Color(0xFF111111),
        muted: dark ? const Color(0xFFA39F95) : const Color(0xFF5C5A55),
        line: dark ? const Color(0xFF2C2A25) : const Color(0xFFE4E2DC),
        up: dark ? const Color(0xFF4CC97E) : const Color(0xFF14A44D),
        down: dark ? const Color(0xFFFF6B6B) : const Color(0xFFE5383B),
        sections: dark ? _sectionsNight : _sectionsPaper,
        tickerBg: dark ? const Color(0xFF141310) : const Color(0xFFFAFAF7),
        tickerInk: dark ? const Color(0xFFF1EFE9) : const Color(0xFF111111),
        tagBg: dark ? const Color(0xFF2E2919) : const Color(0xFFF1EDE4),
        tagInk: dark ? const Color(0xFFD8C08A) : const Color(0xFF7A6A45),
        brandAccent: null,
        headlineFont: 'Archivo',
        headlineWeight: FontWeight.w800,
        bodyFont: 'Inter',
        numberFont: 'Archivo',
        tabShape: TabShape.underline,
        leadShape: LeadShape.card,
        tickerShape: TickerShape.tiles,
        uppercaseTabs: false,
      );
    case AppStyle.bold:
      return Look(
        style: style,
        dark: dark,
        bg: dark ? const Color(0xFF0B0B0B) : Colors.white,
        surface: dark ? const Color(0xFF161616) : Colors.white,
        ink: dark ? Colors.white : const Color(0xFF0D0D0D),
        muted: dark ? const Color(0xFFA3A3A3) : const Color(0xFF555555),
        line: dark ? const Color(0xFF262626) : const Color(0xFFECECEC),
        up: const Color(0xFF3DDC84),
        down: const Color(0xFFFF6B6B),
        sections: dark ? _sectionsNight : _sectionsBold,
        tickerBg: dark ? const Color(0xFF1A1A1A) : const Color(0xFF0D0D0D),
        tickerInk: Colors.white,
        tagBg: dark ? const Color(0xFF33240F) : const Color(0xFFFFF1E0),
        tagInk: dark ? const Color(0xFFFFB766) : const Color(0xFFB35C00),
        brandAccent: null,
        headlineFont: 'InterTight',
        headlineWeight: FontWeight.w900,
        bodyFont: 'Inter',
        numberFont: 'InterTight',
        tabShape: TabShape.block,
        leadShape: LeadShape.fullBleed,
        tickerShape: TickerShape.inline,
        uppercaseTabs: true,
      );
  }
}

ThemeData themeFor(AppStyle style, Brightness brightness) {
  final look = lookFor(style, brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: look.section('markets'),
    brightness: brightness,
  ).copyWith(surface: look.bg, onSurface: look.ink, primary: look.ink);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: look.bg,
    fontFamily: look.bodyFont,
    dividerColor: look.line,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: look.bg,
      foregroundColor: look.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: look.headline(20),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: look.surface,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: look.ink,
      contentTextStyle: look.body(14, color: look.bg, weight: FontWeight.w500),
    ),
    extensions: [look],
  );
}
