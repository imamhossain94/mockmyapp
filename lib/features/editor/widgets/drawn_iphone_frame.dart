// -----------------------------------------------------------------------------
// INTENTIONALLY TOKEN-FREE — this file renders USER CONTENT, not chrome.
//
// `DrawnIPhoneFrame` paints a device body that composites into the mockup
// itself, inside `SceneView`'s `_FrameLayer`, which the editor captures
// through a `RepaintBoundary`. Every colour here lands in the user's exported
// PNG, so it is a literal: an export made in dark mode has to be
// byte-identical to the same export made in light mode.
//
// Same exemption as `custom_device_frame.dart` and `programmatic_frame.dart`.
// -----------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/assets/drawn_iphones.dart';
import '../../../domain/models/screen_doc.dart' show FrameSide;

/// An iPhone, drawn from an [IPhoneSpec].
///
/// Laid out in the same box the traced artwork it replaces was, transparent
/// margin and all, and layered the way a phone is built: the keys under the
/// band, the metal band, the edge of the cover glass, the black display
/// border, then the screen and the camera in it.
///
/// The screenshot is clipped to the screen's own superellipse rather than to
/// the round corner the placement carries, so whatever radius a document
/// saved, nothing shows past the glass.
class DrawnIPhoneFrame extends StatelessWidget {
  const DrawnIPhoneFrame({
    super.key,
    required this.spec,
    required this.frameColor,
    required this.screenshot,
    required this.frameWidth,
    required this.frameHeight,
    this.showCutout = true,
    this.showKeys = true,
  });

  final IPhoneSpec spec;

  /// The finish: the metal band's own colour, which its highlights and shadows
  /// are worked out from.
  final Color frameColor;

  final Widget screenshot;
  final double frameWidth;
  final double frameHeight;

  /// Whether the Dynamic Island or the notch is drawn — the placement's
  /// `cutoutHidden`, inverted.
  final bool showCutout;

  /// Whether the keys stand out from the sides. Off on a turned device, whose
  /// solid body draws them on its side walls instead.
  final bool showKeys;

