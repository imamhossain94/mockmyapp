// -----------------------------------------------------------------------------
// INTENTIONALLY TOKEN-FREE — this file renders USER CONTENT, not chrome.
//
// Everything painted here is part of a device inside `SceneView`, which the
// editor captures through a `RepaintBoundary`: the band round a turned phone,
// its keys, its shadow and the reflection on its glass all land in the user's
// exported PNG. The literal whites and blacks are light, not theme — an export
// made in dark mode has to be byte-identical to the same export made in light.
//
// Same exemption as `scene_view.dart`, `programmatic_frame.dart` and
// `custom_device_frame.dart`.
// -----------------------------------------------------------------------------

/// A device as a solid: the band round its sides, its keys, the shadow it casts
/// and the reflection on its glass, for a device turned out of the page.
///
/// The front of the device is not drawn here. It is the same artwork, drawn
/// body or built frame it has always been, turned by a `Transform` — a flat
/// face in perspective is exactly what a `Transform` is for, and it keeps every
/// frame looking the way it was traced. What a transform cannot give a flat
/// picture is sides. So [DeviceSolidPainter] draws those behind it, through
/// the very same matrix ([deviceTurn]), and the two meet at the front edge of
/// the body because they are projections of one set of points.
///
/// The body is a prism: the chassis outline, pushed straight back by the
/// device's depth. That is convex, which is what keeps the drawing honest
/// without a depth buffer — the faces of a convex solid that face the viewer
/// never overlap one another, so the side quads can be painted in any order
/// and the face goes on top.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../data/assets/drawn_iphones.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/assets/studio_frames.dart';
import '../../features/editor/widgets/programmatic_frame.dart';
import '../models/screen_doc.dart';

/// The turn [t] puts on a device [frameHeight] tall: rotation in the page and,
/// when the device is tilted, a turn out of it seen through a perspective.
///
/// One function for both halves of a turned device. The face is drawn by a
/// `Transform` with this matrix about its centre and the sides are projected
/// through it by hand; if they ever read two different matrices the sides would
/// slide out from under the face.
///
/// The perspective's strength is set by the device's own height, not by pixels,
/// so the editor preview and a full-size export show the same angle.
Matrix4 deviceTurn(Transform2D t, double frameHeight) {
  final turn = Matrix4.identity();
  if (t.isTilted && frameHeight > 0) {
    turn
      ..setEntry(3, 2, 1 / (frameHeight * kDevicePerspective))
      ..rotateX(-t.tiltX * math.pi / 180)
      ..rotateY(t.tiltY * math.pi / 180);
  }
  turn.rotateZ(t.rotationDeg * math.pi / 180);
  return turn;
}

/// How far the eye stands from a turned device, in device heights.
///
/// About what a portrait lens at arm's length gives: enough convergence for the
/// near edge to read as near, not so much that a phone turned 40 degrees looks
/// like a wedge.
const double kDevicePerspective = 2.4;

/// How deep a handset is against the width of its body.
///
/// Read off the current flagships — an iPhone 16 Pro is 8.25 mm on 71.5, a
/// Pixel 9 Pro 8.5 on 72, a Galaxy S25 7.2 on 70.5 — which all land within a
/// hair of 11%.
const double kPhoneDepth = 0.11;

/// The same for a tablet. An iPad Pro 13" is 5.1 mm on 215; an iPad Air 6.1 on
/// 215; an Android slate about 6 on 250. Proportionally a quarter of a phone's,
/// which is why a tablet turned the same amount shows a much thinner band.
const double kTabletDepth = 0.03;

/// How the corners of a body turn.
enum BodyCorner {
  /// A circular arc — `CornerStyle.round`.
  round,

  /// Flutter's continuous corner, as `CornerStyle.smooth` draws it.
  smooth,

  /// A superellipse of exponent 2.5, which is what `tool/frame_geometry.py`
  /// draws every generated chassis with — a real Pixel 9 Pro measures 2.42,
  /// within noise of it. The artwork frames' bodies are this shape.
  squircle,
}

/// A side key on a solid body, in the frame box's own pixels.
class SolidKey {
  const SolidKey({
    required this.side,
    required this.top,
    required this.length,
    required this.protrusion,
    this.onTop = false,
  });

  /// [FrameSide.left] or [FrameSide.right]. Ignored when [onTop].
  final FrameSide side;

  /// Where the key starts along its edge, and how long it is: down a side, or
  /// across the top from the left when [onTop].
  final double top;
  final double length;

  /// Whether the key stands on the top wall rather than a side one — the
  /// iPhone Duo's volume keys.
  final bool onTop;

  /// How far the key stands proud of the band.
  final double protrusion;

  @override
  bool operator ==(Object other) =>
      other is SolidKey &&
      other.side == side &&
      other.top == top &&
      other.length == length &&
      other.protrusion == protrusion &&
      other.onTop == onTop;

  @override
  int get hashCode => Object.hash(side, top, length, protrusion, onTop);
}

/// The solid a device frame stands for, in its frame box's own pixels.
///
/// Every measurement is already resolved to pixels by the caller, which is the
/// one place that knows which of the three kinds of frame this is and where
/// each of them keeps its chassis.
class DeviceSolid {
  const DeviceSolid({
    required this.body,
    required this.radius,
    required this.corner,
    required this.depth,
    required this.finish,
    this.keys = const [],
    this.radii,
  });

