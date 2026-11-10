import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

/// The outcome of reading a user's SVG file: an outline, or a reason.
///
/// Sealed rather than a nullable success with a separate message, so the caller
/// cannot forget to say why nothing arrived. The failure text is written to be
/// shown to the user as it is, the same contract `ProjectArchiveException`
/// keeps.
sealed class SvgImportResult {
  const SvgImportResult();
}

/// An outline read out of a file and normalised into the unit box.
@immutable
class SvgImportSuccess extends SvgImportResult {
  const SvgImportSuccess({
    required this.pathData,
    required this.evenOdd,
    required this.aspect,
    this.colour = const Color(0xFF000000),
    this.stroke,
  });

  /// The one colour the artwork is drawn in.
  ///
  /// Black is also what a file that names no colour at all is drawn in, and
  /// what `currentColor` resolves to, so a caller may take black to mean "no
  /// colour given".
  final Color colour;

  /// For line art — every path stroked, none filled — the stroke's width as a
  /// fraction of the outline box's shorter side. Null for filled artwork.
  final double? stroke;

  /// The outline as absolute `M`, `L`, `C` and `Z` in the unit box: `(0,0)` is
  /// its top-left corner and `(1,1)` its bottom-right.
  ///
  /// Read back with `parseUnitPath`, which is why the grammar is this narrow —
  /// see `domain/engine/svg_path.dart` for the two-halves argument.
  final String pathData;

  /// True when any drawn subpath asked for the even-odd rule.
  final bool evenOdd;

  /// The ink's own width : height, so the caller can size a box that does not
  /// stretch it. Greater than one for a wide outline.
  final double aspect;
}

/// Artwork an outline cannot carry — several colours, a gradient, text, an
/// embedded picture, or more detail than a shape should hold — which the
/// caller brings in as a picture instead, looking as it was drawn.
@immutable
class SvgImportPicture extends SvgImportResult {
  const SvgImportPicture({required this.aspect});

  /// The artwork's width : height.
  final double aspect;
}

/// Why a file could not be turned into a shape.
@immutable
class SvgImportFailure extends SvgImportResult {
  const SvgImportFailure(this.message);

  /// Already phrased for the user; show it as it is.
  final String message;
}

/// Turns a user's SVG file into a single filled outline.
///
/// This is the **import** half of SVG support, and it runs exactly once per
/// file — off the paint path, off the hit-test path, and off anything that
/// happens while a handle is being dragged. That is what buys it the right to
/// be a whole SVG parser. The half that runs on every build is
/// `domain/engine/svg_path.dart`, which reads only the four commands this
/// emits.
///
/// The parser is `vector_graphics_compiler`, which is not a new dependency in
/// any meaningful sense: `flutter_svg`'s own runtime loader imports it and
/// calls `encodeSvg` on it, and this app renders every device frame through
/// `SvgPicture.asset`, so the full SVG parser and its resolver are already
/// compiled into every build. Declaring it directly adds nothing but the right
/// to `import` it.
///
/// What it gives that a regex over `d=` attributes cannot, and why that
/// matters for files a user actually has:
///
///  * `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`, `<polyline>` and `<line>`
///    are resolved into real path commands. Most icon sets are built out of
///    these; a reader that only scrapes `d` turns such a file into an *empty*
///    shape and reports success.
///  * `transform` on a path and on every ancestor `<g>` is already flattened
///    into the coordinates. Figma and Illustrator both emit
///    `<g transform="translate(…)">` as a matter of course, and an outline read
///    without it lands somewhere else entirely.
///  * Units, `viewBox` scaling, `use` references and inherited paint are all
///    resolved, and each path arrives carrying its own fill rule.
///
/// An outline carries one colour, as a fill or as a stroke, so that is what a
/// shape is made of: artwork in one colour arrives in it, filled or stroked as
/// it was drawn, and is then the Style panel's business like any other shape.
/// Anything more — a logo in two colours, a gradient, text — would lose what
/// it looks like as a silhouette, and is reported as a [SvgImportPicture]
/// instead.
abstract final class SvgImport {
  /// The largest file worth decoding, checked by the caller before the bytes
  /// are turned into a string.
  ///
  /// An SVG is text, and two megabytes of it is a map or a traced photograph
  /// rather than a logo — the sort of file whose outline would blow through
  /// [maxPathDataChars] anyway, several seconds later.
  static const maxSourceBytes = 2 * 1024 * 1024;

  /// The longest outline that may become a shape.
  ///
  /// The string sits in `project.json` and is re-saved on every edit to the
  /// screen it is on, so it is a cost the document carries forever rather than
  /// a cost paid once at import. Refusing here follows the precedent the draw
  /// overlay already sets: a stroke that cannot make a usable shape is refused
  /// rather than added as a bad layer.
  static const maxPathDataChars = 60000;

  /// Coordinates are written to this many decimals.
  ///
  /// The unit box is 1.0 across, so 1e-5 is a hundredth of a pixel even at a
  /// 1179px export — below anything that can be seen, and far enough above
  /// double noise that the string does not carry seventeen digits per number.
  static const _decimals = 5;

