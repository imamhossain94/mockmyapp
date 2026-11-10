import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../layout/studio_layout.dart';
import 'studio_tokens.dart';

/// Typography for MockMyApp.
///
/// **Inter** carries every piece of UI text. **JetBrains Mono** is reserved for
/// numeric readouts, dimensions and hex codes — the PyCharm nod. Nothing else
/// is monospaced.
///
/// Each role is exposed twice: a `BuildContext` method that resolves the right
/// token colour automatically, and a `*For(StudioColors)` variant for places
/// that build styles before a context exists (theme construction, painters).
///
/// The reading sizes follow the input. Where touch is primary, [body] and
/// [bodyStrong] are 14 and [caption] 12.5 — the desktop's 13 and 12 are an
/// IDE's density, right under a pointer at arm's length and small in a hand.
/// The `*For` variants have no context, so they keep the desktop sizes.
abstract final class StudioText {
  // ---------------------------------------------------------------------------
  // Context-based API (preferred inside widgets).
  // ---------------------------------------------------------------------------

  /// 32 / w700 / -0.6 — the one headline a consumer screen leads with: the
  /// first-run hero, an AI result's header. Nothing in the
  /// editor's chrome is this size.
  static TextStyle display(BuildContext context) => displayFor(context.studio);

  /// 24 / w600 / -0.4 — empty-state hero.
  static TextStyle displayTitle(BuildContext context) =>
      displayTitleFor(context.studio);

  /// 22 / w600 / -0.3 — a section that introduces a screen: a sheet's lead,
  /// a step's question.
  static TextStyle headline(BuildContext context) =>
      headlineFor(context.studio);

  /// 17 / w600 / -0.2 — screen title, app bar.
  static TextStyle titleLarge(BuildContext context) =>
      titleLargeFor(context.studio);

  /// 15 / w600 / -0.1 — a card's title on a phone, a plan's name: the step
  /// between a panel heading and a screen title that the scale was missing.
  static TextStyle titleMedium(BuildContext context) =>
      titleMediumFor(context.studio);

  /// 14 / w600 / -0.1 — panel and card headings.
  static TextStyle titleSmall(BuildContext context) =>
      titleSmallFor(context.studio);

  /// 11 / w600 / +0.6 — UPPERCASE eyebrow above a group of controls.
  /// Coloured [StudioColors.textSecondary]; never the accent.
  static TextStyle sectionLabel(BuildContext context) =>
      sectionLabelFor(context.studio);

  /// 13 / w400 — default reading size (14 where touch is primary).
  static TextStyle body(BuildContext context) => _touch(context)
      ? _scaled(bodyFor(context.studio), 14)
      : bodyFor(context.studio);

  /// 13 / w500 — emphasised body, button labels (14 where touch is primary).
  static TextStyle bodyStrong(BuildContext context) => _touch(context)
      ? _scaled(bodyStrongFor(context.studio), 14)
      : bodyStrongFor(context.studio);

  /// 12 / w400 — secondary copy (12.5 where touch is primary). Coloured
  /// [StudioColors.textSecondary].
  static TextStyle caption(BuildContext context) => _touch(context)
      ? _scaled(captionFor(context.studio), 12.5)
      : captionFor(context.studio);

  static bool _touch(BuildContext context) => context.layout.isTouchPrimary;

  static TextStyle _scaled(TextStyle style, double size) =>
      style.copyWith(fontSize: size);

  /// 10.5 / w500 / +0.2 — tab labels and hints.
  static TextStyle micro(BuildContext context) => microFor(context.studio);

  /// 11.5 / w500 — JetBrains Mono numeric readout.
  static TextStyle mono(BuildContext context) => monoFor(context.studio);

  // ---------------------------------------------------------------------------
  // Colour-explicit API (theme construction, custom painters).
  // ---------------------------------------------------------------------------

  static TextStyle displayFor(StudioColors c, {Color? color}) => _inter(
    size: 32,
    weight: FontWeight.w700,
    tracking: -0.6,
    height: 1.15,
    color: color ?? c.textPrimary,
  );

