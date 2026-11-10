import 'package:flutter/material.dart';

/// Design tokens for MockMyApp.
///
/// The visual language blends Photoshop's dense professional panels with
/// JetBrains' New UI calm: flat, FILLED surfaces separated by a tonal ramp
/// (not outlines), neutral (never blue-tinted) greys, and a single confident
/// accent blue. Hairlines survive only on floating overlays and structural
/// separators; every inline control carries its edge in its fill.
///
/// Containers and controls never share a fill. A container — a panel, a card,
/// a sheet — is one of the surface tones below; a neutral control inside it is
/// [control]. When the two were both `panelAlt`, a default button inside a
/// panel had no edge at all, and in light mode a whole panel vanished inside a
/// dialog.
///
/// Never hardcode a colour in a widget — always read from [StudioColors] via
/// `context.studio`, or from `Theme.of(context).colorScheme`.
@immutable
class StudioColors {
  const StudioColors({
    required this.canvas,
    required this.panel,
    required this.panelAlt,
    required this.well,
    required this.overlay,
    required this.control,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSubtle,
    required this.onAccentSubtle,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerText,
    required this.successText,
    required this.warningText,
    required this.selectionBg,
    required this.hoverBg,
  });

  /// App scaffold background. The content well behind every panel.
  final Color canvas;

  /// Toolbars, sheets, cards — the primary chrome surface.
  final Color panel;

  /// Nested / elevated surface sitting on top of [panel]. Containers only:
  /// a control filled with it disappears inside a `StudioPanel`.
  final Color panelAlt;

  /// Inputs, numeric readout fields, slider track backgrounds.
  final Color well;

  /// Dialogs, menus, popovers — true floating overlays.
  ///
  /// Never equal to [panelAlt]: a `StudioPanel` inside a dialog has to read as
  /// a raised block, and in light mode the two were both white, so a
  /// dialog's panels dissolved into the dialog around them. The dark overlay
  /// has always been the [panel] tone; the light one now matches it.
  final Color overlay;

  /// The fill of every neutral control — secondary buttons, unselected chips,
  /// tool groups, the empty-state tile.
  ///
  /// A step lighter than [panelAlt] in dark mode and a step darker than it in
  /// light, so a control has an edge on [panel], on [panelAlt] and on
  /// [overlay]. In light mode it is too close to [canvas] and [well] to give a
  /// control an edge there, which is what [controlOn] is for: read the fill
  /// through it, or through `context.controlFill`, rather than directly.
  final Color control;

  /// Standard 1px hairline.
  final Color border;

  /// Quieter hairline for dense internal splits.
  final Color borderSubtle;

  /// Emphasised hairline: control outlines, focus-adjacent edges.
  final Color borderStrong;

  /// Primary reading colour.
  final Color textPrimary;

  /// Supporting copy, inactive icons, section eyebrows, hints.
  final Color textSecondary;

  /// Disabled text, placeholders and decorative glyphs — nothing a user has to
  /// read to use the app.
  ///
  /// It used to carry the section eyebrows, hints and counts as well, at 2.1 to
  /// 2.9:1. These values clear 4:1 on every surface, which keeps a placeholder
  /// legible, and stay visibly fainter than [textSecondary]; anything that
  /// informs takes [textSecondary], which clears WCAG AA's 4.5 everywhere.
  final Color textTertiary;

  /// The single accent blue.
  final Color accent;

  /// Accent under pointer hover.
  final Color accentHover;

  /// Accent while pressed.
  final Color accentPressed;

  /// Translucent accent wash for tinted fills and focus rings.
  final Color accentSubtle;

  /// Foreground on top of [accentSubtle].
  ///
  /// Not [accent], which is what a tinted fill invites you to reach for and
  /// what a selected chip used to use: accent on its own wash measures 2.51
  /// against the dark panel and 3.77 against the light one, both well under
  /// WCAG AA's 4.5. A wash is only a few percent away from the surface under
  /// it, so the text on it has to move instead — lighter than [accent] on dark,
  /// darker on light.
  ///
  /// Solved against the WORST surface the wash can land on rather than the
  /// prettiest one: a tinted chip sits on `canvas`, on `panel` or on `panelAlt`
  /// depending on where it is, and each composites the wash differently. The
  /// light value was first fitted over white, where it measured 4.56 — and 3.97
  /// over the canvas the chips are actually on.
  final Color onAccentSubtle;

