import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_codec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';

/// The photo editor's arithmetic: its colour controls and looks, its
/// straighten, its text, the ops it paints, and the recipe that lets all of
/// them be reopened and changed.
void main() {
  // Text is measured through the font loader, which needs the services.
  TestWidgetsFlutterBinding.ensureInitialized();

  int channel(Color c, int i) =>
      ((switch (i) {
                0 => c.r,
                1 => c.g,
                _ => c.b,
              }) *
              255)
          .round();
  int red(Color c) => channel(c, 0);
  Color grey(int v) => Color.fromARGB(255, v, v, v);

  group('colour matrices', () {
    test('then runs the first matrix, then the second', () {
      final doubleThenLift = ColorMatrix.channels(
        2,
        2,
        2,
      ).then(ColorMatrix.channels(1, 1, 1, offset: 10));
      expect(red(doubleThenLift.apply(grey(50))), 110);

      final liftThenDouble = ColorMatrix.channels(
        1,
        1,
        1,
        offset: 10,
      ).then(ColorMatrix.channels(2, 2, 2));
      expect(red(liftThenDouble.apply(grey(50))), 120);
    });

    test('strength runs from untouched to the whole look', () {
      final look = Tone.saturation(-1);
      expect(look.strength(0).isIdentity, isTrue);
      expect(look.strength(1), look);

      const orange = Color(0xFFFF8000);
      final full = look.apply(orange);
      final half = look.strength(0.5).apply(orange);
      expect(red(half), closeTo((255 + red(full)) / 2, 2));
    });
  });

  group('tone controls', () {
    test('brightness lifts the middle further than the black', () {
      final up = Tone.brightness(1);
      final black = red(up.apply(grey(0)));
      final lift = red(up.apply(grey(128))) - 128;
      expect(black, inInclusiveRange(20, 40));
      expect(lift, greaterThan(black));
      expect(lift, inInclusiveRange(50, 75));
    });

    test('half-way brightness leaves a dark screenshot dark', () {
      // A plain offset took black to mid-grey here.
      expect(red(Tone.brightness(0.5).apply(grey(0))), lessThan(24));
    });

    test('contrast pivots on mid-grey', () {
      final more = Tone.contrast(0.5);
      expect(red(more.apply(grey(128))), 128);
      expect(red(more.apply(grey(192))), greaterThan(192));
      expect(red(more.apply(grey(64))), lessThan(64));
    });

    test('exposure and highlights hold black; shadows hold white', () {
      expect(red(Tone.exposure(1).apply(grey(0))), 0);
      expect(red(Tone.exposure(1).apply(grey(64))), 128);
      expect(red(Tone.highlights(1).apply(grey(0))), 0);
      expect(red(Tone.shadows(1).apply(grey(255))), 255);
      expect(red(Tone.shadows(1).apply(grey(0))), greaterThan(40));
    });

    test('warmth moves red and blue apart, tint moves green', () {
      final warm = Tone.warmth(1).apply(grey(128));
      final cool = Tone.warmth(-1).apply(grey(128));
      expect(channel(warm, 0), greaterThan(channel(warm, 2)));
      expect(channel(cool, 0), lessThan(channel(cool, 2)));
      final magenta = Tone.tint(1).apply(grey(128));
      expect(channel(magenta, 1), lessThan(channel(magenta, 0)));
    });

    test('fade lifts black and lowers white', () {
      expect(red(Tone.fade(1).apply(grey(0))), greaterThan(20));
      expect(red(Tone.fade(1).apply(grey(255))), lessThan(235));
    });

    test('saturation at -1 leaves a grey of the same brightness', () {
      final c = Tone.saturation(-1).apply(grey(90));
      expect(red(c), 90);
      expect(channel(c, 1), 90);
    });
  });

  group('filters', () {
    test('Original changes nothing', () {
      expect(PhotoFilter.none.matrix.isIdentity, isTrue);
      expect(PhotoFilter.none.vignette, 0);
    });

    test('every other look changes a colour photo', () {
      const sample = Color(0xFF4A7FB5);
      for (final look in PhotoFilter.values.skip(1)) {
        expect(
          look.matrix.apply(sample).toARGB32(),
          isNot(sample.toARGB32()),
          reason: look.label,
        );
      }
    });

    test('Mono and Noir take the colour out', () {
      for (final look in [PhotoFilter.mono, PhotoFilter.noir]) {
        final c = look.matrix.apply(const Color(0xFFFF8000));
        expect(red(c), channel(c, 1), reason: look.label);
        expect(channel(c, 1), channel(c, 2), reason: look.label);
      }
    });

    test('a look at no strength is no look', () {
      const adjust = ImageAdjustments(look: PhotoFilter.noir, lookStrength: 0);
      expect(adjust.isIdentity, isTrue);
      expect(adjust.changesColor, isFalse);
      expect(adjust.totalVignette, 0);
    });

    test('a look brings its vignette, scaled by its strength', () {
      const adjust = ImageAdjustments(
        look: PhotoFilter.dramatic,
        lookStrength: 0.5,
      );
      expect(
        adjust.totalVignette,
        closeTo(PhotoFilter.dramatic.vignette / 2, 1e-9),
      );
    });

    test('Reset all in Adjust keeps the look', () {
      const adjust = ImageAdjustments(
        brightness: 0.3,
        warmth: -0.2,
        look: PhotoFilter.warm,
        lookStrength: 0.7,
      );
      expect(
        adjust.withoutSliders(),
        const ImageAdjustments(look: PhotoFilter.warm, lookStrength: 0.7),
      );
    });
  });

  group('auto enhance', () {
    Future<PixelSampler> sampler(List<int> levels) async {
      // One row per level, 8 pixels wide.
      final bytes = Uint8List(levels.length * 8 * 4);
      for (var y = 0; y < levels.length; y++) {
        for (var x = 0; x < 8; x++) {
          final o = (y * 8 + x) * 4;
          bytes[o] = bytes[o + 1] = bytes[o + 2] = levels[y];
          bytes[o + 3] = 255;
        }
      }
      final image = await _fromPixels(bytes, 8, levels.length);
      final s = PixelSampler(image);
      await s.prepare();
      return s;
    }

    test('stretches a flat, dark photo and brightens it', () async {
      final s = await sampler([for (var v = 20; v <= 80; v++) v]);
      final auto = s.autoEnhance();
      expect(auto, isNotNull);
      final m = auto!.matrix;
      // Brighter in the middle — stretching about mid-grey alone made it
      // darker — and wider from end to end.
      expect(red(m.apply(grey(50))), greaterThan(50));
      expect(red(m.apply(grey(80))) - red(m.apply(grey(20))), greaterThan(60));
    });

    test('leaves a photo that already spans the range alone', () async {
      final s = await sampler([
        for (var i = 0; i < 50; i++) 0,
        for (var i = 0; i < 50; i++) 255,
      ]);
      expect(s.autoEnhance(), isNull);
    });

    test('finds a status bar from its row of glyphs', () async {
      // A 1000-row capture, white, with ink across rows 20–39 near both ends
      // of the row: the clock on the left and the icons on the right.
      const w = 400, h = 1000;
      final bytes = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
      for (var y = 20; y < 40; y++) {
        for (final (from, to) in [(40, 100), (320, 380)]) {
          for (var x = from; x < to; x++) {
            final o = (y * w + x) * 4;
            bytes[o] = bytes[o + 1] = bytes[o + 2] = 0;
          }
        }
      }
      final s = PixelSampler(await _fromPixels(bytes, w, h));
      await s.prepare();
      // The glyphs sit in the middle of the bar, so it ends as far below
      // them as it starts above.
      expect(s.statusBarHeight(), closeTo(59 / 1000, 0.002));

      final blank = PixelSampler(
        await _fromPixels(
          Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255),
          w,
          h,
        ),
      );
      await blank.prepare();
      expect(blank.statusBarHeight(fallback: 0.05), 0.05);
    });
  });

  group('straighten', () {
    test('covers the frame at any angle, and only enlarges when turned', () {
      const frame = Size(1080, 2340);
      expect(const ImageOrientation().coverScale(frame), 1);
      for (final angle in [-45.0, -12.0, 3.0, 30.0]) {
        final k = ImageOrientation(angle: angle).coverScale(frame);
        expect(k, greaterThan(1), reason: '$angle°');
      }
    });

    test('toSource is the exact inverse of how the photo is drawn', () async {
      const oriented = Rect.fromLTWH(0, 0, 300, 200);
      for (final o in const [
        ImageOrientation(turns: 1, flipH: true),
        ImageOrientation(angle: 12),
        ImageOrientation(turns: 3, flipV: true, angle: -20),
        ImageOrientation(flipH: true, flipV: true, angle: 7),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final into = o.prepare(canvas, oriented);
        final m = Matrix4.fromFloat64List(canvas.getTransform());
        recorder.endRecording().dispose();

        for (final source in const [
          Offset(0.25, 0.4),
          Offset(0.5, 0.5),
          Offset(0.7, 0.2),
        ]) {
          // Where a source point lands on screen…
          final drawn = MatrixUtils.transformPoint(
            m,
            Offset(
              into.left + source.dx * into.width,
              into.top + source.dy * into.height,
            ),
          );
          // …read back through the eyedropper's path.
          final back = o.toSource(
            Offset(drawn.dx / oriented.width, drawn.dy / oriented.height),
            frame: oriented.size,
          );
          expect(back.dx, closeTo(source.dx, 1e-6), reason: '$o $source');
          expect(back.dy, closeTo(source.dy, 1e-6), reason: '$o $source');
        }
      }
    });
  });

  group('text', () {
    // Widget tests, all of them: measuring words asks google_fonts for the
    // face, and the missing-font error it raises afterwards is only filtered
    // (see flutter_test_config.dart) on that path.
    TextOp words([double fontSize = 0.1]) => TextOp(
      id: 1,
      text: 'Set alarms fast',
      fontSize: fontSize,
      center: const Offset(0.5, 0.5),
    ).fitted();

    testWidgets('its box is measured from its words and its size', (_) async {
      final small = words(0.05), large = words(0.1);
      expect(small.width, greaterThan(0));
      expect(large.width, closeTo(small.width * 2, 1e-9));
      expect(large.height, closeTo(small.height * 2, 1e-9));
    });

    testWidgets('a look with a plate or a ring makes the box roomier', (
      _,
    ) async {
      final plain = words();
      final boxed = plain.copyWith(look: TextLook.box);
      expect(boxed.width, greaterThan(plain.width));
      expect(boxed.height, greaterThan(plain.height));
      expect(TextLook.box.hasAccent, isTrue);
      expect(TextLook.outline.hasAccent, isTrue);
      expect(TextLook.shadow.hasAccent, isFalse);
    });

    testWidgets('dragging a corner resizes the type with the box', (_) async {
      final op = words();
      final bigger = op.withPlacement(width: op.width * 1.5);
      expect(bigger.fontSize, closeTo(op.fontSize * 1.5, 1e-9));
      expect(bigger.height, closeTo(op.height * 1.5, 1e-9));
      // Moving it leaves the size alone.
      final moved = op.withPlacement(center: const Offset(0.2, 0.3));
      expect(moved.fontSize, op.fontSize);
      expect(moved.center, const Offset(0.2, 0.3));
    });

    testWidgets('a box look paints its plate behind the words', (tester) async {
      final op = words(0.2).copyWith(
        text: 'Hi',
        look: TextLook.box,
        accent: const Color(0xFFFF0000),
        color: const Color(0xFFFFFFFF),
      );
      final pixel = (await tester.runAsync(() => _render(200, 200, [op])))!;
      // Half-way into the plate's padding, level with the words' middle: the
      // plate, not a letter. The padding is 34 at the 100 the words are laid
      // out at.
      final left = 100 - op.width * 200 / 2;
      final padding = 0.34 * op.fontSize * 200;
      expect(pixel((left + padding / 2).round(), 100), const Color(0xFFFF0000));
      // And outside the plate, the photo.
      expect(pixel((left - 4).round(), 100), const Color(0xFFFFFFFF));
    });
  });

  group('painting the new ops', () {
    test('a box markup is an outline, not a fill', () async {
      final pixel = await _render(100, 100, [
        const MarkupOp(
          kind: MarkupKind.box,
          start: Offset(0.2, 0.2),
          end: Offset(0.8, 0.8),
          color: Color(0xFFFF0000),
          width: 0.04,
        ),
      ]);
      expect(pixel(20, 50), const Color(0xFFFF0000));
      expect(pixel(50, 50), const Color(0xFFFFFFFF));
    });

    test('an arrow runs its whole length and ends in a head', () async {
      final pixel = await _render(100, 100, [
        const MarkupOp(
          kind: MarkupKind.arrow,
          start: Offset(0.1, 0.5),
          end: Offset(0.9, 0.5),
          color: Color(0xFFFF0000),
          width: 0.03,
        ),
      ]);
      expect(pixel(30, 50), const Color(0xFFFF0000));
      expect(pixel(70, 50), const Color(0xFFFF0000));
      expect(pixel(50, 20), const Color(0xFFFFFFFF));
      // The head is wider than the shaft.
      expect(pixel(80, 46), const Color(0xFFFF0000));
      expect(pixel(50, 46), const Color(0xFFFFFFFF));
    });

    test('a clean status bar fills its band and draws its glyphs', () async {
      final pixel = await _render(400, 800, [
        const StatusBarOp(
          // 48 of the picture's 400 across.
          height: 0.12,
          background: Color(0xFF223344),
          foreground: Color(0xFFFFFFFF),
          style: StatusBarStyle.ios,
        ),
      ]);
      // The bar's own colour between the clock and the icons…
      expect(pixel(200, 24), const Color(0xFF223344));
      // …and the photo untouched below it.
      expect(pixel(200, 200), const Color(0xFFFFFFFF));
      // Ink where the clock and the battery go.
      bool inked(int fromX, int toX) {
        for (var x = fromX; x < toX; x++) {
          for (var y = 10; y < 38; y++) {
            if (pixel(x, y).computeLuminance() > 0.5) return true;
          }
        }
        return false;
      }

      expect(inked(60, 120), isTrue, reason: 'the clock');
      expect(inked(330, 370), isTrue, reason: 'the battery');
    });
  });

  group('the recipe', () {
    test('every new op and control comes back as it went in', () async {
      const text = TextOp(
        id: 7,
        text: 'Track every city',
        fontSize: 0.07,
        center: Offset(0.5, 0.3),
        width: 0.6,
        height: 0.1,
        rotationDeg: -8,
        fontFamily: 'Poppins',
        bold: false,
        color: Color(0xFF111111),
        align: TextAlign.left,
        look: TextLook.box,
        accent: Color(0xFFFACC15),
      );
      final edit = ScreenshotEdit(
        source: 'lib/capture.png',
        crop: const Rect.fromLTRB(0.05, 0.1, 0.95, 0.9),
        orientation: const ImageOrientation(turns: 1, flipV: true, angle: -6.5),
        adjustments: const ImageAdjustments(
          brightness: 0.1,
          exposure: -0.2,
          highlights: 0.3,
          shadows: -0.4,
          warmth: 0.5,
          tint: -0.1,
          fade: 0.2,
          vignette: -0.3,
          blur: 0.25,
          look: PhotoFilter.vintage,
          lookStrength: 0.6,
        ),
        ops: const [
          BrushOp(
            points: [Offset(0.1, 0.1), Offset(0.2, 0.25)],
            color: Color(0xFFFACC15),
            width: 0.02,
            marker: true,
          ),
          MarkupOp(
            kind: MarkupKind.arrow,
            start: Offset(0.2, 0.7),
            end: Offset(0.6, 0.8),
            color: Color(0xFFEF4444),
            width: 0.012,
          ),
          HideOp(
            id: 3,
            center: Offset(0.4, 0.42),
            width: 0.2,
            height: 0.1,
            rotationDeg: 20,
            style: HideStyle.pixelate,
            shape: HideShape.freehand,
            outline: [Offset(-0.5, 0.5), Offset(0, -0.5), Offset(0.5, 0.5)],
            block: 0.05,
          ),
          StatusBarOp(
            height: 0.11,
            background: Color(0xFF000000),
            foreground: Color(0xFFFFFFFF),
            style: StatusBarStyle.samsung,
          ),
          NavBarOp(
            height: 0.06,
            style: NavBarStyle.buttons,
            background: Color(0x00000000),
            foreground: Color(0xFF111111),
          ),
          text,
        ],
      );

      final back = await screenshotEditFromJson(
        screenshotEditToJson(edit),
        imageSize: const Size(1080, 2340),
        texture: (_) async => null,
        sticker: (_) async => null,
      );
      expect(back, isNotNull);
      expect(back!.orientation, edit.orientation);
      expect(back.adjustments, edit.adjustments);

      final [brush, markup, area, bar, nav, words] = back.ops;
      expect((brush as BrushOp).marker, isTrue);
      expect(brush.points, edit.ops.cast<BrushOp>().first.points);

      markup as MarkupOp;
      expect(markup.kind, MarkupKind.arrow);
      expect(markup.start, const Offset(0.2, 0.7));
      expect(markup.end, const Offset(0.6, 0.8));
      expect(markup.width, closeTo(0.012, 1e-9));

      area as HideOp;
      expect(area.id, 3);
      expect(area.style, HideStyle.pixelate);
      expect(area.shape, HideShape.freehand);
      expect(area.outline, const [
        Offset(-0.5, 0.5),
        Offset(0, -0.5),
        Offset(0.5, 0.5),
      ]);
      expect(area.block, closeTo(0.05, 1e-9));
      expect(area.rotationDeg, closeTo(20, 1e-9));
      expect(area.height, closeTo(0.1, 1e-9));

      bar as StatusBarOp;
      expect(bar.style, StatusBarStyle.samsung);
      expect(bar.height, closeTo(0.11, 1e-9));
      expect(bar.time, '9:41');
      expect(bar.background.toARGB32(), 0xFF000000);

      nav as NavBarOp;
      expect(nav.style, NavBarStyle.buttons);
      expect(nav.height, closeTo(0.06, 1e-9));
      expect(nav.background.a, 0);
      expect(nav.foreground.toARGB32(), 0xFF111111);

      words as TextOp;
      expect(words.id, 7);
      expect(words.text, 'Track every city');
      expect(words.fontFamily, 'Poppins');
      expect(words.bold, isFalse);
      expect(words.align, TextAlign.left);
      expect(words.look, TextLook.box);
      expect(words.accent.toARGB32(), 0xFFFACC15);
      expect(words.color.toARGB32(), 0xFF111111);
      expect(words.fontSize, closeTo(0.07, 1e-9));
      expect(words.rotationDeg, closeTo(-8, 1e-9));
      expect(words.center, const Offset(0.5, 0.3));
    });

    test('untouched controls are not written at all', () {
      final json = screenshotEditToJson(
        const ScreenshotEdit(
          source: 'lib/capture.png',
          crop: Rect.fromLTRB(0, 0, 1, 1),
          ops: [],
        ),
      );
      expect(json.containsKey('flipV'), isFalse);
      expect(json.containsKey('angle'), isFalse);
      final adjust = json['adjust'] as Map<String, dynamic>;
      for (final key in ['exposure', 'warmth', 'fade', 'vignette', 'blur']) {
        expect(adjust.containsKey(key), isFalse, reason: key);
      }
    });
  });
}

Future<ui.Image> _fromPixels(Uint8List rgba, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// [ops] composed over a plain white [w]×[h] photo, read back pixel by pixel.
Future<Color Function(int, int)> _render(int w, int h, List<EditOp> ops) async {
  final bytes = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  final image = await _fromPixels(bytes, w, h);
  final recorder = ui.PictureRecorder();
  ScreenshotComposer(
    image: image,
    crop: const Rect.fromLTRB(0, 0, 1, 1),
    ops: ops,
  ).paint(Canvas(recorder), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  final rendered = await recorder.endRecording().toImage(w, h);
  final data = (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  rendered.dispose();
  image.dispose();
  return (x, y) {
    final o = (y * w + x) * 4;
    return Color.fromARGB(
      data.getUint8(o + 3),
      data.getUint8(o),
      data.getUint8(o + 1),
      data.getUint8(o + 2),
    );
  };
}
