import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/layer_stack.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

// Editing polish: snapping, nudging, the layer clipboard, the context menu,
// locking, and the shortcut list.

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

const _badge = ShapeSpec(
  kind: ShapeKind.star,
  center: Offset(0.2, 0.1),
  width: 0.2,
  height: 0.2,
  z: kStackOverEverything,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('editing_polish_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  Future<ProviderContainer> pumpStudio(
    WidgetTester tester, {
    List<ShapeSpec> shapes = const [_badge],
  }) async {
    tester.view.physicalSize = const Size(1440, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
    );
    addTearDown(container.dispose);
    final store = container.read(projectStoreProvider.notifier);
    final project = store.createProject(
      name: 'Listing',
      targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
      initialDeviceId: 'apple-iphone-16',
      initialVariantId: '16---ultramarine',
    );
    final screen = store.byId(project.id)!.subProjects.single.screens.first;
    store.updateScreen(project.id, screen.copyWith(shapes: shapes));

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
    return container;
  }

  ScreenDoc first(ProviderContainer c) =>
      c.read(projectStoreProvider).first.subProjects.single.screens.first;

  final activeScene = find.byKey(const ValueKey('active-scene'));
  SceneView scene(WidgetTester tester) => tester.widget<SceneView>(activeScene);

  /// Drags shape 0 by [by] canvas pixels, as one gesture of several frames.
  Future<void> drag(WidgetTester tester, Offset by, {int steps = 4}) async {
    const target = SceneSelection.shape(0);
    scene(tester).onSelect!(target);
    await settle(tester, frames: 2);
    scene(tester).onTransformStart!(target);
    for (var i = 0; i < steps; i++) {
      scene(tester).onTransform!(
        target,
        ScaleUpdateDetails(focalPointDelta: by / steps.toDouble()),
      );
      await tester.pump();
    }
  }

  /// Ends the drag [drag] began, and lets the store's save debounce run out.
  Future<void> release(WidgetTester tester) async {
    scene(tester).onTransformEnd!(const SceneSelection.shape(0));
    await settle(tester);
  }

  group('snapping', () {
    testWidgets('a shape dragged near the centre lands on it, with a guide', (
      tester,
    ) async {
      final container = await pumpStudio(tester);
      final canvas = first(container).canvas;
      // From 0.2 of the width right of centre to 0.003 short of it.
      await drag(tester, Offset(-(0.2 - 0.003) * canvas.width, 0));

      expect(first(container).shapes.single.center.dx, 0);
      expect(scene(tester).guides, contains(const SnapGuide.vertical(0.5)));

      scene(tester).onTransformEnd!(const SceneSelection.shape(0));
      await settle(tester);
      expect(scene(tester).guides, isEmpty, reason: 'guides go with the drag');
    });

    testWidgets('holding Alt drags freely', (tester) async {
      final container = await pumpStudio(tester);
      final canvas = first(container).canvas;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await drag(tester, Offset(-(0.2 - 0.003) * canvas.width, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      expect(first(container).shapes.single.center.dx, closeTo(0.003, 1e-6));
      await release(tester);
    });

    testWidgets('a snap lets go once the drag carries on past it', (
      tester,
    ) async {
      final container = await pumpStudio(tester);
      final canvas = first(container).canvas;
      await drag(tester, Offset(-0.2 * canvas.width, 0));
      expect(first(container).shapes.single.center.dx, 0);
      await drag(tester, Offset(-0.1 * canvas.width, 0));
      expect(
        first(container).shapes.single.center.dx,
        closeTo(-0.1, 1e-6),
        reason: 'not stuck on the line it passed',
      );
      await release(tester);
    });
  });

  group('the keyboard', () {
    testWidgets('arrows nudge the selection a pixel, with shift ten', (
      tester,
    ) async {
      final container = await pumpStudio(tester);
      final width = first(container).canvas.width;
      scene(tester).onSelect!(const SceneSelection.shape(0));
      await settle(tester, frames: 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester, frames: 2);
      expect(
        first(container).shapes.single.center.dx,
        closeTo(0.2 + 1 / width, 1e-9),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester, frames: 2);
      expect(
        first(container).shapes.single.center.dx,
        closeTo(0.2 + 11 / width, 1e-9),
      );
      await settle(tester);
    });

    testWidgets('copy and paste make a second, offset copy', (tester) async {
      final container = await pumpStudio(tester);
      scene(tester).onSelect!(const SceneSelection.shape(0));
      await settle(tester, frames: 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);

      final shapes = first(container).shapes;
      expect(shapes, hasLength(2));
      expect(shapes.last.center, isNot(shapes.first.center));
    });

    testWidgets('duplicate copies without touching the clipboard', (
      tester,
    ) async {
      final container = await pumpStudio(tester);
      scene(tester).onSelect!(const SceneSelection.shape(0));
      await settle(tester, frames: 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(first(container).shapes, hasLength(2));
    });

    testWidgets('the last device on a screen cannot be deleted', (
      tester,
    ) async {
      final container = await pumpStudio(tester);
      scene(tester).onSelect!(SceneSelection.frameAt(0));
      await settle(tester, frames: 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);
      expect(first(container).frames, hasLength(1));
    });

    testWidgets('? lists the shortcuts', (tester) async {
      await pumpStudio(tester);
      // As a browser sends it: the key is the slash, the character a "?".
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    });
  });

  group('the context menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      scene(tester).onContextMenu!(
        const SceneSelection.shape(0),
        const Offset(600, 400),
      );
      await settle(tester);
    }

    testWidgets('sends a layer to the back of the stack', (tester) async {
      final container = await pumpStudio(tester);
      await openMenu(tester);
      await tester.tap(find.text('Send to back'));
      await settle(tester);

      final stack = LayerStack.of(first(container));
      final shapeRow = stack.rowOfShape(0)!;
      expect(
        stack.rows.indexWhere((r) => r is CanvasLayerRow),
        shapeRow + 1,
        reason: 'right in front of the backdrop',
      );
    });

    testWidgets('locks a layer so the canvas passes it by', (tester) async {
      final container = await pumpStudio(tester);
      await openMenu(tester);
      await tester.tap(find.text('Lock'));
      await settle(tester);
      expect(first(container).shapes.single.locked, isTrue);

      // It can still be unlocked from the layers list.
      await tester.tap(find.byTooltip('Layers').first);
      await settle(tester);
      await tester.tap(find.byTooltip('Unlock layer'));
      await settle(tester);
      expect(first(container).shapes.single.locked, isFalse);
    });
  });

  test('a lock survives a save and reload', () {
    final json = shapeToJson(_badge.copyWith(locked: true));
    expect(shapeFromJson(json, canvas: const Size(1290, 2796)).locked, isTrue);
    expect(shapeToJson(_badge).containsKey('locked'), isFalse);
  });
}
