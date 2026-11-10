import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/engine/shape_painter.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

final FrameCatalog testCatalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

const _desktop = Size(1440, 900);

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// A canvas whose two edges are equal, so the legacy-height migration in
/// [shapeFromJson] is the identity and a round trip tests only what it means
/// to. The conversion itself has its own test.
const squareCanvas = Size(1000, 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shape geometry', () {
    // Every path is built into the box it is given, because that is what lets
    // one spec paint a 24px thumbnail and a 1179px export at the same
    // proportions. A path that overflowed its box would be clipped in the
    // thumbnail and would sit outside its own selection marquee on the canvas.
    test('every kind stays inside the box it is given', () {
      const box = Size(200, 120);
      for (final kind in ShapeKind.values) {
        final spec = ShapeSpec.of(kind).copyWith(
          // Two kinds have no path of their own until the user supplies one —
          // custom until something is drawn, path until something is imported.
          // Give each a triangle's worth of outline so there is something to
          // measure, in the normalised box both of them read their input from.
          points: const [Offset(0, 0), Offset(1, 0.5), Offset(0.2, 1)],
          pathData: 'M0 0 L1 0.5 L0.2 1 Z',
        );
        final bounds = ShapeGeometry.build(spec, box).getBounds();
        expect(
          bounds.left,
          greaterThanOrEqualTo(-0.5),
          reason: '${kind.name} overflows to the left',
        );
        expect(
          bounds.top,
          greaterThanOrEqualTo(-0.5),
          reason: '${kind.name} overflows above',
        );
        expect(
          bounds.right,
          lessThanOrEqualTo(box.width + 0.5),
          reason: '${kind.name} overflows to the right',
        );
        expect(
          bounds.bottom,
          lessThanOrEqualTo(box.height + 0.5),
          reason: '${kind.name} overflows below',
        );
      }
    });

    test('a polygon fills the box it is stretched into', () {
      // Inscribed in the box's ellipse rather than in a circle: a polygon in a
      // wide box has to fill it, not sit in a circle in the middle of it.
      final path = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.polygon).copyWith(sides: 4),
        const Size(300, 100),
      );
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(300, 0.5));
      expect(bounds.height, closeTo(100, 0.5));
    });

    test('sides are clamped rather than producing a degenerate path', () {
      for (final sides in [-4, 0, 2, 3, 500]) {
        final path = ShapeGeometry.build(
          ShapeSpec.of(ShapeKind.polygon).copyWith(sides: sides),
          const Size(100, 100),
        );
        expect(
          path.getBounds().isEmpty,
          isFalse,
          reason: '$sides sides produced nothing',
        );
      }
    });

    test('a rectangle rounds its corners against the shorter side', () {
      // Fully rounded, a wide rectangle is a stadium — its straight top edge is
      // gone but its full width is not.
      final path = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.rectangle).copyWith(cornerRadius: 1),
        const Size(200, 100),
      );
      expect(path.getBounds().width, closeTo(200, 0.5));
      expect(path.contains(const Offset(100, 50)), isTrue, reason: 'centre');
      expect(
        path.contains(const Offset(1, 1)),
        isFalse,
        reason: 'the corner has been rounded away',
      );
    });

    test('an ellipse contains its centre but not its box corner', () {
      final path = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.ellipse),
        const Size(100, 100),
      );
      expect(path.contains(const Offset(50, 50)), isTrue);
      expect(path.contains(const Offset(2, 2)), isFalse);
    });

    test('a wave swings the full height of its box', () {
      final path = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.wave).copyWith(sides: 3),
        const Size(300, 80),
      );
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(300, 1));
      // Sampled and smoothed, so the crests land a hair inside the extremes
      // rather than exactly on them.
      expect(bounds.height, closeTo(80, 4));
    });

    test('crests are clamped, so a wave always has at least one', () {
      for (final crests in [-2, 0, 1, 400]) {
        final path = ShapeGeometry.build(
          ShapeSpec.of(ShapeKind.wave).copyWith(sides: crests),
          const Size(200, 60),
        );
        expect(
          path.getBounds().width,
          closeTo(200, 1),
          reason: '$crests crests',
        );
      }
    });

    test('an imported outline fills exactly the box it is scaled into', () {
      // The unit box the importer writes into maps onto the shape's box, which
      // is what lets one string paint a 22px gallery tile and a 1179px export
      // at the same proportions.
      final path = ShapeGeometry.build(
        const ShapeSpec(kind: ShapeKind.path, pathData: 'M0 0L1 0L1 1L0 1Z'),
        const Size(200, 120),
      );
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(0, 0.001));
      expect(bounds.top, closeTo(0, 0.001));
      expect(bounds.width, closeTo(200, 0.001));
      expect(bounds.height, closeTo(120, 0.001));
    });

    test('an imported outline with no data paints nothing', () {
      // What every shape of this kind carries before a file has been picked,
      // and what a hand-edited document can carry forever.
      for (final data in ['', 'not a path at all']) {
        final path = ShapeGeometry.build(
          ShapeSpec(kind: ShapeKind.path, pathData: data),
          const Size(200, 120),
        );
        expect(
          path.getBounds().isEmpty,
          isTrue,
          reason: '"$data" should paint as nothing rather than throw',
        );
      }
    });

    test('the same outline builds the same path after eviction', () {
      // The unit path is cached because `shouldRepaint` is identity-based and
      // fires on every slider tick. The cache is keyed on the string, so it can
      // never go stale — this pins that clearing it changes nothing.
      const spec = ShapeSpec(kind: ShapeKind.path, pathData: 'M0 0L1 0L0.5 1Z');
      final first = ShapeGeometry.build(spec, const Size(80, 80)).getBounds();
      ShapeGeometry.debugClearPathCache();
      final second = ShapeGeometry.build(spec, const Size(80, 80)).getBounds();
      expect(second, first);
    });

    test('an outline still builds after the cache has evicted it', () {
      // The cache is bounded and drops its oldest entry, so a canvas carrying
      // more distinct outlines than it holds must still paint every one of
      // them — an eviction is a re-parse, never a blank shape.
      ShapeGeometry.debugClearPathCache();
      const first = ShapeSpec(
        kind: ShapeKind.path,
        pathData: 'M0 0L1 0L1 1L0 1Z',
      );
      final before = ShapeGeometry.build(first, const Size(50, 50)).getBounds();

      for (var i = 0; i < 80; i++) {
        ShapeGeometry.build(
          ShapeSpec(kind: ShapeKind.path, pathData: 'M0 0L1 0L0.$i 1Z'),
          const Size(50, 50),
        );
      }

      expect(
        ShapeGeometry.build(first, const Size(50, 50)).getBounds(),
        before,
        reason: 'the first outline outlived its cache entry',
      );
    });

    test('picking an imported shape respects its holes', () {
      // A square with a square counter, wound the same way, so the fill rule is
      // the only thing that decides whether the middle is ink. Precise picking
      // is what lets a tap in the hole fall through to whatever is behind it.
      const donut =
          'M0 0L1 0L1 1L0 1Z M0.25 0.25L0.75 0.25L0.75 0.75L0.25 0.75Z';
      const box = Size(100, 100);

      const holed = ShapeSpec(
        kind: ShapeKind.path,
        pathData: donut,
        evenOdd: true,
      );
      final holedPainter = ShapePainter(
        spec: holed,
        canvasWidth: 1000,
        boxSize: box,
      );
      expect(holedPainter.hitTest(const Offset(10, 10)), isTrue);
      expect(
        holedPainter.hitTest(const Offset(50, 50)),
        isFalse,
        reason: 'the counter is a hole, so a tap there is not on this shape',
      );

      final solidPainter = ShapePainter(
        spec: holed.copyWith(evenOdd: false),
        canvasWidth: 1000,
        boxSize: box,
      );
      expect(
        solidPainter.hitTest(const Offset(50, 50)),
        isTrue,
        reason: 'under the nonzero rule the same outline has no hole',
      );
    });

    test('a drawn path with fewer than two points paints nothing', () {
      // Reachable by a hand-edited project file; the canvas must not throw.
      final path = ShapeGeometry.build(
        const ShapeSpec(kind: ShapeKind.custom, points: [Offset(0.5, 0.5)]),
        const Size(100, 100),
      );
      expect(path.getBounds().isEmpty, isTrue);
    });
  });

  group('line styles', () {
    /// Total drawn length of [path], which is what a dash pattern reduces.
    double lengthOf(Path path) =>
        path.computeMetrics().fold(0.0, (sum, m) => sum + m.length);

    test('dashing removes ink and keeps the run', () {
      final line = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.line),
        const Size(400, 40),
      );
      final dashed = ShapeGeometry.dash(line, on: 10, off: 10);

      expect(dashed.computeMetrics().length, greaterThan(1));
      expect(lengthOf(dashed), lessThan(lengthOf(line)));
      expect(lengthOf(dashed), closeTo(lengthOf(line) / 2, 12));
      // The run is unchanged: a dashed line is the same line with gaps in it,
      // not a shorter one. Within one pattern period, because the tail of the
      // path can land inside a gap.
      expect(dashed.getBounds().width, closeTo(line.getBounds().width, 20));
    });

    test('it dashes a closed outline too, not just a straight line', () {
      // Which is the point of making this a stroke property rather than a line
      // kind: a dashed rectangle and a dotted circle come free.
      final rect = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.rectangle).copyWith(cornerRadius: 0),
        const Size(200, 100),
      );
      final dashed = ShapeGeometry.dash(rect, on: 8, off: 8);
      expect(dashed.computeMetrics().length, greaterThan(4));
      expect(lengthOf(dashed), lessThan(lengthOf(rect)));
    });

    test('it dashes an imported outline, which is an arbitrary path', () {
      // Nothing downstream of the geometry inspects the kind — dashing works
      // off `computeMetrics` — and this is what pins that an imported logo can
      // be given a dashed outline like any other shape.
      final outline = ShapeGeometry.build(
        const ShapeSpec(
          kind: ShapeKind.path,
          pathData: 'M0 0L1 0L1 1L0 1Z',
          strokeWidth: 0.01,
        ),
        const Size(200, 200),
      );
      final dashed = ShapeGeometry.dash(outline, on: 10, off: 10);
      expect(dashed.computeMetrics(), isNotEmpty);
      expect(dashed.computeMetrics().length, greaterThan(4));
      expect(lengthOf(dashed), lessThan(lengthOf(outline)));
    });

    test('a degenerate pattern returns the path rather than hanging', () {
      // Reachable from a hand-edited file, and the loop it guards is unbounded
      // by construction.
      final line = ShapeGeometry.build(
        ShapeSpec.of(ShapeKind.line),
        const Size(100, 20),
      );
      for (final pattern in [(0.0, 4.0), (4.0, 0.0), (-1.0, 2.0)]) {
        final out = ShapeGeometry.dash(line, on: pattern.$1, off: pattern.$2);
        expect(lengthOf(out), closeTo(lengthOf(line), 0.001));
      }
    });

    test('the style survives a round trip and defaults to solid', () {
      final styled = ShapeSpec.of(
        ShapeKind.line,
      ).copyWith(strokeStyle: StrokeStyle.dotted, dashScale: 2.5);
      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(styled))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );
      expect(back.strokeStyle, StrokeStyle.dotted);
      expect(back.dashScale, 2.5);

      // A shape written before line styles existed, and one written by a build
      // with a style this one cannot draw.
      final old = shapeToJson(styled)..remove('strokeStyle');
      expect(
        shapeFromJson(old, canvas: squareCanvas).strokeStyle,
        StrokeStyle.solid,
      );
      final newer = shapeToJson(styled)..['strokeStyle'] = 'hatched';
      expect(
        shapeFromJson(newer, canvas: squareCanvas).strokeStyle,
        StrokeStyle.solid,
      );
    });
  });

  group('shape defaults', () {
    test('open kinds arrive with a stroke, closed kinds with a fill', () {
      // A line dropped in with the closed shapes' defaults would be an
      // invisible layer with controls that appear to do nothing.
      for (final kind in [ShapeKind.line, ShapeKind.arrow, ShapeKind.wave]) {
        final spec = ShapeSpec.of(kind);
        expect(spec.isOpen, isTrue, reason: kind.name);
        expect(spec.effectiveStrokeWidth, greaterThan(0), reason: kind.name);
      }
      expect(ShapeSpec.of(ShapeKind.rectangle).isOpen, isFalse);
      expect(ShapeSpec.of(ShapeKind.star).sides, 5);
    });

    test('an open custom path keeps a visible stroke even at zero width', () {
      const drawn = ShapeSpec(kind: ShapeKind.custom, closed: false);
      expect(drawn.isOpen, isTrue);
      expect(drawn.effectiveStrokeWidth, greaterThan(0));
    });

    test('a new shape lands in front, where it can be seen', () {
      // Behind the device frame it would be hidden by the phone that covers the
      // middle of the canvas, which looks exactly like the button doing nothing.
      for (final kind in ShapeKind.values) {
        expect(ShapeSpec.of(kind).z, kStackOverEverything, reason: kind.name);
      }
    });

    test('a square shape is square on a tall canvas', () {
      // The bug this pins: width was a fraction of the canvas width and height
      // a fraction of its *height*, so 0.28 x 0.28 painted 330 x 716 on a phone
      // screenshot — every circle arrived as a tall ellipse and every square as
      // a portrait rectangle.
      const canvas = Size(1179, 2556);
      final spec = ShapeSpec.of(ShapeKind.ellipse);
      expect(spec.isSquare, isTrue);
      expect(
        spec.width * canvas.width,
        closeTo(spec.height * canvas.width, 0.01),
        reason: 'both edges are read against the same one',
      );
    });
  });

  group('serialization', () {
    test('a shape survives a round trip', () {
      const spec = ShapeSpec(
        kind: ShapeKind.star,
        center: Offset(-0.2, 0.15),
        width: 0.4,
        height: 0.3,
        rotationDeg: 33,
        fill: Color(0xFF5B5FEF),
        fillEnd: Color(0xFF06B6D4),
        gradientAngle: 210,
        strokeColor: Color(0xFFFFFFFF),
        strokeWidth: 0.01,
        opacity: 0.8,
        cornerRadius: 0.25,
        sides: 7,
        innerRatio: 0.6,
        shadow: ShapeShadow(blur: 0.05),
        z: kStackOverEverything,
      );

      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );

      expect(back.kind, ShapeKind.star);
      expect(back.center, const Offset(-0.2, 0.15));
      expect(back.width, 0.4);
      expect(back.height, 0.3);
      expect(back.rotationDeg, 33);
      expect(back.fill, const Color(0xFF5B5FEF));
      expect(back.fillEnd, const Color(0xFF06B6D4));
      expect(back.gradientAngle, 210);
      expect(back.strokeWidth, 0.01);
      expect(back.opacity, 0.8);
      expect(back.cornerRadius, 0.25);
      expect(back.sides, 7);
      expect(back.innerRatio, 0.6);
      expect(back.shadow?.blur, 0.05);
      expect(back.z, kStackOverEverything);
    });

    test('a label survives a round trip', () {
      const spec = ShapeSpec(
        kind: ShapeKind.rectangle,
        label: ShapeLabel(
          'BUS',
          fontFamily: 'Archivo Black',
          size: 0.022,
          color: Color(0xFFFF485A),
          bold: true,
          italic: true,
          allUpCase: true,
          lineHeight: 1.35,
          letterSpacing: 0.002,
          align: TextAlign.left,
          padding: 0.004,
        ),
      );
      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );
      expect(back.label?.text, 'BUS');
      expect(back.label?.fontFamily, 'Archivo Black');
      expect(back.label?.size, 0.022);
      expect(back.label?.color, const Color(0xFFFF485A));
      expect(back.label?.bold, isTrue);
      expect(back.label?.italic, isTrue);
      expect(back.label?.allUpCase, isTrue);
      expect(back.label?.lineHeight, 1.35);
      expect(back.label?.letterSpacing, 0.002);
      expect(back.label?.align, TextAlign.left);
      expect(back.label?.padding, 0.004);
    });

    test('a label set between regular and bold keeps its weight', () {
      // Gesture Volume's feature pills are Sora SemiBold: neither cut the
      // bold toggle offers.
      const spec = ShapeSpec(
        kind: ShapeKind.rectangle,
        label: ShapeLabel('Quick slider', weight: 600),
      );
      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );
      expect(back.label?.weight, 600);

      // A file written before weights existed draws bold or regular, as it did.
      final old =
          jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>;
      (old['label'] as Map<String, dynamic>).remove('weight');
      expect(shapeFromJson(old, canvas: squareCanvas).label?.weight, isNull);

      // Editing anything else keeps it; choosing a cut outright clears it.
      expect(spec.label!.copyWith(size: 0.05).weight, 600);
      expect(
        spec.label!.copyWith(bold: true, clearWeight: true).weight,
        isNull,
      );
    });

    test('a shape written before labels existed reads as unlabelled', () {
      final json = shapeToJson(ShapeSpec.of(ShapeKind.star))..remove('label');
      final back = shapeFromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        canvas: squareCanvas,
      );
      expect(back.label, isNull);
      expect(back.hasLabel, isFalse);
    });

    test('the layer name and the drawn words are two different things', () {
      // `name` is chrome and `label` is artwork. Renaming a row must not
      // retype the badge, and typing the badge must not rename the row.
      const spec = ShapeSpec(
        kind: ShapeKind.rectangle,
        name: 'Mode chip',
        label: ShapeLabel('METRO'),
      );
      expect(spec.displayName, 'Mode chip');
      expect(spec.copyWith(clearName: true).displayName, 'METRO');
      expect(spec.copyWith(clearLabel: true).displayName, 'Mode chip');
      // A shape with neither is still called after its kind.
      expect(
        spec.copyWith(clearName: true, clearLabel: true).displayName,
        'Rectangle',
      );
      // Whitespace is not words.
      expect(const ShapeLabel('   ').isEmpty, isTrue);
      expect(
        const ShapeSpec(kind: ShapeKind.star, label: ShapeLabel('  ')).hasLabel,
        isFalse,
      );
    });

    test('a drawn path survives its points', () {
      const points = [Offset(0, 0), Offset(0.5, 0.25), Offset(1, 1)];
      const spec = ShapeSpec(
        kind: ShapeKind.custom,
        points: points,
        closed: false,
      );

      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );

      expect(back.points, points);
      expect(back.closed, isFalse);
    });

    test('an imported outline survives its path data exactly', () {
      // Byte-exact, because the string is the artwork: a coordinate rewritten
      // on the way through would move the ink. This is also what carries an
      // imported logo through a backup — the data is inside `project.json`, so
      // the archive format needs no shape entry at all.
      const spec = ShapeSpec(
        kind: ShapeKind.path,
        pathData: 'M0 0L0.5 0.12345L1 1Z',
        evenOdd: true,
      );

      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
        canvas: squareCanvas,
      );

      expect(back.kind, ShapeKind.path);
      expect(back.pathData, spec.pathData);
      expect(back.evenOdd, isTrue);
    });

    test(
      'a shape written before import existed reads as having no outline',
      () {
        final json = shapeToJson(ShapeSpec.of(ShapeKind.ellipse))
          ..remove('pathData')
          ..remove('evenOdd');
        final back = shapeFromJson(json, canvas: squareCanvas);
        expect(back.pathData, isEmpty);
        expect(back.evenOdd, isFalse);
      },
    );

    test('an unknown kind degrades to a rectangle rather than throwing', () {
      // What a project written by a newer build looks like from here. One added
      // enum value must not be enough to stop a project opening.
      final json = shapeToJson(ShapeSpec.of(ShapeKind.star))
        ..['kind'] = 'dodecahedron';
      final back = shapeFromJson(json, canvas: squareCanvas);
      expect(back.kind, ShapeKind.rectangle);
      expect(back.sides, 5, reason: 'the rest of the shape is kept');
    });

    test('a screen written before shapes existed opens without any', () {
      final json = screenDocToJson(const ScreenDoc(id: 'a'))..remove('shapes');
      expect(screenDocFromJson(json).shapes, isEmpty);
    });

    test('shapes ride along on a screen round trip', () {
      final doc = ScreenDoc(
        id: 'a',
        shapes: [
          ShapeSpec.of(ShapeKind.blob),
          ShapeSpec.of(ShapeKind.line).copyWith(z: kStackBehindFrames),
        ],
      );
      final back = screenDocFromJson(
        jsonDecode(jsonEncode(screenDocToJson(doc))) as Map<String, dynamic>,
      );
      expect(back.shapes.map((s) => s.kind), [ShapeKind.blob, ShapeKind.line]);
      expect(back.shapes.last.z, kStackBehindFrames);
    });
  });

  group('the export path', () {
    /// The rasterised scene, at canvas resolution.
    ///
    /// Goes through [SceneRenderer.captureStage] rather than through the
    /// editor's own canvas, because that is the subtree an export is actually
    /// taken from: a shape that only painted in the editor would be a mockup
    /// the user cannot ship.
    Future<Uint8List> rasterise(WidgetTester tester, ScreenDoc doc) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: SceneRenderer.captureStage(
                boundaryKey: boundaryKey,
                doc: doc,
                catalog: testCatalog,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      late Uint8List bytes;
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        bytes = data!.buffer.asUint8List();
      });
      return bytes;
    }

    /// The pixel at the middle of the raster, as `#RRGGBB`.
    String centrePixel(Uint8List rgba, int width, int height) {
      final offset = ((height ~/ 2) * width + width ~/ 2) * 4;
      final hex = rgba
          .sublist(offset, offset + 3)
          .map((c) => c.toRadixString(16).padLeft(2, '0'))
          .join();
      return '#$hex';
    }

    // A small canvas: the capture is laid out at canvas / 4 and this test only
    // needs one pixel out of the middle of it.
    const canvas = Size(400, 400);
    const background = SolidBackground(Color(0xFF0000FF));
    const red = Color(0xFFFF0000);

    testWidgets('a shape in front is rasterised over the backdrop', (
      tester,
    ) async {
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        shapes: [
          ShapeSpec.of(
            ShapeKind.ellipse,
          ).copyWith(fill: red, width: 0.9, height: 0.9),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), '#ff0000');
    });

    testWidgets('a label reaches the export raster', (tester) async {
      // The shape is the same colour as the page, so the only thing that can
      // ink the middle pixel is its words. Painting the label in the editor
      // but not in `captureStage` would be a badge the user can see and
      // cannot ship.
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        shapes: const [
          ShapeSpec(
            kind: ShapeKind.rectangle,
            fill: Color(0xFF0000FF),
            width: 0.9,
            height: 0.9,
            z: kStackOverEverything,
            // Big enough that the glyph covers the centre pixel of a 100px
            // raster, and a face that is always present under `flutter test`.
            label: ShapeLabel(
              'H',
              fontFamily: 'Roboto',
              size: 0.5,
              color: red,
              bold: true,
            ),
          ),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), '#ff0000');
    });

    testWidgets('a hidden shape draws no label either', (tester) async {
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        shapes: const [
          ShapeSpec(
            kind: ShapeKind.rectangle,
            fill: Color(0xFF0000FF),
            width: 0.9,
            height: 0.9,
            hidden: true,
            z: kStackOverEverything,
            label: ShapeLabel(
              'H',
              fontFamily: 'Roboto',
              size: 0.5,
              color: red,
              bold: true,
            ),
          ),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), '#0000ff');
    });

    testWidgets('an imported outline reaches the export raster', (
      tester,
    ) async {
      // Through `captureStage` rather than through the editor's canvas,
      // because that is the subtree an export is actually taken from: an
      // imported logo that only painted in the editor would be a mockup the
      // user cannot ship. Nothing between the spec and the raster inspects the
      // kind, and this is the end-to-end proof of it.
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        shapes: const [
          ShapeSpec(
            kind: ShapeKind.path,
            pathData: 'M0 0L1 0L1 1L0 1Z',
            fill: red,
            width: 0.9,
            height: 0.9,
            z: kStackOverEverything,
          ),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), '#ff0000');
    });

    testWidgets('an imported outline with a hole lets the backdrop through', (
      tester,
    ) async {
      // The fill rule is a single bit on the spec and this is what it buys: the
      // counter of the outline is a hole all the way through to the background,
      // not a patch of the shape's own fill.
      const donut =
          'M0 0L1 0L1 1L0 1Z M0.25 0.25L0.75 0.25L0.75 0.75L0.25 0.75Z';
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        shapes: const [
          ShapeSpec(
            kind: ShapeKind.path,
            pathData: donut,
            evenOdd: true,
            fill: red,
            width: 0.9,
            height: 0.9,
            z: kStackOverEverything,
          ),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), '#0000ff');
    });

    testWidgets('a shape sent back is rasterised under the device', (
      tester,
    ) async {
      // The same shape behind the frame: the phone covers the middle of the
      // canvas, so what comes back is the device, not the shape. This is the
      // whole difference the stacking switch makes.
      final doc = ScreenDoc(
        id: 'a',
        canvas: canvas,
        background: background,
        frames: const [
          FramePlacement(
            deviceId: 'apple-iphone-16',
            variantId: '16---ultramarine',
          ),
        ],
        shapes: [
          ShapeSpec.of(
            ShapeKind.ellipse,
          ).copyWith(fill: red, width: 0.9, height: 0.9, z: kStackBehindFrames),
        ],
      );
      final bytes = await rasterise(tester, doc);
      expect(centrePixel(bytes, 100, 100), isNot('#ff0000'));
    });
  });

  group('updateShape', () {
    test('rewrites the shape at the index', () {
      final doc = ScreenDoc(
        id: 'a',
        shapes: [
          ShapeSpec.of(ShapeKind.rectangle),
          ShapeSpec.of(ShapeKind.star),
        ],
      );
      final next = doc.updateShape(1, (s) => s.copyWith(sides: 9));
      expect(next.shapes[1].sides, 9);
      expect(next.shapes[0].sides, doc.shapes[0].sides);
    });

    test('a stale index leaves the document alone', () {
      // A selection can outlive the shape it points at — deleting the last
      // shape while its controls are on screen used to be a crash.
      final doc = ScreenDoc(id: 'a', shapes: [ShapeSpec.of(ShapeKind.heart)]);
      expect(
        doc.updateShape(4, (s) => s.copyWith(sides: 9)).shapes,
        doc.shapes,
      );
      expect(doc.updateShape(-1, (s) => s).shapes, doc.shapes);
    });
  });

  group('the shapes tool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('shapes_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = _desktop * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
      );
      addTearDown(container.dispose);

      final Project project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Listing',
            targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
            initialCornerRadiusPct: 0.12,
          );
      final screenId = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .single
          .screens
          .first
          .id;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: EditorScreen(projectId: project.id, screenId: screenId),
          ),
        ),
      );
      await settle(tester);
      return container;
    }

    List<ShapeSpec> shapesOf(ProviderContainer container) => container
        .read(projectStoreProvider)
        .first
        .subProjects
        .single
        .screens
        .first
        .shapes;

    testWidgets('adds a shape from the gallery and puts it on the canvas', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      expect(shapesOf(container), isEmpty);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip('Ellipse'));
      await settle(tester);

      expect(shapesOf(container).single.kind, ShapeKind.ellipse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('canvas-stage')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ShapePainter,
          ),
        ),
        findsWidgets,
        reason: 'the shape is painted into the scene',
      );
    });

    testWidgets('the gallery offers no tile for a kind it cannot hand over', (
      tester,
    ) async {
      // Two kinds are sentinels rather than shapes — one arms the pen, one
      // opens a file dialog — and their absence from the gallery list is the
      // meaningful part. A tile for either would be a tile that cannot draw its
      // own silhouette, and tapping it would add a shape with no outline.
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);

      expect(find.byTooltip('Rectangle'), findsOneWidget);
      expect(find.byTooltip(ShapeKind.custom.label), findsNothing);
      expect(find.byTooltip(ShapeKind.path.label), findsNothing);
    });

    testWidgets('deleting the last shape goes back to the list', (
      tester,
    ) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip('Star'));
      await settle(tester);
      expect(shapesOf(container), hasLength(1));

      await tester.tap(find.text('Arrange'));
      await settle(tester);
      // The section scrolls; the delete button sits below the fold on a
      // 900dp-tall window.
      await tester.ensureVisible(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(shapesOf(container), isEmpty);
      expect(tester.takeException(), isNull);
      // Nothing is left for the Shape tool to edit, and the list is where the
      // rest of the screen is.
      expect(find.text('No shapes on this screen yet.'), findsOneWidget);
    });

    testWidgets('the pen turns a drag on the canvas into a shape', (
      tester,
    ) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.text('Draw a shape'));
      await settle(tester);

      // A triangle traced on the canvas, ending away from where it started, so
      // it stays an open stroked path.
      final canvas = tester.getRect(find.byKey(const ValueKey('active-scene')));
      final gesture = await tester.startGesture(
        canvas.center - const Offset(60, 60),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (final step in [
        const Offset(30, 20),
        const Offset(30, 20),
        const Offset(-10, 40),
        const Offset(-20, 20),
      ]) {
        await gesture.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      final drawn = shapesOf(container).single;
      expect(drawn.kind, ShapeKind.custom);
      expect(drawn.points.length, greaterThanOrEqualTo(3));
      expect(drawn.closed, isFalse);
      // Normalised into its own box, which is what makes a drawn shape movable
      // and resizable by the same controls as every other one.
      for (final p in drawn.points) {
        expect(p.dx, inInclusiveRange(-0.001, 1.001));
        expect(p.dy, inInclusiveRange(-0.001, 1.001));
      }
      expect(drawn.width, greaterThan(0));
      expect(drawn.height, greaterThan(0));

      // And it lands where it was drawn rather than at the canvas centre. The
      // stroke ran from 60px left of centre to the centre itself, so its middle
      // sits left of centre — the sign is the part that catches a normalisation
      // that has lost the offset it was supposed to keep.
      expect(drawn.center.dx, lessThan(0));
      expect(drawn.center.dx, greaterThan(-0.3));
      expect(drawn.center.dy.abs(), lessThan(0.2));
    });

    testWidgets('a line can be made dashed', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip('Line'));
      await settle(tester);
      expect(shapesOf(container).single.strokeStyle, StrokeStyle.solid);

      // Adding from the gallery lands on Style, where the line controls are.
      await tester.ensureVisible(find.text('Dashed'));
      await settle(tester);
      await tester.tap(find.text('Dashed'));
      await settle(tester);

      expect(shapesOf(container).single.strokeStyle, StrokeStyle.dashed);
      // The spacing control only exists once the stroke is broken.
      expect(find.text('Spacing'), findsOneWidget);
    });

    testWidgets('a filled shape offers no line style until it has an outline', (
      tester,
    ) async {
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip('Rectangle'));
      await settle(tester);

      // Three controls over nothing, until there is a stroke to style.
      expect(find.text('Dashed'), findsNothing);
    });

    testWidgets('a new shape lands over everything, where it can be seen', (
      tester,
    ) async {
      // Moving it down the stack is the layers list's job — see
      // `layers_test.dart`.
      final container = await pumpEditor(tester);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip('Blob'));
      await settle(tester);

      expect(shapesOf(container).single.z, kStackOverEverything);
    });
  });
}
