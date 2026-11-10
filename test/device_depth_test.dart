import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/device_depth.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// Where a `Transform` about the centre of a [box] puts [local] — exactly what
/// the device's face goes through in `SceneView`.
Offset _face(Transform2D t, Size box, Offset local) {
  final centre = Matrix4.translationValues(box.width / 2, box.height / 2, 0)
    ..multiply(deviceTurn(t, box.height))
    ..multiply(Matrix4.translationValues(-box.width / 2, -box.height / 2, 0));
  return MatrixUtils.transformPoint(centre, local);
}

DeviceSolid _slab(Size box) => DeviceSolid(
  body: Offset.zero & box,
  radius: box.width * 0.1,
  corner: BodyCorner.round,
  depth: box.width * kPhoneDepth,
  finish: const Color(0xFF6B6B70),
);

DeviceSolidPainter _painter(Transform2D t, Size box) => DeviceSolidPainter(
  solid: _slab(box),
  transform: t,
  frameSize: box,
  lightDeg: -40,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sides meet the face', () {
    const box = Size(300, 620);

    // The whole feature rests on this: the band is projected by hand and the
    // face by a `Transform`, and they only line up if both see the same
    // matrix, centre and divide. A band that slid out from under its face
    // would show as a strip of metal beside the phone rather than round it.
    for (final t in const [
      Transform2D(tiltY: 30),
      Transform2D(tiltY: -30),
      Transform2D(tiltX: 24),
      Transform2D(tiltX: 10, tiltY: -30, rotationDeg: -5),
      Transform2D(tiltX: 52, rotationDeg: 38),
    ]) {
      test('at tilt ${t.tiltX} turn ${t.tiltY} spin ${t.rotationDeg}', () {
        final painter = _painter(t, box);
        // The face's rim — each edge's midpoint and each rounded corner, a
        // hair inside — lies inside the solid's silhouette. On the side turned
        // away the face's edge *is* the silhouette, which is why the points
        // are pulled in rather than sat on it.
        final r = box.width * 0.1;
        for (final rim in [
          Offset(box.width / 2, 2),
          Offset(box.width - 2, box.height / 2),
          Offset(box.width / 2, box.height - 2),
          Offset(2, box.height / 2),
          Offset(r * 0.4, r * 0.4),
          Offset(box.width - r * 0.4, r * 0.4),
          Offset(box.width - r * 0.4, box.height - r * 0.4),
          Offset(r * 0.4, box.height - r * 0.4),
        ]) {
          final at = _face(t, box, rim);
          expect(painter.hitTest(at), isTrue, reason: 'face rim at $rim');
        }
      });
    }

    test('a turned device shows the side that came towards the viewer', () {
      // Positive turn brings the right edge forward: its side is in view, and
      // the left one is behind the face.
      const t = Transform2D(tiltY: 30);
      final painter = _painter(t, box);
      final mid = box.height / 2;
      final right = _face(t, box, Offset(box.width, mid));
      final left = _face(t, box, Offset(0, mid));

      expect(painter.hitTest(right + const Offset(6, 0)), isTrue);
      expect(painter.hitTest(left - const Offset(3, 0)), isFalse);
    });

    test('the sides hide again when the device faces the viewer', () {
      // Head-on there is no perspective to show them. The painter is never
      // mounted for a flat device, but it must agree that there is nothing to
      // draw: the silhouette is the face and not a pixel more.
      const t = Transform2D();
      final painter = _painter(t, box);
      expect(painter.hitTest(Offset(box.width + 2, box.height / 2)), isFalse);
      expect(painter.hitTest(Offset(box.width - 2, box.height / 2)), isTrue);
    });
  });

  group('deviceSolidFor', () {
    late FrameCatalog catalog;
    setUpAll(() async => catalog = await loadFrameCatalog());

    DeviceSolid? solidOf(String id) {
      final device = catalog.byId(id);
      final variant = device.variants.first;
      return deviceSolidFor(
        device: device,
        variant: variant,
        // Resolved the way the scene resolves it. "Build your own" is never
        // drawn without a design of the user's, so it is given the default.
        design:
            studioDesignFor(device.id, variant.id) ??
            (device.frameStyle == 'custom' ? const FrameDesign() : null),
        depth: const DepthSpec(),
        frameWidth: 300,
        frameHeight: 300 / device.frameAspect,
      );
    }

    test('every handset and tablet is a slab', () {
      for (final device in catalog.devices) {
        if (device.formFactor == 'desktop') continue;
        expect(solidOf(device.id), isNotNull, reason: device.id);
      }
    });

    test('a laptop, a monitor and a browser stay flat cards', () {
      for (final id in [
        StudioFrameIds.macbook,
        StudioFrameIds.imac,
        StudioFrameIds.monitorApple,
        StudioFrameIds.browserMac,
      ]) {
        expect(solidOf(id), isNull, reason: id);
      }
    });

    test('a traced chassis sits inside its artwork margin', () {
      final device = catalog.byId('apple-iphone-16-pro');
      final solid = solidOf(device.id)!;
      final box = Size(300, 300 / device.frameAspect);
      expect(solid.body.left, closeTo(device.bodyRect.x * box.width, 1e-6));
      expect(solid.body.width, closeTo(device.bodyRect.w * box.width, 1e-6));
      expect(solid.corner, BodyCorner.squircle);
      // An iPhone is about 11% as deep as it is wide.
      expect(solid.depth / solid.body.width, closeTo(kPhoneDepth, 1e-9));
    });

    test('a tablet is a quarter as deep as a phone', () {
      final tablet = solidOf(StudioFrameIds.ipad)!;
      expect(tablet.depth / tablet.body.width, closeTo(kTabletDepth, 1e-9));
    });

    test('the depth multiplier scales the body and flat takes it away', () {
      final device = catalog.byId('apple-iphone-16-pro');
      DeviceSolid at(double thickness) => deviceSolidFor(
        device: device,
        variant: device.variants.first,
        design: null,
        depth: DepthSpec(thickness: thickness),
        frameWidth: 300,
        frameHeight: 600,
      )!;
      expect(at(2).depth, closeTo(at(1).depth * 2, 1e-9));
      expect(at(0).depth, 0);
      expect(const DepthSpec(thickness: 0).isFlat, isTrue);
    });

    test(
      'a built frame wears its own keys, a traced one its measured keys',
      () {
        final dynamic = solidOf(StudioFrameIds.iphone17ProMax)!;
        // Power on the right, a two-key volume rocker on the left.
        expect(
          dynamic.keys.where((k) => k.side == FrameSide.left),
          hasLength(2),
        );
        expect(
          dynamic.keys.where((k) => k.side == FrameSide.right),
          hasLength(1),
        );

        final traced = solidOf('apple-iphone-16-pro')!;
        expect(traced.keys, isNotEmpty);
        expect(
          traced.keys.length,
          catalog.byId('apple-iphone-16-pro').keys.length,
        );
      },
    );
  });

  group('measured keys', () {
    test(
      'every traced handset has keys, on its edges, standing a little proud',
      () async {
        final catalog = await loadFrameCatalog();
        for (final device in catalog.artworkDevices) {
          expect(device.keys, isNotEmpty, reason: device.id);
          for (final key in device.keys) {
            final body = device.bodyRect;
            expect(key.top, greaterThanOrEqualTo(body.y), reason: device.id);
            expect(
              key.top + key.length,
              lessThanOrEqualTo(body.y + body.h),
              reason: device.id,
            );
            // A key is a sliver: a few millimetres out of a seventy-wide body.
            expect(
              key.protrusion,
              inExclusiveRange(0, 0.02),
              reason: device.id,
            );
            expect(key.length, inExclusiveRange(0.01, 0.2), reason: device.id);
          }
        }
      },
    );

    test(
      'an iPhone keeps its volume on the left and a Pixel on the right',
      () async {
        final catalog = await loadFrameCatalog();
        final iphone = catalog.byId('apple-iphone-16-pro');
        expect(
          iphone.keys.where((k) => k.side == FrameSide.left),
          hasLength(3),
        );
        final pixel = catalog.byId('google-pixel-9-pro');
        expect(pixel.keys.every((k) => k.side == FrameSide.right), isTrue);
      },
    );
  });

  group('depth round-trips', () {
    test('a device left at life size writes no depth', () {
      const placement = FramePlacement(deviceId: 'a', variantId: 'b');
      expect(framePlacementToJson(placement).containsKey('depth'), isFalse);
    });

    test('a changed depth comes back as it went', () {
      const placement = FramePlacement(
        deviceId: 'a',
        variantId: 'b',
        transform: Transform2D(tiltY: 30),
        depth: DepthSpec(thickness: 1.4, light: 35, glare: 0.3),
      );
      final back = framePlacementFromJson(
        jsonDecode(jsonEncode(framePlacementToJson(placement)))
            as Map<String, dynamic>,
      );
      expect(back.depth, placement.depth);
      expect(back.transform.tiltY, 30);
    });

    test('a file missing a field keeps that field at its default', () {
      final depth = depthFromJson(const {'glare': 0.5});
      expect(depth, const DepthSpec(glare: 0.5));
    });
  });

  group('in the scene', () {
    /// The rasterised scene's pixel at ([x], [y]) of its canvas.
    Future<Color> pixelAt(
      WidgetTester tester,
      ScreenDoc doc,
      FrameCatalog catalog,
      Offset at,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SceneRenderer.captureStage(
              boundaryKey: key,
              doc: doc,
              catalog: catalog,
            ),
          ),
        ),
      );
      await tester.pump();

      late Color colour;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        // The stage lays out at a quarter of the canvas; four brings it back.
        final image = await boundary.toImage(pixelRatio: 4);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final o = (at.dy.round() * image.width + at.dx.round()) * 4;
        image.dispose();
        final rgba = data!.buffer.asUint8List();
        colour = Color.fromARGB(rgba[o + 3], rgba[o], rgba[o + 1], rgba[o + 2]);
      });
      return colour;
    }

    testWidgets('a turned slab paints its side, a flat one does not', (
      tester,
    ) async {
      final catalog = (await tester.runAsync(loadFrameCatalog))!;
      const page = Color(0xFFFFFFFF);
      const canvas = Size(400, 800);

      ScreenDoc docWith(Transform2D t) => ScreenDoc(
        id: 'd',
        canvas: canvas,
        background: const SolidBackground(page),
        frames: [
          FramePlacement(
            deviceId: 'studio-slab-ios',
            variantId: 'ink',
            transform: t.copyWith(pagePercentage: 0.7),
            screenshot: const ScreenshotSpec(
              fill: SolidBackground(Color(0xFF3355FF)),
            ),
            shadow: null,
          ),
        ],
      );

      final frameHeight = canvas.height * 0.7;
      final frameWidth =
          frameHeight * catalog.byId('studio-slab-ios').frameAspect;
      final box = Size(frameWidth, frameHeight);
      final origin = Offset(
        (canvas.width - frameWidth) / 2,
        (canvas.height - frameHeight) / 2,
      );
      const turned = Transform2D(tiltY: 30);
      Offset beside(Transform2D t, double x, double by) =>
          origin + _face(t, box, Offset(x, frameHeight / 2)) + Offset(by, 0);

      // Just past a flat device's right edge there is only the page.
      final flat = await pixelAt(
        tester,
        docWith(const Transform2D()),
        catalog,
        beside(const Transform2D(), frameWidth, 5),
      );
      expect(flat, page, reason: 'nothing beside a flat device');

      // Turned to bring its right side forward, the band is there instead —
      // opaque, with nothing of the page showing through it…
      final side = await pixelAt(
        tester,
        docWith(turned),
        catalog,
        beside(turned, frameWidth, 5),
      );
      expect(side, isNot(page), reason: 'the band beside a turned one');
      expect(side.a, 1.0);

      // …and the side turned away is out of sight behind the face.
      final away = await pixelAt(
        tester,
        docWith(turned),
        catalog,
        beside(turned, 0, -3),
      );
      expect(away, page, reason: 'no band on the side turned away');
    });

    testWidgets('every device renders turned without throwing', (tester) async {
      final catalog = (await tester.runAsync(loadFrameCatalog))!;
      for (final device in catalog.devices) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SceneRenderer.captureStage(
                boundaryKey: GlobalKey(),
                doc: ScreenDoc(
                  id: device.id,
                  frames: [
                    FramePlacement(
                      deviceId: device.id,
                      variantId: device.variants.first.id,
                      transform: const Transform2D(
                        tiltX: 12,
                        tiltY: -28,
                        rotationDeg: 6,
                      ),
                      depth: const DepthSpec(glare: 0.5),
                    ),
                  ],
                ),
                catalog: catalog,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: device.id);
      }
    });
  });
}