  /// The chassis inside the frame box. The whole box for a drawn or built
  /// body; for artwork, the opaque part inside its transparent margin.
  final Rect body;

  /// Corner radius of [body].
  final double radius;
  final BodyCorner corner;

  /// A radius of its own at each corner, where they differ — a foldable shut,
  /// square on its spine. Null for every body with one radius all round.
  final BorderRadius? radii;

  /// How far the body runs back from its face.
  final double depth;

  /// The band's colour: the finish the variant ships in.
  final Color finish;

  final List<SolidKey> keys;

  /// The front edge of the band, where the glass meets the metal.
  Path get outline => bodyOutline(body, radius, corner, radii: radii);

  @override
  bool operator ==(Object other) =>
      other is DeviceSolid &&
      other.body == body &&
      other.radius == radius &&
      other.corner == corner &&
      other.depth == depth &&
      other.finish == finish &&
      other.radii == radii &&
      _sameKeys(other.keys, keys);

  static bool _sameKeys(List<SolidKey> a, List<SolidKey> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    body,
    radius,
    corner,
    depth,
    finish,
    radii,
    Object.hashAll(keys),
  );
}

/// The solid [device] stands for, drawn [frameWidth] by [frameHeight] with
/// [depth] — or null for a frame that is not a slab.
///
/// [design] is the design the frame is actually drawn from: the placement's
/// own, or the catalog's for a dynamic handset, or null for artwork and the
/// drawn bodies. Resolving that is the caller's business, because the scene
/// already has.
///
/// Three kinds of frame keep their chassis in three different places, and
/// this is the one place that knows all of them: a built or dynamic body fills
/// its box edge to edge, traced artwork and a drawn iPhone sit inside the
/// transparent margin their keys stand in, and a drawn slab or tablet fills
/// its box with corners `ProgrammaticDeviceFrame` publishes. A laptop, a
/// monitor, an iMac and a browser window are none of these — a base, a stand
/// and a tab strip are not one outline pushed back — so they stay flat cards
/// when turned. The Frame panel asks the same question to know whether to
/// offer a depth at all.
DeviceSolid? deviceSolidFor({
  required FrameDevice device,
  required FrameVariant variant,
  required FrameDesign? design,
  required DepthSpec depth,
  required double frameWidth,
  required double frameHeight,
}) {
  if (frameWidth <= 0 || frameHeight <= 0) return null;
  final box = Offset.zero & Size(frameWidth, frameHeight);
  final ratio =
      (device.depthRatio ??
          (device.formFactor == 'tablet' ? kTabletDepth : kPhoneDepth)) *
      depth.thickness.clamp(0.0, 3.0);

  if (design != null) {
    return DeviceSolid(
      body: box,
      radius: frameWidth * design.cornerRadius.clamp(0.0, 0.5),
      corner: design.cornerStyle == CornerStyle.smooth
          ? BodyCorner.smooth
          : BodyCorner.round,
      depth: frameWidth * ratio,
      finish: design.color,
      radii: design.hinge.enabled ? design.outerRadii(frameWidth) : null,
      keys: [
        for (final spec in [design.power, design.volume])
          if (spec.enabled)
            for (var i = 0; i < spec.count; i++)
              SolidKey(
                side: spec.side == FrameSide.left
                    ? FrameSide.left
                    : FrameSide.right,
                onTop: spec.onTop,
                // Along the top edge a key is measured against the width.
                top:
                    (spec.onTop ? frameWidth : frameHeight) *
                    (spec.top + i * (spec.length + spec.gap)),
                length: (spec.onTop ? frameWidth : frameHeight) * spec.length,
                // A design's keys are drawn thicker than life on purpose, so
                // a flat sliver shows at preview size. A key with sides of its
                // own needs no help, and at full thickness stands out like a
                // tab.
                protrusion: frameWidth * spec.thickness * 0.6,
              ),
      ],
    );
  }

  // A drawn iPhone sits inside the same transparent margin its traced artwork
  // had, so its chassis is found the way artwork's is; its corner is the one
  // `DrawnIPhoneFrame` actually draws, rather than one derived back out of
  // the screen.
  if (drawnIPhoneFor(device.id) case final iphone?) {
    final b = device.bodyRect;
    final chassis = Rect.fromLTWH(
      b.x * frameWidth,
      b.y * frameHeight,
      b.w * frameWidth,
      b.h * frameHeight,
    );
    return DeviceSolid(
      body: chassis,
      radius: iphone.bodyRadiusShare * chassis.width,
      corner: BodyCorner.squircle,
      depth: chassis.width * ratio,
      finish: Color(variant.frameColor),
      keys: [
        for (final key in device.keys)
          SolidKey(
            side: key.side,
            top: key.top * frameHeight,
            length: key.length * frameHeight,
            protrusion: key.protrusion * frameWidth,
          ),
      ],
    );
  }

  if (variant.asset.isNotEmpty) {
    final b = device.bodyRect;
    final chassis = Rect.fromLTWH(
      b.x * frameWidth,
      b.y * frameHeight,
      b.w * frameWidth,
      b.h * frameHeight,
    );
    return DeviceSolid(
      body: chassis,
      // The radius the Build tab would give this device — the screen's own,
      // grown back out by the border round it — on the superellipse the
      // artwork is drawn with.
      radius:
          frameDesignForDevice(device, variant.id).cornerRadius * chassis.width,
      corner: BodyCorner.squircle,
      depth: chassis.width * ratio,
      finish: Color(variant.frameColor),
      keys: [
        for (final key in device.keys)
          SolidKey(
            side: key.side,
            top: key.top * frameHeight,
            length: key.length * frameHeight,
            protrusion: key.protrusion * frameWidth,
          ),
      ],
    );
  }

  final radius = ProgrammaticDeviceFrame.slabRadius(device.frameStyle);
  if (radius == null) return null;
  return DeviceSolid(
    body: box,
    radius: frameWidth * radius,
    corner: BodyCorner.round,
    depth: frameWidth * ratio,
    finish: Color(variant.frameColor),
    keys: [
      for (final key in ProgrammaticDeviceFrame.slabKeys(device.frameStyle))
        SolidKey(
          side: key.left ? FrameSide.left : FrameSide.right,
          onTop: key.onTop,
          top: (key.onTop ? frameWidth : frameHeight) * key.start,
          length: (key.onTop ? frameWidth : frameHeight) * key.length,
          protrusion: frameWidth * 0.005,
        ),
    ],
  );
}

