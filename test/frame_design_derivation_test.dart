// Every frame in the picker is editable, which means every frame in the picker
// has to be expressible as a `FrameDesign`. These are the guards on that
// derivation — see `frameDesignForDevice`.
//
// The failure they exist to catch is not hypothetical, and it is not loud: a
// design derived from the wrong rect still draws a phone. It just draws one
// with a border up to three times life size, which reads as "the builder is
// approximate" rather than as a bug. So the checks are numeric.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  FrameDesign designOf(FrameDevice d) =>
      frameDesignForDevice(d, d.variants.first.id);

  group('the manifest carries the two rects the builder reads', () {
    test('every artwork device declares a body inside its canvas', () {
      for (final device in catalog.artworkDevices) {
        final body = device.bodyRect;
        // The default is the whole canvas. Every traced asset has margin, so
        // the default here means a regenerated manifest dropped the key —
        // which is exactly the silent failure this guards.
        expect(
          body.w,
          lessThan(1.0),
          reason: '${device.id} has no measured bodyRect',
        );
        expect(body.x, greaterThan(0), reason: device.id);
        expect(body.y, greaterThan(0), reason: device.id);
        expect(body.x + body.w, lessThanOrEqualTo(1.0), reason: device.id);
        expect(body.y + body.h, lessThanOrEqualTo(1.0), reason: device.id);
      }
    });

    test('the body encloses the aperture', () {
      // If it does not, the derived bezel is negative and the screen hangs off
      // the chassis.
      for (final device in catalog.artworkDevices) {
        final body = device.bodyRect;
        final screen = device.screenRect;
        expect(screen.x, greaterThan(body.x), reason: device.id);
        expect(screen.y, greaterThan(body.y), reason: device.id);
        expect(
          screen.x + screen.w,
          lessThan(body.x + body.w),
          reason: device.id,
        );
        expect(
          screen.y + screen.h,
          lessThan(body.y + body.h),
          reason: device.id,
        );
      }
    });

    test('a measured cut-out sits inside the aperture', () {
      for (final device in catalog.artworkDevices) {
        final cutout = device.cutoutRect;
        if (cutout == null) continue;
        final screen = device.screenRect;
        expect(cutout.x, greaterThanOrEqualTo(screen.x), reason: device.id);
        expect(cutout.y, greaterThanOrEqualTo(screen.y), reason: device.id);
        expect(
          cutout.x + cutout.w,
          lessThanOrEqualTo(screen.x + screen.w),
          reason: device.id,
        );
        expect(
          cutout.y + cutout.h,
          lessThanOrEqualTo(screen.y + screen.h),
          reason: device.id,
        );
      }
    });

    test('no artwork variant is still the #000000 placeholder', () {
      // Every traced Apple and Pixel variant shipped as pure black, from before
      // anything read the field. A built frame takes its body colour from it,
      // so a Desert Titanium iPhone came out identical to a Black Titanium one.
      for (final device in catalog.artworkDevices) {
        for (final variant in device.variants) {
          expect(
            variant.frameColor,
            isNot(0xFF000000),
            reason: '${device.id}/${variant.id}',
          );
        }
      }
    });
  });

  group('every device derives a frame that draws the same screen', () {
    test('the derived aperture reproduces the declared screen aspect', () {
      // The whole contract. `CustomDeviceFrame` lays a built frame out from
      // these four numbers, so if they do not reproduce the device's own
      // aperture the screenshot is stretched the moment the user taps Build.
      for (final device in catalog.devices) {
        final design = designOf(device);
        final rect = CustomDeviceFrame.screenRectFor(design, design.aspect);
        final aperture = (rect.width / rect.height) * design.aspect;
        expect(aperture, closeTo(device.screenAspect, 0.01), reason: device.id);
      }
    });

    test('no handset wears a bezel read off the canvas margin', () {
      // This is the regression. Derived from `screenRect` alone a Pixel 8's
      // border comes out at 0.1218 of the frame — three and a half times the
      // 0.0458 it really wears — because the asset's transparent margin gets
      // counted as chassis. Nothing in the catalog is genuinely past 0.06
      // except the Xperia, which has real bezels and no punch hole.
      for (final device in catalog.artworkDevices) {
        final design = designOf(device);
        final ceiling = device.cutout == 'none' ? 0.09 : 0.06;
        expect(design.thickness, lessThan(ceiling), reason: device.id);
        expect(design.top, lessThan(ceiling), reason: device.id);
        expect(design.thickness, greaterThan(0), reason: device.id);
      }
    });

    test('the corner radius stays inside the body', () {
      for (final device in catalog.devices) {
        final design = designOf(device);
        expect(design.cornerRadius, greaterThanOrEqualTo(0), reason: device.id);
        expect(design.cornerRadius, lessThanOrEqualTo(0.5), reason: device.id);
      }
    });

    test('the cut-out follows what the device declares it has', () {
      for (final device in catalog.devices) {
        final hole = designOf(device).punchHole;
        expect(
          hole.enabled,
          device.cutout != 'none',
          reason: '${device.id} declares "${device.cutout}"',
        );
        if (!hole.enabled) continue;
        expect(hole.width, greaterThan(0), reason: device.id);
        expect(hole.height, greaterThan(0), reason: device.id);
        // A camera sits in the top of the display, never halfway down it.
        expect(hole.top, lessThan(0.12), reason: device.id);
      }
    });

    test('a notch derives as a pill and a punch as a circle', () {
      for (final device in catalog.artworkDevices) {
        final hole = designOf(device).punchHole;
        final ratio = hole.width / hole.height;
        switch (device.cutout) {
          case 'notch':
            expect(ratio, greaterThan(2.5), reason: device.id);
          case 'punch':
            expect(ratio, closeTo(1.0, 0.15), reason: device.id);
        }
      }
    });

    test('only handsets get side keys', () {
      // A tablet, a laptop and a browser have none to draw, and a key standing
      // proud of a monitor's bezel reads as damage.
      for (final device in catalog.devices) {
        final design = designOf(device);
        final expected = device.formFactor == 'phone';
        expect(design.power.enabled, expected, reason: device.id);
        expect(design.volume.enabled, expected, reason: device.id);
      }
    });

    test('the finish comes from the picked variant, not the first one', () {
      for (final device in catalog.devices) {
        if (device.variants.length < 2) continue;
        for (final variant in device.variants) {
          expect(
            frameDesignForDevice(device, variant.id).color.toARGB32(),
            variant.frameColor,
            reason: '${device.id}/${variant.id}',
          );
        }
      }
    });
  });

  group('the dynamic handsets keep their hand-measured design', () {
    test('a dynamic device derives to exactly what it is drawn from', () {
      // `SceneView` renders these off `studioDesignFor` whether or not the
      // user has opened the builder, so the two paths must not diverge — the
      // frame would change the moment Build was tapped.
      for (final id in [
        StudioFrameIds.iphone17ProMax,
        StudioFrameIds.galaxyNote20Ultra,
        StudioFrameIds.onePlus13,
      ]) {
        final device = catalog.byId(id);
        for (final variant in device.variants) {
          final drawn = studioDesignFor(id, variant.id)!;
          final derived = frameDesignForDevice(device, variant.id);
          expect(derived.aspect, drawn.aspect, reason: '$id/${variant.id}');
          expect(
            derived.thickness,
            drawn.thickness,
            reason: '$id/${variant.id}',
          );
          expect(derived.color, drawn.color, reason: '$id/${variant.id}');
        }
      }
    });

    test('the iPhone 17 Pro Max wears an even 16 all round', () {
      final design = studioDesignFor(
        StudioFrameIds.iphone17ProMax,
        'deep-blue',
      )!;
      expect(design.thickness, closeTo(0.016, 1e-9));
      expect(design.top, closeTo(0.016, 1e-9));
      expect(design.bottom, closeTo(0.016, 1e-9));
    });

    test('both round-cornered handsets turn on a circular arc', () {
      // A continuous corner is fed roughly double the radius to compensate for
      // how shallow Flutter draws it, and at these radii that overshoots.
      for (final id in [
        StudioFrameIds.iphone17ProMax,
        StudioFrameIds.onePlus13,
      ]) {
        final device = catalog.byId(id);
        expect(
          studioDesignFor(id, device.variants.first.id)!.cornerStyle,
          CornerStyle.round,
          reason: id,
        );
      }
    });
  });
}
