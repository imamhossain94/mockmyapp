import 'package:flutter/material.dart';

import 'studio_tokens.dart';
import 'studio_typography.dart';

/// Builds the light and dark [ThemeData] for MockMyApp from [StudioColors].
///
/// The scheme is written out by hand rather than derived with
/// `ColorScheme.fromSeed`, because seeding would tonally recolour the neutral
/// greys into blue-tinted Material greys and destroy the Photoshop/JetBrains
/// feel. Every colour below traces back to a token.
abstract final class StudioAppTheme {
  static ThemeData light() => _build(StudioColors.light, Brightness.light);

  static ThemeData dark() => _build(StudioColors.dark, Brightness.dark);

  /// Builds the full studio theme from an arbitrary token set.
  ///
  /// This exists so Material-You dynamic colour can re-tint the accent family
  /// (and only the accent family) while every neutral grey, radius, hairline
  /// and control geometry below stays exactly as specified. Callers pass a
  /// [StudioColors.dark]/[StudioColors.light] `copyWith` — never a set of
  /// invented colours.
  static ThemeData fromColors(StudioColors colors, Brightness brightness) =>
      _build(colors, brightness);

  // ---------------------------------------------------------------------------

  static ThemeData _build(StudioColors c, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = _scheme(c, brightness);
    final TextTheme text = StudioText.textTheme(c);

    // Overlays are the only place a shadow is allowed, and it stays tight.
    final Color shadow = isDark ? _shadowDark : _shadowLight;

    // Neutral state washes. Translucent so they adapt to whatever surface the
    // control happens to sit on.
    final Color hover = c.hoverBg;
    final Color pressed = _amplify(c.hoverBg, 2);
    final Color accentHoverWash = c.accentSubtle;
    final Color accentPressedWash = _amplify(c.accentSubtle, 1.6);

    final BorderRadius radiusSm = BorderRadius.circular(StudioRadius.sm);
    final BorderRadius radiusMd = BorderRadius.circular(StudioRadius.md);
    final BorderRadius radiusLg = BorderRadius.circular(StudioRadius.lg);

    OutlineInputBorder inputBorder(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: radiusSm,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[StudioThemeExt(colors: c)],

      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.panel,
      dividerColor: c.border,
      shadowColor: shadow,
      hoverColor: hover,
      focusColor: accentHoverWash,
      highlightColor: pressed,
      // IDE and image-editor chrome does not ripple.
      splashColor: _transparent,
      splashFactory: NoSplash.splashFactory,

      textTheme: text,
      primaryTextTheme: text,

      iconTheme: IconThemeData(size: 16, color: c.textSecondary),
      primaryIconTheme: IconThemeData(size: 16, color: c.textSecondary),

      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: 1,
        indent: 0,
        endIndent: 0,
      ),

      appBarTheme: AppBarThemeData(
        toolbarHeight: StudioSizes.toolbar,
        backgroundColor: c.panel,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: _transparent,
        surfaceTintColor: _transparent,
        centerTitle: false,
        titleSpacing: StudioSpace.l,
        // The hairline, not a shadow, is what separates chrome from content.
        shape: Border(bottom: BorderSide(color: c.border, width: 1)),
        titleTextStyle: StudioText.titleLargeFor(c),
        toolbarTextStyle: StudioText.bodyFor(c),
        iconTheme: IconThemeData(size: 18, color: c.textSecondary),
        actionsIconTheme: IconThemeData(size: 18, color: c.textSecondary),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(
          textStyle: StudioText.bodyStrongFor(c, color: c.onAccent),
          foreground: c.onAccent,
          disabledForeground: c.textTertiary,
          background: c.accent,
          hoveredBackground: c.accentHover,
          pressedBackground: c.accentPressed,
          disabledBackground: c.well,
          side: null,
          radius: radiusSm,
        ),
      ),

      // Formerly outlined; now a filled neutral button (the `control` fill, no
      // border) so a bare OutlinedButton matches the filled language — and
      // still has an edge inside a `panelAlt` panel, which it did not when it
      // was filled with `panelAlt` itself.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          textStyle: StudioText.bodyStrongFor(c),
          foreground: c.textPrimary,
          disabledForeground: c.textTertiary,
          background: c.control,
          hoveredBackground: Color.alphaBlend(hover, c.control),
          pressedBackground: Color.alphaBlend(pressed, c.control),
          disabledBackground: c.control.withValues(alpha: 0.5),
          side: null,
          radius: radiusSm,
        ),
      ),

      // Accent *text*, so `accentText`: the `accent` fill measured 3.0 as words
      // on the dark panel.
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(
          textStyle: StudioText.bodyStrongFor(c, color: c.accentText),
          foreground: c.accentText,
          disabledForeground: c.textTertiary,
          background: _transparent,
          hoveredBackground: accentHoverWash,
          pressedBackground: accentPressedWash,
          disabledBackground: _transparent,
          side: null,
          radius: radiusSm,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconSize: const WidgetStatePropertyAll<double>(16),
          iconColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) return c.textTertiary;
            if (states.contains(WidgetState.selected)) return c.accentText;
            return c.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.pressed)) return pressed;
            if (states.contains(WidgetState.hovered)) return hover;
            return _transparent;
          }),
          overlayColor: const WidgetStatePropertyAll<Color>(_transparent),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadius.xs),
            ),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size.square(StudioSizes.toolButton),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.all(StudioSpace.m),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.well,
        isDense: true,
        constraints: const BoxConstraints(minHeight: StudioSizes.input),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: StudioSpace.m,
          vertical: StudioSpace.m,
        ),
        // Filled, not outlined: resting/disabled fields carry no visible edge —
        // the `well` fill is the field. Only the transient focus/error states
        // paint an accent/danger line.
        border: inputBorder(_transparent),
        enabledBorder: inputBorder(_transparent),
        focusedBorder: inputBorder(c.accent),
        disabledBorder: inputBorder(_transparent),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger),
        hintStyle: StudioText.bodyFor(c, color: c.textTertiary),
        labelStyle: StudioText.captionFor(c),
        floatingLabelStyle: StudioText.captionFor(c, color: c.accentText),
        helperStyle: StudioText.captionFor(c, color: c.textSecondary),
        errorStyle: StudioText.captionFor(c, color: c.dangerText),
        prefixStyle: StudioText.bodyFor(c),
        suffixStyle: StudioText.bodyFor(c),
        iconColor: c.textSecondary,
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        hoverColor: _transparent,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 2,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.border,
        disabledActiveTrackColor: c.textTertiary,
        disabledInactiveTrackColor: c.borderSubtle,
        thumbColor: c.accent,
        disabledThumbColor: c.textTertiary,
        overlayColor: c.accentSubtle,
        activeTickMarkColor: c.onAccent,
        inactiveTickMarkColor: c.textTertiary,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6,
          disabledThumbRadius: 6,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
        valueIndicatorColor: c.panelAlt,
        valueIndicatorTextStyle: StudioText.monoFor(c),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) return c.textTertiary;
          if (states.contains(WidgetState.selected)) return c.onAccent;
          return c.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) return c.borderSubtle;
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.well;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) return c.borderSubtle;
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.borderStrong;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll<double>(1),
        overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.pressed)) return accentPressedWash;
          if (states.contains(WidgetState.hovered)) return accentHoverWash;
          return _transparent;
        }),
        splashRadius: 16,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) return c.borderSubtle;
          if (states.contains(WidgetState.selected)) return c.accent;
          return _transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(c.onAccent),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: c.borderSubtle, width: 1.5);
          }
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: c.accent, width: 1.5);
          }
          return BorderSide(color: c.borderStrong, width: 1.5);
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.pressed)) return accentPressedWash;
          if (states.contains(WidgetState.hovered)) return accentHoverWash;
          return _transparent;
        }),
        splashRadius: 14,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) return c.borderSubtle;
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.borderStrong;
        }),
        overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.pressed)) return accentPressedWash;
          if (states.contains(WidgetState.hovered)) return accentHoverWash;
          return _transparent;
        }),
        splashRadius: 14,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(
            StudioText.bodyStrongFor(c),
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) return c.textTertiary;
            if (states.contains(WidgetState.selected)) return c.textPrimary;
            return c.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) return _transparent;
            if (states.contains(WidgetState.selected)) return c.selectionBg;
            if (states.contains(WidgetState.pressed)) return pressed;
            if (states.contains(WidgetState.hovered)) return hover;
            return _transparent;
          }),
          iconColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) return c.textTertiary;
            if (states.contains(WidgetState.selected)) return c.textPrimary;
            return c.textSecondary;
          }),
          iconSize: const WidgetStatePropertyAll<double>(16),
          overlayColor: const WidgetStatePropertyAll<Color>(_transparent),
          // Filled cells, no outline: the selected `selectionBg` fill is the
          // only edge the control needs.
          side: const WidgetStatePropertyAll<BorderSide>(BorderSide.none),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: radiusSm),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, StudioSizes.buttonCompact),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: StudioSpace.l),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.panel,
        modalBackgroundColor: c.panel,
        surfaceTintColor: _transparent,
        elevation: 0,
        modalElevation: 0,
        shadowColor: _transparent,
        clipBehavior: Clip.antiAlias,
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(StudioSpace.huge, StudioSpace.xs),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(StudioRadius.lg),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.overlay,
        surfaceTintColor: _transparent,
        elevation: 8,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: c.border, width: 1),
        ),
        titleTextStyle: StudioText.titleSmallFor(c),
        contentTextStyle: StudioText.bodyFor(c),
        iconColor: c.textSecondary,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: StudioSpace.xxxl,
          vertical: StudioSpace.xxxl,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          StudioSpace.xl,
          StudioSpace.m,
          StudioSpace.xl,
          StudioSpace.l,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: c.overlay,
        surfaceTintColor: _transparent,
        elevation: 4,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: c.border, width: 1),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: StudioSpace.xs),
        textStyle: StudioText.bodyFor(c),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          if (states.contains(WidgetState.disabled)) {
            return StudioText.bodyFor(c, color: c.textTertiary);
          }
          return StudioText.bodyFor(c);
        }),
        iconColor: c.textSecondary,
        iconSize: 16,
        position: PopupMenuPosition.under,
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.overlay),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(_transparent),
          shadowColor: WidgetStatePropertyAll<Color>(shadow),
          elevation: const WidgetStatePropertyAll<double>(4),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(vertical: StudioSpace.xs),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: radiusMd,
              side: BorderSide(color: c.border, width: 1),
            ),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.panelAlt,
        contentTextStyle: StudioText.bodyFor(c),
        actionTextColor: c.accentText,
        disabledActionTextColor: c.textTertiary,
        closeIconColor: c.textSecondary,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(StudioSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: c.border, width: 1),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.panelAlt,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
          border: Border.all(color: c.border, width: 1),
        ),
        textStyle: StudioText.captionFor(c, color: c.textPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: StudioSpace.m,
          vertical: StudioSpace.s,
        ),
        margin: const EdgeInsets.symmetric(horizontal: StudioSpace.m),
        waitDuration: const Duration(milliseconds: 500),
        preferBelow: false,
      ),

      // Filled, borderless: a card is a raised `panelAlt` fill that separates
      // from the surface behind it by tone, not by a hairline.
      cardTheme: CardThemeData(
        color: c.panelAlt,
        surfaceTintColor: _transparent,
        shadowColor: _transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.control,
        selectedColor: c.selectionBg,
        secondarySelectedColor: c.selectionBg,
        disabledColor: c.borderSubtle,
        checkmarkColor: c.accent,
        labelStyle: StudioText.captionFor(c, color: c.textPrimary),
        secondaryLabelStyle: StudioText.captionFor(c, color: c.textPrimary),
        labelPadding: const EdgeInsets.symmetric(horizontal: StudioSpace.s),
        padding: const EdgeInsets.symmetric(
          horizontal: StudioSpace.m,
          vertical: StudioSpace.s,
        ),
        // Filled, not outlined — the `control`/`selectionBg` fill is the edge.
        side: BorderSide.none,
        // Explicitly not a stadium: chips are 6px rounded rectangles.
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        iconTheme: IconThemeData(size: 14, color: c.textSecondary),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: true,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: _transparent,
        selectedTileColor: c.selectionBg,
        selectedColor: c.textPrimary,
        textColor: c.textPrimary,
        iconColor: c.textSecondary,
        minVerticalPadding: StudioSpace.m,
        horizontalTitleGap: StudioSpace.l,
        minLeadingWidth: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: StudioSpace.l),
        titleTextStyle: StudioText.bodyFor(c),
        subtitleTextStyle: StudioText.captionFor(c),
        leadingAndTrailingTextStyle: StudioText.captionFor(c),
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: c.accentText,
        unselectedLabelColor: c.textSecondary,
        labelStyle: StudioText.microFor(c, color: c.accentText),
        unselectedLabelStyle: StudioText.microFor(c, color: c.textSecondary),
        indicatorColor: c.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: c.border,
        dividerHeight: 1,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.pressed)) return pressed;
          if (states.contains(WidgetState.hovered)) return hover;
          return _transparent;
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.border,
        circularTrackColor: c.border,
        linearMinHeight: 2,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(StudioSpace.s),
        radius: const Radius.circular(StudioRadius.xs),
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)) {
            return c.textTertiary;
          }
          return c.borderStrong;
        }),
        trackColor: const WidgetStatePropertyAll<Color>(_transparent),
        trackBorderColor: const WidgetStatePropertyAll<Color>(_transparent),
        crossAxisMargin: StudioSpace.xxs,
        mainAxisMargin: StudioSpace.xxs,
        interactive: true,
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: _transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: _transparent,
        indicatorColor: c.selectionBg,
        elevation: 0,
        height: StudioSizes.tabStrip,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return StudioText.microFor(
            c,
            color: selected ? c.textPrimary : c.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 20,
            color: selected ? c.accentText : c.textSecondary,
          );
        }),
        indicatorShape: RoundedRectangleBorder(borderRadius: radiusSm),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Colour scheme
  // ---------------------------------------------------------------------------

  static ColorScheme _scheme(StudioColors c, Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.selectionBg,
      onPrimaryContainer: c.textPrimary,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.selectionBg,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.success,
      onTertiary: c.onAccent,
      tertiaryContainer: c.panelAlt,
      onTertiaryContainer: c.textPrimary,
      error: c.danger,
      onError: c.onAccent,
      errorContainer: c.panelAlt,
      onErrorContainer: c.danger,
      surface: c.panel,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceDim: c.canvas,
      surfaceBright: c.panelAlt,
      surfaceContainerLowest: c.canvas,
      surfaceContainerLow: c.well,
      surfaceContainer: c.panel,
      surfaceContainerHigh: c.panelAlt,
      surfaceContainerHighest: c.panelAlt,
      outline: c.border,
      outlineVariant: c.borderSubtle,
      shadow: _shadowOpaque,
      scrim: _scrim,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.panel,
      inversePrimary: c.accentHover,
      // Flat surfaces: never let M3 elevation tint the greys.
      surfaceTint: _transparent,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Shared button geometry: fixed 36px height, 6px radius, zero elevation and
  /// explicit hover/pressed background colours instead of a ripple.
  static ButtonStyle _buttonStyle({
    required TextStyle textStyle,
    required Color foreground,
    required Color disabledForeground,
    required Color background,
    required Color hoveredBackground,
    required Color pressedBackground,
    required Color disabledBackground,
    required WidgetStateProperty<BorderSide>? side,
    required BorderRadius radius,
  }) {
    return ButtonStyle(
      textStyle: WidgetStatePropertyAll<TextStyle>(textStyle),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) return disabledForeground;
        return foreground;
      }),
      iconColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) return disabledForeground;
        return foreground;
      }),
      iconSize: const WidgetStatePropertyAll<double>(16),
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) return disabledBackground;
        if (states.contains(WidgetState.pressed)) return pressedBackground;
        if (states.contains(WidgetState.hovered)) return hoveredBackground;
        return background;
      }),
      // No ripple, no highlight bloom — the background colour is the feedback.
      overlayColor: const WidgetStatePropertyAll<Color>(_transparent),
      side: side,
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      elevation: const WidgetStatePropertyAll<double>(0),
      shadowColor: const WidgetStatePropertyAll<Color>(_transparent),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(_transparent),
      minimumSize: const WidgetStatePropertyAll<Size>(
        Size(0, StudioSizes.button),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: StudioSpace.xl),
      ),
      alignment: Alignment.center,
      splashFactory: NoSplash.splashFactory,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      animationDuration: StudioDuration.fast,
    );
  }

  /// Multiplies a translucent wash's alpha, keeping it token-derived.
  static Color _amplify(Color color, double factor) =>
      color.withValues(alpha: (color.a * factor).clamp(0.0, 1.0));

  // Overlay inks live in studio_tokens.dart so this file spells out no colour
  // literal of its own. Aliased here to keep the call sites below terse.
  static const Color _transparent = StudioInk.transparent;
  static const Color _shadowOpaque = StudioInk.shadowOpaque;
  static const Color _scrim = StudioInk.scrim;
  static const Color _shadowDark = StudioInk.shadowDark;
  static const Color _shadowLight = StudioInk.shadowLight;
}
