import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/stage_transform.dart';

/// The retouch stage's viewport maths.
///
/// This is the first test any of it has ever had. Every line of it used to be
/// private state on a `State` object, which is how a pointer-mapping bug lived
/// in the one widget where mapping is the entire job.
void main() {
  // A tall phone capture, which is the case that catches axis mix-ups: a rect
  // that is square in normalised space is nothing like square on screen.
  const image = Size(1080, 2340);
  const whole = Rect.fromLTRB(0, 0, 1, 1);

  StageTransform stage({
    Size viewport = const Size(400, 800),
    EdgeInsets chrome = EdgeInsets.zero,
    Rect document = whole,
  }) => StageTransform(
    document: document,
    viewport: viewport,
    scale: 1,
    offset: Offset.zero,
    chromeInsets: chrome,
  ).fitted(image);

  group('fitting', () {
    test('fits inside the safe box and centres there', () {
      final t = stage();
      final rect = t.contentRect(image);
      // 1080x2340 in a 400x800 box is height-limited: 800 tall, 369 wide.
      expect(rect.height, closeTo(800, 0.5));
      expect(rect.width, closeTo(800 * 1080 / 2340, 0.5));
      expect(rect.center.dx, closeTo(200, 0.5));
      expect(rect.center.dy, closeTo(400, 0.5));
    });

    test('chrome takes room from the fit, not from the artwork later', () {
      // The whole point of carrying insets rather than wrapping the stage in a
      // Padding: the artwork is fitted to what is free, and may still be
      // painted under the chrome when panned.
      final bare = stage();
      final withDock = stage(chrome: const EdgeInsets.fromLTRB(0, 60, 0, 200));
      expect(withDock.scale, lessThan(bare.scale));
      final rect = withDock.contentRect(image);
      expect(rect.height, closeTo(800 - 260, 0.5));
      // Centred in the free space, which sits above the dock.
      expect(rect.center.dy, closeTo(60 + (800 - 260) / 2, 0.5));
    });
  });

  group('mapping', () {
    test('a stage point and back is the same document point', () {
      final t = stage(chrome: const EdgeInsets.all(20));
      for (final p in const [
        Offset(0.5, 0.5),
        Offset(0, 0),
        Offset(1, 1),
        Offset(0.2, 0.8),
      ]) {
        final round = t.toDocument(t.toStage(p, image), image);
        expect(round.dx, closeTo(p.dx, 1e-9), reason: '$p');
        expect(round.dy, closeTo(p.dy, 1e-9), reason: '$p');
      }
    });

    test('the middle of the artwork is the middle of the safe box', () {
      final t = stage(chrome: const EdgeInsets.fromLTRB(0, 60, 0, 200));
      final at = t.toStage(const Offset(0.5, 0.5), image);
      expect(at.dx, closeTo(200, 0.5));
      expect(at.dy, closeTo(60 + (800 - 260) / 2, 0.5));
    });
  });

  group('zoom', () {
    test('zooming pins the point under the finger', () {
      final t = stage();
      const focal = Offset(120, 300);
      final before = t.toDocument(focal, image);
      final after = t.zoomAbout(t.scale * 3, focal, image);
      final now = after.toDocument(focal, image);
      expect(now.dx, closeTo(before.dx, 1e-6));
      expect(now.dy, closeTo(before.dy, 1e-6));
    });

    test('it can zoom BELOW fit, which the old window model could not', () {
      // A sub-rect of the document cannot be larger than the document, so the
      // old model's floor was fit. Pulling the artwork smaller than the window
      // is what lets an expanded crop be seen whole, with its margins.
      final t = stage();
      final out = t.zoomAbout(t.scale * 0.5, const Offset(200, 400), image);
      expect(out.scale, lessThan(t.scale));
      expect(out.contentRect(image).height, lessThan(800));
    });

    test(
      'the limits are relative to fit, so they mean the same everywhere',
      () {
        final small = stage(viewport: const Size(200, 400));
        final large = stage(viewport: const Size(800, 1600));
        // Four times the window, so four times the fit scale...
        expect(large.scale / small.scale, closeTo(4, 0.01));
        // ...and the same magnification ceiling in both.
        final smallMax = small.zoomAbout(1e9, const Offset(100, 200), image);
        final largeMax = large.zoomAbout(1e9, const Offset(400, 800), image);
        expect(largeMax.scale / smallMax.scale, closeTo(4, 0.01));
      },
    );
  });

  group('panning', () {
    test('the artwork always keeps some overlap with the safe box', () {
      final t = stage().zoomAbout(
        stage().scale * 4,
        const Offset(200, 400),
        image,
      );
      final flung = t.panned(const Offset(100000, 100000), image);
      final rect = flung.contentRect(image);
      expect(
        rect.overlaps(flung.safeBox),
        isTrue,
        reason: 'panned entirely off the stage: $rect',
      );
    });

    test(
      'an artwork smaller than the box is centred, not pinned to an edge',
      () {
        final t = stage();
        final out = t.zoomAbout(t.scale * 0.4, const Offset(200, 400), image);
        final nudged = out.panned(const Offset(500, 500), image);
        final rect = nudged.contentRect(image);
        expect(rect.center.dx, closeTo(200, 0.5));
        expect(rect.center.dy, closeTo(400, 0.5));
      },
    );

    test('at fit the artwork stays put when panned', () {
      // Fit is exactly the "content is not larger than the box" case, so it
      // centres — panning at fit cannot drift the picture off-centre.
      final t = stage();
      final nudged = t.panned(const Offset(80, -40), image);
      expect(nudged.contentRect(image).center.dx, closeTo(200, 0.5));
    });
  });

  test('the visible document narrows as you zoom in', () {
    final t = stage();
    final wide = t.visibleDocument(image);
    final tight = t
        .zoomAbout(t.scale * 4, const Offset(200, 400), image)
        .visibleDocument(image);
    expect(tight.width, lessThan(wide.width));
    expect(tight.height, lessThan(wide.height));
  });
}
