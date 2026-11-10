// The fastlane layouts: where each set's files go so `fastlane deliver` and
// `fastlane supply` upload them as they are.

import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/repositories/fastlane_layout.dart';
import 'package:mockmyapp/data/repositories/graphics_archive.dart';
import 'package:mockmyapp/domain/models/store_target.dart';

FastlaneSlot? slot(StoreTarget target, {Size? canvas, String? preset}) =>
    FastlaneLayout.slotFor(
      target,
      canvas ?? target.defaultPreset.size,
      preset ?? target.defaultPreset.id,
    );

void main() {
  group('deliver', () {
    test('files each iPhone class under its App Store Connect type', () {
      const cases = [
        (Size(1320, 2868), 'APP_IPHONE_67'),
        (Size(1290, 2796), 'APP_IPHONE_67'),
        (Size(2868, 1320), 'APP_IPHONE_67'),
        (Size(1284, 2778), 'APP_IPHONE_65'),
        (Size(1206, 2622), 'APP_IPHONE_61'),
        (Size(1179, 2556), 'APP_IPHONE_61'),
        (Size(1170, 2532), 'APP_IPHONE_61'),
        (Size(1125, 2436), 'APP_IPHONE_58'),
        (Size(1242, 2208), 'APP_IPHONE_55'),
      ];
      for (final (canvas, type) in cases) {
        final s = slot(StoreTargets.iphone, canvas: canvas)!;
        expect(s.tool, FastlaneTool.deliver);
        expect(s.folder, 'screenshots');
        expect(s.displayType, type, reason: '$canvas');
      }
    });

    test("names iPad files so deliver knows they're the 13-inch class", () {
      for (final canvas in const [
        Size(2064, 2752),
        Size(2048, 2732),
        Size(2732, 2048),
      ]) {
        expect(
          slot(StoreTargets.ipad, canvas: canvas)!.displayType,
          'APP_IPAD_PRO_3GEN_129',
        );
      }
      final path = slot(
        StoreTargets.ipad,
      )!.pathFor(language: 'en-US', index: 0, extension: 'png');
      expect(path, 'screenshots/en-US/APP_IPAD_PRO_3GEN_129_01.png');
    });

    test('puts each file in its locale, numbered in set order', () {
      final s = slot(StoreTargets.iphone)!;
      expect(
        s.pathFor(language: 'en-US', index: 0, extension: 'png'),
        'screenshots/en-US/APP_IPHONE_67_01.png',
      );
      expect(
        s.pathFor(language: 'ja-JP', index: 9, extension: 'jpg'),
        'screenshots/ja/APP_IPHONE_67_10.jpg',
      );
    });

    test('keeps the watch with the iPhone, and other platforms apart', () {
      expect(slot(StoreTargets.appleWatch)!.folder, 'screenshots');
      expect(slot(StoreTargets.appleWatch)!.displayType, 'APP_WATCH_ULTRA');
      expect(
        slot(
          StoreTargets.appleWatch,
          canvas: const Size(368, 448),
        )!.displayType,
        'APP_WATCH_SERIES_4',
      );
      expect(slot(StoreTargets.mac)!.folder, 'screenshots-macos');
      expect(slot(StoreTargets.mac)!.displayType, 'APP_DESKTOP');
      expect(slot(StoreTargets.appleTv)!.folder, 'screenshots-tvos');
      expect(slot(StoreTargets.visionPro)!.folder, 'screenshots-visionos');
    });

    test('leaves out what App Store Connect has no slot for, saying why', () {
      for (final target in [
        StoreTargets.iphoneDuoInner,
        StoreTargets.iphoneDuoOuter,
        StoreTargets.appStoreCreative,
        StoreTargets.appStoreEventCard,
        StoreTargets.appStoreEventPage,
      ]) {
        expect(slot(target), isNull, reason: target.id);
        expect(
          FastlaneLayout.skipReason(
            target,
            target.defaultPreset.size,
            target.defaultPreset.id,
          ),
          isNotNull,
        );
      }
      // A custom canvas is no device class at all.
      expect(slot(StoreTargets.iphone, canvas: const Size(1500, 1000)), isNull);
      expect(slot(StoreTargets.mac, canvas: const Size(1500, 1000)), isNull);
      expect(slot(StoreTargets.appleTv, canvas: const Size(1280, 720)), isNull);
      expect(
        FastlaneLayout.skipReason(
          StoreTargets.iphone,
          const Size(1500, 1000),
          kCustomPresetId,
        ),
        contains('1500 × 1000'),
      );
    });
  });

  group('supply', () {
    test('puts phone and tablet screenshots in their folders', () {
      final phone = slot(StoreTargets.androidPhone)!;
      expect(phone.tool, FastlaneTool.supply);
      expect(
        phone.pathFor(language: 'en-US', index: 0, extension: 'png'),
        'metadata/android/en-US/images/phoneScreenshots/01.png',
      );
      expect(
        slot(
          StoreTargets.androidTablet,
        )!.pathFor(language: 'de-DE', index: 1, extension: 'png'),
        'metadata/android/de-DE/images/tenInchScreenshots/02.png',
      );
      expect(
        slot(StoreTargets.androidTablet, preset: 'android-tablet-7')!.folder,
        'sevenInchScreenshots',
      );
    });

    test('names the feature graphic and the icon as single files', () {
      final graphic = slot(StoreTargets.playFeatureGraphic)!;
      expect(graphic.single, isTrue);
      expect(
        graphic.pathFor(language: 'en-US', index: 0, extension: 'png'),
        'metadata/android/en-US/images/featureGraphic.png',
      );
      expect(
        slot(
          StoreTargets.playIcon,
        )!.pathFor(language: 'zh-Hans', index: 0, extension: 'png'),
        'metadata/android/zh-CN/images/icon.png',
      );
    });

    test('has no slot for Chromebook or Android XR', () {
      expect(slot(StoreTargets.chromebook), isNull);
      expect(slot(StoreTargets.androidXr), isNull);
      expect(
        FastlaneLayout.skipReason(
          StoreTargets.androidXr,
          const Size(3840, 2400),
          'xr-3840',
        ),
        contains('Android XR'),
      );
    });

    test('nothing outside Apple and Google goes in', () {
      for (final target in StoreTargets.all) {
        if (target.store == StoreKind.appStore ||
            target.store == StoreKind.macAppStore ||
            target.store == StoreKind.playStore) {
          continue;
        }
        expect(slot(target), isNull, reason: target.id);
      }
    });
  });

  group('locales', () {
    test('as App Store Connect names them', () {
      expect(FastlaneLayout.appleLocale('en-US'), 'en-US');
      expect(FastlaneLayout.appleLocale('de-DE'), 'de-DE');
      expect(FastlaneLayout.appleLocale('ja-JP'), 'ja');
      expect(FastlaneLayout.appleLocale('nb-NO'), 'no');
      expect(FastlaneLayout.appleLocale('zh-Hans'), 'zh-Hans');
      expect(FastlaneLayout.appleLocale('xx-YY'), 'xx-YY');
    });

    test('as the Play Console names them', () {
      expect(FastlaneLayout.playLocale('en-US'), 'en-US');
      expect(FastlaneLayout.playLocale('ja-JP'), 'ja-JP');
      expect(FastlaneLayout.playLocale('zh-Hans'), 'zh-CN');
      expect(FastlaneLayout.playLocale('zh-Hant'), 'zh-TW');
      expect(FastlaneLayout.playLocale('he-IL'), 'iw-IL');
      expect(FastlaneLayout.playLocale('es-MX'), 'es-419');
    });
  });

  test('the archive keeps every path exactly as given', () {
    final zip = GraphicsArchive.bundleFiles([
      (
        path: 'fastlane/screenshots/en-US/APP_IPHONE_67_01.png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      (
        path: 'fastlane/metadata/android/en-US/images/featureGraphic.png',
        bytes: Uint8List.fromList([4]),
      ),
    ]);
    final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name);
    expect(names, [
      'fastlane/screenshots/en-US/APP_IPHONE_67_01.png',
      'fastlane/metadata/android/en-US/images/featureGraphic.png',
    ]);
  });
}
