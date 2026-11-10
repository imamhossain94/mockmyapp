import 'dart:convert';
import 'dart:io';
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
import 'package:mockmyapp/domain/models/layer_stack.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/editor/panels/caption_panel.dart';
import 'package:mockmyapp/features/editor/panels/frame_layout_panel.dart';
import 'package:mockmyapp/features/editor/panels/layers_panel.dart';
import 'package:mockmyapp/features/editor/panels/shape_panel.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

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

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// A screen carrying one shape per band, named so the assertions read.
ScreenDoc docWith(List<ShapeSpec> shapes) => ScreenDoc(
  id: 'a',
  frames: const [
    FramePlacement(deviceId: 'apple-iphone-16', variantId: '16---ultramarine'),
  ],
  caption: const CaptionSpec(text: 'Headline'),
  shapes: shapes,
);

ShapeSpec named(String name, int z) =>
    ShapeSpec.of(ShapeKind.rectangle).copyWith(name: name, z: z);

/// The devices front first, by id, so a restacking test reads.
List<String> devices(ScreenDoc doc) {
  final out = <String>[];
  for (final row in LayerStack.of(doc).rows) {
    if (row is FrameLayerRow && row.placement != null) {
      out.add(row.placement!.deviceId);
    }
  }
  return out;
}

/// The display list as plain strings, front first — shapes by name, everything
/// else by what it is.
List<String> render(LayerStack stack) => [
  for (final row in stack.rows)
    switch (row) {
      ShapeLayerRow(:final spec) => spec.displayName,
      CaptionsLayerRow() => '<captions>',
      FrameLayerRow() => '<frame>',
      // Nested inside its device rather than a position of its own, so it is
      // never somewhere a dragged layer can land.
      ScreenshotLayerRow() => '<screenshot>',
      CanvasLayerRow() => '<canvas>',
    },
];

