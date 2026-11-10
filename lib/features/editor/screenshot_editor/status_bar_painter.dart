import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'screenshot_edit_ops.dart' show NavBarStyle, StatusBarStyle;

/// Draws a tidy phone status bar into [bar]: the time on the left, and full
/// signal, Wi-Fi and a full battery on the right — laid out the way an iPhone,
/// a stock Android phone or a Samsung phone lays its own out.
///
/// Every glyph is a path sized from the bar's height, so the same call draws
/// the editor's preview and the full-resolution export, and nothing depends on
/// an icon font that might not have loaded. The shapes are generic — a clock,
/// bars, arcs and a battery — rather than any one maker's artwork.
void paintCleanStatusBar(
  Canvas canvas,
  Rect bar, {
  required StatusBarStyle style,
  required Color background,
  required Color foreground,
  String time = '9:41',
}) {
  if (bar.isEmpty) return;
  canvas.save();
  canvas.clipRect(bar);
  canvas.drawRect(bar, Paint()..color = background);

  final h = bar.height;
  // The glyphs sit in the middle band of the bar, which is where a phone
  // draws them whatever its bar height.
  final mid = bar.top + h * 0.52;
  final unit = h * 0.3;
  final ink = Paint()
    ..color = foreground
    ..isAntiAlias = true;

  final isIos = style == StatusBarStyle.ios;
  final isSamsung = style == StatusBarStyle.samsung;
  final margin = bar.width * (isIos ? 0.085 : 0.05);

  // --- the time --------------------------------------------------------------
  final clock = TextPainter(
    text: TextSpan(
      text: time,
      style: TextStyle(
        color: foreground,
        fontSize: h * (isIos ? 0.36 : (isSamsung ? 0.31 : 0.33)),
        fontWeight: isIos || isSamsung ? FontWeight.w600 : FontWeight.w500,
        letterSpacing: 0,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final clockLeft = isIos
      // An iPhone centres its clock in the space left of the camera.
      ? bar.left + bar.width * 0.22 - clock.width / 2
      : bar.left + margin;
  clock.paint(canvas, Offset(clockLeft, mid - clock.height / 2));
  clock.dispose();

  // --- right-hand cluster, laid out from the right edge inwards --------------
  var x = bar.right - margin;

  // Battery.
  final batteryWidth = unit * (isIos ? 2.35 : (isSamsung ? 2.1 : 1.15));
  final batteryHeight = unit * (isIos ? 1.1 : (isSamsung ? 1.05 : 1.9));
  final battery = Rect.fromLTWH(
    x - batteryWidth,
    mid - batteryHeight / 2,
    batteryWidth,
    batteryHeight,
  );
  if (isIos) {
    final radius = Radius.circular(batteryHeight * 0.32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(battery, radius),
      Paint()
        ..color = foreground.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(battery.deflate(unit * 0.17), radius * 0.6),
      ink,
    );
    // The terminal.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          battery.right + unit * 0.08,
          mid - batteryHeight * 0.18,
          unit * 0.12,
          batteryHeight * 0.36,
        ),
        Radius.circular(unit * 0.06),
      ),
      ink..color = foreground.withValues(alpha: 0.4),
    );
    ink.color = foreground;
  } else if (isSamsung) {
    // A solid body lying down, its terminal to the right, and the charge
    // written out beside it.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          battery.left,
          battery.top,
          batteryWidth - unit * 0.18,
          batteryHeight,
        ),
        Radius.circular(batteryHeight * 0.3),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          battery.right - unit * 0.14,
          mid - batteryHeight * 0.2,
          unit * 0.14,
          batteryHeight * 0.4,
        ),
        Radius.circular(unit * 0.05),
      ),
      ink,
    );
    final charge = TextPainter(
      text: TextSpan(
        text: '100%',
        style: TextStyle(
          color: foreground,
          fontSize: h * 0.25,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    charge.paint(
      canvas,
      Offset(battery.left - unit * 0.3 - charge.width, mid - charge.height / 2),
    );
    x = battery.left - unit * 0.3 - charge.width;
    charge.dispose();
  } else {
    final body = Rect.fromLTWH(
      battery.left,
      battery.top + batteryHeight * 0.1,
      batteryWidth,
      batteryHeight * 0.9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(unit * 0.16)),
      ink,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        body.center.dx - batteryWidth * 0.22,
        battery.top,
        batteryWidth * 0.44,
        batteryHeight * 0.12,
      ),
      ink,
    );
  }
  x = (isSamsung ? x : battery.left) - unit * (isIos ? 0.55 : 0.6);

  // Wi-Fi: a fan of three arcs over a dot, the widest at the top.
  final wifiRadius = unit * 1.15;
  final wifiCentre = Offset(x - wifiRadius, mid + wifiRadius * 0.55);
  final sweep = math.pi / 2;
  final start = -math.pi / 2 - sweep / 2;
  final stroke = Paint()
    ..color = foreground
    ..style = PaintingStyle.stroke
    ..strokeWidth = unit * 0.26
    ..strokeCap = StrokeCap.round;
  for (final r in [0.95, 0.62]) {
    canvas.drawArc(
      Rect.fromCircle(center: wifiCentre, radius: wifiRadius * r),
      start,
      sweep,
      false,
      stroke,
    );
  }
  canvas.drawPath(
    Path()
      ..moveTo(wifiCentre.dx, wifiCentre.dy)
      ..arcTo(
        Rect.fromCircle(center: wifiCentre, radius: wifiRadius * 0.32),
        start,
        sweep,
        false,
      )
      ..close(),
    ink,
  );
  x = wifiCentre.dx - wifiRadius - unit * 0.55;

  // Signal.
  if (isIos || isSamsung) {
    // Four bars rising left to right — narrower and taller on a Samsung.
    final barWidth = unit * (isSamsung ? 0.26 : 0.36);
    final gap = unit * (isSamsung ? 0.16 : 0.2);
    final tallest = unit * (isSamsung ? 1.35 : 1.15);
    for (var i = 3; i >= 0; i--) {
      final barHeight = tallest * (0.4 + 0.2 * i);
      final left = x - (4 - i) * barWidth - (3 - i) * gap;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            mid + tallest / 2 - barHeight,
            barWidth,
            barHeight,
          ),
          Radius.circular(barWidth * 0.3),
        ),
        ink,
      );
    }
  } else {
    // A filled wedge.
    final size = unit * 1.6;
    canvas.drawPath(
      Path()
        ..moveTo(x, mid - size / 2)
        ..lineTo(x, mid + size / 2)
        ..lineTo(x - size, mid + size / 2)
        ..close(),
      ink,
    );
  }

  canvas.restore();
}

