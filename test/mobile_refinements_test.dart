import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/editor/panels/layers_panel.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

/// The shipped frame manifest, read straight off disk — see
/// `screens_smoke_test.dart` for why this is not `rootBundle`.
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

/// Widths the editor has to survive, narrowest first.
///
/// 297 is the one that shipped broken: a desktop window dragged down that far
/// classifies as a phone, and the toolbar's fixed controls needed more than it
/// had. The rest are real phones, a phone on its side, and a desktop.
const _widths = <Size>[
  Size(297, 700),
  Size(320, 640),
  Size(360, 800),
  Size(390, 844),
  Size(844, 390),
  Size(1440, 900),
];

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mobile_refinements_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  /// Pumps the editor at [size] over a freshly seeded project, on its
  /// [screen]th screen.
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester,
    Size size, {
    int screen = 0,
  }) async {
    tester.view.physicalSize = size * 2;
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
        .first
        .subProjects
        .single
        .screens[screen]
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

  testWidgets('a screen selected further along the strip stays in view', (
    tester,
  ) async {
    // The sheet rising under a selection shrinks the canvas, and the strip is
    // laid out against its height: every screen shrank under a view offset
    // that stayed put, and the second screen slid off the left edge while its
    // tools opened for it.
    await pumpEditor(tester, const Size(390, 844), screen: 1);
    final stage = find.byKey(const ValueKey('canvas-stage'));
    final active = find.byKey(const ValueKey('active-scene'));
    await settle(tester, frames: 20);
    final before = tester.getRect(active);

    await tester.tap(active);
    await settle(tester, frames: 20);
    if (find.byTooltip('Close').evaluate().isNotEmpty) {
      // An empty device offers a picture for itself; set the offer aside.
      await tester.tap(find.byTooltip('Close').first);
      await settle(tester, frames: 20);
    }

    final view = tester.getRect(stage);
    final shown = tester.getRect(active).intersect(view);
    expect(
      shown.width,
      greaterThan(tester.getRect(active).width * 0.9),
      reason:
          'the selected screen is on screen (it was at $before, '
          'now ${tester.getRect(active)} in $view)',
    );
  });

  testWidgets('a panel opening beside the first screen leaves it whole', (
    tester,
  ) async {
    // Kept at its share of a canvas a panel had narrowed, the first screen
    // had its edge under the tool rail on the left.
    await pumpEditor(tester, const Size(1280, 800));
    final stage = find.byKey(const ValueKey('canvas-stage'));
    final active = find.byKey(const ValueKey('active-scene'));
    await settle(tester, frames: 20);
    final before = tester.getRect(stage);

    await tester.tap(active);
    await settle(tester, frames: 20);
    if (find.byTooltip('Close').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Close').first);
      await settle(tester, frames: 20);
    }

    final view = tester.getRect(stage);
    expect(view.width, lessThan(before.width), reason: 'a panel opened');
    final screen = tester.getRect(active);
    expect(screen.left, greaterThanOrEqualTo(view.left - 0.5));
    expect(screen.right, lessThanOrEqualTo(view.right + 0.5));
  });

  group('the toolbar fits', () {
    for (final size in _widths) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await pumpEditor(tester, size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the work-area brightness toggle is gone', (tester) async {
      await pumpEditor(tester, const Size(390, 844));
      // It cost a permanent slot in a bar with six controls and ~300dp to fit
      // them in, and the work area follows the app theme now.
      expect(find.byTooltip('Back to the app theme'), findsNothing);
      expect(find.byTooltip('Work area follows the dark theme'), findsNothing);
    });

    testWidgets('on a phone, Preview waits in the overflow menu', (
      tester,
    ) async {
      // History, Download and the menu fill a phone's bar; a preview button
      // besides overflowed it at 320dp.
      await pumpEditor(tester, const Size(390, 844));
      expect(find.byTooltip('Preview'), findsNothing);

      await tester.tap(find.byTooltip('Project'));
      await settle(tester);
      await tester.tap(find.text('Preview'));
      await settle(tester);

      // And once in it, the way out is on the bar.
      expect(find.byTooltip('Back to editing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and spells itself out on a desktop', (tester) async {
      await pumpEditor(tester, const Size(1440, 900));
      expect(find.text('Preview'), findsOneWidget);
    });
  });

  group('the tool strip', () {
    testWidgets('scrolls its seven tabs on a small phone, Layers first', (
      tester,
    ) async {
      await pumpEditor(tester, const Size(320, 640));

      final strip = find.byType(StudioTabStrip);
      expect(strip, findsOneWidget);

      // Seven captioned tabs do not fit 320dp, and squeezing them made the
      // captions unreadable; the strip scrolls instead.
      expect(
        find.descendant(
          of: strip,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      // Cut through a tab rather than between two, so it reads as more.
      final last = tester.getRect(
        find.descendant(of: strip, matching: find.byTooltip('Uploads')),
      );
      expect(last.left, greaterThan(320));
      final layers = tester.getRect(
        find.descendant(of: strip, matching: find.byTooltip('Layers')),
      );
      expect(
        layers.left,
        lessThan(tester.getRect(find.byTooltip('Templates')).left),
      );

      // Every tab is reachable, and named by its tooltip.
      for (final library in [
        'Layers',
        'Templates',
        'Devices',
        'Elements',
        'Text',
        'Background',
        'Uploads',
      ]) {
        expect(
          find.descendant(of: strip, matching: find.byTooltip(library)),
          findsOneWidget,
          reason: library,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('and captions every tab', (tester) async {
      await pumpEditor(tester, const Size(320, 640));
      final strip = find.byType(StudioTabStrip);
      for (final label in ['Layers', 'Templates', 'Background', 'Uploads']) {
        expect(
          find.descendant(of: strip, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('its Uploads tab holds the backgrounds as well', (
      tester,
    ) async {
      // One library for everything imported: a backdrop imported in the
      // Background tool is here, and a tap puts it behind the devices.
      final container = await pumpEditor(tester, const Size(390, 844));
      final project = container.read(projectStoreProvider).first;
      container.read(imageLibraryProvider.notifier).state = [
        LibraryImage(
          id: 'backdrop',
          fileName: 'backdrop.png',
          kind: LibraryImageKind.background,
          addedAt: DateTime(2026),
          projectId: project.id,
        ),
      ];

      // The last tab, past the end of the strip until it is scrolled to.
      final uploads = find.descendant(
        of: find.byType(StudioTabStrip),
        matching: find.byTooltip('Uploads'),
      );
      await tester.ensureVisible(uploads);
      await settle(tester);
      await tester.tap(uploads);
      await settle(tester);
      await tester.tap(find.text('Backgrounds'));
      await settle(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_LibraryTile',
        ),
      );
      await settle(tester);

      final background = container
          .read(projectStoreProvider)
          .first
          .subProjects
          .single
          .screens
          .first
          .background;
      expect(background, isA<ImageBackground>());
      expect((background as ImageBackground).path, endsWith('backdrop.png'));
    });

    testWidgets('its Layers tab lists the layers and keeps the bar', (
      tester,
    ) async {
      await pumpEditor(tester, const Size(390, 844));
      final strip = find.byType(StudioTabStrip);
      await tester.tap(
        find.descendant(of: strip, matching: find.byTooltip('Layers')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LayersPanel), findsOneWidget);
      // The bar stays, with Layers as its current tab, so any library is
      // still one tap away.
      expect(find.byType(StudioTabStrip), findsOneWidget);
      final current = tester.widget<StudioTabStrip>(
        find.byType(StudioTabStrip),
      );
      expect(current.currentIndex, 0);

      await tester.tap(
        find.descendant(
          of: find.byType(StudioTabStrip),
          matching: find.byTooltip('Templates'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LayersPanel), findsNothing);
      expect(
        tester.widget<StudioTabStrip>(find.byType(StudioTabStrip)).currentIndex,
        1,
      );
    });
  });

  group('canvas size lock', () {
    /// The painted scene, which is what the lock is about.
    Rect scene(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('active-scene')));

    Future<void> menu(WidgetTester tester, String entry) async {
      await tester.tap(find.byTooltip('Project'));
      await settle(tester);
      await tester.tap(find.text(entry));
      await settle(tester);
    }

    Future<void> openTool(WidgetTester tester, String tool) async {
      await tester.tap(
        find.descendant(
          of: find.byType(StudioTabStrip),
          matching: find.byTooltip(tool),
        ),
      );
      await settle(tester);
    }

    testWidgets('unlocked, opening the tool sheet shrinks the canvas', (
      tester,
    ) async {
      await pumpEditor(tester, const Size(390, 844));
      final before = scene(tester).size;

      await openTool(tester, 'Background');

      expect(scene(tester).size.height, lessThan(before.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('locked, the canvas holds its size and the sheet rides over', (
      tester,
    ) async {
      await pumpEditor(tester, const Size(390, 844));
      final before = scene(tester).size;

      await menu(tester, 'Lock the canvas size');
      await openTool(tester, 'Background');

      expect(
        scene(tester).size.height,
        closeTo(before.height, 0.5),
        reason: 'the scale you are judging the artwork at does not move',
      );
      await tester.tap(find.byTooltip('Project'));
      await settle(tester);
      expect(find.text('Unlock the canvas size'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lock is not offered where nothing resizes', (
      tester,
    ) async {
      // The side layouts put the panel beside the canvas, so opening it has
      // always been a reflow rather than a resize of the artwork.
      await pumpEditor(tester, const Size(1440, 900));
      await tester.tap(find.byTooltip('Project'));
      await settle(tester);
      expect(find.text('Lock the canvas size'), findsNothing);
    });
  });

  group('dragging tracks the pointer', () {
    testWidgets('the artwork moves by the fraction of the scene crossed', (
      tester,
    ) async {
      // Landscape, because that is where the painted scene and the box it sits
      // in diverge most: a portrait canvas in a wide, short workspace is
      // letterboxed hard, so a bug that divides by the wrong one is unmissable.
      final container = await pumpEditor(tester, const Size(844, 390));
      final projectId = container.read(projectStoreProvider).first.id;

      ScreenDoc current() => container
          .read(projectStoreProvider)
          .first
          .subProjects
          .single
          .screens
          .first;

      // The document is fitted and centred *inside* the SceneView's box, so
      // the box is not the artwork. This clip is.
      final sceneRect = tester.getRect(
        find
            .descendant(
              of: find.byType(SceneView),
              matching: find.byType(ClipRect),
            )
            .first,
      );
      final windowWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        sceneRect.width,
        lessThan(windowWidth * 0.5),
        reason: 'the scene really is much narrower than its window',
      );

      // The frame is what the editor opens selected on, and it sits under the
      // centre of the scene. Captions travel through the same handler.
      double offset() => current().frames.first.transform.offsetPct.dx;

      final gesture = await tester.startGesture(sceneRect.center);
      await tester.pump();
      // The first move is partly eaten getting past the touch slop, so it is
      // not the one to measure.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final mid = offset();

      const dragX = 40.0;
      await gesture.moveBy(const Offset(dragX, 0));
      await tester.pump();
      final moved = offset() - mid;
      await gesture.up();
      await settle(tester);

      expect(moved, greaterThan(0), reason: 'the drag reached the frame');

      // Offsets are a fraction of the canvas, so a pointer that crossed
      // `dragX` of the painted scene must move the artwork by exactly that
      // fraction. Measuring against the window instead — which is what it used
      // to do — made the artwork lag the pointer by whatever the difference
      // between the two happened to be, and that difference changes every time
      // the chrome does.
      expect(moved, closeTo(dragX / sceneRect.width, 0.002));
      expect(
        moved,
        isNot(closeTo(dragX / windowWidth, 0.002)),
        reason: 'and not by the fraction of the window',
      );
      expect(projectId, isNotEmpty);
    });
  });
}