/// A canvas whose two edges are equal, so the legacy-height migration in
/// [shapeFromJson] is the identity and a round trip tests only what it means
/// to. The conversion itself has its own test.
const squareCanvas = Size(1000, 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the display list', () {
    test('runs front to back, every component in one order', () {
      // At their defaults, which are spaced to reproduce the fixed spine this
      // replaced: a document written before z existed reads exactly like this.
      final stack = LayerStack.of(
        docWith([
          named('under', kStackBehindFrames),
          named('on the phone', kStackOverFrames),
          named('sticker', kStackOverEverything),
        ]),
      );

      expect(render(stack), [
        'sticker',
        '<captions>',
        'on the phone',
        '<frame>',
        '<screenshot>',
        'under',
        '<canvas>',
      ]);
    });

    test('shows every layer even on an empty screen', () {
      // The captions row holds the place the headline will go, so arranging
      // shapes around it now survives typing one later. No screenshot row: a
      // screen with no device has no picture inside one.
      expect(render(LayerStack.of(const ScreenDoc(id: 'a'))), [
        '<captions>',
        '<frame>',
        '<canvas>',
      ]);
    });

    test(
      'two shapes at one position are ordered by their place in the list',
      () {
        // Which is what makes a screen nobody has rearranged paint its shapes in
        // the order they were added.
        final stack = LayerStack.of(
          docWith([
            named('first', kStackOverEverything),
            named('second', kStackOverEverything),
          ]),
        );
        expect(render(stack).take(2), ['second', 'first']);
      },
    );

    test(
      'every component can be picked up but the backdrop and the screenshot',
      () {
        // The bug this class was rewritten for: only shapes used to be draggable,
        // so there was no way to put a caption behind a phone and no way to say
        // which of two phones was in front.
        final stack = LayerStack.of(
          docWith([named('a', kStackOverEverything)]),
        );
        expect(
          [for (final row in stack.rows) row.draggable],
          // a, captions, frame, screenshot, canvas
          [true, true, true, false, false],
        );
      },
    );

    test('the device placeholder on an empty screen cannot be dragged', () {
      final stack = LayerStack.of(const ScreenDoc(id: 'a'));
      expect(stack.rows[1], isA<FrameLayerRow>());
      expect(stack.rows[1].draggable, isFalse);
    });
  });

  group('reordering', () {
    /// Applies a move and returns the resulting display list.
    List<String> move(ScreenDoc doc, int from, int to) =>
        render(LayerStack.of(LayerStack.of(doc).reorder(from, to)!));

    test('dragging a shape past the device sends it behind', () {
      final doc = docWith([named('badge', kStackOverEverything)]);
      expect(render(LayerStack.of(doc)), [
        'badge',
        '<captions>',
        '<frame>',
        '<screenshot>',
        '<canvas>',
      ]);

      // Rows: 0 badge, 1 captions, 2 frame, 3 screenshot, 4 canvas. Drop it at
      // 3 — under the device, above the backdrop.
      expect(move(doc, 0, 3), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        'badge',
        '<canvas>',
      ]);
      expect(
        LayerStack.of(LayerStack.of(doc).reorder(0, 3)!).describeShape(0),
        'Behind the device',
      );
    });

    test('a shape dropped on a screenshot lands under the whole device', () {
      // There is no gap between a device and the picture inside it, so a drop
      // aimed at one is read as a drop below both rather than as nothing.
      final doc = docWith([named('badge', kStackOverEverything)]);
      expect(move(doc, 0, 2), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        'badge',
        '<canvas>',
      ]);
    });

    test('a shape dropped between the device and the captions lands there', () {
      final doc = docWith([named('badge', kStackBehindFrames)]);
      // Rows: 0 captions, 1 frame, 2 screenshot, 3 badge, 4 canvas. Move it to
      // 1 — above the device, still below the captions.
      expect(move(doc, 3, 1), [
        '<captions>',
        'badge',
        '<frame>',
        '<screenshot>',
        '<canvas>',
      ]);
      expect(
        LayerStack.of(LayerStack.of(doc).reorder(3, 1)!).describeShape(0),
        'Over the device',
      );
    });

    test('a layer dropped under the backdrop stops at the bottom', () {
      // Nothing goes under the backdrop, and a drag that overshoots should read
      // as the move it was reaching for rather than as nothing at all.
      final doc = docWith([named('badge', kStackOverEverything)]);
      expect(move(doc, 0, 99), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        'badge',
        '<canvas>',
      ]);
    });

    test('the captions can be sent behind the device', () {
      // Flatly impossible before: the captions were an anchor the shapes were
      // arranged around, painted over the device by the scene's own spine.
      final doc = docWith(const []);
      expect(render(LayerStack.of(doc)), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        '<canvas>',
      ]);
      expect(move(doc, 0, 3), [
        '<frame>',
        '<screenshot>',
        '<captions>',
        '<canvas>',
      ]);
    });

    test('a device can be sent behind another device', () {
      const doc = ScreenDoc(
        id: 'a',
        frames: [
          FramePlacement(deviceId: 'back', variantId: 'v'),
          FramePlacement(deviceId: 'front', variantId: 'v'),
        ],
      );
      // `frames` paints in list order until something says otherwise, so the
      // one added last starts in front.
      expect(devices(doc), ['front', 'back']);

      // Rows: 0 captions, 1 front, 2 its screenshot, 3 back, 4 its screenshot,
      // 5 canvas. Drop 'front' at 3 — below the whole of 'back'.
      final next = LayerStack.of(doc).reorder(1, 3)!;
      expect(devices(next), ['back', 'front']);
    });

    test('a device takes its screenshot with it', () {
      const doc = ScreenDoc(
        id: 'a',
        frames: [
          FramePlacement(deviceId: 'back', variantId: 'v'),
          FramePlacement(deviceId: 'front', variantId: 'v'),
        ],
      );
      expect(render(LayerStack.of(LayerStack.of(doc).reorder(1, 3)!)), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        '<frame>',
        '<screenshot>',
        '<canvas>',
      ]);
    });

    test('a reorder leaves every index alone', () {
      // The point of moving z rather than the lists: `shapes` and `frames` are
      // addressed by index from the selection, the undo stack and every
      // component instance on the screen, and a drag that renumbered them would
      // invalidate all three to say something the z already says.
      final doc = docWith([
        named('lower', kStackOverEverything),
        named('upper', kStackOverEverything),
      ]);
      // Rows: 0 upper, 1 lower. Swap them.
      final next = LayerStack.of(doc).reorder(0, 1)!;
      expect(next.shapes.map((s) => s.displayName), ['lower', 'upper']);
      expect(render(LayerStack.of(next)).take(2), ['lower', 'upper']);
      expect(next.shapes[0].z, greaterThan(next.shapes[1].z));
    });

    test('a reorder states the whole stack outright', () {
      // Every component comes out with a position of its own, so nothing after
      // a drag depends on a default or on a tie-break.
      final doc = docWith([
        named('a', kStackOverEverything),
        named('b', kStackOverEverything),
      ]);
      final next = LayerStack.of(doc).reorder(0, 1)!;
      final zs = [
        ...next.shapes.map((s) => s.z),
        ...next.frames.map((f) => f.z),
        next.captionsZ,
      ];
      expect(zs.toSet().length, zs.length, reason: 'no two share a position');
    });

    test('a move that changes nothing is refused', () {
      // So the caller does not write an identical document and push an undo
      // entry for a drag that went nowhere.
      final doc = docWith([named('a', kStackOverEverything)]);
      expect(LayerStack.of(doc).reorder(0, 0), isNull);
      // The screenshot and the backdrop cannot be dragged at all.
      expect(LayerStack.of(doc).reorder(3, 0), isNull);
      expect(LayerStack.of(doc).reorder(4, 0), isNull);
      expect(LayerStack.of(doc).reorder(99, 0), isNull);
    });

    test('a device dropped onto its own screenshot has not moved', () {
      final doc = docWith(const []);
      // Rows: 0 captions, 1 frame, 2 screenshot, 3 canvas.
      expect(LayerStack.of(doc).reorder(1, 2), isNull);
    });
  });

  group('the nudge buttons', () {
    /// One press of Move up (-1) or Move down (1) on the layer at [row].
    ScreenDoc? nudge(ScreenDoc doc, int row, int delta) {
      final stack = LayerStack.of(doc);
      final to = stack.nudgeTarget(row, delta);
      return to == null ? null : stack.reorder(row, to);
    }

    test('a shape steps one whole component at a time', () {
      final doc = docWith([named('badge', kStackOverEverything)]);
      final once = nudge(doc, 0, 1)!;
      expect(render(LayerStack.of(once)), [
        '<captions>',
        'badge',
        '<frame>',
        '<screenshot>',
        '<canvas>',
      ]);

      final twice = nudge(once, 1, 1)!;
      expect(render(LayerStack.of(twice)), [
        '<captions>',
        '<frame>',
        '<screenshot>',
        'badge',
        '<canvas>',
      ]);
    });

    test('a device steps past its own screenshot, not onto it', () {
      // Counted in components rather than rows. "Down one row" would only ever
      // swap a device with the picture inside it, which is not a move.
      final doc = docWith(const []);
      // Rows: 0 captions, 1 frame, 2 screenshot, 3 canvas.
      expect(render(LayerStack.of(nudge(doc, 1, -1)!)), [
        '<frame>',
        '<screenshot>',
        '<captions>',
        '<canvas>',
      ]);
    });

    test('there is nothing past the ends of the stack', () {
      final doc = docWith([named('badge', kStackOverEverything)]);
      final stack = LayerStack.of(doc);
      // The frontmost layer cannot go further forward…
      expect(stack.nudgeTarget(0, -1), isNull);
      // …and the backmost cannot go under the backdrop.
      expect(stack.nudgeTarget(2, 1), isNull);
    });
  });

  group('hidden layers', () {
    /// The middle pixel of the rasterised scene, as `#RRGGBB`.
    ///
    /// Through [SceneRenderer.captureStage], because hiding a layer has to
    /// reach the *export*: the artwork you were looking at when you pressed
    /// save is the artwork you expect to ship.
    Future<String> centrePixel(WidgetTester tester, ScreenDoc doc) async {
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

      late String hex;
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final rgba = data!.buffer.asUint8List();
        // The capture is laid out at canvas / 4, so a 400px canvas rasterises
        // 100 wide here.
        final offset = (50 * 100 + 50) * 4;
        hex = rgba
            .sublist(offset, offset + 3)
            .map((c) => c.toRadixString(16).padLeft(2, '0'))
            .join();
      });
      return '#$hex';
    }

    ScreenDoc withCircle({required bool hidden}) => ScreenDoc(
      id: 'a',
      canvas: const Size(400, 400),
      background: const SolidBackground(Color(0xFF0000FF)),
      shapes: [
        ShapeSpec.of(ShapeKind.ellipse).copyWith(
          fill: const Color(0xFFFF0000),
          width: 0.9,
          height: 0.9,
          hidden: hidden,
        ),
      ],
    );

    testWidgets('a hidden shape is left out of the export', (tester) async {
      expect(await centrePixel(tester, withCircle(hidden: false)), '#ff0000');
      expect(await centrePixel(tester, withCircle(hidden: true)), '#0000ff');
    });

    /// Two overlapping squares, red first in the list and blue second.
    ScreenDoc twoSquares({required int redZ, required int blueZ}) {
      ShapeSpec square(Color fill, int z) => ShapeSpec.of(
        ShapeKind.rectangle,
      ).copyWith(fill: fill, width: 0.9, height: 0.9, cornerRadius: 0, z: z);
      return ScreenDoc(
        id: 'a',
        canvas: const Size(400, 400),
        background: const SolidBackground(Color(0xFF00FF00)),
        shapes: [
          square(const Color(0xFFFF0000), redZ),
          square(const Color(0xFF0000FF), blueZ),
        ],
      );
    }

    testWidgets('the scene paints in stack order, not in list order', (
      tester,
    ) async {
      // The canvas and the layers list are one order read two ways now — the
      // scene builds its children straight off the same stack the list shows.
      // Red is first in `shapes` and blue is second, and which one you see is
      // decided by z alone.
      expect(
        await centrePixel(tester, twoSquares(redZ: 2, blueZ: 1)),
        '#ff0000',
      );
      expect(
        await centrePixel(tester, twoSquares(redZ: 1, blueZ: 2)),
        '#0000ff',
      );
    });

    test('the flag survives a round trip and defaults to visible', () {
      const spec = ShapeSpec(kind: ShapeKind.star, hidden: true);
      expect(
        shapeFromJson(shapeToJson(spec), canvas: squareCanvas).hidden,
        isTrue,
      );

      final old = shapeToJson(ShapeSpec.of(ShapeKind.star))..remove('hidden');
      expect(shapeFromJson(old, canvas: squareCanvas).hidden, isFalse);
    });
  });

  group('names', () {
    test('a shape falls back to its kind', () {
      expect(ShapeSpec.of(ShapeKind.blob).displayName, 'Blob');
      expect(
        ShapeSpec.of(ShapeKind.blob).copyWith(name: 'Splash').displayName,
        'Splash',
      );
      // A name of nothing but spaces is not a name.
      expect(
        ShapeSpec.of(ShapeKind.blob).copyWith(name: '   ').displayName,
        'Blob',
      );
    });

    test('the name survives a round trip', () {
      final spec = ShapeSpec.of(ShapeKind.star).copyWith(name: 'Badge');
      expect(
        shapeFromJson(
          jsonDecode(jsonEncode(shapeToJson(spec))) as Map<String, dynamic>,
          canvas: squareCanvas,
        ).name,
        'Badge',
      );
    });
  });

  group('migration', () {
    test('a shape written as one of three bands keeps its position', () {
      // Bands were the generation before free stacking. The z defaults are
      // spaced to land each one exactly where its band used to paint, so an old
      // document reopens looking the way it was drawn.
      for (final (band, z) in const [
        ('foreground', kStackOverEverything),
        ('overFrame', kStackOverFrames),
        ('background', kStackBehindFrames),
      ]) {
        final json = shapeToJson(ShapeSpec.of(ShapeKind.star))
          ..remove('z')
          ..['depth'] = band;
        expect(shapeFromJson(json, canvas: squareCanvas).z, z, reason: band);
      }
    });

    test('a shape written before bands existed keeps its position', () {
      // Shapes shipped one build before bands did, carrying `inFront`. Falling
      // through to the default would drop every sticker to the bottom of its
      // own screen.
      final front = shapeToJson(ShapeSpec.of(ShapeKind.star))
        ..remove('z')
        ..['inFront'] = true;
      expect(
        shapeFromJson(front, canvas: squareCanvas).z,
        kStackOverEverything,
      );

      final back = shapeToJson(ShapeSpec.of(ShapeKind.star))
        ..remove('z')
        ..['inFront'] = false;
      expect(shapeFromJson(back, canvas: squareCanvas).z, kStackBehindFrames);
    });

    test('a screen written before free stacking paints as it always did', () {
      // The whole of the migration, and there is no migration pass: the
      // defaults reproduce the spine. A document with no z anywhere in it comes
      // back as backdrop, shapes behind, device, shapes over, captions,
      // stickers — which is the order the scene used to hard-code.
      final json = screenDocToJson(
        docWith([
          named('under', kStackBehindFrames),
          named('sticker', kStackOverEverything),
        ]),
      );
      for (final shape in json['shapes'] as List) {
        (shape as Map<String, dynamic>).remove('z');
      }
      (json['shapes'] as List)[0]['depth'] = 'background';
      (json['shapes'] as List)[1]['depth'] = 'foreground';
      for (final frame in json['frames'] as List) {
        (frame as Map<String, dynamic>).remove('z');
      }
      json.remove('captionsZ');

      expect(render(LayerStack.of(screenDocFromJson(json))), [
        'sticker',
        '<captions>',
        '<frame>',
        '<screenshot>',
        'under',
        '<canvas>',
      ]);
    });

    test('a height written against the canvas height is converted', () {
      // Height used to be a fraction of the canvas *height*; it is a fraction
      // of the width now. Reading the old number straight through would reopen
      // a shape at well under half the height it was drawn on a phone canvas.
      const canvas = Size(1000, 2000);
      final legacy = shapeToJson(ShapeSpec.of(ShapeKind.rectangle))
        ..remove('heightRef')
        ..['height'] = 0.25; // a quarter of 2000 = 500px

      final back = shapeFromJson(legacy, canvas: canvas);
      expect(back.height * canvas.width, closeTo(500, 0.01));
    });

    test('a height already written against the width is left alone', () {
      const canvas = Size(1000, 2000);
      final current = shapeToJson(
        ShapeSpec.of(ShapeKind.rectangle).copyWith(height: 0.25),
      );
      expect(current['heightRef'], 'width');
      expect(shapeFromJson(current, canvas: canvas).height, 0.25);
    });

    test('a whole screen migrates its shapes against its own canvas', () {
      // The canvas lives on the screen, not on the shape, so the conversion has
      // to happen where both are in hand.
      final doc = ScreenDoc(
        id: 'a',
        canvas: const Size(1000, 2000),
        shapes: [ShapeSpec.of(ShapeKind.rectangle).copyWith(height: 0.25)],
      );
      final json = screenDocToJson(doc);
      for (final s in json['shapes'] as List) {
        (s as Map<String, dynamic>).remove('heightRef');
      }
      expect(screenDocFromJson(json).shapes.single.height, closeTo(0.5, 0.001));
    });

    test('an unknown band degrades rather than throwing', () {
      final json = shapeToJson(ShapeSpec.of(ShapeKind.star))
        ..remove('z')
        ..['depth'] = 'underneath-everything';
      expect(shapeFromJson(json, canvas: squareCanvas).z, kStackBehindFrames);
    });

    test('a position survives a round trip', () {
      final doc = docWith([named('badge', 7)]).copyWith(captionsZ: 9);
      final back = screenDocFromJson(
        jsonDecode(jsonEncode(screenDocToJson(doc))) as Map<String, dynamic>,
      );
      expect(back.shapes.single.z, 7);
      expect(back.captionsZ, 9);
      expect(back.frames.single.z, kStackFrames);
    });
  });

  group('the layers tool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('layers_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    Future<ProviderContainer> pumpEditor(
      WidgetTester tester, {
      Size window = const Size(1440, 900),
    }) async {
      tester.view.physicalSize = window * 2;
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

    ScreenDoc docOf(ProviderContainer container) => container
        .read(projectStoreProvider)
        .first
        .subProjects
        .single
        .screens
        .first;

    /// Opens the Layers tool and adds a shape of [kind] through the gallery,
    /// which lands in the new shape's own tool.
    Future<void> addShape(WidgetTester tester, String kind) async {
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add a shape'));
      await settle(tester);
      await tester.tap(find.byTooltip(kind));
      await settle(tester);
    }

    /// Opens the Layers list from wherever the inspector is.
    Future<void> openList(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      expect(find.byType(LayersPanel), findsOneWidget);
    }

    /// Opens the "..." menu on the row titled [title] — the one on that row's
    /// own line, without tapping the row, which would open its tool.
    Future<void> openMenuFor(WidgetTester tester, String title) async {
      final y = tester.getCenter(find.text(title).first).dy;
      final menus = find.byTooltip('Layer actions');
      var best = -1;
      var bestDistance = double.infinity;
      for (var i = 0; i < menus.evaluate().length; i++) {
        final d = (tester.getCenter(menus.at(i)).dy - y).abs();
        if (d < bestDistance) {
          best = i;
          bestDistance = d;
        }
      }
      expect(best, isNot(-1), reason: 'the row has a menu');
      expect(bestDistance, lessThan(24), reason: 'on the row, not another');
      await tester.tap(menus.at(best));
      await settle(tester);
    }

    testWidgets('lists every layer, not only the shapes', (tester) async {
      await pumpEditor(tester);
      await addShape(tester, 'Star');
      await openList(tester);

      // The spine of the composition, all of it addressable.
      expect(find.text('Star'), findsWidgets);
      expect(find.text('Headline'), findsWidgets);
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Background'), findsWidgets);
    });

    testWidgets('moving a shape down past the device sends it behind', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      await addShape(tester, 'Blob');
      String? where() => LayerStack.of(docOf(container)).describeShape(0);
      expect(where(), 'Over everything');

      await openList(tester);

      // Rows: blob, captions, device, screenshot, background. One press is one
      // whole component, so two puts it under the device.
      await openMenuFor(tester, 'Blob');
      await tester.tap(find.text('Move down'));
      await settle(tester);
      expect(where(), 'Over the device');

      await openMenuFor(tester, 'Blob');
      await tester.tap(find.text('Move down'));
      await settle(tester);
      expect(where(), 'Behind the device');
      expect(
        find.byType(LayersPanel),
        findsOneWidget,
        reason: 'a menu action keeps the list up',
      );
    });

    testWidgets('dragging the device grip restacks it, screenshot and all', (
      tester,
    ) async {
      // The one part the unit tests cannot reach: a device is two rows in the
      // list and one thing in the stack, so what `ReorderableListView` reports
      // for a device drag has to be reinterpreted before it means anything.
      final container = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);

      // Rows: 0 captions, 1 device, 2 screenshot, 3 background.
      expect(
        LayerStack.of(docOf(container)).rows.first,
        isA<CaptionsLayerRow>(),
      );

      final grips = find.byType(ReorderableDragStartListener);
      final deviceGrip = grips.at(1);
      final rowHeight = tester.getSize(find.text('Device')).height;

      final drag = await tester.startGesture(tester.getCenter(deviceGrip));
      // `ReorderableDragStartListener` picks up on the drag itself, with no
      // long press to wait out.
      await tester.pump(const Duration(milliseconds: 100));
      // Up and over the captions, which are the only thing in front of it.
      await drag.moveBy(Offset(0, -rowHeight * 3));
      await settle(tester);
      await drag.up();
      // Twice: the drop lands at the end of the first settle, and the store
      // saves on a debounce started by the write it makes there.
      await settle(tester);
      await settle(tester);

      final rows = LayerStack.of(docOf(container)).rows;
      expect(rows[0], isA<FrameLayerRow>());
      expect(
        rows[1],
        isA<ScreenshotLayerRow>(),
        reason: 'the picture came with it',
      );
      expect(rows[2], isA<CaptionsLayerRow>());
    });

    testWidgets('the device can be moved behind the captions', (tester) async {
      // The reported bug: only shapes could be restacked, so a device sat where
      // the scene put it and nothing in the list could move it.
      final container = await pumpEditor(tester);

      await openList(tester);

      final before = docOf(container);
      expect(
        LayerStack.of(before).rows.first,
        isA<CaptionsLayerRow>(),
        reason: 'the captions start in front',
      );

      await openMenuFor(tester, 'Device');
      await tester.tap(find.text('Move up'));
      await settle(tester);

      expect(LayerStack.of(docOf(container)).rows.first, isA<FrameLayerRow>());
    });

    testWidgets('a device can be deleted from the overflow menu', (
      tester,
    ) async {
      // The reported bug: the menu was gated on a shape being selected, so a
      // device could be selected and restacked but never deleted.
      final container = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);

      // A second device, so the screen is not down to its last one.
      await openMenuFor(tester, 'Device');
      await tester.tap(find.text('Duplicate'));
      await settle(tester);
      expect(docOf(container).frames.length, 2);

      await openMenuFor(tester, 'Device 2');
      expect(find.text('Delete device'), findsOneWidget);
      await tester.tap(find.text('Delete device'));
      await settle(tester);

      expect(docOf(container).frames.length, 1);
    });

    testWidgets('the last device offers Delete but will not do it', (
      tester,
    ) async {
      // A screen keeps its last device. The item stays visible and disabled
      // rather than vanishing, which would read as "devices cannot be deleted".
      final container = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      expect(docOf(container).frames.length, 1);

      await openMenuFor(tester, 'Device');
      expect(find.text('Delete device'), findsOneWidget);
      await tester.tap(find.text('Delete device'));
      await settle(tester);

      expect(docOf(container).frames.length, 1, reason: 'refused');
    });

    testWidgets('a caption can be deleted from the overflow menu', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      expect(docOf(container).caption, isNotNull);

      await openMenuFor(tester, 'Headline');
      // A caption has no name to edit and nowhere for a copy to go.
      expect(find.text('Rename…'), findsNothing);
      expect(find.text('Duplicate'), findsNothing);
      await tester.tap(find.text('Delete headline'));
      await settle(tester);

      expect(docOf(container).caption, isNull);
    });

    testWidgets('the backdrop offers nothing to delete', (tester) async {
      // It is the artboard itself, not a layer you can take off the screen —
      // and with nothing to move either, its row has no menu at all.
      await pumpEditor(tester);
      await openList(tester);

      final backdropRow = find.ancestor(
        of: find.text('Background').first,
        matching: find.byType(StudioListRow),
      );
      expect(
        find.descendant(
          of: backdropRow,
          matching: find.byTooltip('Layer actions'),
        ),
        findsNothing,
      );
    });

    testWidgets('hiding a layer takes it off the canvas but keeps the row', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      await addShape(tester, 'Star');
      await openList(tester);
      await tester.tap(find.byTooltip('Hide layer').first);
      await settle(tester);

      expect(docOf(container).shapes.single.hidden, isTrue);
      expect(find.text('Star'), findsWidgets, reason: 'the row stays');
      expect(find.byTooltip('Show layer'), findsWidgets);
    });

    testWidgets('the device can be hidden from the list', (tester) async {
      // Distinct from the frameless *style* on the Frame tool, which drops the
      // bezel and keeps the screenshot. This takes the whole layer off.
      final container = await pumpEditor(tester);
      expect(docOf(container).frames.single.hidden, isFalse);

      await openList(tester);

      // The Device row's own eye, not the caption's above it.
      final deviceRow = find.ancestor(
        of: find.text('Device'),
        matching: find.byType(StudioListRow),
      );
      await tester.tap(
        find.descendant(of: deviceRow, matching: find.byTooltip('Hide layer')),
      );
      await settle(tester);

      final frame = docOf(container).frames.single;
      expect(frame.hidden, isTrue);
      expect(
        frame.frameHidden,
        isFalse,
        reason: 'the frameless style is a different setting and is untouched',
      );
      expect(find.text('Hidden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hidden device is left out of the export', (tester) async {
      const doc = ScreenDoc(
        id: 'a',
        canvas: Size(400, 400),
        background: SolidBackground(Color(0xFF0000FF)),
        frames: [
          FramePlacement(
            deviceId: 'apple-iphone-16',
            variantId: '16---ultramarine',
            hidden: true,
          ),
        ],
      );

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

      late String hex;
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final rgba = data!.buffer.asUint8List();
        final offset = (50 * 100 + 50) * 4;
        hex = rgba
            .sublist(offset, offset + 3)
            .map((c) => c.toRadixString(16).padLeft(2, '0'))
            .join();
      });

      // The backdrop, where the phone would have been.
      expect(hex, '0000ff');
    });

    testWidgets('a caption can be hidden from the list', (tester) async {
      final container = await pumpEditor(tester);
      expect(docOf(container).caption?.enabled, isTrue);

      await tester.tap(find.byTooltip('Layers'));
      await settle(tester);
      await tester.tap(find.byTooltip('Hide layer').first);
      await settle(tester);

      expect(docOf(container).caption?.enabled, isFalse);
    });

    testWidgets('renaming a layer keeps its kind on the row', (tester) async {
      final container = await pumpEditor(tester);
      await addShape(tester, 'Star');
      await openList(tester);
      await openMenuFor(tester, 'Star');
      await tester.tap(find.text('Rename…'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Award badge');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(docOf(container).shapes.single.name, 'Award badge');
      expect(find.text('Award badge'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget, reason: 'the kind, underneath');
    });

    testWidgets('the size fields read and accept canvas pixels', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      await addShape(tester, 'Rectangle');

      await tester.tap(find.text('Arrange'));
      await settle(tester);

      final canvas = docOf(container).canvas;
      final drawn = (docOf(container).shapes.single.width * canvas.width)
          .round();
      expect(
        find.text('$drawn'),
        findsWidgets,
        reason: 'the readout is in pixels, not a percentage',
      );

      // Type a size in, the way the complaint asked for.
      await tester.tap(find.byType(StudioNumericWell).first);
      await settle(tester);
      await tester.enterText(find.byType(TextField), '320');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(
        docOf(container).shapes.single.width * canvas.width,
        closeTo(320, 1),
      );
    });

    testWidgets('position reads and accepts canvas pixels', (tester) async {
      final container = await pumpEditor(tester);
      await addShape(tester, 'Rectangle');

      await tester.tap(find.text('Arrange'));
      await settle(tester);

      final canvas = docOf(container).canvas;
      // A new shape is centred, so X reads half the canvas width.
      expect(find.text('${(canvas.width / 2).round()}'), findsWidgets);

      await tester.ensureVisible(find.text('X'));
      await settle(tester);
      // The X row's readout is the first well after the size ones.
      final wells = find.byType(StudioNumericWell);
      await tester.tap(wells.at(2));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '200');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      final centreX =
          (0.5 + docOf(container).shapes.single.center.dx) * canvas.width;
      expect(centreX, closeTo(200, 1));
    });

    testWidgets('the align grid puts a shape flush against an edge', (
      tester,
    ) async {
      // Flush, not centred on the corner: an align tool that hung half the
      // shape off the canvas would be a positioning tool nobody asked for.
      final container = await pumpEditor(tester);
      await addShape(tester, 'Rectangle');

      await tester.tap(find.text('Arrange'));
      await settle(tester);
      await tester.ensureVisible(find.byTooltip('Left'));
      await settle(tester);
      await tester.tap(find.byTooltip('Left'));
      await settle(tester);

      final shape = docOf(container).shapes.single;
      final canvas = docOf(container).canvas;
      final leftEdge =
          (0.5 + shape.center.dx) * canvas.width -
          shape.width * canvas.width / 2;
      expect(leftEdge, closeTo(0, 1));
      // Vertically untouched — "Left" is one axis, not two.
      expect(shape.center.dy, 0);
    });

    testWidgets('a quarter turn lands exactly on 90 degrees', (tester) async {
      // Hitting exactly 90 on a slider spanning 360 is luck, and quarter turns
      // are most of what rotation is used for.
      final container = await pumpEditor(tester);
      await addShape(tester, 'Rectangle');

      await tester.tap(find.text('Arrange'));
      await settle(tester);
      await tester.ensureVisible(find.text('+90°'));
      await settle(tester);
      await tester.tap(find.text('+90°'));
      await settle(tester);
      expect(docOf(container).shapes.single.rotationDeg, 90);

      await tester.tap(find.text('+90°'));
      await settle(tester);
      expect(docOf(container).shapes.single.rotationDeg, 180);

      // And past the end of the slider it wraps rather than piling up outside
      // its own range.
      await tester.tap(find.text('+90°'));
      await settle(tester);
      expect(docOf(container).shapes.single.rotationDeg, -90);
    });

    testWidgets('the layers sheet holds the list and nothing else', (
      tester,
    ) async {
      // It used to carry the selected shape's Style and Arrange as two more
      // sections, which made the list one tab of a shape editor.
      await pumpEditor(tester);
      await addShape(tester, 'Star');
      await openList(tester);

      expect(find.text('Style'), findsNothing);
      expect(find.text('Arrange'), findsNothing);
      expect(find.byType(ShapePanel), findsNothing);
    });

    testWidgets("tapping a row opens that layer's own tool", (tester) async {
      // A row is the layer, so a tap on it does what a tap on the layer does
      // on the canvas — the device's row brings up the Device tool.
      await pumpEditor(tester);
      await addShape(tester, 'Star');

      await openList(tester);
      await tester.tap(find.text('Device'));
      await settle(tester);
      expect(find.byType(FrameLayoutPanel), findsOneWidget);
      expect(find.byType(LayersPanel), findsNothing);

      await openList(tester);
      await tester.tap(find.text('Headline').first);
      await settle(tester);
      expect(find.byType(CaptionPanel), findsOneWidget);

      await openList(tester);
      await tester.tap(find.text('Star').first);
      await settle(tester);
      expect(find.byType(ShapePanel), findsOneWidget);
      expect(find.byType(LayersPanel), findsNothing);
    });

    testWidgets('a new shape lands in its own tool, on its paint', (
      tester,
    ) async {
      await pumpEditor(tester);
      await addShape(tester, 'Star');

      expect(find.byType(ShapePanel), findsOneWidget);
      expect(find.byType(LayersPanel), findsNothing);
      // Style's colour controls, not Arrange's panels.
      expect(find.text('Stacking'), findsNothing);
    });

    testWidgets('the shape tool goes back to the list', (tester) async {
      await pumpEditor(tester);
      await addShape(tester, 'Star');

      await tester.tap(find.text('All layers'));
      await settle(tester);
      expect(find.byType(LayersPanel), findsOneWidget);
      expect(find.byType(ShapePanel), findsNothing);
    });
  });
}