/// Draws a phone's navigation into [bar]: a gesture handle, a home indicator,
/// or three buttons.
///
/// A transparent [background] draws the handle straight over the picture,
/// which is how an iPhone's home indicator sits — its screenshots have none,
/// and the app runs to the bottom edge under it.
///
/// Like the status bar, every glyph is a generic path sized from the bar, so
/// preview and export are the same drawing at two scales.
void paintCleanNavBar(
  Canvas canvas,
  Rect bar, {
  required NavBarStyle style,
  required Color background,
  required Color foreground,
}) {
  if (bar.isEmpty) return;
  canvas.save();
  canvas.clipRect(bar);
  if (background.a > 0) canvas.drawRect(bar, Paint()..color = background);

  final w = bar.width, h = bar.height;
  final mid = bar.center.dy;
  final ink = Paint()
    ..color = foreground
    ..isAntiAlias = true;

  void pill(Offset centre, double width, double thickness) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: width, height: thickness),
      Radius.circular(thickness / 2),
    ),
    ink,
  );

  // The three buttons' glyphs share a size and a line.
  final glyph = h * 0.34;
  final line = Paint()
    ..color = foreground
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, glyph * 0.13)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final left = Offset(bar.left + w * 0.22, mid);
  final centre = Offset(bar.center.dx, mid);
  final right = Offset(bar.left + w * 0.78, mid);

  switch (style) {
    case NavBarStyle.gesture:
      pill(bar.center, w * 0.26, math.max(1.5, h * 0.17));
    case NavBarStyle.ios:
      // Low in the bar rather than in its middle, the way the indicator sits
      // just off the bottom edge.
      pill(
        Offset(bar.center.dx, bar.bottom - h * 0.31),
        w * 0.34,
        math.max(1.5, h * 0.15),
      );
    case NavBarStyle.buttons:
      // Back: a triangle pointing left.
      canvas.drawPath(
        Path()
          ..moveTo(left.dx - glyph * 0.5, mid)
          ..lineTo(left.dx + glyph * 0.4, mid - glyph * 0.55)
          ..lineTo(left.dx + glyph * 0.4, mid + glyph * 0.55)
          ..close(),
        line,
      );
      // Home: a circle.
      canvas.drawCircle(centre, glyph * 0.55, line);
      // Recent apps: a square.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: right, width: glyph, height: glyph),
          Radius.circular(glyph * 0.12),
        ),
        line,
      );
    case NavBarStyle.samsung:
      // Recent apps: three upright lines.
      for (final dx in [-0.36, 0.0, 0.36]) {
        canvas.drawLine(
          left + Offset(dx * glyph, -glyph * 0.45),
          left + Offset(dx * glyph, glyph * 0.45),
          line,
        );
      }
      // Home: a rounded square.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: centre,
            width: glyph * 1.05,
            height: glyph * 1.05,
          ),
          Radius.circular(glyph * 0.32),
        ),
        line,
      );
      // Back: a chevron pointing left.
      canvas.drawPath(
        Path()
          ..moveTo(right.dx + glyph * 0.22, mid - glyph * 0.5)
          ..lineTo(right.dx - glyph * 0.28, mid)
          ..lineTo(right.dx + glyph * 0.22, mid + glyph * 0.5),
        line,
      );
  }
  canvas.restore();
}
