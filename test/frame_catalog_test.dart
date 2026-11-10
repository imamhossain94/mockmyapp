import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/default_frames.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'frame catalog loads all generated devices with real-colorway variants',
    () async {
      final catalog = await loadFrameCatalog();

      expect(catalog.devices, isNotEmpty);
      expect(catalog.forPlatform(FramePlatform.ios), isNotEmpty);
      expect(catalog.forPlatform(FramePlatform.android), isNotEmpty);

      for (final device in catalog.devices) {
        expect(device.releaseYear, greaterThanOrEqualTo(2019));
        expect(device.variants, isNotEmpty);
        // Only the generated devices carry artwork; the studio frames are
        // drawn from code and deliberately ship no asset.
        for (final variant in catalog.artworkDevices.expand(
          (d) => d.variants,
        )) {
          expect(
            variant.asset.endsWith('.svg') || variant.asset.endsWith('.png'),
            isTrue,
            reason: '${variant.asset} is neither svg nor png',
          );
        }

        final rect = device.screenRect;
        expect(
          rect.x + rect.w,
          lessThanOrEqualTo(1.0),
          reason: '${device.id} screenRect overflows horizontally',
        );
        expect(
          rect.y + rect.h,
          lessThanOrEqualTo(1.0),
          reason: '${device.id} screenRect overflows vertically',
        );
      }
    },
  );

  test('the frames new projects open on are still in the catalog', () async {
    // `byId` falls back to the first device and the variant lookup falls back
    // to the first variant, so a default renamed or dropped by a regenerated
    // catalog would quietly change what every new project starts on rather
    // than fail. This is what makes it fail.
    final defaults = {
      for (final handset in [kDefaultIosHandset, kDefaultAndroidHandset])
        handset.deviceId: handset.variantId,
    };

    final catalog = await loadFrameCatalog();
    for (final MapEntry(key: deviceId, value: variantId) in defaults.entries) {
      final device = catalog.devices.where((d) => d.id == deviceId).firstOrNull;
      expect(
        device,
        isNotNull,
        reason: '$deviceId is no longer in the catalog',
      );
      expect(
        device!.variants.map((v) => v.id),
        contains(variantId),
        reason: '$deviceId no longer ships a "$variantId" colourway',
      );
    }
  });

  test(
    'the default Android handset is a current, round-cornered phone',
    () async {
      // It was a 2019 Galaxy Note 10+ for a long time, with square screen
      // corners, set separately in three places.
      final catalog = await loadFrameCatalog();
      final android = catalog.byId(kDefaultAndroidHandset.deviceId);
      expect(android.id, kDefaultAndroidHandset.deviceId);
      expect(android.platform, FramePlatform.android);
      expect(android.releaseYear, greaterThanOrEqualTo(2026));
      expect(android.cornerRadiusPct, greaterThan(0.05));
      expect(android.pickerHidden, isFalse);
    },
  );

  test('every variant asset is bundled and decodes', () async {
    final catalog = await loadFrameCatalog();
    for (final device in catalog.artworkDevices) {
      for (final variant in device.variants) {
        if (variant.isVector) {
          final bytes = await SvgAssetLoader(variant.asset).loadBytes(null);
          expect(bytes.lengthInBytes, greaterThan(0), reason: variant.asset);
        } else {
          final data = await rootBundle.load(variant.asset);
          expect(data.lengthInBytes, greaterThan(0), reason: variant.asset);
        }
      }
    }
  });

  // ── guards against a manifest that has drifted from its artwork ──
  //
  // These are not hypothetical. `samsung-galaxy-note-10-plus`,
  // `nothing-phone-2` and `nothing-phone-3a` all shipped for a while carrying
  // iPhone placeholder geometry — an iPhone screenRect and `cutout: notch` —
  // while their SVGs drew punch-hole Android phones, so the screenshot landed
  // in the wrong place inside the frame.

  test('no Android device claims an iPhone notch', () async {
    final catalog = await loadFrameCatalog();
    for (final device in catalog.forPlatform(FramePlatform.android)) {
      expect(
        device.cutout,
        isNot('notch'),
        reason:
            '${device.id} is Android but declares a notch, which is the '
            'signature of un-regenerated iPhone placeholder geometry',
      );
    }
  });

  test('no two devices share one screen geometry', () async {
    final catalog = await loadFrameCatalog();
    final seen = <String, String>{};
    // Scoped to the generated devices: the studio slab is one drawn frame
    // offered on both platforms, so its two entries share geometry by design.
    for (final device in catalog.artworkDevices) {
      final r = device.screenRect;
      final key = [
        r.x,
        r.y,
        r.w,
        r.h,
        device.cornerRadiusPct,
      ].map((v) => v.toStringAsFixed(4)).join(',');
      final previous = seen[key];
      expect(
        previous,
        isNull,
        reason:
            '${device.id} has byte-identical screen geometry to '
            '$previous — one of them was copied rather than generated',
      );
      seen[key] = device.id;
    }
  });

  test('declared screenAspect agrees with the screen rect', () async {
    final catalog = await loadFrameCatalog();
    for (final device in catalog.devices) {
      // screenRect is a fraction of the frame box, so the aspect it implies is
      // (w/h) scaled by the frame's own aspect. If the two disagree the
      // manifest was not regenerated alongside the artwork.
      final r = device.screenRect;
      final implied = (r.w / r.h) * device.frameAspect;
      expect(
        (implied - device.screenAspect).abs(),
        lessThan(0.01),
        reason:
            '${device.id}: screenRect implies ${implied.toStringAsFixed(4)} '
            'but screenAspect says ${device.screenAspect}',
      );
    }
  });

  test('the aperture sits centred between its own borders', () async {
    final catalog = await loadFrameCatalog();
    for (final device in catalog.devices) {
      // A frame's left and right borders are the same piece of hardware, so an
      // off-centre aperture means the artwork and the rect disagree about where
      // the hole is. This is not hypothetical: the generator floored the side
      // inset up on thin-bezel devices without growing the aperture to match,
      // and the S25, S26, Nothing Phone (2) and Edge 50 Ultra all shipped with
      // the screenshot overhanging one border by several pixels.
      final r = device.screenRect;
      final centre = r.x + r.w / 2;
      // One exception, and by exactly one part: a foldable shown shut, whose
      // hinge side carries the hinge cover as well as the cover's own border.
      final hinge = studioDesignFor(device.id, '')?.hinge;
      final expected = hinge != null && hinge.enabled
          ? 0.5 + (hinge.onLeft ? 1 : -1) * hinge.width / 2
          : 0.5;
      // The traced Apple frames are pixel-measured, so they carry a little
      // measurement noise; anything past this is a geometry error.
      expect(
        (centre - expected).abs(),
        lessThan(0.003),
        reason:
            '${device.id}: aperture centre is ${centre.toStringAsFixed(4)}, '
            'so its left and right borders differ',
      );
    }
  });

  test(
    'the studio slab is offered on both platforms and drawn in code',
    () async {
      final catalog = await loadFrameCatalog();
      final slabs = catalog.devices
          .where((d) => d.frameStyle == 'slab')
          .toList();

      expect(
        slabs.map((d) => d.platform).toSet(),
        {FramePlatform.ios, FramePlatform.android},
        reason: 'the marketing bezel should appear in both device pickers',
      );

      for (final slab in slabs) {
        // Asset-less is what routes it to ProgrammaticDeviceFrame; an asset here
        // would silently render the handset simulation instead of the slab.
        expect(slab.isProgrammatic, isTrue, reason: slab.id);
        expect(slab.variants, isNotEmpty, reason: slab.id);
        expect(
          slab.cutout,
          'none',
          reason: '${slab.id}: a marketing bezel has no camera',
        );
      }
    },
  );

  test('screenshot corner radius stays inside the aperture', () async {
    final catalog = await loadFrameCatalog();
    for (final device in catalog.devices) {
      // The app rounds the screenshot by cornerRadiusPct * screenWidth, so a
      // value past half the short edge cannot be drawn at all.
      expect(device.cornerRadiusPct, lessThan(0.5), reason: device.id);

      // A browser window is the one body with no bezel: its viewport runs to
      // the edge of the window and only the *window* is rounded, at the top.
      // So a square aperture there is the drawn truth rather than an unset
      // field, and it is the reason this assertion is scoped rather than
      // universal.
      if (device.frameStyle == 'browser') continue;

      // Zero or negative is what an unset or miscomputed radius looks like,
      // and would leak screenshot colour past the bezel.
      expect(device.cornerRadiusPct, greaterThan(0), reason: device.id);
    }
  });

  test('no phone wears a square screen', () async {
    // Every OLED panel is round-cornered, the boxiest included. The S24
    // Ultra and the four Notes shipped with square screenshots once, because
    // their chassis corner was smaller than their border and the display's
    // corner was worked out from the chassis's — see `screen_radius` in
    // tool/frame_geometry.py.
    final catalog = await loadFrameCatalog();
    for (final device in catalog.devices) {
      if (device.formFactor != 'phone' || device.series == 'Foldable') {
        continue;
      }
      expect(
        device.cornerRadiusPct,
        greaterThan(0.025),
        reason: '${device.id} has a square screen',
      );
    }
  });

  test(
    'a set saved on the old traced Pixels opens on the generated ones',
    () async {
      // The traced Pixel artwork left the repository because its source was
      // never recorded. The generator draws the same three phones under the
      // same device and finish ids, so a saved placement resolves as before.
      final catalog = await loadFrameCatalog();
      const saved = {
        'google-pixel-8-pro': ['black', 'blue', 'silver'],
        'google-pixel-9-pro': ['hazel', 'obsidian', 'rose-quartz'],
        'google-pixel-9-pro-xl': ['hazel', 'obsidian', 'rose-quartz'],
      };
      for (final MapEntry(key: id, value: finishes) in saved.entries) {
        final device = catalog.byId(id);
        expect(device.id, id);
        expect(device.brand, 'Google');
        for (final finish in finishes) {
          final variant = device.variants.firstWhere((v) => v.id == finish);
          expect(
            File(variant.asset).existsSync(),
            isTrue,
            reason: variant.asset,
          );
          expect(
            variant.asset,
            isNot(contains('Google Pixel')),
            reason: 'still the traced file: ${variant.asset}',
          );
        }
      }
      // A device this build has never heard of still draws a phone.
      expect(catalog.byId('no-such-phone'), same(catalog.devices.first));
    },
  );
}
