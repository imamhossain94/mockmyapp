import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/screen_doc.dart';

/// Where a [PatternStyle.crestTop] / `crestBottom` / `crestFull` field hangs
/// its crests from.
enum _Crest { top, bottom, full }

/// Draws a [PatternBackground] at any size.
///
/// Two rules hold across every style and are what make this usable as export
/// artwork:
///
/// * **Resolution independence.** Every coordinate, radius and stroke width is
///   a fraction of the box being painted, so a 120px thumbnail and a 2778px
///   export are the same composition rather than the same picture at different
///   crops.
/// * **Determinism.** All placement comes from `math.Random(spec.seed)`, seeded
///   fresh on each paint. Re-rendering the same document — in a thumbnail, in
///   the editor, in an export — always produces identical pixels.
///
/// Nothing here reads a theme token. A generated backdrop is the user's
/// content, and an export made in dark mode has to match one made in light.
class PatternPainter extends CustomPainter {
  const PatternPainter(this.spec);

  final PatternBackground spec;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // The panorama.
    //
    // Above one slice the composition is laid out `slices` screens wide and the
    // canvas slid so that only this slice shows. Every painter below then works
    // in the *whole* artwork's coordinates without knowing anything about it,
    // which is what makes slice 3 of 8 line up with slice 4 exactly: they are
    // literally the same picture, drawn twice, viewed through two windows.
    //
    // Seeded placement is what makes that hold — the two screens run the
    // generator over the same composition and get the same answer.
    final slices = spec.slices.clamp(1, 16);
    final rect = slices == 1
        ? Offset.zero & size
        : Rect.fromLTWH(0, 0, size.width * slices, size.height);
    if (slices > 1) {
      canvas.translate(-spec.slice.clamp(0, slices - 1) * size.width, 0);
    }

    // One generator per paint, seeded identically every time.
    final random = math.Random(spec.seed);
    final intensity = spec.intensity.clamp(0.0, 1.0);
    final scale = spec.scale.clamp(0.4, 2.5);

    switch (spec.style) {
      case PatternStyle.mesh:
        _mesh(canvas, rect, random, intensity, scale);
      case PatternStyle.blobs:
        _blobs(canvas, rect, random, intensity, scale);
      case PatternStyle.waves:
        _waves(canvas, rect, random, intensity, scale);
      case PatternStyle.rays:
        _rays(canvas, rect, random, intensity, scale);
      case PatternStyle.dots:
        _dots(canvas, rect, intensity, scale);
      case PatternStyle.grid:
        _grid(canvas, rect, intensity, scale);
      case PatternStyle.stripes:
        _stripes(canvas, rect, intensity, scale);
      case PatternStyle.aurora:
        _aurora(canvas, rect, random, intensity, scale);
      case PatternStyle.bokeh:
        _bokeh(canvas, rect, random, intensity, scale);
      case PatternStyle.rings:
        _rings(canvas, rect, random, intensity, scale);
      case PatternStyle.topography:
        _topography(canvas, rect, random, intensity, scale);
      case PatternStyle.checkers:
        _checkers(canvas, rect, intensity, scale);
      case PatternStyle.diamonds:
        _diamonds(canvas, rect, intensity, scale);
      case PatternStyle.triangles:
        _triangles(canvas, rect, intensity, scale);
      case PatternStyle.hexagons:
        _hexagons(canvas, rect, intensity, scale);
      case PatternStyle.crosses:
        _crosses(canvas, rect, intensity, scale);
      case PatternStyle.circuit:
        _circuit(canvas, rect, random, intensity, scale);
      case PatternStyle.confetti:
        _confetti(canvas, rect, random, intensity, scale);
      case PatternStyle.bubbles:
        _bubbles(canvas, rect, random, intensity, scale);
      case PatternStyle.zigzag:
        _zigzag(canvas, rect, intensity, scale);
      case PatternStyle.scales:
        _scales(canvas, rect, intensity, scale);
      case PatternStyle.crosshatch:
        _crosshatch(canvas, rect, intensity, scale);
      case PatternStyle.halftone:
        _halftone(canvas, rect, intensity, scale);
      case PatternStyle.spotlight:
        _spotlight(canvas, rect, random, intensity, scale);
      case PatternStyle.sunburst:
        _sunburst(canvas, rect, random, intensity, scale);
      case PatternStyle.swirl:
        _swirl(canvas, rect, random, intensity, scale);
      case PatternStyle.terrain:
        _terrain(canvas, rect, random, intensity, scale);
      case PatternStyle.plaid:
        _plaid(canvas, rect, intensity, scale);
      case PatternStyle.starfield:
        _starfield(canvas, rect, random, intensity, scale);
      case PatternStyle.prism:
        _prism(canvas, rect, random, intensity, scale);
      case PatternStyle.isometric:
        _isometric(canvas, rect, intensity, scale);
      case PatternStyle.poster:
        _poster(canvas, rect, random, intensity, scale);
      case PatternStyle.stage:
        _stage(canvas, rect, random, intensity, scale);
      case PatternStyle.beams:
        _beams(canvas, rect, random, intensity, scale);
      case PatternStyle.symbols:
        _symbolField(canvas, rect, random, intensity, scale);

      // Second wave of atmospherics.
      case PatternStyle.aura:
        _aura(canvas, rect, random, intensity, scale);
      case PatternStyle.broken:
        _broken(canvas, rect, random, intensity, scale);
      case PatternStyle.facets:
        _facets(canvas, rect, random, intensity, scale);
      case PatternStyle.crestTop:
        _crests(canvas, rect, random, intensity, scale, _Crest.top);
      case PatternStyle.crestBottom:
        _crests(canvas, rect, random, intensity, scale, _Crest.bottom);
      case PatternStyle.crestFull:
        _crests(canvas, rect, random, intensity, scale, _Crest.full);
      case PatternStyle.ridges:
        _ridges(canvas, rect, random, intensity, scale);
      case PatternStyle.dunes:
        _dunes(canvas, rect, random, intensity, scale);
      case PatternStyle.strata:
        _strata(canvas, rect, random, intensity, scale);
      case PatternStyle.isobars:
        _isobars(canvas, rect, random, intensity, scale);
    }

