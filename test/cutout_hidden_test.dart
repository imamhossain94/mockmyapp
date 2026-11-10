// Taking the camera off a frame — see `FramePlacement.cutoutHidden`.
//
// Three painters draw a camera and each takes it off differently, which is the
// whole risk here: a switch that works on a built frame and silently does
// nothing on a traced one is worse than no switch. So every path is checked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';
import 'package:mockmyapp/features/editor/widgets/drawn_iphone_frame.dart';

const _shot = ColoredBox(color: Color(0xFF3355FF));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  group('the catalog can say where every camera is', () {
    test('every device that declares a camera has one to switch off', () {
      // `hasCutout` is what puts the control on screen. A device that declares
      // a punch hole but cannot answer where it is would show a switch that
      // does nothing — which is exactly what happened to the iPhone 17 Pro Max
      // while its island was hidden from the measuring pass by a sheen.
      for (final device in catalog.devices) {
        if (device.cutout == 'none') {
          expect(device.hasCutout, isFalse, reason: device.id);
          continue;
        }
        expect(device.hasCutout, isTrue, reason: device.id);
        if (!device.isProgrammatic) {
          expect(
            device.cutoutRect,
            isNotNull,
            reason: '${device.id} draws a camera nothing can locate',
          );
        }
      }
    });
  });

  group('the patch that covers a traced camera', () {
    /// The clip in aperture coordinates, at a frame [width] wide.
    Rect clipFor(FrameDevice device, double width) {
      final height = width / device.frameAspect;
      final screen = device.screenRect;
      final clipper = CutoutPatchClipper(
        cutout: device.cutoutRect!,
        screen: screen,
        frameWidth: width,
        frameHeight: height,
      );
      return clipper.getClip(Size(screen.w * width, screen.h * height));
    }

    test('covers the whole island on every traced device', () {
      for (final device in catalog.artworkDevices) {
        if (device.cutoutRect == null) continue;
        const width = 1200.0;
        final height = width / device.frameAspect;
        final screen = device.screenRect;
        final cutout = device.cutoutRect!;
        final clip = clipFor(device, width);

        // The island, in the same aperture coordinates.
        final island = Rect.fromLTWH(
          (cutout.x - screen.x) * width,
          (cutout.y - screen.y) * height,
          cutout.w * width,
          cutout.h * height,
        );
        expect(
          clip.contains(island.topLeft) && clip.contains(island.bottomRight),
          isTrue,
          reason: '${device.id}: $clip does not cover $island',
        );
        // And wider than it, or the anti-aliased rim of the hole survives.
        expect(clip.width, greaterThan(island.width), reason: device.id);
      }
    });

    test('never paints outside the aperture', () {
      // A notch hangs off the top border, so an unclamped patch would spill
      // screenshot over the bezel above the screen.
      for (final device in catalog.artworkDevices) {
        if (device.cutoutRect == null) continue;
        const width = 1200.0;
        final height = width / device.frameAspect;
        final screen = device.screenRect;
        final aperture = Rect.fromLTWH(
          0,
          0,
          screen.w * width,
          screen.h * height,
        );
        final clip = clipFor(device, width);

        expect(aperture.contains(clip.topLeft), isTrue, reason: device.id);
        expect(
          clip.right,
          lessThanOrEqualTo(aperture.right + 0.001),
          reason: device.id,
        );
        expect(
          clip.bottom,
          lessThanOrEqualTo(aperture.bottom + 0.001),
          reason: device.id,
        );
      }
    });

    test('scales with the frame, so an export matches the editor', () {
      final device = catalog.byId('apple-iphone-16-pro');
      final small = clipFor(device, 300);
      final large = clipFor(device, 1200);
      expect(large.left / small.left, closeTo(4, 0.001));
      expect(large.width / small.width, closeTo(4, 0.001));
    });
  });

  group('the scene actually stops drawing it', () {
    Future<void> pumpScene(
      WidgetTester tester,
      FramePlacement placement,
    ) async {
      final doc = ScreenDoc(
        id: 'test',
        canvas: const Size(600, 1200),
        background: const SolidBackground(Color(0xFFFFFFFF)),
        frames: [placement],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: SceneView(doc: doc, catalog: catalog),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final patchFinder = find.byWidgetPredicate(
      (w) => w is ClipRect && w.clipper is CutoutPatchClipper,
    );

    testWidgets('a traced frame gains a patch only when asked', (tester) async {
      const base = FramePlacement(
        deviceId: 'google-pixel-9-pro',
        variantId: 'obsidian',
      );

      await pumpScene(tester, base);
      expect(patchFinder, findsNothing);

      await pumpScene(tester, base.copyWith(cutoutHidden: true));
      expect(patchFinder, findsOneWidget);
    });

    testWidgets('a drawn iPhone drops its island without a patch', (
      tester,
    ) async {
      // Drawn, so there is nothing in any pixels to cover: the frame simply
      // stops drawing the island.
      const base = FramePlacement(
        deviceId: 'apple-iphone-16-pro',
        variantId: '16-pro---black-titanium',
      );

      await pumpScene(tester, base);
      var frame = tester.widget<DrawnIPhoneFrame>(
        find.byType(DrawnIPhoneFrame),
      );
      expect(frame.showCutout, isTrue);

      await pumpScene(tester, base.copyWith(cutoutHidden: true));
      frame = tester.widget<DrawnIPhoneFrame>(find.byType(DrawnIPhoneFrame));
      expect(frame.showCutout, isFalse);
      expect(patchFinder, findsNothing);
    });

    testWidgets('a hidden frame draws no patch', (tester) async {
      // Nothing is covering anything when there is no artwork on screen.
      await pumpScene(
        tester,
        const FramePlacement(
          deviceId: 'apple-iphone-16-pro',
          variantId: '16-pro---black-titanium',
          cutoutHidden: true,
          frameHidden: true,
        ),
      );
      expect(patchFinder, findsNothing);
    });

    testWidgets('a dynamic handset drops its island', (tester) async {
      // These are drawn by `CustomDeviceFrame` from a catalog design the user
      // has never edited, so there is no `punchHole` of theirs to switch off —
      // the placement's flag is the only thing that can reach them.
      const base = FramePlacement(
        deviceId: StudioFrameIds.iphone17ProMax,
        variantId: 'deep-blue',
      );

      await pumpScene(tester, base);
      var frame = tester.widget<CustomDeviceFrame>(
        find.byType(CustomDeviceFrame),
      );
      expect(frame.showCutout, isTrue);
      expect(frame.design.punchHole.enabled, isTrue);

      await pumpScene(tester, base.copyWith(cutoutHidden: true));
      frame = tester.widget<CustomDeviceFrame>(find.byType(CustomDeviceFrame));
      expect(frame.showCutout, isFalse);
    });
  });

  group('CustomDeviceFrame', () {
    testWidgets('draws no camera when the placement says not to', (
      tester,
    ) async {
      const design = FrameDesign(
        punchHole: PunchHoleSpec(enabled: true, width: 0.25, height: 0.08),
      );

      Future<int> holesAt({required bool showCutout}) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: CustomDeviceFrame(
                frameWidth: 300,
                frameHeight: 600,
                design: design,
                screenshot: _shot,
                showCutout: showCutout,
              ),
            ),
          ),
        );
        return tester
            .widgetList<Container>(find.byType(Container))
            .where(
              (c) =>
                  (c.decoration as BoxDecoration?)?.color ==
                  design.punchHole.color,
            )
            .length;
      }

      expect(await holesAt(showCutout: true), 1);
      expect(await holesAt(showCutout: false), 0);
    });
  });

  group('the setting is part of the document', () {
    test('survives a save and a reload', () {
      const placement = FramePlacement(
        deviceId: 'apple-iphone-16-pro',
        variantId: '16-pro---black-titanium',
        cutoutHidden: true,
      );
      final reloaded = framePlacementFromJson(framePlacementToJson(placement));
      expect(reloaded.cutoutHidden, isTrue);
    });

    test('a project written before it existed keeps its camera', () {
      final json = framePlacementToJson(
        const FramePlacement(deviceId: 'a', variantId: 'b'),
      )..remove('cutoutHidden');
      expect(framePlacementFromJson(json).cutoutHidden, isFalse);
    });
  });
}