  /// Foreground on top of [accent].
  final Color onAccent;

  /// Fill colours. [success], [warning] and [danger] are for fills, dots,
  /// progress and tints; text and glyphs in those roles take the `*Text`
  /// tokens below, which are tuned to clear WCAG AA as words.
  final Color success;
  final Color warning;
  final Color danger;

  /// Accent-coloured words and glyphs on a bare surface: a link, a selected
  /// item's name, a selected icon on its wash.
  ///
  /// The same value as [onAccentSubtle], which was solved against the worst
  /// surface a wash lands on and so clears AA on the bare surfaces too — 5.23
  /// on the dark `panelAlt`, 4.83 on the light `well`. [accent] itself is a
  /// fill: as text it measured 3.0 on the dark panel and 2.71 on `panelAlt`.
  Color get accentText => onAccentSubtle;

  /// Error text and glyphs: inline errors, a destructive menu item's label.
  ///
  /// The dark value is a hair lighter than the audit's `#E57B7B`, which
  /// measured 4.44 on `panelAlt` — exactly where inline errors sit, inside a
  /// panel. This one clears 4.59 there.
  final Color dangerText;

  /// Success text ("Ready to analyse"). The light [success] fill measured 3.65
  /// as text on the light canvas.
  final Color successText;

  /// Warning text and tags. The light [warning] fill measured 2.99 as text.
  final Color warningText;

  /// Background of a selected list row.
  final Color selectionBg;

  /// Translucent hover wash for rows and ghost buttons.
  final Color hoverBg;

  /// [control] under a pointer.
  Color get controlHover => Color.alphaBlend(hoverBg, control);

  /// The fill a neutral control takes when it sits on [surface].
  ///
  /// [control], unless that is too close to [surface] to give the control an
  /// edge — under 1.08:1, which happens only in light mode, on the canvas
  /// (1.04) and in wells — and then the raised [panelAlt], which separates
  /// better there (1.16 on the light canvas). Dark mode always gets [control].
  Color controlOn(Color surface) {
    final onControl = contrastRatio(control, surface);
    if (onControl >= _minControlStep) return control;
    return contrastRatio(panelAlt, surface) > onControl ? panelAlt : control;
  }

  /// The smallest tone step that still reads as a control's edge. Picked
  /// between the light control's 1.10 on `panel`, which reads, and its 1.04
  /// on the canvas, which does not.
  static const double _minControlStep = 1.08;