    canvas.restore();
  }

  /// One page of the artwork, for a motif that has to stay a motif.
  ///
  /// Every size in this file is a fraction of the box being painted, which is
  /// exactly right until the box is a panorama: above one slice the artwork is
  /// laid out `slices` screens wide, so a star at 0.008 of the longest side
  /// comes out five times its size and reads as a bubble, and an out-of-focus
  /// highlight comes out a third of a screen across. Fields — auroras, blooms,
  /// spotlights — are *meant* to span the whole composition and go on using the
  /// full box; the small repeating marks measure against this instead.
  ///
  /// Identical to the longest side at one slice, so nothing already drawn
  /// changes.
  double _motifUnit(Rect rect) {
    final slices = spec.slices.clamp(1, 16);
    if (slices <= 1) return rect.longestSide;
    return rect.width / slices;
  }

  // ---------------------------------------------------------------------------
  // Atmospheric styles — soft fields of colour, no visible motif
  // ---------------------------------------------------------------------------

  /// Overlapping radial fields fading to nothing — the mesh-gradient look,
  /// without needing a shader or a mesh.
  void _mesh(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final stops = math.max(2, spec.colors.length);
    final longest = math.max(rect.width, rect.height);

    for (var i = 1; i < stops + 1; i++) {
      final color = spec.colorAt(i);
      // Spread the fields around the canvas instead of clustering them: each
      // gets its own band of the vertical axis, jittered inside it.
      final band = (i - 1) / stops;
      final center = Offset(
        rect.left + rect.width * (0.15 + random.nextDouble() * 0.7),
        rect.top + rect.height * (band + random.nextDouble() / stops),
      );
      final radius = longest * (0.45 + random.nextDouble() * 0.35) * scale;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  /// A handful of large soft shapes. Reads as depth rather than as texture.
  void _blobs(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final longest = math.max(rect.width, rect.height);
    final count = (3 + spec.colors.length).clamp(3, 6);

    for (var i = 0; i < count; i++) {
      final color = spec.colorAt(i + 1);
      final center = Offset(
        rect.left + rect.width * (random.nextDouble() * 1.2 - 0.1),
        rect.top + rect.height * (random.nextDouble() * 1.2 - 0.1),
      );
      final radius = longest * (0.18 + random.nextDouble() * 0.22) * scale;

      // An oval, not a circle, so the shapes read as organic.
      final oval = Rect.fromCenter(
        center: center,
        width: radius * 2 * (0.8 + random.nextDouble() * 0.6),
        height: radius * 2 * (0.8 + random.nextDouble() * 0.6),
      );

      canvas.drawOval(
        oval,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.85 * intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0.35, 1],
          ).createShader(oval),
      );
    }
  }

  /// Tall, slightly tilted curtains of light hanging over a flat base.
  ///
  /// Each ribbon is a circular glow stretched by the canvas transform, not an
  /// oval filled with a radial gradient: `createShader` sizes a radial gradient
  /// off the rect's *shortest* side, so a tall thin oval would be lit by a
  /// small circle at its waist and read as a blob. Stretching the whole
  /// coordinate system keeps the falloff proportional to the shape.
  ///
  /// Two to three canvases tall, so only the horizontal falloff lands inside
  /// the frame — a curtain that ends where the canvas does is a bar chart.
  void _aurora(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final ribbons = (4 * scale).round().clamp(3, 8);
    for (var i = 0; i < ribbons; i++) {
      final color = spec.colorAt(1 + i % math.max(1, spec.colors.length - 1));
      // One ribbon per vertical slice, jittered inside it, so they drape across
      // the whole canvas instead of bunching in the middle.
      final center = Offset(
        rect.left +
            rect.width *
                ((i + 0.5) / ribbons + (random.nextDouble() - 0.5) * 0.3),
        rect.top + rect.height * (0.3 + random.nextDouble() * 0.4),
      );
      final width = rect.width * (0.22 + random.nextDouble() * 0.3) * scale;
      final height = rect.height * (2 + random.nextDouble() * 1.2);
      final glow = Rect.fromCircle(center: Offset.zero, radius: width / 2);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((random.nextDouble() - 0.5) * 0.5);
      canvas.scale(1, height / width);
      canvas.drawCircle(
        Offset.zero,
        width / 2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.6 * intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(glow),
      );
      canvas.restore();
    }
  }

  /// Out-of-focus discs: flat inside, bright at the rim.
  void _bokeh(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = _motifUnit(rect);
    // Per page, so a panorama is as busy as one screen rather than one
    // screen's worth of discs spread over five.
    final count = (16 * scale).round().clamp(6, 34) * spec.slices.clamp(1, 16);

    for (var i = 0; i < count; i++) {
      final color = spec.colorAt(2 + i % 2);
      final center = Offset(
        rect.left + rect.width * random.nextDouble(),
        rect.top + rect.height * random.nextDouble(),
      );
      // Squared so most discs stay small and a few dominate, which is what a
      // real out-of-focus highlight field looks like.
      final t = random.nextDouble();
      final radius = longest * (0.025 + t * t * 0.12) * scale;
      final circle = Rect.fromCircle(center: center, radius: radius);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.12 * intensity),
              color.withValues(alpha: 0.14 * intensity),
              color.withValues(alpha: 0.42 * intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.72, 0.9, 1],
          ).createShader(circle),
      );
    }
  }

  /// One pool of light with the rest of the canvas falling away around it.
  void _spotlight(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final center = Offset(
      rect.left + rect.width * (0.3 + random.nextDouble() * 0.4),
      rect.top + rect.height * (0.25 + random.nextDouble() * 0.4),
    );
    final radius = math.max(rect.width, rect.height) * 0.62 * scale;
    final glow = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            spec.colorAt(1).withValues(alpha: 0.8 * intensity),
            spec.colorAt(1).withValues(alpha: 0),
          ],
          stops: const [0, 1],
        ).createShader(glow),
    );

    // The vignette is what stops the glow reading as a stray blob: it pins the
    // composition to the canvas edges rather than to wherever the seed put it.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.75,
          colors: [
            spec.colorAt(2).withValues(alpha: 0),
            spec.colorAt(2).withValues(alpha: 0.55 * intensity),
          ],
          stops: const [0.35, 1],
        ).createShader(rect),
    );
  }

  /// Stacked sine bands over a vertical ramp.
  void _waves(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [spec.colorAt(0), spec.colorAt(1)],
        ).createShader(rect),
    );

    final bands = (4 * scale).round().clamp(2, 9);
    final amplitude = rect.height * 0.06 * scale;
    final phase = random.nextDouble() * math.pi * 2;

    for (var i = 0; i < bands; i++) {
      final color = spec.colorAt(i + 2);
      // Later bands sit lower and fade, which is what gives the stack depth.
      final baseline = rect.top + rect.height * (0.32 + i * 0.16);
      final path = Path()..moveTo(rect.left, rect.bottom);

      const steps = 48;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final x = rect.left + rect.width * t;
        final y =
            baseline + math.sin(t * math.pi * 2 + phase + i * 0.9) * amplitude;
        if (s == 0) {
          path
            ..reset()
            ..moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();

      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: (0.5 - i * 0.06) * intensity),
      );
    }
  }

  /// Layered ridge silhouettes under a sky ramp.
  void _terrain(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    const layers = 4;
    for (var i = 0; i < layers; i++) {
      // Each layer sits lower and reads darker, which is the whole trick: the
      // eye takes overlapping silhouettes with a tonal step as distance.
      final baseline = rect.top + rect.height * (0.4 + i * 0.14);
      final amplitude = rect.height * 0.13 * scale * (1 - i * 0.15);
      final ridges = 3 + i;
      final phase = random.nextDouble() * math.pi * 2;
      final detail = random.nextDouble() * math.pi * 2;

      final path = Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, baseline);

      const steps = 64;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        // Two sines at unrelated frequencies, so the skyline is irregular
        // instead of a row of identical humps. Summed rather than multiplied by
        // an absolute value: `sin().abs()` puts a cusp at every zero crossing,
        // which reads as a saw blade rather than a ridge line.
        final peak =
            0.5 +
            0.32 * math.sin(t * math.pi * ridges + phase) +
            0.18 * math.sin(t * math.pi * ridges * 2.7 + detail);
        path.lineTo(rect.left + rect.width * t, baseline - peak * amplitude);
      }

      path
        ..lineTo(rect.right, rect.bottom)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = spec
              .colorAt(2 + i % 2)
              .withValues(
                alpha: ((0.8 - i * 0.11) * intensity).clamp(0.0, 1.0),
              ),
      );
    }
  }

  /// A fan of tapered beams from an origin just off the canvas.
  void _rays(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final origin = Offset(
      rect.left + rect.width * (0.15 + random.nextDouble() * 0.7),
      rect.top - rect.height * 0.15,
    );
    final reach = rect.height * 2.2;
    final count = (12 / scale).round().clamp(5, 24);
    final start = spec.angle * math.pi / 180;

    for (var i = 0; i < count; i++) {
      if (i.isOdd) continue;
      final color = spec.colorAt(
        1 + (i ~/ 2) % math.max(1, spec.colors.length - 1),
      );
      // Beams sweep the lower half-plane, which is where the canvas is.
      final a0 = start + math.pi * (i / count);
      final a1 = start + math.pi * ((i + 0.9) / count);

      canvas.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..lineTo(
            origin.dx + math.cos(a0) * reach,
            origin.dy + math.sin(a0) * reach,
          )
          ..lineTo(
            origin.dx + math.cos(a1) * reach,
            origin.dy + math.sin(a1) * reach,
          )
          ..close(),
        Paint()..color = color.withValues(alpha: 0.22 * intensity),
      );
    }
  }

  /// Alternating wedges radiating the full way round an origin.
  void _sunburst(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final origin = Offset(
      rect.left + rect.width * (0.3 + random.nextDouble() * 0.4),
      rect.top + rect.height * (0.25 + random.nextDouble() * 0.5),
    );
    // Even, so the gaps between wedges stay the same width as the wedges.
    final wedges = ((16 / scale).round().clamp(6, 32) ~/ 2) * 2;
    final reach = math.max(rect.width, rect.height) * 2.4;
    final start = spec.angle * math.pi / 180;

    for (var i = 0; i < wedges; i += 2) {
      final a0 = start + math.pi * 2 * (i / wedges);
      final a1 = start + math.pi * 2 * ((i + 1) / wedges);
      canvas.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..lineTo(
            origin.dx + math.cos(a0) * reach,
            origin.dy + math.sin(a0) * reach,
          )
          ..lineTo(
            origin.dx + math.cos(a1) * reach,
            origin.dy + math.sin(a1) * reach,
          )
          ..close(),
        Paint()
          ..color = spec
              .colorAt(1 + (i ~/ 2) % 2)
              .withValues(alpha: 0.4 * intensity),
      );
    }
  }

  /// Spiral arms winding out from one point.
  void _swirl(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = math.max(rect.width, rect.height);
    final origin = Offset(
      rect.left + rect.width * (0.3 + random.nextDouble() * 0.4),
      rect.top + rect.height * (0.3 + random.nextDouble() * 0.4),
    );
    final arms = 3 + random.nextInt(3);
    final turns = 1.1 + random.nextDouble() * 0.8;
    final start = spec.angle * math.pi / 180;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = longest * 0.03 * scale;

    for (var a = 0; a < arms; a++) {
      final path = Path();
      const steps = 90;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final theta = start + a * math.pi * 2 / arms + t * turns * math.pi * 2;
        final point =
            origin +
            Offset(math.cos(theta), math.sin(theta)) * (longest * 1.5 * t);
        if (s == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      paint.color = spec.colorAt(2 + a % 2).withValues(alpha: 0.45 * intensity);
      canvas.drawPath(path, paint);
    }
  }

  /// Overlapping translucent shards — the low-poly / cut-glass look.
  void _prism(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    // Vertices are drawn from an over-scanned box so most shards run off an
    // edge; triangles that float entirely inside the canvas read as confetti.
    final field = rect.inflate(math.max(rect.width, rect.height) * 0.3);
    Offset vertex() => Offset(
      field.left + field.width * random.nextDouble(),
      field.top + field.height * random.nextDouble(),
    );

    final shards = (10 * scale).round().clamp(5, 24);
    for (var i = 0; i < shards; i++) {
      final a = vertex();
      final b = vertex();
      final c = vertex();
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        Paint()
          ..color = spec.colorAt(1 + i % 3).withValues(alpha: 0.28 * intensity),
      );
    }
  }

  /// Nebula glow with a scatter of stars over it.
  ///
  /// The glow is not decoration: stars sized as a fraction of the canvas are
  /// sub-pixel in a preset thumbnail, so without it the tile would be a flat
  /// fill even though the export looks right.
  void _starfield(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final longest = math.max(rect.width, rect.height);

    for (var i = 0; i < 2; i++) {
      final color = spec.colorAt(1 + i);
      final center = Offset(
        rect.left + rect.width * (0.2 + random.nextDouble() * 0.6),
        rect.top + rect.height * (0.2 + random.nextDouble() * 0.6),
      );
      final radius = longest * (0.4 + random.nextDouble() * 0.3);
      final area = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.45 * intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(area),
      );
    }

    // The two nebulae above span the whole composition on purpose; a star is
    // a mark and is sized off one page.
    final unit = _motifUnit(rect);
    final stars =
        (70 * scale).round().clamp(30, 160) * spec.slices.clamp(1, 16);
    final paint = Paint();
    for (var i = 0; i < stars; i++) {
      final center = Offset(
        rect.left + rect.width * random.nextDouble(),
        rect.top + rect.height * random.nextDouble(),
      );
      final t = random.nextDouble();
      paint.color = spec
          .colorAt(3)
          .withValues(alpha: ((0.35 + t * 0.6) * intensity).clamp(0.0, 1.0));
      canvas.drawCircle(center, unit * (0.002 + t * t * 0.006) * scale, paint);
    }
  }

  // ---------------------------------------------------------------------------
  // Line and lattice styles — a visible, repeating motif
  // ---------------------------------------------------------------------------

  /// A regular field of soft dots over a ramp.
  void _dots(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final step = math.max(rect.width, rect.height) / (14 / scale);
    final radius = step * 0.16;
    final paint = Paint()
      ..color = spec.colorAt(2).withValues(alpha: 0.5 * intensity);

    _tiled(canvas, rect, step, (offset) {
      canvas.drawCircle(offset, radius, paint);
    });
  }

  /// A dot field whose dots shrink across the canvas.
  void _halftone(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final step = math.max(rect.width, rect.height) / (20 / scale);
    final paint = Paint()
      ..color = spec.colorAt(2).withValues(alpha: 0.7 * intensity);

    _tiled(canvas, rect, step, (offset) {
      // The size ramp is what separates a halftone from a dot grid; taken along
      // the diagonal so it survives any [spec.angle].
      final t =
          (((offset.dx - rect.left) / rect.width) +
              ((offset.dy - rect.top) / rect.height)) /
          2;
      final radius = step * 0.48 * (1 - t.clamp(0.0, 1.0));
      if (radius > 0.05) canvas.drawCircle(offset, radius, paint);
    });
  }

  /// Fine graph-paper ruling over a ramp.
  void _grid(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final step = math.max(rect.width, rect.height) / (16 / scale);
    // Hairlines scale with the canvas so the ruling has the same visual weight
    // in a thumbnail and in a full-size export.
    final paint = Paint()
      ..color = spec.colorAt(2).withValues(alpha: 0.35 * intensity)
      ..strokeWidth = math.max(rect.width * 0.0015, 0.5)
      ..style = PaintingStyle.stroke;

    _rotated(canvas, rect, (bounds) {
      for (var x = bounds.left; x <= bounds.right; x += step) {
        canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
      }
      for (var y = bounds.top; y <= bounds.bottom; y += step) {
        canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
      }
    });
  }

  /// Two sets of diagonal hairlines crossing.
  void _crosshatch(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final step = math.max(rect.width, rect.height) / (18 / scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(rect.width * 0.0018, 0.5);

    _rotated(canvas, rect, (bounds) {
      paint.color = spec.colorAt(2).withValues(alpha: 0.4 * intensity);
      for (var x = bounds.left - bounds.height; x <= bounds.right; x += step) {
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x + bounds.height, bounds.bottom),
          paint,
        );
      }
      // The second pass is a shade lighter, so the two directions stay legible
      // where they overlap instead of merging into a solid tint.
      paint.color = spec.colorAt(3).withValues(alpha: 0.3 * intensity);
      for (var x = bounds.left; x <= bounds.right + bounds.height; x += step) {
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x - bounds.height, bounds.bottom),
          paint,
        );
      }
    });
  }

  /// Wide diagonal bands.
  void _stripes(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final band = math.max(rect.width, rect.height) / (9 / scale);
    final paint = Paint()
      ..color = spec.colorAt(1).withValues(alpha: 0.55 * intensity);

    _rotated(canvas, rect, (bounds) {
      for (var x = bounds.left; x <= bounds.right; x += band * 2) {
        canvas.drawRect(
          Rect.fromLTWH(x, bounds.top, band, bounds.height),
          paint,
        );
      }
    });
  }

  /// Crossing translucent bands — a tartan.
  ///
  /// Every band is translucent, so the plaid's darker squares come from the
  /// overlaps rather than from a third set of hand-picked colours.
  void _plaid(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final unit = math.max(rect.width, rect.height) / (7 / scale);
    final paint = Paint();

    _rotated(canvas, rect, (bounds) {
      void bands({required bool vertical}) {
        final start = vertical ? bounds.left : bounds.top;
        final end = vertical ? bounds.right : bounds.bottom;

        for (var v = start; v <= end; v += unit) {
          void band(double offset, double width, int stop, double alpha) {
            paint.color = spec
                .colorAt(stop)
                .withValues(alpha: (alpha * intensity).clamp(0.0, 1.0));
            canvas.drawRect(
              vertical
                  ? Rect.fromLTWH(v + offset, bounds.top, width, bounds.height)
                  : Rect.fromLTWH(bounds.left, v + offset, bounds.width, width),
              paint,
            );
          }

          band(0, unit * 0.42, 1, 0.28);
          band(unit * 0.52, unit * 0.12, 2, 0.42);
          band(unit * 0.72, unit * 0.06, 3, 0.5);
        }
      }

      bands(vertical: true);
      bands(vertical: false);
    });
  }

  /// A two-tone checkerboard.
  void _checkers(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final step = math.max(rect.width, rect.height) / (10 / scale);
    final paint = Paint()
      ..color = spec.colorAt(1).withValues(alpha: 0.9 * intensity);

    _lattice(canvas, rect, step, step, (point, column, row) {
      if ((column + row).isEven) {
        canvas.drawRect(Rect.fromLTWH(point.dx, point.dy, step, step), paint);
      }
    });
  }

  /// A staggered lattice of filled diamonds.
  void _diamonds(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final step = math.max(rect.width, rect.height) / (9 / scale);
    final half = step * 0.42;
    final paint = Paint();

    _lattice(canvas, rect, step, step, (point, column, row) {
      paint.color = spec
          .colorAt(1 + (column + row) % 2)
          .withValues(alpha: 0.7 * intensity);
      canvas.drawPath(
        Path()
          ..moveTo(point.dx, point.dy - half)
          ..lineTo(point.dx + half, point.dy)
          ..lineTo(point.dx, point.dy + half)
          ..lineTo(point.dx - half, point.dy)
          ..close(),
        paint,
      );
    }, stagger: true);
  }

  /// A triangle tessellation in alternating tones.
  void _triangles(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final side = math.max(rect.width, rect.height) / (8 / scale);
    final height = side * 0.866;
    final paint = Paint();

    _rotated(canvas, rect, (bounds) {
      var row = 0;
      for (var y = bounds.top; y <= bounds.bottom; y += height, row++) {
        var column = 0;
        for (var x = bounds.left; x <= bounds.right; x += side / 2, column++) {
          // Alternating orientation is what makes the row tile without gaps:
          // every downward triangle fills the notch its neighbours leave.
          final up = (row + column).isEven;
          final path = Path();
          if (up) {
            path
              ..moveTo(x, y + height)
              ..lineTo(x + side / 2, y)
              ..lineTo(x + side, y + height);
          } else {
            path
              ..moveTo(x, y)
              ..lineTo(x + side / 2, y + height)
              ..lineTo(x + side, y);
          }
          path.close();

          paint.color = spec
              .colorAt(1 + (column + row * 2) % 3)
              .withValues(alpha: (up ? 0.55 : 0.3) * intensity);
          canvas.drawPath(path, paint);
        }
      }
    });
  }

  /// An outlined honeycomb.
  void _hexagons(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final radius = math.max(rect.width, rect.height) / (13 / scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(radius * 0.12, 0.6)
      ..color = spec.colorAt(2).withValues(alpha: 0.5 * intensity);

    _lattice(
      canvas,
      rect,
      radius * math.sqrt(3),
      radius * 1.5,
      (point, column, row) => canvas.drawPath(_hexagon(point, radius), paint),
      stagger: true,
    );
  }

  /// A grid of three-faced isometric cubes.
  ///
  /// A cube is just a hexagon split into three rhombi at its centre, which is
  /// why this shares the honeycomb's lattice: hexagons tile, so cubes do too.
  void _isometric(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final radius = math.max(rect.width, rect.height) / (11 / scale);
    final paint = Paint();

    void face(List<Offset> points, int stop, double alpha) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      paint.color = spec
          .colorAt(stop)
          .withValues(alpha: (alpha * intensity).clamp(0.0, 1.0));
      canvas.drawPath(path, paint);
    }

    _lattice(canvas, rect, radius * math.sqrt(3), radius * 1.5, (
      point,
      column,
      row,
    ) {
      final v = _hexagonPoints(point, radius);
      // Top face brightest, then right, then left: one light source, which is
      // the only thing that makes a flat rhombus read as a solid.
      face([v[5], v[0], v[1], point], 1, 0.9);
      face([point, v[1], v[2], v[3]], 2, 0.62);
      face([point, v[3], v[4], v[5]], 3, 0.38);
    }, stagger: true);
  }

  /// A staggered lattice of small plus signs.
  void _crosses(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final step = math.max(rect.width, rect.height) / (13 / scale);
    final arm = step * 0.3;
    final thickness = step * 0.09;
    final paint = Paint()
      ..color = spec.colorAt(2).withValues(alpha: 0.55 * intensity);

    _lattice(canvas, rect, step, step, (point, column, row) {
      canvas.drawRect(
        Rect.fromCenter(center: point, width: arm * 2, height: thickness * 2),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: thickness * 2, height: arm * 2),
        paint,
      );
    }, stagger: true);
  }

  /// Overlapping arcs, like fish scales or roof tiles.
  void _scales(Canvas canvas, Rect rect, double intensity, double scale) {
    _paintRamp(canvas, rect);

    final radius = math.max(rect.width, rect.height) / (9 / scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(radius * 0.13, 0.6);

    _lattice(canvas, rect, radius * 2, radius, (point, column, row) {
      paint.color = spec
          .colorAt(2 + row % 2)
          .withValues(alpha: 0.5 * intensity);
      // Half-turn from pi: the upper half of the circle, which is the arc
      // that reads as a scale once the rows overlap.
      canvas.drawArc(
        Rect.fromCircle(center: point, radius: radius),
        math.pi,
        math.pi,
        false,
        paint,
      );
    }, stagger: true);
  }

  /// Stacked chevron rows.
  void _zigzag(Canvas canvas, Rect rect, double intensity, double scale) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final step = math.max(rect.width, rect.height) / (10 / scale);
    final amplitude = step * 0.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = step * 0.22;

    _rotated(canvas, rect, (bounds) {
      var row = 0;
      for (var y = bounds.top; y <= bounds.bottom + step; y += step, row++) {
        final path = Path()..moveTo(bounds.left, y);
        var peak = 0;
        for (var x = bounds.left; x <= bounds.right + step; x += step, peak++) {
          path.lineTo(x, peak.isEven ? y : y - amplitude);
        }
        paint.color = spec
            .colorAt(1 + row % 2)
            .withValues(alpha: 0.6 * intensity);
        canvas.drawPath(path, paint);
      }
    });
  }

  /// Concentric rings spreading from one point.
  void _rings(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = math.max(rect.width, rect.height);
    final origin = Offset(
      rect.left + rect.width * (0.15 + random.nextDouble() * 0.7),
      rect.top + rect.height * (0.15 + random.nextDouble() * 0.7),
    );
    final step = longest / (13 / scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(step * 0.22, 0.5);

    for (var i = 1; step * i < longest * 1.8; i++) {
      // Fading outwards keeps the origin the subject; a ring field at even
      // weight just reads as noise.
      paint.color = spec
          .colorAt(2 + i % 2)
          .withValues(alpha: ((0.55 - i * 0.015) * intensity).clamp(0.0, 1.0));
      canvas.drawCircle(origin, step * i, paint);
    }
  }

  /// Nested contour lines, like a map's height curves.
  void _topography(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = math.max(rect.width, rect.height);
    final origin = Offset(
      rect.left + rect.width * (0.2 + random.nextDouble() * 0.6),
      rect.top + rect.height * (0.2 + random.nextDouble() * 0.6),
    );
    final step = longest / (16 / scale);
    // Three unrelated harmonics: one is a circle, two is an oval, three is the
    // irregular closed curve a contour line actually looks like.
    final wobble = [
      random.nextDouble() * math.pi * 2,
      random.nextDouble() * math.pi * 2,
      random.nextDouble() * math.pi * 2,
    ];

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(rect.width * 0.003, 0.6);

    final lines = (longest * 1.6 / step).ceil();
    for (var i = 1; i <= lines; i++) {
      final base = step * i;
      final path = Path();
      const steps = 72;
      for (var s = 0; s <= steps; s++) {
        final angle = s / steps * math.pi * 2;
        final radius =
            base *
            (1 +
                0.14 * math.sin(angle * 3 + wobble[0]) +
                0.09 * math.sin(angle * 5 + wobble[1]) +
                0.05 * math.sin(angle * 8 + wobble[2]));
        final point =
            origin +
            Offset(math.cos(angle) * radius, math.sin(angle) * radius * 0.85);
        if (s == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();

      paint.color = spec.colorAt(2 + i % 2).withValues(alpha: 0.42 * intensity);
      canvas.drawPath(path, paint);
    }
  }

  /// Outlined circles at mixed sizes.
  void _bubbles(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = math.max(rect.width, rect.height);
    final count = (18 * scale).round().clamp(8, 40);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(longest * 0.004, 0.6);
    final fill = Paint();

    for (var i = 0; i < count; i++) {
      final color = spec.colorAt(2 + i % 2);
      final center = Offset(
        rect.left + rect.width * random.nextDouble(),
        rect.top + rect.height * random.nextDouble(),
      );
      final t = random.nextDouble();
      final radius = longest * (0.02 + t * t * 0.13) * scale;

      // Every other bubble takes a faint fill, which is what stops the field
      // reading as a flat outline texture.
      if (i.isEven) {
        fill.color = color.withValues(alpha: 0.12 * intensity);
        canvas.drawCircle(center, radius, fill);
      }
      stroke.color = color.withValues(alpha: 0.5 * intensity);
      canvas.drawCircle(center, radius, stroke);
    }
  }

  /// Right-angled traces with a pad at each end — the circuit-board look.
  void _circuit(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final step = math.max(rect.width, rect.height) / (18 / scale);
    final trace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(step * 0.14, 0.6)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final pad = Paint();

    final traces = (14 * scale).round().clamp(6, 26);
    for (var i = 0; i < traces; i++) {
      final color = spec.colorAt(1 + i % 2);
      // Every turn is a right angle on the same lattice, so unrelated traces
      // still look like one board rather than a scribble.
      var x =
          rect.left +
          (random.nextDouble() * rect.width / step).floorToDouble() * step;
      var y =
          rect.top +
          (random.nextDouble() * rect.height / step).floorToDouble() * step;

      final path = Path()..moveTo(x, y);
      pad.color = color.withValues(alpha: 0.75 * intensity);
      canvas.drawCircle(Offset(x, y), step * 0.22, pad);

      var horizontal = random.nextBool();
      final segments = 3 + random.nextInt(5);
      for (var s = 0; s < segments; s++) {
        final length =
            step * (1 + random.nextInt(4)) * (random.nextBool() ? 1 : -1);
        if (horizontal) {
          x += length;
        } else {
          y += length;
        }
        path.lineTo(x, y);
        horizontal = !horizontal;
      }

      trace.color = color.withValues(alpha: 0.55 * intensity);
      canvas.drawPath(path, trace);
      canvas.drawCircle(Offset(x, y), step * 0.22, pad);
    }
  }

  /// Small rotated capsules scattered across the canvas.
  void _confetti(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final longest = math.max(rect.width, rect.height);
    final count = (26 * scale).round().clamp(10, 60);
    final paint = Paint();

    for (var i = 0; i < count; i++) {
      final color = spec.colorAt(1 + i % math.max(1, spec.colors.length - 1));
      final center = Offset(
        rect.left + rect.width * random.nextDouble(),
        rect.top + rect.height * random.nextDouble(),
      );
      final width = longest * 0.014 * scale;
      final height = longest * (0.03 + random.nextDouble() * 0.03) * scale;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(random.nextDouble() * math.pi);
      paint.color = color.withValues(
        alpha: ((0.55 + random.nextDouble() * 0.4) * intensity).clamp(0.0, 1.0),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: width, height: height),
          Radius.circular(width * 0.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------
  // Store-panel styles — the marketing-screenshot looks
  // ---------------------------------------------------------------------------

  /// The vertical poster ramp [_poster] and [_beams] share: slightly lifted at
  /// the top, the pure base colour through the middle, sunk toward the mid
  /// stop at the foot. One saturated hue owning the whole canvas is the look;
  /// stop 1 only decides what "darker" means for it.
  void _posterRamp(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(spec.colorAt(0), const Color(0xFFFFFFFF), 0.12)!,
            spec.colorAt(0),
            Color.lerp(spec.colorAt(0), spec.colorAt(1), 0.45)!,
          ],
          stops: const [0.0, 0.40, 1.0],
        ).createShader(rect),
    );
  }

  /// A saturated poster panel: the base hue floods the canvas under a top
  /// highlight, ghost rounded squares drift across it and a dot mist keeps the
  /// upper half from reading as a flat swatch. Stop 3 tints the ghosts.
  void _poster(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _posterRamp(canvas, rect);
    final longest = rect.longestSide;

    // The high, wide light the panel sits under.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.92),
          radius: 0.9,
          colors: [
            spec.colorAt(3).withValues(alpha: 0.13 * intensity),
            spec.colorAt(3).withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Ghost squares, one per horizontal band so they scatter rather than
    // cluster. Alternating fill and stroke, like cut-outs and outlines.
    final ghost = spec.colorAt(3);
    final count = (4 * scale).round().clamp(3, 7);
    for (var i = 0; i < count; i++) {
      final cx = rect.left + rect.width * random.nextDouble();
      final band = (i + random.nextDouble()) / count;
      final cy = rect.top + rect.height * 0.5 * band;
      final side = longest * (0.16 + random.nextDouble() * 0.22) * scale;
      final rotation = (random.nextDouble() - 0.5) * 0.7;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rotation);
      final box = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Radius.circular(side * 0.22),
      );
      canvas.drawRRect(
        box,
        i.isEven
            ? (Paint()..color = ghost.withValues(alpha: 0.055 * intensity))
            : (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = longest * 0.008
                ..color = ghost.withValues(alpha: 0.075 * intensity)),
      );
      canvas.restore();
    }

    // The dot mist across the upper half. Deliberately near-invisible: it
    // reads as paper grain at export size and simply vanishes in thumbnails,
    // where the ramp and squares carry the composition.
    final dot = Paint()..color = ghost.withValues(alpha: 0.05 * intensity);
    final spacing = longest * 0.032 * scale;
    final mistBottom = rect.top + rect.height * 0.62;
    for (var y = rect.top + spacing / 2; y < mistBottom; y += spacing) {
      for (var x = rect.left + spacing / 2; x < rect.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), longest * 0.0012, dot);
      }
    }
  }

  /// A dark stage: a near-black bed (stop 0), a cool ambient wash pouring in
  /// high up (stop 1), one colour bloom at centre (stop 2) and a floor that
  /// falls away to shadow. Everything a lit product shot needs behind it.
  void _stage(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    // Where the two lights hang.
    //
    // This used to take no random at all: every alignment below was a literal,
    // so a stage was the same lighting rig whatever the seed and a row of stage
    // presets differed only in hue. The rig now moves — the ambient slides
    // across the top, the bloom drifts and breathes — while staying a stage:
    // ambient high and wide, bloom low and tight.
    final ambientX = (random.nextDouble() - 0.5) * 0.7;
    final ambientY = -0.86 + random.nextDouble() * 0.18;
    final ambientR = 0.92 + random.nextDouble() * 0.30;
    final bloomX = (random.nextDouble() - 0.5) * 0.5;
    final bloomY = -0.24 + random.nextDouble() * 0.30;
    final bloomR = 0.68 + random.nextDouble() * 0.34;

    // The ambient light source, high and broad.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(ambientX, ambientY),
          radius: ambientR * scale,
          colors: [
            spec.colorAt(1).withValues(alpha: 0.50 * intensity),
            spec.colorAt(1).withValues(alpha: 0.25 * intensity),
            spec.colorAt(1).withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // The bloom that will halo whatever the user floats over the stage.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(bloomX, bloomY),
          radius: bloomR * scale,
          colors: [
            spec.colorAt(2).withValues(alpha: 0.30 * intensity),
            spec.colorAt(2).withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Floor falling to shadow, then the edges pulled down all round.
    final floor = Color.lerp(spec.colorAt(0), const Color(0xFF000000), 0.55)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [floor.withValues(alpha: 0), floor.withValues(alpha: 0.8)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [
            const Color(0x00000000),
            const Color(0xFF000000).withValues(alpha: 0.5 * intensity),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );

    // The same grain mist as the poster, cooled to the ambient stop.
    final dot = Paint()
      ..color = spec.colorAt(1).withValues(alpha: 0.10 * intensity);
    final spacing = rect.longestSide * 0.030 * scale;
    for (var y = rect.top + spacing / 2; y < rect.bottom; y += spacing) {
      for (var x = rect.left + spacing / 2; x < rect.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), rect.longestSide * 0.0011, dot);
      }
    }
  }

  /// One bent arrow — vertical tail, horizontal run, filled head — the ghost
  /// motif [_beams] scatters the way the store panels echo a puzzle piece.
  void _ghostArrow(
    Canvas canvas,
    Offset elbow,
    double unit,
    double rotation,
    Color color,
  ) {
    canvas.save();
    canvas.translate(elbow.dx, elbow.dy);
    canvas.rotate(rotation);
    canvas.drawPath(
      Path()
        ..moveTo(0, unit)
        ..lineTo(0, 0)
        ..lineTo(unit * 0.92, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.26
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawPath(
      Path()
        ..moveTo(unit * 1.32, 0)
        ..lineTo(unit * 0.82, -unit * 0.36)
        ..lineTo(unit * 0.82, unit * 0.36)
        ..close(),
      Paint()..color = color,
    );
    canvas.restore();
  }

  /// The poster ramp swept by diagonal light: a corner flare, soft-edged
  /// beams running through the canvas, ghost arrows and sparkles up top and a
  /// light swoosh across the foot. The angle knob steers the beams.
  void _beams(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _posterRamp(canvas, rect);
    final longest = rect.longestSide;
    final light = spec.colorAt(3);

    // The flare the beams appear to pour out of.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.9, -1.05),
          radius: 1.15,
          colors: [
            light.withValues(alpha: 0.25 * intensity),
            light.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Beams: bands rotated about the centre, soft-edged by running the fill
    // transparent → light → transparent across each band's height. No blur —
    // gradient falloff keeps thumbnails and exports identical.
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(-0.58 + spec.angle * math.pi / 180);
    canvas.translate(0, -rect.height * 0.10);
    for (final (offset, band, alpha) in const [
      (-0.36, 0.26, 0.110),
      (-0.04, 0.14, 0.080),
      (0.26, 0.22, 0.095),
    ]) {
      final bandRect = Rect.fromLTWH(
        -longest * 2,
        rect.height * offset - rect.height * band * 0.5 * scale,
        longest * 4,
        rect.height * band * scale,
      );
      canvas.drawRect(
        bandRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              light.withValues(alpha: 0),
              light.withValues(alpha: alpha * intensity),
              light.withValues(alpha: 0),
            ],
          ).createShader(bandRect),
      );
    }
    canvas.restore();

    // Ghost arrows.
    //
    // These used to be two arrows pinned to the top-left and top-right, with
    // the seed jittering each by four to eight percent of the canvas — which is
    // to say invisibly. Every beams composition therefore had the same two
    // arrows in the same two places, and a row of beams presets read as one
    // picture recoloured.
    //
    // So the seed now chooses the arrangement rather than nudging it: how many
    // arrows, which of eight anchors around the margin they hang on, and each
    // one's size and angle. Two compositions share a layout only when they
    // share a seed.
    const anchors = <Offset>[
      Offset(0.07, 0.05),
      Offset(0.91, 0.17),
      Offset(0.14, 0.83),
      Offset(0.86, 0.72),
      Offset(0.50, 0.06),
      Offset(0.06, 0.44),
      Offset(0.94, 0.47),
      Offset(0.42, 0.90),
    ];

    final picks = List<Offset>.from(anchors)..shuffle(random);
    final arrowCount = 2 + random.nextInt(2);
    for (var i = 0; i < arrowCount; i++) {
      final at = picks[i];
      _ghostArrow(
        canvas,
        Offset(
          rect.left + rect.width * (at.dx + (random.nextDouble() - 0.5) * 0.05),
          rect.top + rect.height * (at.dy + (random.nextDouble() - 0.5) * 0.05),
        ),
        longest * (0.040 + random.nextDouble() * 0.028) * scale,
        random.nextDouble() * math.pi * 2,
        light.withValues(
          alpha: (0.10 + random.nextDouble() * 0.06) * intensity,
        ),
      );
    }

    // A few sparkles in the headline's airspace.
    final sparkleCount = (5 * scale).round().clamp(3, 9);
    for (var i = 0; i < sparkleCount; i++) {
      final t = random.nextDouble();
      canvas.drawCircle(
        Offset(
          rect.left + rect.width * random.nextDouble(),
          rect.top + rect.height * random.nextDouble() * 0.28,
        ),
        longest * (0.0015 + t * t * 0.0022) * scale,
        Paint()..color = light.withValues(alpha: 0.30 * intensity),
      );
    }

    // The light swoosh across the foot — a soft-edged band like the beams,
    // shallower and nearly level.
    canvas.save();
    canvas.translate(rect.center.dx, rect.top + rect.height * 0.955);
    canvas.rotate(-0.16);
    final swoosh = Rect.fromCenter(
      center: Offset.zero,
      width: longest * 1.7,
      height: rect.height * 0.06,
    );
    canvas.drawRect(
      swoosh,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            light.withValues(alpha: 0),
            light.withValues(alpha: 0.10 * intensity),
            light.withValues(alpha: 0),
          ],
        ).createShader(swoosh),
    );
    canvas.restore();

    // Floor vignette, gentle enough to keep the panel reading bright.
    final floor = Color.lerp(spec.colorAt(0), const Color(0xFF000000), 0.6)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [floor.withValues(alpha: 0), floor.withValues(alpha: 0.18)],
          stops: const [0.70, 1.0],
        ).createShader(rect),
    );
  }

  // ---------------------------------------------------------------------------
  // Icon motif — a scattered field of chosen symbols
  // ---------------------------------------------------------------------------

  /// Stamps [PatternBackground.symbols] across the canvas on a jittered
  /// lattice.
  ///
  /// A lattice rather than a free scatter because free scatter clumps: pure
  /// random placement leaves bald patches and three-glyph pile-ups, which reads
  /// as a mistake rather than as a pattern. Jittering inside each cell keeps
  /// the spacing even while losing the grid.
  ///
  /// The jitter, size and spin all come from [random], so a new seed genuinely
  /// rearranges the field instead of recolouring the same picture — which is
  /// what the seed test asks of every non-tiling style.
  ///
  /// **Every glyph is one [Path], drawn once.** This is not tidiness, it is the
  /// whole reason the symbols read as symbols: the glyphs were once assembled
  /// from three or four separate `drawRect`/`drawOval`/`drawPath` calls, and
  /// since the field paints at under full alpha, every overlap between those
  /// pieces stacked into a darker patch. A note's stem crossing its head, a
  /// speech bubble meeting its tail — each showed a seam exactly where the
  /// shape was supposed to be solid. One path with several subpaths fills under
  /// the non-zero rule, so overlaps merge and the glyph is a single flat
  /// silhouette at one alpha.
  void _symbolField(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final chosen = spec.symbols.isEmpty
        ? const [PatternSymbol.heart]
        : spec.symbols;

    // Count is a target, not a tally. It sets the lattice pitch across the
    // canvas; the field is then overscanned and rotated, so some of what gets
    // laid down lands outside the frame. Deriving the pitch from the count —
    // rather than exposing the pitch — is what makes the knob mean the thing
    // people actually want to change.
    final count = spec.symbolCount.clamp(2, 400);
    final cells = math.sqrt(count * rect.width / rect.height);
    final step = rect.width / math.max(1.0, cells);
    if (step <= 0) return;

    final stops = math.max(1, spec.colors.length - 1);
    final alpha = (spec.symbolOpacity * intensity).clamp(0.0, 1.0);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var index = 0;

    canvas.save();
    canvas.translate(
      spec.symbolCenter.dx * rect.width,
      spec.symbolCenter.dy * rect.height,
    );

    _rotated(canvas, rect, (bounds) {
      for (var y = bounds.top; y <= bounds.bottom; y += step) {
        for (var x = bounds.left; x <= bounds.right; x += step) {
          final symbol = chosen[index % chosen.length];
          final unit = step * (0.2 + random.nextDouble() * 0.13) * scale;
          final stroke = _strokeWidthFor(symbol);

          paint
            ..color = spec.colorAt(1 + index % stops).withValues(alpha: alpha)
            ..style = stroke > 0 ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = unit * stroke;

          canvas.save();
          canvas.translate(
            x + (random.nextDouble() - 0.5) * step * 0.66,
            y + (random.nextDouble() - 0.5) * step * 0.66,
          );
          canvas.rotate((random.nextDouble() - 0.5) * _tiltFor(symbol));
          canvas.drawPath(_pathFor(symbol, unit), paint);
          canvas.restore();
          index++;
        }
      }
    });

    canvas.restore();
  }

  /// The glyph for [symbol] at radius [unit], centred on the origin.
  static Path _pathFor(PatternSymbol symbol, double unit) => switch (symbol) {
    PatternSymbol.note => _note(unit),
    PatternSymbol.waveform => _waveform(unit),
    PatternSymbol.heart => _heart(unit),
    PatternSymbol.download => _download(unit),
    PatternSymbol.wifi => _wifi(unit),
    PatternSymbol.network => _networkGlyph(unit),
    PatternSymbol.sparkle => _sparkle(unit),
    PatternSymbol.chat => _chat(unit),
    PatternSymbol.play => _play(unit),
    PatternSymbol.shield => _shield(unit),
    PatternSymbol.cloud => _cloud(unit),
    PatternSymbol.pin => _pin(unit),
    PatternSymbol.star => _star(unit),
    PatternSymbol.bolt => _bolt(unit),
    PatternSymbol.aperture => _aperture(unit),
    PatternSymbol.orbit => _orbit(unit),
    PatternSymbol.bell => _bell(unit),
    PatternSymbol.bug => _bug(unit),
    PatternSymbol.hash => _hash(unit),
    PatternSymbol.at => _at(unit),
  };

  /// Stroke width as a fraction of the glyph's unit, or zero to fill it.
  ///
  /// A property of the symbol rather than of the style: an outlined heart and
  /// a filled wi-fi fan are both wrong, whatever the rest of the field is set
  /// to, so this is not a knob.
  static double _strokeWidthFor(PatternSymbol symbol) => switch (symbol) {
    PatternSymbol.wifi => 0.2,
    PatternSymbol.aperture => 0.16,
    PatternSymbol.orbit => 0.14,
    PatternSymbol.at => 0.17,
    PatternSymbol.network => 0.11,
    _ => 0,
  };

  /// The widest angle a symbol may turn.
  ///
  /// Symbols with an obvious "up" — a download arrow, a wi-fi fan, a bell —
  /// take a small tilt or none; a heart or a sparkle can take a large one.
  static double _tiltFor(PatternSymbol symbol) => switch (symbol) {
    PatternSymbol.sparkle || PatternSymbol.star => 1.2,
    PatternSymbol.aperture || PatternSymbol.orbit => 1.2,
    PatternSymbol.heart || PatternSymbol.bug => 0.8,
    PatternSymbol.hash || PatternSymbol.bolt => 0.6,
    PatternSymbol.note || PatternSymbol.bell || PatternSymbol.at => 0.5,
    PatternSymbol.chat || PatternSymbol.play => 0.45,
    PatternSymbol.wifi || PatternSymbol.shield || PatternSymbol.pin => 0.3,
    PatternSymbol.download => 0.25,
    PatternSymbol.cloud => 0.15,
    PatternSymbol.waveform || PatternSymbol.network => 0,
  };

  /// Three linked nodes — the network glyph.
  ///
  /// The old `network` style drew a whole graph across the canvas, which is not
  /// something a symbol can be. This is the same idea shrunk to one mark: a
  /// triangle of nodes with the edges between them, stroked in one path.
  static Path _networkGlyph(double u) {
    final nodes = [
      Offset(0, -u * 0.85),
      Offset(-u * 0.8, u * 0.6),
      Offset(u * 0.8, u * 0.6),
    ];
    final path = Path()
      ..moveTo(nodes[0].dx, nodes[0].dy)
      ..lineTo(nodes[1].dx, nodes[1].dy)
      ..lineTo(nodes[2].dx, nodes[2].dy)
      ..close();
    for (final node in nodes) {
      path.addOval(Rect.fromCircle(center: node, radius: u * 0.2));
    }
    return path;
  }

  /// A quaver: head, stem and flag as one silhouette.
  ///
  /// The head sits upright rather than slanted the way a engraved note's does.
  /// A slanted head has to be rotated about its own centre, which means either
  /// a second draw call — the seam this whole section exists to avoid — or a
  /// matrix on the subpath for a tilt nobody can see at a 40dp preset tile.
  static Path _note(double u) => Path()
    ..addOval(
      Rect.fromCenter(
        center: Offset(-u * 0.3, u * 0.62),
        width: u * 1.02,
        height: u * 0.76,
      ),
    )
    ..addRect(Rect.fromLTWH(u * 0.06, -u, u * 0.17, u * 1.68))
    ..addPath(
      Path()
        ..moveTo(u * 0.23, -u)
        ..quadraticBezierTo(u * 1.02, -u * 0.72, u * 0.62, -u * 0.02)
        ..quadraticBezierTo(u * 0.8, -u * 0.58, u * 0.23, -u * 0.5)
        ..close(),
      Offset.zero,
    );

  /// Audio waveform: capsules mirrored about the centre line.
  ///
  /// Heights come from a fixed cosine rather than the generator, so the bar
  /// spacing stays even. This is the one that replaced the equaliser: the two
  /// were the same idea, and columns of bars rooted at a baseline read as a bar
  /// chart rather than as sound.
  static Path _waveform(double u) {
    final path = Path();
    for (var i = 0; i < 7; i++) {
      final t = i / 6;
      final height =
          u * (0.22 + 0.85 * (0.5 - 0.5 * math.cos(t * math.pi * 3)));
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-u + i * u * 0.34, 0),
            width: u * 0.19,
            height: math.max(height, u * 0.19) * 2,
          ),
          Radius.circular(u * 0.1),
        ),
      );
    }
    return path;
  }

  static Path _heart(double u) => Path()
    ..moveTo(0, u * 0.9)
    ..cubicTo(-u * 1.55, -u * 0.18, -u * 0.72, -u * 1.15, 0, -u * 0.42)
    ..cubicTo(u * 0.72, -u * 1.15, u * 1.55, -u * 0.18, 0, u * 0.9)
    ..close();

  /// A down arrow over a tray.
  static Path _download(double u) => Path()
    ..addRect(Rect.fromLTWH(-u * 0.15, -u, u * 0.3, u * 1.05))
    ..addPath(
      Path()
        ..moveTo(0, u * 0.62)
        ..lineTo(-u * 0.55, u * 0.02)
        ..lineTo(u * 0.55, u * 0.02)
        ..close(),
      Offset.zero,
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-u * 0.8, u * 0.78, u * 1.6, u * 0.22),
        Radius.circular(u * 0.11),
      ),
    );

  /// Three arcs fanning up from a dot. Stroked, so the dot is a stub segment
  /// under a round cap rather than a filled circle the stroke could not draw.
  static Path _wifi(double u) {
    final path = Path();
    for (var i = 1; i <= 3; i++) {
      path.addArc(
        Rect.fromCircle(center: Offset(0, u * 0.72), radius: u * 0.4 * i),
        -math.pi * 0.78,
        math.pi * 0.56,
      );
    }
    return path
      ..moveTo(0, u * 0.7)
      ..lineTo(0, u * 0.71);
  }

  /// A four-point sparkle with concave sides.
  static Path _sparkle(double u) => Path()
    ..moveTo(0, -u)
    ..quadraticBezierTo(u * 0.16, -u * 0.16, u, 0)
    ..quadraticBezierTo(u * 0.16, u * 0.16, 0, u)
    ..quadraticBezierTo(-u * 0.16, u * 0.16, -u, 0)
    ..quadraticBezierTo(-u * 0.16, -u * 0.16, 0, -u)
    ..close();

  /// A rounded speech bubble whose tail grows out of the body.
  static Path _chat(double u) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-u, -u * 0.9, u * 2, u * 1.5),
        Radius.circular(u * 0.42),
      ),
    )
    ..addPath(
      Path()
        ..moveTo(-u * 0.56, u * 0.2)
        ..lineTo(-u * 0.42, u * 1.06)
        ..lineTo(-u * 0.02, u * 0.36)
        ..close(),
      Offset.zero,
    );

  static Path _play(double u) => Path()
    ..moveTo(-u * 0.58, -u * 0.85)
    ..lineTo(u * 0.85, 0)
    ..lineTo(-u * 0.58, u * 0.85)
    ..close();

  static Path _shield(double u) => Path()
    ..moveTo(0, -u)
    ..lineTo(u * 0.78, -u * 0.62)
    ..lineTo(u * 0.78, u * 0.12)
    ..quadraticBezierTo(u * 0.78, u * 0.74, 0, u)
    ..quadraticBezierTo(-u * 0.78, u * 0.74, -u * 0.78, u * 0.12)
    ..lineTo(-u * 0.78, -u * 0.62)
    ..close();

  /// Three overlapping discs on a flat base.
  static Path _cloud(double u) => Path()
    ..addOval(
      Rect.fromCircle(center: Offset(-u * 0.5, u * 0.06), radius: u * 0.44),
    )
    ..addOval(
      Rect.fromCircle(center: Offset(u * 0.05, -u * 0.24), radius: u * 0.6),
    )
    ..addOval(
      Rect.fromCircle(center: Offset(u * 0.62, u * 0.1), radius: u * 0.4),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-u * 0.94, u * 0.02, u * 1.96, u * 0.48),
        Radius.circular(u * 0.24),
      ),
    );

  /// A map pin with its eye cut out.
  ///
  /// A real difference rather than a disc of the base colour punched over the
  /// top: the ground under a pin is not always flat — a panorama slides the
  /// composition sideways — and a punch that assumes it is shows as a hole in
  /// the wrong colour the moment anything is drawn behind.
  static Path _pin(double u) => Path.combine(
    PathOperation.difference,
    Path()
      ..moveTo(0, u)
      ..cubicTo(-u * 0.95, -u * 0.22, -u * 0.72, -u, 0, -u)
      ..cubicTo(u * 0.72, -u, u * 0.95, -u * 0.22, 0, u)
      ..close(),
    Path()..addOval(
      Rect.fromCircle(center: Offset(0, -u * 0.36), radius: u * 0.26),
    ),
  );

  static Path _star(double u) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? u : u * 0.42;
      final point = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static Path _bolt(double u) => Path()
    ..moveTo(u * 0.28, -u)
    ..lineTo(-u * 0.62, u * 0.14)
    ..lineTo(-u * 0.06, u * 0.14)
    ..lineTo(-u * 0.28, u)
    ..lineTo(u * 0.62, -u * 0.14)
    ..lineTo(u * 0.06, -u * 0.14)
    ..close();

  /// A camera iris: a ring cut by six blades.
  static Path _aperture(double u) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: u * 0.85));
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      path
        ..moveTo(math.cos(angle) * u * 0.85, math.sin(angle) * u * 0.85)
        ..lineTo(
          math.cos(angle + 1.05) * u * 0.28,
          math.sin(angle + 1.05) * u * 0.28,
        );
    }
    return path;
  }

  /// A nucleus inside two tilted rings.
  static Path _orbit(double u) {
    final ring = Path()
      ..addOval(
        Rect.fromCenter(center: Offset.zero, width: u * 2, height: u * 0.82),
      );
    return Path()
      ..addPath(ring, Offset.zero, matrix4: Matrix4.rotationZ(0.6).storage)
      ..addPath(ring, Offset.zero, matrix4: Matrix4.rotationZ(-0.6).storage)
      ..moveTo(0, 0)
      ..lineTo(0, u * 0.01);
  }

  static Path _bell(double u) => Path()
    ..moveTo(-u * 0.75, u * 0.48)
    ..quadraticBezierTo(-u * 0.55, u * 0.4, -u * 0.55, -u * 0.12)
    ..quadraticBezierTo(-u * 0.55, -u * 0.85, 0, -u * 0.85)
    ..quadraticBezierTo(u * 0.55, -u * 0.85, u * 0.55, -u * 0.12)
    ..quadraticBezierTo(u * 0.55, u * 0.4, u * 0.75, u * 0.48)
    ..close()
    ..addOval(Rect.fromCircle(center: Offset(0, u * 0.7), radius: u * 0.21));

  /// A ladybird from above: round shell, small head, six short legs.
  ///
  /// The shell is deliberately round rather than the long oval a real beetle
  /// has — an elongated body with legs on it reads as a bird at preset size,
  /// which is what the first attempt at this looked like.
  static Path _bug(double u) {
    final path = Path();

    // Legs first, so the shell covers where they meet the body.
    for (var i = 0; i < 3; i++) {
      final angle = -0.75 + i * 0.75;
      for (final side in const [-1.0, 1.0]) {
        path.addPath(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(u * 0.45, -u * 0.06, u * 0.62, u * 0.12),
              Radius.circular(u * 0.06),
            ),
          ),
          Offset.zero,
          matrix4:
              (Matrix4.identity()
                    ..scaleByDouble(side, 1.0, 1.0, 1.0)
                    ..rotateZ(angle))
                  .storage,
        );
      }
    }

    return path
      ..addOval(
        Rect.fromCenter(
          center: Offset(0, u * 0.16),
          width: u * 1.32,
          height: u * 1.42,
        ),
      )
      ..addOval(
        Rect.fromCenter(
          center: Offset(0, -u * 0.72),
          width: u * 0.7,
          height: u * 0.52,
        ),
      )
      // Antennae.
      ..addPath(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.08, -u * 1.22, u * 0.4, u * 0.11),
            Radius.circular(u * 0.055),
          ),
        ),
        Offset.zero,
        matrix4: (Matrix4.identity()..rotateZ(-0.5)).storage,
      )
      ..addPath(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.08, -u * 1.22, u * 0.4, u * 0.11),
            Radius.circular(u * 0.055),
          ),
        ),
        Offset.zero,
        matrix4:
            (Matrix4.identity()
                  ..scaleByDouble(-1.0, 1.0, 1.0, 1.0)
                  ..rotateZ(-0.5))
                .storage,
      );
  }

  /// The at sign: an open outer ring around a closed inner one, with the tail
  /// curling off to the right.
  static Path _at(double u) => Path()
    ..addArc(
      Rect.fromCircle(center: Offset.zero, radius: u * 0.9),
      -math.pi * 0.12,
      math.pi * 1.68,
    )
    ..addOval(
      Rect.fromCircle(center: Offset(-u * 0.06, u * 0.02), radius: u * 0.33),
    )
    ..moveTo(u * 0.27, u * 0.02)
    ..lineTo(u * 0.27, u * 0.3)
    ..quadraticBezierTo(u * 0.32, u * 0.62, u * 0.76, u * 0.56);

  /// The hash sign: two horizontals crossed by two slanted uprights.
  static Path _hash(double u) {
    final path = Path();
    for (final y in [-u * 0.46, u * 0.14]) {
      path.addRect(Rect.fromLTWH(-u * 0.92, y, u * 1.84, u * 0.2));
    }
    for (final x in [-u * 0.38, u * 0.16]) {
      path.addPath(
        Path()..addRect(Rect.fromLTWH(x, -u * 0.92, u * 0.2, u * 1.84)),
        Offset.zero,
        // A shear rather than a rotation: the uprights of a hash lean without
        // their ends going out of level.
        matrix4: (Matrix4.identity()..setEntry(0, 1, -0.2)).storage,
      );
    }
    return path;
  }

  // ---------------------------------------------------------------------------
  // Second wave of atmospherics — minimal variants of the families that worked
  // ---------------------------------------------------------------------------

  /// Concentric soft halos around one origin.
  ///
  /// Each ring is a transparent → colour → transparent radial band rather than
  /// a stroked circle, so the structure is legible without a hard edge
  /// anywhere. That is the whole difference from [_rings]: same geometry, and
  /// the falloff is what turns a target into a glow.
  void _aura(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final longest = rect.longestSide;
    final origin = Offset(
      rect.left + rect.width * (0.3 + random.nextDouble() * 0.4),
      rect.top + rect.height * (0.28 + random.nextDouble() * 0.44),
    );
    final rings = (5 * scale).round().clamp(3, 9);
    final stops = math.max(1, spec.colors.length - 1);

    for (var i = rings; i >= 1; i--) {
      final radius = longest * 0.17 * i * scale;
      final color = spec.colorAt(1 + i % stops);
      final area = Rect.fromCircle(center: origin, radius: radius);
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.28 * intensity),
              color.withValues(alpha: 0),
            ],
            stops: const [0.52, 0.8, 1.0],
          ).createShader(area),
      );
    }

    // The core the halos belong to.
    final core = Rect.fromCircle(center: origin, radius: longest * 0.2 * scale);
    canvas.drawCircle(
      origin,
      longest * 0.2 * scale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            spec.colorAt(3).withValues(alpha: 0.55 * intensity),
            spec.colorAt(3).withValues(alpha: 0),
          ],
        ).createShader(core),
    );
  }

  /// Cracks spreading from an impact point, with the facets between them
  /// catching a little light.
  ///
  /// The geometry is one polar mesh: spokes at jittered angles, rings at
  /// growing radii, every vertex nudged. Drawing the cracks *along* that mesh
  /// rather than as free lines is what makes them look like one break instead
  /// of a pile of scratches — every crack meets another at a vertex.
  void _broken(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final longest = rect.longestSide;
    final origin = Offset(
      rect.left + rect.width * (0.25 + random.nextDouble() * 0.5),
      rect.top + rect.height * (0.25 + random.nextDouble() * 0.5),
    );
    final spokes = (11 * scale).round().clamp(7, 20);
    const rings = 5;

    final mesh = <List<Offset>>[];
    for (var r = 0; r < rings; r++) {
      // Squared growth, so the shards near the impact stay small and the ones
      // at the edge run long — which is how glass actually breaks.
      final t = (r + 1) / rings;
      final radius = longest * 0.9 * t * t * scale;
      mesh.add([
        for (var i = 0; i < spokes; i++)
          origin +
              Offset(
                    math.cos(
                      i / spokes * math.pi * 2 + random.nextDouble() * 0.12,
                    ),
                    math.sin(
                      i / spokes * math.pi * 2 + random.nextDouble() * 0.12,
                    ),
                  ) *
                  (radius * (0.86 + random.nextDouble() * 0.28)),
      ]);
    }

    // A few lit facets, so the break has a surface rather than being wireframe.
    final facet = Paint();
    for (var r = 0; r < rings - 1; r++) {
      for (var i = 0; i < spokes; i++) {
        if (random.nextDouble() > 0.42) continue;
        final j = (i + 1) % spokes;
        facet.color = spec
            .colorAt(1 + (r + i) % math.max(1, spec.colors.length - 1))
            .withValues(alpha: (0.16 * intensity).clamp(0.0, 1.0));
        canvas.drawPath(
          Path()
            ..moveTo(mesh[r][i].dx, mesh[r][i].dy)
            ..lineTo(mesh[r][j].dx, mesh[r][j].dy)
            ..lineTo(mesh[r + 1][j].dx, mesh[r + 1][j].dy)
            ..lineTo(mesh[r + 1][i].dx, mesh[r + 1][i].dy)
            ..close(),
          facet,
        );
      }
    }

    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(longest * 0.0025, 0.6)
      ..strokeCap = StrokeCap.round
      ..color = spec.colorAt(3).withValues(alpha: 0.6 * intensity);

    for (var i = 0; i < spokes; i++) {
      final path = Path()..moveTo(origin.dx, origin.dy);
      for (var r = 0; r < rings; r++) {
        path.lineTo(mesh[r][i].dx, mesh[r][i].dy);
      }
      canvas.drawPath(path, crack);
    }
    // Only the inner rings are joined up: a complete outer ring would read as a
    // circle drawn on top of the break rather than as part of it.
    for (var r = 0; r < rings - 1; r++) {
      final path = Path()..moveTo(mesh[r][0].dx, mesh[r][0].dy);
      for (var i = 1; i <= spokes; i++) {
        final point = mesh[r][i % spokes];
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, crack);
    }
  }

  /// A jittered triangular tessellation shaded along one axis — the low-poly
  /// wallpaper that shipped on a generation of Android handsets.
  ///
  /// The look does not come from the triangles, it comes from the shading:
  /// every facet takes a flat colour sampled from one diagonal ramp across the
  /// whole canvas, plus a small lightness jitter. Colour the facets
  /// independently and it is confetti; colour them from a shared ramp and the
  /// canvas reads as one lit surface that happens to be faceted.
  void _facets(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final columns = (7 / scale).round().clamp(3, 16);
    final stepX = rect.width / columns;
    final rows = math.max(2, (rect.height / stepX).ceil());
    final stepY = rect.height / rows;

    // One vertex grid, jittered, with a margin of one cell so the edge facets
    // are whole triangles rather than slivers.
    final points = <List<Offset>>[
      for (var r = -1; r <= rows + 1; r++)
        [
          for (var c = -1; c <= columns + 1; c++)
            Offset(
              rect.left + c * stepX + (random.nextDouble() - 0.5) * stepX * 0.6,
              rect.top + r * stepY + (random.nextDouble() - 0.5) * stepY * 0.6,
            ),
        ],
    ];

    final paint = Paint();
    void facet(Offset a, Offset b, Offset c) {
      final centroid = (a + b + c) / 3;
      // Position along the diagonal, which is what the ramp is sampled by.
      final t =
          (((centroid.dx - rect.left) / rect.width) +
              ((centroid.dy - rect.top) / rect.height)) /
          2;
      final shade = t.clamp(0.0, 1.0);
      final ramp = shade < 0.5
          ? Color.lerp(spec.colorAt(1), spec.colorAt(2), shade * 2)!
          : Color.lerp(spec.colorAt(2), spec.colorAt(3), (shade - 0.5) * 2)!;
      paint.color = Color.lerp(
        ramp,
        random.nextBool() ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        random.nextDouble() * 0.12,
      )!.withValues(alpha: intensity);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        paint,
      );
    }

    for (var r = 0; r < points.length - 1; r++) {
      for (var c = 0; c < points[r].length - 1; c++) {
        // The diagonal alternates, so the tessellation does not read as a grid
        // of identical parallelograms.
        if ((r + c).isEven) {
          facet(points[r][c], points[r][c + 1], points[r + 1][c]);
          facet(points[r][c + 1], points[r + 1][c + 1], points[r + 1][c]);
        } else {
          facet(points[r][c], points[r][c + 1], points[r + 1][c + 1]);
          facet(points[r][c], points[r + 1][c + 1], points[r + 1][c]);
        }
      }
    }
  }

  /// Two or three big smooth crests, filled as flat silhouettes.
  ///
  /// Deliberately fewer and larger than [_waves]: that one stacks translucent
  /// sine bands and reads as texture, this reads as shape. The curve is a
  /// midpoint-smoothed polyline through seeded heights, so the crests are
  /// irregular without a single sine's obvious repeat.
  void _crests(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
    _Crest where,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final layers = where == _Crest.full ? 4 : 3;
    final lobes = math.max(2, (3 / scale).round());

    for (var layer = 0; layer < layers; layer++) {
      final fromTop = switch (where) {
        _Crest.top => true,
        _Crest.bottom => false,
        // Alternating in the full case is what makes the crests interlock
        // rather than sit in two unrelated stacks.
        _Crest.full => layer.isOdd,
      };

      // Each layer reaches *less* far than the one before, so the stack paints
      // back to front: the palest, deepest-reaching crest goes down first and
      // every later layer sits in front of it. Done the other way round — which
      // is how this first read — each layer covers its predecessor and only the
      // last one is really visible, so a three-layer stack looks like one band.
      final reach = switch (where) {
        _Crest.full => 0.62 - layer * 0.055,
        _ => 0.56 - layer * 0.13,
      };
      final amplitude = rect.height * 0.11 * scale * (1 - layer * 0.12);

      final heights = [
        for (var i = 0; i <= lobes; i++)
          rect.height * reach +
              (random.nextDouble() - 0.5) * amplitude * 2 * (fromTop ? -1 : 1),
      ];

      final path = Path();
      Offset at(int i) => Offset(
        rect.left + rect.width * i / lobes,
        fromTop ? rect.top + heights[i] : rect.bottom - heights[i],
      );

      final anchor = fromTop ? rect.top : rect.bottom;
      path
        ..moveTo(rect.left, anchor)
        ..lineTo(at(0).dx, at(0).dy);
      for (var i = 0; i < lobes; i++) {
        final current = at(i);
        final next = at(i + 1);
        // Control at the vertex, endpoint at the midpoint of the next span:
        // the standard smoothing that keeps the curve continuous through every
        // point without needing tangents.
        path.quadraticBezierTo(
          current.dx,
          current.dy,
          (current.dx + next.dx) / 2,
          (current.dy + next.dy) / 2,
        );
      }
      path
        ..lineTo(at(lobes).dx, at(lobes).dy)
        ..lineTo(rect.right, anchor)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = spec
              .colorAt(1 + layer % math.max(1, spec.colors.length - 1))
              .withValues(
                alpha: ((0.85 - layer * 0.14) * intensity).clamp(0.0, 1.0),
              ),
      );
    }
  }

  /// Three clean mountain silhouettes — [_terrain] cut back to its bones.
  ///
  /// Straight segments rather than curves, and a flat fill per layer with no
  /// sky ramp behind it. The whole point is the negative space.
  void _ridges(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    for (var layer = 0; layer < 3; layer++) {
      final baseline = rect.top + rect.height * (0.46 + layer * 0.16);
      final peaks = 2 + layer;
      final amplitude = rect.height * 0.2 * scale * (1 - layer * 0.22);

      final path = Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, baseline);
      for (var i = 0; i <= peaks * 2; i++) {
        final x = rect.left + rect.width * i / (peaks * 2);
        final y = i.isOdd
            ? baseline - amplitude * (0.55 + random.nextDouble() * 0.45)
            : baseline - amplitude * random.nextDouble() * 0.18;
        path.lineTo(x, y);
      }
      path
        ..lineTo(rect.right, rect.bottom)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = spec
              .colorAt(1 + layer)
              .withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
      );
    }
  }

  /// Soft rolling hills: low, wide and rounded, four layers deep.
  void _dunes(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    for (var layer = 0; layer < 4; layer++) {
      final baseline = rect.top + rect.height * (0.5 + layer * 0.12);
      final amplitude = rect.height * 0.09 * scale;
      final phase = random.nextDouble() * math.pi * 2;
      // A single low harmonic per layer, so a dune is one long swell rather
      // than a row of bumps.
      final frequency = 0.7 + random.nextDouble() * 0.5;

      final path = Path()..moveTo(rect.left, rect.bottom);
      const steps = 40;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        path.lineTo(
          rect.left + rect.width * t,
          baseline + math.sin(t * math.pi * frequency + phase) * amplitude,
        );
      }
      path
        ..lineTo(rect.right, rect.bottom)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = spec
              .colorAt(1 + layer % math.max(1, spec.colors.length - 1))
              .withValues(
                alpha: ((0.9 - layer * 0.08) * intensity).clamp(0.0, 1.0),
              ),
      );
    }
  }

  /// Parallel wavy bands filling the canvas — a cut-away through strata.
  ///
  /// A contour style, but an open one: [_topography] draws closed loops around
  /// a centre, this draws lines that leave by both edges. Band thickness varies
  /// so the section reads as deposited rather than ruled.
  void _strata(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    canvas.drawRect(rect, Paint()..color = spec.colorAt(0));

    final bands = (9 * scale).round().clamp(4, 22);
    final phase = random.nextDouble() * math.pi * 2;
    final stops = math.max(1, spec.colors.length - 1);

    // Boundaries first, then each band is the strip between two of them —
    // which is what guarantees no gap and no overlap however they wobble.
    double boundary(double t, double x) {
      final u = (x - rect.left) / rect.width;
      return rect.top +
          rect.height * t +
          rect.height *
              0.04 *
              scale *
              (math.sin(u * math.pi * 1.7 + phase + t * 5.5) +
                  0.45 * math.sin(u * math.pi * 3.3 + phase * 1.7 + t * 9));
    }

    for (var i = 0; i < bands; i++) {
      final top = i / bands;
      final bottom = (i + 1) / bands;
      final path = Path();
      const steps = 36;
      for (var s = 0; s <= steps; s++) {
        final x = rect.left + rect.width * s / steps;
        final y = boundary(top, x);
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (var s = steps; s >= 0; s--) {
        final x = rect.left + rect.width * s / steps;
        path.lineTo(x, boundary(bottom, x));
      }
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = spec
              .colorAt(1 + i % stops)
              .withValues(
                alpha: ((0.35 + (i % 3) * 0.22) * intensity).clamp(0.0, 1.0),
              ),
      );
    }
  }

  /// Contours around two centres — a weather map's high and its low.
  ///
  /// Two families of nested closed curves that run into each other. The
  /// crossings are the point: one centre is [_topography], two is a pressure
  /// chart, and the difference costs nothing but a second origin.
  void _isobars(
    Canvas canvas,
    Rect rect,
    math.Random random,
    double intensity,
    double scale,
  ) {
    _paintRamp(canvas, rect);

    final longest = rect.longestSide;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(rect.width * 0.0032, 0.6);

    for (var centre = 0; centre < 2; centre++) {
      final origin = Offset(
        rect.left + rect.width * (0.2 + random.nextDouble() * 0.6),
        rect.top +
            rect.height * (centre == 0 ? 0.18 : 0.62) +
            rect.height * random.nextDouble() * 0.2,
      );
      final step = longest / (11 / scale);
      final wobble = [
        random.nextDouble() * math.pi * 2,
        random.nextDouble() * math.pi * 2,
      ];
      final squash = 0.7 + random.nextDouble() * 0.5;

      for (var i = 1; i <= 7; i++) {
        final base = step * i;
        final path = Path();
        const steps = 64;
        for (var s = 0; s <= steps; s++) {
          final angle = s / steps * math.pi * 2;
          final radius =
              base *
              (1 +
                  0.12 * math.sin(angle * 2 + wobble[0]) +
                  0.07 * math.sin(angle * 4 + wobble[1]));
          final point =
              origin +
              Offset(
                math.cos(angle) * radius,
                math.sin(angle) * radius * squash,
              );
          if (s == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        paint.color = spec
            .colorAt(2 + centre)
            .withValues(alpha: (0.5 * intensity).clamp(0.0, 1.0));
        canvas.drawPath(path..close(), paint);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// The two-stop vertical ramp the textured styles sit on.
  void _paintRamp(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [spec.colorAt(0), spec.colorAt(1)],
        ).createShader(rect),
    );
  }

  /// Runs [draw] with the canvas rotated about the centre of [rect], handing it
  /// bounds large enough that the rotated motif still covers every corner.
  void _rotated(Canvas canvas, Rect rect, void Function(Rect bounds) draw) {
    final center = rect.center;
    // A rotated square only covers the original once it is sqrt(2) larger.
    final overscan = rect.longestSide * 0.75;
    final bounds = rect.inflate(overscan);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(spec.angle * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);
    draw(bounds);
    canvas.restore();
  }

  /// Calls [draw] once per lattice point of a [step]-spaced grid, rotated by
  /// the spec's angle and overscanned to cover the corners.
  void _tiled(
    Canvas canvas,
    Rect rect,
    double step,
    void Function(Offset point) draw,
  ) {
    if (step <= 0) return;
    _rotated(canvas, rect, (bounds) {
      for (var y = bounds.top; y <= bounds.bottom; y += step) {
        for (var x = bounds.left; x <= bounds.right; x += step) {
          draw(Offset(x, y));
        }
      }
    });
  }

  /// [_tiled] with independent axes, row indices, and an optional half-step
  /// row offset.
  ///
  /// The indices are the point of it: a checkerboard, an argyle and a triangle
  /// tessellation are all the same walk with a different rule for which colour
  /// a cell takes, and [stagger] turns the square lattice into the hexagonal
  /// one the honeycomb, scale and cube styles need.
  void _lattice(
    Canvas canvas,
    Rect rect,
    double stepX,
    double stepY,
    void Function(Offset point, int column, int row) draw, {
    bool stagger = false,
  }) {
    if (stepX <= 0 || stepY <= 0) return;
    _rotated(canvas, rect, (bounds) {
      final columns = (bounds.width / stepX).ceil();
      final rows = (bounds.height / stepY).ceil();
      for (var row = 0; row <= rows; row++) {
        final offsetX = stagger && row.isOdd ? stepX / 2 : 0.0;
        for (var column = 0; column <= columns; column++) {
          draw(
            Offset(
              bounds.left + column * stepX + offsetX,
              bounds.top + row * stepY,
            ),
            column,
            row,
          );
        }
      }
    });
  }

  /// The six corners of a pointy-top hexagon, starting at the top and going
  /// clockwise.
  static List<Offset> _hexagonPoints(Offset center, double radius) => [
    for (var i = 0; i < 6; i++)
      center +
          Offset(
            math.cos((i * 60 - 90) * math.pi / 180) * radius,
            math.sin((i * 60 - 90) * math.pi / 180) * radius,
          ),
  ];

  static Path _hexagon(Offset center, double radius) {
    final points = _hexagonPoints(center, radius);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(PatternPainter old) =>
      old.spec.style != spec.style ||
      old.spec.seed != spec.seed ||
      old.spec.scale != spec.scale ||
      old.spec.angle != spec.angle ||
      old.spec.intensity != spec.intensity ||
      old.spec.slices != spec.slices ||
      old.spec.slice != spec.slice ||
      !listEquals(old.spec.colors, spec.colors);
}

/// The colour sets the presets draw from.
///
/// Each list runs base → mid → accent → highlight, which is the order every
/// painter reads its stops in. What "mid" and "accent" have to *do*, though,
/// depends on the style: the textured styles lay their motif over a base→mid
/// ramp and paint it in stop 2, while the flat styles fill with stop 0 and
/// paint everything else on top. A palette whose stop 2 sits a shade off its
/// ramp is invisible under `grid` and perfectly good under `checkers`.
///
/// So these are tuned per preset rather than shared between them, and each is
/// used exactly once. That is the whole fix for a gallery of look-alikes: two
/// presets that share four colours are two presets that share a thumbnail, and
/// no amount of style variety hides it at 44dp wide.
///
/// These are the user's *content*, never theme tokens: an export made in dark
/// mode has to match one made in light.
/// The colour sets the presets draw from.
///
/// Each list runs base → mid → accent → highlight, which is the order every
/// painter reads its stops in. What "mid" and "accent" have to *do*, though,
/// depends on the style: the textured styles lay their motif over a base→mid
/// ramp and paint it in stop 2, the flat styles fill with stop 0 and paint
/// everything else on top, and the icon styles cycle stops 1 upward one glyph
/// at a time. A palette whose stop 2 sits a shade off its ramp is invisible
/// under `grid` and perfectly good under `checkers`.
///
/// So these are tuned per preset rather than shared between them, and each is
/// used exactly once. That is the whole fix for a gallery of look-alikes: two
/// presets that share four colours share a thumbnail, and no amount of style
/// variety hides it at 44dp wide.
///
/// These are the user's *content*, never theme tokens: an export made in dark
/// mode has to match one made in light.
abstract final class _Palettes {
  // ---------------------------------------------------------------------------
  // Atmospheric — soft fields, sweeps and scatters.
  //
  // Grounds are tinted rather than neutral: a near-black with a hue in it reads
  // as lit, a pure #0A0A0A reads as switched off.
  // ---------------------------------------------------------------------------

  /// mesh — indigo night under a cyan edge.
  static const indigoDrift = [
    Color(0xFF070B24),
    Color(0xFF1B1F55),
    Color(0xFF4F46E5),
    Color(0xFF22D3EE),
  ];

  /// blobs — deep water, teal accent.
  static const deepLagoon = [
    Color(0xFF021018),
    Color(0xFF0A3B4A),
    Color(0xFF0E9BB8),
    Color(0xFF34E3D0),
  ];

  /// aurora — the green-over-blue northern light.
  static const polarNight = [
    Color(0xFF040A16),
    Color(0xFF0D2A4A),
    Color(0xFF3EE0B0),
    Color(0xFF8AF0FF),
  ];

  /// bokeh — warm city lights out of focus.
  static const nightMarket = [
    Color(0xFF0E0616),
    Color(0xFF2A0F35),
    Color(0xFFFF5FA2),
    Color(0xFFFFD166),
  ];

  /// spotlight — a red pool with the corners pulled down hard.
  static const oxblood = [
    Color(0xFF170406),
    Color(0xFFE23B4B),
    Color(0xFF35060C),
    Color(0xFFFF9AA2),
  ];

  /// starfield — a blue nebula and white stars.
  static const deepSpace = [
    Color(0xFF04060F),
    Color(0xFF2B3FA8),
    Color(0xFF7C3AED),
    Color(0xFFFFFFFF),
  ];

  /// prism — cut glass. The shards paint at barely a quarter alpha,
  /// so the stops run well clear of the ramp or the style is a flat rectangle.
  static const duskGlass = [
    Color(0xFF0D0B2B),
    Color(0xFF241F63),
    Color(0xFF7C6BFF),
    Color(0xFF4BF0D2),
  ];

  /// waves — cold sea under a steel sky.
  static const tidalSteel = [
    Color(0xFF9FDCEC),
    Color(0xFF06263A),
    Color(0xFF35A7C8),
    Color(0xFF0B3B57),
  ];

  /// terrain — blue-hour ridges.
  static const royalRidge = [
    Color(0xFFA9C2FF),
    Color(0xFF3E56C8),
    Color(0xFF16205C),
    Color(0xFF0A0C2E),
  ];

  /// rays — a hot sun low in the frame. All three beam stops are
  /// bright: they paint at a fifth alpha over a near-black ground, so a dim one
  /// is a wedge of mud rather than a wedge of light.
  static const solarEmber = [
    Color(0xFF2A1006),
    Color(0xFFC24A10),
    Color(0xFFF2831F),
    Color(0xFFFFD37A),
  ];

  /// sunburst — full-strength retro wedges.
  static const citrusWheel = [
    Color(0xFFFFF0D6),
    Color(0xFFFF7A2F),
    Color(0xFFE23A2E),
    Color(0xFFFFC93C),
  ];

  /// swirl — arms of hot pink and gold.
  static const berrySpin = [
    Color(0xFF1B0B2E),
    Color(0xFF3E1470),
    Color(0xFFFF3D8A),
    Color(0xFFFFD84D),
  ];

  /// rings — copper ripples on a dark ground.
  static const copperEcho = [
    Color(0xFF170D08),
    Color(0xFF35190B),
    Color(0xFFD2792B),
    Color(0xFFF6C88A),
  ];

  /// topography — contour lines on a dark map, the ramp lifted just
  /// enough to give the lines something to sit on.
  static const mossMap = [
    Color(0xFF0F2412),
    Color(0xFF224A28),
    Color(0xFF8BD94E),
    Color(0xFFD6F58E),
  ];

  /// bubbles — outlined circles on ice.
  static const aquaFoam = [
    Color(0xFFEEFBFF),
    Color(0xFFC6EEF8),
    Color(0xFF1E90B4),
    Color(0xFF0A5C78),
  ];

  // ---------------------------------------------------------------------------
  // Motif — the repeating lattices.
  //
  // These live or die on the step between the base→mid ramp and the motif stop.
  // Every one below is a deliberate tonal jump, not a neighbouring shade.
  // ---------------------------------------------------------------------------

  /// dots — violet on a lilac field, the ramp carrying real colour
  /// rather than sitting a hair off white.
  static const lilacDot = [
    Color(0xFFEDE6FF),
    Color(0xFFD5C7FA),
    Color(0xFF4A2FA0),
    Color(0xFF2A1866),
  ];

  /// halftone — the loud one.
  static const neonHalf = [
    Color(0xFF06060F),
    Color(0xFF19003A),
    Color(0xFFFF2D95),
    Color(0xFF00E5FF),
  ];

  /// grid — cyan ruling on a deep blue field.
  static const blueprint = [
    Color(0xFF071B2E),
    Color(0xFF0B2B47),
    Color(0xFF6FD4FF),
    Color(0xFFB3E5FC),
  ];

  /// crosshatch — technical pen on cool paper.
  static const inkHatch = [
    Color(0xFFF4F6FA),
    Color(0xFFE4E9F2),
    Color(0xFF33445F),
    Color(0xFF5E7391),
  ];

  /// stripes — bright bands on bottle green.
  static const forestStripe = [
    Color(0xFF06231A),
    Color(0xFF14C98A),
    Color(0xFF9BF6D8),
    Color(0xFF03150F),
  ];

  /// plaid — a wine tartan, its darks made by the overlaps.
  static const wineTartan = [
    Color(0xFF1A0810),
    Color(0xFFB02450),
    Color(0xFFE0567A),
    Color(0xFFFFC48A),
  ];

  /// checkers — near-black against near-white, the highest-contrast
  /// pair here.
  static const monoCheck = [
    Color(0xFF101215),
    Color(0xFFE9EDF2),
    Color(0xFF6B7280),
    Color(0xFFFFFFFF),
  ];

  /// diamonds — copper argyle.
  static const copperArgyle = [
    Color(0xFF1A0F0A),
    Color(0xFFDB6A1B),
    Color(0xFFF7C98A),
    Color(0xFF521F06),
  ];

  /// triangles — a teal tessellation, three tones of one hue.
  static const tealFacet = [
    Color(0xFF04262B),
    Color(0xFF2FD3C0),
    Color(0xFF0E7C7B),
    Color(0xFFA9F5E4),
  ];

  /// hexagons — a bright honeycomb over navy.
  static const royalComb = [
    Color(0xFF0A0F2E),
    Color(0xFF16205C),
    Color(0xFF7E9CFF),
    Color(0xFFC3D2FF),
  ];

  /// isometric — cubes lit from one side: bright top, mid right, dark
  /// left.
  static const plumStack = [
    Color(0xFF150A22),
    Color(0xFFB57BFF),
    Color(0xFF7A34D6),
    Color(0xFF3B1273),
  ];

  /// scales — green tiles on a pale wash.
  static const seafoamScale = [
    Color(0xFFF0FBF6),
    Color(0xFFD5F2E4),
    Color(0xFF1B9E72),
    Color(0xFF0A6349),
  ];

  /// zigzag — chevrons in pink and gold.
  static const berryChevron = [
    Color(0xFF1C0B33),
    Color(0xFFFF4D9D),
    Color(0xFFFFD166),
    Color(0xFF3A1268),
  ];

  /// crosses — an emerald sprinkle on mint.
  static const mintCross = [
    Color(0xFFF2FFFB),
    Color(0xFFDDF7EE),
    Color(0xFF0E9E6E),
    Color(0xFF056046),
  ];

  /// circuit — traces and pads on a board-green ground.
  static const boardGreen = [
    Color(0xFF04120C),
    Color(0xFF17C964),
    Color(0xFF7DF3C0),
    Color(0xFF0A2B1A),
  ];

  /// confetti — capsules on a warm white.
  static const partyPop = [
    Color(0xFFFFEADB),
    Color(0xFFFF3D6E),
    Color(0xFF12B76A),
    Color(0xFF7C3AED),
  ];

  // ---------------------------------------------------------------------------
  // Store panel.
  //
  // One saturated hue floods the canvas (poster), a near-black ground carries a
  // bloom (stage), or the poster ramp is swept by light (beams). Stop 1 is the
  // ink the ramp sinks toward; stop 3 tints the ghost shapes.
  // ---------------------------------------------------------------------------

  /// poster.
  static const cobaltPop = [
    Color(0xFF2645D4),
    Color(0xFF0A0E22),
    Color(0xFFFFD84D),
    Color(0xFFFFFFFF),
  ];

  /// stage.
  static const stageViolet = [
    Color(0xFF17102E),
    Color(0xFF4632A0),
    Color(0xFFA855F7),
    Color(0xFFF0ABFC),
  ];

  /// beams.
  static const beamAmber = [
    Color(0xFFD99A0B),
    Color(0xFF241503),
    Color(0xFFFFF0B8),
    Color(0xFFFFFCEC),
  ];

  // ---------------------------------------------------------------------------
  // Icon motifs — a scattered field of one symbol.
  //
  // Stop 0 is the ground and stops 1 upward colour the glyphs, cycled per glyph,
  // so every stop after the first has to read against the ground on its own.
  // That is the one rule these break most easily: an ink stop borrowed from a
  // ramp palette is a glyph nobody can see.
  // ---------------------------------------------------------------------------

  /// notes.
  static const noteViolet = [
    Color(0xFF0B0714),
    Color(0xFF3B0764),
    Color(0xFF8B2FE8),
    Color(0xFFF472D0),
  ];

  /// hearts.
  static const heartCrimson = [
    Color(0xFFD92B3A),
    Color(0xFF1A0606),
    Color(0xFFFFD84D),
    Color(0xFFFFFFFF),
  ];

  /// wifi.
  static const signalInk = [
    Color(0xFF101828),
    Color(0xFF38BDF8),
    Color(0xFF7DD3FC),
    Color(0xFFFFFFFF),
  ];

  /// sparkles.
  static const sparkRose = [
    Color(0xFF26091A),
    Color(0xFF8A1741),
    Color(0xFFFB4E7E),
    Color(0xFFFFC2D4),
  ];

  /// clouds.
  static const cloudSky = [
    Color(0xFFF1FAFF),
    Color(0xFF9FD8F5),
    Color(0xFF74CDF5),
    Color(0xFF2E9FDD),
  ];

  /// stars.
  static const starEmber = [
    Color(0xFF1C0D05),
    Color(0xFF6E3611),
    Color(0xFFF97316),
    Color(0xFFFFD8A8),
  ];

  // ---------------------------------------------------------------------------
  // Second wave — the icon glyphs and minimal atmospherics added after the
  // first pass, plus the panorama's shared set.
  // ---------------------------------------------------------------------------

  /// aura — halos over near-black.
  static const auraViolet = [
    Color(0xFF0A0618),
    Color(0xFF4C1D95),
    Color(0xFFA855F7),
    Color(0xFFF0ABFC),
  ];

  /// broken — cold light through the cracks.
  static const brokenIce = [
    Color(0xFF04121F),
    Color(0xFF0E4C6B),
    Color(0xFF38BDF8),
    Color(0xFFE0F2FE),
  ];

  /// facets — the ramp the low-poly surface is lit by, running violet
  /// through magenta to gold.
  static const facetSunset = [
    Color(0xFF1A0A20),
    Color(0xFF6D28D9),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
  ];

  /// crestTop — aqua crests on ice.
  static const crestAqua = [
    Color(0xFFEAF8FC),
    Color(0xFF0E7490),
    Color(0xFF155E75),
    Color(0xFF083344),
  ];

  /// crestBottom — plum crests on near-black.
  static const crestPlum = [
    Color(0xFF160A28),
    Color(0xFF7C3AED),
    Color(0xFFA855F7),
    Color(0xFFD8B4FE),
  ];

  /// crestFull — interlocking coral crests on blush.
  static const crestCoral = [
    Color(0xFFFFF1EA),
    Color(0xFFFB7185),
    Color(0xFFF97316),
    Color(0xFF7C2D12),
  ];

  /// ridges — mountains flattened into three tones against a dusk sky.
  static const ridgeDusk = [
    Color(0xFFF5D9B0),
    Color(0xFFE07A5F),
    Color(0xFF8C4A3F),
    Color(0xFF3D2B2B),
  ];

  /// dunes — rolling sand.
  static const duneRose = [
    Color(0xFFFFE8D6),
    Color(0xFFF4A261),
    Color(0xFFE76F51),
    Color(0xFF9C4223),
  ];

  /// strata — a section through warm rock.
  static const strataEarth = [
    Color(0xFF2A1A12),
    Color(0xFFB45309),
    Color(0xFFD97706),
    Color(0xFFFCD34D),
  ];

  /// isobars — a parchment ramp for the map, then two contour colours for the
  /// high and the low. Warm rather than the obvious blue-white: a cool pale
  /// ground under thin lines is [inkHatch] with different lines on it.
  static const isobarSea = [
    Color(0xFFFBF4E6),
    Color(0xFFF0E2C6),
    Color(0xFF0B6E86),
    Color(0xFF9A3412),
  ];

  /// the mesh panorama.
  static const panoMesh = [
    Color(0xFF090D26),
    Color(0xFF3B3AC9),
    Color(0xFFB43FD6),
    Color(0xFF34E0E8),
  ];

  /// the aura panorama.
  static const panoAura = [
    Color(0xFF0B0618),
    Color(0xFF4C1D95),
    Color(0xFFD946EF),
    Color(0xFFFDE68A),
  ];

  /// the terrain panorama.
  static const panoTerrain = [
    Color(0xFFBFD9F2),
    Color(0xFF4C74C9),
    Color(0xFF1D3170),
    Color(0xFF090F2E),
  ];

  /// the waves panorama.
  static const panoWaves = [
    Color(0xFFA7E8F0),
    Color(0xFF073B52),
    Color(0xFF2C93B5),
    Color(0xFF0A5A78),
  ];

  /// the crest panorama.
  static const panoCrest = [
    Color(0xFF120A2E),
    Color(0xFF6D28D9),
    Color(0xFF9B5CFF),
    Color(0xFFD8B4FE),
  ];

  /// the ridges panorama.
  static const panoRidge = [
    Color(0xFFF7CFA0),
    Color(0xFFDE6B4C),
    Color(0xFF8A3C3A),
    Color(0xFF34212B),
  ];

  /// the dunes panorama.
  static const panoDune = [
    Color(0xFFFFE3C7),
    Color(0xFFF0A868),
    Color(0xFFD2703F),
    Color(0xFF8C4224),
  ];

  /// the contours panorama.
  static const panoContour = [
    Color(0xFF08221C),
    Color(0xFF124C3C),
    Color(0xFF3FCF97),
    Color(0xFFB8F5D8),
  ];

  /// the strata panorama.
  static const panoStrata = [
    Color(0xFF2A1A12),
    Color(0xFFB45309),
    Color(0xFFE59B25),
    Color(0xFFFBD98A),
  ];
}

/// Curated starting points for the pattern picker.
///
/// Hand-tuned rather than generated: a random style with random colours is
/// usually ugly, and the point of the presets grid is that one tap gives
/// something a person would actually ship.
///
/// Three rules hold across the table, and they are what keep it a gallery
/// rather than a list:
///
/// * **One palette each.** No two presets draw from the same colour set. A
///   shared palette is the fastest way to two tiles that read alike whatever
///   their style, which is what the sameness test measures.
/// * **The motif has to survive the thumbnail.** Intensity is set per preset
///   against the palette it got, not left at a default — a hairline grid needs
///   a full 1.0 where a checkerboard needs half that.
/// * **Unique seeds.** The grid marks the showing preset by matching its seed,
///   so a duplicate would light two tiles and make neither selectable.
///
/// Ordered in three bands — atmospheric, motif, store-panel — so the grid
/// scrolls through related looks together instead of alternating between a
/// soft gradient and a checkerboard.
abstract final class PatternPresets {
  static const List<PatternBackground> all = <PatternBackground>[
    // --- Atmospheric ---------------------------------------------------
    //
    // Soft fields, sweeps and silhouettes.
    PatternBackground(
      style: PatternStyle.mesh,
      colors: _Palettes.indigoDrift,
      seed: 1,
    ),
    PatternBackground(
      style: PatternStyle.blobs,
      colors: _Palettes.deepLagoon,
      seed: 5,
    ),
    PatternBackground(
      style: PatternStyle.aurora,
      colors: _Palettes.polarNight,
      seed: 8,
      scale: 1.2,
    ),
    PatternBackground(
      style: PatternStyle.bokeh,
      colors: _Palettes.nightMarket,
      seed: 11,
      scale: 1.2,
    ),
    PatternBackground(
      style: PatternStyle.spotlight,
      colors: _Palettes.oxblood,
      seed: 13,
    ),
    PatternBackground(
      style: PatternStyle.aura,
      colors: _Palettes.auraViolet,
      seed: 85,
    ),
    PatternBackground(
      style: PatternStyle.starfield,
      colors: _Palettes.deepSpace,
      seed: 26,
      scale: 1.4,
    ),
    PatternBackground(
      style: PatternStyle.prism,
      colors: _Palettes.duskGlass,
      seed: 25,
    ),
    PatternBackground(
      style: PatternStyle.facets,
      colors: _Palettes.facetSunset,
      seed: 86,
    ),
    PatternBackground(
      style: PatternStyle.broken,
      colors: _Palettes.brokenIce,
      seed: 87,
    ),
    PatternBackground(
      style: PatternStyle.waves,
      colors: _Palettes.tidalSteel,
      seed: 15,
    ),
    PatternBackground(
      style: PatternStyle.crestTop,
      colors: _Palettes.crestAqua,
      seed: 88,
    ),
    PatternBackground(
      style: PatternStyle.crestBottom,
      colors: _Palettes.crestPlum,
      seed: 89,
    ),
    PatternBackground(
      style: PatternStyle.crestFull,
      colors: _Palettes.crestCoral,
      seed: 90,
    ),
    PatternBackground(
      style: PatternStyle.terrain,
      colors: _Palettes.royalRidge,
      seed: 18,
    ),
    PatternBackground(
      style: PatternStyle.ridges,
      colors: _Palettes.ridgeDusk,
      seed: 91,
    ),
    PatternBackground(
      style: PatternStyle.dunes,
      colors: _Palettes.duneRose,
      seed: 92,
    ),
    PatternBackground(
      style: PatternStyle.rays,
      colors: _Palettes.solarEmber,
      seed: 20,
      scale: 1.2,
      angle: 12,
    ),
    PatternBackground(
      style: PatternStyle.sunburst,
      colors: _Palettes.citrusWheel,
      seed: 22,
      scale: 1.2,
    ),
    PatternBackground(
      style: PatternStyle.swirl,
      colors: _Palettes.berrySpin,
      seed: 24,
      scale: 1.3,
    ),
    PatternBackground(
      style: PatternStyle.rings,
      colors: _Palettes.copperEcho,
      seed: 27,
      intensity: 0.8,
    ),
    PatternBackground(
      style: PatternStyle.topography,
      colors: _Palettes.mossMap,
      seed: 29,
      scale: 1.3,
    ),
    PatternBackground(
      style: PatternStyle.isobars,
      colors: _Palettes.isobarSea,
      seed: 93,
    ),
    PatternBackground(
      style: PatternStyle.strata,
      colors: _Palettes.strataEarth,
      seed: 94,
    ),
    PatternBackground(
      style: PatternStyle.bubbles,
      colors: _Palettes.aquaFoam,
      seed: 30,
      scale: 0.8,
    ),
    // --- Motif ---------------------------------------------------------
    PatternBackground(
      style: PatternStyle.dots,
      colors: _Palettes.lilacDot,
      seed: 31,
      scale: 0.7,
    ),
    PatternBackground(
      style: PatternStyle.halftone,
      colors: _Palettes.neonHalf,
      seed: 33,
      scale: 1.2,
    ),
    PatternBackground(
      style: PatternStyle.grid,
      colors: _Palettes.blueprint,
      seed: 35,
      scale: 0.8,
    ),
    PatternBackground(
      style: PatternStyle.crosshatch,
      colors: _Palettes.inkHatch,
      seed: 37,
      scale: 1.4,
    ),
    PatternBackground(
      style: PatternStyle.stripes,
      colors: _Palettes.forestStripe,
      seed: 39,
      angle: 35,
      intensity: 0.85,
    ),
    PatternBackground(
      style: PatternStyle.plaid,
      colors: _Palettes.wineTartan,
      seed: 41,
      scale: 1.3,
    ),
    PatternBackground(
      style: PatternStyle.checkers,
      colors: _Palettes.monoCheck,
      seed: 42,
      scale: 0.7,
    ),
    PatternBackground(
      style: PatternStyle.diamonds,
      colors: _Palettes.copperArgyle,
      seed: 43,
      scale: 1.4,
    ),
    PatternBackground(
      style: PatternStyle.triangles,
      colors: _Palettes.tealFacet,
      seed: 44,
      scale: 1.1,
    ),
    PatternBackground(
      style: PatternStyle.hexagons,
      colors: _Palettes.royalComb,
      seed: 45,
      scale: 0.8,
    ),
    PatternBackground(
      style: PatternStyle.isometric,
      colors: _Palettes.plumStack,
      seed: 46,
      scale: 1.1,
    ),
    PatternBackground(
      style: PatternStyle.scales,
      colors: _Palettes.seafoamScale,
      seed: 47,
      scale: 1.5,
    ),
    PatternBackground(
      style: PatternStyle.zigzag,
      colors: _Palettes.berryChevron,
      seed: 48,
      scale: 0.8,
    ),
    PatternBackground(
      style: PatternStyle.crosses,
      colors: _Palettes.mintCross,
      seed: 49,
      scale: 0.7,
    ),
    PatternBackground(
      style: PatternStyle.circuit,
      colors: _Palettes.boardGreen,
      seed: 50,
      scale: 1.1,
    ),
    PatternBackground(
      style: PatternStyle.confetti,
      colors: _Palettes.partyPop,
      seed: 38,
    ),
    // --- Store panel ---------------------------------------------------
    //
    // The three looks a listing reaches for first. One entry each, like
    // everything else — the hue is the palette row's job, not the gallery's.
    PatternBackground(
      style: PatternStyle.poster,
      colors: _Palettes.cobaltPop,
      seed: 51,
    ),
    PatternBackground(
      style: PatternStyle.stage,
      colors: _Palettes.stageViolet,
      seed: 57,
    ),
    PatternBackground(
      style: PatternStyle.beams,
      colors: _Palettes.beamAmber,
      seed: 62,
    ),
    // --- Symbols -------------------------------------------------------
    //
    // One style, several starting points. These are the exception to the
    // one-entry-per-style rule the rest of the gallery keeps: what makes
    // two symbol presets different pictures is the glyphs, not the style,
    // so a single entry would hide nineteen of the twenty behind a panel.
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.noteViolet,
      seed: 67,
      symbols: [PatternSymbol.note],
      symbolCount: 30,
      symbolOpacity: 0.85,
    ),
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.heartCrimson,
      seed: 70,
      symbols: [PatternSymbol.heart],
      symbolCount: 26,
      symbolOpacity: 0.9,
    ),
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.signalInk,
      seed: 72,
      symbols: [PatternSymbol.wifi, PatternSymbol.network],
      symbolCount: 22,
      symbolOpacity: 0.8,
    ),
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.sparkRose,
      seed: 74,
      symbols: [PatternSymbol.sparkle, PatternSymbol.star],
      symbolCount: 34,
      symbolOpacity: 0.85,
    ),
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.cloudSky,
      seed: 78,
      symbols: [PatternSymbol.cloud],
      symbolCount: 18,
      symbolOpacity: 0.9,
    ),
    PatternBackground(
      style: PatternStyle.symbols,
      colors: _Palettes.starEmber,
      seed: 80,
      symbols: [
        PatternSymbol.bolt,
        PatternSymbol.aperture,
        PatternSymbol.orbit,
      ],
      symbolCount: 24,
      symbolOpacity: 0.8,
    ),
  ];

  /// One artwork spread across eight screens, in ten styles.
  ///
  /// Apply slice 0 to the first screen, slice 1 to the second and so on, and
  /// the listing carries a single backdrop running behind the whole set
  /// instead of eight unrelated ones. Every entry within a set is the same
  /// composition — same style, same palette, same seed — differing only in
  /// which eighth is showing, which is exactly why the seams line up.
  ///
  /// Deliberately not in [all]: a set is one preset that happens to need
  /// eight tiles to show, and dropping eighty of them into a gallery whose
  /// rule is one entry per style would read as the repeat that rule exists
  /// to prevent.
  ///
  /// Only styles that sweep are here. A checkerboard eight screens wide is
  /// still a checkerboard on every one of them, so tiling styles gain
  /// nothing from a panorama and are left out of it.
  static const List<List<PatternBackground>> panoramas =
      <List<PatternBackground>>[
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.mesh,
            colors: _Palettes.panoMesh,
            seed: 101,
            scale: 0.5,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.aura,
            colors: _Palettes.panoAura,
            seed: 102,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.terrain,
            colors: _Palettes.panoTerrain,
            seed: 103,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.waves,
            colors: _Palettes.panoWaves,
            seed: 104,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.crestBottom,
            colors: _Palettes.panoCrest,
            seed: 105,
            scale: 0.45,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.ridges,
            colors: _Palettes.panoRidge,
            seed: 106,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.dunes,
            colors: _Palettes.panoDune,
            seed: 107,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.topography,
            colors: _Palettes.panoContour,
            seed: 108,
            scale: 1.6,
            slices: 8,
            slice: 7,
          ),
        ],
        <PatternBackground>[
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 0,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 1,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 2,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 3,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 4,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 5,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 6,
          ),
          PatternBackground(
            style: PatternStyle.strata,
            colors: _Palettes.panoStrata,
            seed: 109,
            slices: 8,
            slice: 7,
          ),
        ],
      ];
}
