// -----------------------------------------------------------------------------
// INTENTIONALLY TOKEN-FREE — this file renders USER CONTENT, not chrome.
//
// `CustomDeviceFrame` draws a device body the user has designed, and it is
// mounted inside `SceneView`'s `_FrameLayer`, which the editor captures through
// a `RepaintBoundary`. Every colour here comes from the user's `FrameDesign`
// and lands in their exported PNG, so the design system's token rules do not
// apply — and must not be applied. An export made in dark mode has to be
// byte-identical to the same export made in light mode.
//
// Same exemption as `programmatic_frame.dart` and `scene_view.dart`.
// -----------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/screen_doc.dart';

/// A device frame assembled from a [FrameDesign].
///
/// Where [ProgrammaticDeviceFrame] simulates a specific handset, this draws
/// whatever the user dialled in: a bezel of any thickness (including none), a
/// corner radius, an optional punch hole anywhere along the top, and optional
/// side keys on either edge.
class CustomDeviceFrame extends StatelessWidget {
  const CustomDeviceFrame({
    super.key,
    required this.screenshot,
    required this.frameWidth,
    required this.frameHeight,
    required this.design,
    this.showCutout = true,
    this.showKeys = true,
  });

  final Widget screenshot;
  final double frameWidth;
  final double frameHeight;
  final FrameDesign design;

  /// Whether to draw the camera [design] describes.
  ///
  /// Distinct from `design.punchHole.enabled`, which says whether this frame
  /// has a camera at all, and is the thing the builder's own switch edits.
  /// This one is the placement's override, and it exists because the dynamic
  /// handsets are drawn from a catalog design the user has never touched — so
  /// there is no `punchHole` of theirs to switch off until they start editing.
  final bool showCutout;

  /// Whether to draw the side keys as slivers standing proud of the edge.
  ///
  /// Off when the device is turned out of the page and drawn as a solid: a
  /// sliver is flat, in the plane of the screen, and a turned phone would wear
  /// it as a fin. The solid puts the same keys on its side wall instead — see
  /// `DeviceSolidPainter`.
  final bool showKeys;

  /// The screen rect a [FrameDesign] leaves inside its own frame box, as
  /// fractions of the frame — the same contract as `FrameDevice.screenRect`, so
  /// the scene's shadow and screenshot-pan maths line up with what is drawn.
  static Rect screenRectFor(FrameDesign design, double aspect) {
    // The two sides differ only on a foldable, whose hinge cover widens the
    // bezel on the edge it folds on.
    final left = design.left.clamp(0.0, 0.45);
    final right = design.right.clamp(0.0, 0.45);
    // Every thickness is a fraction of *width*; expressed against height it
    // shrinks by the frame's aspect, which is what keeps a bezel set to one
    // number visually even all the way round.
    final forehead = design.top.clamp(0.0, 0.45) * aspect;
    final chin = design.bottom.clamp(0.0, 0.45) * aspect;
    return Rect.fromLTRB(left, forehead, 1 - right, 1 - chin);
  }

  /// The corners of the screen opening a [FrameDesign] leaves in a frame
  /// [frameWidth] wide.
  ///
  /// Concentric, not equal: an inner radius that matched the outer one would
  /// leave the bezel visibly thicker at the corners than along the edges.
  ///
  /// Driven by the *thinner* of the two edges meeting at a corner, because
  /// that is the one the inner curve has to clear — a thick forehead over thin
  /// sides must not round the screen's top corners away.
  ///
  /// Public because the scene casts the screen's shadow from this shape when
  /// the corners differ, which a single radius cannot describe.
  static BorderRadius apertureRadii(FrameDesign design, double frameWidth) {
    final left = frameWidth * design.left.clamp(0.0, 0.45);
    final right = frameWidth * design.right.clamp(0.0, 0.45);
    final forehead = frameWidth * design.top.clamp(0.0, 0.45);
    final outer = design.outerRadii(frameWidth);
    final spine = design.hinge.enabled ? frameWidth * _spineScreenRadius : 0.0;
    Radius inset(Radius r, double by, {required bool spineSide}) =>
        Radius.circular(math.max(r.x - by, spineSide ? spine : 0.0));
    final hingeLeft = design.hinge.enabled && design.hinge.onLeft;
    final hingeRight = design.hinge.enabled && !design.hinge.onLeft;
    return BorderRadius.only(
      topLeft: inset(
        outer.topLeft,
        math.min(left, forehead),
        spineSide: hingeLeft,
      ),
      bottomLeft: inset(
        outer.bottomLeft,
        math.min(left, forehead),
        spineSide: hingeLeft,
      ),
      topRight: inset(
        outer.topRight,
        math.min(right, forehead),
        spineSide: hingeRight,
      ),
      bottomRight: inset(
        outer.bottomRight,
        math.min(right, forehead),
        spineSide: hingeRight,
      ),
    );
  }