  /// The WCAG 2.x contrast ratio between two opaque colours, from 1 to 21.
  ///
  /// Here rather than in a test so a widget can make the same decision a test
  /// checks: [controlOn] uses it to pick a fill.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static const StudioColors dark = StudioColors(
    canvas: Color(0xFF1E1F22),
    panel: Color(0xFF2B2D30),
    panelAlt: Color(0xFF313438),
    // A step above `canvas` so a filled input reads on a canvas background and
    // still recesses on `panel`/`panelAlt` — the fill, not a border, is the edge.
    well: Color(0xFF26282C),
    overlay: Color(0xFF2B2D30),
    // 1.31 on panel, 1.18 on panelAlt: a control reads on both.
    control: Color(0xFF3C3F44),
    border: Color(0xFF393B40),
    borderSubtle: Color(0xFF303236),
    borderStrong: Color(0xFF4E5157),
    textPrimary: Color(0xFFDFE1E5),
    textSecondary: Color(0xFF9DA0A8),
    // Was #6F737A: 2.90 on panel, 2.63 on panelAlt. Now 5.28 on the canvas,
    // 4.73 in a well, 4.01 on panelAlt.
    textTertiary: Color(0xFF8E929A),
    // A shade off #3574F0, which measured 4.28 against white — under AA, and
    // white on accent is what every filled button, selected segment and
    // selected tab in the app is. Dark enough to clear 4.61, close enough that
    // the brand blue is the same blue.
    accent: Color(0xFF336FE6),
    // Hover DARKENS here, as it already did in the light palette. It used to
    // lighten, which on a filled accent surface spends the contrast headroom
    // the fix above just bought: #4A85F5 put white at 3.77.
    accentHover: Color(0xFF2F66D4),
    accentPressed: Color(0xFF2A5BBD),
    // #336FE6 @ 16% alpha.
    accentSubtle: Color(0x29336FE6),
    onAccent: Color(0xFFFFFFFF),
    onAccentSubtle: Color(0xFF80A7F6),
    success: Color(0xFF5FAD65),
    warning: Color(0xFFD6A32E),
    // #DB5C5C put white at 3.69. This clears 4.60 and stays the same red.
    danger: Color(0xFFC15151),
    // As text the fill measured 3.00 on panel; this is 5.07 there.
    dangerText: Color(0xFFE67F7F),
    // The dark fills already read as text: 4.56 and 5.44 on panelAlt.
    successText: Color(0xFF5FAD65),
    warningText: Color(0xFFD6A32E),
    selectionBg: Color(0xFF2E436E),
    // #FFFFFF @ 6% alpha.
    hoverBg: Color(0x0FFFFFFF),
  );

  static const StudioColors light = StudioColors(
    // Tonal ramp (darkest → lightest) so filled surfaces separate from one
    // another WITHOUT a hairline: recessed `well` < app `canvas` < `panel`
    // chrome < raised `panelAlt`/`overlay` (white). This is what lets the app
    // read as a filled design in light mode instead of a borderless white void.
    canvas: Color(0xFFEDEEF2),
    panel: Color(0xFFF4F5F8),
    panelAlt: Color(0xFFFFFFFF),
    well: Color(0xFFE4E6EC),
    // The panel tone, as in dark mode: a white `StudioPanel` inside a dialog
    // now sits 1.09 above it instead of vanishing into it.
    overlay: Color(0xFFF4F5F8),
    // 1.10 on panel, 1.20 on panelAlt and white.
    control: Color(0xFFE8EAEE),
    border: Color(0xFFD3D5DB),
    borderSubtle: Color(0xFFE3E5EB),
    borderStrong: Color(0xFFA8ADB8),
    textPrimary: Color(0xFF1E1F22),
    textSecondary: Color(0xFF5A5D63),
    // Was #9AA0A6: 2.42 on panel, 2.12 in a well. Now 4.56 on the canvas,
    // 4.85 on panel, 5.29 on white and 4.24 in a well.
    textTertiary: Color(0xFF676C73),
    accent: Color(0xFF336FE6),
    accentHover: Color(0xFF2F66D4),
    accentPressed: Color(0xFF244EA1),
    // #336FE6 @ 10% alpha.
    accentSubtle: Color(0x1A336FE6),
    onAccent: Color(0xFFFFFFFF),
    onAccentSubtle: Color(0xFF2B5EC2),
    success: Color(0xFF3D8B40),
    warning: Color(0xFFB8860B),
    danger: Color(0xFFC4453D),
    dangerText: Color(0xFFA93A33),
    successText: Color(0xFF2B7030),
    warningText: Color(0xFF7F5C06),
    selectionBg: Color(0xFFD4E2FF),
    // #000000 @ 5% alpha.
    hoverBg: Color(0x0D000000),
  );

  /// Returns the token set matching [brightness].
  static StudioColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  StudioColors copyWith({
    Color? canvas,
    Color? panel,
    Color? panelAlt,
    Color? well,
    Color? overlay,
    Color? control,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentSubtle,
    Color? onAccentSubtle,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerText,
    Color? successText,
    Color? warningText,
    Color? selectionBg,
    Color? hoverBg,
  }) {
    return StudioColors(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      panelAlt: panelAlt ?? this.panelAlt,
      well: well ?? this.well,
      overlay: overlay ?? this.overlay,
      control: control ?? this.control,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      onAccentSubtle: onAccentSubtle ?? this.onAccentSubtle,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      dangerText: dangerText ?? this.dangerText,
      successText: successText ?? this.successText,
      warningText: warningText ?? this.warningText,
      selectionBg: selectionBg ?? this.selectionBg,
      hoverBg: hoverBg ?? this.hoverBg,
    );
  }

  /// Linearly interpolates every token between [a] and [b].
  static StudioColors lerp(StudioColors a, StudioColors b, double t) {
    if (identical(a, b)) return a;
    Color c(Color x, Color y) => Color.lerp(x, y, t) ?? x;
    return StudioColors(
      canvas: c(a.canvas, b.canvas),
      panel: c(a.panel, b.panel),
      panelAlt: c(a.panelAlt, b.panelAlt),
      well: c(a.well, b.well),
      overlay: c(a.overlay, b.overlay),
      control: c(a.control, b.control),
      border: c(a.border, b.border),
      borderSubtle: c(a.borderSubtle, b.borderSubtle),
      borderStrong: c(a.borderStrong, b.borderStrong),
      textPrimary: c(a.textPrimary, b.textPrimary),
      textSecondary: c(a.textSecondary, b.textSecondary),
      textTertiary: c(a.textTertiary, b.textTertiary),
      accent: c(a.accent, b.accent),
      accentHover: c(a.accentHover, b.accentHover),
      accentPressed: c(a.accentPressed, b.accentPressed),
      accentSubtle: c(a.accentSubtle, b.accentSubtle),
      onAccentSubtle: c(a.onAccentSubtle, b.onAccentSubtle),
      onAccent: c(a.onAccent, b.onAccent),
      success: c(a.success, b.success),
      warning: c(a.warning, b.warning),
      danger: c(a.danger, b.danger),
      dangerText: c(a.dangerText, b.dangerText),
      successText: c(a.successText, b.successText),
      warningText: c(a.warningText, b.warningText),
      selectionBg: c(a.selectionBg, b.selectionBg),
      hoverBg: c(a.hoverBg, b.hoverBg),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudioColors &&
        other.canvas == canvas &&
        other.panel == panel &&
        other.panelAlt == panelAlt &&
        other.well == well &&
        other.overlay == overlay &&
        other.control == control &&
        other.border == border &&
        other.borderSubtle == borderSubtle &&
        other.borderStrong == borderStrong &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textTertiary == textTertiary &&
        other.accent == accent &&
        other.accentHover == accentHover &&
        other.accentPressed == accentPressed &&
        other.accentSubtle == accentSubtle &&
        other.onAccentSubtle == onAccentSubtle &&
        other.onAccent == onAccent &&
        other.success == success &&
        other.warning == warning &&
        other.danger == danger &&
        other.dangerText == dangerText &&
        other.successText == successText &&
        other.warningText == warningText &&
        other.selectionBg == selectionBg &&
        other.hoverBg == hoverBg;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    canvas,
    panel,
    panelAlt,
    well,
    overlay,
    control,
    border,
    borderSubtle,
    borderStrong,
    textPrimary,
    textSecondary,
    textTertiary,
    accent,
    accentHover,
    accentPressed,
    accentSubtle,
    onAccentSubtle,
    onAccent,
    success,
    warning,
    danger,
    dangerText,
    successText,
    warningText,
    selectionBg,
    hoverBg,
  ]);
}

