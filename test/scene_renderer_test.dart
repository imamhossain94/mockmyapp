import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/custom_device_frame.dart';

/// Mounts the capture subtree inside a box of [stage] logical pixels — standing
/// in for whatever room the render dialog happens to have on a given phone.
/// A catalog holding just the built-frame entry, for docs that place a frame.
///
/// `FrameCatalog.byId` falls back to `devices.first`, so an empty catalog
/// throws the moment a doc has any frame at all.
const _catalog = FrameCatalog([
  FrameDevice(
    id: 'studio-custom-ios',
    brand: 'Studio',
    series: 'Custom',
    model: 'Build your own',
    platform: FramePlatform.ios,
    releaseYear: 2025,
    screenAspect: 0.4615,
    frameAspect: 0.4743,
    screenRect: ScreenRect(x: 0.025, y: 0.0119, w: 0.95, h: 0.9763),
    cornerRadiusPct: 0.07,
    cutout: 'none',
    frameStyle: 'custom',
    variants: [FrameVariant(id: 'design', name: 'Design', asset: '')],
  ),
]);

Future<GlobalKey> _pumpStage(
  WidgetTester tester,
  ScreenDoc doc, {
  Size stage = const Size(300, 260),
}) async {
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: stage.width,
          height: stage.height,
          child: SceneRenderer.captureStage(
            boundaryKey: boundaryKey,
            doc: doc,
            catalog: _catalog,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return boundaryKey;
}

void main() {
  const background = SolidBackground(Color(0xFF2A6DF4));

  group('capture stage geometry', () {
    testWidgets('scene is laid out at full canvas size, not the capture box', (
      tester,
    ) async {
      const canvas = Size(1179, 2556);
      await _pumpStage(
        tester,
        const ScreenDoc(id: 'a', canvas: canvas, background: background),
      );

      // The regression: the scene's SizedBox inherited the boundary's tight
      // `canvas / divisor` constraints, so it measured a quarter of the canvas
      // and was then scaled down by another quarter — painting the whole scene
      // into the top-left 1/16 of the export.
      expect(
        tester.getSize(find.byType(SceneView)),
        canvas,
        reason: 'SceneView must measure the document canvas',
      );
    });

    testWidgets('boundary measures canvas / divisor on any stage size', (
      tester,
    ) async {
      const canvas = Size(1179, 2556);
      // Two very different stages stand in for two different phones; the
      // captured layer has to come out identical on both.
      for (final stage in [const Size(300, 260), const Size(900, 700)]) {
        final key = await _pumpStage(
          tester,
          const ScreenDoc(id: 'a', canvas: canvas, background: background),
          stage: stage,
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        // Rasterised at pixelRatio 4, this is exactly the canvas in pixels.
        expect(
          boundary.size,
          Size(canvas.width / 4, canvas.height / 4),
          reason: 'boundary size must not depend on the $stage stage',
        );
      }
    });

    testWidgets('landscape canvases keep their aspect ratio', (tester) async {
      const canvas = Size(2556, 1179);
      final key = await _pumpStage(
        tester,
        const ScreenDoc(id: 'a', canvas: canvas, background: background),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

      expect(tester.getSize(find.byType(SceneView)), canvas);
      expect(
        boundary.size.width / boundary.size.height,
        closeTo(canvas.width / canvas.height, 0.001),
      );
    });
  });

  group('caption effects', () {
    testWidgets('an outlined, glowing caption on a plate renders', (
      tester,
    ) async {
      // Exercises the branches the caption layer only takes when it is styled:
      // the two-layer stroke stack, the shadow list, and the plate's rim.
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'effects',
          canvas: Size(1080, 1920),
          background: background,
          caption: CaptionSpec(
            text: 'ARROW RUSH',
            letterSpacing: -1.5,
            strokeWidth: 6,
            strokeColor: Color(0xFF0A0E22),
            shadowBlur: 12,
            shadowOffsetY: 5,
            glowBlur: 20,
            glowColor: Color(0xFF4DE9FF),
            backgroundColor: Color(0xFF1B34A8),
            backgroundRadius: 40,
            backgroundBorderColor: Color(0xFFFFFFFF),
            backgroundBorderWidth: 2,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // The outline is a second copy of the text painted underneath the fill;
      // both must carry the same string or their metrics diverge.
      expect(find.text('ARROW RUSH'), findsNWidgets(2));
    });

    testWidgets('an unstyled caption is still a single text layer', (
      tester,
    ) async {
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'plain',
          canvas: Size(1080, 1920),
          background: background,
          caption: CaptionSpec(text: 'ARROW RUSH'),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('ARROW RUSH'), findsOneWidget);
    });

    testWidgets('each run paints in its own ink inside one paragraph', (
      tester,
    ) async {
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'two-tone',
          canvas: Size(1080, 1920),
          background: background,
          caption: CaptionSpec(
            text: 'UNIQUE\nSHAPES',
            color: Color(0xFF0000FF),
            runs: [
              CaptionRun('UNIQUE\n', color: Color(0xFFFF0000)),
              // No colour of its own: falls back to the caption's ink.
              CaptionRun('SHAPES'),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(
        texts,
        hasLength(1),
        reason: 'a styled caption is one paragraph, not a row per line',
      );

      final spans = _spansOf(texts.single);
      expect(spans.map((s) => s.text), ['UNIQUE\n', 'SHAPES']);
      expect(spans[0].style!.color, const Color(0xFFFF0000));
      expect(spans[1].style!.color, const Color(0xFF0000FF));
    });

    testWidgets('a run can override its size and weight', (tester) async {
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'scaled',
          canvas: Size(1179, 1920),
          background: background,
          caption: CaptionSpec(
            text: 'BIG\nsmall',
            size: 50,
            bold: false,
            runs: [
              CaptionRun('BIG\n', sizeScale: 2, bold: true),
              CaptionRun('small'),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final spans = _spansOf(tester.widget<Text>(find.byType(Text)));
      // 1179-wide canvas, so the design-px scale factor is exactly 1.
      expect(spans[0].style!.fontSize, closeTo(100, 0.01));
      expect(spans[1].style!.fontSize, closeTo(50, 0.01));
      expect(spans[0].style!.fontWeight, FontWeight.bold);
      expect(spans[1].style!.fontWeight, FontWeight.normal);
    });

    testWidgets('a run can override its slant and rule', (tester) async {
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'slanted',
          canvas: Size(1179, 1920),
          background: background,
          caption: CaptionSpec(
            text: 'plain fancy',
            runs: [
              CaptionRun('plain '),
              CaptionRun('fancy', italic: true, underline: true),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final spans = _spansOf(tester.widget<Text>(find.byType(Text)));
      expect(spans[0].style!.fontStyle, FontStyle.normal);
      expect(spans[0].style!.decoration, TextDecoration.none);
      expect(spans[1].style!.fontStyle, FontStyle.italic);
      expect(spans[1].style!.decoration, TextDecoration.underline);
    });

    testWidgets('an outlined rich caption keeps its stroke uncoloured', (
      tester,
    ) async {
      // The stroke layer must not take a run's ink, or it would paint the fill
      // colours over its own outline.
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'runs-outlined',
          canvas: Size(1080, 1920),
          background: background,
          caption: CaptionSpec(
            text: 'A\nB',
            strokeWidth: 6,
            strokeColor: Color(0xFF000000),
            runs: [
              CaptionRun('A\n', color: Color(0xFFFF0000)),
              CaptionRun('B', color: Color(0xFF00FF00)),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // One stroke copy under one fill copy, each carrying both runs.
      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts, hasLength(2));

      final stroked = texts.where(
        (t) => _spansOf(t).every((s) => s.style?.foreground != null),
      );
      expect(stroked, hasLength(1));
      for (final span in _spansOf(stroked.single)) {
        expect(span.style!.color, isNull);
      }
    });
  });

  group('built frames', () {
    testWidgets('a designed frame renders with its hole and side keys', (
      tester,
    ) async {
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'built',
          canvas: Size(1080, 1920),
          background: background,
          frames: [
            FramePlacement(
              deviceId: 'studio-custom-ios',
              variantId: 'design',
              design: FrameDesign(
                thickness: 0.03,
                cornerRadius: 0.12,
                punchHole: PunchHoleSpec(enabled: true, width: 0.18),
                power: SideButtonSpec(enabled: true),
                volume: SideButtonSpec(
                  enabled: true,
                  side: FrameSide.left,
                  count: 2,
                ),
              ),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomDeviceFrame), findsOneWidget);
    });

    testWidgets('a frameless design still draws the screenshot', (
      tester,
    ) async {
      // Thickness zero is a real setting, not an off switch: the bezel goes
      // and the rounded screen stays.
      await _pumpStage(
        tester,
        const ScreenDoc(
          id: 'frameless',
          canvas: Size(1080, 1920),
          background: background,
          frames: [
            FramePlacement(
              deviceId: 'studio-custom-ios',
              variantId: 'design',
              design: FrameDesign(thickness: 0, rimWidth: 0),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomDeviceFrame), findsOneWidget);
    });

    test('the design decides the aperture, so shadows line up with it', () {
      const design = FrameDesign(thickness: 0.05);
      final rect = CustomDeviceFrame.screenRectFor(design, 0.5);

      expect(rect.left, closeTo(0.05, 1e-9));
      expect(rect.right, closeTo(0.95, 1e-9));
      // The bezel is a fraction of width, so against height it shrinks by the
      // frame's aspect — which is what makes the border visually even.
      expect(rect.top, closeTo(0.025, 1e-9));
      expect(rect.bottom, closeTo(0.975, 1e-9));
    });

    test('a frameless design leaves the whole box to the screen', () {
      final rect = CustomDeviceFrame.screenRectFor(
        const FrameDesign(thickness: 0),
        0.5,
      );
      expect(rect, const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('matching the screenshot leaves the screen its exact shape', () {
      // The panel's "Match the screenshot" solve, checked end to end: feed it
      // an image aspect, and the *screen* the frame ends up with should have
      // that aspect — not the frame, which is bigger by its own bezel.
      double solve(double imageAspect, double t, double c) =>
          imageAspect / ((1 - 2 * t) + imageAspect * (t + c));

      for (final (imageAspect, t, c) in [
        (1080 / 2400, 0.012, 0.012),
        (1080 / 1920, 0.04, 0.02),
        (3 / 4, 0.0, 0.0),
        (1.0, 0.08, 0.0),
      ]) {
        final aspect = solve(imageAspect, t, c);
        final design = FrameDesign(thickness: t, bottomThickness: c);
        final rect = CustomDeviceFrame.screenRectFor(design, aspect);

        // screenRect is a fraction of the frame box, so the aspect it implies
        // is (w/h) scaled by the frame's own aspect.
        final screenAspect = (rect.width / rect.height) * aspect;
        expect(
          screenAspect,
          closeTo(imageAspect, 1e-9),
          reason: 'image $imageAspect with bezel $t / chin $c',
        );
      }
    });
  });
}

/// The runs one `Text.rich` copy paints, in order.
///
/// A styled caption is a single paragraph of spans rather than a widget per
/// line, so every assertion about per-run styling reads the span tree.
List<TextSpan> _spansOf(Text text) =>
    (text.textSpan! as TextSpan).children!.cast<TextSpan>();