/// The outline of a body [rect] with corners of [radius] turned as [corner] —
/// or of [radii], one per corner, where a body has them.
Path bodyOutline(
  Rect rect,
  double radius,
  BodyCorner corner, {
  BorderRadius? radii,
}) {
  if (radii != null && corner != BodyCorner.squircle) {
    return cornerShapeWith(
      corner == BodyCorner.smooth ? CornerStyle.smooth : CornerStyle.round,
      radii,
    ).getOuterPath(rect);
  }
  final r = radius.clamp(0.0, rect.shortestSide / 2);
  return switch (corner) {
    BodyCorner.round => cornerShape(CornerStyle.round, r).getOuterPath(rect),
    BodyCorner.smooth => cornerShape(CornerStyle.smooth, r).getOuterPath(rect),
    BodyCorner.squircle => _squircle(rect, r),
  };
}

/// A superellipse-cornered rectangle, clockwise from the top edge — the same
/// figure `squircle()` in `tool/frame_geometry.py` fits with cubics, here as a
/// fine polyline, which is all a sampler needs.
Path _squircle(Rect rect, double r) {
  const n = 2.5;
  const steps = 18;
  final path = Path();
  if (r <= 0.5) return path..addRect(rect);

  // A point on the corner at [vertex], whose body runs off along (sx, sy). At
  // theta 0 it sits on the vertical edge, at a quarter turn on the horizontal.
  Offset at(Offset vertex, double sx, double sy, double theta) {
    final px = r - r * math.pow(math.cos(theta).abs(), 2 / n);
    final py = r - r * math.pow(math.sin(theta).abs(), 2 / n);
    return Offset(vertex.dx + sx * px, vertex.dy + sy * py);
  }

  void corner(Offset vertex, double sx, double sy, {required bool rising}) {
    for (var i = 0; i <= steps; i++) {
      final f = rising ? i / steps : 1 - i / steps;
      final p = at(vertex, sx, sy, f * math.pi / 2);
      path.lineTo(p.dx, p.dy);
    }
  }

  path.moveTo(rect.left + r, rect.top);
  path.lineTo(rect.right - r, rect.top);
  corner(rect.topRight, -1, 1, rising: false);
  path.lineTo(rect.right, rect.bottom - r);
  corner(rect.bottomRight, -1, -1, rising: true);
  path.lineTo(rect.left + r, rect.bottom);
  corner(rect.bottomLeft, 1, -1, rising: false);
  path.lineTo(rect.left, rect.top + r);
  corner(rect.topLeft, 1, 1, rising: true);
  return path..close();
}

// -----------------------------------------------------------------------------
// Geometry
// -----------------------------------------------------------------------------

/// A 3-vector, as bare as the maths here needs. Private rather than
/// `vector_math`'s, which Flutter only re-exports `Matrix4` from.
class _V {
  const _V(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;

  _V get unit {
    final l = math.sqrt(x * x + y * y + z * z);
    return l == 0 ? this : _V(x / l, y / l, z / l);
  }
}

/// A turned device's projection, expressed so a point anywhere on the solid —
/// not just on its face — can be put on the page.
///
/// A `Transform` about the box's centre paints its child through
/// `T(c) · turn · T(-c)`, and a child point at z = 0 lands at the perspective
/// divide of that. The same product applied to a point with depth is where
/// that point of the solid lands: the face and its sides agree because they
/// share the matrix, the centre and the divide.
class _Projection {
  _Projection(Matrix4 turn, Size box)
    : _m = turn.storage,
      _c = Offset(box.width / 2, box.height / 2) {
    final k = _m[11];
    // Where the eye is, in the device's turned space: the point whose
    // perspective divide is zero. Head-on devices have no perspective at all,
    // and are seen from infinitely far down the axis.
    _eye = k.abs() < 1e-12 ? null : _V(0, 0, -1 / k);
  }