  /// A floor on each axis of the outline's box, as a fraction of its longer
  /// axis, so the aspect can never exceed 20:1.
  ///
  /// A perfectly flat outline — a horizontal rule, one straight segment — has
  /// zero extent on one axis, which is a box nothing can be drawn in and a
  /// handle nothing can grab. `_addDrawnShape` meets the same case on a
  /// freehand stroke and answers it the same way. The ink is centred in the box
  /// the floor produces, so nothing shifts for an outline that did not need it.
  static const _minExtentRatio = 0.05;

  /// Reads [svg] and returns its outline, or why it has none.
  ///
  /// Never throws. The parser signals malformed XML, a missing viewport and a
  /// file that is not an SVG at all by throwing [StateError] from inside its
  /// tokeniser, and this is the layer that turns each of those into a sentence.
  static SvgImportResult read(String svg) {
    final vg.VectorInstructions instructions;
    try {
      // `parseWithoutOptimizers` rather than `parse`: the masking, clipping and
      // overdraw optimizers are the only code paths that reach for the native
      // `libpathops`, which is not linked into a Flutter app and would fail at
      // the FFI lookup. Nothing here needs them — they exist to shrink an
      // encoded picture, and the output wanted here is one outline.
      instructions = vg.parseWithoutOptimizers(svg);
    } catch (_) {
      return const SvgImportFailure(
        'That file is not an SVG this app can read.',
      );
    }

    final paint = _Paints.of(instructions);
    if (paint.needsPicture) return _picture(instructions);

    final drawn = _drawnPaths(instructions);
    if (drawn.isEmpty) {
      // Rare, and rare *because* the compiler resolves the primitive elements
      // into paths — this is the case a regex reader hits constantly. What
      // reaches it now is a file whose only content is text, an embedded
      // bitmap, or shapes with neither a fill nor a stroke.
      return const SvgImportFailure('That SVG has no drawable outline.');
    }

    var bounds = drawn.first.bounds();
    for (final path in drawn.skip(1)) {
      bounds = bounds.expanded(path.bounds());
    }

    // NaN propagates through `bounds()`, so a path with a non-finite coordinate
    // arrives here as a non-finite box rather than as a throw.
    if (!bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.right.isFinite ||
        !bounds.bottom.isFinite) {
      return const SvgImportFailure("That SVG's outline has no size.");
    }

    final longest = math.max(bounds.width, bounds.height);
    if (longest <= 0) {
      return const SvgImportFailure("That SVG's outline has no size.");
    }

    final boxWidth = math.max(bounds.width, longest * _minExtentRatio);
    final boxHeight = math.max(bounds.height, longest * _minExtentRatio);
    final left = (bounds.left + bounds.right) / 2 - boxWidth / 2;
    final top = (bounds.top + bounds.bottom) / 2 - boxHeight / 2;

    final buffer = StringBuffer();
    for (final path in drawn) {
      for (final command in path.commands) {
        _write(buffer, command, left, top, boxWidth, boxHeight);
      }
    }

    final pathData = buffer.toString();
    // Too much to keep as an outline: it lives in `project.json` and is
    // rewritten on every edit to its screen. A picture of it costs one file.
    if (pathData.length > maxPathDataChars) return _picture(instructions);

    final strokeWidth = paint.strokeWidth;
    return SvgImportSuccess(
      pathData: pathData,
      // `ui.Path` carries one fill rule for the whole path, so a file that
      // mixes the two rules has to lose the argument one way or the other.
      // Even-odd is the rule that makes a counter and a donut read as holes,
      // and a shape with a hole that should be solid is a smaller mistake than
      // a shape whose hole has filled in.
      evenOdd: drawn.any((p) => p.fillType == vg.PathFillType.evenOdd),
      aspect: boxWidth / boxHeight,
      colour: Color(paint.colour ?? 0xFF000000),
      stroke: strokeWidth == null
          ? null
          : strokeWidth / math.min(boxWidth, boxHeight),
    );
  }

  /// The artwork as a picture, at its own proportions.
  static SvgImportResult _picture(vg.VectorInstructions instructions) {
    final width = instructions.width, height = instructions.height;
    if (!(width > 0) || !(height > 0)) {
      return const SvgImportFailure("That SVG's artwork has no size.");
    }
    return SvgImportPicture(aspect: width / height);
  }

  /// The paths the file actually *draws*, in paint order and without repeats.
  ///
  /// Not `instructions.paths`, which is the pool every command indexes into and
  /// therefore holds clip paths too. That distinction is not academic: a Figma
  /// export routinely wraps its whole artboard in
  /// `<g clip-path="url(#clip0)">` with a full-bleed `<rect>` behind it, and
  /// taking the pool would add that rectangle to the outline *and* normalise
  /// the ink against the artboard instead of against itself — an icon that
  /// arrives as a small mark floating inside a box.
  ///
  /// Deduplicated by path id as well, because the pool is interned: the same
  /// outline drawn twice would otherwise be emitted twice, and two identical
  /// coincident subpaths cancel each other out completely under the even-odd
  /// rule.
  static List<vg.Path> _drawnPaths(vg.VectorInstructions instructions) {
    final seen = <int>{};
    final drawn = <vg.Path>[];
    for (final command in instructions.commands) {
      if (command.type != vg.DrawCommandType.path) continue;
      final id = command.objectId;
      if (id == null || id < 0 || id >= instructions.paths.length) continue;
      if (!seen.add(id)) continue;
      drawn.add(instructions.paths[id]);
    }
    return drawn;
  }

