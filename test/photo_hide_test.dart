import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/models/shape_spec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_codec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_editor_screen.dart';

/// Hiding part of a photo, the bars along its edges, and a picture laid over
/// it — each an object that stays editable after it is put down.
///
/// A hidden area used to be a rectangle baked in the moment the finger lifted:
/// one dragged a little short of the name it was for could only be undone and
/// drawn again, and a mosaic carried the colours of wherever it was first
/// drawn. A status bar was a fixed rect with two looks, and there was no
/// navigation bar at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const white = Color(0xFFFFFFFF);
  const black = Color(0xFF000000);
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);
  const full = Rect.fromLTRB(0, 0, 1, 1);

  HideOp area({
    Offset center = const Offset(0.5, 0.5),
    double width = 0.4,
    double height = 0.2,
    double rotationDeg = 0,
    HideStyle style = HideStyle.cover,
    HideShape shape = HideShape.box,
    List<Offset> outline = const [],
    double block = 0.035,
  }) => HideOp(
    id: 5,
    center: center,
    width: width,
    height: height,
    rotationDeg: rotationDeg,
    style: style,
    shape: shape,
    outline: outline,
    block: block,
  );

  group('a hidden area', () {
    test('a cover fills its box and nothing past it', () async {
      final pixel = await _render(await _solid(100, 100, white), [
        area(center: const Offset(0.4, 0.3), width: 0.4, height: 0.2),
      ]);
      expect(pixel(40, 30), black);
      expect(pixel(70, 30), white);
      expect(pixel(40, 50), white);
    });

    test('an oval leaves the corners of its box alone', () async {
      final pixel = await _render(await _solid(100, 100, white), [
        area(width: 0.6, height: 0.6, shape: HideShape.oval),
      ]);
      expect(pixel(50, 50), black);
      expect(pixel(23, 23), white, reason: 'a corner of the box');
    });

    test('a freehand area is cut to its outline', () async {
      final pixel = await _render(await _solid(100, 100, white), [
        area(
          width: 0.6,
          height: 0.6,
          shape: HideShape.freehand,
          // A triangle standing on the bottom of its box.
          outline: const [Offset(-0.5, 0.5), Offset(0, -0.5), Offset(0.5, 0.5)],
        ),
      ]);
      expect(pixel(50, 70), black);
      expect(pixel(25, 25), white, reason: 'beside the apex');
      expect(pixel(75, 25), white, reason: 'beside the apex');
    });

    test('a turned area hides along its own axis', () async {
      final pixel = await _render(await _solid(100, 100, white), [
        area(width: 0.8, height: 0.1, rotationDeg: 90),
      ]);
      expect(pixel(50, 15), black, reason: 'stood on end');
      expect(pixel(15, 50), white, reason: 'where it lay before it turned');
    });

    test('is never see-through, whatever a placement asks', () {
      expect(area().withPlacement(opacity: 0.2).opacity, 1);
    });

    test('pixelated, it is cut into cells of the photo under it', () async {
      final photo = await _split(100, 100);
      final pixels = PixelSampler(photo);
      await pixels.prepare();
      final pixel = await _render(photo, [
        area(width: 1, height: 1, style: HideStyle.pixelate, block: 0.5),
      ], pixels: pixels);
      expect(pixel(25, 50), red);
      expect(pixel(75, 50), blue);
      // Cells, not the photo: one colour from corner to corner of each.
      expect(pixel(3, 3), pixel(46, 96));
    });

    test('moved, it pixelates what it has been moved over', () async {
      final photo = await _split(100, 100);
      final pixels = PixelSampler(photo);
      await pixels.prepare();
      final left = area(
        center: const Offset(0.25, 0.5),
        width: 0.3,
        height: 0.3,
        style: HideStyle.pixelate,
        block: 0.1,
      );
      final before = await _render(photo, [left], pixels: pixels);
      expect(before(25, 50), red);

      final moved = left.withPlacement(center: const Offset(0.75, 0.5));
      final after = await _render(photo, [moved], pixels: pixels);
      expect(after(75, 50), blue);
      expect(after(25, 50), red, reason: 'the photo, uncovered');
    });

    test('pixelated before the pixels are read, it is blurred', () async {
      final photo = await _split(100, 100);
      final pixel = await _render(photo, [
        area(width: 1, height: 1, style: HideStyle.pixelate, block: 0.1),
      ]);
      // The hard seam down the middle has become a ramp.
      expect(pixel(47, 50).r, lessThan(0.98));
      expect(pixel(53, 50).r, greaterThan(0.02));
    });

    test('its cells sit on one grid, however the area is placed', () async {
      final pixels = PixelSampler(await _split(100, 100));
      await pixels.prepare();
      Mosaic at(double left) => pixels.mosaic(
        Rect.fromLTWH(left, 0.3, 0.3, 0.3),
        block: 0.1,
        orientation: ImageOrientation.none,
        frame: const Size(100, 100),
      )!;
      expect(at(0.12).rect.left, closeTo(0.1, 1e-9));
      expect(at(0.17).rect.left, closeTo(0.1, 1e-9));
      expect(at(0.12).cols, 4);
    });
  });

  group('drawing an area', () {
    test('a drag measures its height against the width', () {
      final box = area().over(
        const Rect.fromLTRB(0.1, 0.2, 0.5, 0.3),
        const Size(1000, 2000),
      );
      expect(box.center.dx, closeTo(0.3, 1e-9));
      expect(box.center.dy, closeTo(0.25, 1e-9));
      expect(box.width, closeTo(0.4, 1e-9));
      expect(box.height, closeTo(0.2, 1e-9));
    });

    test('a freehand outline is fitted into its own box', () {
      final lasso = area().around(const [
        Offset(0.2, 0.2),
        Offset(0.6, 0.3),
        Offset(0.3, 0.6),
      ], const Size(100, 100));
      expect(lasso.shape, HideShape.freehand);
      expect(lasso.isFreehand, isTrue);
      expect(lasso.center.dx, closeTo(0.4, 1e-9));
      expect(lasso.center.dy, closeTo(0.4, 1e-9));
      expect(lasso.width, closeTo(0.4, 1e-9));
      expect(lasso.outline[0].dx, closeTo(-0.5, 1e-9));
      expect(lasso.outline[1].dy, closeTo(-0.25, 1e-9));
      expect(lasso.outline[2].dy, closeTo(0.5, 1e-9));
    });
  });

  group('the bars', () {
    test(
      'a status bar sits across the top of the crop, wherever it is',
      () async {
        final pixel = await _render(
          await _solid(100, 200, white),
          const [
            StatusBarOp(
              height: 0.1,
              background: Color(0xFF223344),
              foreground: white,
              style: StatusBarStyle.ios,
            ),
          ],
          crop: const Rect.fromLTRB(0, 0.25, 1, 0.75),
          size: const Size(100, 100),
        );
        expect(pixel(50, 4), const Color(0xFF223344));
        expect(pixel(50, 16), white);
      },
    );

    test('each phone draws a bar of its own', () async {
      Future<List<Color>> band(StatusBarStyle style) async {
        final pixel = await _render(await _solid(400, 800, white), [
          StatusBarOp(
            height: 0.12,
            background: black,
            foreground: white,
            style: style,
          ),
        ]);
        return [
          for (var y = 0; y < 48; y += 2)
            for (var x = 0; x < 400; x += 2) pixel(x, y),
        ];
      }

      final ios = await band(StatusBarStyle.ios);
      final android = await band(StatusBarStyle.android);
      final samsung = await band(StatusBarStyle.samsung);
      expect(samsung, isNot(equals(android)));
      expect(samsung, isNot(equals(ios)));
      expect(android, isNot(equals(ios)));
    });

    test(
      'a navigation bar runs along the bottom, its handle in the middle',
      () async {
        final pixel = await _render(await _solid(400, 800, white), const [
          NavBarOp(
            height: 0.06,
            style: NavBarStyle.gesture,
            background: Color(0xFF101010),
            foreground: red,
          ),
        ]);
        expect(pixel(10, 790), const Color(0xFF101010));
        expect(pixel(200, 788), red, reason: 'the handle');
        expect(pixel(200, 770), white, reason: 'the photo above the bar');
      },
    );

    test(
      'with no background, only the handle is drawn over the photo',
      () async {
        final pixel = await _render(await _solid(400, 800, white), const [
          NavBarOp(
            height: 0.087,
            style: NavBarStyle.ios,
            background: Color(0x00000000),
            foreground: black,
          ),
        ]);
        expect(pixel(10, 790), white);
        expect(pixel(200, 789), black);
      },
    );

    test('three buttons are three glyphs, apart', () async {
      final pixel = await _render(await _solid(400, 800, white), const [
        NavBarOp(
          height: 0.117,
          style: NavBarStyle.buttons,
          background: white,
          foreground: black,
        ),
      ]);
      bool inked(int fromX, int toX) {
        for (var x = fromX; x < toX; x++) {
          for (var y = 760; y < 794; y++) {
            if (pixel(x, y).computeLuminance() < 0.5) return true;
          }
        }
        return false;
      }

      expect(inked(76, 100), isTrue, reason: 'back');
      expect(inked(188, 212), isTrue, reason: 'home');
      expect(inked(300, 324), isTrue, reason: 'recent apps');
      expect(inked(130, 160), isFalse);
      expect(inked(240, 270), isFalse);
    });
  });

  group('an edit saved before hiding was an object', () {
    test('opens with its patches, blurs and mosaics as areas', () async {
      final edit = await screenshotEditFromJson(
        {
          'source': 'lib/capture.png',
          'ops': [
            {
              'kind': 'text',
              'id': 2,
              'text': 'Hi',
              'center': {'x': 0.5, 'y': 0.5},
              'w': 0.2,
              'h': 0.1,
            },
            {
              'kind': 'redact',
              'rect': {'l': 0, 't': 0, 'r': 1, 'b': 0.05},
              'color': 0xFF112233,
              'cornerRadius': 0.01,
              'style': 'fill',
            },
            {
              'kind': 'redact',
              'rect': {'l': 0.1, 't': 0.5, 'r': 0.3, 'b': 0.6},
              'color': 0xFF000000,
              'style': 'blur',
              'blur': 0.04,
            },
            {
              'kind': 'pixelate',
              'rect': {'l': 0.2, 't': 0.4, 'r': 0.6, 'b': 0.5},
              'cols': 8,
              'rows': 2,
              'colors': [for (var i = 0; i < 16; i++) 0xFF808080],
            },
            {
              'kind': 'statusBar',
              'rect': {'l': 0, 't': 0, 'r': 1, 'b': 0.05},
              'background': 0xFF000000,
              'foreground': 0xFFFFFFFF,
              'style': 'android',
            },
          ],
        },
        imageSize: const Size(1000, 2000),
        texture: (_) async => null,
        sticker: (_) async => null,
      );
      final [text, patch, blur, mosaic, bar] = edit!.ops;
      expect((text as TextOp).id, 2);

      patch as HideOp;
      expect(patch.style, HideStyle.cover);
      expect(patch.color.toARGB32(), 0xFF112233);
      expect(patch.cornerRadius, closeTo(0.01, 1e-9));
      expect(patch.center.dy, closeTo(0.025, 1e-9));
      expect(patch.width, closeTo(1, 1e-9));
      // 5% of a capture twice as tall as it is wide.
      expect(patch.height, closeTo(0.1, 1e-9));

      blur as HideOp;
      expect(blur.style, HideStyle.blur);
      expect(blur.blur, closeTo(0.04, 1e-9));

      mosaic as HideOp;
      expect(mosaic.style, HideStyle.pixelate);
      expect(mosaic.block, closeTo(0.05, 1e-9));

      // Each with an id of its own, past the one already in use.
      expect({patch.id, blur.id, mosaic.id}, {3, 4, 5});

      bar as StatusBarOp;
      expect(bar.style, StatusBarStyle.android);
      expect(bar.height, closeTo(0.1, 1e-9));
    });
  });

  group('a picture laid over the photo', () {
    test('cropped, it shows only what is left of it', () async {
      final texture = await _split(20, 10);
      final shown = ImageOp(
        id: 1,
        image: texture,
        source: 'lib/logo.png',
        center: const Offset(0.5, 0.5),
        width: 0.5,
        height: ImageOp.heightFor(
          texture,
          0.5,
          const Rect.fromLTRB(0.5, 0, 1, 1),
        ),
        crop: const Rect.fromLTRB(0.5, 0, 1, 1),
      );
      expect(shown.height, closeTo(0.5, 1e-9), reason: 'a square of it');
      final pixel = await _render(await _solid(100, 100, white), [shown]);
      expect(pixel(30, 50), blue);
      expect(pixel(70, 50), blue);

      final whole = await _render(await _solid(100, 100, white), [
        shown.croppedTo(null).withPlacement(height: 0.5),
      ]);
      expect(whole(30, 50), red);
    });

    test('cropped to a ratio, its pixels keep their shape', () async {
      final texture = await _solid(200, 100, white);
      final op = ImageOp(
        id: 1,
        image: texture,
        source: 'lib/wide.png',
        center: const Offset(0.5, 0.5),
        width: 0.4,
        height: 0.2,
      );
      final square = op.croppedTo(1);
      expect(square.crop.left, closeTo(0.25, 1e-9));
      expect(square.crop.right, closeTo(0.75, 1e-9));
      expect(square.height, closeTo(square.width, 1e-9));
      final back = square.croppedTo(null);
      expect(back.isCropped, isFalse);
      expect(back.height, closeTo(0.2, 1e-9));
    });

    test('its rim is drawn inside its box, in its colour', () async {
      final texture = await _solid(10, 10, red);
      final pixel = await _render(await _solid(100, 100, white), [
        ImageOp(
          id: 1,
          image: texture,
          source: 'lib/red.png',
          center: const Offset(0.5, 0.5),
          width: 0.5,
          height: 0.5,
          borderWidth: 0.06,
          borderColor: const Color(0xFF00FF00),
        ),
      ]);
      expect(pixel(28, 50), const Color(0xFF00FF00));
      expect(pixel(50, 50), red);
      expect(pixel(20, 50), white, reason: 'the rim adds nothing outside');
    });

    test('a duplicate keeps every setting', () async {
      final texture = await _solid(10, 10, red);
      final op = ImageOp(
        id: 1,
        image: texture,
        source: 'lib/red.png',
        center: const Offset(0.3, 0.4),
        width: 0.5,
        height: 0.25,
        rotationDeg: 15,
        opacity: 0.8,
        flipH: true,
        cornerRadius: 0.02,
        crop: const Rect.fromLTRB(0, 0.25, 1, 0.75),
        borderWidth: 0.01,
        borderColor: blue,
      );
      final copy = op.withId(9);
      expect(copy.id, 9);
      expect(copy.crop, op.crop);
      expect(copy.borderWidth, op.borderWidth);
      expect(copy.borderColor, op.borderColor);
      expect(copy.flipH, isTrue);
      expect(copy.cornerRadius, op.cornerRadius);
      expect(copy.rotationDeg, op.rotationDeg);
      expect(copy.opacity, op.opacity);
    });

    test('its crop and rim are saved with the edit', () async {
      final texture = await _solid(20, 10, red);
      final edit = ScreenshotEdit(
        source: 'lib/capture.png',
        crop: full,
        ops: [
          ImageOp(
            id: 3,
            image: texture,
            source: 'lib/logo.png',
            center: const Offset(0.5, 0.5),
            width: 0.4,
            height: 0.4,
            crop: const Rect.fromLTRB(0.25, 0, 0.75, 1),
            borderWidth: 0.02,
            borderColor: blue,
          ),
        ],
      );
      final back = await screenshotEditFromJson(
        screenshotEditToJson(edit),
        imageSize: const Size(100, 100),
        texture: (_) async => texture,
        sticker: (_) async => null,
      );
      final op = back!.ops.single as ImageOp;
      expect(op.crop, const Rect.fromLTRB(0.25, 0, 0.75, 1));
      expect(op.borderWidth, closeTo(0.02, 1e-9));
      expect(op.borderColor, blue);
    });
  });

  testWidgets('an element carries its words onto the photo', (tester) async {
    // A widget test: words are measured through the font loader.
    final pixel = (await tester.runAsync(() async {
      return _render(await _solid(200, 200, white), [
        const ShapeOp(
          id: 1,
          spec: ShapeSpec(
            kind: ShapeKind.rectangle,
            width: 0.6,
            height: 0.3,
            fill: black,
            label: ShapeLabel('WWWW', size: 0.1, color: white),
          ),
          center: Offset(0.5, 0.5),
          width: 0.6,
          height: 0.3,
        ),
      ]);
    }))!;
    var lit = 0;
    for (var x = 50; x < 150; x++) {
      if (pixel(x, 100).computeLuminance() > 0.5) lit++;
    }
    expect(lit, greaterThan(10), reason: 'the words, in white, on the black');
  });

  group('the canvas', () {
    const stage = Size(400, 400);

    Future<
      ({
        List<int?> selected,
        List<PlacedOp> moved,
        List<Offset> painted,
        int ended,
        int commits,
      })
    >
    drag(
      WidgetTester tester, {
      required List<EditOp> ops,
      required Offset from,
      required Offset by,
      bool paints = true,
      bool Function(PlacedOp op)? selectable,
      PlacedOp? selection,
    }) async {
      final image = await _imageFor(tester, 200, 200);
      addTearDown(image.dispose);
      final selected = <int?>[];
      final moved = <PlacedOp>[];
      final painted = <Offset>[];
      var ended = 0, commits = 0;

      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = stage;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: stage,
                child: RetouchCanvas(
                  image: image,
                  crop: full,
                  ops: ops,
                  draft: null,
                  orientation: ImageOrientation.none,
                  cropMode: false,
                  targetAspect: 1,
                  paints: paints,
                  objectMode: true,
                  selectable: selectable,
                  selection: selection,
                  onSelectObject: selected.add,
                  onObjectChanged: moved.add,
                  onObjectCommitted: () => commits++,
                  onCropChanged: (_) {},
                  onPaintStart: painted.add,
                  onPaintUpdate: (_, _) {},
                  onPaintEnd: () => ended++,
                  onPaintCancel: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      final origin = tester.getTopLeft(find.byType(RetouchCanvas));
      final gesture = await tester.startGesture(origin + from);
      await _settle(tester);
      await gesture.moveBy(by);
      await _settle(tester);
      await gesture.up();
      await _settle(tester);
      return (
        selected: selected,
        moved: moved,
        painted: painted,
        ended: ended,
        commits: commits,
      );
    }

    bool onlyAreas(PlacedOp op) => op is HideOp;

    testWidgets('in Hide, a drag on bare photo draws a new area', (
      tester,
    ) async {
      final r = await drag(
        tester,
        ops: [area()],
        from: const Offset(40, 40),
        by: const Offset(60, 60),
        selectable: onlyAreas,
      );
      expect(r.selected, [null]);
      expect(r.painted, hasLength(1));
      expect(r.painted.single.dx, closeTo(0.1, 0.01));
      expect(r.ended, 1);
      expect(r.moved, isEmpty);
    });

    testWidgets('in Hide, a drag on an area moves it', (tester) async {
      final r = await drag(
        tester,
        ops: [area()],
        from: const Offset(200, 200),
        by: const Offset(40, 0),
        selectable: onlyAreas,
      );
      expect(r.selected, [5]);
      expect(r.moved.last.center.dx, closeTo(0.6, 0.02));
      expect(r.painted, isEmpty, reason: 'nothing drawn under it');
      expect(r.ended, 0);
      expect(r.commits, 1);
    });

    testWidgets('each tool picks up only its own objects', (tester) async {
      const star = ShapeOp(
        id: 7,
        spec: ShapeSpec(kind: ShapeKind.star),
        center: Offset(0.5, 0.5),
        width: 0.4,
        height: 0.4,
      );
      final hide = await drag(
        tester,
        ops: const [star],
        from: const Offset(200, 200),
        by: const Offset(40, 0),
        selectable: onlyAreas,
      );
      expect(hide.selected, [null], reason: 'Hide passes over a sticker');
      expect(hide.painted, hasLength(1), reason: '…and draws');

      final stickers = await drag(
        tester,
        ops: [area()],
        from: const Offset(200, 200),
        by: const Offset(40, 0),
        paints: false,
        selectable: (op) => op is! HideOp,
      );
      expect(stickers.selected, [null], reason: 'Stickers pass over an area');
      expect(stickers.moved, isEmpty);
    });

    testWidgets('a thin area is picked up by its middle, not stretched', (
      tester,
    ) async {
      // Over one line of text: 16 of the stage's 400 pixels tall, which the
      // grips' whole reach would cover from top to bottom.
      final line = area(height: 0.04);
      final r = await drag(
        tester,
        ops: [line],
        selection: line,
        from: const Offset(200, 200),
        by: const Offset(0, 60),
        selectable: onlyAreas,
      );
      expect(r.moved.last.center.dy, closeTo(0.65, 0.01));
      expect(r.moved.last.height, closeTo(0.04, 1e-6));
      expect(r.moved.last.width, closeTo(0.4, 1e-6));
    });

    testWidgets('a side pulled out stretches an area and nothing else', (
      tester,
    ) async {
      final box = area();
      // The right side's middle: x = 0.7 of the stage, halfway down.
      final r = await drag(
        tester,
        ops: [box],
        selection: box,
        from: const Offset(280, 200),
        by: const Offset(40, 0),
        selectable: onlyAreas,
      );
      final stretched = r.moved.last;
      expect(stretched.width, closeTo(0.5, 0.01));
      expect(stretched.height, closeTo(0.2, 1e-6));
      expect(
        stretched.center.dx - stretched.width / 2,
        closeTo(0.3, 0.01),
        reason: 'the far side stays put',
      );
      expect(r.painted, isEmpty);
    });

    testWidgets('a side pulled in crops a picture rather than squash it', (
      tester,
    ) async {
      final texture = await _imageFor(tester, 20, 10);
      addTearDown(texture.dispose);
      final picture = ImageOp(
        id: 8,
        image: texture,
        source: 'lib/logo.png',
        center: const Offset(0.5, 0.5),
        width: 0.4,
        height: 0.2,
      );
      final r = await drag(
        tester,
        ops: [picture],
        selection: picture,
        from: const Offset(280, 200),
        by: const Offset(-40, 0),
        paints: false,
      );
      final cropped = r.moved.last as ImageOp;
      expect(cropped.crop.right, closeTo(0.75, 0.01));
      expect(cropped.crop.left, 0);
      expect(cropped.width, closeTo(0.3, 0.01));
      expect(cropped.height, closeTo(0.2, 1e-6), reason: 'not squashed');
      expect(cropped.center.dx, closeTo(0.45, 0.01));
    });
  });
}