  static TextStyle displayTitleFor(StudioColors c, {Color? color}) => _inter(
    size: 24,
    weight: FontWeight.w600,
    tracking: -0.4,
    height: 1.2,
    color: color ?? c.textPrimary,
  );

  static TextStyle headlineFor(StudioColors c, {Color? color}) => _inter(
    size: 22,
    weight: FontWeight.w600,
    tracking: -0.3,
    height: 1.2,
    color: color ?? c.textPrimary,
  );

  static TextStyle titleLargeFor(StudioColors c, {Color? color}) => _inter(
    size: 17,
    weight: FontWeight.w600,
    tracking: -0.2,
    height: 1.25,
    color: color ?? c.textPrimary,
  );

  static TextStyle titleMediumFor(StudioColors c, {Color? color}) => _inter(
    size: 15,
    weight: FontWeight.w600,
    tracking: -0.1,
    height: 1.3,
    color: color ?? c.textPrimary,
  );

  static TextStyle titleSmallFor(StudioColors c, {Color? color}) => _inter(
    size: 14,
    weight: FontWeight.w600,
    tracking: -0.1,
    height: 1.3,
    color: color ?? c.textPrimary,
  );

  // 11 / w600 in the secondary grey. At 10 / w700 in the tertiary grey the
  // eyebrows were the least legible text in the app (2.1 to 2.9:1) and they are
  // on every panel; this clears 4.78 on the darkest surface they sit on.
  static TextStyle sectionLabelFor(StudioColors c, {Color? color}) => _inter(
    size: 11,
    weight: FontWeight.w600,
    tracking: 0.6,
    height: 1.2,
    color: color ?? c.textSecondary,
  );

  static TextStyle bodyFor(StudioColors c, {Color? color}) => _inter(
    size: 13,
    weight: FontWeight.w400,
    tracking: 0,
    height: 1.4,
    color: color ?? c.textPrimary,
  );

  static TextStyle bodyStrongFor(StudioColors c, {Color? color}) => _inter(
    size: 13,
    weight: FontWeight.w500,
    tracking: 0,
    height: 1.4,
    color: color ?? c.textPrimary,
  );

  static TextStyle captionFor(StudioColors c, {Color? color}) => _inter(
    size: 12,
    weight: FontWeight.w400,
    tracking: 0,
    height: 1.35,
    color: color ?? c.textSecondary,
  );

  static TextStyle microFor(StudioColors c, {Color? color}) => _inter(
    size: 10.5,
    weight: FontWeight.w500,
    tracking: 0.2,
    height: 1.2,
    color: color ?? c.textPrimary,
  );

  static TextStyle monoFor(StudioColors c, {Color? color}) => _mono(
    size: 11.5,
    weight: FontWeight.w500,
    tracking: 0,
    height: 1.2,
    color: color ?? c.textPrimary,
  );

  // ---------------------------------------------------------------------------
  // Material bridge.
  // ---------------------------------------------------------------------------

  /// A Material [TextTheme] wired to the studio scale, so any stock widget that
  /// slips through still lands on-brand.
  static TextTheme textTheme(StudioColors c) {
    return TextTheme(
      displayLarge: displayTitleFor(c),
      displayMedium: displayTitleFor(c),
      displaySmall: displayTitleFor(c),
      headlineLarge: displayTitleFor(c),
      headlineMedium: titleLargeFor(c),
      headlineSmall: titleLargeFor(c),
      titleLarge: titleLargeFor(c),
      titleMedium: titleSmallFor(c),
      titleSmall: bodyStrongFor(c),
      bodyLarge: bodyFor(c),
      bodyMedium: bodyFor(c),
      bodySmall: captionFor(c),
      labelLarge: bodyStrongFor(c),
      labelMedium: captionFor(c, color: c.textPrimary),
      labelSmall: microFor(c, color: c.textSecondary),
    );
  }

  // ---------------------------------------------------------------------------
  // Font builders.
  // ---------------------------------------------------------------------------

  static TextStyle _inter({
    required double size,
    required FontWeight weight,
    required double tracking,
    required double height,
    required Color color,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: height,
      color: color,
    );
  }

  static TextStyle _mono({
    required double size,
    required FontWeight weight,
    required double tracking,
    required double height,
    required Color color,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: height,
      color: color,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}