  final Float64List _m;
  final Offset _c;
  late final _V? _eye;

  /// [p] turned into the eye's space, centred on the box.
  _V world(_V p) {
    final x = p.x - _c.dx;
    final y = p.y - _c.dy;
    final z = p.z;
    return _V(
      _m[0] * x + _m[4] * y + _m[8] * z,
      _m[1] * x + _m[5] * y + _m[9] * z,
      _m[2] * x + _m[6] * y + _m[10] * z,
    );
  }

  /// A direction turned the same way — a normal. The turn's upper 3x3 is its
  /// rotation alone: the perspective sits in the fourth row.
  _V direction(_V d) => _V(
    _m[0] * d.x + _m[4] * d.y + _m[8] * d.z,
    _m[1] * d.x + _m[5] * d.y + _m[9] * d.z,
    _m[2] * d.x + _m[6] * d.y + _m[10] * d.z,
  ).unit;

  /// Where [p] lands on the page, in the frame box's coordinates.
  Offset project(_V p) {
    final x = p.x - _c.dx;
    final y = p.y - _c.dy;
    final z = p.z;
    final px = _m[0] * x + _m[4] * y + _m[8] * z + _m[12];
    final py = _m[1] * x + _m[5] * y + _m[9] * z + _m[13];
    var w = _m[3] * x + _m[7] * y + _m[11] * z + _m[15];
    // Nothing on a device held in front of the eye reaches the eye's own
    // plane; this only keeps a degenerate turn from dividing by zero.
    if (w < 1e-6) w = 1e-6;
    return Offset(px / w + _c.dx, py / w + _c.dy);
  }

  /// Which way to look from [worldPoint] to see the eye.
  _V toEye(_V worldPoint) {
    final eye = _eye;
    return eye == null ? const _V(0, 0, -1) : (eye - worldPoint).unit;
  }

  /// Whether a face at [worldPoint] with outward [worldNormal] faces the eye.
  bool faces(_V worldPoint, _V worldNormal) {
    final eye = _eye;
    final toward = eye == null ? const _V(0, 0, -1) : eye - worldPoint;
    return worldNormal.dot(toward) > 1e-9;
  }
}

/// One sample of a body's outline: where it is and which way is out.
class _Rim {
  const _Rim(this.at, this.out);

  final Offset at;
  final Offset out;
}

/// Samples round [outline], closely enough that a corner turns smoothly and
/// sparsely enough that a long straight edge is not a thousand quads.
///
/// Walks the path at a fine pitch and keeps a point whenever the direction has
/// swung a few degrees since the last one — which is every step on a corner —
/// or a long stretch has gone by without one, which is what gives a straight
/// edge vertices enough to carry a highlight partway along it.
List<_Rim> _sampleRim(Path outline) {
  final metrics = outline.computeMetrics().toList();
  if (metrics.isEmpty) return const [];
  final metric = metrics.reduce((a, b) => a.length >= b.length ? a : b);
  final length = metric.length;
  if (length <= 0) return const [];

  const fine = 900;
  final maxGap = length / 48;
  final raw = <(Offset, Offset)>[];
  for (var i = 0; i < fine; i++) {
    final t = metric.getTangentForOffset(length * i / fine);
    if (t == null) continue;
    raw.add((t.position, t.vector));
  }
  if (raw.length < 3) return const [];

  // Which way round the path runs decides which side of the tangent is out.
  var area = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final a = raw[i].$1;
    final b = raw[(i + 1) % raw.length].$1;
    area += a.dx * b.dy - b.dx * a.dy;
  }
  final sign = area >= 0 ? 1.0 : -1.0;

  final kept = <_Rim>[];
  Offset? lastDir;
  var travelled = 0.0;
  Offset? lastAt;
  for (final (at, dir) in raw) {
    if (lastAt != null) travelled += (at - lastAt).distance;
    lastAt = at;
    final turned = lastDir == null
        ? true
        : (dir.dx * lastDir.dx + dir.dy * lastDir.dy) < math.cos(0.07);
    if (!turned && travelled < maxGap) continue;
    kept.add(_Rim(at, Offset(dir.dy * sign, -dir.dx * sign)));
    lastDir = dir;
    travelled = 0;
  }
  return kept;
}