Future<ui.Image> _fromPixels(Uint8List rgba, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

Uint8List _pixels(int w, int h, Color Function(int x) colourAt) {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = colourAt(x);
      final o = (y * w + x) * 4;
      bytes[o] = (c.r * 255).round();
      bytes[o + 1] = (c.g * 255).round();
      bytes[o + 2] = (c.b * 255).round();
      bytes[o + 3] = 255;
    }
  }
  return bytes;
}

Future<ui.Image> _solid(int w, int h, Color colour) =>
    _fromPixels(_pixels(w, h, (_) => colour), w, h);

/// Red on the left half, blue on the right.
Future<ui.Image> _split(int w, int h) => _fromPixels(
  _pixels(
    w,
    h,
    (x) => x < w / 2 ? const Color(0xFFFF0000) : const Color(0xFF0000FF),
  ),
  w,
  h,
);

/// A capture for a widget test, decoded on the real event loop — see the note
/// on the pointer mapping test's own copy.
Future<ui.Image> _imageFor(WidgetTester tester, int w, int h) async =>
    (await tester.runAsync(() => _split(w, h)))!;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// [ops] composed over [photo], read back pixel by pixel.
Future<Color Function(int, int)> _render(
  ui.Image photo,
  List<EditOp> ops, {
  PixelSampler? pixels,
  Rect crop = const Rect.fromLTRB(0, 0, 1, 1),
  Size? size,
}) async {
  final out = size ?? Size(photo.width.toDouble(), photo.height.toDouble());
  final w = out.width.round(), h = out.height.round();
  final recorder = ui.PictureRecorder();
  ScreenshotComposer(
    image: photo,
    crop: crop,
    ops: ops,
    pixels: pixels,
  ).paint(Canvas(recorder), Offset.zero & out);
  final rendered = await recorder.endRecording().toImage(w, h);
  final data = (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  rendered.dispose();
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
