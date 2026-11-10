// The drawn iPhones that replaced the traced Apple bezels — see
// `lib/data/assets/drawn_iphones.dart`.
//
// The artwork could not ship in a paid app, but every set made with it is
// still on someone's disk. So the promise held here is that nothing about an
// old document changes except the pixels of the bezel: it names the same
// device and finish, finds them, lays the screenshot out in the same box, and
// saves back to exactly the bytes it was loaded from.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/device_filter.dart';
import 'package:mockmyapp/data/assets/drawn_iphones.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/device_depth.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/drawn_iphone_frame.dart';

import 'support/project_fixture.dart';

/// Every device and finish id the traced Apple artwork shipped with — what
/// saved documents carry. Copied from the frames manifest before its Apple
/// rows were removed. Never edit this list: it is the record of what is out
/// there.
const _legacy = <String, List<String>>{
  'apple-iphone-13-mini': [
    '13-mini---black',
    '13-mini---blue',
    '13-mini---pink',
    '13-mini---product-red',
    '13-mini---starlight',
  ],
  'apple-iphone-14-pro-max': [
    '14-pro-max---deep-purple',
    '14-pro-max---deep-purple---shadow',
    '14-pro-max---gold',
    '14-pro-max---gold---shadow',
    '14-pro-max---silver',
    '14-pro-max---silver---shadow',
    '14-pro-max---space-black',
    '14-pro-max---space-black---shadow',
  ],
  'apple-iphone-15-pro-max': [
    '15-pro-max---black-titanium',
    '15-pro-max---blue-titanium',
    '15-pro-max---natural-titanium',
    '15-pro-max---white-titanium',
  ],
  'apple-iphone-16': [
    '16---black',
    '16---pink',
    '16---teal',
    '16---ultramarine',
    '16---white',
  ],
  'apple-iphone-16-plus': [
    '16-plus---black',
    '16-plus---pink',
    '16-plus---teal',
    '16-plus---ultramarine',
    '16-plus---white',
  ],
  'apple-iphone-16-pro': [
    '16-pro---black-titanium',
    '16-pro---desert-titanium',
    '16-pro---natural-titanium',
    '16-pro---white-titanium',
  ],
  'apple-iphone-16-pro-max': [
    '16-pro-max---black-titanium',
    '16-pro-max---desert-titanium',
    '16-pro-max---natural-titanium',
    '16-pro-max---white-titanium',
  ],
  'apple-iphone-17-pro': [
    '17-pro---cosmic-orange',
    '17-pro---deep-blue',
    '17-pro---silver',
  ],
  'apple-iphone-17-pro-max': [
    '17-pro-max---cosmic-orange',
    '17-pro-max---deep-blue',
    '17-pro-max---silver',
  ],
};

/// The box each traced frame laid its screenshot out in, as the manifest
/// recorded it: the canvas aspect, the screen and the body inside it.
class _Box {
  const _Box(this.aspect, this.screen, this.body);

  final double aspect;
  final (double, double, double, double) screen;
  final (double, double, double, double) body;
}

const _tracedBox = <String, _Box>{
  'apple-iphone-13-mini': _Box(
    0.5039,
    (0.0781, 0.0394, 0.8438, 0.9213),
    (0.0297, 0.015, 0.9405, 0.97),
  ),
  'apple-iphone-14-pro-max': _Box(
    0.4973,
    (0.0678, 0.0327, 0.8658, 0.9332),
    (0.0302, 0.0143, 0.9411, 0.9714),
  ),
  'apple-iphone-15-pro-max': _Box(
    0.4973,
    (0.0664, 0.0334, 0.8658, 0.9332),
    (0.033, 0.0164, 0.9325, 0.9671),
  ),
  'apple-iphone-16': _Box(
    0.5004,
    (0.0725, 0.0363, 0.855, 0.9274),
    (0.03, 0.015, 0.9401, 0.97),
  ),
  'apple-iphone-16-plus': _Box(
    0.4973,
    (0.0671, 0.0334, 0.8658, 0.9332),
    (0.0273, 0.0136, 0.9454, 0.9729),
  ),
  'apple-iphone-16-pro': _Box(
    0.4982,
    (0.0725, 0.0354, 0.8578, 0.9291),
    (0.0415, 0.02, 0.9198, 0.96),
  ),
  'apple-iphone-16-pro-max': _Box(
    0.4954,
    (0.0658, 0.0326, 0.8684, 0.9348),
    (0.036, 0.0179, 0.928, 0.9643),
  ),
  'apple-iphone-17-pro': _Box(
    0.4982,
    (0.0718, 0.036, 0.8564, 0.928),
    (0.0372, 0.0186, 0.9241, 0.9629),
  ),
  'apple-iphone-17-pro-max': _Box(
    0.4954,
    (0.0667, 0.0327, 0.8666, 0.9347),
    (0.036, 0.0179, 0.928, 0.9643),
  ),
};

