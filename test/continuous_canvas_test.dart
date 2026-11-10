import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

// The continuous canvas, and the two other model additions that came with it:
// device tilt and multi-colour gradients.

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

const _canvas = Size(1290, 2796);
const _red = SolidBackground(Color(0xFFFF0000));
const _blue = SolidBackground(Color(0xFF0000FF));

ScreenDoc _screen(
  String id, {
  List<ShapeSpec> shapes = const [],
  List<FramePlacement> frames = const [],
  Background background = _red,
}) => ScreenDoc(
  id: id,
  canvas: _canvas,
  shapes: shapes,
  frames: frames,
  background: background,
);

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composeScreen', () {
    test('an ordinary set shows each screen alone', () {
      final set = [
        _screen('a', shapes: [const ShapeSpec(kind: ShapeKind.star)]),
        _screen('b'),
      ];
      final composed = composeScreen(set, 1, continuous: false);
      expect(composed.doc, same(set[1]));
      expect(composed.backgroundSlice, isNull);
    });

    test('a shape over the join carries into the next screen', () {
      final set = [
        _screen(
          'a',
          shapes: [
            const ShapeSpec(
              kind: ShapeKind.ellipse,
              center: Offset(0.45, 0.1),
              width: 0.3,
              height: 0.3,
            ),
          ],
        ),
        _screen('b'),
      ];
      final b = composeScreen(set, 1, continuous: true);
      expect(b.ownShapes, 0, reason: 'screen b owns no shapes of its own');
      expect(b.doc.shapes, hasLength(1));
      // One canvas width to the left of where it sits on its own screen.
      expect(b.doc.shapes.single.center.dx, closeTo(-0.55, 1e-9));
      expect(b.doc.shapes.single.center.dy, 0.1);
    });

    test('a shape well inside its screen stays there', () {
      final set = [
        _screen('a', shapes: [const ShapeSpec(kind: ShapeKind.star)]),
        _screen('b'),
      ];
      expect(composeScreen(set, 1, continuous: true).doc.shapes, isEmpty);
    });

    test('a device pushed across the join shows on the neighbour', () {
      const phone = FramePlacement(
        deviceId: 'apple-iphone-16',
        variantId: '16---ultramarine',
        transform: Transform2D(offsetPct: Offset(0.6, 0)),
      );
      final set = [
        _screen('a', frames: [phone]),
        _screen('b'),
      ];
      final b = composeScreen(set, 1, continuous: true);
      expect(b.ownFrames, 0);
      expect(b.doc.frames.single.transform.offsetPct.dx, closeTo(-0.4, 1e-9));
      // And stays the first screen's: nothing about screen a changed.
      expect(set.first.frames.single.transform.offsetPct.dx, 0.6);
    });

    test('guests come after the screen\'s own layers', () {
      final set = [
        _screen(
          'a',
          shapes: [
            const ShapeSpec(kind: ShapeKind.rectangle, center: Offset(0.5, 0)),
          ],
        ),
        _screen('b', shapes: [const ShapeSpec(kind: ShapeKind.star)]),
      ];
      final b = composeScreen(set, 1, continuous: true);
      expect(b.ownShapes, 1);
      expect(b.doc.shapes.first.kind, ShapeKind.star);
      expect(b.doc.shapes.last.kind, ShapeKind.rectangle);
    });

    test('one background, the first screen\'s, spreads across the set', () {
      final set = [
        _screen('a', background: _red),
        _screen('b', background: _blue),
        _screen('c', background: _blue),
      ];
      final c = composeScreen(set, 2, continuous: true);
      expect(c.doc.background, same(_red));
      expect(c.backgroundSlice, const BackgroundSlice(index: 2, count: 3));
    });

    test('a pattern that is already a panorama is not spread twice', () {
      const panorama = PatternBackground(
        style: PatternStyle.mesh,
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
        slices: 3,
      );
      final set = [
        _screen('a', background: panorama),
        _screen('b', background: panorama),
      ];
      expect(composeScreen(set, 1, continuous: true).backgroundSlice, isNull);
    });

    test('a panorama runs across the set, each screen on its own slice', () {
      // The reported bug: a continuous set gives every screen the same
      // background, so every screen stored — and showed — the same slice. The
      // artwork repeated instead of running across.
      const stored = PatternBackground(
        style: PatternStyle.dunes,
        colors: [Color(0xFF101830), Color(0xFFE0B080), Color(0xFF805030)],
        seed: 7,
        slices: 8,
        slice: 5,
      );
      final set = [
        for (final id in ['a', 'b', 'c', 'd']) _screen(id, background: stored),
      ];
      for (var i = 0; i < set.length; i++) {
        final shown =
            composeScreen(set, i, continuous: true).doc.background
                as PatternBackground;
        expect(shown.slices, 4, reason: 'laid out across exactly this set');
        expect(shown.slice, i, reason: 'screen $i shows slice $i');
        expect(shown.seed, 7, reason: 'the same artwork on every screen');
      }
    });

    test('an ordinary background ignores the panorama arithmetic', () {
      expect(panoramaAt(_red, index: 2, count: 5), same(_red));
      const single = PatternBackground(
        style: PatternStyle.mesh,
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
      );
      expect(panoramaAt(single, index: 2, count: 5), same(single));
    });
  });

  group('persistence', () {
    test('a continuous set round-trips, and old sets read as separate', () {
      final sub = SubProject(
        id: 's',
        targetId: 'ios-iphone',
        presetId: 'iphone-6-9',
        canvas: _canvas,
        screens: [_screen('a')],
        continuous: true,
      );
      final json = jsonDecode(jsonEncode(sub.toJson())) as Map<String, dynamic>;
      expect(SubProject.fromJson(json).continuous, isTrue);

      json.remove('continuous');
      expect(SubProject.fromJson(json).continuous, isFalse);
    });

    test('device tilt round-trips, and a flat device writes no tilt', () {
      const tilted = Transform2D(tiltX: 12, tiltY: -20);
      final back = transformFromJson(
        jsonDecode(jsonEncode(transformToJson(tilted))) as Map<String, dynamic>,
      );
      expect(back.tiltX, 12);
      expect(back.tiltY, -20);

      final flat = transformToJson(const Transform2D());
      expect(flat.containsKey('tiltX'), isFalse);
      expect(transformFromJson(flat).isTilted, isFalse);
    });

    test('middle colours and the radial form round-trip', () {
      const gradient = GradientBackground(
        colorOne: Color(0xFF111111),
        colorTwo: Color(0xFF999999),
        midColors: [Color(0xFF555555)],
        radial: true,
      );
      final back =
          backgroundFromJson(
                jsonDecode(jsonEncode(backgroundToJson(gradient)))
                    as Map<String, dynamic>,
              )
              as GradientBackground;
      expect(back.midColors.single.toARGB32(), 0xFF555555);
      expect(back.radial, isTrue);
      expect(back.colors, hasLength(3));
      expect(back.toGradient(), isA<RadialGradient>());
    });

    test('a two-colour gradient reads back exactly as it was written', () {
      const plain = GradientBackground(
        colorOne: Color(0xFF111111),
        colorTwo: Color(0xFF999999),
      );
      final json = backgroundToJson(plain);
      expect(json.containsKey('midColors'), isFalse);
      expect(json.containsKey('radial'), isFalse);
      final back = backgroundFromJson(json) as GradientBackground;
      expect(back.midColors, isEmpty);
      expect(back.toGradient(), isA<LinearGradient>());
    });
  });

  group('the scene', () {
    testWidgets('a guest layer is drawn but cannot be picked', (tester) async {
      final set = [
        _screen(
          'a',
          shapes: [
            const ShapeSpec(
              kind: ShapeKind.rectangle,
              center: Offset(0.45, 0),
              width: 0.3,
              height: 0.3,
            ),
          ],
        ),
        _screen('b'),
      ];
      final picks = <SceneSelection?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 129,
              height: 279.6,
              child: SceneView.composed(
                composeScreen(set, 1, continuous: true),
                catalog: testCatalog,
                onSelect: picks.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The guest sits over screen b's left edge; tap inside that part.
      final scene = tester.getRect(find.byType(SceneView));
      await tester.tapAt(scene.centerLeft + const Offset(4, 0));
      await tester.pump();

      expect(picks, isNot(contains(SceneSelection.shape(0))));
      expect(picks, contains(SceneSelection.canvas));
    });
  });

  group('in the studio', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('continuous_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    test('turning continuous off leaves each screen on its own slice', () {
      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
      );
      addTearDown(container.dispose);
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Panorama',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      SubProject sub() =>
          container.read(projectStoreProvider).first.subProjects.single;
      while (sub().screens.length < 3) {
        store.addScreen(project.id, sub().id);
      }
      const panorama = PatternBackground(
        style: PatternStyle.waves,
        colors: [Color(0xFF0B1E3A), Color(0xFF3A7BD5)],
        seed: 3,
        slices: 8,
        slice: 2,
      );
      store.updateScreen(
        project.id,
        sub().screens.first.copyWith(background: panorama),
      );

      store.setContinuous(
        project.id,
        sub().id,
        on: true,
        backgroundFrom: sub().screens.first.id,
      );
      store.setContinuous(project.id, sub().id, on: false);

      // Separate pictures again, still one artwork: slice 0, 1, 2 of three —
      // not slice 2 three times.
      final slices = [
        for (final s in sub().screens) (s.background as PatternBackground),
      ];
      expect([for (final b in slices) b.slice], [0, 1, 2]);
      expect([for (final b in slices) b.slices], [3, 3, 3]);
      expect(sub().continuous, isFalse);
    });

    testWidgets('the toolbar turns the continuous canvas on, and undo off', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
      );
      addTearDown(container.dispose);
      final project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Listing',
            targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: EditorScreen(projectId: project.id),
          ),
        ),
      );
      await settle(tester);

      bool continuous() => container
          .read(projectStoreProvider)
          .first
          .subProjects
          .single
          .continuous;
      expect(continuous(), isFalse);

      await tester.tap(
        find.byTooltip(
          'Continuous canvas: let layers and the background run across '
          'screens',
        ),
      );
      await settle(tester);
      expect(continuous(), isTrue);

      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(continuous(), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
