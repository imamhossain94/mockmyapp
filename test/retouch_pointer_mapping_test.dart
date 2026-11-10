import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/models/shape_spec.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_edit_ops.dart';
import 'package:mockmyapp/features/editor/screenshot_editor/screenshot_editor_screen.dart';

/// Where the finger lands on the artwork, which is the one thing the retouch
/// canvas cannot get wrong and still be a retoucher.
///
/// The pointer and the painter derive the visible region separately, and they
/// drifted apart once zoom existed: the painter was moved onto the zoomed view
/// and the pointer was left mapping through the un-zoomed crop, so a stroke at
/// 4x landed roughly four times as far from the cursor as it should. Nothing
/// caught it because every test on this file tests pure crop maths, and the
/// canvas itself had no test at all.
/// A flat test capture.
///
/// Decoded inside [WidgetTester.runAsync]: `decodeImageFromPixels` hands its
/// result back through the engine's real async machinery, which a widget test
/// does not pump unless asked — called outside it the completer never fires and
/// the test hangs rather than failing, which is a far worse thing to leave
/// behind than a red assertion.
Future<ui.Image> _image(WidgetTester tester, int w, int h) async {
  final pixels = Uint8List(w * h * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 90;
    pixels[i + 1] = 120;
    pixels[i + 2] = 200;
    pixels[i + 3] = 255;
  }
  late ui.Image image;
  await tester.runAsync(() async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    image = await done.future;
  });
  return image;
}

