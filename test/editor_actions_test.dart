import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/editor/widgets/hsv_color_picker.dart';
import 'package:mockmyapp/features/editor/widgets/scene_pick.dart';
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

const _desktop = Size(1440, 900);

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('editor_actions_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  ProviderContainer seededContainer() {
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Project seedProject(ProviderContainer container) => container
      .read(projectStoreProvider.notifier)
      .createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
        initialCornerRadiusPct: 0.12,
      );

  Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = _desktop * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final container = seededContainer();
    final project = seedProject(container);
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

  /// The active screen's scene, as opposed to the other screens on the strip
  /// — which are [SceneView]s too.
  final canvasScene = find.byKey(const ValueKey('active-scene'));

  /// The frame's transform on the first screen of the seeded project.
  Transform2D frameTransform(ProviderContainer container) => container
      .read(projectStoreProvider)
      .first
      .subProjects
      .single
      .screens
      .first
      .frames
      .first
      .transform;

  List<String> screenIds(ProviderContainer container) => container
      .read(projectStoreProvider)
      .first
      .subProjects
      .single
      .screens
      .map((s) => s.id)
      .toList();

  group('canvas gestures', () {
    /// Selects the empty device by tapping it — which also offers a picture to
    /// put in it — and sets the offer aside.
    Future<void> tapToSelectDevice(WidgetTester tester) async {
      await tester.tap(canvasScene);
      await settle(tester);
      expect(find.text('Choose a screenshot'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
    }

    testWidgets('the canvas toolbar stays put as the inspector opens', (
      tester,
    ) async {
      // It was centred on the canvas between the panels, and the canvas
      // narrows whenever the inspector slides open — so it walked half a
      // panel's width across the screen on every selection, and back again.
      await pumpEditor(tester);
      final toolbar = find.byTooltip('Fit every screen');
      final stage = find.byKey(const ValueKey('canvas-stage'));
      final before = tester.getCenter(toolbar);
      final stageBefore = tester.getSize(stage).width;

      await tapToSelectDevice(tester);
      await settle(tester, frames: 20);

      expect(
        tester.getSize(stage).width,
        lessThan(stageBefore),
        reason: 'the inspector opened beside the canvas',
      );
      expect(tester.getCenter(toolbar).dx, closeTo(before.dx, 0.5));
    });

    testWidgets('tapping an empty device offers a screenshot for it', (
      tester,
    ) async {
      // The empty screen is drawn with an "add a picture" glyph; a tap on it
      // used to select the frame and nothing more.
      await pumpEditor(tester);
      await tester.tap(canvasScene);
      await settle(tester);
      expect(find.text('Choose a screenshot'), findsOneWidget);
    });

    testWidgets('dragging an empty device moves it without offering one', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      final before = frameTransform(container);
      await tester.dragFrom(
        tester.getCenter(canvasScene),
        const Offset(50, 30),
      );
      await settle(tester);
      expect(find.text('Choose a screenshot'), findsNothing);
      expect(frameTransform(container).offsetPct, isNot(before.offsetPct));
    });

    /// Pinches [centre] apart by [steps] steps of 12px per finger.
    Future<void> pinchOut(WidgetTester tester, Offset centre) async {
      final a = await tester.startGesture(centre - const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final b = await tester.startGesture(centre + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-12, 0));
        await b.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await settle(tester);
    }

    testWidgets('a pinch resizes the selection when there is one', (
      tester,
    ) async {
      // What the viewport got wrong: it listens on raw pointers, so it never
      // enters the gesture arena and zoomed the workspace on *every* pinch —
      // including the ones aimed at a frame the user had just selected.
      final container = await pumpEditor(tester);
      await tapToSelectDevice(tester);
      final before = frameTransform(container);

      await pinchOut(tester, tester.getCenter(canvasScene));

      expect(
        frameTransform(container).scale,
        greaterThan(before.scale),
        reason: 'pinching a selected frame zoomed the canvas instead',
      );
    });

    testWidgets('a pinch zooms the canvas when nothing is selected', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      final before = frameTransform(container);

      // Deselect by tapping the backdrop — a corner of the scene, well clear
      // of the frame, since tapping the frame again just re-selects it.
      // Deselect on the backdrop, and pinch there too.
      //
      // Both have to miss the frame: its own scale recogniser calls back to
      // select before it transforms, so a pinch that *starts* on the frame is
      // the frame's whatever was selected a moment earlier. The foot of the
      // canvas is below it and clear of the captions.
      final scene = tester.getRect(canvasScene);
      final backdrop = Offset(scene.center.dx, scene.bottom - 10);
      await tester.tapAt(backdrop);
      await settle(tester);

      await pinchOut(tester, backdrop);

      expect(
        frameTransform(container).scale,
        before.scale,
        reason: 'a backdrop pinch resized the artwork',
      );
    });

    testWidgets('a one-finger drag still moves the selection', (tester) async {
      // The other half: none of the above may have made the canvas read-only.
      final container = await pumpEditor(tester);
      await tapToSelectDevice(tester);
      final before = frameTransform(container);

      await tester.dragFrom(
        tester.getCenter(canvasScene),
        const Offset(50, 30),
      );
      await settle(tester);

      expect(frameTransform(container).offsetPct, isNot(before.offsetPct));
    });
  });

  group('screen strip', () {
    testWidgets('adds a screen and makes it active', (tester) async {
      final container = await pumpEditor(tester);
      expect(screenIds(container), hasLength(3));

      // At fit zoom the tile is past the right edge of the window; fitting
      // the whole set brings it into view, as it would for a user.
      await tester.tap(find.byTooltip('Fit every screen'));
      await settle(tester);
      await tester.tap(find.text('Add screen'));
      await settle(tester);

      expect(screenIds(container), hasLength(4));
      expect(
        find.bySemanticsLabel('Screen 4 of 4'),
        findsOneWidget,
        reason: 'the strip did not grow a fourth screen',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicates the active screen from its header', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byTooltip('Duplicate'));
      await settle(tester);

      expect(screenIds(container), hasLength(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves a screen right', (tester) async {
      final container = await pumpEditor(tester);
      final before = screenIds(container);

      expect(
        find.byTooltip('Move left'),
        findsNothing,
        reason: 'the first screen has nowhere to go',
      );
      await tester.tap(find.byTooltip('Move right'));
      await settle(tester);

      expect(screenIds(container), [before[1], before[0], before[2]]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deletes a screen, and hands the canvas its neighbour', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      final before = screenIds(container);

      // The editor opens on the first screen, which is the one being deleted.
      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);

      expect(screenIds(container), [before[1], before[2]]);
      // The canvas followed the deletion rather than pointing at a document
      // that no longer exists.
      expect(canvasScene, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a delete is undone by undo', (tester) async {
      final container = await pumpEditor(tester);
      final before = screenIds(container);

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);

      expect(screenIds(container), before);
    });

    testWidgets('a look at another target keeps this one\'s history', (
      tester,
    ) async {
      // Two targets this time: the history is per target, and switching away
      // and back used to clear it, so nothing done before could be undone.
      tester.view.physicalSize = _desktop * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = seededContainer();
      final project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Both stores',
            targets: const [
              (targetId: 'ios-iphone', presetId: 'iphone-6-5'),
              (targetId: 'android-phone', presetId: 'android-phone-9-16'),
            ],
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

      List<SubProject> subs() => container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects;
      Future<void> show(SubProject sub) async {
        await tester.tap(find.byTooltip('Store target'));
        await settle(tester);
        await tester.tap(find.text(sub.label).last);
        await settle(tester);
      }

      final [first, second] = subs();
      final screens = first.screens.length;

      await tester.tap(find.byTooltip('Duplicate'));
      await settle(tester);
      expect(subs().first.screens, hasLength(screens + 1));

      await show(second);
      await show(first);
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);

      expect(subs().first.screens, hasLength(screens));
      expect(
        subs().last.screens,
        hasLength(second.screens.length),
        reason: 'and the other target is untouched by it',
      );
    });

    testWidgets('tapping another screen makes it the active one', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      final ids = screenIds(container);

      await tester.tap(find.text('2'));
      await settle(tester);

      final active = tester.widget<SceneView>(canvasScene);
      expect(active.doc.id, ids[1]);
    });

    testWidgets('the last screen cannot be deleted', (tester) async {
      final container = await pumpEditor(tester);
      final store = container.read(projectStoreProvider.notifier);
      final ids = screenIds(container);
      store.deleteScreen(container.read(projectStoreProvider).first.id, ids[2]);
      store.deleteScreen(container.read(projectStoreProvider).first.id, ids[1]);
      await settle(tester);
      expect(screenIds(container), hasLength(1));

      expect(find.byTooltip('Delete'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  /// Runs [body] as if on [platform].
  ///
  /// Reset inside the body rather than through `addTearDown`, which the
  /// binding's "a foundation debug variable was changed" check runs *before*.
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('the colour picker itself', () {
    /// Pumps a bare picker, reporting what it emits.
    Future<List<Color>> pumpPicker(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      final emitted = <Color>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: Scaffold(
              body: SingleChildScrollView(
                child: HsvColorPicker(
                  color: const Color(0xFF3574F0),
                  onChanged: emitted.add,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester, frames: 4);
      return emitted;
    }

    testWidgets('emits while the saturation field is dragged', (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final emitted = await pumpPicker(tester, seededContainer());

      // The field is the first thing in the picker; drag across it.
      final field = find.byType(GestureDetector).first;
      await tester.drag(field, const Offset(40, 20));
      await settle(tester, frames: 4);

      expect(emitted, isNotEmpty, reason: 'a drag produces colours');
      expect(tester.takeException(), isNull);
    });

    testWidgets('spends the eyedropper glyph on the eyedropper alone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = seededContainer();
      container.read(scenePickProvider.notifier).attach();
      await pumpPicker(tester, container);
      await settle(tester, frames: 4);

      // The hex field used to carry `StudioIcons.colorPicker`, which is the
      // same glyph, so the row showed two identical droppers side by side —
      // one that samples the canvas and one that is decoration on a text box.
      Finder glyph(StudioIconData icon) =>
          find.byWidgetPredicate((w) => w is StudioIcon && w.icon == icon);

      expect(
        glyph(StudioIcons.dropper),
        findsOneWidget,
        reason: 'exactly one eyedropper, and it is the canvas sampler',
      );
      expect(glyph(StudioIcons.hex), findsOneWidget);
    });

    testWidgets('commits a quick-pick swatch', (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final emitted = await pumpPicker(tester, seededContainer());

      await tester.tap(find.byType(StudioSwatch).last, warnIfMissed: false);
      await settle(tester, frames: 4);

      expect(emitted, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hex field is typed into directly on a pointer device', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      // The branch turns on the *platform's* primary input, not the window
      // size, and a widget test reports Android unless told otherwise.
      await withPlatform(TargetPlatform.windows, () async {
        final emitted = await pumpPicker(tester, seededContainer());

        final field = find.widgetWithText(StudioTextField, '3574F0');
        expect(field, findsOneWidget);

        // A real caret, not a read-only preview driven by a custom keypad: the
        // pad exists to keep the *system* keyboard off the colour field, and a
        // desktop has no system keyboard to keep off it.
        expect(tester.widget<StudioTextField>(field).readOnly, isFalse);

        await tester.tap(field);
        await settle(tester, frames: 4);
        expect(
          find.text('3574F0'),
          findsOneWidget,
          reason: 'clicking into the field must not wipe the code',
        );

        await tester.enterText(field, 'aa3311');
        await settle(tester, frames: 4);

        expect(find.text('AA3311'), findsOneWidget, reason: 'upper-cased');
        expect(emitted.last, const Color(0xFFAA3311));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('opening the touch keypad leaves the code on screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await withPlatform(TargetPlatform.android, () async {
        final emitted = await pumpPicker(tester, seededContainer());

        final field = find.widgetWithText(StudioTextField, '3574F0');
        expect(tester.widget<StudioTextField>(field).readOnly, isTrue);

        await tester.tap(field);
        await settle(tester, frames: 4);

        // Opening the pad used to empty the field, so the colour you were
        // about to replace vanished the moment you touched it and a mis-tap
        // left you with nothing to go back to.
        expect(find.text('3574F0'), findsOneWidget);

        // The first key still starts a fresh code — the field holds six
        // characters, so appending to it could never do anything.
        for (final key in ['A', 'A', '3', '3', '1', '1']) {
          await tester.tap(find.widgetWithText(InkWell, key).first);
          await settle(tester, frames: 2);
        }

        expect(find.text('AA3311'), findsOneWidget);
        expect(emitted.last, const Color(0xFFAA3311));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('scene eyedropper', () {
    testWidgets('is offered while a canvas is on screen, and not before', (
      tester,
    ) async {
      final container = seededContainer();
      expect(
        container.read(scenePickProvider).available,
        isFalse,
        reason: 'nothing to sample yet',
      );

      await pumpEditor(tester);
      // A fresh container is built by pumpEditor; read through the tree's own.
      final element = tester.element(find.byType(EditorScreen));
      final scope = ProviderScope.containerOf(element);
      expect(scope.read(scenePickProvider).available, isTrue);
    });

    testWidgets('the picker shows the dropper only when one is available', (
      tester,
    ) async {
      final container = seededContainer();

      Future<void> pumpPicker() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: StudioAppTheme.dark(),
              builder: StudioLayoutScope.wrap,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: HsvColorPicker(
                    color: const Color(0xFF3574F0),
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester, frames: 4);
      }

      await pumpPicker();
      expect(find.byTooltip('Pick a colour from the canvas'), findsNothing);

      container.read(scenePickProvider.notifier).attach();
      await settle(tester, frames: 4);
      expect(find.byTooltip('Pick a colour from the canvas'), findsOneWidget);
    });

    testWidgets('the button arms the pick and dismisses the picker', (
      tester,
    ) async {
      tester.view.physicalSize = _desktop * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = seededContainer();
      container.read(scenePickProvider.notifier).attach();

      Color? applied;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showStudioSheet<void>(
                      context,
                      title: 'Colour',
                      child: SingleChildScrollView(
                        child: HsvColorPicker(
                          color: const Color(0xFF3574F0),
                          onChanged: (c) => applied = c,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester, frames: 4);

      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byType(HsvColorPicker), findsOneWidget);

      await tester.tap(find.byTooltip('Pick a colour from the canvas'));
      await settle(tester);

      expect(
        find.byType(HsvColorPicker),
        findsNothing,
        reason: 'the picker is covering the artwork, so it gets out of the way',
      );
      expect(container.read(scenePickProvider).picking, isTrue);

      // The armed callback belongs to the caller, not to the dismissed picker.
      container
          .read(scenePickProvider.notifier)
          .complete(const Color(0xFF808080));
      expect(applied, const Color(0xFF808080));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an inline picker arms without taking the page down with it', (
      tester,
    ) async {
      tester.view.physicalSize = _desktop * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = seededContainer();
      container.read(scenePickProvider.notifier).attach();

      // The solid-background fill and the screenshot stroke embed the picker
      // straight into their panel rather than opening it as a sheet. A bare
      // `maybePop` there pops the *editor* and dumps the user back in the
      // project — the panel is beside the canvas, not over it, so there is
      // nothing to dismiss.
      Color? applied;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: Scaffold(
              body: SingleChildScrollView(
                child: HsvColorPicker(
                  color: const Color(0xFF3574F0),
                  onChanged: (c) => applied = c,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester, frames: 4);

      await tester.tap(find.byTooltip('Pick a colour from the canvas'));
      await settle(tester);

      expect(
        find.byType(HsvColorPicker),
        findsOneWidget,
        reason: 'still on screen — nothing was popped',
      );
      expect(container.read(scenePickProvider).picking, isTrue);

      container
          .read(scenePickProvider.notifier)
          .complete(const Color(0xFF00FF00));
      await settle(tester, frames: 4);
      expect(applied, const Color(0xFF00FF00));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an inline picker shows the colour it was just handed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = seededContainer();
      var color = const Color(0xFF3574F0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      HsvColorPicker(
                        color: color,
                        onChanged: (c) => setState(() => color = c),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => color = const Color(0xFFAA3311)),
                        child: const Text('set'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester, frames: 4);
      expect(find.text('3574F0'), findsOneWidget);

      // A colour arriving from outside — a pick, a preset, an undo — has to
      // move the picker's own field and readout, not just the document.
      await tester.tap(find.text('set'));
      await settle(tester, frames: 4);

      expect(find.text('AA3311'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a click made straight after arming still yields a colour', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(EditorScreen)),
      );

      Color? picked;
      scope.read(scenePickProvider.notifier).begin((c) => picked = c);
      await settle(tester);
      expect(find.text('Pick a colour from the canvas'), findsOneWidget);

      // No wait before the tap on purpose. Arming the eyedropper and clicking
      // with it are one gesture, and the snapshot takes a frame plus a raster
      // round-trip — this is the click that used to be swallowed whole.
      await tester.tapAt(const Offset(700, 450));
      // Real async, because the capture is a genuine raster round-trip that a
      // fake clock never reaches.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);

      expect(picked, isNotNull);
      expect(scope.read(scenePickProvider).picking, isFalse);
      expect(container.read(projectStoreProvider), isNotEmpty);
    });
  });

  group('ScenePickController', () {
    /// The controller defers its writes to a post-frame callback, so a test has
    /// to pump for them to land.
    testWidgets('counts canvases rather than toggling a flag', (tester) async {
      final container = seededContainer();
      final pick = container.read(scenePickProvider.notifier);

      pick.attach();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isTrue);

      // A second canvas mounting before the first tears down — which is what a
      // rebuild at a new window size looks like — must not end up unavailable
      // whichever order the two callbacks run in.
      pick.attach();
      pick.detach();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isTrue);

      pick.detach();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isFalse);
    });

    testWidgets('a full-screen cover withdraws the offer', (tester) async {
      final container = seededContainer();
      final pick = container.read(scenePickProvider.notifier);

      pick.attach();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isTrue);

      pick.suppress();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isFalse);

      pick.unsuppress();
      await tester.pump();
      expect(container.read(scenePickProvider).available, isTrue);
    });

    testWidgets('delivers the picked colour and disarms', (tester) async {
      final container = seededContainer();
      final pick = container.read(scenePickProvider.notifier);
      pick.attach();
      await tester.pump();

      Color? received;
      pick.begin((c) => received = c);
      expect(container.read(scenePickProvider).picking, isTrue);

      pick.complete(const Color(0xFF123456));
      expect(received, const Color(0xFF123456));
      expect(container.read(scenePickProvider).picking, isFalse);
    });

    testWidgets('cannot be armed with no canvas to sample', (tester) async {
      final container = seededContainer();
      container.read(scenePickProvider.notifier).begin((_) {});
      expect(container.read(scenePickProvider).picking, isFalse);
    });

    testWidgets('a pick does not survive its canvas going away', (
      tester,
    ) async {
      final container = seededContainer();
      final pick = container.read(scenePickProvider.notifier);
      pick.attach();
      await tester.pump();
      pick.begin((_) {});
      expect(container.read(scenePickProvider).picking, isTrue);

      pick.detach();
      await tester.pump();
      expect(container.read(scenePickProvider).picking, isFalse);
    });
  });
}
