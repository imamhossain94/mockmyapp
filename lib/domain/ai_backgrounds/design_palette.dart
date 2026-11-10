/// The colours a design is already made of, which the AI tools — art
/// direction and icon concepts — keep to, and the `#RRGGBB` form a prompt
/// writes them in.
library;

import 'dart:ui';

import '../models/screen_doc.dart';

/// The most of the person's own words a brief carries into a prompt: a mood
/// is at most 200 characters and an app name at most 60, so a long paste
/// cannot crowd the instructions out of a small model's context.
const kMaxMoodChars = 200;
const kMaxAppNameChars = 60;

/// `#RRGGBB` for [color], as a prompt and a colour field write it.
String hexOf(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The colours the design on [doc] is already made of — its background and
/// the shapes behind its devices — so a suggested background keeps to the
/// same palette.
///
/// Not the caption's colour: the headline is usually white or near black,
/// and asking for a background in the headline's own colour is asking for
/// text nobody can read. At most [max] distinct colours, background first,
/// alpha ignored; empty when the design has none (a photo backdrop, say).
List<Color> paletteOf(ScreenDoc doc, {int max = 5}) {
  final seen = <int>{};
  final out = <Color>[];
  void add(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    if (out.length >= max || color.a < 0.05 || !seen.add(rgb)) return;
    out.add(Color(0xFF000000 | rgb));
  }

  switch (doc.background) {
    case SolidBackground(:final color):
      add(color);
    case final GradientBackground gradient:
      gradient.colors.forEach(add);
    case PatternBackground(:final colors):
      colors.forEach(add);
    case ImageBackground():
      break;
  }
  for (final shape in doc.shapes) {
    if (shape.hidden || shape.z > kStackBehindFrames) continue;
    if (shape.isText || shape.hasImage) continue;
    add(shape.fill);
    if (shape.fillEnd case final end?) add(end);
  }
  return out;
}
