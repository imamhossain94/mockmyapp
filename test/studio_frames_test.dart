import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/device_depth.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';
import 'package:mockmyapp/features/editor/widgets/programmatic_frame.dart';

void main() {
  final devices = studioSurfaceDevices();

  FrameDevice byId(String id) => devices.firstWhere((d) => d.id == id);

  group('the drawn bodies', () {
    test('are all programmatic — none claims artwork it does not have', () {
      for (final device in devices) {
        expect(device.isProgrammatic, isTrue, reason: device.id);
        for (final variant in device.variants) {
          expect(variant.asset, isEmpty, reason: '${device.id}/${variant.id}');
        }
      }
    });

    test('have unique ids and at least one finish each', () {
      final ids = devices.map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final device in devices) {
        expect(device.variants, isNotEmpty, reason: device.id);
        final variantIds = device.variants.map((v) => v.id).toList();
        expect(variantIds.toSet(), hasLength(variantIds.length));
      }
    });

    test('cover every style the painter knows', () {
      expect(devices.map((d) => d.frameStyle).toSet(), {
        'tablet',
        'laptop',
        'monitor',
        'imac',
        'browser',
        // An open foldable, upright or turned on its side.
        'foldable',
        'foldable-turned',
        // The dynamic handsets are drawn from their own `FrameDesign` by
        // `CustomDeviceFrame`, not by a `ProgrammaticDeviceFrame` branch.
        'custom',
      });
    });
  });

  group('declared geometry agrees with the metrics', () {
    // The whole reason `StudioFrameMetrics` exists. `SceneView` places the drop
    // shadow and derives the screenshot's corner radius from `screenRect`, and
    // the painter lays the body out from the same constants — so if the aperture
    // a device declares ever stops matching the one its metric computes, the
    // shadow drifts off the body and nothing else in the app notices.

    void check(String id, StudioFrameGeometry expected) {
      final device = byId(id);
      expect(device.frameAspect, closeTo(expected.aspect, 1e-9), reason: id);
      expect(device.screenRect.x, closeTo(expected.rect.x, 1e-9), reason: id);
      expect(device.screenRect.y, closeTo(expected.rect.y, 1e-9), reason: id);
      expect(device.screenRect.w, closeTo(expected.rect.w, 1e-9), reason: id);
      expect(device.screenRect.h, closeTo(expected.rect.h, 1e-9), reason: id);
    }

    test('tablets', () {
      check(StudioFrameIds.ipad, StudioFrameMetrics.tablet(2064 / 2752));
      check(
        StudioFrameIds.androidTablet,
        StudioFrameMetrics.tablet(1600 / 2560),
      );
    });

    test('laptops', () {
      check(StudioFrameIds.macbook, StudioFrameMetrics.laptop(1.6));
      check(StudioFrameIds.windowsLaptop, StudioFrameMetrics.laptop(16 / 9));
    });

    test('monitors', () {
      check(StudioFrameIds.monitorApple, StudioFrameMetrics.monitor(1.6));
      check(StudioFrameIds.windowsMonitor, StudioFrameMetrics.monitor(16 / 9));
    });

    test('the iMac', () {
      check(StudioFrameIds.imac, StudioFrameMetrics.imac(1.6));
    });

    test('open foldables', () {
      check(
        StudioFrameIds.iphoneDuoOpen,
        StudioFrameMetrics.foldable(2007 / 2853),
      );
      check(
        StudioFrameIds.androidFoldable,
        StudioFrameMetrics.foldable(1840 / 2208),
      );
    });

    test("the shut iPhone Duo frames Apple's outer-display screenshot", () {
      // Drawn from a design, so its aperture is the design's; what has to hold
      // is that a 1398 x 2034 capture fills it without visible distortion.
      final cover = byId(StudioFrameIds.iphoneDuoCover);
      expect(cover.screenAspect, closeTo(1398 / 2034, 0.0005));
      // Squarer than any other phone, because it is half a book.
      expect(cover.frameAspect, greaterThan(0.69));
    });

    test('browsers', () {
      check(StudioFrameIds.browserMac, StudioFrameMetrics.browser(1280 / 800));
      check(
        StudioFrameIds.browserWindows,
        StudioFrameMetrics.browser(1280 / 800),
      );
    });
  });

  group('every aperture is a sane rectangle', () {
    test('sits inside its frame', () {
      for (final device in devices) {
        final r = device.screenRect;
        expect(r.x, greaterThanOrEqualTo(0), reason: device.id);
        expect(r.y, greaterThanOrEqualTo(0), reason: device.id);
        expect(r.w, greaterThan(0), reason: device.id);
        expect(r.h, greaterThan(0), reason: device.id);
        expect(r.x + r.w, lessThanOrEqualTo(1.0000001), reason: device.id);
        expect(r.y + r.h, lessThanOrEqualTo(1.0000001), reason: device.id);
      }
    });

    test('the aperture really is the declared screen shape', () {
      // frameAspect and screenRect together have to reproduce screenAspect, or
      // the screenshot is stretched inside a correctly-drawn body.
      for (final device in devices) {
        final r = device.screenRect;
        final apertureAspect = (r.w / r.h) * device.frameAspect;
        expect(
          apertureAspect,
          closeTo(device.screenAspect, 1e-9),
          reason: device.id,
        );
      }
    });

    test('the corner radius stays inside the aperture', () {
      // `SceneView` computes the radius as `cornerRadiusPct * screenWidth`, so
      // anything past half the shorter side would round the screen away.
      for (final device in devices) {
        expect(device.cornerRadiusPct, lessThan(0.5), reason: device.id);
        expect(
          device.cornerRadiusPct,
          greaterThanOrEqualTo(0),
          reason: device.id,
        );
      }
    });

    test('sides are symmetric where the body is symmetric', () {
      // Tablets and browsers are the two bodies with no chin, so their aperture
      // should be centred horizontally. A laptop and a monitor are deliberately
      // bottom-heavy.
      for (final id in [
        StudioFrameIds.ipad,
        StudioFrameIds.androidTablet,
        StudioFrameIds.browserMac,
        StudioFrameIds.browserWindows,
      ]) {
        final r = byId(id).screenRect;
        expect(r.x, closeTo(1 - (r.x + r.w), 1e-9), reason: id);
      }
    });

    test('a tablet is bezelled evenly all round in real pixels', () {
      // The bezel is a fraction of *width*, so an even-looking body has a
      // vertical inset that is smaller as a fraction of height. Checking it in
      // frame-relative pixels is what catches a metric that multiplied by the
      // wrong dimension.
      final device = byId(StudioFrameIds.ipad);
      final r = device.screenRect;
      final wPx = 1.0;
      final hPx = 1 / device.frameAspect;
      expect(r.x * wPx, closeTo((1 - r.x - r.w) * wPx, 1e-9));
      expect(r.y * hPx, closeTo((1 - r.y - r.h) * hPx, 1e-9));
      expect(r.x * wPx, closeTo(r.y * hPx, 1e-9), reason: 'even all round');
    });
  });

  group('targets open in the right body', () {
    test('every non-handset target names a frame that exists', () {
      for (final target in StoreTargets.all) {
        final frame = target.defaultFrame;
        if (frame == null) continue;
        final device = devices.where((d) => d.id == frame.$1).firstOrNull;
        expect(device, isNotNull, reason: '${target.id} → ${frame.$1}');
        expect(
          device!.variants.map((v) => v.id),
          contains(frame.$2),
          reason: '${target.id} → ${frame.$1}/${frame.$2}',
        );
      }
    });

    test('the targets the catalog could not serve now have a body', () {
      expect(StoreTargets.ipad.defaultFrame?.$1, StudioFrameIds.ipad);
      expect(
        StoreTargets.androidTablet.defaultFrame?.$1,
        StudioFrameIds.androidTablet,
      );
      expect(StoreTargets.mac.defaultFrame?.$1, StudioFrameIds.macbook);
      expect(
        StoreTargets.windows.defaultFrame?.$1,
        StudioFrameIds.windowsLaptop,
      );
      expect(StoreTargets.web.defaultFrame?.$1, StudioFrameIds.browserMac);
    });

    test('the handset targets still take the user\'s own pick', () {
      // The new-project form's frame row is a handset picker. Overriding it for
      // iPhone or Android phone would make it decorative.
      expect(StoreTargets.iphone.defaultFrame, isNull);
      expect(StoreTargets.androidPhone.defaultFrame, isNull);
    });

    test('the feature graphic stays bare', () {
      // A banner is the artwork. Putting it in a device would frame the thing
      // the frame is supposed to be about.
      expect(StoreTargets.playFeatureGraphic.defaultFrame, isNull);
      expect(StoreTargets.playFeatureGraphic.wearsDeviceFrame, isFalse);
    });

    test('a target\'s body matches the shape of its own canvas', () {
      // A MacBook around a 16:9 canvas would letterbox the screenshot inside a
      // correctly-drawn laptop. Allowed to differ, but not by much.
      for (final target in StoreTargets.all) {
        final frame = target.defaultFrame;
        if (frame == null) continue;
        final device = devices.firstWhere((d) => d.id == frame.$1);
        final canvas = target.defaultPreset.size;
        expect(
          device.screenAspect,
          closeTo(canvas.width / canvas.height, 0.13),
          reason:
              '${target.id}: body ${device.screenAspect} '
              'vs canvas ${canvas.width / canvas.height}',
        );
      }
    });
  });

  group('the catalog takes them in', () {
    test('platforms are split so both pickers have a full set', () {
      for (final platform in FramePlatform.values) {
        final forPlatform = devices.where((d) => d.platform == platform);
        expect(
          forPlatform.map((d) => d.frameStyle).toSet(),
          containsAll(<String>{'tablet', 'laptop', 'monitor', 'browser'}),
          reason: '$platform should offer every drawn body',
        );
      }
    });

    test('form factors are declared, so the pickers can group them', () {
      expect(byId(StudioFrameIds.ipad).formFactor, 'tablet');
      expect(byId(StudioFrameIds.macbook).formFactor, 'desktop');
      expect(byId(StudioFrameIds.browserMac).formFactor, 'desktop');
      expect(byId(StudioFrameIds.imac).formFactor, 'desktop');
      expect(byId(StudioFrameIds.iphone17ProMax).formFactor, 'phone');
    });
  });
  group('the iPhone Duo, drawn from Apple\'s diagrams', () {
    final cover = studioDesignFor(StudioFrameIds.iphoneDuoCover, 'black')!;

    test('shut, its camera is a round hole in the top-right corner', () {
      // Not a centred Dynamic Island: Apple runs the island down the
      // trailing edge on this device, and at rest it is a corner camera.
      final hole = cover.punchHole;
      expect(hole.enabled, isTrue);
      expect(hole.align, FrameSide.right);
      expect(hole.width, hole.height, reason: 'a circle, not a pill');
      expect(hole.cornerRadius, 0.5);
      expect(byId(StudioFrameIds.iphoneDuoCover).cutout, 'punch');
    });

    test(
      'shut, it folds on the left: square there, round on the free edge',
      () {
        expect(cover.hinge.enabled, isTrue);
        expect(cover.hinge.onLeft, isTrue);
        final radii = cover.outerRadii(100);
        expect(
          radii.topLeft.x,
          lessThan(2),
          reason: 'the spine is near-square',
        );
        expect(radii.bottomLeft.x, lessThan(2));
        expect(radii.topRight.x, closeTo(14, 0.01));
        expect(radii.bottomRight.x, closeTo(14, 0.01));
      },
    );

    test('shut, the hinge cover widens the border on its own side only', () {
      final r = CustomDeviceFrame.screenRectFor(cover, cover.aspect);
      final leftBorder = r.left;
      final rightBorder = 1 - r.right;
      expect(leftBorder - rightBorder, closeTo(cover.hinge.width, 1e-9));
      // And the aperture the widget draws is the one the catalog declares.
      final declared = byId(StudioFrameIds.iphoneDuoCover).screenRect;
      expect(r.left, closeTo(declared.x, 1e-9));
      expect(r.width, closeTo(declared.w, 1e-9));
    });

    test('shut, its volume keys ride the top edge and Touch ID the right', () {
      expect(cover.volume.onTop, isTrue);
      expect(cover.volume.count, 2);
      // Towards the free edge, well clear of the hinge.
      expect(cover.volume.top, greaterThan(0.4));
      expect(cover.power.onTop, isFalse);
      expect(cover.power.side, FrameSide.right);
    });

    test(
      "wears Apple's two finishes, keeping the ids a set was saved with",
      () {
        final names = [
          for (final v in byId(StudioFrameIds.iphoneDuoCover).variants) v.name,
        ];
        expect(names, ['Night Sky', 'Star White']);
        final ids = [
          for (final v in byId(StudioFrameIds.iphoneDuoOpen).variants) v.id,
        ];
        expect(ids, ['black', 'silver']);
      },
    );

    test(
      'a hinge and top keys survive a save; an ordinary design is unchanged',
      () {
        final back = frameDesignFromJson(frameDesignToJson(cover));
        expect(back.hinge.enabled, isTrue);
        expect(back.hinge.width, cover.hinge.width);
        expect(back.hinge.cornerRadius, cover.hinge.cornerRadius);
        expect(back.volume.onTop, isTrue);

        // A design without either writes neither key, so every document saved
        // before these existed round-trips byte for byte.
        final plain = frameDesignToJson(const FrameDesign());
        expect(plain.containsKey('hinge'), isFalse);
        expect(
          (plain['power'] as Map<String, dynamic>).containsKey('onTop'),
          isFalse,
        );
      },
    );

    test('turned in 3D, the shut body keeps its square spine and top keys', () {
      final device = byId(StudioFrameIds.iphoneDuoCover);
      final solid = deviceSolidFor(
        device: device,
        variant: device.variants.first,
        design: cover,
        depth: const DepthSpec(),
        frameWidth: 400,
        frameHeight: 400 / cover.aspect,
      )!;
      expect(solid.radii, isNotNull);
      expect(solid.radii!.topLeft.x, lessThan(8));
      expect(solid.radii!.topRight.x, closeTo(56, 0.01));
      // The outline really is square at the spine: a point just inside the
      // top-left corner is on the body.
      expect(solid.outline.contains(const Offset(1.5, 1.5)), isTrue);
      expect(solid.outline.contains(const Offset(398.5, 1.5)), isFalse);
      expect(solid.keys.where((k) => k.onTop), hasLength(2));
    });

    test(
      'open, it has a black border inside a thin rail and its own corners',
      () {
        final open = byId(StudioFrameIds.iphoneDuoOpen);
        expect(
          ProgrammaticDeviceFrame.slabRadius(open.frameStyle),
          closeTo(0.105, 1e-9),
        );
        // The Android foldable keeps its own, rounder-than-a-tablet corner.
        expect(
          ProgrammaticDeviceFrame.slabRadius('foldable'),
          closeTo(0.058, 1e-9),
        );
        // The screenshot's corner is the body's less the border, restated
        // against the screen's width.
        final inner =
            (0.105 - StudioFrameMetrics.foldableBezel) /
            (1 - 2 * StudioFrameMetrics.foldableBezel);
        expect(open.cornerRadiusPct, closeTo(inner, 0.001));
        // Its keys: the volume pair down the left, the side button on top.
        final keys = ProgrammaticDeviceFrame.slabKeys(open.frameStyle);
        expect(keys.where((k) => !k.onTop && k.left), hasLength(2));
        expect(keys.where((k) => k.onTop), hasLength(1));
      },
    );
  });
}
