import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../domain/engine/device_depth.dart';
import '../../../domain/models/screen_doc.dart';

/// A camera angle worth a single tap: a tilt, a turn and a spin in the page.
///
/// All three, because an angle is one idea. A phone lying on a table seen from
/// above is a lean back *and* a quarter-turn in the page, and a preset that set
/// only the lean would leave whatever spin the device happened to have.
@immutable
class DeviceAngle {
  const DeviceAngle(
    this.label, {
    this.tiltX = 0,
    this.tiltY = 0,
    this.rotation = 0,
  });

  final String label;
  final double tiltX;
  final double tiltY;
  final double rotation;

  /// Whether [t] is this angle, to within what a slider can land on.
  bool matches(Transform2D t) =>
      (t.tiltX - tiltX).abs() < 0.5 &&
      (t.tiltY - tiltY).abs() < 0.5 &&
      (t.rotationDeg - rotation).abs() < 0.5;
}

/// The angles store listings actually use.
///
/// Named for what the tile shows rather than for which way the maths turns:
/// *Left* is the left side of the phone coming into view — the side an
/// iPhone's volume keys are on — not the screen facing left.
const kDeviceAngles = [
  DeviceAngle('Front'),
  DeviceAngle('Left', tiltY: -28),
  DeviceAngle('Right', tiltY: 28),
  DeviceAngle('Lean back', tiltX: 22),
  DeviceAngle('Hero', tiltX: 10, tiltY: -30, rotation: -5),
  DeviceAngle('Swing', tiltX: 10, tiltY: 30, rotation: 5),
  DeviceAngle('Flat lay', tiltX: 52, rotation: 38),
  DeviceAngle('Float', tiltX: -14, tiltY: 22, rotation: 8),
];

/// How far the Tilt and Turn controls reach, either way.
///
/// Past 45 degrees a flat card stops reading as a screen, which is where the
/// old sliders stopped. A body with sides reads as a phone much further round,
/// and a phone lying on a table — the flat lay — needs more than 45 to lie
/// down.
const double kMaxTilt = 60;

/// A small phone drawn at [angle], for a preset tile.
///
/// The real solid painter over a two-tone face, so the tile is the angle the
/// canvas will show rather than an icon that suggests it. Chrome, not content:
/// its colours are the caller's tokens.
class DeviceAngleGlyph extends StatelessWidget {
  const DeviceAngleGlyph({
    super.key,
    required this.angle,
    required this.body,
    required this.screen,
    this.size = const Size(22, 46),
  });