/// The convex hull of [points], counter-clockwise, by monotone chain.
List<Offset> _hull(List<Offset> points) {
  if (points.length < 3) return List.of(points);
  final sorted = List.of(
    points,
  )..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  final lower = <Offset>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

Path _polygon(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

// -----------------------------------------------------------------------------
// Light
// -----------------------------------------------------------------------------

/// The studio a device is lit in: a key light where [DepthSpec.light] says,
/// and a large soft box overhead leaning the same way, which is what a metal
/// band mostly shows — a band is a mirror more than it is a matte surface.
class _Studio {
  _Studio(double lightDeg) {
    final a = lightDeg.clamp(-90.0, 90.0) * math.pi / 180;
    // Up and round towards the viewer, never behind the device: a key light
    // behind it would leave the only side anyone can see in shadow.
    key = _V(math.sin(a) * 0.85, -math.cos(a) * 0.85, -0.9).unit;
    box = _V(math.sin(a) * 0.55, -1, -0.25).unit;
    // The side panels stand level with the device and a little behind it,
    // which is where a wall turned towards the viewer looks when it reflects.
    // A light overhead has no side, and lights both equally.
    final side = a.abs() < 0.2 ? 0.0 : a.sign;
    panel = _V(side == 0 ? -1 : side, -0.35, 0.15).unit;
    fill = _V(side == 0 ? 1 : -side, -0.35, 0.15).unit;
    shadowFall = Offset(-math.sin(a), math.cos(a));
  }

  late final _V key;
  late final _V box;
  late final _V panel;
  late final _V fill;

  /// Which way on the page a shadow falls: away from the key light.
  late final Offset shadowFall;
}

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The colour a patch of the band shows, facing [n] and seen along [toEye].
///
/// A metal: most of what it shows is the studio reflected in it, plus a hard
/// highlight where the key light glints. Diffuse light is only a small part of
/// it — which is why a band lit the same way as the face reads as painted
/// plastic.
///
/// The finish is what the manifest measured off the artwork's rail: its
/// *median* face, darker than the rail looks, because what makes a traced rail
/// read as titanium is the specular chamfer running along it. The reflections
/// here are what put that brightness back, so a band and the rail beside it on
/// the face come out as one material.
Color _metal(Color finish, _V n, _V toEye, _Studio studio, double shade) {
  final ndl = math.max(0.0, n.dot(studio.key));
  final half = (studio.key + toEye).unit;
  final ndh = math.max(0.0, n.dot(half));
  final ndv = n.dot(toEye);
  final reflected = n * (2 * ndv) - toEye;

  // Four lights, as the band sees them: the soft box overhead; a tall panel on
  // the key light's side that the long walls catch at a glance; a dimmer fill
  // opposite, so the side away from the light is shaded rather than black;
  // and the bright card behind the camera that every lip facing the viewer
  // turns into a highlight line — the same line the traced rails wear.
  final env =
      (_smooth(0.1, 0.95, reflected.dot(studio.box)) +
              0.85 * _smooth(0.3, 0.92, reflected.dot(studio.panel)) +
              0.3 * _smooth(0.3, 0.92, reflected.dot(studio.fill)) +
              0.7 * _smooth(0.55, 1.0, -reflected.z))
          .clamp(0.0, 1.3);

  // A dark anodised finish reflects less than a bare pale one; without this a
  // Black Titanium band washes out to the grey of a Natural one.
  final lum = 0.2126 * finish.r + 0.7152 * finish.g + 0.0722 * finish.b;
  final reflectivity = (0.5 + 0.45 * lum) * shade;
  final diffuse = (0.24 + 0.42 * ndl) * shade;
  final glint =
      0.9 * math.pow(ndh, 80).toDouble() + 0.22 * math.pow(ndh, 12).toDouble();

  double channel(double base) {
    // Reflections of white lights in a tinted metal: half the finish's own
    // colour, half the light's.
    final tint = base + (1 - base) * 0.5;
    return (base * diffuse +
            tint * env * 0.62 * reflectivity +
            (0.7 + 0.3 * base) * glint)
        .clamp(0.0, 1.0);
  }

  return Color.from(
    alpha: 1,
    red: channel(finish.r),
    green: channel(finish.g),
    blue: channel(finish.b),
  );
}

// -----------------------------------------------------------------------------
// The band's profile
// -----------------------------------------------------------------------------

/// Stations across the band, front (0) to back (1), closer at the lips where
/// the profile turns fastest.
const List<double> _kStations = [
  0.0,
  0.035,
  0.09,
  0.16,
  0.26,
  0.38,
  0.5,
  0.62,
  0.74,
  0.84,
  0.91,
  0.965,
  1.0,
];

/// How far the band's surface leans towards the front (negative) or the back
/// (positive) at [s], in radians.
///
/// A flat band with rounded lips — the shape of every current flagship's rail,
/// if not of any one exactly. The lean is shading only: the geometry stays a
/// straight prism, so the band's front edge is the face's own outline and the
/// two cannot open a gap between them.
double _profile(double s) {
  const lip = 0.3;
  const lean = 72 * math.pi / 180;
  if (s < lip) return -lean * math.pow(1 - s / lip, 1.6).toDouble();
  if (s > 1 - lip) {
    return lean * math.pow((s - (1 - lip)) / lip, 1.6).toDouble();
  }
  return 0;
}

// -----------------------------------------------------------------------------
// The painter
// -----------------------------------------------------------------------------

/// Paints what is behind a turned device's face: the shadow it casts, the band
/// round its sides and the keys on that band.
///
/// Laid out in the device's own frame box, in the same stack as the `Transform`
/// that draws the face, and painted first. Nothing it paints falls inside the
/// face's own projection except the shadow and a thin underlay that the face
/// covers, so the face needs no clipping to sit on top.
class DeviceSolidPainter extends CustomPainter {
  DeviceSolidPainter({
    required this.solid,
    required this.transform,
    required this.frameSize,
    required this.lightDeg,
    this.shadow,
    this.shadowBlurScale = 1,
  });

  final DeviceSolid solid;

  /// The device's placement transform, and the box it is laid out in. The
  /// turn is rebuilt from these with [deviceTurn], the same call the face's
  /// `Transform` makes.
  final Transform2D transform;
  final Size frameSize;
  final double lightDeg;

  /// The drop shadow to cast, or null for none.
  final ShadowSpec? shadow;

  /// What a shadow's blur, stated in pixels at a 1179-wide canvas, is
  /// multiplied by here — the scene's rule for every blur.
  final double shadowBlurScale;

  late final _Projection _projection = _Projection(
    deviceTurn(transform, frameSize.height),
    frameSize,
  );

  late final _Studio _studio = _Studio(lightDeg);

  late final List<_Rim> _rim = _sampleRim(solid.outline);

  /// The front and back rims, projected.
  late final List<Offset> _front = [
    for (final r in _rim) _projection.project(_V(r.at.dx, r.at.dy, 0)),
  ];
  late final List<Offset> _back = [
    for (final r in _rim)
      _projection.project(_V(r.at.dx, r.at.dy, solid.depth)),
  ];

  /// The whole solid's outline on the page: where it can be touched, and the
  /// shape of the shadow it casts.
  late final List<Offset> _silhouette = _hull([..._front, ..._back]);

  @override
  void paint(Canvas canvas, Size size) {
    if (_rim.length < 3 || solid.depth <= 0) return;

    _paintShadow(canvas);

    // Which stretches of the band face the eye. A quad of a convex prism's
    // side either faces the viewer or is hidden behind the rest of the body,
    // so the band is visible exactly where its flat face would be.
    final count = _rim.length;
    final visible = List<bool>.filled(count, false);
    var any = false;
    for (var i = 0; i < count; i++) {
      final a = _rim[i];
      final b = _rim[(i + 1) % count];
      final mid = Offset.lerp(a.at, b.at, 0.5)!;
      final out = a.out + b.out;
      final centre = _projection.world(_V(mid.dx, mid.dy, solid.depth / 2));
      final normal = _projection.direction(_V(out.dx, out.dy, 0));
      visible[i] = _projection.faces(centre, normal);
      any = any || visible[i];
    }

    if (any) _paintBand(canvas, visible);
    _paintKeys(canvas);
  }

  void _paintShadow(Canvas canvas) {
    final spec = shadow;
    if (spec == null || spec.opacity <= 0 || _silhouette.length < 3) return;
    // Stated like the flat shadow — a fraction of the frame, a blur in pixels
    // at a 1179-wide canvas — and then pushed away from the key light by a
    // share of the body's depth, so a solid lit from the left drops its shadow
    // to the right the way the band's shading says it should.
    final fall = _studio.shadowFall * (solid.depth * 0.45);
    final offset =
        Offset(
          spec.offsetPct.dx * frameSize.width,
          spec.offsetPct.dy * frameSize.height,
        ) +
        fall;
    final blur = spec.blur * shadowBlurScale;
    canvas.drawPath(
      _polygon(_silhouette).shift(offset),
      Paint()
        ..color = spec.color.withValues(alpha: spec.opacity.clamp(0.0, 1.0))
        ..maskFilter = blur > 0
            ? MaskFilter.blur(
                BlurStyle.normal,
                Shadow.convertRadiusToSigma(blur),
              )
            : null,
    );
  }

  void _paintBand(Canvas canvas, List<bool> visible) {
    final count = _rim.length;
    final stations = _kStations.length;

    final positions = Float32List(count * stations * 2);
    final colors = Int32List(count * stations);
    var r = 0.0, g = 0.0, b = 0.0;
    var lit = 0;

    for (var i = 0; i < count; i++) {
      final rim = _rim[i];
      for (var j = 0; j < stations; j++) {
        final s = _kStations[j];
        final z = s * solid.depth;
        final local = _V(rim.at.dx, rim.at.dy, z);
        final at = _projection.project(local);
        final k = i * stations + j;
        positions[k * 2] = at.dx;
        positions[k * 2 + 1] = at.dy;

        final lean = _profile(s);
        final normal = _projection.direction(
          _V(
            rim.out.dx * math.cos(lean),
            rim.out.dy * math.cos(lean),
            math.sin(lean),
          ),
        );
        final toEye = _projection.toEye(_projection.world(local));
        // The back lip sits in the seam with the back glass and never catches
        // quite the light the front one does.
        final colour = _metal(
          solid.finish,
          normal,
          toEye,
          _studio,
          1 - 0.16 * s,
        );
        colors[k] = colour.toARGB32();
        if (visible[i] || visible[(i - 1 + count) % count]) {
          r += colour.r;
          g += colour.g;
          b += colour.b;
          lit++;
        }
      }
    }

    final indices = <int>[];
    for (var i = 0; i < count; i++) {
      if (!visible[i]) continue;
      final next = (i + 1) % count;
      for (var j = 0; j < stations - 1; j++) {
        final a = i * stations + j;
        final bb = next * stations + j;
        indices
          ..addAll([a, bb, bb + 1])
          ..addAll([a, bb + 1, a + 1]);
      }
    }
    if (indices.isEmpty) return;

    // An anti-aliased underlay first. A mesh of triangles is filled without
    // anti-aliasing, so its outer edge would step pixel by pixel against the
    // page; laid over a smooth silhouette in the band's own average tone, the
    // steps land on colour that matches them. The face's middle is cut out —
    // it covers the underlay's inner edge, and a screenshot with any
    // transparency in it must still show what it always showed through it.
    if (lit > 0 && _silhouette.length >= 3) {
      final inner = _inset(_front, solid.body.width * 0.01);
      final underlay = _polygon(_silhouette)
        ..addPath(_polygon(inner), Offset.zero)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        underlay,
        Paint()
          ..color = Color.from(
            alpha: 1,
            red: r / lit,
            green: g / lit,
            blue: b / lit,
          ),
      );
    }

    // Sixteen-bit indices always suffice: the rim is sampled at most 900
    // times (see `_sampleRim`), which is under twelve thousand vertices.
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: Uint16List.fromList(indices),
    );
    // `dst` keeps the vertex colours whatever the paint is: with no shader on
    // the paint that is what both Skia and Impeller draw regardless, and
    // naming it means a later shader on this paint could not silently tint
    // the band.
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  /// [polygon] pulled in by [by] towards its own centre.
  List<Offset> _inset(List<Offset> polygon, double by) {
    if (polygon.isEmpty) return polygon;
    var cx = 0.0, cy = 0.0;
    for (final p in polygon) {
      cx += p.dx;
      cy += p.dy;
    }
    final centre = Offset(cx / polygon.length, cy / polygon.length);
    return [
      for (final p in polygon)
        () {
          final d = p - centre;
          final l = d.distance;
          return l <= by ? centre : p - d * (by / l);
        }(),
    ];
  }

  void _paintKeys(Canvas canvas) {
    if (solid.keys.isEmpty) return;
    final body = solid.body;
    // A key rides the middle of the band and is a little over a third of its
    // depth — about what an iPhone's 2.8 mm keys are on an 8.25 mm body.
    final front = solid.depth * 0.32;
    final back = solid.depth * 0.68;

    for (final key in solid.keys) {
      final left = key.side == FrameSide.left;
      // Built in the key's own axes — across the wall, then along it — and
      // laid on the top wall by swapping the two, so a key on the top is the
      // same six faces as one on a side.
      _V v(double across, double along, double z) =>
          key.onTop ? _V(along, across, z) : _V(across, along, z);
      // Sunk a little into the band so no seam of page shows between them.
      final base = key.onTop ? body.top : (left ? body.left : body.right);
      final outward = key.onTop || left ? -1.0 : 1.0;
      final inner = base - outward * key.protrusion * 0.4;
      final outer = base + outward * key.protrusion;
      final top = key.top;
      final bottom = key.top + key.length;

      // The key's six faces as corner lists, each with its outward normal.
      final faces = <(List<_V>, _V)>[
        // Outer face — the one that reads as the key.
        (
          [
            v(outer, top, front),
            v(outer, bottom, front),
            v(outer, bottom, back),
            v(outer, top, back),
          ],
          v(outward, 0, 0),
        ),
        // Front and back.
        (
          [
            v(inner, top, front),
            v(outer, top, front),
            v(outer, bottom, front),
            v(inner, bottom, front),
          ],
          v(0, 0, -1),
        ),
        (
          [
            v(inner, top, back),
            v(outer, top, back),
            v(outer, bottom, back),
            v(inner, bottom, back),
          ],
          v(0, 0, 1),
        ),
        // Ends.
        (
          [
            v(inner, top, front),
            v(outer, top, front),
            v(outer, top, back),
            v(inner, top, back),
          ],
          v(0, -1, 0),
        ),
        (
          [
            v(inner, bottom, front),
            v(outer, bottom, front),
            v(outer, bottom, back),
            v(inner, bottom, back),
          ],
          v(0, 1, 0),
        ),
      ];

      for (final (corners, localNormal) in faces) {
        var centre = const _V(0, 0, 0);
        for (final c in corners) {
          centre = centre + c;
        }
        centre = centre * (1 / corners.length);
        final worldCentre = _projection.world(centre);
        final normal = _projection.direction(localNormal);
        if (!_projection.faces(worldCentre, normal)) continue;

        final toEye = _projection.toEye(worldCentre);
        final projected = [for (final c in corners) _projection.project(c)];
        final paint = Paint();
        if (identical(corners, faces.first.$1)) {
          // The outer face is rounded across, like the key it is: shaded from
          // its front edge to its back through normals leaning the way the
          // band's own lips do, so it catches the same highlight lines.
          Color at(double lean) => _metal(
            solid.finish,
            _projection.direction(
              v(outward * math.cos(lean), 0, math.sin(lean)),
            ),
            toEye,
            _studio,
            1,
          );
          // Across the key, square to its front edge. Under perspective the
          // midpoints of its front and back edges sit at different heights,
          // and a gradient aimed from one to the other lays its bands
          // diagonally across a key only a few pixels wide.
          final from = Offset.lerp(projected[0], projected[1], 0.5)!;
          final back = Offset.lerp(projected[2], projected[3], 0.5)!;
          final edge = projected[1] - projected[0];
          final along = edge.distance == 0 ? Offset.zero : edge / edge.distance;
          final span = back - from;
          final to =
              from + span - along * (span.dx * along.dx + span.dy * along.dy);
          if ((to - from).distance > 0.01) {
            paint.shader = ui.Gradient.linear(
              from,
              to,
              [at(-1.1), at(-0.45), at(0), at(0.45), at(1.1)],
              const [0.0, 0.22, 0.5, 0.78, 1.0],
            );
          } else {
            paint.color = at(0);
          }
        } else {
          // The ends and the lips, which are narrow and turned away from
          // most of the studio: the band's material, a shade down.
          paint.color = _metal(solid.finish, normal, toEye, _studio, 0.85);
        }
        canvas.drawPath(_polygon(projected), paint);
      }
    }
  }

  @override
  bool? hitTest(Offset position) =>
      _silhouette.length >= 3 && _polygon(_silhouette).contains(position);

  @override
  bool shouldRepaint(DeviceSolidPainter old) =>
      old.solid != solid ||
      old.transform.tiltX != transform.tiltX ||
      old.transform.tiltY != transform.tiltY ||
      old.transform.rotationDeg != transform.rotationDeg ||
      old.frameSize != frameSize ||
      old.lightDeg != lightDeg ||
      old.shadowBlurScale != shadowBlurScale ||
      !_sameShadow(old.shadow, shadow);

  static bool _sameShadow(ShadowSpec? a, ShadowSpec? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.opacity == b.opacity &&
          a.color == b.color &&
          a.blur == b.blur &&
          a.offsetPct == b.offsetPct);
}

// -----------------------------------------------------------------------------
// Glare
// -----------------------------------------------------------------------------

/// The studio reflected in a device's glass, painted over its face.
///
/// A window's worth of light laid across the glass as a streak: one broad band
/// and a thin one beside it, running corner to corner at a steep diagonal that
/// rises away from the key light. That is what a softbox reads as in a
/// product shot, and it is the reflection people recognise — a soft wash over
/// the whole screen, which is what physically-shaded glass gives, reads as a
/// dirty screen instead.
///
/// Laid out *inside* the face's `Transform`, in the face's own flat
/// coordinates, so it turns and foreshortens with the glass for free. Where it
/// falls is the part the transform cannot give: that follows which way the
/// glass faces, so tipping the device back or turning it towards the light
/// slides the streak across the screen, the way a window slides across a phone
/// tipped in the hand.
///
/// Unlike the band this is drawn head-on too: glass reflects whether or not
/// the device is turned.
class GlassGlarePainter extends CustomPainter {
  GlassGlarePainter({
    required this.transform,
    required this.frameSize,
    required this.outline,
    required this.lightDeg,
    required this.strength,
  });

  final Transform2D transform;
  final Size frameSize;

  /// The face, in the frame box's own pixels — where the glass is.
  final Path outline;
  final double lightDeg;

  /// [DepthSpec.glare], 0 to 1.
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final bounds = outline.getBounds();
    if (bounds.isEmpty) return;

    // Which way the glass faces once turned: (0, 0, -1) head-on.
    final glass = _Projection(
      deviceTurn(transform, frameSize.height),
      frameSize,
    ).direction(const _V(0, 0, -1));
    final a = lightDeg.clamp(-90.0, 90.0) * math.pi / 180;

    // The streak's axis, from the corner nearest the light to the far one;
    // its bands lie square across it.
    final axis = a <= 0 ? const Offset(0.82, 0.57) : const Offset(-0.82, 0.57);
    final reach =
        (bounds.width * axis.dx.abs() + bounds.height * axis.dy.abs()) / 2;
    final start = bounds.center - axis * reach;
    final end = bounds.center + axis * reach;

    // Where along that axis the broad band sits, 0 at the near corner: a
    // third of the way in head-on, sliding on as the glass tips back (up is
    // negative y) or turns towards the light, and off the glass entirely
    // before the device is turned far enough to stop reflecting the studio.
    final centre = 0.3 - glass.y * 0.95 + glass.x * math.sin(a) * 1.15;
    final thinCentre = centre + 0.24;

    double alphaAt(double t) {
      final broad =
          _smooth(centre - 0.2, centre - 0.12, t) *
          (1 - _smooth(centre + 0.12, centre + 0.2, t));
      final d = (t - thinCentre) / 0.016;
      final thin = math.exp(-d * d);
      // A faint wash nearest the light, so the glass between the bands still
      // reads as glass rather than as nothing.
      final wash = 0.2 * math.pow(1 - t.clamp(0.0, 1.0), 2).toDouble();
      return (0.34 * broad + 0.22 * thin + 0.12 * wash) * strength;
    }

    // Sampled rather than keyed: the bands slide off either end of the axis,
    // and a gradient's stops cannot run outside it.
    const samples = 120;
    final stops = [for (var i = 0; i <= samples; i++) i / samples];
    final colors = [
      for (final t in stops)
        Color.from(
          alpha: alphaAt(t).clamp(0.0, 1.0),
          red: 1,
          green: 1,
          blue: 1,
        ),
    ];

    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(
      bounds,
      Paint()..shader = ui.Gradient.linear(start, end, colors, stops),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassGlarePainter old) =>
      old.transform.tiltX != transform.tiltX ||
      old.transform.tiltY != transform.tiltY ||
      old.transform.rotationDeg != transform.rotationDeg ||
      old.frameSize != frameSize ||
      old.lightDeg != lightDeg ||
      old.strength != strength ||
      old.outline.getBounds() != outline.getBounds();
}
