import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';
import 'package:mockmyapp/features/editor/widgets/programmatic_frame.dart';

/// A stand-in for the user's screenshot.
///
/// Keyed rather than found by type: the bodies build plenty of `ColoredBox`es
/// of their own — every `Container` with a bare colour is one — so searching by
/// type would sometimes measure a window button instead of the artwork.
const _shotKey = ValueKey('screenshot');
const _shot = ColoredBox(key: _shotKey, color: Color(0xFF3355FF));

void main() {
  final devices = studioSurfaceDevices();

  /// Pumps [device] at [width], laid out the way `SceneView` lays it out.
  ///
  /// The surface is grown to the frame first. A 2880px export is far larger
  /// than the default 800x600 test window, and a frame that merely ran off the
  /// edge of that window would report an overflow that says nothing about the
  /// frame.
  Future<void> pumpFrame(
    WidgetTester tester,
    FrameDevice device,
    FrameVariant variant,
    double width,
  ) async {
    final height = width / device.frameAspect;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width + 8, height + 8);
    addTearDown(tester.view.reset);

    // Routed the way `SceneView` routes: a device that ships its own
    // `FrameDesign` is drawn by `CustomDeviceFrame`, everything else by a
    // `ProgrammaticDeviceFrame` body. Testing both through one widget would
    // test a path the app never takes.
    final design = studioDesignFor(device.id, variant.id);
    final Widget frame = design != null
        ? CustomDeviceFrame(
            frameWidth: width,
            frameHeight: height,
            design: design,
            screenshot: _shot,
          )
        : ProgrammaticDeviceFrame(
            frameWidth: width,
            frameHeight: height,
            frameColor: Color(variant.frameColor),
            cutout: device.cutout,
            style: device.frameStyle,
            variantId: variant.id,
            screenshot: _shot,
          );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: width, height: height, child: frame),
        ),
      ),
    );
  }

  group('every drawn body renders', () {
    // The same widget serves an 88px picker tile and a 2880px export, so both
    // ends of that range have to lay out without overflowing. A frame that
    // overflows in a test is a frame with a black-and-yellow stripe baked into
    // the user's exported PNG.
    for (final width in const [88.0, 320.0, 2880.0]) {
      testWidgets('at ${width.round()}px', (tester) async {
        for (final device in devices) {
          for (final variant in device.variants) {
            await pumpFrame(tester, device, variant, width);
            expect(
              tester.takeException(),
              isNull,
              reason: '${device.id}/${variant.id} at $width',
            );
            expect(
              find.byKey(_shotKey),
              findsOneWidget,
              reason: '${device.id}/${variant.id} composites its screenshot',
            );
          }
        }
      });
    }
  });

  group('the screenshot lands in the declared aperture', () {
    // The load-bearing property. `SceneView` puts the drop shadow behind the
    // frame at `screenRect` and rounds the screenshot by
    // `cornerRadiusPct * screenRect.w * frameWidth`, both computed from the
    // catalog's declaration rather than from anything the painter did. If a
    // painter's bezel disagrees, the shadow sits off the body and no other test
    // in the suite would notice.
    for (final device in studioSurfaceDevices()) {
      testWidgets(device.id, (tester) async {
        const width = 600.0;
        final height = width / device.frameAspect;
        await pumpFrame(tester, device, device.variants.first, width);

        final frameRect = tester.getRect(find.byType(SizedBox).first);
        final shot = tester.getRect(find.byKey(_shotKey));

        final expected = Rect.fromLTWH(
          frameRect.left + device.screenRect.x * width,
          frameRect.top + device.screenRect.y * height,
          device.screenRect.w * width,
          device.screenRect.h * height,
        );

        // A pixel of slack: the painters round through Padding and ClipRRect,
        // and sub-pixel disagreement is invisible. Anything larger is a bezel
        // that does not match its own metric.
        expect(shot.left, closeTo(expected.left, 1.0), reason: 'left');
        expect(shot.top, closeTo(expected.top, 1.0), reason: 'top');
        expect(shot.width, closeTo(expected.width, 1.0), reason: 'width');
        expect(shot.height, closeTo(expected.height, 1.0), reason: 'height');
      });
    }
  });

  group('the browser reads its platform off the variant', () {
    testWidgets('a Windows window is not a macOS one', (tester) async {
      final browser = devices.firstWhere(
        (d) => d.id == StudioFrameIds.browserWindows,
      );
      await pumpFrame(tester, browser, browser.variants.first, 600);
      // The macOS treatment paints three coloured circles; the Windows one
      // paints monochrome caption strokes. Neither of the traffic-light colours
      // should appear anywhere in a Windows window.
      final decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .toSet();
      expect(decorations, isNot(contains(const Color(0xFFFF5F57))));
      expect(decorations, isNot(contains(const Color(0xFF28C840))));
    });

    testWidgets('a macOS window has its traffic lights', (tester) async {
      final browser = devices.firstWhere(
        (d) => d.id == StudioFrameIds.browserMac,
      );
      await pumpFrame(tester, browser, browser.variants.first, 600);
      final colors = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .toSet();
      expect(colors, contains(const Color(0xFFFF5F57)));
      expect(colors, contains(const Color(0xFFFEBC2E)));
      expect(colors, contains(const Color(0xFF28C840)));
    });
  });
}
