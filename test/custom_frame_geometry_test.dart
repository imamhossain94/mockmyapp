import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';

/// Mounts a built frame at a known size and reports where the screen lands.
Future<Rect> _screenRect(WidgetTester tester, FrameDesign design) async {
  const key = ValueKey('screen');
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: CustomDeviceFrame(
          frameWidth: 300,
          frameHeight: 600,
          design: design,
          // A keyed marker standing in for the screenshot: it fills the screen
          // area, so its rect *is* the screen's rect.
          screenshot: const ColoredBox(key: key, color: Color(0xFFFFFFFF)),
        ),
      ),
    ),
  );
  await tester.pump();

  final frame = tester.getRect(find.byType(CustomDeviceFrame));
  final screen = tester.getRect(find.byKey(key));
  // Relative to the frame's own box, so the numbers are the insets.
  return Rect.fromLTRB(
    screen.left - frame.left,
    screen.top - frame.top,
    frame.right - screen.right,
    frame.bottom - screen.bottom,
  );
}

void main() {
  group('built frame insets', () {
    testWidgets('the chin is the bottom inset, independent of the sides', (
      tester,
    ) async {
      // 300px wide frame: thickness 0.02 is 6px a side, chin 0.1 is 30px.
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0.02, bottomThickness: 0.1),
      );

      expect(insets.left, closeTo(6, 0.01));
      expect(insets.right, closeTo(6, 0.01));
      expect(insets.top, closeTo(6, 0.01));
      expect(insets.bottom, closeTo(30, 0.01));
    });

    testWidgets('the forehead is the top inset, independent of the sides', (
      tester,
    ) async {
      // 300px wide frame: thickness 0.02 is 6px a side, top 0.09 is 27px.
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0.02, topThickness: 0.09),
      );

      expect(insets.left, closeTo(6, 0.01));
      expect(insets.right, closeTo(6, 0.01));
      expect(insets.top, closeTo(27, 0.01));
      expect(insets.bottom, closeTo(6, 0.01), reason: 'chin follows the sides');
    });

    testWidgets('all three edges can differ at once', (tester) async {
      final insets = await _screenRect(
        tester,
        const FrameDesign(
          thickness: 0.02,
          topThickness: 0.09,
          bottomThickness: 0.1,
        ),
      );

      expect(insets.left, closeTo(6, 0.01));
      expect(insets.right, closeTo(6, 0.01));
      expect(insets.top, closeTo(27, 0.01));
      expect(insets.bottom, closeTo(30, 0.01));
    });

    testWidgets('a design that sets only the sides stays even all round', (
      tester,
    ) async {
      // Every frame built before the top and bottom could differ is this one,
      // and it has to keep looking exactly as it did.
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0.03),
      );

      expect(insets.left, closeTo(9, 0.01));
      expect(insets.right, closeTo(9, 0.01));
      expect(insets.top, closeTo(9, 0.01));
      expect(insets.bottom, closeTo(9, 0.01));
    });

    testWidgets('a zero forehead leaves no top inset at all', (tester) async {
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0.02, topThickness: 0),
      );

      expect(insets.top, closeTo(0, 0.01));
      expect(insets.left, closeTo(6, 0.01));
    });

    testWidgets('a zero chin leaves no bottom inset at all', (tester) async {
      // The reported bug: dragging Chin to nothing still left a band.
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0.02, bottomThickness: 0),
      );

      expect(insets.bottom, closeTo(0, 0.01));
      expect(insets.left, closeTo(6, 0.01));
    });

    testWidgets('a zero chin leaves no band with smooth corners either', (
      tester,
    ) async {
      // Corner style must not change the insets — an over-rounded clip eats
      // the bottom of the screen and reads exactly like a chin that will not
      // go away.
      final insets = await _screenRect(
        tester,
        const FrameDesign(
          thickness: 0.02,
          bottomThickness: 0,
          cornerStyle: CornerStyle.smooth,
        ),
      );

      expect(insets.bottom, closeTo(0, 0.01));
      expect(insets.top, closeTo(6, 0.01));
    });

    testWidgets('frameless leaves the screen the whole box', (tester) async {
      final insets = await _screenRect(
        tester,
        const FrameDesign(thickness: 0, bottomThickness: 0, rimWidth: 0),
      );

      expect(insets.left, closeTo(0, 0.01));
      expect(insets.top, closeTo(0, 0.01));
      expect(insets.right, closeTo(0, 0.01));
      expect(insets.bottom, closeTo(0, 0.01));
    });
  });
}