/// Neutral, brightness-independent inks used only by overlay chrome.
///
/// These are not part of [StudioColors] because they never vary with the theme:
/// a scrim is the same black behind a light dialog as a dark one, and
/// "transparent" has no light/dark variant. They live here so that
/// `studio_tokens.dart` remains the single file in the app that spells out a
/// chrome colour literal.
abstract final class StudioInk {
  /// Fully transparent. Used to suppress Material's splashes, surface tints and
  /// default shadows across the theme.
  static const Color transparent = Color(0x00000000);

  /// The opaque base colour Material derives its own shadows from.
  static const Color shadowOpaque = Color(0xFF000000);

  /// Modal barrier behind dialogs and bottom sheets.
  static const Color scrim = Color(0x99000000);

  /// Overlay shadow on a dark theme — stronger, since it must read against a
  /// dark surface.
  static const Color shadowDark = Color(0x8C000000);

  /// Overlay shadow on a light theme — tight and subtle, per the "no heavy
  /// drop shadows" rule.
  static const Color shadowLight = Color(0x33000000);
}

/// Corner radii. Never use a value off this scale.
///
/// `full` is reserved for avatars and status dots — buttons and chips are
/// never pill-shaped.
abstract final class StudioRadius {
  /// Tool buttons, swatches, checkboxes.
  static const double xs = 4;