  /// The screen inside a box [width] wide, in its pixels.
  static Rect screenRectIn(IPhoneSpec spec, double width) {
    final mm = width / spec.canvasWidthMm;
    return Rect.fromLTWH(
      (spec.marginXMm + spec.sideMm) * mm,
      (spec.marginYMm + spec.endMm) * mm,
      spec.screenWidthMm * mm,
      spec.screenHeightMm * mm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mm = frameWidth / spec.canvasWidthMm;
    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Under the body, so the band covers each key's inner end and it
          // reads as set into the side rather than stuck on.
          if (showKeys)
            Positioned.fill(
              child: CustomPaint(painter: _KeysPainter(spec, frameColor)),
            ),
          Positioned.fill(
            child: CustomPaint(painter: _BodyPainter(spec, frameColor)),
          ),
          Positioned.fromRect(
            rect: screenRectIn(spec, frameWidth),
            child: ClipPath(
              clipper: _ScreenClipper(spec.screenRadiusMm * mm),
              child: screenshot,
            ),
          ),
          // Over the clipped screen, not inside the clip. Inside it, the
          // screenshot and the camera would each be blended against the
          // clip's soft top row in turn, and a quarter of the screenshot
          // would survive under the black as a coloured hairline across the
          // top of the notch.
          if (showCutout)
            Positioned.fromRect(
              rect: screenRectIn(spec, frameWidth),
              child: IgnorePointer(
                child: CustomPaint(painter: _CameraPainter(spec, mm)),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The superellipse
// -----------------------------------------------------------------------------

/// The exponent every chassis in the catalog turns its corners on: the traced
/// iPhones measured 2.4 to 2.8, the Pixel 9 Pro 2.42, and
/// `tool/frame_geometry.py` draws the generated phones at 2.5.
/// `BodyCorner.squircle` is the same curve.
const double kSquircleExponent = 2.5;

/// A rectangle with superellipse corners of radius [r] — the extent of the
/// curve along each edge — as a smooth path, clockwise from the top edge.
///
/// Fitted with three cubics a quarter, as `squircle()` in
/// `tool/frame_geometry.py` does, which holds it within a quarter of a pixel of
/// the true curve at any size a frame is exported at.
Path squirclePath(Rect rect, double r) {
  final radius = r.clamp(0.0, rect.shortestSide / 2);
  if (radius <= 0.25) return Path()..addRect(rect);

  final quad = _unitQuadrant;
  // Local corner coordinates: the vertex at the origin, the quadrant running
  // from (0, 1) on the vertical edge to (1, 0) on the horizontal one.
  Offset at(Offset vertex, double sx, double sy, Offset p) =>
      Offset(vertex.dx + sx * p.dx * radius, vertex.dy + sy * p.dy * radius);

  final path = Path()
    ..moveTo(rect.left + radius, rect.top)
    ..lineTo(rect.right - radius, rect.top);

  void corner(Offset vertex, double sx, double sy, {required bool reverse}) {
    final segments = reverse
        ? [
            for (final s in quad.reversed) [s[3], s[2], s[1], s[0]],
          ]
        : quad;
    for (final s in segments) {
      final c0 = at(vertex, sx, sy, s[1]);
      final c1 = at(vertex, sx, sy, s[2]);
      final p1 = at(vertex, sx, sy, s[3]);
      path.cubicTo(c0.dx, c0.dy, c1.dx, c1.dy, p1.dx, p1.dy);
    }
  }

  corner(rect.topRight, -1, 1, reverse: true);
  path.lineTo(rect.right, rect.bottom - radius);
  corner(rect.bottomRight, -1, -1, reverse: false);
  path.lineTo(rect.left + radius, rect.bottom);
  corner(rect.bottomLeft, 1, -1, reverse: true);
  path.lineTo(rect.left, rect.top + radius);
  corner(rect.topLeft, 1, 1, reverse: false);
  return path..close();
}

/// One quadrant of the unit superellipse as three cubics, each
/// `[p0, c0, c1, p1]`. Worked out once: the curve only scales.
final List<List<Offset>> _unitQuadrant = [
  for (var i = 0; i < 3; i++)
    _fitCubic(math.pi / 2 * i / 3, math.pi / 2 * (i + 1) / 3),
];

Offset _sePoint(double theta) {
  const k = 2 / kSquircleExponent;
  return Offset(
    1 - math.pow(math.cos(theta).abs(), k).toDouble(),
    1 - math.pow(math.sin(theta).abs(), k).toDouble(),
  );
}

/// The unit tangent at [theta], in the direction of increasing theta. The
/// derivative itself is unbounded at both ends — the curve meets each edge
/// tangentially — so only its direction is used.
Offset _seTangent(double theta) {
  const k = 2 / kSquircleExponent;
  final c = math.max(math.cos(theta), 1e-9);
  final s = math.max(math.sin(theta), 1e-9);
  final dx = k * math.pow(c, k - 1) * s;
  final dy = -k * math.pow(s, k - 1) * c;
  final m = math.sqrt(dx * dx + dy * dy);
  return Offset(dx / m, dy / m);
}

/// A cubic over [t0, t1] with exact ends and end directions, its two arm
/// lengths solved so it also passes through the true midpoint.
List<Offset> _fitCubic(double t0, double t1) {
  final p0 = _sePoint(t0);
  final p1 = _sePoint(t1);
  final d0 = _seTangent(t0);
  final d1 = _seTangent(t1);
  final mid = _sePoint((t0 + t1) / 2);
  final rx = mid.dx - 0.5 * (p0.dx + p1.dx);
  final ry = mid.dy - 0.5 * (p0.dy + p1.dy);
  final a11 = 0.375 * d0.dx;
  final a21 = 0.375 * d0.dy;
  final a12 = -0.375 * d1.dx;
  final a22 = -0.375 * d1.dy;
  final det = a11 * a22 - a12 * a21;
  double a;
  double b;
  if (det.abs() < 1e-12) {
    a = b = (p1 - p0).distance / 3;
  } else {
    a = (rx * a22 - a12 * ry) / det;
    b = (a11 * ry - rx * a21) / det;
  }
  return [p0, p0 + d0 * a, p1 - d1 * b, p1];
}

// -----------------------------------------------------------------------------
// The finish
//
// A band is drawn as nested fills, each the body's outline pulled in a little
// further and painted one step along the profile, outside in. Each fill's edge
// is anti-aliased over the one before, so the band comes out as a smooth ramp
// that follows the corners exactly — the same construction the generated
// frames use, a ring per step.
// -----------------------------------------------------------------------------

/// The widest a single step of a ramp may be, in the frame's own pixels.
/// Small enough that no step shows, at any size a frame is exported at.
const double _stepPx = 0.6;

/// Across the band from its outer edge (0) to the glass (1): how far each point
/// is lifted (positive, as a share of the finish's highlight) or sunk
/// (negative, as a share of [_sink]) from the finish's own colour.
///
/// Calibrated against the traced frames rendered through the exporter's own
/// stage, on the finishes whose band colour is known best: the White 16 and
/// 16 Plus, the White Titanium 16 Pro and 16 Pro Max, the Silver 17 Pro and
/// 17 Pro Max, and the Starlight 13 mini.
const _satin = [
  (0.00, 0.22),
  (0.05, -0.15),
  (0.12, -0.10),
  (0.20, 0.05),
  (0.30, 0.25),
  (0.40, 0.44),
  (0.50, 0.60),
  (0.60, 0.73),
  (0.70, 0.86),
  (0.80, 0.98),
  (0.85, 0.95),
  (0.92, 0.75),
  (0.97, 0.45),
  (1.00, 0.05),
];
const _titanium = [
  (0.00, -0.05),
  (0.05, -0.20),
  (0.12, -0.12),
  (0.20, -0.03),
  (0.30, 0.12),
  (0.40, 0.29),
  (0.50, 0.52),
  (0.60, 0.76),
  (0.70, 0.93),
  (0.78, 1.00),
  (0.83, 0.85),
  (0.89, 0.45),
  (0.94, -0.15),
  (1.00, -0.90),
];
const _unibody = [
  (0.00, 0.10),
  (0.07, 0.00),
  (0.13, -0.34),
  (0.17, -0.33),
  (0.22, -0.18),
  (0.27, -0.08),
  (0.32, 0.06),
  (0.40, 0.22),
  (0.48, 0.38),
  (0.55, 0.52),
  (0.62, 0.66),
  (0.70, 0.74),
  (0.77, 0.86),
  (0.81, 0.88),
  (0.86, 0.84),
  (0.91, 0.71),
  (0.95, 0.58),
  (1.00, 0.50),
];
const _flatEdge = [
  (0.00, -0.24),
  (0.07, -0.39),
  (0.11, -0.47),
  (0.15, -0.29),
  (0.20, -0.09),
  (0.24, 0.32),
  (0.28, 0.76),
  (0.33, 0.90),
  (0.37, 0.95),
  (0.41, 0.87),
  (0.46, 0.71),
  (0.50, 0.54),
  (0.58, 0.27),
  (0.67, -0.02),
  (0.80, -0.04),
  (0.89, 0.12),
  (0.97, 0.38),
  (1.00, 0.38),
];

/// How far a full highlight lifts each channel, out of 255. Adding the same
/// amount to all three keeps the finish's hue and chroma, which is what the
/// traced frames do: an Ultramarine band highlights to a paler blue, not to
/// grey. The flat-sided 13 throws a far weaker glint than the rounded edges.
double _liftFor(IPhoneRail rail) => switch (rail) {
  IPhoneRail.satin => 92,
  IPhoneRail.titanium => 105,
  IPhoneRail.unibody => 85,
  IPhoneRail.flatEdge => 35,
  IPhoneRail.polishedSteel => 0,
};

/// How far a full shadow darkens the finish.
const double _sink = 0.55;

int _channel(int argb, int shift) => (argb >> shift) & 0xFF;

/// [base] lifted by [s] of [lift] (positive) or sunk by [s] of [_sink].
Color _shade(Color base, double s, double lift) {
  final argb = base.toARGB32();
  final r = _channel(argb, 16);
  final g = _channel(argb, 8);
  final b = _channel(argb, 0);
  if (s >= 0) {
    // Every finish lifts by about the same amount at its highlight except a
    // black one, which reflects about half as much: the Black 16 against the
    // White, Black Titanium against Natural, measured.
    final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    final reflect = 0.5 + 0.5 * ((luma - 0.15) / 0.15).clamp(0.0, 1.0);
    // And a saturated one highlights narrowly: the Ultramarine 16 reaches the
    // White's peak but holds its colour across the rest of the band, where the
    // White is pale all the way across. Raising the profile to a power keeps
    // the peak and narrows everything under it.
    final chroma =
        (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 255;
    final shaped = math.pow(s, 1 + 3 * chroma).toDouble();
    final add = shaped * lift * reflect;
    int up(int c) => (c + add).round().clamp(0, 255);
    return Color.fromARGB(255, up(r), up(g), up(b));
  }
  final k = 1 + s * _sink;
  int down(int c) => (c * k).round().clamp(0, 255);
  return Color.fromARGB(255, down(r), down(g), down(b));
}

/// The band's colours across its width, outer edge first.
List<(double, Color)> _railStops(IPhoneRail rail, Color base) {
  if (rail == IPhoneRail.polishedSteel) {
    // A mirror: the stripe reflects the room, not the finish, so it is near
    // white on every colour — a dark outline, the stripe, then the finish.
    final stripe = Color.lerp(base, const Color(0xFFFFFFFF), 0.85)!;
    const outline = Color(0xFF232222);
    return [
      (0.00, outline),
      (0.10, outline),
      (0.12, stripe),
      (0.40, stripe),
      (0.43, base),
      (0.95, base),
      (1.00, _shade(base, 0.25, 32)),
    ];
  }
  final profile = switch (rail) {
    IPhoneRail.satin => _satin,
    IPhoneRail.titanium => _titanium,
    IPhoneRail.unibody => _unibody,
    _ => _flatEdge,
  };
  final lift = _liftFor(rail);
  return [for (final (t, s) in profile) (t, _shade(base, s, lift))];
}

/// Between the band and the black border: grey levels at distances in
/// millimetres in from the band, the last one black.
List<(double, int)> _edgeStops(IPhoneGlassEdge edge) => switch (edge) {
  IPhoneGlassEdge.gradient => const [
    (0.00, 14),
    (0.07, 14),
    (0.08, 78),
    (0.17, 57),
    (0.28, 41),
    (0.39, 29),
    (0.50, 22),
    (0.61, 12),
    (0.72, 8),
    (0.83, 4),
    (0.94, 2),
    (1.05, 0),
  ],
  IPhoneGlassEdge.lip => const [
    (0.00, 50),
    (0.05, 42),
    (0.10, 57),
    (0.16, 65),
    (0.21, 58),
    (0.22, 30),
    (0.32, 29),
    (0.33, 0),
  ],
  IPhoneGlassEdge.line => const [
    (0.00, 45),
    (0.05, 45),
    (0.055, 101),
    (0.10, 101),
    (0.11, 40),
    (0.16, 40),
    (0.165, 0),
  ],
  IPhoneGlassEdge.darkLip => const [
    (0.00, 62),
    (0.055, 50),
    (0.11, 50),
    (0.115, 0),
  ],
};

/// [stops] — each a position from 0 to 1 across a ramp [width] pixels wide,
/// and a colour — as the insets each fill starts at and the colour it wears.
List<(double, Color)> _steps(List<(double, Color)> stops, double width) {
  final out = <(double, Color)>[];
  if (width <= 0) return out;
  for (var i = 0; i < stops.length - 1; i++) {
    final (t0, c0) = stops[i];
    final (t1, c1) = stops[i + 1];
    final span = (t1 - t0) * width;
    if (span <= 0) continue;
    final n = math.max(1, (span / _stepPx).ceil());
    for (var j = 0; j < n; j++) {
      out.add((t0 * width + span * j / n, Color.lerp(c0, c1, (j + 0.5) / n)!));
    }
  }
  return out;
}

// -----------------------------------------------------------------------------
// The painters
// -----------------------------------------------------------------------------

Rect _bodyIn(IPhoneSpec spec, Size size) {
  final mm = size.width / spec.canvasWidthMm;
  return Rect.fromLTWH(
    spec.marginXMm * mm,
    spec.marginYMm * mm,
    spec.bodyWidthMm * mm,
    spec.bodyHeightMm * mm,
  );
}

class _BodyPainter extends CustomPainter {
  const _BodyPainter(this.spec, this.color);

  final IPhoneSpec spec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final mm = size.width / spec.canvasWidthMm;
    final body = _bodyIn(spec, size);
    final radius = spec.bodyRadiusMm * mm;
    final fill = Paint();

    void ring(double inset, Color c) => canvas.drawPath(
      squirclePath(body.deflate(inset), radius - inset),
      fill..color = c,
    );

    // The metal band.
    final rail = spec.railMm * mm;
    for (final (inset, c) in _steps(_railStops(spec.rail, color), rail)) {
      ring(inset, c);
    }

    // The cover glass's edge, then the black border all the way in.
    final edge = _edgeStops(spec.edge);
    final edgeMm = edge.last.$1;
    final edgeWidth = edgeMm * mm;
    final greys = [
      for (final (d, grey) in edge)
        (d / edgeMm, Color.fromARGB(255, grey, grey, grey)),
    ];
    for (final (inset, c) in _steps(greys, edgeWidth)) {
      ring(rail + inset, c);
    }
    ring(rail + edgeWidth, const Color(0xFF000000));

    _earpiece(canvas, spec.earpiece, body, body.top + rail, mm);
  }

  /// The earpiece, hanging from the inner edge of the band at [top].
  static void _earpiece(
    Canvas canvas,
    IPhoneEarpiece ear,
    Rect body,
    double top,
    double mm,
  ) {
    final w = ear.widthMm * mm;
    final d = ear.depthMm * mm;
    final left = body.center.dx - w / 2;
    final right = left + w;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.06 * mm, 0.5);
    switch (ear.shape) {
      case IPhoneEarpieceShape.tab:
        // Tucked a hair under the band so it reads as hanging from it.
        final slot = RRect.fromLTRBAndCorners(
          left,
          top - 0.05 * mm,
          right,
          top + d,
          bottomLeft: Radius.circular(d * 0.8),
          bottomRight: Radius.circular(d * 0.8),
        );
        canvas.drawRRect(slot, Paint()..color = const Color(0xFF151515));
        canvas.drawRRect(slot, line..color = const Color(0xFF2F2F2F));
      case IPhoneEarpieceShape.u:
        final r = math.min(d * 0.55, w / 2);
        canvas.drawPath(
          Path()
            ..moveTo(left, top)
            ..lineTo(left, top + d - r)
            ..quadraticBezierTo(left, top + d, left + r, top + d)
            ..lineTo(right - r, top + d)
            ..quadraticBezierTo(right, top + d, right, top + d - r)
            ..lineTo(right, top),
          line
            ..strokeWidth = math.max(0.1 * mm, 0.5)
            ..color = const Color(0xFF3A3A3A),
        );
      case IPhoneEarpieceShape.chamfer:
        canvas.drawPath(
          Path()
            ..moveTo(left - d, top)
            ..lineTo(left, top + d)
            ..lineTo(right, top + d)
            ..lineTo(right + d, top),
          line
            ..strokeWidth = math.max(0.1 * mm, 0.5)
            ..color = const Color(0xFF3A3A3A),
        );
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.spec != spec || old.color != color;
}

class _KeysPainter extends CustomPainter {
  const _KeysPainter(this.spec, this.color);

  final IPhoneSpec spec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final mm = size.width / spec.canvasWidthMm;
    final body = _bodyIn(spec, size);
    final lift = math.max(_liftFor(spec.rail), 60.0);
    // Turned metal: darker where it rolls away, lit across its crown.
    final outer = _shade(color, -0.35, lift);
    final crown = _shade(color, 0.55, lift);
    final inner = _shade(color, 0.05, lift);
    for (final key in spec.keys) {
      final proud = key.proudMm * mm;
      final left = key.side == FrameSide.left;
      final rect = Rect.fromLTWH(
        left ? body.left - proud : body.right - proud,
        body.top + key.topMm * mm,
        proud * 2,
        key.lengthMm * mm,
      );
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(proud));
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            colors: left ? [outer, crown, inner] : [inner, crown, outer],
            stops: const [0.0, 0.3, 1.0],
          ).createShader(rect),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(proud * 0.14, 0.4)
          ..color = const Color(0x38000000),
      );
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) =>
      old.spec != spec || old.color != color;
}

/// The screen's outline, for clipping the screenshot to it.
class _ScreenClipper extends CustomClipper<Path> {
  const _ScreenClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) => squirclePath(Offset.zero & size, radius);

  @override
  bool shouldReclip(_ScreenClipper old) => old.radius != radius;
}

/// The Dynamic Island, or the notch, in the screen's own coordinates.
class _CameraPainter extends CustomPainter {
  const _CameraPainter(this.spec, this.mm);

  final IPhoneSpec spec;

  /// Pixels per millimetre.
  final double mm;

  @override
  void paint(Canvas canvas, Size size) {
    final c = spec.cutout;
    final w = c.widthMm * mm;
    final h = c.heightMm * mm;
    final left = (size.width - w) / 2;
    const black = Color(0xFF000000);
    if (!c.notch) {
      final island = Rect.fromLTWH(left, c.topMm * mm, w, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(island, Radius.circular(h / 2)),
        Paint()..color = black,
      );
      _lens(canvas, Offset(island.right - h * 0.46, island.center.dy), h);
      return;
    }

    // The notch, hanging from the top edge. Drawn from a little above it, into
    // the black border, so its top meets the border with no seam.
    final right = left + w;
    final f = c.filletMm * mm;
    final r = c.cornerMm * mm;
    final path = Path()
      ..moveTo(left - f, -1)
      ..lineTo(left - f, 0)
      ..quadraticBezierTo(left, 0, left, f)
      ..lineTo(left, h - r)
      ..cubicTo(left, h - r * 0.45, left + r * 0.45, h, left + r, h)
      ..lineTo(right - r, h)
      ..cubicTo(right - r * 0.45, h, right, h - r * 0.45, right, h - r)
      ..lineTo(right, f)
      ..quadraticBezierTo(right, 0, right + f, 0)
      ..lineTo(right + f, -1)
      ..close();
    canvas.drawPath(path, Paint()..color = black);
    _lens(canvas, Offset(left + w * 0.13, h * 0.42), h * 0.62);
  }

  /// A camera lens inside a cut-out [h] tall: dark blue glass in a barely
  /// lighter surround, catching a violet glint above a green one, as the
  /// front camera photographs.
  void _lens(Canvas canvas, Offset centre, double h) {
    final r = h * 0.16;
    canvas.drawCircle(
      centre,
      r * 1.4,
      Paint()..color = const Color(0xFF050609),
    );
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1F2650), Color(0xFF0B0E22), Color(0xFF020306)],
          stops: [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: r)),
    );
    canvas.drawCircle(
      centre + Offset(0, -r * 0.42),
      r * 0.16,
      Paint()..color = const Color(0x739A86E0),
    );
    canvas.drawCircle(
      centre + Offset(0, r * 0.42),
      r * 0.13,
      Paint()..color = const Color(0x5944B08C),
    );
  }

  @override
  bool shouldRepaint(_CameraPainter old) => old.spec != spec || old.mm != mm;
}
