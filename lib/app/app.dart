import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/providers/settings_provider.dart';
import 'layout/studio_layout.dart';
import 'router.dart';
import 'theme/studio_theme.dart';
import 'theme/studio_tokens.dart';

class MockMyApp extends ConsumerWidget {
  const MockMyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // The default path: our tokens verbatim. No seeding, no tonal palettes —
    // ColorScheme.fromSeed would recolour the neutral greys into blue-tinted
    // Material greys and destroy the Photoshop/JetBrains identity.
    if (!settings.dynamicColorEnabled) {
      return MaterialApp.router(
        title: 'MockMyApp',
        debugShowCheckedModeBanner: false,
        theme: StudioAppTheme.light(),
        darkTheme: StudioAppTheme.dark(),
        themeMode: settings.themeMode,
        routerConfig: appRouter,
        builder: StudioLayoutScope.wrap,
      );
    }

    // Dynamic colour is opt-in. Even then it only re-tints the accent family:
    // the wallpaper picks the blue, our tokens keep the greys.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp.router(
          title: 'MockMyApp',
          debugShowCheckedModeBanner: false,
          theme: _harmonized(
            StudioColors.light,
            lightDynamic,
            Brightness.light,
          ),
          darkTheme: _harmonized(
            StudioColors.dark,
            darkDynamic,
            Brightness.dark,
          ),
          themeMode: settings.themeMode,
          routerConfig: appRouter,
          builder: StudioLayoutScope.wrap,
        );
      },
    );
  }

  /// Rebuilds the studio theme with [dynamicScheme]'s primary substituted for
  /// our accent.
  ///
  /// Everything else — canvas, panel, well, every hairline, every text tone —
  /// comes from [base] untouched, and the [StudioThemeExt] carried by the
  /// result stays intact so `context.studio` keeps working. Falls back to
  /// [base] verbatim when the platform exposes no dynamic scheme.
  static ThemeData _harmonized(
    StudioColors base,
    ColorScheme? dynamicScheme,
    Brightness brightness,
  ) {
    if (dynamicScheme == null) {
      return StudioAppTheme.fromColors(base, brightness);
    }

    final bool isDark = brightness == Brightness.dark;
    final Color accent = dynamicScheme.primary;

    return StudioAppTheme.fromColors(
      base.copyWith(
        accent: accent,
        // Dark lifts on hover and drops on press; light darkens for both.
        accentHover: _shiftLightness(accent, isDark ? 0.05 : -0.07),
        accentPressed: _shiftLightness(accent, isDark ? -0.07 : -0.147),
        accentSubtle: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        onAccent: dynamicScheme.onPrimary,
        // Selected rows are an opaque accent wash over the canvas, matching how
        // the hand-authored selectionBg tokens are constructed.
        selectionBg: Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.35 : 0.16),
          base.canvas,
        ),
      ),
      brightness,
    );
  }

  /// Nudges a colour's HSL lightness, staying in gamut.
  static Color _shiftLightness(Color color, double delta) {
    final HSLColor hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }
}
