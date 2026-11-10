import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/shape_spec.dart';
import 'svg_path.dart';

/// Builds and paints the vector shapes a [ShapeSpec] describes.
///
/// Everything here works in the shape's own box — `Rect.fromLTWH(0, 0, w, h)` —
/// so the same code draws a 40px picker thumbnail and a 700px export at the same
/// proportions. Placement, rotation and opacity belong to the layer around it.
abstract final class ShapeGeometry {
  /// Polygons and stars below three corners have no area; above two dozen they
  /// are a circle with extra maths.
  static const int minSides = 3;
  static const int maxSides = 24;

  /// The path for [spec], laid out to fill [size].
  static Path build(ShapeSpec spec, Size size) {
    final rect = Offset.zero & size;
    return switch (spec.kind) {
      ShapeKind.rectangle => _rectangle(spec, rect),
      ShapeKind.ellipse => Path()..addOval(rect),
      ShapeKind.triangle => _polygon(rect, 3, spec.cornerRadius),
      ShapeKind.polygon => _polygon(rect, spec.sides, spec.cornerRadius),
      ShapeKind.star => _star(
        rect,
        spec.sides,
        spec.innerRatio,
        spec.cornerRadius,
      ),
      ShapeKind.burst => _star(
        rect,
        spec.sides,
        spec.innerRatio,
        spec.cornerRadius,
      ),
      ShapeKind.line => _line(rect),
      ShapeKind.arrow => _arrow(rect),
      ShapeKind.wave => _wave(rect, spec.sides),
      ShapeKind.heart => _heart(rect),
      ShapeKind.blob => _blob(rect),
      ShapeKind.bubble => _bubble(rect, spec.cornerRadius),
      ShapeKind.cross => _cross(rect),
      ShapeKind.chevron => _chevron(rect),
      ShapeKind.drop => _drop(rect),
      ShapeKind.shield => _shield(rect),
      ShapeKind.custom => _custom(spec, rect),
      ShapeKind.path => _importedPath(spec, rect),
    };
  }

  // --- primitives ----------------------------------------------------------

  static Path _rectangle(ShapeSpec spec, Rect rect) {
    // Against the shorter side, so a wide rectangle at full rounding is a
    // stadium rather than an ellipse.
    final radius = spec.cornerRadius.clamp(0.0, 1.0) * rect.shortestSide / 2;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }

  static Path _line(Rect rect) => Path()
    ..moveTo(rect.left, rect.center.dy)
    ..lineTo(rect.right, rect.center.dy);

  /// A shaft with an open V head, drawn as one stroked path.
  ///
  /// The head is sized off the box's shorter side rather than off the stroke
  /// width: an arrow that grew its own head as it was made thicker would stop
  /// being the arrow the user placed.
  static Path _arrow(Rect rect) {
    final y = rect.center.dy;
    final head = math.min(rect.width * 0.32, rect.height * 0.9);
    return Path()
      ..moveTo(rect.left, y)
      ..lineTo(rect.right, y)
      ..moveTo(rect.right - head, y - head / 2)
      ..lineTo(rect.right, y)
      ..lineTo(rect.right - head, y + head / 2);
  }

  /// A sine running the width of the box, [crests] full periods across it.
  ///
  /// Sampled and smoothed rather than built from arcs: a sine is not made of
  /// circular segments, and approximating it with them shows as flat spots at
  /// the crests once the shape is exported at a couple of thousand pixels.
  static Path _wave(Rect rect, int crests) {
    final periods = crests.clamp(minWaves, maxWaves);
    final amplitude = rect.height / 2;
    final samples = (periods * 24).clamp(24, 512);
    final points = [
      for (var i = 0; i <= samples; i++)
        () {
          final t = i / samples;
          return Offset(
            rect.left + rect.width * t,
            rect.center.dy + amplitude * math.sin(2 * math.pi * periods * t),
          );
        }(),
    ];
    return _smoothOpen(points);
  }

  /// A wave needs at least one crest; past a dozen it is hatching.
  static const int minWaves = 1;
  static const int maxWaves = 12;

  // --- regular figures -----------------------------------------------------

