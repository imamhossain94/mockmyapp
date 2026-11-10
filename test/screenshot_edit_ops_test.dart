import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/services/device_storage.dart';
import 'package:mockmyapp/domain/models/shape_spec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';

/// A solid-colour image to composite against.
Future<ui.Image> _solidImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  group('coverCrop', () {
    test('trims the sides of a source wider than the target', () {
      // 16:9 source into a 9:19.5 phone screen.
      final crop = coverCrop(imageAspect: 16 / 9, aspect: 9 / 19.5);
      expect(crop.top, 0);
      expect(crop.height, 1);
      expect(crop.width, lessThan(1));
      // Centred.
      expect(crop.left, closeTo((1 - crop.width) / 2, 1e-9));
    });

    test('trims top and bottom of a source taller than the target', () {
      final crop = coverCrop(imageAspect: 9 / 21, aspect: 9 / 16);
      expect(crop.left, 0);
      expect(crop.width, 1);
      expect(crop.height, lessThan(1));
      expect(crop.top, closeTo((1 - crop.height) / 2, 1e-9));
    });

    test('is the identity when the ratios already match', () {
      final crop = coverCrop(imageAspect: 0.5, aspect: 0.5);
      expect(crop.width, closeTo(1, 1e-9));
      expect(crop.height, closeTo(1, 1e-9));
    });

    test('degrades to the whole image on a nonsense ratio', () {
      expect(
        coverCrop(imageAspect: 0.5, aspect: 0),
        const Rect.fromLTRB(0, 0, 1, 1),
      );
      expect(
        coverCrop(imageAspect: double.nan, aspect: 0.5),
        const Rect.fromLTRB(0, 0, 1, 1),
      );
    });
  });

  group('clampCrop', () {
    test('pulls a rect that ran off the edge back inside', () {
      final clamped = clampCrop(const Rect.fromLTWH(0.8, 0.9, 0.4, 0.3));
      expect(clamped.right, lessThanOrEqualTo(1.0));
      expect(clamped.bottom, lessThanOrEqualTo(1.0));
      // The size survives; only the origin moves.
      expect(clamped.width, closeTo(0.4, 1e-9));
      expect(clamped.height, closeTo(0.3, 1e-9));
    });

    test('never collapses below a usable size', () {
      final clamped = clampCrop(const Rect.fromLTWH(0.5, 0.5, 0.0, 0.0));
      expect(clamped.width, greaterThanOrEqualTo(0.05));
      expect(clamped.height, greaterThanOrEqualTo(0.05));
    });
  });

  group('resizeCropFromCorner', () {
    // A 1200x2600 capture going into a 9:19.5 phone screen.
    const imageSize = Size(1200, 2600);
    const target = 9 / 19.5;

    double pixelAspect(Rect crop) =>
        (crop.width * imageSize.width) / (crop.height * imageSize.height);

    test('keeps the device ratio whatever the finger does', () {
      final base = coverCrop(
        imageAspect: imageSize.width / imageSize.height,
        aspect: target,
      );

      for (final handle in CropHandle.values) {
        for (final dx in [0.05, 0.2, 0.45, 0.9]) {
          final resized = resizeCropFromCorner(
            base: base,
            handle: handle,
            pointer: Offset(dx, 0.5),
            imageSize: imageSize,
            targetAspect: target,
          );
          expect(
            pixelAspect(resized),
            closeTo(target, 1e-6),
            reason: '$handle at dx=$dx drifted off ratio',
          );
        }
      }
    });

    test('pins the opposite corner', () {
      const base = Rect.fromLTWH(0.2, 0.2, 0.4, 0.3);

      final fromTopLeft = resizeCropFromCorner(
        base: base,
        handle: CropHandle.topLeft,
        pointer: const Offset(0.3, 0.25),
        imageSize: imageSize,
        targetAspect: target,
      );
      expect(fromTopLeft.right, closeTo(base.right, 1e-9));

      final fromBottomRight = resizeCropFromCorner(
        base: base,
        handle: CropHandle.bottomRight,
        pointer: const Offset(0.5, 0.4),
        imageSize: imageSize,
        targetAspect: target,
      );
      expect(fromBottomRight.left, closeTo(base.left, 1e-9));
      expect(fromBottomRight.top, closeTo(base.top, 1e-9));
    });

    test('never leaves the image, even when dragged well past the edge', () {
      const base = Rect.fromLTWH(0.1, 0.1, 0.3, 0.6);
      for (final handle in CropHandle.values) {
        final resized = resizeCropFromCorner(
          base: base,
          handle: handle,
          pointer: const Offset(-5, -5),
          imageSize: imageSize,
          targetAspect: target,
        );
        expect(resized.left, greaterThanOrEqualTo(-1e-9));
        expect(resized.top, greaterThanOrEqualTo(-1e-9));
        expect(resized.right, lessThanOrEqualTo(1 + 1e-9));
        expect(resized.bottom, lessThanOrEqualTo(1 + 1e-9));
        // Bounded growth means clampCrop never had to reshape it.
        expect(pixelAspect(resized), closeTo(target, 1e-6));
      }
    });

    test('gives up rather than producing a degenerate rect', () {
      // Dragging the top-right corner pins the left edge, and that edge is hard
      // against the right of the image — so there is nowhere left to grow.
      const base = Rect.fromLTWH(0.99, 0.4, 0.01, 0.02);
      final resized = resizeCropFromCorner(
        base: base,
        handle: CropHandle.topRight,
        pointer: const Offset(0.5, 0.5),
        imageSize: imageSize,
        targetAspect: target,
      );
      expect(resized, base);
    });

    group('edge handles', () {
      const base = Rect.fromLTWH(0.2, 0.2, 0.4, 0.3);

      test('unlocked, a side grip moves one edge and nothing else', () {
        final resized = resizeCropFromCorner(
          base: base,
          handle: CropHandle.right,
          pointer: const Offset(0.8, 0.9),
          imageSize: imageSize,
          targetAspect: target,
          lockAspect: false,
        );
        // The dragged edge follows the finger's x…
        expect(resized.right, closeTo(0.8, 1e-9));
        // …and the other three sides are exactly where they were, including
        // the vertical ones the finger also travelled across.
        expect(resized.left, closeTo(base.left, 1e-9));
        expect(resized.top, closeTo(base.top, 1e-9));
        expect(resized.bottom, closeTo(base.bottom, 1e-9));
      });

      test('unlocked, an end grip moves one edge and nothing else', () {
        final resized = resizeCropFromCorner(
          base: base,
          handle: CropHandle.top,
          pointer: const Offset(0.9, 0.05),
          imageSize: imageSize,
          targetAspect: target,
          lockAspect: false,
        );
        expect(resized.top, closeTo(0.05, 1e-9));
        expect(resized.bottom, closeTo(base.bottom, 1e-9));
        expect(resized.left, closeTo(base.left, 1e-9));
        expect(resized.right, closeTo(base.right, 1e-9));
      });

      test('locked, the derived axis grows about the centre', () {
        final resized = resizeCropFromCorner(
          base: base,
          handle: CropHandle.right,
          pointer: const Offset(0.7, 0.5),
          imageSize: imageSize,
          targetAspect: target,
        );
        expect(pixelAspect(resized), closeTo(target, 1e-6));
        expect(resized.left, closeTo(base.left, 1e-9));
        // Height changed, but the crop did not slide up or down to do it.
        expect(resized.center.dy, closeTo(base.center.dy, 1e-9));
      });

      test('expand lets a side grip reach past the artwork', () {
        final blocked = resizeCropFromCorner(
          base: const Rect.fromLTWH(0.2, 0.3, 0.4, 0.3),
          handle: CropHandle.right,
          pointer: const Offset(2, 0.45),
          imageSize: imageSize,
          targetAspect: target,
          lockAspect: false,
        );
        expect(blocked.right, closeTo(1, 1e-9));

        final expanded = resizeCropFromCorner(
          base: const Rect.fromLTWH(0.2, 0.3, 0.4, 0.3),
          handle: CropHandle.right,
          pointer: const Offset(2, 0.45),
          imageSize: imageSize,
          targetAspect: target,
          lockAspect: false,
          expand: true,
        );
        expect(expanded.right, closeTo(1 + kMaxExpand, 1e-9));
      });
    });
  });

  group('ScreenshotComposer', () {
    test(
      'exports at the cropped source resolution, not the canvas size',
      () async {
        final image = await _solidImage(1200, 2600, const Color(0xFF112233));
        final composer = ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.5),
          ops: const [],
        );

        expect(composer.exportSize, const Size(600, 1300));
        // Compared per-edge: the crop is stored as a fraction, so the pixel rect
        // carries the usual binary-fraction dust.
        expect(composer.sourceRect.left, closeTo(120, 1e-6));
        expect(composer.sourceRect.top, closeTo(520, 1e-6));
        expect(composer.sourceRect.width, closeTo(600, 1e-6));
        expect(composer.sourceRect.height, closeTo(1300, 1e-6));

        final png = await composer.toPng();
        expect(png, isNotNull);
        expect(png, isA<Uint8List>());
        // PNG magic number — proves a real encode happened.
        expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

        image.dispose();
      },
    );

    test('a redaction op lands inside the exported pixels', () async {
      final image = await _solidImage(100, 200, const Color(0xFFFFFFFF));
      final composer = ScreenshotComposer(
        image: image,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: [_hidden(const Rect.fromLTRB(0, 0, 1, 0.1), const Size(100, 200))],
      );

      // Re-render through the same paint path the export uses and read it back.
      final recorder = ui.PictureRecorder();
      composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 100, 200));
      final rendered = await recorder.endRecording().toImage(100, 200);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      int red(int x, int y) => data!.getUint8((y * 100 + x) * 4);

      // Inside the redaction: black. Below it: untouched white.
      expect(red(50, 5), 0);
      expect(red(50, 150), 255);

      rendered.dispose();
      image.dispose();
    });
  });

  group('placed objects', () {
    ShapeOp red({
      Offset center = const Offset(0.5, 0.5),
      double width = 0.4,
      double height = 0.4,
      double rotationDeg = 0,
      double opacity = 1,
    }) => ShapeOp(
      id: 1,
      spec: const ShapeSpec(
        kind: ShapeKind.rectangle,
        fill: Color(0xFFFF0000),
        cornerRadius: 0,
      ),
      center: center,
      width: width,
      height: height,
      rotationDeg: rotationDeg,
      opacity: opacity,
    );

    test('equal width and height is a square, whatever the capture', () {
      // Both edges are measured against the image's WIDTH. Measuring height
      // against the height is the mistake `ShapeSpec` documents having made
      // once, which turned every circle on a tall canvas into an ellipse — a
      // phone capture is 9:19.5, so it would be wrong by more than double.
      final box = red().localBox(const Size(200, 400));
      expect(box.width, box.height);
      expect(box.width, closeTo(80, 1e-9));
    });

    test('a hit lands inside the box and misses outside it', () {
      const size = Size(200, 400);
      final op = red(center: const Offset(0.5, 0.25), width: 0.4, height: 0.4);
      // Box is 80x80px centred at (100, 100), so x 60..140 and y 60..140.
      expect(op.hitTest(const Offset(0.5, 0.25), size), isTrue);
      // 0.7 is 140px — the right edge, still inside.
      expect(op.hitTest(const Offset(0.69, 0.25), size), isTrue);
      // 0.75 is 150px, past it.
      expect(op.hitTest(const Offset(0.75, 0.25), size), isFalse);
      // 0.6 of the HEIGHT is 240px, well below the box.
      expect(op.hitTest(const Offset(0.5, 0.6), size), isFalse);
    });

    test('a rotated hit test un-rotates in pixels, not in fractions', () {
      // The regression this guards. Normalised x and y divide by different
      // edges, so a rotation applied in normalised space is a shear: on a
      // 1:2 capture a 45-degree box would be tested as a lopsided diamond and
      // miss by more the further from square the picture is.
      const size = Size(200, 400);
      final op = red(center: const Offset(0.5, 0.25), width: 0.4, height: 0.1);

      // A 40x8px bar turned upright is 8 wide and 40 tall about its centre.
      final upright = op.withPlacement(rotationDeg: 90);
      // 30px below centre = 0.075 of the 400px height, inside the turned bar.
      expect(upright.hitTest(const Offset(0.5, 0.325), size), isTrue);
      // 30px to the right = 0.15 of the 200px width, outside it.
      expect(upright.hitTest(const Offset(0.65, 0.25), size), isFalse);

      // And the same two points against the un-turned bar, which must answer
      // the other way round.
      expect(op.hitTest(const Offset(0.5, 0.325), size), isFalse);
      expect(op.hitTest(const Offset(0.65, 0.25), size), isTrue);
    });

    test('the corners of an un-rotated box are its own edges', () {
      const size = Size(200, 400);
      final op = red(center: const Offset(0.5, 0.25), width: 0.4, height: 0.4);
      final corners = op.corners(size);

      expect(corners, hasLength(4));
      // 80x80px about (100,100) => x 60..140 of 200, y 60..140 of 400.
      expect(corners[0].dx, closeTo(0.3, 1e-9));
      expect(corners[0].dy, closeTo(0.15, 1e-9));
      expect(corners[2].dx, closeTo(0.7, 1e-9));
      expect(corners[2].dy, closeTo(0.35, 1e-9));
    });

    test('placement changes leave the contents alone', () {
      final op = red();
      final moved = op.withPlacement(center: const Offset(0.2, 0.2));
      expect(moved, isA<ShapeOp>());
      expect(moved.spec, same(op.spec));
      expect(moved.id, op.id);
      expect(moved.center, const Offset(0.2, 0.2));
      expect(moved.width, op.width);
    });

    test(
      'a shape op lands in the exported pixels where it was placed',
      () async {
        final image = await _solidImage(200, 400, const Color(0xFFFFFFFF));
        final composer = ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          ops: [red(center: const Offset(0.5, 0.25), width: 0.4, height: 0.4)],
        );

        final recorder = ui.PictureRecorder();
        composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 200, 400));
        final rendered = await recorder.endRecording().toImage(200, 400);
        final data = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );

        int red8(int x, int y) => data!.getUint8((y * 200 + x) * 4);
        int green8(int x, int y) => data!.getUint8((y * 200 + x) * 4 + 1);

        // Middle of the box: the shape's own red.
        expect(red8(100, 100), 255);
        expect(green8(100, 100), 0);
        // Just outside it, and far below: the untouched white capture.
        expect(green8(150, 100), 255);
        expect(green8(100, 300), 255);

        rendered.dispose();
        image.dispose();
      },
    );

    test('a shape is drawn in op order, over a redaction under it', () async {
      // Placed objects are painted in list order rather than hoisted into a
      // pre-pass the way background masks are, so a shape laid down after a
      // redaction sits on top of it.
      final image = await _solidImage(200, 400, const Color(0xFFFFFFFF));
      final composer = ScreenshotComposer(
        image: image,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: [
          _hidden(const Rect.fromLTRB(0, 0, 1, 0.5), const Size(200, 400)),
          red(center: const Offset(0.5, 0.25), width: 0.4, height: 0.4),
        ],
      );

      final recorder = ui.PictureRecorder();
      composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 200, 400));
      final rendered = await recorder.endRecording().toImage(200, 400);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      int red8(int x, int y) => data!.getUint8((y * 200 + x) * 4);
      // The shape, not the patch under it.
      expect(red8(100, 100), 255);
      // The patch, where the shape does not reach.
      expect(red8(20, 100), 0);

      rendered.dispose();
      image.dispose();
    });
  });

  group('placed images', () {
    test(
      'a placed image keeps its own pixel aspect, not the capture\'s',
      () async {
        // Both edges of a PlacedOp are fractions of the CAPTURE's width, so the
        // height that keeps a 16:9 logo 16:9 has to be computed from the bitmap
        // rather than assumed. Getting this wrong stretches every placement by
        // the capture's aspect — on a 9:19.5 phone shot, by more than double.
        final wide = await _solidImage(160, 90, const Color(0xFF00FF00));
        expect(ImageOp.heightFor(wide, 0.4), closeTo(0.4 * 90 / 160, 1e-9));

        final tall = await _solidImage(90, 160, const Color(0xFF00FF00));
        expect(ImageOp.heightFor(tall, 0.4), closeTo(0.4 * 160 / 90, 1e-9));

        wide.dispose();
        tall.dispose();
      },
    );

    test('it lands in the exported pixels where it was placed', () async {
      final capture = await _solidImage(200, 400, const Color(0xFFFFFFFF));
      final logo = await _solidImage(100, 100, const Color(0xFF00FF00));

      final composer = ScreenshotComposer(
        image: capture,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: [
          ImageOp(
            id: 1,
            image: logo,
            source: 'logo.png',
            center: const Offset(0.5, 0.25),
            width: 0.4,
            height: 0.4,
          ),
        ],
      );

      final recorder = ui.PictureRecorder();
      composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 200, 400));
      final rendered = await recorder.endRecording().toImage(200, 400);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      int green(int x, int y) => data!.getUint8((y * 200 + x) * 4 + 1);
      int red(int x, int y) => data!.getUint8((y * 200 + x) * 4);

      // Box is 80x80px centred at (100, 100).
      expect(green(100, 100), 255);
      expect(red(100, 100), 0, reason: 'the logo, not the white capture');
      expect(red(100, 300), 255, reason: 'untouched capture below it');

      rendered.dispose();
      capture.dispose();
      logo.dispose();
    });

    test('the tone adjustments do not touch a placed image', () async {
      // A placed logo keeps the colours it was made in, for the same reason a
      // redaction patch does: the adjustment is a property of the capture, and
      // a badge that dimmed with the screenshot would be unreadable exactly
      // when the screenshot was darkened to make it stand out.
      final capture = await _solidImage(200, 200, const Color(0xFFFFFFFF));
      final logo = await _solidImage(50, 50, const Color(0xFF00FF00));

      Future<int> greenAtCentre(ImageAdjustments adjust) async {
        final composer = ScreenshotComposer(
          image: capture,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          adjustments: adjust,
          ops: [
            ImageOp(
              id: 1,
              image: logo,
              source: 'logo.png',
              center: const Offset(0.5, 0.5),
              width: 0.5,
              height: 0.5,
            ),
          ],
        );
        final recorder = ui.PictureRecorder();
        composer.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 200, 200));
        final rendered = await recorder.endRecording().toImage(200, 200);
        final data = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final value = data!.getUint8((100 * 200 + 100) * 4 + 1);
        rendered.dispose();
        return value;
      }

      final plain = await greenAtCentre(const ImageAdjustments());
      final dimmed = await greenAtCentre(
        const ImageAdjustments(brightness: -0.8),
      );
      expect(dimmed, plain);

      capture.dispose();
      logo.dispose();
    });

    test('mirroring changes the picture but not the placement', () async {
      final bitmap = await _solidImage(10, 10, const Color(0xFF00FF00));
      final op = ImageOp(
        id: 1,
        image: bitmap,
        source: 'a.png',
        center: const Offset(0.3, 0.3),
        width: 0.4,
        height: 0.2,
      );
      final flipped = op.copyWith(flipH: true);
      expect(flipped.flipH, isTrue);
      expect(flipped.center, op.center);
      expect(flipped.width, op.width);
      expect(flipped.image, same(op.image));
      bitmap.dispose();
    });
  });

  group('blur redaction', () {
    /// An image split down the middle: black on the left, white on the right.
    ///
    /// A hard edge is what a blur has to do something visible to — a flat
    /// region blurs to itself and would pass whatever the filter did.
    Future<ui.Image> splitImage(int width, int height) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawRect(
        Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      return image;
    }

    Future<ByteData> render(ScreenshotComposer composer, Size size) async {
      final recorder = ui.PictureRecorder();
      composer.paint(
        Canvas(recorder),
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
      final rendered = await recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      rendered.dispose();
      return data!;
    }

    test('softens the edge under it and leaves the rest alone', () async {
      final image = await splitImage(100, 100);
      final data = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          ops: [
            _hidden(
              const Rect.fromLTRB(0, 0, 1, 0.5),
              const Size(100, 100),
              color: const Color(0xFFFF0000),
              style: HideStyle.blur,
              blur: 0.06,
            ),
          ],
        ),
        const Size(100, 100),
      );

      int red(int x, int y) => data.getUint8((y * 100 + x) * 4);

      // Under the redaction the hard black/white seam has become a ramp, so
      // the pixels either side of the middle are no longer 0 and 255.
      expect(red(48, 25), greaterThan(10));
      expect(red(52, 25), lessThan(245));
      // Outside it the seam is untouched.
      expect(red(48, 75), 0);
      expect(red(52, 75), 255);

      image.dispose();
    });

    test(
      'takes its pixels from the screenshot, not from the patch colour',
      () async {
        // The distinction that makes it a blur rather than a translucent fill:
        // the op carries a red colour and none of it may appear.
        final image = await splitImage(100, 100);
        final data = await render(
          ScreenshotComposer(
            image: image,
            crop: const Rect.fromLTRB(0, 0, 1, 1),
            ops: [
              _hidden(
                const Rect.fromLTRB(0, 0, 1, 0.5),
                const Size(100, 100),
                color: const Color(0xFFFF0000),
                style: HideStyle.blur,
                blur: 0.02,
              ),
            ],
          ),
          const Size(100, 100),
        );

        int channel(int x, int y, int c) =>
            data.getUint8((y * 100 + x) * 4 + c);
        // Grey, not red: every channel agrees.
        expect(channel(50, 25, 0), closeTo(channel(50, 25, 1), 6));
        expect(channel(50, 25, 1), closeTo(channel(50, 25, 2), 6));

        image.dispose();
      },
    );

    test('blurs by the same amount at preview and export scale', () async {
      // The sigma is a fraction of the source width times the same `scale`
      // every other measurement uses, so the picture is one blur at two sizes.
      final image = await splitImage(100, 100);
      final small = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          ops: [
            _hidden(
              const Rect.fromLTRB(0, 0, 1, 1),
              const Size(100, 100),
              style: HideStyle.blur,
              blur: 0.05,
            ),
          ],
        ),
        const Size(100, 100),
      );
      final large = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(0, 0, 1, 1),
          ops: [
            _hidden(
              const Rect.fromLTRB(0, 0, 1, 1),
              const Size(100, 100),
              style: HideStyle.blur,
              blur: 0.05,
            ),
          ],
        ),
        const Size(300, 300),
      );

      // Sample the same fractional position in both.
      int redSmall(double fx) =>
          small.getUint8(((50 * 100) + (fx * 100).round()) * 4);
      int redLarge(double fx) =>
          large.getUint8(((150 * 300) + (fx * 300).round()) * 4);

      for (final fx in [0.3, 0.45, 0.55, 0.7]) {
        expect(
          redSmall(fx),
          closeTo(redLarge(fx), 26),
          reason: 'the ramp lands in the same place at $fx',
        );
      }

      image.dispose();
    });
  });

  group('image adjustments', () {
    test('untouched is the identity, and says so', () {
      const none = ImageAdjustments();
      expect(none.isIdentity, isTrue);
      expect(none.copyWith(contrast: 0.2).isIdentity, isFalse);
    });

    Future<int> renderChannel(
      ImageAdjustments adjustments,
      Color source,
      int channel,
    ) async {
      final image = await _solidImage(20, 20, source);
      final recorder = ui.PictureRecorder();
      ScreenshotComposer(
        image: image,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: const [],
        adjustments: adjustments,
      ).paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 20, 20));
      final rendered = await recorder.endRecording().toImage(20, 20);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      rendered.dispose();
      image.dispose();
      return data!.getUint8((10 * 20 + 10) * 4 + channel);
    }

    test('brightness lifts and drops every channel', () async {
      const grey = Color(0xFF808080);
      expect(
        await renderChannel(const ImageAdjustments(brightness: 0.2), grey, 0),
        greaterThan(await renderChannel(const ImageAdjustments(), grey, 0)),
      );
      expect(
        await renderChannel(const ImageAdjustments(brightness: -0.2), grey, 0),
        lessThan(await renderChannel(const ImageAdjustments(), grey, 0)),
      );
    });

    test('contrast pivots on mid-grey rather than sliding the image', () async {
      // The property that makes it contrast and not brightness: the pivot does
      // not move, so a mid-grey pixel comes back where it started.
      const grey = Color(0xFF808080);
      expect(
        await renderChannel(const ImageAdjustments(contrast: 0.5), grey, 0),
        closeTo(128, 2),
      );
      // A light pixel gets lighter and a dark one darker.
      expect(
        await renderChannel(
          const ImageAdjustments(contrast: 0.5),
          const Color(0xFFC0C0C0),
          0,
        ),
        greaterThan(192),
      );
      expect(
        await renderChannel(
          const ImageAdjustments(contrast: 0.5),
          const Color(0xFF404040),
          0,
        ),
        lessThan(64),
      );
    });

    test('saturation at -100% leaves a grey of the same luma', () async {
      // Fully desaturated, the three channels have to agree — that is what
      // grey means, and a wrong luma row in the matrix shows up here.
      const red = Color(0xFFCC3333);
      final r = await renderChannel(
        const ImageAdjustments(saturation: -1),
        red,
        0,
      );
      final g = await renderChannel(
        const ImageAdjustments(saturation: -1),
        red,
        1,
      );
      final b = await renderChannel(
        const ImageAdjustments(saturation: -1),
        red,
        2,
      );
      expect(g, closeTo(r, 2));
      expect(b, closeTo(r, 2));
      // And it is the luma, not the average: red weighs less than green.
      expect(r, lessThan(140));
    });
  });

  group('remove background', () {
    /// A page-white 100x100 field holding one dark 40x40 subject at the
    /// centre, a second, smaller part of it off to one side — a wordmark's
    /// letter, the dot on an i — and a two-pixel speck of noise near a corner.
    Future<ui.Image> subjectOnPage() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = const Color(0xFFF7F8FA),
      );
      canvas.drawRect(
        const Rect.fromLTWH(30, 30, 40, 40),
        Paint()..color = const Color(0xFF101828),
      );
      canvas.drawRect(
        const Rect.fromLTWH(80, 44, 6, 6),
        Paint()..color = const Color(0xFF101828),
      );
      canvas.drawRect(
        const Rect.fromLTWH(88, 8, 2, 1),
        Paint()..color = const Color(0xFF101828),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      picture.dispose();
      return image;
    }

    /// Alpha of the composed result at a pixel, rendered through the same
    /// paint path the export uses.
    Future<int Function(int, int)> composeAlpha(
      List<EditOp> ops,
      ui.Image image,
    ) async {
      final recorder = ui.PictureRecorder();
      ScreenshotComposer(
        image: image,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        ops: ops,
      ).paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 100, 100));
      final rendered = await recorder.endRecording().toImage(100, 100);
      final data = (await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      rendered.dispose();
      return (x, y) => data.getUint8((y * 100 + x) * 4 + 3);
    }

    test('erases the page and keeps the subject', () async {
      final image = await subjectOnPage();
      final mask = await buildBorderFloodMask(image);
      final alpha = await composeAlpha([
        RemoveBackgroundOp(mask: mask, tolerance: 90),
      ], image);

      expect(alpha(50, 50), 255, reason: 'the subject must survive intact');
      expect(alpha(5, 5), 0, reason: 'the page must be gone');
      expect(alpha(95, 95), 0, reason: 'the page must be gone in every corner');

      mask.dispose();
      image.dispose();
    });

    test('sweeps away specks of noise the fill could not reach', () async {
      final image = await subjectOnPage();
      final mask = await buildBorderFloodMask(image);
      final alpha = await composeAlpha([
        RemoveBackgroundOp(mask: mask, tolerance: 90),
      ], image);

      // The speck is dark, so the flood fill stops at it; only the island
      // sweep removes it.
      expect(alpha(88, 8), 0, reason: 'two pixels of noise are not a subject');

      mask.dispose();
      image.dispose();
    });

    test('keeps every part of the subject, not just the biggest', () async {
      final image = await subjectOnPage();
      final mask = await buildBorderFloodMask(image);
      final alpha = await composeAlpha([
        RemoveBackgroundOp(mask: mask, tolerance: 90),
      ], image);

      // A logo's letters, a screenshot's buttons: separate from the largest
      // shape, and still wanted.
      expect(alpha(83, 47), 255, reason: 'a smaller part must survive');

      mask.dispose();
      image.dispose();
    });

    test(
      'clears the page from inside a letter, not from a big enclosure',
      () async {
        // A dark ring around a small pocket of page — the inside of an "o" —
        // and a dark frame around a large one, bigger than any letter's.
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 100, 100),
            Paint()..color = const Color(0xFFF7F8FA),
          );
        final ink = Paint()..color = const Color(0xFF101828);
        canvas
          ..drawRect(const Rect.fromLTWH(10, 10, 20, 20), ink)
          ..drawRect(
            const Rect.fromLTWH(18, 18, 4, 4),
            Paint()..color = const Color(0xFFF7F8FA),
          )
          ..drawRect(const Rect.fromLTWH(40, 40, 50, 50), ink)
          ..drawRect(
            const Rect.fromLTWH(45, 45, 40, 40),
            Paint()..color = const Color(0xFFF7F8FA),
          );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        picture.dispose();

        final mask = await buildBorderFloodMask(image);
        final alpha = await composeAlpha([
          RemoveBackgroundOp(mask: mask, tolerance: 90),
        ], image);

        expect(alpha(20, 20), 0, reason: 'the inside of a letter is page');
        expect(alpha(13, 20), 255, reason: 'the letter itself stays');
        expect(alpha(65, 65), 255, reason: 'a big enclosure is the subject');

        mask.dispose();
        image.dispose();
      },
    );

    test('leaves the image opaque when no removal op is present', () async {
      final image = await subjectOnPage();
      final alpha = await composeAlpha(const [], image);

      expect(alpha(5, 5), 255);
      expect(alpha(50, 50), 255);

      image.dispose();
    });

    test('a redaction painted after a cutout still lands', () async {
      // The mask erases the image layer only, so ops keep working over it
      // whatever order they were committed in.
      final image = await subjectOnPage();
      final mask = await buildBorderFloodMask(image);
      final alpha = await composeAlpha([
        RemoveBackgroundOp(mask: mask, tolerance: 90),
        _hidden(const Rect.fromLTRB(0, 0, 1, 0.1), const Size(100, 100)),
      ], image);

      expect(alpha(50, 5), 255, reason: 'the redaction bar must be opaque');
      expect(alpha(50, 95), 0, reason: 'the cutout below it must survive');

      mask.dispose();
      image.dispose();
    });
  });

  group('expand crop', () {
    /// A 100x200 image: left half red, right half blue, with a green top row —
    /// enough structure to tell edge-extend from mirror from solid.
    Future<ui.Image> striped() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 50, 200),
        Paint()..color = const Color(0xFFFF0000),
      );
      canvas.drawRect(
        const Rect.fromLTWH(50, 0, 50, 200),
        Paint()..color = const Color(0xFF0000FF),
      );
      // A thick top band, so a sample point lands unambiguously inside it.
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 20),
        Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 200);
      picture.dispose();
      return image;
    }

    /// Renders a composer through the same paint path the export uses.
    Future<ByteData> render(ScreenshotComposer composer, Size size) async {
      final recorder = ui.PictureRecorder();
      composer.paint(Canvas(recorder), Offset.zero & size);
      final rendered = await recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      rendered.dispose();
      return data!;
    }

    Color at(ByteData data, Size size, int x, int y) {
      final o = (y * size.width.toInt() + x) * 4;
      return Color.fromARGB(
        data.getUint8(o + 3),
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      );
    }

    test('a crop inside the image is not treated as expanded', () async {
      final image = await striped();
      for (final crop in const [
        Rect.fromLTRB(0, 0, 1, 1),
        Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      ]) {
        expect(
          ScreenshotComposer(
            image: image,
            crop: crop,
            ops: const [],
          ).isExpanded,
          isFalse,
          reason: '$crop',
        );
      }
      image.dispose();
    });

    test('reaching past any edge counts as expanded', () async {
      final image = await striped();
      for (final crop in const [
        Rect.fromLTRB(-0.1, 0, 1, 1),
        Rect.fromLTRB(0, -0.1, 1, 1),
        Rect.fromLTRB(0, 0, 1.1, 1),
        Rect.fromLTRB(0, 0, 1, 1.1),
      ]) {
        expect(
          ScreenshotComposer(
            image: image,
            crop: crop,
            ops: const [],
          ).isExpanded,
          isTrue,
          reason: '$crop',
        );
      }
      image.dispose();
    });

    test('export size grows with the expansion', () async {
      final image = await striped();
      final composer = ScreenshotComposer(
        image: image,
        crop: const Rect.fromLTRB(-0.2, 0, 1.2, 1),
        ops: const [],
      );
      // 1.4x the width in normalised terms -> 140px of a 100px-wide source.
      expect(composer.exportSize.width, 140);
      expect(composer.exportSize.height, 200);
      image.dispose();
    });

    test('edge fill continues the border colours outward', () async {
      final image = await striped();
      // Half an image-width of margin on the left and right.
      const size = Size(200, 200);
      final data = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(-0.5, 0, 1.5, 1),
          ops: const [],
        ),
        size,
      );

      // Left margin continues red, right margin continues blue...
      expect(at(data, size, 10, 100), const Color(0xFFFF0000));
      expect(at(data, size, 190, 100), const Color(0xFF0000FF));
      // ...and the artwork itself is untouched in the middle.
      expect(at(data, size, 60, 100), const Color(0xFFFF0000));
      expect(at(data, size, 140, 100), const Color(0xFF0000FF));
      image.dispose();
    });

    test('edge fill carries the top row into the corners', () async {
      final image = await striped();
      const size = Size(200, 400);
      final data = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(-0.5, -0.5, 1.5, 1.5),
          ops: const [],
        ),
        size,
      );
      // Top-left corner is the image's top-left pixel — the green row.
      expect(at(data, size, 5, 5), const Color(0xFF00FF00));
      // Directly above the artwork, still green.
      expect(at(data, size, 100, 40), const Color(0xFF00FF00));
      // Below the artwork the bottom row continues: red left, blue right.
      expect(at(data, size, 20, 380), const Color(0xFFFF0000));
      expect(at(data, size, 180, 380), const Color(0xFF0000FF));
      image.dispose();
    });

    test('mirror fill reflects the band structure back out', () async {
      final image = await striped();
      // Expand vertically: the green top band gives the reflection an
      // unambiguous signature. (Horizontally it could not — reflecting the red
      // half about the left edge is red either way, so that axis cannot tell
      // mirror apart from edge-extend.)
      const size = Size(100, 400);
      final data = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(0, -0.5, 1, 1.5),
          ops: const [],
          fill: ExpandFill.mirror,
        ),
        size,
      );

      // Artwork occupies y 100..300. Just above it the reflection replays the
      // green band outward, so green sits ABOVE the artwork's own green.
      expect(at(data, size, 20, 90), const Color(0xFF00FF00));
      // Further up, past the reflected band, the body colours return.
      expect(at(data, size, 20, 40), const Color(0xFFFF0000));
      expect(at(data, size, 80, 40), const Color(0xFF0000FF));
      // Edge-extend would instead have smeared the top row green all the way
      // to the canvas edge — this is what separates the two fills.
      expect(at(data, size, 20, 5), isNot(const Color(0xFF00FF00)));
      image.dispose();
    });

    test('solid fill paints exactly the requested colour', () async {
      final image = await striped();
      const size = Size(200, 200);
      final data = await render(
        ScreenshotComposer(
          image: image,
          crop: const Rect.fromLTRB(-0.5, 0, 1.5, 1),
          ops: const [],
          fill: ExpandFill.solid,
          fillColor: const Color(0xFF123456),
        ),
        size,
      );
      expect(at(data, size, 10, 100), const Color(0xFF123456));
      expect(at(data, size, 190, 100), const Color(0xFF123456));
      // The artwork still wins where it exists.
      expect(at(data, size, 60, 100), const Color(0xFFFF0000));
      image.dispose();
    });

    test('every fill leaves the margin fully opaque', () async {
      final image = await striped();
      const size = Size(200, 200);
      for (final fill in ExpandFill.values) {
        final data = await render(
          ScreenshotComposer(
            image: image,
            crop: const Rect.fromLTRB(-0.5, 0, 1.5, 1),
            ops: const [],
            fill: fill,
            fillColor: const Color(0xFF123456),
          ),
          size,
        );
        // A transparent margin would composite the device frame through the
        // screenshot — the one outcome that is never acceptable.
        expect(at(data, size, 3, 100).a, 1.0, reason: '$fill left edge');
        expect(at(data, size, 196, 100).a, 1.0, reason: '$fill right edge');
      }
      image.dispose();
    });
  });

  group('clampCrop / resize with expand', () {
    test('without expand the crop stays inside the image', () {
      final clamped = clampCrop(const Rect.fromLTWH(-0.5, -0.5, 0.4, 0.3));
      expect(clamped.left, greaterThanOrEqualTo(0));
      expect(clamped.top, greaterThanOrEqualTo(0));
    });

    test('with expand it may reach kMaxExpand outside, and no further', () {
      final clamped = clampCrop(
        const Rect.fromLTWH(-5, -5, 0.4, 0.3),
        expand: true,
      );
      expect(clamped.left, closeTo(-kMaxExpand, 1e-9));
      expect(clamped.top, closeTo(-kMaxExpand, 1e-9));

      final far = clampCrop(const Rect.fromLTWH(5, 5, 0.4, 0.3), expand: true);
      expect(far.right, lessThanOrEqualTo(1 + kMaxExpand + 1e-9));
      expect(far.bottom, lessThanOrEqualTo(1 + kMaxExpand + 1e-9));
    });

    test('a corner drag past the edge grows instead of stopping', () {
      const imageSize = Size(1200, 2600);
      const target = 9 / 19.5;
      const base = Rect.fromLTWH(0.0, 0.0, 0.5, 0.5);

      final blocked = resizeCropFromCorner(
        base: base,
        handle: CropHandle.bottomRight,
        pointer: const Offset(2.0, 0.5),
        imageSize: imageSize,
        targetAspect: target,
      );
      final expanded = resizeCropFromCorner(
        base: base,
        handle: CropHandle.bottomRight,
        pointer: const Offset(2.0, 0.5),
        imageSize: imageSize,
        targetAspect: target,
        expand: true,
      );

      expect(expanded.width, greaterThan(blocked.width));
      expect(expanded.right, greaterThan(1.0));
      // The device ratio still holds — expanding must not distort the output.
      final pixelAspect =
          (expanded.width * imageSize.width) /
          (expanded.height * imageSize.height);
      expect(pixelAspect, closeTo(target, 1e-6));
    });
  });

  group('DeviceStorage.sanitizeFileName', () {
    test('strips characters that are illegal on any target', () {
      expect(
        DeviceStorage.sanitizeFileName('My App: v1/2 <beta>'),
        'My App v1 2 beta',
      );
    });

    test('never returns an empty name', () {
      expect(DeviceStorage.sanitizeFileName('   '), 'Untitled');
      expect(DeviceStorage.sanitizeFileName('///'), 'Untitled');
    });

    test('caps the length so no filesystem rejects it', () {
      final long = DeviceStorage.sanitizeFileName('a' * 400);
      expect(long.length, lessThanOrEqualTo(120));
    });
  });
}

/// An area hiding [rect] of a photo of [size] — a black cover unless told
/// otherwise.
HideOp _hidden(
  Rect rect,
  Size size, {
  HideStyle style = HideStyle.cover,
  Color color = const Color(0xFF000000),
  double blur = 0.02,
}) => HideOp(
  id: 1,
  center: rect.center,
  width: 0,
  height: 0,
  style: style,
  color: color,
  blur: blur,
).over(rect, size);