/// A set made with the traced artwork: one screen per device and finish,
/// each placed and dressed the way a real one is.
Project _legacyProject() {
  var i = 0;
  final screens = [
    for (final MapEntry(key: deviceId, value: finishes) in _legacy.entries)
      for (final variantId in finishes)
        ScreenDoc(
          id: 's${i++}',
          canvas: const Size(1290, 2796),
          background: const SolidBackground(Color(0xFF223344)),
          caption: CaptionSpec(text: '$deviceId $variantId'),
          frames: [
            FramePlacement(
              deviceId: deviceId,
              variantId: variantId,
              transform: Transform2D(
                pagePercentage: 0.72,
                offsetPct: const Offset(0, 0.08),
                rotationDeg: i.isEven ? 0 : -6,
                tiltY: i % 3 == 0 ? 24 : 0,
              ),
              screenshot: const ScreenshotSpec(cornerRadiusPct: 0.149),
              shadow: const ShadowSpec(opacity: 0.3, blur: 30),
              cutoutHidden: i % 4 == 0,
            ),
          ],
        ),
  ];
  return projectOf(screens, createdAt: DateTime.utc(2026, 7, 20, 9));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;
  setUpAll(() async => catalog = await loadFrameCatalog());

  group('a document saved with the traced artwork', () {
    test('finds every device and finish it names — itself, not a fallback', () {
      for (final MapEntry(key: deviceId, value: finishes) in _legacy.entries) {
        final device = catalog.byId(deviceId);
        expect(device.id, deviceId, reason: '$deviceId fell back to another');
        expect(drawnIPhoneFor(deviceId), isNotNull, reason: deviceId);
        expect(device.isProgrammatic, isTrue, reason: '$deviceId is drawn');
        expect(device.maker, 'Apple', reason: deviceId);
        expect(device.platform, FramePlatform.ios, reason: deviceId);
        expect(kindOf(device), DeviceKind.phone, reason: deviceId);
        for (final variantId in finishes) {
          expect(
            device.variants.map((v) => v.id),
            contains(variantId),
            reason: '$deviceId lost its "$variantId" finish',
          );
        }
      }
    });

    test('opens and saves back byte for byte', () {
      final saved = jsonEncode(_legacyProject().toJson());
      final opened = Project.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );

      // Everything a document says about its frame is the two ids, and the
      // drawn devices are filed under exactly those: nothing to rewrite.
      for (final screen in opened.allScreens) {
        final placement = screen.frames.single;
        expect(catalog.byId(placement.deviceId).id, placement.deviceId);
      }
      expect(jsonEncode(opened.toJson()), saved);
    });

    testWidgets('draws, and is left exactly as it was', (tester) async {
      final saved = jsonEncode(_legacyProject().toJson());
      final opened = Project.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
      for (final screen in opened.allScreens.take(12)) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 650,
                child: SceneView(doc: screen, catalog: catalog),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: screen.id);
        final shown = screen.frames.single;
        final turned = shown.transform.isTilted;
        // Drawn by the new painter, not by the generic handset fallback.
        expect(
          find.byType(DrawnIPhoneFrame),
          findsOneWidget,
          reason: '${shown.deviceId} ${turned ? '(turned)' : ''}',
        );
      }
      expect(jsonEncode(opened.toJson()), saved);
    });

    test('lays its screenshot out in the box the traced frame did', () {
      // The drawn body keeps the traced canvas's transparent margin, so a set
      // positioned against the artwork does not move: same aspect, same
      // screen, same body, to a few thousandths of the canvas.
      for (final MapEntry(key: id, value: box) in _tracedBox.entries) {
        final d = catalog.byId(id);
        expect(d.frameAspect, closeTo(box.aspect, 0.001), reason: id);
        final (sx, sy, sw, sh) = box.screen;
        expect(d.screenRect.x, closeTo(sx, 0.002), reason: '$id screen x');
        expect(d.screenRect.y, closeTo(sy, 0.002), reason: '$id screen y');
        expect(d.screenRect.w, closeTo(sw, 0.002), reason: '$id screen w');
        expect(d.screenRect.h, closeTo(sh, 0.002), reason: '$id screen h');
        // The body a little looser: the traced figures were measured off
        // anti-aliased pixels, and the drawn ones are the published size.
        final (bx, by, bw, bh) = box.body;
        expect(d.bodyRect.x, closeTo(bx, 0.004), reason: '$id body x');
        expect(d.bodyRect.y, closeTo(by, 0.004), reason: '$id body y');
        expect(d.bodyRect.w, closeTo(bw, 0.004), reason: '$id body w');
        expect(d.bodyRect.h, closeTo(bh, 0.004), reason: '$id body h');
      }
    });
  });

  group('every drawn iPhone', () {
    test('is drawn to its published screen', () {
      for (final spec in kDrawnIPhones) {
        final d = catalog.byId(spec.id);
        expect(
          d.screenAspect,
          spec.displayWidthPx / spec.displayHeightPx,
          reason: spec.id,
        );
        // The declared rect implies the declared aspect.
        final implied = d.screenRect.w / d.screenRect.h * d.frameAspect;
        expect(implied, closeTo(d.screenAspect, 1e-9), reason: spec.id);
        // An even border: the screen centred in the body.
        final body = d.bodyRect;
        expect(
          d.screenRect.x - body.x,
          closeTo(body.x + body.w - d.screenRect.x - d.screenRect.w, 1e-9),
          reason: spec.id,
        );
        // Its camera inside its screen, and its keys inside its body's height.
        final cut = d.cutoutRect!;
        expect(cut.x, greaterThan(d.screenRect.x), reason: spec.id);
        expect(cut.x + cut.w, lessThan(d.screenRect.x + d.screenRect.w));
        expect(cut.y, greaterThanOrEqualTo(d.screenRect.y), reason: spec.id);
        expect(d.keys, hasLength(4), reason: spec.id);
        for (final key in d.keys) {
          expect(key.top, greaterThan(body.y), reason: spec.id);
          expect(key.top + key.length, lessThan(body.y + body.h));
        }
      }
    });

    test(
      'includes the iPhone 17 and the Air, from Apple\'s specifications',
      () {
        final iphone17 = drawnIPhoneFor('apple-iphone-17')!;
        expect(iphone17.bodyWidthMm, 71.5);
        expect(iphone17.bodyHeightMm, 149.6);
        expect(
          (iphone17.displayWidthPx, iphone17.displayHeightPx),
          (1206, 2622),
        );

        final air = drawnIPhoneFor('apple-iphone-air')!;
        expect(air.bodyWidthMm, 74.7);
        expect(air.bodyHeightMm, 156.2);
        expect((air.displayWidthPx, air.displayHeightPx), (1260, 2736));
        // The thinnest iPhone is the thinnest solid when it is turned.
        expect(catalog.byId('apple-iphone-air').depthRatio, lessThan(0.08));
      },
    );

    testWidgets('clips its screenshot to the screen it declares', (
      tester,
    ) async {
      const width = 400.0;
      for (final spec in kDrawnIPhones) {
        final d = catalog.byId(spec.id);
        final height = width / d.frameAspect;
        final shot = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: DrawnIPhoneFrame(
                spec: spec,
                frameColor: Color(d.variants.first.frameColor),
                frameWidth: width,
                frameHeight: height,
                screenshot: ColoredBox(
                  key: shot,
                  color: const Color(0xFF00FF00),
                ),
              ),
            ),
          ),
        );
        final frame = tester.getRect(find.byType(DrawnIPhoneFrame));
        final drawn = tester.getRect(find.byKey(shot)).shift(-frame.topLeft);
        final r = d.screenRect;
        expect(drawn.left, closeTo(r.x * width, 1), reason: spec.id);
        expect(drawn.top, closeTo(r.y * height, 1), reason: spec.id);
        expect(drawn.width, closeTo(r.w * width, 1), reason: spec.id);
        expect(drawn.height, closeTo(r.h * height, 1), reason: spec.id);
      }
    });

    test('turns into a solid that wears its keys on its sides', () {
      for (final spec in kDrawnIPhones) {
        final d = catalog.byId(spec.id);
        final solid = deviceSolidFor(
          device: d,
          variant: d.variants.first,
          design: null,
          depth: const DepthSpec(),
          frameWidth: 300,
          frameHeight: 300 / d.frameAspect,
        )!;
        expect(solid.corner, BodyCorner.squircle, reason: spec.id);
        expect(solid.keys, hasLength(4), reason: spec.id);
        expect(solid.body.left, closeTo(d.bodyRect.x * 300, 1e-6));
        expect(
          solid.radius,
          closeTo(spec.bodyRadiusShare * solid.body.width, 1e-6),
        );
      }
    });
  });

  testWidgets('the theme never reaches the pixels', (tester) async {
    // A drawn frame is user content: an export made in dark mode has to match
    // one made in light mode byte for byte.
    final doc = ScreenDoc(
      id: 'theme',
      canvas: const Size(400, 800),
      background: const SolidBackground(Color(0xFFE6E9EF)),
      frames: const [
        FramePlacement(
          deviceId: 'apple-iphone-16-pro',
          variantId: '16-pro---desert-titanium',
          screenshot: ScreenshotSpec(
            cornerRadiusPct: 0.15,
            fill: SolidBackground(Color(0xFF6A5CFF)),
          ),
        ),
        FramePlacement(
          deviceId: 'apple-iphone-13-mini',
          variantId: '13-mini---product-red',
          transform: Transform2D(pagePercentage: 0.4, tiltY: 28),
        ),
      ],
    );

    Future<Uint8List> capture(ThemeData theme) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                height: 400,
                child: SceneView(doc: doc, catalog: catalog, forExport: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return bytes!.buffer.asUint8List();
      }))!;
    }

    final light = await capture(StudioAppTheme.light());
    final dark = await capture(StudioAppTheme.dark());
    expect(dark, light);
  });
}