/// A fixed number of frames rather than `pumpAndSettle`.
///
/// The canvas keeps no animation of its own, but settling waits on the whole
/// tree; anything repeating anywhere in it turns a failing assertion into a
/// hung test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  const stage = Size(400, 400);

  /// Pumps the canvas over [crop] and returns the normalised points that
  /// `onPaintStart` reports.
  Future<List<Offset>> pumpAndTap(
    WidgetTester tester, {
    required ui.Image image,
    required Rect crop,
    required List<Offset> taps,
    double zoom = 1,
  }) async {
    final reported = <Offset>[];

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = stage;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: stage.width,
              height: stage.height,
              child: RetouchCanvas(
                image: image,
                crop: crop,
                ops: const [],
                draft: null,
                orientation: ImageOrientation.none,
                cropMode: false,
                targetAspect: 1,
                paints: true,
                objectMode: false,
                onSelectObject: (_) {},
                onObjectChanged: (_) {},
                onObjectCommitted: () {},
                onCropChanged: (_) {},
                onPaintStart: reported.add,
                onPaintUpdate: (_, _) {},
                onPaintEnd: () {},
                onPaintCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    final centre = tester.getCenter(find.byType(RetouchCanvas));

    // A scale signal, not a wheel scroll: a plain scroll PANS here and only
    // zooms with ctrl/meta held, so scrolling would have quietly tested the
    // wrong gesture. Sent about the exact centre of the stage, so the view
    // stays centred and the expected numbers stay arithmetic.
    if (zoom != 1) {
      await tester.sendEventToBinding(
        PointerScaleEvent(position: centre, scale: zoom),
      );
      await _settle(tester);
    }

    for (final tap in taps) {
      final at = tester.getTopLeft(find.byType(RetouchCanvas)) + tap;
      final gesture = await tester.startGesture(at);
      await tester.pump();
      await gesture.up();
      await _settle(tester);
    }
    return reported;
  }

  testWidgets('at fit, the middle of the stage is the middle of the crop', (
    tester,
  ) async {
    final image = await _image(tester, 200, 200);
    addTearDown(image.dispose);

    final got = await pumpAndTap(
      tester,
      image: image,
      crop: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
      taps: const [Offset(200, 200)],
    );

    expect(got, hasLength(1));
    expect(got.single.dx, closeTo(0.5, 0.01));
    expect(got.single.dy, closeTo(0.5, 0.01));
  });

  testWidgets('zoomed in, the middle of the stage is still the same pixel', (
    tester,
  ) async {
    // The regression. Zooming about the centre narrows the view around that
    // point, so whatever was under the middle of the stage must stay under it —
    // the magnified pixel is the one you were pointing at. Mapping through the
    // un-zoomed crop instead pulled the reported point back toward the crop's
    // own centre by the zoom factor.
    final image = await _image(tester, 200, 200);
    addTearDown(image.dispose);

    final got = await pumpAndTap(
      tester,
      image: image,
      crop: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
      taps: const [Offset(200, 200), Offset(300, 200)],
      zoom: 2,
    );

    expect(got, hasLength(2));
    // The centre is unmoved by a centred zoom.
    expect(got[0].dx, closeTo(0.5, 0.01));
    expect(got[0].dy, closeTo(0.5, 0.01));

    // A quarter of the stage to the right is a SMALLER step across the artwork
    // than it was at fit, because the view has narrowed. The crop is 0.6 wide,
    // so at fit that step is 0.25 x 0.6 = 0.15 of the image; at 2x the view is
    // 0.3 wide and the same step must be half that.
    final step = got[1].dx - got[0].dx;
    expect(
      step,
      closeTo(0.075, 0.005),
      reason: 'zoom did not narrow the pointer mapping — step was $step',
    );
  });

  group('dragging a placed object', () {
    ShapeOp star({Offset center = const Offset(0.5, 0.5)}) => ShapeOp(
      id: 7,
      spec: const ShapeSpec(kind: ShapeKind.star, fill: Color(0xFFFF0000)),
      center: center,
      width: 0.4,
      height: 0.4,
    );

    /// Pumps the canvas in object mode and drags from [from] by [by].
    Future<({List<PlacedOp> reported, int commits, List<int?> selected})> drag(
      WidgetTester tester, {
      required ui.Image image,
      required Offset from,
      required Offset by,
    }) async {
      final reported = <PlacedOp>[];
      final selected = <int?>[];
      var commits = 0;

      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = stage;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: stage.width,
                height: stage.height,
                child: RetouchCanvas(
                  image: image,
                  crop: const Rect.fromLTRB(0, 0, 1, 1),
                  ops: [star()],
                  draft: null,
                  orientation: ImageOrientation.none,
                  cropMode: false,
                  targetAspect: 1,
                  paints: false,
                  objectMode: true,
                  onSelectObject: selected.add,
                  onObjectChanged: reported.add,
                  onObjectCommitted: () => commits++,
                  onCropChanged: (_) {},
                  onPaintStart: (_) {},
                  onPaintUpdate: (_, _) {},
                  onPaintEnd: () {},
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

      return (reported: reported, commits: commits, selected: selected);
    }

    testWidgets('a drag on the object moves it and commits once', (
      tester,
    ) async {
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      // A square image in a square stage, so the artwork fills it: the middle
      // of the stage is the middle of the capture, where the star sits.
      final r = await drag(
        tester,
        image: image,
        from: const Offset(200, 200),
        by: const Offset(80, 0),
      );

      expect(r.selected, [7], reason: 'the object under the finger is picked');
      expect(r.reported, isNotEmpty);
      // 80px of a 400px stage over the whole capture is a fifth of the width.
      expect(r.reported.last.center.dx, closeTo(0.7, 0.02));
      expect(r.reported.last.center.dy, closeTo(0.5, 0.02));
      // One entry for the whole drag, not one per frame.
      expect(r.commits, 1);
    });

    testWidgets('the grab point is kept, so the object does not snap', (
      tester,
    ) async {
      // Grabbing near an edge and moving must translate by the drag, not
      // centre the object on the finger — the snap is the tell-tale of a
      // handler that forgot where it was grabbed.
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      final r = await drag(
        tester,
        image: image,
        from: const Offset(230, 200),
        by: const Offset(40, 40),
      );

      expect(r.reported.last.center.dx, closeTo(0.6, 0.02));
      expect(r.reported.last.center.dy, closeTo(0.6, 0.02));
    });

    testWidgets('a tap on empty space deselects and moves nothing', (
      tester,
    ) async {
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      final r = await drag(
        tester,
        image: image,
        // Well outside the star's 0.4-wide box.
        from: const Offset(30, 30),
        by: const Offset(50, 0),
      );

      expect(r.selected, [null]);
      expect(r.reported, isEmpty, reason: 'nothing was grabbed');
      expect(r.commits, 0);
    });
  });

  group('two fingers on an object', () {
    ShapeOp star() => const ShapeOp(
      id: 7,
      spec: ShapeSpec(kind: ShapeKind.star, fill: Color(0xFFFF0000)),
      center: Offset(0.5, 0.5),
      width: 0.4,
      height: 0.4,
    );

    /// Pinches with two fingers, the first landing on [first].
    ///
    /// adb cannot drive a second finger, so this is the only place the
    /// arbitration can be exercised at all: whether a two-finger gesture turns
    /// into an object transform or a stage zoom depends entirely on what the
    /// FIRST finger landed on, and that is the decision worth pinning.
    Future<List<PlacedOp>> pinch(
      WidgetTester tester, {
      required ui.Image image,
      required Offset first,
      required Offset second,
      required Offset firstTo,
      required Offset secondTo,
    }) async {
      final reported = <PlacedOp>[];

      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = stage;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: stage.width,
                height: stage.height,
                child: RetouchCanvas(
                  image: image,
                  crop: const Rect.fromLTRB(0, 0, 1, 1),
                  ops: [star()],
                  draft: null,
                  orientation: ImageOrientation.none,
                  cropMode: false,
                  targetAspect: 1,
                  paints: false,
                  objectMode: true,
                  onSelectObject: (_) {},
                  onObjectChanged: reported.add,
                  onObjectCommitted: () {},
                  onCropChanged: (_) {},
                  onPaintStart: (_) {},
                  onPaintUpdate: (_, _) {},
                  onPaintEnd: () {},
                  onPaintCancel: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      final origin = tester.getTopLeft(find.byType(RetouchCanvas));
      final a = await tester.startGesture(origin + first, pointer: 1);
      await _settle(tester);
      final b = await tester.startGesture(origin + second, pointer: 2);
      await _settle(tester);
      await a.moveTo(origin + firstTo);
      await b.moveTo(origin + secondTo);
      await _settle(tester);
      await a.up();
      await b.up();
      await _settle(tester);

      return reported;
    }

    testWidgets('spreading them scales the object up', (tester) async {
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      final before = star();
      final reported = await pinch(
        tester,
        image: image,
        // Both inside the star's box, which is what routes the gesture to the
        // object rather than to the stage.
        first: const Offset(190, 200),
        second: const Offset(210, 200),
        firstTo: const Offset(150, 200),
        secondTo: const Offset(250, 200),
      );

      expect(reported, isNotEmpty, reason: 'the object never moved');
      // Span went 20 -> 100, so the box grows about fivefold.
      expect(reported.last.width, greaterThan(before.width * 2));
    });

    testWidgets('turning them turns the object', (tester) async {
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      final reported = await pinch(
        tester,
        image: image,
        first: const Offset(180, 200),
        second: const Offset(220, 200),
        // Same span, rotated a quarter turn about the midpoint.
        firstTo: const Offset(200, 180),
        secondTo: const Offset(200, 220),
      );

      expect(reported, isNotEmpty);
      expect(reported.last.rotationDeg.abs(), greaterThan(45));
    });

    testWidgets('starting off the object leaves it alone', (tester) async {
      // The arbitration in one test: the same two-finger gesture, begun on
      // empty canvas, is a stage zoom and must not touch the object.
      final image = await _image(tester, 200, 200);
      addTearDown(image.dispose);

      final reported = await pinch(
        tester,
        image: image,
        first: const Offset(20, 20),
        second: const Offset(40, 20),
        firstTo: const Offset(10, 10),
        secondTo: const Offset(90, 30),
      );

      expect(reported, isEmpty);
    });
  });
}
