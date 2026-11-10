import 'dart:math' as math;

import '../models/screen_doc.dart';

/// Which part of a background spread across a set one screen shows.
class BackgroundSlice {
  const BackgroundSlice({required this.index, required this.count});

  /// This screen's position in the set.
  final int index;

  /// How many screens the background spans.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is BackgroundSlice && other.index == index && other.count == count;

  @override
  int get hashCode => Object.hash(index, count);
}

/// One screen as it is seen in its set.
///
/// In an ordinary set that is just the screen. In a *continuous* one the
/// screens are panels of one wide artwork, cut at the screen edges the way the
/// store shows them side by side: a phone dragged half off screen 2 appears,
/// cut, on screen 3, and one background runs across the lot.
///
/// Each screen still owns its layers — a device belongs to the screen it was
/// put on, and moving it across the join does not hand it to a neighbour. What
/// changes is only what is *drawn*: [doc] carries the neighbours' layers that
/// reach into this screen as guests, appended after the screen's own so every
/// index the editor holds still points at the same layer.
class ComposedScreen {
  const ComposedScreen({
    required this.doc,
    required this.ownShapes,
    required this.ownFrames,
    this.backgroundSlice,
  });

  /// A screen composed on its own, with nothing borrowed.
  ComposedScreen.alone(ScreenDoc screen)
    : doc = screen,
      ownShapes = screen.shapes.length,
      ownFrames = screen.frames.length,
      backgroundSlice = null;

  /// The screen with any guest layers appended, and the shared background.
  final ScreenDoc doc;

  /// How many of [doc]'s shapes are the screen's own: `shapes[0, ownShapes)`.
  /// The rest are guests, drawn but not editable here.
  final int ownShapes;

  /// The same for devices.
  final int ownFrames;

  /// The part of the shared background this screen shows, or null to paint
  /// the background whole.
  final BackgroundSlice? backgroundSlice;
}

/// Screen [index] of [screens], composed for display and export.
///
/// Not [continuous], it is the screen alone. Continuous, it gains every
/// neighbour's layer that crosses into it — shifted by whole canvas widths,
/// since the screens sit edge to edge — and the first screen's background,
/// sliced to its place in the set.
ComposedScreen composeScreen(
  List<ScreenDoc> screens,
  int index, {
  required bool continuous,
}) {
  final screen = screens[index];
  if (!continuous || screens.length < 2) return ComposedScreen.alone(screen);

  final guestShapes = <ShapeSpec>[];
  final guestFrames = <FramePlacement>[];

  for (var j = 0; j < screens.length; j++) {
    if (j == index) continue;
    // How far that screen sits from this one, in canvas widths. Shapes are
    // measured from the canvas centre in canvas widths, and a device's offset
    // in fractions of the canvas width, so one number moves both across.
    final shift = (j - index).toDouble();
    final other = screens[j];

    for (final shape in other.shapes) {
      if (shape.hidden) continue;
      final centre = shape.center.dx + shift;
      // Half the diagonal, so a rotated shape's corners are not missed.
      final reach =
          math.sqrt(shape.width * shape.width + shape.height * shape.height) /
          2;
      if (centre.abs() - reach < 0.5) {
        guestShapes.add(
          shape.copyWith(center: shape.center.translate(shift, 0)),
        );
      }
    }

    for (final frame in other.frames) {
      if (frame.hidden) continue;
      final centre = frame.transform.offsetPct.dx + shift;
      // A device is at most about a canvas wide; one whose centre is within a
      // canvas width of this screen's centre may reach into it. The canvas
      // clips whatever does not.
      if (centre.abs() < 1.0) {
        guestFrames.add(
          frame.copyWith(
            transform: frame.transform.copyWith(
              offsetPct: frame.transform.offsetPct.translate(shift, 0),
            ),
          ),
        );
      }
    }
  }

  // One background for the whole set: the first screen's.
  //
  // A panorama — a pattern or a picture that lays itself out across screens —
  // is laid out across exactly this set, this screen's slice in view (see
  // [panoramaAt]). It used to keep each screen's own stored slice, and every
  // screen of a continuous set stores the same background, so every screen
  // showed the same slice: one eighth of the artwork, eight times over. It
  // paints its own slice, so it must not be slid as well. Anything else is
  // painted a set wide and slid, the same picture through each window.
  final shared = screens.first.background;
  final panorama = isPanorama(shared);

  return ComposedScreen(
    doc: screen.copyWith(
      background: panorama
          ? panoramaAt(shared, index: index, count: screens.length)
          : shared,
      shapes: [...screen.shapes, ...guestShapes],
      frames: [...screen.frames, ...guestFrames],
    ),
    ownShapes: screen.shapes.length,
    ownFrames: screen.frames.length,
    backgroundSlice: panorama
        ? null
        : BackgroundSlice(index: index, count: screens.length),
  );
}
