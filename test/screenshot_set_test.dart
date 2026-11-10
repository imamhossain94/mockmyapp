// A frame carries a set of screenshots, not one — see `ScreenshotSpec.images`.
//
// The risk this guards is quiet rather than loud. Every renderer, exporter and
// thumbnail reads `imagePath`, which is now derived; every backup and copy
// rewrites paths, and one that rewrote only the visible capture would leave a
// frame's alternates pointing at files that no longer exist. None of that
// throws. It just loses pictures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  group('the active image', () {
    test('an empty set has none', () {
      const spec = ScreenshotSpec();
      expect(spec.imagePath, isNull);
      expect(spec.hasAlternates, isFalse);
      expect(spec.activeIndex, 0);
    });

    test('a set of one behaves exactly as a single image did', () {
      final spec = ScreenshotSpec.of('/a.png');
      expect(spec.imagePath, '/a.png');
      expect(spec.images, ['/a.png']);
      expect(spec.hasAlternates, isFalse);
    });

    test('an index past the end degrades to the last image', () {
      // A document can lose an image to a failed library repair, and an index
      // left pointing past the end must not throw inside a paint.
      const spec = ScreenshotSpec(images: ['/a.png', '/b.png'], index: 7);
      expect(spec.imagePath, '/b.png');
      expect(spec.activeIndex, 1);
    });
  });

  group('copyWith', () {
    test('imagePath replaces the active slot, not the whole set', () {
      const spec = ScreenshotSpec(images: ['/a.png', '/b.png'], index: 1);
      final next = spec.copyWith(imagePath: '/edited.png');
      expect(next.images, ['/a.png', '/edited.png']);
      expect(next.activeIndex, 1);
    });

    test('imagePath on an empty set seeds it', () {
      const spec = ScreenshotSpec();
      expect(spec.copyWith(imagePath: '/a.png').images, ['/a.png']);
    });

    test('clearImages is the only way to empty it', () {
      // `imagePath: null` reads as "leave this alone", which is why
      // `ProjectStore.addScreen` used to hand every new screen the previous
      // screen's capture while asking for exactly that.
      final spec = ScreenshotSpec.of('/a.png', cornerRadiusPct: 0.09);
      expect(spec.copyWith(imagePath: null).imagePath, '/a.png');

      final cleared = spec.copyWith(clearImages: true);
      expect(cleared.images, isEmpty);
      expect(cleared.imagePath, isNull);
      expect(
        cleared.cornerRadiusPct,
        0.09,
        reason: 'the framing belongs to the frame, not to the picture',
      );
    });

    test('the framing survives switching image', () {
      const spec = ScreenshotSpec(
        images: ['/a.png', '/b.png'],
        cornerRadiusPct: 0.09,
        strokeWidthPct: 0.01,
        scale: 1.4,
        offsetX: -0.2,
      );
      final next = spec.copyWith(index: 1);
      expect(next.imagePath, '/b.png');
      expect(next.cornerRadiusPct, 0.09);
      expect(next.strokeWidthPct, 0.01);
      expect(next.scale, 1.4);
      expect(next.offsetX, -0.2);
    });
  });

  group('adding and removing', () {
    test('a batch lands in order and shows the first new one', () {
      final spec = ScreenshotSpec.of('/a.png');
      final next = spec.withImagesAdded(['/b.png', '/c.png']);
      expect(next.images, ['/a.png', '/b.png', '/c.png']);
      expect(next.imagePath, '/b.png');
    });

    test('duplicates are dropped', () {
      // The library hands back the same path for the same file, and a set
      // holding one capture twice is a set the user has to tidy by hand.
      const spec = ScreenshotSpec(images: ['/a.png']);
      final next = spec.withImagesAdded(['/a.png', '/b.png', '/a.png']);
      expect(next.images, ['/a.png', '/b.png']);
    });

    test('adding nothing new leaves the set untouched', () {
      const spec = ScreenshotSpec(images: ['/a.png'], index: 0);
      expect(spec.withImagesAdded(['/a.png', '']).images, ['/a.png']);
    });

    test('removing keeps the view on a neighbour', () {
      const spec = ScreenshotSpec(images: ['/a.png', '/b.png', '/c.png']);
      expect(spec.withImageRemoved(0).images, ['/b.png', '/c.png']);

      // Removing the last one must step the index back rather than leave it
      // off the end.
      const onLast = ScreenshotSpec(images: ['/a.png', '/b.png'], index: 1);
      final next = onLast.withImageRemoved(1);
      expect(next.images, ['/a.png']);
      expect(next.activeIndex, 0);
    });

    test('removing the only image empties the set', () {
      expect(ScreenshotSpec.of('/a.png').withImageRemoved(0).images, isEmpty);
    });

    test('an out-of-range removal is a no-op', () {
      const spec = ScreenshotSpec(images: ['/a.png']);
      expect(spec.withImageRemoved(4).images, ['/a.png']);
      expect(spec.withImageRemoved(-1).images, ['/a.png']);
    });
  });

  group('mapImages', () {
    test('rewrites every path, not just the visible one', () {
      // The failure this exists for: a backup restore or a target copy that
      // repointed only `imagePath` left the alternates aimed at files that did
      // not travel.
      const spec = ScreenshotSpec(
        images: ['/old/a.png', '/old/b.png'],
        index: 1,
      );
      final moved = spec.mapImages((p) => p.replaceFirst('/old/', '/new/'));
      expect(moved.images, ['/new/a.png', '/new/b.png']);
      expect(moved.activeIndex, 1, reason: 'the slot does not move');
    });

    test('an empty set is left alone', () {
      const spec = ScreenshotSpec();
      expect(spec.mapImages((p) => '/never').images, isEmpty);
    });
  });

  group('serialization', () {
    test('a set survives a round-trip', () {
      const spec = ScreenshotSpec(
        images: ['/a.png', '/b.png', '/c.png'],
        index: 2,
        cornerRadiusPct: 0.09,
        strokeColor: Color(0xFF112233),
      );
      final back = screenshotFromJson(screenshotToJson(spec));
      expect(back.images, spec.images);
      expect(back.activeIndex, 2);
      expect(back.imagePath, '/c.png');
      expect(back.cornerRadiusPct, 0.09);
      expect(back.strokeColor, const Color(0xFF112233));
    });

    test('a project written before sets existed reads as a set of one', () {
      final json = {
        'imagePath': '/legacy.png',
        'cornerRadiusPct': 0.05,
        'strokeWidthPct': 0.0,
        'strokeColor': 0xFF000000,
        'scale': 1.0,
        'offsetX': 0.0,
        'offsetY': 0.0,
      };
      final spec = screenshotFromJson(json);
      expect(spec.images, ['/legacy.png']);
      expect(spec.imagePath, '/legacy.png');
    });

    test('a legacy document with no image at all reads as empty', () {
      final json = screenshotToJson(const ScreenshotSpec())
        ..remove('images')
        ..remove('index');
      expect(screenshotFromJson(json).images, isEmpty);
    });

    test('the active image is still written under the old key', () {
      // So a build from before sets existed opens the project showing the
      // capture that was on screen, rather than an empty frame.
      const spec = ScreenshotSpec(images: ['/a.png', '/b.png'], index: 1);
      expect(screenshotToJson(spec)['imagePath'], '/b.png');
    });

    test('empty paths are dropped on read', () {
      final json = screenshotToJson(const ScreenshotSpec());
      json['images'] = ['', '/a.png', ''];
      expect(screenshotFromJson(json).images, ['/a.png']);
    });
  });
}