  /// Corner angles of a regular figure with [sides] corners, inscribed in
  /// [rect] and starting at twelve o'clock.
  ///
  /// Inscribed in the box's *ellipse*, not in a circle, so a polygon stretched
  /// into a wide box fills it instead of sitting in a circle in the middle.
  static List<Offset> _corners(Rect rect, int sides, double radiusScale) {
    final n = sides.clamp(minSides, maxSides);
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2 * radiusScale;
    final ry = rect.height / 2 * radiusScale;
    return [
      for (var i = 0; i < n; i++)
        () {
          final a = -math.pi / 2 + i * 2 * math.pi / n;
          return Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
        }(),
    ];
  }

  static Path _polygon(Rect rect, int sides, double cornerRadius) =>
      _throughCorners(_corners(rect, sides, 1), rect, cornerRadius);

  static Path _star(
    Rect rect,
    int points,
    double innerRatio,
    double cornerRadius,
  ) {
    final n = points.clamp(minSides, maxSides);
    final inner = innerRatio.clamp(0.05, 0.95);
    final outer = _corners(rect, n, 1);
    // Rotated half a step so a valley falls between every pair of points.
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2 * inner;
    final ry = rect.height / 2 * inner;
    final valleys = [
      for (var i = 0; i < n; i++)
        () {
          final a = -math.pi / 2 + (i + 0.5) * 2 * math.pi / n;
          return Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
        }(),
    ];
    return _throughCorners(
      [
        for (var i = 0; i < n; i++) ...[outer[i], valleys[i]],
      ],
      rect,
      cornerRadius,
    );
  }

  /// A closed path through [corners], rounding each one by [cornerRadius].
  ///
  /// The rounding backs off along both edges meeting at a corner and joins them
  /// with a quadratic through the corner itself, capped at half the shorter of
  /// the two edges so adjacent roundings can never overrun each other — which is
  /// what turns a star's sharp points into petals without collapsing its
  /// valleys.
  static Path _throughCorners(
    List<Offset> corners,
    Rect rect,
    double cornerRadius,
  ) {
    final path = Path();
    if (corners.length < 3) return path;

    final amount = cornerRadius.clamp(0.0, 1.0);
    if (amount <= 0) {
      path.addPolygon(corners, true);
      return path;
    }

    final maxRadius = rect.shortestSide / 2 * amount;
    for (var i = 0; i < corners.length; i++) {
      final prev = corners[(i - 1 + corners.length) % corners.length];
      final current = corners[i];
      final next = corners[(i + 1) % corners.length];

      final toPrev = prev - current;
      final toNext = next - current;
      final back = math.min(
        maxRadius,
        math.min(toPrev.distance, toNext.distance) / 2,
      );
      if (back <= 0.01) {
        if (i == 0) {
          path.moveTo(current.dx, current.dy);
        } else {
          path.lineTo(current.dx, current.dy);
        }
        continue;
      }

      final start = current + (toPrev / toPrev.distance) * back;
      final end = current + (toNext / toNext.distance) * back;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
    }
    return path..close();
  }

  // --- motifs --------------------------------------------------------------

  /// Fractions of the box, so every motif below is one table of proportions
  /// read at whatever size it is drawn.
  static Offset _at(Rect r, double x, double y) =>
      Offset(r.left + r.width * x, r.top + r.height * y);

  static Path _heart(Rect r) {
    final path = Path()..moveTo(_at(r, 0.5, 1).dx, _at(r, 0.5, 1).dy);
    // Up the left flank, over the left lobe, into the cleft.
    path.cubicTo(
      _at(r, 0.06, 0.62).dx,
      _at(r, 0.06, 0.62).dy, //
      _at(r, 0, 0.36).dx,
      _at(r, 0, 0.36).dy,
      _at(r, 0.14, 0.16).dx,
      _at(r, 0.14, 0.16).dy,
    );
    path.cubicTo(
      _at(r, 0.3, 0).dx,
      _at(r, 0.3, 0).dy, //
      _at(r, 0.46, 0.06).dx,
      _at(r, 0.46, 0.06).dy,
      _at(r, 0.5, 0.2).dx,
      _at(r, 0.5, 0.2).dy,
    );
    // And back down the mirror image.
    path.cubicTo(
      _at(r, 0.54, 0.06).dx,
      _at(r, 0.54, 0.06).dy, //
      _at(r, 0.7, 0).dx,
      _at(r, 0.7, 0).dy,
      _at(r, 0.86, 0.16).dx,
      _at(r, 0.86, 0.16).dy,
    );
    path.cubicTo(
      _at(r, 1, 0.36).dx,
      _at(r, 1, 0.36).dy, //
      _at(r, 0.94, 0.62).dx,
      _at(r, 0.94, 0.62).dy,
      _at(r, 0.5, 1).dx,
      _at(r, 0.5, 1).dy,
    );
    return path..close();
  }

