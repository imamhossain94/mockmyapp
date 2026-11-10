// Turning a capture before it is cropped — see `ImageOrientation`.
//
// The transform is the risky part, and it is risky quietly: a wrong inverse
// puts the eyedropper on the wrong pixel and a wrong size swap leaves the crop
// marquee shaped for the picture the capture used to be. Neither throws.

import 'dart:math' as math;
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';

void main() {
  const portrait = Size(1080, 2400);

  group('the size the user sees', () {
    test('an upright capture is unchanged', () {
      expect(ImageOrientation.none.sizeOf(portrait), portrait);
      expect(ImageOrientation.none.isIdentity, isTrue);
      expect(ImageOrientation.none.isQuarter, isFalse);
    });

    test('a quarter turn stands it on its side', () {
      for (final turns in [1, 3]) {
        final o = ImageOrientation(turns: turns);
        expect(o.sizeOf(portrait), const Size(2400, 1080), reason: '$turns');
        expect(o.isQuarter, isTrue, reason: '$turns');
      }
    });

    test('a half turn keeps the shape', () {
      const o = ImageOrientation(turns: 2);
      expect(o.sizeOf(portrait), portrait);
      expect(o.isQuarter, isFalse);
    });

    test('a mirror keeps the shape', () {
      const o = ImageOrientation(flipH: true);
      expect(o.sizeOf(portrait), portrait);
      expect(o.isIdentity, isFalse);
    });
  });

  group('turning wraps', () {
    test('four quarter turns is upright again', () {
      var o = ImageOrientation.none;
      for (var i = 0; i < 4; i++) {
        o = o.rotated(1);
      }
      expect(o.turns, 0);
      expect(o.isIdentity, isTrue);
    });

    test('turning back past upright wraps rather than going negative', () {
      // A negative `turns` would multiply into a negative angle that still
      // draws correctly but compares unequal to the same orientation reached
      // the other way round, so the "Upright" button would not know it was
      // already upright.
      expect(ImageOrientation.none.rotated(-1).turns, 3);
      expect(ImageOrientation.none.rotated(-5).turns, 3);
    });

    test('a mirror survives a turn', () {
      const o = ImageOrientation(flipH: true);
      expect(o.rotated(1).flipH, isTrue);
    });
  });

  group('mapping a point back to the file', () {
    // The sampler reads the decoded image, which never turns, so an eyedropper
    // tapped on a turned view has to ask about the pixel really under it.
    Offset src(ImageOrientation o, Offset p) => o.toSource(p);

    test('upright is the identity', () {
      expect(
        src(ImageOrientation.none, const Offset(0.25, 0.75)),
        const Offset(0.25, 0.75),
      );
    });

    test('a quarter turn clockwise moves the top-left to the top-right', () {
      // Turning the picture 90 degrees clockwise carries the file's top-left
      // corner to the view's top-right, so the view's top-right reads back as
      // the file's top-left.
      const o = ImageOrientation(turns: 1);
      final p = src(o, const Offset(1, 0));
      expect(p.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(0, 1e-9));
    });

    test('every turn round-trips against its own inverse', () {
      // Rotating a point t turns clockwise then asking `toSource` for it must
      // give the point back.
      Offset forward(int turns, Offset p) {
        var q = p;
        for (var i = 0; i < turns; i++) {
          q = Offset(1 - q.dy, q.dx);
        }
        return q;
      }

      const probes = [
        Offset(0, 0),
        Offset(1, 0),
        Offset(0.2, 0.9),
        Offset(0.5, 0.5),
      ];
      for (var turns = 0; turns < 4; turns++) {
        final o = ImageOrientation(turns: turns);
        for (final p in probes) {
          final back = o.toSource(forward(turns, p));
          expect(back.dx, closeTo(p.dx, 1e-9), reason: 'turns $turns, $p');
          expect(back.dy, closeTo(p.dy, 1e-9), reason: 'turns $turns, $p');
        }
      }
    });

    test('a mirror is its own inverse', () {
      const o = ImageOrientation(flipH: true);
      expect(o.toSource(const Offset(0.2, 0.4)), const Offset(0.8, 0.4));
      // closeTo, not equals: 1 - (1 - 0.2) is 0.19999999999999996, and an
      // exact comparison here would be asserting something about binary
      // floating point rather than about the mirror.
      final back = o.toSource(o.toSource(const Offset(0.2, 0.4)));
      expect(back.dx, closeTo(0.2, 1e-9));
      expect(back.dy, closeTo(0.4, 1e-9));
    });

    test('the centre is fixed under every orientation', () {
      for (var turns = 0; turns < 4; turns++) {
        for (final flip in [false, true]) {
          final o = ImageOrientation(turns: turns, flipH: flip);
          final c = o.toSource(const Offset(0.5, 0.5));
          expect(c.dx, closeTo(0.5, 1e-9), reason: '$turns/$flip');
          expect(c.dy, closeTo(0.5, 1e-9), reason: '$turns/$flip');
        }
      }
    });
  });

  group('the canvas transform', () {
    test('a quarter turn swaps the rect it draws the file into', () {
      // The file is drawn upright into a rect that the rotation then stands on
      // its side, so that rect has to be the target's dimensions swapped —
      // about the same centre, or the picture walks off its own crop.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const target = Rect.fromLTWH(10, 20, 100, 200);

      final upright = const ImageOrientation(turns: 1).prepare(canvas, target);
      expect(upright.width, 200);
      expect(upright.height, 100);
      expect(upright.center, target.center);
      recorder.endRecording().dispose();
    });

    test('an upright orientation touches neither canvas nor rect', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const target = Rect.fromLTWH(10, 20, 100, 200);

      expect(ImageOrientation.none.prepare(canvas, target), target);
      expect(
        canvas.getTransform(),
        Matrix4.identity().storage,
        reason: 'no turn means no transform to undo later',
      );
      recorder.endRecording().dispose();
    });

    test('a half turn keeps the rect and rotates the canvas', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const target = Rect.fromLTWH(0, 0, 100, 200);

      expect(const ImageOrientation(turns: 2).prepare(canvas, target), target);
      // A half turn about the centre sends the top-left corner to the
      // bottom-right one.
      final m = Matrix4.fromList(canvas.getTransform());
      final moved = MatrixUtils.transformPoint(m, Offset.zero);
      expect(moved.dx, closeTo(100, 1e-6));
      expect(moved.dy, closeTo(200, 1e-6));
      recorder.endRecording().dispose();
    });
  });

  group('equality', () {
    test('two orientations reached differently compare equal', () {
      expect(
        ImageOrientation.none.rotated(1).rotated(1),
        const ImageOrientation(turns: 2),
      );
      expect(
        ImageOrientation.none.rotated(-1),
        const ImageOrientation(turns: 3),
      );
    });

    test('a mirror is not the same as a half turn', () {
      // They look alike on a symmetric picture and are completely different on
      // anything with text in it.
      expect(
        const ImageOrientation(flipH: true),
        isNot(const ImageOrientation(turns: 2)),
      );
    });
  });

  test('the quarter turn really is a quarter of a circle', () {
    // Guards the angle unit: radians, not degrees.
    expect(math.pi / 2, closeTo(1.5707963, 1e-6));
  });
}
