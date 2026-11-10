import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/domain/engine/export_settings.dart';
import 'package:mockmyapp/domain/models/store_target.dart';

void main() {
  group('the target table', () {
    test('every target id is unique', () {
      final ids = StoreTargets.all.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every preset id is unique across the whole catalog', () {
      // Across targets, not just within one: a `presetId` is stored on a
      // SubProject beside its `targetId`, and ids that collide between targets
      // make a mis-migrated document silently resolve to the wrong canvas
      // rather than fall back to a default.
      final ids = [
        for (final target in StoreTargets.all)
          for (final preset in target.presets) preset.id,
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every target offers at least one preset', () {
      for (final target in StoreTargets.all) {
        expect(target.presets, isNotEmpty, reason: target.id);
      }
    });

    test('every canvas is a positive whole number of pixels', () {
      for (final target in StoreTargets.all) {
        for (final preset in target.presets) {
          expect(preset.size.width, greaterThan(0), reason: preset.id);
          expect(preset.size.height, greaterThan(0), reason: preset.id);
          expect(preset.size.width, preset.size.width.roundToDouble());
          expect(preset.size.height, preset.size.height.roundToDouble());
        }
      }
    });

    test('every default preset resolves back to itself', () {
      for (final target in StoreTargets.all) {
        expect(
          target.resolvePreset(target.defaultPreset.id).id,
          target.defaultPreset.id,
          reason: target.id,
        );
      }
    });

    test('an unknown preset id falls back to the default', () {
      // A document that chose a preset a later build dropped must keep working.
      expect(
        StoreTargets.iphone.resolvePreset('no-such-preset').id,
        StoreTargets.iphone.defaultPreset.id,
      );
      expect(StoreTargets.resolve('no-such-target').id, StoreTargets.iphone.id);
    });

    test('the stores each own the targets they claim', () {
      for (final store in StoreTargets.stores) {
        final targets = StoreTargets.forStore(store);
        expect(targets, isNotEmpty);
        for (final target in targets) {
          expect(target.store, store);
        }
      }
      expect(
        StoreTargets.stores.length,
        StoreKind.values.length,
        reason: 'every StoreKind should have at least one target',
      );
    });
  });

  group('the published requirements', () {
    test("Apple's required base sizes are the ones the store asks for", () {
      // The numbers App Store Connect demands as the master source. They are
      // the reason the whole table exists, so they are asserted literally.
      expect(
        StoreTargets.iphone.defaultPreset.size,
        const Size(1320, 2868),
        reason: '6.9-inch is the required iPhone base',
      );
      expect(
        StoreTargets.ipad.defaultPreset.size,
        const Size(2064, 2752),
        reason: '13-inch is the required iPad base',
      );
    });

    test("Google's sizes are the ones the console accepts", () {
      expect(
        StoreTargets.androidPhone.defaultPreset.size,
        const Size(1080, 1920),
      );
      expect(
        StoreTargets.playFeatureGraphic.defaultPreset.size,
        const Size(1024, 500),
      );
    });

    test('the feature graphic is one exact size and nothing else', () {
      // Google accepts a single feature graphic at a single size. Offering a
      // second preset here would offer a canvas the console rejects.
      expect(StoreTargets.playFeatureGraphic.presets, hasLength(1));
      expect(StoreTargets.playFeatureGraphic.starterScreenCount, 1);
    });

    test("the iPhone Duo's two displays are Apple's two sizes", () {
      expect(
        StoreTargets.iphoneDuoInner.defaultPreset.size,
        const Size(2007, 2853),
      );
      expect(
        StoreTargets.iphoneDuoOuter.defaultPreset.size,
        const Size(1398, 2034),
      );
      // Each opens in the body it shows.
      expect(
        StoreTargets.iphoneDuoInner.defaultFrame?.$1,
        StudioFrameIds.iphoneDuoOpen,
      );
      expect(
        StoreTargets.iphoneDuoOuter.defaultFrame?.$1,
        StudioFrameIds.iphoneDuoCover,
      );
    });

    test("Apple's creative assets are the template sizes, one image each", () {
      expect(
        StoreTargets.appStoreCreative.presets.map((p) => p.size).toList(),
        const [Size(3840, 1646), Size(3840, 2560), Size(5244, 2950)],
      );
      expect(StoreTargets.appStoreCreative.starterScreenCount, 1);
      // Not Google's word for it.
      expect(StoreTargets.appStoreCreative.shortLabel, 'Creative');
      expect(StoreTargets.playFeatureGraphic.shortLabel, 'Feature');
    });

    test('screenshot targets seed a set rather than a single image', () {
      for (final target in StoreTargets.all) {
        if (target.formFactor == TargetFormFactor.graphic) continue;
        expect(target.starterScreenCount, 3, reason: target.id);
      }
    });
  });

  group('the October 2026 corrections', () {
    Size size(StoreTarget target, String preset) =>
        target.presetById(preset)!.size;

    test('1179 × 2556 is a 6.3-inch size, under the id it always had', () {
      final preset = StoreTargets.iphone.presetById('iphone-6-1')!;
      expect(preset.size, const Size(1179, 2556));
      expect(preset.label, '6.3" display');
    });

    test("Apple's real 6.1-inch sizes are there", () {
      final sixOne = StoreTargets.iphone.presets
          .where((p) => p.label == '6.1" display')
          .map((p) => p.size)
          .toList();
      expect(sixOne, const [
        Size(1170, 2532),
        Size(1125, 2436),
        Size(1080, 2340),
      ]);
    });

    test("Play tablets open on 9:16, with 16:9 and both at 4K", () {
      final tablet = StoreTargets.androidTablet;
      expect(tablet.defaultPreset.size, const Size(1440, 2560));
      expect(tablet.defaultPreset.label, 'Portrait 9:16');
      for (final s in const [
        Size(1440, 2560),
        Size(2160, 3840),
        Size(2560, 1440),
        Size(3840, 2160),
      ]) {
        expect(tablet.presets.map((p) => p.size), contains(s), reason: '$s');
      }
      // The old default keeps its id, so a set made at it resolves.
      expect(size(tablet, 'android-tablet-10'), const Size(1600, 2560));
    });

    test('Windows takes ten screenshots, PNG only', () {
      final rules = StoreTargets.windows.rules;
      expect(rules.maxCount, 10);
      expect(rules.formats, {ExportFormat.png});
      expect(StoreTargets.windows.requirements, contains('up to 10'));
      expect(StoreTargets.windows.requirements, isNot(contains('up to 9')));
    });

    test('the feature graphic no longer claims a 1 MB cap', () {
      expect(StoreTargets.playFeatureGraphic.rules.maxBytes, isNull);
      expect(
        StoreTargets.playFeatureGraphic.requirements,
        'PNG or JPEG · no alpha · exactly one · '
        'Keep the name, logo and words clear of the edges',
      );
    });

    test('both iPhone Duo lines say MB', () {
      for (final duo in [
        StoreTargets.iphoneDuoInner,
        StoreTargets.iphoneDuoOuter,
      ]) {
        expect(duo.requirements, contains('up to 10 MB'));
        expect(duo.requirements, contains('later in 2026'));
      }
    });

    test("the Watch labels name this year's watches", () {
      final labels = StoreTargets.appleWatch.presets.map((p) => p.label);
      expect(labels, contains('Ultra 3 & 4'));
      expect(labels, contains('Series 10–12'));
      expect(
        StoreTargets.appleWatch.presetById('watch-series-4')!.size,
        const Size(368, 448),
      );
      // Ids unchanged.
      expect(
        StoreTargets.appleWatch.presetById('watch-ultra-3')!.size,
        const Size(422, 514),
      );
      expect(
        StoreTargets.appleWatch.presetById('watch-series-10')!.size,
        const Size(416, 496),
      );
    });

    test("Play's two 2.22:1 presets stay, last, saying why", () {
      final phone = StoreTargets.androidPhone;
      expect(phone.presets.last.id, 'android-phone-landscape-tall');
      expect(phone.presetById('android-phone-9-20')!.note, contains('2:1'));
      expect(phone.defaultPreset.size, const Size(1080, 1920));
    });
  });

  group('the new targets', () {
    test('are the published sizes', () {
      Size head(String id) => StoreTargets.byId(id)!.defaultPreset.size;
      List<Size> all(String id) =>
          StoreTargets.byId(id)!.presets.map((p) => p.size).toList();

      expect(all('ios-event-card'), const [Size(1920, 1080), Size(3840, 2160)]);
      expect(all('ios-event-details'), const [
        Size(1080, 1920),
        Size(2160, 3840),
      ]);
      expect(all('ms-hero-art'), const [Size(1920, 1080), Size(3840, 2160)]);
      expect(head('android-xr'), const Size(3840, 2400));
      expect(head('galaxy-hero'), const Size(1200, 675));
      expect(head('chrome-small-tile'), const Size(440, 280));
      expect(head('chrome-marquee'), const Size(1400, 560));
      expect(head('social-og'), const Size(1200, 630));
      expect(head('social-x'), const Size(1600, 900));
      expect(head('social-linkedin'), const Size(1200, 627));
      expect(head('producthunt-thumbnail'), const Size(240, 240));
      expect(head('producthunt-gallery'), const Size(1270, 760));
      expect(head('android-app-icon'), const Size(512, 512));
    });

    test('sit with their stores, and the launch kit on its own at the end', () {
      expect(StoreTargets.stores, const [
        StoreKind.appStore,
        StoreKind.playStore,
        StoreKind.huaweiAppGallery,
        StoreKind.galaxyStore,
        StoreKind.macAppStore,
        StoreKind.microsoftStore,
        StoreKind.chromeWebStore,
        StoreKind.social,
      ]);
      List<String> ids(StoreKind store) =>
          StoreTargets.forStore(store).map((t) => t.id).toList();
      expect(
        ids(StoreKind.appStore),
        containsAll(['ios-event-card', 'ios-event-details']),
      );
      expect(
        ids(StoreKind.playStore),
        containsAll(['android-xr', 'android-app-icon']),
      );
      expect(ids(StoreKind.microsoftStore), ['windows', 'ms-hero-art']);
      expect(ids(StoreKind.chromeWebStore), [
        'web',
        'chrome-small-tile',
        'chrome-marquee',
      ]);
      expect(ids(StoreKind.galaxyStore), ['galaxy-hero']);
      expect(ids(StoreKind.social), [
        'social-og',
        'social-x',
        'social-linkedin',
        'producthunt-thumbnail',
        'producthunt-gallery',
      ]);
      for (final t in StoreTargets.forStore(StoreKind.social)) {
        expect(t.storeLabel, 'Social & launch');
      }
    });

    test('artwork is one image; Android XR and the gallery are sets', () {
      for (final id in [
        'ios-event-card',
        'ios-event-details',
        'ms-hero-art',
        'galaxy-hero',
        'chrome-small-tile',
        'chrome-marquee',
        'social-og',
        'social-x',
        'social-linkedin',
        'producthunt-thumbnail',
        'android-app-icon',
      ]) {
        final target = StoreTargets.byId(id)!;
        expect(target.starterScreenCount, 1, reason: id);
        expect(target.rules.maxCount, 1, reason: id);
        expect(target.wearsDeviceFrame, isFalse, reason: id);
      }
      expect(StoreTargets.androidXr.starterScreenCount, 3);
      expect(StoreTargets.productHuntGallery.starterScreenCount, 3);
    });

    test('a tag names each one in a word or two', () {
      expect(StoreTargets.playIcon.shortLabel, 'Icon');
      expect(StoreTargets.appStoreEventCard.shortLabel, 'Event card');
      expect(StoreTargets.appStoreEventPage.shortLabel, 'Event page');
      expect(StoreTargets.galaxyHero.shortLabel, 'Hero');
      expect(StoreTargets.microsoftHero.shortLabel, 'Hero art');
      expect(StoreTargets.chromeMarquee.shortLabel, 'Marquee');
      expect(StoreTargets.productHuntGallery.shortLabel, 'PH gallery');
      expect(StoreTargets.androidXr.shortLabel, 'Android XR');
    });
  });

  group('the structured rules', () {
    test('read back as the line the pickers show', () {
      expect(
        StoreTargets.iphone.requirements,
        'PNG or JPEG · no alpha · up to 10 MB · up to 10 per listing · sRGB',
      );
      expect(
        StoreTargets.androidPhone.requirements,
        'PNG or JPEG · no alpha · sides 320–3840 px, at most 2:1 · up to 8 MB · '
        '2–8 per listing',
      );
      expect(
        StoreTargets.huaweiPhone.requirements,
        'PNG or JPEG · sides 320–3840 px · up to 2 MB · 3–8 per listing · '
        'HarmonyOS apps take 3–5',
      );
      expect(
        StoreTargets.windows.requirements,
        'PNG only · 1366 × 768 or larger, up to 3840 × 2160 · up to 50 MB · '
        'up to 10 per listing · keep key content in the top two-thirds',
      );
      expect(
        StoreTargets.androidXr.requirements,
        'PNG or JPEG · no alpha · 8:5, 1920 × 1200 to 3840 × 2400 · '
        'up to 8 MB · 4–8 per listing',
      );
    });

    test('derive the exact sizes from the presets', () {
      expect(StoreTargets.playFeatureGraphic.exactSizes, const [
        Size(1024, 500),
      ]);
      expect(StoreTargets.androidPhone.exactSizes, isNull);
      final iphone = StoreTargets.iphone.exactSizes!;
      expect(iphone, contains(const Size(2736, 1260)));
      expect(iphone.toSet(), hasLength(iphone.length), reason: 'no repeats');
      expect(
        StoreTargets.mac.exactSizes,
        isNot(contains(const Size(1800, 2880))),
        reason: 'Mac screenshots only come landscape',
      );
    });
  });

  group('device frames', () {
    test('only phone and tablet targets wear one', () {
      for (final target in StoreTargets.all) {
        final expected =
            target.formFactor == TargetFormFactor.phone ||
            target.formFactor == TargetFormFactor.tablet;
        expect(target.wearsDeviceFrame, expected, reason: target.id);
      }
    });

    test('a frameless target still opens the picker somewhere sensible', () {
      // `catalogPlatform` always answers, so a user who goes looking for a real
      // device on a Mac set is not shown an empty picker.
      expect(StoreTargets.mac.catalogPlatform, FramePlatform.ios);
      expect(StoreTargets.windows.catalogPlatform, FramePlatform.android);
      expect(StoreTargets.web.catalogPlatform, FramePlatform.android);
    });

    test('a framed target opens on its own hardware', () {
      expect(StoreTargets.iphone.catalogPlatform, FramePlatform.ios);
      expect(StoreTargets.ipad.catalogPlatform, FramePlatform.ios);
      expect(StoreTargets.androidPhone.catalogPlatform, FramePlatform.android);
      expect(StoreTargets.androidTablet.catalogPlatform, FramePlatform.android);
    });
  });

  group('forLegacy', () {
    // The migration for every project written before targets existed. It has to
    // answer for any canvas at all: failing here loses somebody's work.

    test('recovers the exact canvases the old table produced', () {
      // The four sizes the pre-target `StoreCanvas` could emit, portrait.
      const cases = [
        (FramePlatform.ios, Size(1284, 2778), 'ios-iphone'),
        (FramePlatform.ios, Size(2048, 2732), 'ios-ipad'),
        (FramePlatform.android, Size(1080, 1920), 'android-phone'),
        (FramePlatform.android, Size(1600, 2560), 'android-tablet'),
      ];
      for (final (platform, canvas, targetId) in cases) {
        final (target, preset) = StoreTargets.forLegacy(platform, canvas);
        expect(target.id, targetId, reason: '$canvas');
        expect(preset.size, canvas, reason: 'exact match keeps the canvas');
      }
    });

    test('recovers the landscape ones too', () {
      final (target, preset) = StoreTargets.forLegacy(
        FramePlatform.ios,
        const Size(2778, 1284),
      );
      expect(target.id, 'ios-iphone');
      expect(preset.size, const Size(2778, 1284));
      expect(preset.isLandscape, isTrue);
    });

    test('a canvas matching nothing falls back to its aspect ratio', () {
      // A hand-edited document, or one from a build this is not. Phones run
      // 0.462–0.5625 short/long and tablets 0.625–0.75, so the gap separates
      // them. (1170 × 2532 used to be the example here; it is one of Apple's
      // 6.1-inch sizes and a preset of its own now.)
      expect(
        StoreTargets.forLegacy(FramePlatform.ios, const Size(1100, 2400)).$1.id,
        'ios-iphone',
      );
      expect(
        StoreTargets.forLegacy(FramePlatform.ios, const Size(2000, 2600)).$1.id,
        'ios-ipad',
      );
      expect(
        StoreTargets.forLegacy(
          FramePlatform.android,
          const Size(1000, 1000),
        ).$1.id,
        'android-tablet',
        reason: 'a square canvas is squarer than any phone',
      );
    });

    test('an unmatched landscape canvas keeps its orientation', () {
      final (_, preset) = StoreTargets.forLegacy(
        FramePlatform.android,
        const Size(2532, 1170),
      );
      expect(preset.isLandscape, isTrue);
    });

    test('never throws, whatever it is handed', () {
      const nonsense = [
        Size.zero,
        Size(1, 100000),
        Size(100000, 1),
        Size(-10, -10),
      ];
      for (final platform in FramePlatform.values) {
        for (final size in nonsense) {
          expect(
            () => StoreTargets.forLegacy(platform, size),
            returnsNormally,
            reason: '$platform $size',
          );
        }
      }
    });

    test('stays on the store it was given', () {
      for (final size in const [
        Size(1284, 2778),
        Size(2048, 2732),
        Size(1080, 1920),
        Size(999, 1234),
      ]) {
        expect(
          StoreTargets.forLegacy(FramePlatform.ios, size).$1.store,
          StoreKind.appStore,
        );
        expect(
          StoreTargets.forLegacy(FramePlatform.android, size).$1.store,
          StoreKind.playStore,
        );
      }
    });
  });

  group('readouts', () {
    test('sizeLabel is the mono readout the UI shows', () {
      expect(
        const CanvasPreset(
          id: 'x',
          label: 'x',
          size: Size(1320, 2868),
        ).sizeLabel,
        '1320 × 2868',
      );
    });

    test('isLandscape reads off the shape', () {
      expect(StoreTargets.iphone.presets.first.isLandscape, isFalse);
      expect(
        StoreTargets.iphone.presets
            .firstWhere((p) => p.id == 'iphone-6-9-landscape')
            .isLandscape,
        isTrue,
      );
    });
  });
}