  /// The smallest a display's own corner gets on a hinge's side, as a fraction
  /// of frame width. The body is near-square there, so concentric arithmetic
  /// would square the screen off too — but a panel always has some rounding.
  /// Measured off Apple's iPhone Duo diagrams: about 2% of the screen's width.
  static const _spineScreenRadius = 0.018;

  @override
  Widget build(BuildContext context) {
    final sides = frameWidth * design.thickness.clamp(0.0, 0.45);
    final left = frameWidth * design.left.clamp(0.0, 0.45);
    final right = frameWidth * design.right.clamp(0.0, 0.45);
    final forehead = frameWidth * design.top.clamp(0.0, 0.45);
    final chin = frameWidth * design.bottom.clamp(0.0, 0.45);
    final radiusOuter = frameWidth * design.cornerRadius.clamp(0.0, 0.5);
    final outer = design.outerRadii(frameWidth);
    final inner = apertureRadii(design, frameWidth);
    final rimWidth = frameWidth * design.rimWidth;

    final screen = ClipPath(
      clipper: ShapeBorderClipper(
        shape: cornerShapeWith(design.cornerStyle, inner),
      ),
      child: ColoredBox(
        color: design.screenColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            screenshot,
            // Above the picture, below the camera: the glass curves in front
            // of what it is showing, and the lens sits in a hole through it.
            if (design.edgeCurve > 0) _edgeCurve(),
            if (design.punchHole.enabled && showCutout) _punchHole(),
          ],
        ),
      ),
    );

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Keys sit under the body so they read as pressed into the edge
          // rather than stuck onto the front.
          if (showKeys) ...[
            ..._buttons(design.power, radiusOuter),
            ..._buttons(design.volume, radiusOuter),
          ],

          // The chassis, painted rather than filled. A device body is not one
          // flat colour: it is a metal rail catching the light along its
          // chamfer, and a black display border inside it. Filling the whole
          // body with `design.color` — which is what this did — is why a built
          // frame read as a plastic slab beside the traced artwork.
          Positioned.fill(
            child: CustomPaint(
              painter: _Chassis(
                design: design,
                sides: sides,
                left: left,
                right: right,
                forehead: forehead,
                chin: chin,
                outer: outer,
                inner: inner,
                rimWidth: rimWidth,
              ),
            ),
          ),

          // The picture, over the border the chassis painted under it.
          if (left > 0 || right > 0 || forehead > 0 || chin > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(left, forehead, right, chin),
              child: screen,
            )
          else
            Positioned.fill(child: screen),
        ],
      ),
    );
  }

  /// The waterfall-edge shading — glass rolling away down both sides.
  ///
  /// **Both** sides darken. The traced Edge 50 Ultra and Galaxy Note 10+ put a
  /// white specular band down one edge and a shadow down the other, which
  /// works over their own dark artwork but not here: a 30%-white band over a
  /// light screenshot is invisible, so the curve only ever showed on the
  /// shaded side. A screenshot can be any colour, and the thing that reads as
  /// curvature on all of them is the display turning away — a shadow at each
  /// edge, with a thin bright specular line right on the rim where the glass
  /// catches the light.
  Widget _edgeCurve() {
    final t = design.edgeCurve.clamp(0.0, 1.0);
    Color shade(double a) => const Color(0xFF000000).withValues(alpha: a * t);
    Color spec(double a) => const Color(0xFFFFFFFF).withValues(alpha: a * t);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              shade(0.38),
              spec(0.22),
              shade(0.10),
              const Color(0x00000000),
              const Color(0x00000000),
              shade(0.10),
              spec(0.22),
              shade(0.38),
            ],
            // Narrow on purpose: widen these and it stops reading as an edge
            // and starts reading as a vignette over the screenshot.
            stops: const [0.0, 0.018, 0.05, 0.16, 0.84, 0.95, 0.982, 1.0],
          ),
        ),
      ),
    );
  }

  /// The camera cut-out, positioned inside the screen.
  Widget _punchHole() {
    final hole = design.punchHole;
    final w = frameWidth * hole.width;
    final h = frameWidth * hole.height;
    final border = frameWidth * hole.borderWidth;
    // Rounding is a fraction of the hole's own short side, so a square hole at
    // 0.5 is a circle and a wide one at 0.5 is a pill — one control, both
    // shapes, and nothing in between can overflow into a corner artefact.
    final radius = math.min(w, h) * hole.cornerRadius.clamp(0.0, 0.5);

    // A centred hole pins both edges so the Center has a width to work with —
    // a Positioned anchored on one axis only hands its child unbounded
    // constraints, which an infinite-width box cannot satisfy.
    if (hole.align == FrameSide.center) {
      return Positioned(
        top: frameWidth * hole.top,
        left: 0,
        right: 0,
        child: Center(child: _holeBody(w, h, radius, border)),
      );
    }

    return Positioned(
      top: frameWidth * hole.top,
      left: hole.align == FrameSide.left ? frameWidth * hole.inset : null,
      right: hole.align == FrameSide.right ? frameWidth * hole.inset : null,
      child: _holeBody(w, h, radius, border),
    );
  }

  Widget _holeBody(double w, double h, double radius, double border) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: design.punchHole.color,
        borderRadius: BorderRadius.circular(radius),
        border: border > 0
            ? Border.all(color: design.punchHole.borderColor, width: border)
            : null,
      ),
    );
  }

  /// One group of side keys, standing proud of the body's edge.
  List<Widget> _buttons(SideButtonSpec spec, double radiusOuter) {
    if (!spec.enabled || spec.count < 1) return const [];
    if (spec.onTop) return _topButtons(spec);
    final left = spec.side == FrameSide.left;
    final thickness = frameWidth * spec.thickness;
    final length = frameHeight * spec.length;
    final gap = frameHeight * spec.gap;

    return [
      for (var i = 0; i < spec.count; i++)
        Positioned(
          top: frameHeight * spec.top + i * (length + gap),
          left: left ? -thickness : null,
          right: left ? null : -thickness,
          child: Container(
            width: thickness * 2,
            height: length,
            decoration: BoxDecoration(
              // Shaded across, not filled flat. A key is a small cylinder of
              // the same metal as the rail, and the artwork draws it with its
              // own three-stop gradient and a dark hairline so it reads as
              // pressed into the edge rather than stuck on as a grey block.
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: _keyRamp(design.color),
              ),
              border: Border.all(
                color: const Color(0x42000000),
                width: math.max(thickness * 0.16, 0.5),
              ),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(left ? thickness : 0),
                right: Radius.circular(left ? 0 : thickness),
              ),
            ),
          ),
        ),
    ];
  }

  /// A group riding the top edge — [SideButtonSpec.onTop]. Everything along
  /// the edge is a fraction of frame *width* here, since that is the edge's
  /// length.
  List<Widget> _topButtons(SideButtonSpec spec) {
    final thickness = frameWidth * spec.thickness;
    final length = frameWidth * spec.length;
    final gap = frameWidth * spec.gap;

    return [
      for (var i = 0; i < spec.count; i++)
        Positioned(
          left: frameWidth * spec.top + i * (length + gap),
          top: -thickness,
          child: Container(
            width: length,
            height: thickness * 2,
            decoration: BoxDecoration(
              // The same cylinder as a side key, turned a quarter: lit from
              // above like the rest of the rail.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _keyRamp(design.color),
              ),
              border: Border.all(
                color: const Color(0x42000000),
                width: math.max(thickness * 0.16, 0.5),
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(thickness),
              ),
            ),
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// The chassis
//
// A transcription of the recipe the generated frame artwork is drawn from —
// see `build_frame_svg` in tool/frame_geometry.py, which is where these
// numbers and this layer order come from. Keeping the two in step is the whole
// point: a device the user "adjusts" into a built frame should not visibly
// change material, and before this it did.
// ---------------------------------------------------------------------------

/// Share of the side inset given to the metal rail; the rest is the black
/// display border.
///
/// `RAIL_SHARE` in the generator. A Pixel 9 Pro splits its inset 48/52 and a
/// Pixel 8 1.57/2.91; 45 sits between them.
const double _kRailShare = 0.45;

/// Where the rail's specular bands sit, as a fraction of rail width, and how
/// bright — the chamfer profile measured off the Pixel 9 Pro: a thin lit outer
/// edge, a shadow groove, a wide lit face, then falloff.
///
/// Restrained on purpose. The rim ramp already carries the finish's own colour,
/// and layering much white over it turns a navy rail powder-blue.
const List<(double, double, Color, double)> _kRailBands = [
  (0.00, 0.09, Color(0xFFFFFFFF), 0.42),
  (0.09, 0.22, Color(0xFF000000), 0.26),
  (0.22, 0.70, Color(0xFFFFFFFF), 0.15),
  (0.70, 1.00, Color(0xFF000000), 0.40),
];

/// The black border between the rail and the aperture.
///
/// Near-black whatever the body is made of, because that is what a display
/// bezel is on every phone: a white handset has a white rail and a black
/// border, and filling the whole inset with the body colour — which is what
/// this used to do — is the single thing that made a pale built frame look
/// nothing like the device it was traced from.
const Color _kDisplayBorder = Color(0xFF04050A);

/// Outer silhouette contour, as a share of body width. `EDGE_LINE_PCT`.
const double _kEdgeLinePct = 0.0016;

/// The finish's vertical ramp: lighter at the top where the key light lands,
/// falling to a deep shade at the bottom.
///
/// Derived from the body colour rather than stored, so every design that
/// already exists gains the rail with no migration and no new control. The
/// factors are read off the generated artwork's own five-stop `rim`: measured
/// against the Galaxy S25 Navy ramp they come out at +15% white, base, +8%,
/// -19% black, -37%.
List<Color> _rimRamp(Color base) => [
  Color.lerp(base, const Color(0xFFFFFFFF), 0.15)!,
  base,
  Color.lerp(base, const Color(0xFFFFFFFF), 0.08)!,
  Color.lerp(base, const Color(0xFF000000), 0.19)!,
  Color.lerp(base, const Color(0xFF000000), 0.37)!,
];

const List<double> _kRimStops = [0.0, 0.2, 0.45, 0.7, 1.0];

/// A side key's three-stop ramp across its own width. The generator's `btn`,
/// which samples the same rim ramp it draws the rail from.
List<Color> _keyRamp(Color base) {
  final ramp = _rimRamp(base);
  return [ramp[1], ramp[2], ramp[4]];
}

class _Chassis extends CustomPainter {
  const _Chassis({
    required this.design,
    required this.sides,
    required this.left,
    required this.right,
    required this.forehead,
    required this.chin,
    required this.outer,
    required this.inner,
    required this.rimWidth,
  });

  final FrameDesign design;

  /// The side bezel the rail is measured off — the design's own thickness,
  /// without any hinge cover.
  final double sides;

  /// The bezels actually drawn down each side; wider than [sides] on a hinge.
  final double left;
  final double right;
  final double forehead;
  final double chin;

  /// The body's corners, and the screen's.
  final BorderRadius outer;
  final BorderRadius inner;
  final double rimWidth;

  /// [outer] pulled in by [by] at every corner, never below square.
  static BorderRadius _less(BorderRadius r, double by) {
    Radius less(Radius c) => Radius.circular(math.max(c.x - by, 0));
    return BorderRadius.only(
      topLeft: less(r.topLeft),
      topRight: less(r.topRight),
      bottomLeft: less(r.bottomLeft),
      bottomRight: less(r.bottomRight),
    );
  }

  /// [radii] grown by [by] at every corner.
  static BorderRadius _more(BorderRadius r, double by) => _less(r, -by);

  Path _shape(Rect rect, BorderRadius radii) =>
      cornerShapeWith(design.cornerStyle, radii).getOuterPath(rect);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;

    // A flat rim is the colour alone: no rail, no display border, no outline.
    // The screen is laid over the middle of it by the widget above, clipped
    // to the inner corners, so what shows is an even band of [design.color].
    if (design.flat) {
      canvas.drawPath(_shape(rect, outer), Paint()..color = design.color);
      return;
    }

    // The rail is measured off the *side* inset and drawn uniformly all round,
    // exactly as the artwork does: a phone's metal band is one thickness, and
    // it is the black border behind it that grows at the brow and chin.
    //
    // Floored so a hairline-bezel design still reads as hardware, and capped so
    // the rail can never eat the border it is supposed to sit outside of.
    final inset = math.min(sides, math.min(forehead, chin));
    var rail = inset * _kRailShare;
    if (inset <= 0) rail = 0;
    rail = math.min(rail, math.max(inset - 0.5, 0));

    final body = _shape(rect, outer);

    // A foldable's cover half: the body less the hinge strip down its spine.
    // Its own rail and black border run inside it, so on a hinge the frame
    // reads as two parts — the cover and the hinge beside it — as it does in
    // the hand. For every other phone this is the whole body.
    final hinge = design.hinge;
    final hingeWidth = hinge.enabled
        ? size.width * hinge.width.clamp(0.0, 0.2)
        : 0.0;
    final cover = hinge.enabled
        ? (hinge.onLeft
              ? Rect.fromLTRB(hingeWidth, 0, size.width, size.height)
              : Rect.fromLTRB(0, 0, size.width - hingeWidth, size.height))
        : rect;

    canvas.save();
    canvas.clipPath(body);

    // 1. The finish itself, running top to bottom.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _rimRamp(design.color),
          stops: _kRimStops,
        ).createShader(rect),
    );

    // 2. Cross-body specular: a lit left rail falling to a shaded right one, so
    // the chassis reads as lit from one side rather than glowing evenly.
    canvas.drawRect(rect, Paint()..shader = _spec(rect));

    // 3. The chamfer, as concentric bands. Stroked along each band's midline
    // rather than filled as an annulus — for a rounded body the two are the
    // same figure, and a stroke follows the corner without a second path.
    for (final (start, end, colour, alpha) in _kRailBands) {
      final thickness = rail * (end - start);
      if (thickness < 0.4) continue;
      final mid = rail * start + thickness / 2;
      canvas.drawPath(
        _shape(cover.deflate(mid), _less(outer, mid)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = colour.withValues(alpha: alpha),
      );
    }

    // 3b. The hinge cover, over the spine the cover's rail leaves bare.
    if (hinge.enabled && hingeWidth > 0) _paintHinge(canvas, size, hingeWidth);

    // 4. Vertical falloff: the top catches the key light, the bottom sits in
    // shadow. Without it the corners read as flat colour.
    canvas.drawRect(rect, Paint()..shader = _vfall(rect));
    canvas.restore();

    // 5. The black display border, from the rail's inner edge inward. The
    // screenshot is laid over the middle of it by the widget above.
    final innerRect = cover.deflate(rail);
    final innerPath = _shape(innerRect, _less(outer, rail));
    if (rail > 0) canvas.drawPath(innerPath, Paint()..color = _kDisplayBorder);

    // 6. Outer silhouette, so the body has an edge against a pale backdrop.
    final edge = math.max(size.width * _kEdgeLinePct, 1.0);
    canvas.drawPath(
      _shape(rect.deflate(edge / 2), _less(outer, edge / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge
        ..color = const Color(0xFF000000).withValues(alpha: 0.42),
    );

    // 7. The rail's inner lip. Still `design.rimColor` and `design.rimWidth`,
    // so a design that tuned them keeps its say; the artwork's own figure is a
    // white hairline at 10% over a dark finish and 20% over a light one.
    if (rimWidth > 0 && rail > 0) {
      canvas.drawPath(
        innerPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimWidth
          ..color = design.rimColor,
      );
    }

    // 8. Screen edge shading, drawn strictly outside the aperture as its own
    // ring so none of it washes over the user's screenshot.
    final aperture = Rect.fromLTRB(
      left,
      forehead,
      size.width - right,
      size.height - chin,
    );
    if (!aperture.isEmpty) {
      final lip = math.max(size.width * 0.004, 0.6);
      canvas.drawPath(
        _shape(aperture.inflate(lip / 2), _more(inner, lip / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lip
          ..color = const Color(0xFF000000).withValues(alpha: 0.55),
      );
    }
  }

  /// The hinge cover: a matte strip down the spine, stopping short of the top
  /// and bottom in rounded caps.
  ///
  /// Micro-blasted where the frame is polished, so it is the finish a shade
  /// darker with none of the rail's specular bands — only a soft roll across
  /// it, lit on the outside, and a dark seam where it meets the cover half.
  void _paintHinge(Canvas canvas, Size size, double width) {
    final hinge = design.hinge;
    final cap = size.width * hinge.inset.clamp(0.0, 0.2);
    final strip = hinge.onLeft
        ? Rect.fromLTRB(0, cap, width, size.height - cap)
        : Rect.fromLTRB(size.width - width, cap, size.width, size.height - cap);
    if (strip.isEmpty) return;
    final shape = RRect.fromRectAndRadius(strip, Radius.circular(width / 2));

    final base = Color.lerp(design.color, const Color(0xFF000000), 0.14)!;
    final lit = Color.lerp(design.color, const Color(0xFFFFFFFF), 0.06)!;
    final deep = Color.lerp(design.color, const Color(0xFF000000), 0.30)!;
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          // Outside to inside: the lit outer roll, the flat, the fall-off
          // into the seam.
          begin: hinge.onLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: hinge.onLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [deep, lit, base, deep],
          stops: const [0.0, 0.28, 0.62, 1.0],
        ).createShader(strip),
    );

    // The seam between the hinge and the cover, the one hard line a matte
    // part has.
    final seamX = hinge.onLeft ? strip.right : strip.left;
    canvas.drawLine(
      Offset(seamX, strip.top + width / 2),
      Offset(seamX, strip.bottom - width / 2),
      Paint()
        ..strokeWidth = math.max(size.width * 0.0022, 0.6)
        ..color = const Color(0xFF000000).withValues(alpha: 0.45),
    );
  }

  Shader _spec(Rect rect) => const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0x4DFFFFFF),
      Color(0x0FFFFFFF),
      Color(0x00FFFFFF),
      Color(0x00000000),
      Color(0x24000000),
      Color(0x5C000000),
    ],
    stops: [0.0, 0.04, 0.30, 0.70, 0.96, 1.0],
  ).createShader(rect);

  Shader _vfall(Rect rect) => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x29FFFFFF),
      Color(0x00FFFFFF),
      Color(0x00000000),
      Color(0x42000000),
    ],
    stops: [0.0, 0.35, 0.72, 1.0],
  ).createShader(rect);

  @override
  bool shouldRepaint(_Chassis old) =>
      old.design != design ||
      old.sides != sides ||
      old.left != left ||
      old.right != right ||
      old.forehead != forehead ||
      old.chin != chin ||
      old.outer != outer ||
      old.inner != inner ||
      old.rimWidth != rimWidth;
}