  /// Buttons, inputs, chips, segmented controls.
  static const double sm = 6;

  /// Cards, panels, popup menus.
  static const double md = 8;

  /// Dialogs, bottom sheet top corners.
  static const double lg = 12;

  /// Avatars and dots only.
  static const double full = 999;
}

/// The spacing scale. Never use a value off this scale.
abstract final class StudioSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 6;
  static const double m = 8;
  static const double l = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 24;
  static const double huge = 32;
}

/// Fixed control heights. Touch targets stay >= 44px via padding even when the
/// painted control is smaller.
///
/// The first group is the desktop density, which is a feature there: a mouse
/// hits a 30px button every time. Where touch is the primary input the
/// components switch to the second group on their own (they read
/// `context.layout.isTouchPrimary`), because a 36px button is under both
/// Apple's 44pt and Material's 48dp.
abstract final class StudioSizes {
  static const double toolbar = 48;
  static const double toolButton = 32;
  static const double buttonCompact = 30;
  static const double button = 36;
  static const double input = 34;
  static const double listRow = 44;
  static const double tabStrip = 64;

  /// The smallest hit area anything tappable gets on a touch screen.
  static const double touchTarget = 44;

  /// A standard button where touch is primary.
  static const double buttonTouch = 44;

  /// A dense button where touch is primary — painted at the desktop's
  /// standard height, with its hit area padded out to [touchTarget].
  static const double buttonTouchDense = 36;

  /// The primary call to action in a dock or a form footer, where touch is
  /// primary: the one button on the screen that should never be missed.
  static const double buttonTall = 48;

  /// A segmented control where touch is primary.
  static const double segmentedTouch = 40;

  /// A chip's painted height where touch is primary; its hit area is padded
  /// out to [touchTarget].
  static const double chipTouch = 32;
}

/// Motion durations. Chrome moves quickly and without bounce.
///
/// Read them through `context.motion(...)` wherever something animates, so a
/// system asking for reduced motion gets none.
abstract final class StudioDuration {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);
}

/// Reduced motion, honoured in one place.
extension StudioMotionX on BuildContext {
  /// Whether the platform has asked for animations to be turned off — iOS
  /// "Reduce Motion", Android "Remove animations", the browser's
  /// `prefers-reduced-motion`.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// [duration], or zero when the platform asks for reduced motion.
  ///
  /// Zero rather than a shorter animation: an implicit animation given
  /// [Duration.zero] jumps straight to its end, which is exactly what
  /// "remove animations" means, and nothing else about the widget changes.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;
}

/// Carries [StudioColors] through [ThemeData.extensions].
@immutable
class StudioThemeExt extends ThemeExtension<StudioThemeExt> {
  const StudioThemeExt({required this.colors});

  final StudioColors colors;

  @override
  StudioThemeExt copyWith({StudioColors? colors}) =>
      StudioThemeExt(colors: colors ?? this.colors);

  @override
  StudioThemeExt lerp(ThemeExtension<StudioThemeExt>? other, double t) {
    if (other is! StudioThemeExt) return this;
    return StudioThemeExt(colors: StudioColors.lerp(colors, other.colors, t));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudioThemeExt && other.colors == colors);

  @override
  int get hashCode => colors.hashCode;
}

/// Ergonomic access to the design tokens from any [BuildContext].
extension StudioContextX on BuildContext {
  /// The active [StudioColors].
  ///
  /// Reads [StudioThemeExt] from the theme and falls back to the token set
  /// matching the ambient brightness if the extension is absent, so this never
  /// throws and never force-unwraps a null.
  StudioColors get studio {
    final ThemeData theme = Theme.of(this);
    final StudioThemeExt? ext = theme.extension<StudioThemeExt>();
    return ext?.colors ?? StudioColors.of(theme.brightness);
  }

  /// Whether the active theme is dark.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
