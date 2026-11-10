import 'dart:ui';

import 'package:path_parsing/path_parsing.dart';

/// Reads a normalised outline string back into a path in the unit box.
///
/// This is the half of SVG import that runs on the **paint** path, and it is
/// deliberately much smaller than the half that runs on the import path. It
/// only ever sees strings this app itself emitted — absolute `M`, `L`, `C` and
/// `Z`, written by `SvgImport.read` — so it needs four commands and no XML at
/// all, and `path_parsing` supplies exactly those four through its [PathProxy].
/// The document parser that turns a user's file into one of these strings is
/// `data/services/svg_import.dart`; it may be as heavy as it likes, because it
/// runs once. This runs on every build and every pointer hit-test.
///
/// **Total by contract.** A string it cannot read returns null and the shape
/// paints as nothing, because the alternative is an exception thrown inside
/// `build` on a widget that also paints the export raster — the same failure
/// mode `StudioFonts.style` exists to close for typefaces. `path_parsing`
/// signals every malformed input by throwing [StateError] from deep inside its
/// tokeniser, so that is the throw this catches; the bare `catch` after it is
/// there because a promise of totality is worth more than the one branch it
/// costs.
///
/// The path comes back in the unit box — `(0,0)` to `(1,1)` — and is scaled
/// into the shape's real box by `ShapeGeometry`, which is also where the result
/// is cached.
Path? parseUnitPath(String d, {bool evenOdd = false}) {
  // What `ShapeSpec.pathData` carries when nothing has been imported. Worth its
  // own branch rather than falling through the parser, which accepts an empty
  // string happily and hands back an empty path.
  if (d.trim().isEmpty) return null;

  final proxy = _UiPathProxy();
  try {
    writeSvgPathDataToPath(d, proxy);
  } on StateError {
    return null;
  } catch (_) {
    return null;
  }

  // A string that parsed but drew nothing — a lone `M`, a `M`/`Z` pair, or a
  // run of commands the normaliser dropped. Null rather than an empty path, so
  // the caller cannot tell those apart from an unreadable string and does not
  // have to.
  if (proxy.ink == 0) return null;

  // `ui.Path` carries one fill rule for the whole path, which is why this is a
  // parameter rather than something the string could say per subpath. See
  // `ShapeSpec.evenOdd` for what that costs.
  return proxy.path
    ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
}

/// Forwards the four normalised verbs onto a real [Path].
///
/// [SvgPathNormalizer] has already turned every command form the SVG grammar
/// allows — relative coordinates, `H`/`V`, the smooth `S`/`T` shorthands, and
/// elliptical `A` arcs — into these four, so there is nothing left for this to
/// decide.
class _UiPathProxy implements PathProxy {
  final Path path = Path();

  /// How many segments actually laid down ink.
  ///
  /// Only lines and curves count. A `moveTo` puts the pen down and a `close`
  /// joins a contour that may be a single point, so neither on its own is a
  /// shape — and `Path` itself cannot answer "is there anything here" cheaply.
  int ink = 0;

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) {
    ink++;
    path.lineTo(x, y);
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    ink++;
    path.cubicTo(x1, y1, x2, y2, x3, y3);
  }

  @override
  void close() => path.close();
}
