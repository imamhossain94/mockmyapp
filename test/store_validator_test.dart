// The store export checker: every target's rules, tested the way an export is.
//
// Each group is one console. The numbers are the published ones from
// docs/research/2026-10-02/store-specs.md, asserted literally, because the
// checker's whole value is in getting them exactly right.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mockmyapp/domain/engine/export_settings.dart';
import 'package:mockmyapp/domain/engine/store_validator.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';

/// [target] checked at [canvas] with [count] images, PNG, 1×.
StoreReport check(
  StoreTarget target,
  Size canvas, {
  int count = 3,
  ExportFormat format = ExportFormat.png,
  double scale = 1,
  double? requestedScale,
  bool hasAlpha = false,
  List<int>? fileSizes,
}) => StoreValidator.check(
  target: target,
  canvas: canvas,
  format: format,
  count: count,
  scale: scale,
  requestedScale: requestedScale,
  hasAlpha: hasAlpha,
  fileSizes: fileSizes,
);

CheckLevel? levelOf(StoreReport report, CheckTopic topic) =>
    report[topic]?.level;

bool sizeOk(StoreTarget target, Size size) =>
    StoreValidator.accepts(target, size);

const _mb = 1000 * 1000;

void main() {
  group('every target', () {
    test('accepts every one of its own presets, but two', () {
      // The two Play presets at 2.22:1 are the exception, and the reason the
      // checker exists: Play's long side may be at most twice the short one,
      // and the table offered them as "modern tall displays" for a year.
      const overLimit = {'android-phone-9-20', 'android-phone-landscape-tall'};
      for (final target in StoreTargets.all) {
        for (final preset in target.presets) {
          expect(
            sizeOk(target, preset.size),
            !overLimit.contains(preset.id),
            reason: '${target.id} / ${preset.id}',
          );
        }
      }
    });

    test('reports the rules it has, in a fixed order', () {
      for (final target in StoreTargets.all) {
        final report = check(
          target,
          target.defaultPreset.size,
          count: target.rules.minCount,
          requestedScale: 2,
        );
        final topics = report.checks.map((c) => c.topic).toList();
        expect(topics.first, CheckTopic.size, reason: target.id);
        expect(topics, contains(CheckTopic.format), reason: target.id);
        expect(topics, contains(CheckTopic.count), reason: target.id);
        expect(
          topics.contains(CheckTopic.alpha),
          !target.rules.alphaAllowed,
          reason: '${target.id}: transparency is only mentioned when banned',
        );
        expect(
          topics.contains(CheckTopic.fileSize),
          target.rules.maxBytes != null,
          reason: target.id,
        );
        expect(
          topics.contains(CheckTopic.content),
          target.rules.contentRule != null,
          reason: target.id,
        );
        final sorted = [...topics]..sort((a, b) => a.index.compareTo(b.index));
        expect(topics, sorted, reason: target.id);
      }
    });

    test('its default preset at its minimum count is clear', () {
      for (final target in StoreTargets.all) {
        final report = check(
          target,
          target.defaultPreset.size,
          count: target.rules.recommendedCount ?? target.rules.minCount,
          format: target.rules.formats.first,
        );
        expect(report.hasErrors, isFalse, reason: '${target.id}: $report');
        expect(report.isClear, isTrue, reason: target.id);
      }
    });
  });

  group('App Store screenshots', () {
    final iphone = StoreTargets.iphone;

    test('take exactly the sizes Apple lists, either way up', () {
      for (final size in const [
        Size(1320, 2868),
        Size(1290, 2796),
        Size(1260, 2736),
        Size(1284, 2778),
        Size(1242, 2688),
        Size(1206, 2622),
        Size(1179, 2556),
        Size(1170, 2532),
        Size(1125, 2436),
        Size(1080, 2340),
        Size(1242, 2208),
      ]) {
        expect(sizeOk(iphone, size), isTrue, reason: '$size');
        expect(sizeOk(iphone, size.flipped), isTrue, reason: '$size turned');
      }
      // A landscape the table has no preset for, accepted because Apple takes
      // every iPhone size on its side.
      expect(sizeOk(iphone, const Size(2736, 1260)), isTrue);
    });

    test('refuse anything else, and suggest the nearest', () {
      final report = check(iphone, const Size(1300, 2800));
      final size = report[CheckTopic.size]!;
      expect(size.level, CheckLevel.error);
      expect(size.title, "App Store doesn't take 1300 × 2800");
      expect(size.detail, contains('1320 × 2868'));
      expect(size.fix, isNull, reason: 'resizing a set is not a one-tap fix');
      expect(
        StoreValidator.nearestAccepted(iphone, const Size(1300, 2800)),
        hasLength(3),
      );
      expect(
        StoreValidator.nearestAccepted(
          iphone,
          const Size(2800, 1300),
        ).every((s) => s.width > s.height),
        isTrue,
        reason: 'a landscape canvas is offered landscapes first',
      );
    });

    test('take PNG or JPEG, no transparency, up to 10 MB', () {
      final rules = iphone.rules;
      expect(rules.formats, {ExportFormat.png, ExportFormat.jpg});
      expect(rules.alphaAllowed, isFalse);
      expect(rules.maxBytes, 10 * _mb);
      expect(
        levelOf(check(iphone, const Size(1320, 2868)), CheckTopic.alpha),
        CheckLevel.pass,
      );
      final alpha = check(iphone, const Size(1320, 2868), hasAlpha: true);
      expect(levelOf(alpha, CheckTopic.alpha), CheckLevel.error);
      expect(
        levelOf(
          check(iphone, const Size(1320, 2868), format: ExportFormat.jpg),
          CheckTopic.format,
        ),
        CheckLevel.pass,
      );
    });

    test('take one to ten a listing', () {
      expect(
        levelOf(
          check(iphone, const Size(1320, 2868), count: 0),
          CheckTopic.count,
        ),
        CheckLevel.error,
      );
      expect(
        levelOf(
          check(iphone, const Size(1320, 2868), count: 10),
          CheckTopic.count,
        ),
        CheckLevel.pass,
      );
      final over = check(
        iphone,
        const Size(1320, 2868),
        count: 12,
      )[CheckTopic.count]!;
      expect(over.level, CheckLevel.error);
      expect(over.title, '12 screenshots; App Store takes up to 10');
      expect(over.fix, const ExportFirstFix(10));
    });

    test('iPad takes the 13-inch sizes either way up', () {
      for (final size in const [Size(2064, 2752), Size(2048, 2732)]) {
        expect(sizeOk(StoreTargets.ipad, size), isTrue);
        expect(sizeOk(StoreTargets.ipad, size.flipped), isTrue);
      }
      expect(sizeOk(StoreTargets.ipad, const Size(1668, 2388)), isFalse);
    });

    test('iPhone Duo takes its two displays', () {
      expect(
        sizeOk(StoreTargets.iphoneDuoInner, const Size(2007, 2853)),
        isTrue,
      );
      expect(
        sizeOk(StoreTargets.iphoneDuoInner, const Size(2853, 2007)),
        isTrue,
      );
      expect(
        sizeOk(StoreTargets.iphoneDuoOuter, const Size(1398, 2034)),
        isTrue,
      );
      expect(
        sizeOk(StoreTargets.iphoneDuoOuter, const Size(2007, 2853)),
        isFalse,
        reason: 'the inner display is not an outer size',
      );
    });

    test('Watch takes its five sizes, upright only', () {
      for (final size in const [
        Size(422, 514),
        Size(410, 502),
        Size(416, 496),
        Size(396, 484),
        Size(368, 448),
      ]) {
        expect(sizeOk(StoreTargets.appleWatch, size), isTrue, reason: '$size');
        expect(sizeOk(StoreTargets.appleWatch, size.flipped), isFalse);
      }
    });

    test('TV, Vision Pro and Mac take their sizes, landscape only', () {
      expect(sizeOk(StoreTargets.appleTv, const Size(3840, 2160)), isTrue);
      expect(sizeOk(StoreTargets.appleTv, const Size(1920, 1080)), isTrue);
      expect(sizeOk(StoreTargets.appleTv, const Size(1080, 1920)), isFalse);
      expect(sizeOk(StoreTargets.visionPro, const Size(3840, 2160)), isTrue);
      expect(sizeOk(StoreTargets.visionPro, const Size(1920, 1080)), isFalse);
      for (final size in const [
        Size(2880, 1800),
        Size(2560, 1600),
        Size(1440, 900),
        Size(1280, 800),
      ]) {
        expect(sizeOk(StoreTargets.mac, size), isTrue);
        expect(sizeOk(StoreTargets.mac, size.flipped), isFalse);
      }
    });
  });

  group('App Store artwork', () {
    test('creative assets take their three templates, one image each', () {
      final t = StoreTargets.appStoreCreative;
      expect(sizeOk(t, const Size(3840, 1646)), isTrue);
      expect(sizeOk(t, const Size(3840, 2560)), isTrue);
      expect(sizeOk(t, const Size(5244, 2950)), isTrue);
      expect(sizeOk(t, const Size(1920, 823)), isFalse);
      final two = check(t, const Size(3840, 1646), count: 2)[CheckTopic.count]!;
      expect(two.level, CheckLevel.error);
      expect(two.fix, const ExportFirstFix(1));
      expect(two.fix!.label, 'Export the first');
      final content = check(
        t,
        const Size(3840, 1646),
        count: 1,
      )[CheckTopic.content]!;
      expect(content.level, CheckLevel.info);
      expect(content.detail, contains('No prices'));
    });

    test('an In-App Event card takes any 16:9 from 1080p to 4K', () {
      final card = StoreTargets.appStoreEventCard;
      expect(sizeOk(card, const Size(1920, 1080)), isTrue);
      expect(sizeOk(card, const Size(2560, 1440)), isTrue);
      expect(sizeOk(card, const Size(3840, 2160)), isTrue);
      expect(sizeOk(card, const Size(1600, 900)), isFalse, reason: 'too small');
      expect(sizeOk(card, const Size(4096, 2304)), isFalse, reason: 'too big');
      final wrong = check(card, const Size(1920, 1200), count: 1);
      expect(wrong[CheckTopic.size]!.title, 'App Store needs 16:9');
      expect(wrong[CheckTopic.size]!.detail, contains('8:5'));
    });

    test('an In-App Event page is the card turned upright', () {
      final page = StoreTargets.appStoreEventPage;
      expect(sizeOk(page, const Size(1080, 1920)), isTrue);
      expect(sizeOk(page, const Size(2160, 3840)), isTrue);
      expect(sizeOk(page, const Size(1920, 1080)), isFalse);
      expect(page.requirements, contains('9:16, 1080 × 1920 to 2160 × 3840'));
      expect(
        StoreTargets.appStoreEventCard.requirements,
        contains('16:9, 1920 × 1080 to 3840 × 2160'),
      );
    });
  });

  group('Google Play', () {
    final phone = StoreTargets.androidPhone;

    test('phone screenshots: sides 320–3840, at most 2:1', () {
      expect(sizeOk(phone, const Size(1080, 1920)), isTrue);
      expect(
        sizeOk(phone, const Size(1080, 2160)),
        isTrue,
        reason: '2:1 exactly',
      );
      expect(sizeOk(phone, const Size(320, 640)), isTrue);
      expect(sizeOk(phone, const Size(3840, 2160)), isTrue);

      final tall = check(phone, const Size(1080, 2400))[CheckTopic.size]!;
      expect(tall.title, "Over Google Play's 2:1 limit");
      final small = check(phone, const Size(300, 600))[CheckTopic.size]!;
      expect(small.title, 'Too small for Google Play');
      expect(small.detail, contains('320'));
      final big = check(phone, const Size(2160, 4000))[CheckTopic.size]!;
      expect(big.title, 'Too large for Google Play');
      expect(big.detail, contains('3840'));
    });

    test('phone screenshots: two to eight, four for promotion', () {
      expect(
        levelOf(
          check(phone, const Size(1080, 1920), count: 1),
          CheckTopic.count,
        ),
        CheckLevel.error,
      );
      final three = check(phone, const Size(1080, 1920))[CheckTopic.count]!;
      expect(three.level, CheckLevel.warning);
      expect(three.title, '3 screenshots; Google Play recommends 4 or more');
      expect(
        levelOf(
          check(phone, const Size(1080, 1920), count: 4),
          CheckTopic.count,
        ),
        CheckLevel.pass,
      );
      expect(
        check(phone, const Size(1080, 1920), count: 9)[CheckTopic.count]!.fix,
        const ExportFirstFix(8),
      );
    });

    test('phone screenshots: 8 MB a file, compressible as JPG', () {
      final pending = check(phone, const Size(1080, 1920));
      expect(levelOf(pending, CheckTopic.fileSize), CheckLevel.pending);
      final fine = check(
        phone,
        const Size(1080, 1920),
        fileSizes: [2 * _mb, 3 * _mb],
      );
      expect(levelOf(fine, CheckTopic.fileSize), CheckLevel.pass);
      expect(fine[CheckTopic.fileSize]!.title, 'Largest file 3 MB');
      final over = check(
        phone,
        const Size(1080, 1920),
        fileSizes: [2 * _mb, 8 * _mb + 1, 9 * _mb],
      )[CheckTopic.fileSize]!;
      expect(over.level, CheckLevel.error);
      expect(over.title, '2 files are over 8 MB');
      expect(over.fix, const CompressFix(8 * _mb));
    });

    test('tablets take 9:16 and 16:9 up to 7680 px, and the old 10:16', () {
      final tablet = StoreTargets.androidTablet;
      expect(tablet.defaultPreset.size, const Size(1440, 2560));
      for (final size in const [
        Size(1440, 2560),
        Size(2160, 3840),
        Size(2560, 1440),
        Size(3840, 2160),
        Size(1600, 2560),
        Size(4320, 7680),
      ]) {
        expect(sizeOk(tablet, size), isTrue, reason: '$size');
      }
      expect(sizeOk(tablet, const Size(4320, 8000)), isFalse);
      expect(tablet.rules.minCount, 1, reason: 'tablet sets are optional');
    });

    test('the feature graphic is 1024 × 500 and states no size cap', () {
      final t = StoreTargets.playFeatureGraphic;
      expect(sizeOk(t, const Size(1024, 500)), isTrue);
      expect(sizeOk(t, const Size(2048, 1000)), isFalse);
      expect(t.rules.maxBytes, isNull);
      final report = check(t, const Size(1024, 500), count: 1);
      expect(report[CheckTopic.fileSize], isNull);
      expect(levelOf(report, CheckTopic.alpha), CheckLevel.pass);
      expect(t.requirements, isNot(contains('MB')));
    });

    test('the icon is a 512 PNG under 1024 KB, transparency allowed', () {
      final t = StoreTargets.playIcon;
      expect(sizeOk(t, const Size(512, 512)), isTrue);
      expect(sizeOk(t, const Size(1024, 1024)), isFalse);
      final jpg = check(
        t,
        const Size(512, 512),
        count: 1,
        format: ExportFormat.jpg,
      );
      expect(levelOf(jpg, CheckTopic.format), CheckLevel.error);
      expect(jpg[CheckTopic.format]!.fix, const UsePngFix());
      expect(jpg[CheckTopic.alpha], isNull);
      final heavy = check(
        t,
        const Size(512, 512),
        count: 1,
        fileSizes: [1100 * 1000],
      )[CheckTopic.fileSize]!;
      expect(heavy.level, CheckLevel.error);
      expect(heavy.fix, isNull, reason: 'PNG only, so no JPG to compress to');
    });

    test('Chromebook follows the large-screen rules', () {
      final t = StoreTargets.chromebook;
      expect(sizeOk(t, const Size(1920, 1080)), isTrue);
      expect(sizeOk(t, const Size(2560, 1440)), isTrue);
      expect(sizeOk(t, const Size(3000, 1000)), isFalse, reason: 'over 2:1');
    });

    test(
      'Android XR takes 8:5 from 1920 × 1200 to 3840 × 2400, four to eight',
      () {
        final xr = StoreTargets.androidXr;
        expect(sizeOk(xr, const Size(3840, 2400)), isTrue);
        expect(sizeOk(xr, const Size(1920, 1200)), isTrue);
        expect(sizeOk(xr, const Size(2560, 1600)), isTrue);
        expect(sizeOk(xr, const Size(1280, 800)), isFalse);
        expect(sizeOk(xr, const Size(3840, 2160)), isFalse, reason: '16:9');
        expect(
          levelOf(check(xr, const Size(3840, 2400)), CheckTopic.count),
          CheckLevel.error,
          reason: 'three is under four',
        );
        expect(
          levelOf(
            check(xr, const Size(3840, 2400), count: 4),
            CheckTopic.count,
          ),
          CheckLevel.pass,
        );
      },
    );
  });

  group('Huawei AppGallery', () {
    test('three to eight, 2 MB a file, sides 320–3840', () {
      for (final t in [StoreTargets.huaweiPhone, StoreTargets.huaweiTablet]) {
        expect(t.rules.minCount, 3);
        expect(t.rules.maxCount, 8);
        expect(t.rules.maxBytes, 2 * _mb);
        expect(sizeOk(t, t.defaultPreset.size), isTrue);
        expect(
          sizeOk(t, const Size(1080, 2400)),
          isTrue,
          reason: 'no 2:1 rule',
        );
        expect(sizeOk(t, const Size(300, 1000)), isFalse);
        expect(
          levelOf(check(t, t.defaultPreset.size, count: 2), CheckTopic.count),
          CheckLevel.error,
        );
        final over = check(
          t,
          t.defaultPreset.size,
          fileSizes: [2500 * 1000],
        )[CheckTopic.fileSize]!;
        expect(over.title, 'A file is over 2 MB');
        expect(over.detail, contains('2.5 MB'));
        expect(over.fix, const CompressFix(2 * _mb));
      }
    });
  });

  group('Galaxy Store', () {
    test('the hero image is 1200 × 675 under 1024 KB', () {
      final t = StoreTargets.galaxyHero;
      expect(t.store, StoreKind.galaxyStore);
      expect(sizeOk(t, const Size(1200, 675)), isTrue);
      expect(sizeOk(t, const Size(1920, 1080)), isFalse);
      expect(t.rules.maxBytes, 1024 * 1000);
      final over = check(
        t,
        const Size(1200, 675),
        count: 1,
        fileSizes: [1100 * 1000],
      )[CheckTopic.fileSize]!;
      expect(over.title, 'A file is over 1024 KB');
      expect(over.fix, isA<CompressFix>());
    });
  });

  group('Microsoft Store', () {
    final windows = StoreTargets.windows;

    test('PNG only, with a one-tap fix for JPG', () {
      final jpg = check(
        windows,
        const Size(1920, 1080),
        count: 4,
        format: ExportFormat.jpg,
      )[CheckTopic.format]!;
      expect(jpg.level, CheckLevel.error);
      expect(jpg.title, 'Microsoft Store takes PNG only');
      expect(jpg.fix, const UsePngFix());
      expect(
        levelOf(
          check(windows, const Size(1920, 1080), count: 4),
          CheckTopic.format,
        ),
        CheckLevel.pass,
      );
    });

    test('1366 × 768 to 3840 × 2160, either way up, up to ten', () {
      expect(sizeOk(windows, const Size(1366, 768)), isTrue);
      expect(sizeOk(windows, const Size(768, 1366)), isTrue);
      expect(sizeOk(windows, const Size(3840, 2160)), isTrue);
      expect(sizeOk(windows, const Size(1280, 800)), isFalse);
      expect(sizeOk(windows, const Size(4096, 2160)), isFalse);
      final small = check(windows, const Size(1280, 720), count: 4);
      expect(small[CheckTopic.size]!.detail, contains('1366 × 768'));
      expect(windows.rules.maxCount, 10);
      expect(
        check(
          windows,
          const Size(1920, 1080),
          count: 11,
        )[CheckTopic.count]!.fix,
        const ExportFirstFix(10),
      );
      expect(windows.requirements, contains('up to 10 per listing'));
      expect(windows.requirements, startsWith('PNG only'));
    });

    test('hero art is 1080p or 4K PNG, with nothing in it but art', () {
      final hero = StoreTargets.microsoftHero;
      expect(sizeOk(hero, const Size(1920, 1080)), isTrue);
      expect(sizeOk(hero, const Size(3840, 2160)), isTrue);
      expect(sizeOk(hero, const Size(2560, 1440)), isFalse);
      expect(hero.rules.formats, {ExportFormat.png});
      final note = check(
        hero,
        const Size(1920, 1080),
        count: 1,
      )[CheckTopic.content]!;
      expect(note.detail, contains('No text, app UI or devices'));
    });
  });

  group('Chrome Web Store', () {
    test('screenshots are 1280 × 800 or 640 × 400, one to five', () {
      final web = StoreTargets.web;
      expect(sizeOk(web, const Size(1280, 800)), isTrue);
      expect(sizeOk(web, const Size(640, 400)), isTrue);
      expect(sizeOk(web, const Size(800, 1280)), isFalse);
      expect(web.rules.maxCount, 5);
    });

    test('the promo tiles are exact', () {
      expect(
        sizeOk(StoreTargets.chromeSmallTile, const Size(440, 280)),
        isTrue,
      );
      expect(
        sizeOk(StoreTargets.chromeSmallTile, const Size(880, 560)),
        isFalse,
      );
      expect(sizeOk(StoreTargets.chromeMarquee, const Size(1400, 560)), isTrue);
      expect(
        sizeOk(StoreTargets.chromeMarquee, const Size(1400, 600)),
        isFalse,
      );
    });
  });

  group('social and launch', () {
    test('Open Graph takes anything from 200 px, up to 8 MB', () {
      final og = StoreTargets.openGraph;
      expect(sizeOk(og, const Size(1200, 630)), isTrue);
      expect(sizeOk(og, const Size(600, 315)), isTrue);
      expect(sizeOk(og, const Size(150, 150)), isFalse);
      final report = check(og, const Size(150, 150), count: 1);
      expect(report[CheckTopic.size]!.title, 'Too small for Open Graph');
      expect(og.rules.maxBytes, 8 * _mb);
    });

    test('X takes up to 4096 px and 5 MB', () {
      final x = StoreTargets.xPost;
      expect(sizeOk(x, const Size(1600, 900)), isTrue);
      expect(sizeOk(x, const Size(5000, 2000)), isFalse);
      expect(x.rules.maxBytes, 5 * _mb);
    });

    test('LinkedIn wants at least 1200 × 627', () {
      final li = StoreTargets.linkedIn;
      expect(sizeOk(li, const Size(1200, 627)), isTrue);
      expect(sizeOk(li, const Size(1000, 523)), isFalse);
      final report = check(li, const Size(1000, 523), count: 1);
      expect(report[CheckTopic.size]!.title, 'Too small for LinkedIn');
    });

    test('Product Hunt: a square thumbnail and a gallery of two or more', () {
      final thumb = StoreTargets.productHuntThumbnail;
      expect(sizeOk(thumb, const Size(240, 240)), isTrue);
      expect(sizeOk(thumb, const Size(480, 480)), isTrue);
      expect(sizeOk(thumb, const Size(240, 200)), isFalse);
      final gallery = StoreTargets.productHuntGallery;
      expect(sizeOk(gallery, const Size(1270, 760)), isTrue);
      expect(
        levelOf(
          check(gallery, const Size(1270, 760), count: 1),
          CheckTopic.count,
        ),
        CheckLevel.error,
      );
      expect(
        check(
          gallery,
          const Size(1270, 760),
          count: 1,
        )[CheckTopic.count]!.title,
        '1 screenshot; Product Hunt needs at least 2',
      );
    });
  });

  group('scale', () {
    test('a store export at 1× says when it overrode the setting', () {
      final report = check(
        StoreTargets.iphone,
        const Size(1320, 2868),
        requestedScale: 2,
      );
      final note = report[CheckTopic.scale]!;
      expect(note.level, CheckLevel.info);
      expect(note.title, 'Exported at 1×');
      expect(note.detail, contains('Your 2× setting'));
      expect(
        check(
          StoreTargets.iphone,
          const Size(1320, 2868),
          requestedScale: 1,
        )[CheckTopic.scale],
        isNull,
      );
    });

    test('the size is checked after scaling, rounded as the engine rounds', () {
      expect(
        StoreValidator.outputSize(const Size(1179, 2556), 0.5),
        const Size(590, 1278),
      );
      final doubled = check(
        StoreTargets.iphone,
        const Size(1320, 2868),
        scale: 2,
      );
      expect(doubled[CheckTopic.size]!.level, CheckLevel.error);
      expect(doubled[CheckTopic.size]!.title, contains('2640 × 5736'));
    });

    test('store settings are always 1×', () {
      const settings = ExportSettings(format: ExportFormat.jpg, scale: 3);
      expect(settings.forStore.scale, 1);
      expect(settings.forStore.format, ExportFormat.jpg);
      expect(const ExportSettings().forStore, const ExportSettings());
    });
  });

  group('the export plan', () {
    SubProject set(StoreTarget target, {int screens = 3, Size? canvas}) {
      final size = canvas ?? target.defaultPreset.size;
      return SubProject(
        id: target.id,
        targetId: target.id,
        presetId: target.defaultPreset.id,
        canvas: size,
        screens: [
          for (var i = 0; i < screens; i++) ScreenDoc(id: '$i', canvas: size),
        ],
      );
    }

    test('starts as the user set it, at 1×', () {
      const user = ExportSettings(format: ExportFormat.jpg, scale: 2);
      const plan = StoreExportPlan(user);
      expect(plan.formatFor('a'), ExportFormat.jpg);
      expect(plan.settingsFor('a').scale, 1);
      expect(plan.settingsFor('a').jpegQuality, user.jpegQuality);
      expect(plan.countFor('a', 5), 5);
    });

    test('Use PNG turns one set to PNG and leaves the others', () {
      const plan = StoreExportPlan(ExportSettings(format: ExportFormat.jpg));
      final windows = set(StoreTargets.windows, screens: 4);
      final iphone = set(StoreTargets.iphone);
      expect(plan.reportFor(windows).hasErrors, isTrue);

      final fixed = plan.apply(windows.id, const UsePngFix());
      expect(fixed.formatFor(windows.id), ExportFormat.png);
      expect(fixed.formatFor(iphone.id), ExportFormat.jpg);
      expect(fixed.settingsFor(windows.id).format, ExportFormat.png);
      expect(fixed.reportFor(windows).hasErrors, isFalse);
    });

    test('Export the first N limits that set', () {
      const plan = StoreExportPlan(ExportSettings());
      final phone = set(StoreTargets.androidPhone, screens: 10);
      final report = plan.reportFor(phone);
      final fix = report[CheckTopic.count]!.fix!;
      final fixed = plan.apply(phone.id, fix);
      expect(fixed.countFor(phone.id, 10), 8);
      expect(fixed.take(phone.id, phone.screens), hasLength(8));
      expect(fixed.take(phone.id, phone.screens).first.id, '0');
      expect(fixed.reportFor(phone).hasErrors, isFalse);
      expect(fixed.countFor('other', 10), 10);
    });

    test('compressing works on files, not on the plan', () {
      const plan = StoreExportPlan(ExportSettings());
      expect(plan.apply('a', const CompressFix(1)), same(plan));
    });

    test('a custom canvas is still checked against its store', () {
      const plan = StoreExportPlan(ExportSettings());
      final custom = SubProject(
        id: 'c',
        targetId: StoreTargets.iphone.id,
        presetId: kCustomPresetId,
        canvas: const Size(1500, 1000),
        screens: const [ScreenDoc(id: 's', canvas: Size(1500, 1000))],
      );
      expect(custom.hasCustomCanvas, isTrue);
      expect(plan.reportFor(custom)[CheckTopic.size]!.level, CheckLevel.error);

      final play = SubProject(
        id: 'p',
        targetId: StoreTargets.androidPhone.id,
        presetId: kCustomPresetId,
        canvas: const Size(1000, 1800),
        screens: const [
          ScreenDoc(id: 'a', canvas: Size(1000, 1800)),
          ScreenDoc(id: 'b', canvas: Size(1000, 1800)),
        ],
      );
      expect(
        plan.reportFor(play)[CheckTopic.size]!.level,
        CheckLevel.pass,
        reason: 'inside 320–3840 and 2:1',
      );
    });
  });

  group('compress to fit', () {
    test('brings a heavy PNG under a cap as a JPG', () async {
      // Noise: the worst case for a PNG and a fair one for a JPG.
      final image = img.Image(width: 600, height: 600);
      var seed = 7;
      for (final p in image) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p
          ..r = seed & 0xff
          ..g = (seed >> 8) & 0xff
          ..b = (seed >> 16) & 0xff;
      }
      final png = Uint8List.fromList(img.encodePng(image));
      const cap = 400 * 1000;
      expect(png.length, greaterThan(cap));

      final out = await compressToFit(png, cap);
      expect(out, isNotNull);
      expect(out!.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG magic');
      expect(out.length, lessThanOrEqualTo(cap));
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 600);
      expect(decoded.height, 600);
    });

    test('hands back its smallest attempt when nothing fits', () async {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 64, height: 64)),
      );
      final out = await compressToFit(png, 10);
      expect(out, isNotNull);
      expect(out!.length, greaterThan(10));
    });

    test('says nothing it cannot read', () async {
      expect(await compressToFit(Uint8List.fromList([1, 2, 3]), 10), isNull);
    });
  });

  group('readouts', () {
    test('ratios read as the stores write them', () {
      expect(ratioLabel(16 / 9), '16:9');
      expect(ratioLabel(9 / 16), '9:16');
      expect(ratioLabel(1.6), '8:5');
      expect(ratioLabel(2), '2:1');
      expect(ratioLabel(1), '1:1');
      expect(ratioLabel(1.92), '1.92');
    });

    test('byte caps print as written, file sizes round up', () {
      expect(formatBytes(10 * _mb), '10 MB');
      expect(formatBytes(1024 * 1000), '1024 KB');
      expect(formatBytes(2 * _mb + 1), '2.1 MB');
      expect(formatBytes(812345), '813 KB');
    });
  });
}
