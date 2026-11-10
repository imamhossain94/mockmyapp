import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/painting.dart';

/// A colour transform in the shape [ColorFilter.matrix] takes: four rows of
/// five, row-major, with the fifth column — the offset — in 0–255 space.
///
/// Every tone and colour control in the photo editor is one of these, and they
/// are multiplied into a single matrix before anything is drawn. `ColorFilter`
/// does not compose, so chaining filters would mean a `saveLayer` over the
/// whole photo per control on every frame of a slider drag; one matrix on the
/// image paint costs nothing.
@immutable
class ColorMatrix {
  /// [values] must hold exactly 20 numbers.
  const ColorMatrix(this.values);

  final List<double> values;

  static const identity = ColorMatrix([
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// Scales the three colour channels and adds [offset] to each, in 0–255.
  factory ColorMatrix.channels(
    double r,
    double g,
    double b, {
    double offset = 0,
  }) => ColorMatrix([
    r, 0, 0, 0, offset, //
    0, g, 0, 0, offset,
    0, 0, b, 0, offset,
    0, 0, 0, 1, 0,
  ]);

  /// Every channel scaled by [scale] about [pivot] (0–255).
  factory ColorMatrix.scaleAbout(double scale, double pivot) =>
      ColorMatrix.channels(scale, scale, scale, offset: pivot * (1 - scale));

  /// Saturation, where 1 is untouched, 0 grey and 2 roughly double.
  ///
  /// Rec. 601 luma, which is what Skia's own saturation matrix uses, so a grey
  /// comes back the grey it was.
  factory ColorMatrix.saturation(double s) {
    const lr = 0.213, lg = 0.715, lb = 0.072;
    double at(double luma, bool diagonal) =>
        diagonal ? luma * (1 - s) + s : luma * (1 - s);
    return ColorMatrix([
      at(lr, true), at(lg, false), at(lb, false), 0, 0, //
      at(lr, false), at(lg, true), at(lb, false), 0, 0,
      at(lr, false), at(lg, false), at(lb, true), 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  /// The classic sepia tone.
  static const sepia = ColorMatrix([
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// This transform, then [next] — the matrix that does both in one pass.
  ColorMatrix then(ColorMatrix next) {
    final a = values, b = next.values;
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += b[row * 5 + k] * a[k * 5 + col];
        }
        // The implied fifth row of each matrix is [0 0 0 0 1], so only the
        // offset column picks up the second matrix's own offset.
        if (col == 4) sum += b[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return ColorMatrix(out);
  }

  /// [t] of the way from untouched to this — how a filter's strength works.
  ColorMatrix strength(double t) {
    final k = t.clamp(0.0, 1.0);
    if (k == 1) return this;
    if (k == 0) return identity;
    return ColorMatrix([
      for (var i = 0; i < 20; i++)
        identity.values[i] + (values[i] - identity.values[i]) * k,
    ]);
  }

  bool get isIdentity {
    for (var i = 0; i < 20; i++) {
      if ((values[i] - identity.values[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  ColorFilter toFilter() => ColorFilter.matrix(values);

  /// [color] through this matrix, clamped — what the painter would draw.
  Color apply(Color color) {
    final r = color.r * 255, g = color.g * 255, b = color.b * 255;
    final a = color.a * 255;
    double row(int i) =>
        values[i * 5] * r +
        values[i * 5 + 1] * g +
        values[i * 5 + 2] * b +
        values[i * 5 + 3] * a +
        values[i * 5 + 4];
    int c(double v) => v.round().clamp(0, 255);
    return Color.fromARGB(c(row(3)), c(row(0)), c(row(1)), c(row(2)));
  }

  @override
  bool operator ==(Object other) =>
      other is ColorMatrix && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

/// The tone and colour controls, as one matrix each.
///
/// Every argument is centred on zero meaning "untouched", -1–1 unless noted.
/// Kept apart from `ImageAdjustments` so a filter — which is a set of these
/// dialled in together — can build its look from the same arithmetic the
/// sliders use, rather than from a second, slightly different copy.
abstract final class Tone {
  /// Lifts or lowers the picture through its middle: at full strength black
  /// moves an eighth of the way and mid-grey a quarter.
  ///
  /// A plain offset — every level moved by the same amount — is what turned a
  /// dark screenshot's black to flat grey long before the slider got anywhere
  /// near its end. The scale takes some of the work, so the bright end moves
  /// more than the dark end, as it does in the eye.
  static ColorMatrix brightness(double v) {
    final b = v.clamp(-1.0, 1.0);
    final k = 1 + _brightnessScale * b;
    return ColorMatrix.channels(k, k, k, offset: _brightnessOffset * 255 * b);
  }

  static const _brightnessScale = 0.25;
  static const _brightnessOffset = 0.12;

  /// Scales each channel about mid-grey.
  static ColorMatrix contrast(double v) =>
      ColorMatrix.scaleAbout((1 + v).clamp(0.0, 2.0), 128);

  /// -1 is fully grey, 1 roughly double.
  static ColorMatrix saturation(double v) =>
      ColorMatrix.saturation((1 + v).clamp(0.0, 2.0));

  /// A stop either way: multiplies the light, keeps black black.
  static ColorMatrix exposure(double v) {
    final k = math.pow(2, v.clamp(-1.0, 1.0)).toDouble();
    return ColorMatrix.channels(k, k, k);
  }

  /// Positive brightens the bright end and leaves black where it is;
  /// negative pulls it back. Pivots on black, the mirror of [shadows].
  static ColorMatrix highlights(double v) =>
      ColorMatrix.scaleAbout(1 + 0.35 * v.clamp(-1.0, 1.0), 0);

  /// Positive lifts the dark end and leaves white where it is; negative
  /// deepens it. Pivots on white.
  static ColorMatrix shadows(double v) =>
      ColorMatrix.scaleAbout(1 - 0.35 * v.clamp(-1.0, 1.0), 255);

  /// Positive is warmer (towards amber), negative cooler (towards blue).
  static ColorMatrix warmth(double v) {
    final w = v.clamp(-1.0, 1.0);
    return ColorMatrix.channels(1 + 0.16 * w, 1 + 0.03 * w, 1 - 0.16 * w);
  }

  /// Positive is magenta, negative green.
  static ColorMatrix tint(double v) {
    final t = v.clamp(-1.0, 1.0);
    return ColorMatrix.channels(1 + 0.06 * t, 1 - 0.12 * t, 1 + 0.06 * t);
  }

  /// 0–1. Lifts black and lowers white towards a matte print, and takes some
  /// of the colour out with them.
  static ColorMatrix fade(double v) {
    final f = v.clamp(0.0, 1.0);
    final k = 1 - 0.28 * f;
    return ColorMatrix.channels(
      k,
      k,
      k,
      offset: 0.14 * f * 255,
    ).then(saturation(-0.25 * f));
  }
}

/// A one-tap look.
///
/// Each is a recipe of the same controls the Adjust tool has — so a filter
/// followed by a nudge of the sliders is one coherent picture rather than two
/// systems fighting — plus, for the few that need it, a colour transform no
/// slider makes (sepia) and a vignette.
enum PhotoFilter {
  none('Original'),
  vivid('Vivid'),
  warm('Warm'),
  cool('Cool'),
  bright('Bright'),
  dramatic('Dramatic'),
  mono('Mono'),
  noir('Noir'),
  sepia('Sepia'),
  vintage('Vintage'),
  fade('Fade'),
  pop('Pop');

  const PhotoFilter(this.label);

  final String label;

  /// The look's colour transform at full strength.
  ColorMatrix get matrix => switch (this) {
    PhotoFilter.none => ColorMatrix.identity,
    PhotoFilter.vivid => Tone.saturation(0.4).then(Tone.contrast(0.12)),
    PhotoFilter.warm => Tone.warmth(0.6).then(Tone.saturation(0.12)),
    PhotoFilter.cool => Tone.warmth(-0.6).then(Tone.tint(-0.1)),
    PhotoFilter.bright => Tone.exposure(
      0.3,
    ).then(Tone.shadows(0.25)).then(Tone.contrast(-0.05)),
    PhotoFilter.dramatic => Tone.contrast(
      0.35,
    ).then(Tone.saturation(-0.15)).then(Tone.shadows(-0.2)),
    PhotoFilter.mono => Tone.saturation(-1),
    PhotoFilter.noir => Tone.saturation(-1).then(Tone.contrast(0.45)),
    PhotoFilter.sepia =>
      ColorMatrix.sepia.then(Tone.contrast(0.05)).then(Tone.exposure(0.05)),
    PhotoFilter.vintage => Tone.fade(
      0.5,
    ).then(Tone.warmth(0.35)).then(Tone.saturation(-0.15)),
    PhotoFilter.fade => Tone.fade(0.75),
    PhotoFilter.pop => Tone.contrast(
      0.2,
    ).then(Tone.saturation(0.25)).then(Tone.exposure(0.1)),
  };

  /// Edge darkening the look brings, -1–1 like the Vignette slider.
  double get vignette => switch (this) {
    PhotoFilter.dramatic => -0.45,
    PhotoFilter.noir => -0.35,
    PhotoFilter.vintage => -0.3,
    _ => 0,
  };
}