  final DeviceAngle angle;
  final Color body;
  final Color screen;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final t = Transform2D(
      tiltX: angle.tiltX,
      tiltY: angle.tiltY,
      rotationDeg: angle.rotation,
    );
    final radius = size.width * 0.2;
    final solid = DeviceSolid(
      body: Offset.zero & size,
      radius: radius,
      corner: BodyCorner.round,
      // Deeper than life: at twenty pixels across a real phone's band is under
      // a pixel, and the tile's whole job is to show the turn.
      depth: size.width * kPhoneDepth * 2.4,
      finish: body,
    );

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DeviceSolidPainter(
                solid: solid,
                transform: t,
                frameSize: size,
                lightDeg: -40,
              ),
            ),
          ),
          // Pinned to the glyph's box: a bare decoration in a stack sizes to
          // its child, and a face with no child is a dot.
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              transform: deviceTurn(t, size.height),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: body,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Padding(
                  padding: EdgeInsets.all(size.width * 0.09),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: screen,
                      borderRadius: BorderRadius.circular(radius * 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One preset angle: the phone drawn at it, and its name.
class DeviceAngleTile extends StatefulWidget {
  const DeviceAngleTile({
    super.key,
    required this.angle,
    required this.selected,
    required this.onTap,
  });

  final DeviceAngle angle;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<DeviceAngleTile> createState() => _DeviceAngleTileState();
}

class _DeviceAngleTileState extends State<DeviceAngleTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final selected = widget.selected;

    // On the well, which reads against both the panel and a sheet's overlay,
    // and lit up on the rim rather than by a change of fill — a fill that
    // brightens to the surface it sits on disappears into it.
    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.angle.label} angle',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: Container(
            width: 64,
            height: 78,
            decoration: BoxDecoration(
              color: s.well,
              borderRadius: BorderRadius.circular(StudioRadius.md),
              border: Border.all(
                color: selected
                    ? s.accent
                    : (_hover ? s.borderStrong : s.borderSubtle),
                width: selected ? 2 : 1,
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xs,
              StudioSpace.m,
              StudioSpace.xs,
              StudioSpace.xs,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ExcludeSemantics(
                      child: DeviceAngleGlyph(
                        angle: widget.angle,
                        body: selected ? s.accent : s.textSecondary,
                        screen: s.panelAlt,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: StudioSpace.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.angle.label,
                    maxLines: 1,
                    style: StudioText.micro(context).copyWith(
                      color: selected ? s.textPrimary : s.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pad to aim the screen with: drag the knob, and the screen faces where it
/// sits.
///
/// One gesture for two numbers. The Tilt and Turn sliders set an angle one
/// axis at a time, which is right for dialling in a figure and wrong for
/// finding a pose — nobody holds a phone up to the light by turning it about
/// one axis and then the other.
///
/// The knob is the direction the glass faces, as if a stick came straight out
/// of the screen: push it right and the screen turns to face right, which is
/// what brings the phone's *left* side into view. Up faces the screen up, which
/// is the device leaning back. The centre snaps, with a tick, and a double tap
/// returns it there.
class OrbitPad extends StatefulWidget {
  const OrbitPad({
    super.key,
    required this.tiltX,
    required this.tiltY,
    required this.onChanged,
    this.range = kMaxTilt,
    this.maxSide = 176,
  });

  final double tiltX;
  final double tiltY;

  /// Fires continuously while dragging, with the new tilt and turn.
  final void Function(double tiltX, double tiltY) onChanged;

  /// The angle at the pad's edge, either way.
  final double range;

  /// The largest the pad draws; it takes the available width below that.
  final double maxSide;

  @override
  State<OrbitPad> createState() => _OrbitPadState();
}

class _OrbitPadState extends State<OrbitPad> {
  /// Within this share of the pad's half-width of the middle, the knob sits
  /// dead centre.
  static const _snap = 0.07;

  bool _centred = true;
  bool _dragging = false;

  Offset get _knob => Offset(
    (-widget.tiltY / widget.range).clamp(-1.0, 1.0),
    (-widget.tiltX / widget.range).clamp(-1.0, 1.0),
  );

  void _aim(Offset local, double side) {
    var u = Offset(
      (local.dx / side * 2 - 1).clamp(-1.0, 1.0),
      (local.dy / side * 2 - 1).clamp(-1.0, 1.0),
    );
    final centred = u.distance < _snap;
    if (centred) u = Offset.zero;
    if (centred && !_centred) HapticFeedback.selectionClick();
    _centred = centred;

    double round(double v) => (v * 2).roundToDouble() / 2;
    widget.onChanged(
      round(-u.dy * widget.range) + 0.0,
      round(-u.dx * widget.range) + 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, widget.maxSide);
        return Semantics(
          label: 'Aim the screen',
          value:
              'Tilt ${widget.tiltX.round()} degrees, '
              'turn ${widget.tiltY.round()} degrees',
          hint: 'Drag to turn the device. Double tap to face it forward.',
          child: MouseRegion(
            cursor: _dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                setState(() => _dragging = true);
                _aim(d.localPosition, side);
              },
              onPanUpdate: (d) => _aim(d.localPosition, side),
              onPanEnd: (_) => setState(() => _dragging = false),
              onPanCancel: () => setState(() => _dragging = false),
              onTapUp: (d) => _aim(d.localPosition, side),
              onDoubleTap: () {
                HapticFeedback.selectionClick();
                _centred = true;
                widget.onChanged(0, 0);
              },
              child: SizedBox.square(
                dimension: side,
                child: CustomPaint(
                  painter: _OrbitPadPainter(
                    knob: _knob,
                    well: s.well,
                    rule: s.borderSubtle,
                    ring: s.border,
                    accent: s.accent,
                    onAccent: s.onAccent,
                    active: _dragging,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbitPadPainter extends CustomPainter {
  const _OrbitPadPainter({
    required this.knob,
    required this.well,
    required this.rule,
    required this.ring,
    required this.accent,
    required this.onAccent,
    required this.active,
  });

  /// The knob, -1 to 1 on each axis.
  final Offset knob;
  final Color well;
  final Color rule;
  final Color ring;
  final Color accent;
  final Color onAccent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final half = size.width / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(StudioRadius.lg)),
      Paint()..color = well,
    );

    final hairline = Paint()
      ..color = rule
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        Offset(centre.dx, StudioSpace.m),
        Offset(centre.dx, size.height - StudioSpace.m),
        hairline,
      )
      ..drawLine(
        Offset(StudioSpace.m, centre.dy),
        Offset(size.width - StudioSpace.m, centre.dy),
        hairline,
      );
    // Rings at a third and two thirds of the reach: 20 and 40 degrees at the
    // default range, which is where most listings' angles live.
    final rings = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in const [1 / 3, 2 / 3]) {
      canvas.drawCircle(centre, (half - StudioSpace.m) * r, rings);
    }

    final at = centre + Offset(knob.dx, knob.dy) * (half - StudioSpace.l);
    canvas.drawLine(
      centre,
      at,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas
      ..drawCircle(
        at,
        active ? 11 : 9,
        Paint()..color = accent.withValues(alpha: 0.22),
      )
      ..drawCircle(at, 7, Paint()..color = accent)
      ..drawCircle(at, 2.5, Paint()..color = onAccent);
  }

  @override
  bool shouldRepaint(_OrbitPadPainter old) =>
      old.knob != knob ||
      old.well != well ||
      old.rule != rule ||
      old.ring != ring ||
      old.accent != accent ||
      old.onAccent != onAccent ||
      old.active != active;
}
