import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';

/// A built frame is a metal rail with a black display border inside it, not one
/// slab of `design.color`.
///
/// This is what a device actually looks like — a white phone has a white rail
/// and a black bezel — and it is the difference the traced artwork has always
/// drawn and the built frame did not, which is why "Adjust this frame" used to
/// turn a phone into a flat plastic rectangle. The whole point is only visible
/// on a PALE finish: with a black body the old flat fill and the new border
/// were the same colour, so a test on a dark frame would pass either way.
void main() {
  const white = Color(0xFFFFFFFF);
  const screenshotColour = Color(0xFF3355FF);

  /// The frame rasterised, as a pixel reader.
  Future<ui.Image> render(
    WidgetTester tester,
    FrameDesign design, {
    double width = 400,
    double height = 800,
  }) async {
    final key = GlobalKey();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width + 40, height + 40);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: CustomDeviceFrame(
              frameWidth: width,
              frameHeight: height,
              design: design,
              screenshot: const ColoredBox(color: screenshotColour),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    late ui.Image image;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      image = await boundary.toImage();
    });
    return image;
  }

  Future<List<int>> pixel(ui.Image image, int x, int y) async {
    late List<int> rgb;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final at = (y * image.width + x) * 4;
    rgb = [bytes[at], bytes[at + 1], bytes[at + 2]];
    return rgb;
  }

  testWidgets('a pale frame wears a dark display border, not a pale one', (
    tester,
  ) async {
    // Sides of 0.06 x 400 = 24px, of which the rail takes 45% = 10.8px. So
    // x=4 is rail and x=18 is the border between the rail and the aperture.
    const design = FrameDesign(
      thickness: 0.06,
      topThickness: 0.06,
      bottomThickness: 0.06,
      cornerRadius: 0.08,
      color: white,
      aspect: 0.5,
    );

    final image = await render(tester, design);
    late List<int> rail;
    late List<int> border;
    late List<int> screen;
    await tester.runAsync(() async {
      rail = await pixel(image, 4, 400);
      border = await pixel(image, 18, 400);
      screen = await pixel(image, 200, 400);
      image.dispose();
    });

    // The rail carries the finish.
    expect(
      rail.reduce((a, b) => a + b) / 3,
      greaterThan(140),
      reason: 'rail should carry the white finish, got $rail',
    );
    // The display border is near-black regardless of the finish.
    expect(
      border.reduce((a, b) => a + b) / 3,
      lessThan(40),
      reason: 'display border should be near-black, got $border',
    );
    // And the screenshot is untouched in the middle.
    expect(screen[2], greaterThan(screen[0]), reason: 'blue screenshot');
  });

  testWidgets('the rail is lit rather than flat', (tester) async {
    // The chamfer runs bright at the outer edge into shadow further in, which
    // is the whole of why the rail reads as metal. A flat fill would make these
    // two samples identical.
    const design = FrameDesign(
      thickness: 0.09,
      topThickness: 0.09,
      bottomThickness: 0.09,
      cornerRadius: 0.08,
      color: Color(0xFF3E5074),
      aspect: 0.5,
    );

    // Rendered large on purpose: the chamfer's bands are fractions of a rail
    // that is itself a fraction of the body, so at a few hundred pixels the lit
    // edge and the groove behind it are a pixel each and the sample lands on
    // whichever one antialiasing felt like.
    final image = await render(tester, design, width: 1200, height: 2400);
    late List<int> outer;
    late List<int> groove;
    await tester.runAsync(() async {
      // Rail is 0.09 x 1200 x 0.45 = 48.6px. The lit edge is its first 9%
      // (0-4.4px) and the groove the next 13% (4.4-10.7px); the outer 1.9px is
      // the silhouette contour, so the lit sample sits just inside it.
      outer = await pixel(image, 3, 1200);
      groove = await pixel(image, 7, 1200);
      image.dispose();
    });

    expect(
      outer.reduce((a, b) => a + b),
      greaterThan(groove.reduce((a, b) => a + b)),
      reason: 'outer edge $outer should be lit against the groove $groove',
    );
  });

  testWidgets('a flat rim is its colour edge to edge, with no hardware', (
    tester,
  ) async {
    // Store art that frames its shots in a plain white rim — Gesture Volume's
    // listing does — has no rail, no display border and no outline, and the
    // hardware drawn over such a rim made it a different, heavier mockup.
    // Sides of 0.06 x 400 = 24px: on a phone x=18 is the black border.
    const design = FrameDesign(
      thickness: 0.06,
      cornerRadius: 0.08,
      color: white,
      aspect: 0.5,
      flat: true,
    );

    final image = await render(tester, design);
    late List<int> edge;
    late List<int> inner;
    late List<int> bottom;
    late List<int> screen;
    await tester.runAsync(() async {
      edge = await pixel(image, 1, 400);
      inner = await pixel(image, 18, 400);
      bottom = await pixel(image, 200, 790);
      screen = await pixel(image, 200, 400);
      image.dispose();
    });

    for (final (name, rgb) in [
      ('outer edge', edge),
      ('where the border would be', inner),
      ('the foot, where the finish would shade', bottom),
    ]) {
      expect(rgb, [255, 255, 255], reason: '$name should be the rim colour');
    }
    expect(screen[2], greaterThan(screen[0]), reason: 'blue screenshot');
  });
}