  /// An organic closed curve: eight radii around the centre, joined by
  /// quadratics through their midpoints so the result has no visible joints.
  ///
  /// The radii are a fixed table rather than a seeded random walk. A blob that
  /// re-rolled its own outline between the editor and the export would not be
  /// the shape the user placed.
  static Path _blob(Rect r) {
    const radii = [1.0, 0.86, 0.97, 0.8, 1.0, 0.88, 0.93, 0.82];
    final ring = [
      for (var i = 0; i < radii.length; i++)
        () {
          final a = i * 2 * math.pi / radii.length;
          return Offset(
            r.center.dx + r.width / 2 * radii[i] * math.cos(a),
            r.center.dy + r.height / 2 * radii[i] * math.sin(a),
          );
        }(),
    ];
    return _smoothClosed(ring);
  }

  /// A rounded speech bubble with a tail off the bottom-left.
  static Path _bubble(Rect r, double cornerRadius) {
    final body = Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * 0.78);
    final radius =
        (cornerRadius <= 0 ? 0.35 : cornerRadius).clamp(0.0, 1.0) *
        body.shortestSide /
        2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    return path
      ..moveTo(_at(r, 0.26, 0.76).dx, _at(r, 0.26, 0.76).dy)
      ..lineTo(_at(r, 0.22, 1).dx, _at(r, 0.22, 1).dy)
      ..lineTo(_at(r, 0.46, 0.76).dx, _at(r, 0.46, 0.76).dy)
      ..close();
  }

  /// A plus sign: arms a third of the box wide.
  static Path _cross(Rect r) {
    const t = 1 / 3;
    return Path()..addPolygon([
      _at(r, t, 0), _at(r, 1 - t, 0), //
      _at(r, 1 - t, t), _at(r, 1, t),
      _at(r, 1, 1 - t), _at(r, 1 - t, 1 - t),
      _at(r, 1 - t, 1), _at(r, t, 1),
      _at(r, t, 1 - t), _at(r, 0, 1 - t),
      _at(r, 0, t), _at(r, t, t),
    ], true);
  }

  /// A thick right-pointing chevron.
  static Path _chevron(Rect r) => Path()
    ..addPolygon([
      _at(r, 0, 0), _at(r, 0.45, 0), //
      _at(r, 1, 0.5), _at(r, 0.45, 1),
      _at(r, 0, 1), _at(r, 0.55, 0.5),
    ], true);

  /// A teardrop: a point at the top over a circular belly.
  static Path _drop(Rect r) {
    final path = Path()..moveTo(_at(r, 0.5, 0).dx, _at(r, 0.5, 0).dy);
    path.cubicTo(
      _at(r, 0.92, 0.42).dx,
      _at(r, 0.92, 0.42).dy, //
      _at(r, 1, 0.62).dx,
      _at(r, 1, 0.62).dy,
      _at(r, 1, 0.68).dx,
      _at(r, 1, 0.68).dy,
    );
    path.arcToPoint(
      _at(r, 0, 0.68),
      radius: Radius.elliptical(r.width / 2, r.height * 0.32),
      clockwise: true,
    );
    path.cubicTo(
      _at(r, 0, 0.62).dx,
      _at(r, 0, 0.62).dy, //
      _at(r, 0.08, 0.42).dx,
      _at(r, 0.08, 0.42).dy,
      _at(r, 0.5, 0).dx,
      _at(r, 0.5, 0).dy,
    );
    return path..close();
  }

  /// A crest: square shoulders tapering to a point.
  static Path _shield(Rect r) {
    final path = Path()..moveTo(_at(r, 0.5, 0).dx, _at(r, 0.5, 0).dy);
    path.lineTo(_at(r, 1, 0.16).dx, _at(r, 1, 0.16).dy);
    path.lineTo(_at(r, 1, 0.52).dx, _at(r, 1, 0.52).dy);
    path.cubicTo(
      _at(r, 1, 0.78).dx,
      _at(r, 1, 0.78).dy, //
      _at(r, 0.78, 0.94).dx,
      _at(r, 0.78, 0.94).dy,
      _at(r, 0.5, 1).dx,
      _at(r, 0.5, 1).dy,
    );
    path.cubicTo(
      _at(r, 0.22, 0.94).dx,
      _at(r, 0.22, 0.94).dy, //
      _at(r, 0, 0.78).dx,
      _at(r, 0, 0.78).dy,
      _at(r, 0, 0.52).dx,
      _at(r, 0, 0.52).dy,
    );
    path.lineTo(_at(r, 0, 0.16).dx, _at(r, 0, 0.16).dy);
    return path..close();
  }

  // --- drawn paths ---------------------------------------------------------

  /// The user's own path, scaled out of its normalised box into [rect].
  ///
  /// Smoothed the same way [_blob] is: a freehand drag arrives as a dense run of
  /// samples, and joining them with straight segments makes a hand-drawn curve
  /// look faceted at export resolution.
  static Path _custom(ShapeSpec spec, Rect rect) {
    final scaled = [
      for (final p in spec.points)
        Offset(rect.left + p.dx * rect.width, rect.top + p.dy * rect.height),
    ];
    if (scaled.length < 2) return Path();
    return spec.closed ? _smoothClosed(scaled) : _smoothOpen(scaled);
  }

  /// The imported outline, scaled out of its unit box into [rect].
  ///
  /// The outline is a string rather than a built path because that is what
  /// survives a save; see [ShapeSpec.pathData]. Rebuilding it is the only work
  /// this kind costs, and [_unitPath] is what keeps that from being paid
  /// dozens of times a second.
  ///
  /// An unreadable string paints nothing rather than throwing. A shape that has
  /// gone blank is a thing the user can see and delete; an exception raised
  /// inside `build` on the widget that also paints the export raster is not.
  static Path _importedPath(ShapeSpec spec, Rect rect) {
    final unit = _unitPath(spec.pathData, spec.evenOdd);
    if (unit == null) return Path();
    // A column-major 4x4 built by hand rather than through `Matrix4`, which
    // would pull `vector_math` into a file that otherwise needs nothing from
    // it. Indices 0 and 5 are the axis scales; 12 and 13 are the translation.
    final matrix = Float64List(16)
      ..[0] = rect.width
      ..[5] = rect.height
      ..[10] = 1
      ..[12] = rect.left
      ..[13] = rect.top
      ..[15] = 1;
    return unit.transform(matrix);
  }

  /// The parsed outline for [data], kept between builds.
  ///
  /// Cached because both of this file's entry points are hot in ways that are
  /// easy to miss. `ShapePainter.shouldRepaint` is identity-based — specs are
  /// replaced wholesale on every edit — so it returns true on every tick of a
  /// slider drag; and `hitTest` builds a second path on every pointer test. A
  /// logo with a few thousand commands would otherwise be re-parsed dozens of
  /// times a second while a handle is moving.
  ///
  /// The *unit* path is what is cached, not the scaled one: the transform is a
  /// matrix multiply and the box changes on every resize, so caching the
  /// scaled path would miss on exactly the frames that matter.
  ///
  /// A null result — an unreadable string — is cached too. Re-parsing a string
  /// that has already failed once costs the same as parsing one that works.
  static Path? _unitPath(String data, bool evenOdd) {
    // Both halves of the key, because the fill rule is baked into the path and
    // the same outline can legitimately be held under either rule.
    final key = evenOdd ? 'e:$data' : 'n:$data';
    if (_unitPaths.containsKey(key)) return _unitPaths[key];

    // Bounded, and evicted oldest-first: Dart maps iterate in insertion order,
    // so the first key is the least recently *added*. Not an LRU — a strict LRU
    // would have to re-insert on every hit, which is a write on the paint path
    // to solve a problem a canvas with 64 distinct outlines on it does not
    // have.
    if (_unitPaths.length >= _unitPathCacheLimit) {
      _unitPaths.remove(_unitPaths.keys.first);
    }

    final path = parseUnitPath(data, evenOdd: evenOdd);
    _unitPaths[key] = path;
    return path;
  }

  static final Map<String, Path?> _unitPaths = {};

  /// Far more distinct outlines than a screen can hold, and small enough that
  /// the whole cache is a rounding error next to one exported frame.
  static const _unitPathCacheLimit = 64;

  /// Empties the outline cache.
  ///
  /// Tests only. Nothing in the app invalidates this — a path string is its own
  /// identity, so an entry can never go stale.
  @visibleForTesting
  static void debugClearPathCache() => _unitPaths.clear();

  /// An open path through [points], each vertex smoothed by running quadratics
  /// between the midpoints of consecutive segments.
  static Path _smoothOpen(List<Offset> points) {
    if (points.length < 2) return Path();
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    return path..lineTo(points.last.dx, points.last.dy);
  }

  /// [source] broken into dashes: [on] units drawn, [off] units skipped.
  ///
  /// Works off `computeMetrics`, so it dashes any path — a rectangle's outline
  /// and a hand-drawn squiggle alike — rather than only straight lines. Returns
  /// [source] unchanged if either length is degenerate, which is the guard that
  /// keeps a zero-width stroke from spinning here forever.
  static Path dash(Path source, {required double on, required double off}) {
    if (on <= 0 || off <= 0 || !on.isFinite || !off.isFinite) return source;

    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var drawing = true;
      // A path can be arbitrarily long relative to a small pattern; the cap is
      // a backstop against a pathological spec producing millions of segments.
      var segments = 0;
      while (distance < metric.length && segments < 4000) {
        final length = drawing ? on : off;
        if (drawing) {
          result.addPath(
            metric.extractPath(
              distance,
              math.min(distance + length, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += length;
        drawing = !drawing;
        segments++;
      }
    }
    return result;
  }

  /// A closed path through [ring], every vertex smoothed by running quadratics
  /// between the midpoints of consecutive segments.
  static Path _smoothClosed(List<Offset> ring) {
    final path = Path();
    if (ring.length < 3) {
      if (ring.length == 2) {
        path
          ..moveTo(ring.first.dx, ring.first.dy)
          ..lineTo(ring.last.dx, ring.last.dy);
      }
      return path;
    }
    final start = (ring.last + ring.first) / 2;
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < ring.length; i++) {
      final control = ring[i];
      final end = (ring[i] + ring[(i + 1) % ring.length]) / 2;
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    return path..close();
  }
}

/// Paints one [ShapeSpec] into the box it is given.
///
/// [canvasWidth] is the document's own width, because every width-ish number on
/// the spec — the stroke, the shadow's blur and offset — is a fraction of the
/// canvas rather than of the shape. Passing the shape's width instead would make
/// a stroke thicken as the shape grew.
/// Which part of a shape a [ShapePainter] draws.
///
/// All of it, ordinarily. A shape filled with a picture is drawn in two
/// passes around the picture: its shadow under it, its outline over it — an
/// outline painted first would be half covered by the photo it frames.
enum ShapePaintPass {
  /// Shadow, fill and outline.
  all,

  /// Shadow only, for under a picture fill.
  under,

  /// Outline only, for over a picture fill.
  over,
}

class ShapePainter extends CustomPainter {
  const ShapePainter({
    required this.spec,
    required this.canvasWidth,
    required this.boxSize,
    this.pass = ShapePaintPass.all,
  });

  final ShapeSpec spec;
  final double canvasWidth;

  /// See [ShapePaintPass].
  final ShapePaintPass pass;

  /// The box this painter is laid out in.
  ///
  /// Carried explicitly because [hitTest] is not told the size it was painted
  /// into, and picking has to build the same path the paint did.
  final Size boxSize;

  /// The stroke's path with its dash pattern applied.
  ///
  /// The pattern is measured in stroke widths, so a thicker line gets longer
  /// dashes without anything else being touched. A dot is a near-zero-length
  /// dash under a round cap, which renders as a circle one stroke wide — the
  /// standard trick, and the reason the cap below is never square.
  static Path _styled(Path path, ShapeSpec spec, double strokeWidth) {
    if (spec.strokeStyle == StrokeStyle.solid || strokeWidth <= 0) return path;
    final scale = spec.dashScale.clamp(0.25, 4.0);
    return switch (spec.strokeStyle) {
      StrokeStyle.dashed => ShapeGeometry.dash(
        path,
        on: strokeWidth * 2.6 * scale,
        off: strokeWidth * 2.0 * scale,
      ),
      StrokeStyle.dotted => ShapeGeometry.dash(
        path,
        on: strokeWidth * 0.02,
        off: strokeWidth * 1.9 * scale,
      ),
      StrokeStyle.solid => path,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = ShapeGeometry.build(spec, size);
    final strokeWidth = spec.strokePixels(canvasWidth, size);
    final strokePath = _styled(path, spec, strokeWidth);

    final shadow = spec.shadow;
    if (pass != ShapePaintPass.over && shadow != null && shadow.opacity > 0) {
      final sigma = shadow.blur * canvasWidth;
      final shadowPaint = Paint()
        ..color = shadow.color.withValues(alpha: shadow.opacity)
        ..maskFilter = sigma > 0.01
            ? MaskFilter.blur(BlurStyle.normal, sigma)
            : null;
      // An open shape has no interior to cast from, so its shadow follows the
      // stroke — otherwise a line would drop the shadow of the triangle its
      // two ends and the canvas origin happen to enclose.
      if (spec.isOpen) {
        shadowPaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      }
      canvas.save();
      canvas.translate(
        shadow.offset.dx * canvasWidth,
        shadow.offset.dy * canvasWidth,
      );
      // The dashed path, so a dashed line's shadow is dashed too rather than
      // a solid bar under a broken rule.
      canvas.drawPath(spec.isOpen ? strokePath : path, shadowPaint);
      canvas.restore();
    }

    if (pass == ShapePaintPass.all && !spec.isOpen) {
      final fill = Paint()..style = PaintingStyle.fill;
      final end = spec.fillEnd;
      if (end == null) {
        fill.color = spec.fill;
      } else if (spec.gradientRadial) {
        // From the centre out to the far edge of the box. `RadialGradient`
        // measures its radius against the *shortest* side, so a wide ellipse
        // needs the ratio folded in or its long ends sit in flat rim colour.
        final short = math.min(size.width, size.height);
        final long = math.max(size.width, size.height);
        fill.shader = RadialGradient(
          radius: short > 0 ? 0.5 * long / short : 0.5,
          colors: [spec.fill, end],
        ).createShader(Offset.zero & size);
      } else {
        final radians = spec.gradientAngle * math.pi / 180;
        final direction = Offset(math.sin(radians), -math.cos(radians));
        fill.shader = LinearGradient(
          begin: Alignment(-direction.dx, -direction.dy),
          end: Alignment(direction.dx, direction.dy),
          colors: [spec.fill, end],
        ).createShader(Offset.zero & size);
      }
      canvas.drawPath(path, fill);
    }

    if (pass != ShapePaintPass.under &&
        strokeWidth > 0 &&
        (spec.isOpen || spec.strokeWidth > 0)) {
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = spec.strokeColor,
      );
    }
  }

  /// Precise picking: a tap inside the shape's box but outside the shape itself
  /// falls through to whatever is behind it, so a circle overlapping a rectangle
  /// selects the one actually under the finger.
  ///
  /// Open shapes have no interior to test, so they keep the box — `Path` cannot
  /// be widened into a hit region without re-implementing stroking, and a line's
  /// box is already only as tall as the gesture that drew it.
  @override
  bool hitTest(Offset position) {
    if (spec.isOpen || boxSize.isEmpty) return true;
    return ShapeGeometry.build(spec, boxSize).contains(position);
  }

  /// Specs are rebuilt wholesale on every edit rather than mutated, so identity
  /// is the honest test — two different instances may or may not describe the
  /// same shape, and repainting one that has not changed costs a path build.
  @override
  bool shouldRepaint(ShapePainter old) =>
      !identical(old.spec, spec) ||
      old.canvasWidth != canvasWidth ||
      old.boxSize != boxSize ||
      old.pass != pass;
}

/// Clips to a shape's own outline, so a picture fill takes the shape's form: a
/// photo in a rounded rectangle, an avatar in a circle.
class ShapeClipper extends CustomClipper<Path> {
  const ShapeClipper(this.spec);

  final ShapeSpec spec;

  @override
  Path getClip(Size size) => ShapeGeometry.build(spec, size);

  @override
  bool shouldReclip(ShapeClipper old) => !identical(old.spec, spec);
}
