import 'dart:math';

import 'package:flutter/painting.dart';

/// How a rolled palette arranges its hues around the wheel.
///
/// Random RGB is the obvious implementation and it is unusable: three
/// independent channels land on mud far more often than on anything you would
/// ship, and the one time in ten it does not, it still has no relationship
/// between its colours. Every roll here picks *one* hue and derives the rest
/// from it through a named harmony, which is what makes the results look
/// chosen rather than generated.
enum PaletteHarmony {
  /// Neighbours on the wheel. Calm, and the safest with four stops.
  analogous,

  /// Opposite hues. The most contrast two colours can have.
  complementary,

  /// Three evenly spaced hues — vivid without any pair clashing.
  triadic,

  /// The complement's two neighbours instead of the complement itself. Nearly
  /// as much contrast, noticeably less tension.
  splitComplementary,

  /// One hue throughout, separated by lightness alone. The look most store
  /// listings actually ship.
  monochrome,
}

/// A generated backdrop palette: a base fill followed by motif colours.
///
/// The first entry is the background the pattern painters fill with, and the
/// rest paint the motif over it — see `PatternBackground.colors`. They are
/// generated together because the relationship between them is the whole
/// point: a motif needs to sit *on* its base with enough separation to read,
/// and picking the two independently is how you get a pattern nobody can see.
///
/// Deterministic in [seed], so a roll can be reproduced, stored and re-rendered
/// — the same property `PatternBackground.seed` gives the layout.
List<Color> rollPalette({
  required int count,
  required int seed,
  PaletteHarmony? harmony,
  bool? dark,
}) {
  final random = Random(seed);
  final stops = count.clamp(2, 4);
  final scheme =
      harmony ??
      PaletteHarmony.values[random.nextInt(PaletteHarmony.values.length)];

  final baseHue = random.nextDouble() * 360;
  // Both grounds, roughly evenly. A generator that only ever produced dark
  // backdrops would quietly halve the range of listings it is useful for.
  final onDark = dark ?? random.nextBool();

  final offsets = switch (scheme) {
    PaletteHarmony.analogous => [0.0, 24.0, 48.0, 72.0],
    PaletteHarmony.complementary => [0.0, 180.0, 18.0, 198.0],
    PaletteHarmony.triadic => [0.0, 120.0, 240.0, 60.0],
    PaletteHarmony.splitComplementary => [0.0, 150.0, 210.0, 30.0],
    PaletteHarmony.monochrome => [0.0, 0.0, 0.0, 0.0],
  };

  /// A hue jittered a few degrees, so two rolls of the same harmony are not
  /// the same picture in a different key.
  double hueAt(int i) =>
      (baseHue + offsets[i] + (random.nextDouble() - 0.5) * 8) % 360;

  final colors = <Color>[];

  // The base. Deep and desaturated on a dark ground, pale and soft on a light
  // one: a base as saturated as the motif competes with it.
  colors.add(
    HSLColor.fromAHSL(
      1,
      hueAt(0),
      onDark
          ? 0.34 + random.nextDouble() * 0.22
          : 0.26 + random.nextDouble() * 0.30,
      onDark
          ? 0.09 + random.nextDouble() * 0.07
          : 0.90 + random.nextDouble() * 0.06,
    ).toColor(),
  );

  for (var i = 1; i < stops; i++) {
    // Monochrome separates by lightness, so it needs its own ramp; the others
    // already separate by hue and only need to stay clear of the base.
    final lightness = scheme == PaletteHarmony.monochrome
        ? (onDark ? 0.30 + i * 0.16 : 0.62 - i * 0.14)
        : (onDark
              ? 0.54 + random.nextDouble() * 0.16
              : 0.44 + random.nextDouble() * 0.14);
    colors.add(
      HSLColor.fromAHSL(
        1,
        hueAt(i),
        0.62 + random.nextDouble() * 0.28,
        lightness.clamp(0.08, 0.92),
      ).toColor(),
    );
  }

  return colors;
}

/// A palette whose motif is guaranteed to read against its own base.
///
/// [rollPalette] can land on a base and a motif close enough in luminance that
/// the pattern disappears — rarely, but "rarely" is once every dozen taps of a
/// button people tap repeatedly. This re-rolls until the first motif colour
/// clears [minContrast] against the base, then gives up and returns the best it
/// saw rather than looping forever.
List<Color> rollReadablePalette({
  required int count,
  required int seed,
  double minContrast = 1.9,
  int attempts = 12,
}) {
  List<Color>? best;
  var bestRatio = 0.0;

  for (var i = 0; i < attempts; i++) {
    final colors = rollPalette(count: count, seed: seed + i * 7919);
    final ratio = _contrast(colors.first, colors[1]);
    if (ratio >= minContrast) return colors;
    if (ratio > bestRatio) {
      bestRatio = ratio;
      best = colors;
    }
  }
  return best!;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