  /// Appends one command, normalised out of the source's coordinates into the
  /// unit box.
  ///
  /// Normalised against the **drawn bounds**, not against
  /// `instructions.width`/`height`. The shape is the ink, not the artboard: an
  /// icon drawn with padding inside a square `viewBox` would otherwise arrive
  /// as a small mark floating in the middle of its own drag handles, and there
  /// would be no way to tell that from artwork that is genuinely that shape.
  ///
  /// The bounds themselves come from `vg.Path.bounds()`, which takes the hull
  /// of a curve's control points rather than the curve's true extent. That errs
  /// in the safe direction — a curved outline lands slightly *inside* the unit
  /// box rather than slightly outside it, which is what
  /// `ShapeGeometry.build`'s contract requires of every kind.
  static void _write(
    StringBuffer buffer,
    vg.PathCommand command,
    double left,
    double top,
    double width,
    double height,
  ) {
    String x(double v) => _round((v - left) / width);
    String y(double v) => _round((v - top) / height);

    switch (command) {
      case vg.MoveToCommand():
        buffer.write('M${x(command.x)} ${y(command.y)}');
      case vg.LineToCommand():
        buffer.write('L${x(command.x)} ${y(command.y)}');
      case vg.CubicToCommand():
        buffer.write(
          'C${x(command.x1)} ${y(command.y1)} '
          '${x(command.x2)} ${y(command.y2)} '
          '${x(command.x3)} ${y(command.y3)}',
        );
      case vg.CloseCommand():
        buffer.write('Z');
      default:
        // The four above are the whole of `PathCommandType`, and the compiler
        // has already reduced arcs and quadratics into them. A fifth verb from
        // a future version of the package is skipped rather than written out
        // in a grammar the reader does not have.
        break;
    }
  }

  /// One coordinate, at [_decimals] and without the trailing zeros that would
  /// otherwise be most of the string.
  static String _round(double value) {
    final fixed = value.toStringAsFixed(_decimals);
    var end = fixed.length;
    while (end > 0 && fixed[end - 1] == '0') {
      end--;
    }
    if (end > 0 && fixed[end - 1] == '.') end--;
    final trimmed = fixed.substring(0, end);
    // A coordinate a rounding hair below zero prints as `-0`, which is a valid
    // number and an ugly one.
    return trimmed == '-0' || trimmed.isEmpty ? '0' : trimmed;
  }
}

/// What the drawn paths are painted with, and whether one outline can say it.
class _Paints {
  _Paints._({
    required this.needsPicture,
    required this.colour,
    required this.strokeWidth,
  });

  /// Whether the artwork needs more than one outline in one colour.
  final bool needsPicture;

  /// The one colour, as ARGB; null when there is none.
  final int? colour;

  /// The stroke of line art, in the file's own units; null for filled art.
  final double? strokeWidth;

  static _Paints of(vg.VectorInstructions instructions) {
    final colours = <int>{};
    final widths = <double>[];
    var fills = 0, strokes = 0;
    var picture = false;
    for (final command in instructions.commands) {
      switch (command.type) {
        case vg.DrawCommandType.path:
          if (command.patternId != null) picture = true;
          final id = command.paintId;
          if (id == null || id < 0 || id >= instructions.paints.length) {
            continue;
          }
          final paint = instructions.paints[id];
          if (paint.fill case final fill?) {
            fills++;
            if (fill.shader != null) picture = true;
            colours.add(fill.color.value);
          }
          if (paint.stroke case final stroke?) {
            strokes++;
            if (stroke.shader != null) picture = true;
            colours.add(stroke.color.value);
            widths.add(stroke.width ?? 1);
          }
        // Type, embedded bitmaps, patterns and meshes: none of them is an
        // outline, and all of them are part of how the artwork looks.
        case vg.DrawCommandType.text ||
            vg.DrawCommandType.textPosition ||
            vg.DrawCommandType.image ||
            vg.DrawCommandType.pattern ||
            vg.DrawCommandType.vertices:
          picture = true;
        case vg.DrawCommandType.saveLayer ||
            vg.DrawCommandType.restore ||
            vg.DrawCommandType.clip ||
            vg.DrawCommandType.mask:
          break;
      }
    }
    // One colour, and one way of painting it: an outline filled or stroked
    // throughout. A filled disc inside a stroked ring is two paints however
    // alike their colour, and filling the ring would close it up.
    if (colours.length > 1 || (fills > 0 && strokes > 0)) picture = true;
    widths.sort();
    return _Paints._(
      needsPicture: picture,
      colour: colours.isEmpty ? null : colours.first,
      strokeWidth: strokes > 0 && widths.isNotEmpty
          ? widths[widths.length ~/ 2]
          : null,
    );
  }
}
