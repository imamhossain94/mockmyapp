import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/home/home_screen.dart';
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

/// The window sizes this app has to be right at, in logical pixels.
///
/// Each one is a real device or a real window rather than a round number: the
/// classification turns on the *shortest* side, and the case that breaks a
/// width-only rule is a phone on its side, which is wider than a small tablet.
const _phonePortrait = Size(390, 844);
const _phoneLandscape = Size(844, 390);
const _tabletPortrait = Size(834, 1112);
const _desktop = Size(1440, 900);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('responsive_layout_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
  });

  tearDown(() {
    // Best-effort: the store flushes to this directory on a debounce, and on
    // Windows the handle can still be open for a moment after the write.
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Leave it for the OS to reap.
    }
  });

  // ---------------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------------

  group('StudioLayout.fromSize', () {
    StudioFormFactor formOf(Size size) =>
        StudioLayout.fromSize(size, isTouchPrimary: true).form;

    test('splits a phone by orientation', () {
      expect(formOf(_phonePortrait), StudioFormFactor.phonePortrait);
      expect(formOf(_phoneLandscape), StudioFormFactor.phoneLandscape);
    });

    test('a phone on its side is never mistaken for a tablet', () {
      // The whole reason the classification uses the shortest side: this window
      // is 844dp wide, wider than an iPad in portrait. Width alone would dock a
      // persistent inspector onto a 390dp-tall screen.
      expect(_phoneLandscape.width, greaterThan(_tabletPortrait.width));
      expect(formOf(_phoneLandscape), StudioFormFactor.phoneLandscape);
      expect(formOf(_tabletPortrait), StudioFormFactor.tablet);
    });

    test('promotes to desktop only once all three panes fit', () {
      expect(formOf(const Size(1099, 800)), StudioFormFactor.tablet);
      expect(formOf(const Size(1100, 800)), StudioFormFactor.desktop);
      expect(formOf(_desktop), StudioFormFactor.desktop);
    });

    test('a narrowed desktop window behaves like the phone it now is', () {
      // Nothing about the platform is consulted, only the box: a desktop window
      // dragged down to 500dp gets the phone layout, which is the point.
      expect(
        StudioLayout.fromSize(const Size(500, 900), isTouchPrimary: false).form,
        StudioFormFactor.phonePortrait,
      );
    });

    test('chrome docks to the bottom only in phone portrait', () {
      expect(
        StudioLayout.fromSize(
          _phonePortrait,
          isTouchPrimary: true,
        ).docksToBottom,
        isTrue,
      );
      for (final size in [_phoneLandscape, _tabletPortrait, _desktop]) {
        final layout = StudioLayout.fromSize(size, isTouchPrimary: true);
        expect(layout.docksToBottom, isFalse, reason: '$size');
        expect(layout.hasRail, isTrue, reason: '$size');
      }
    });

    test('the screens pane needs a wide window', () {
      expect(
        StudioLayout.fromSize(
          _phoneLandscape,
          isTouchPrimary: true,
        ).canShowScreensPane,
        isFalse,
      );
      expect(
        StudioLayout.fromSize(
          _desktop,
          isTouchPrimary: false,
        ).showsScreensPaneByDefault,
        isTrue,
      );
    });

    test('chrome never takes more than half a landscape phone', () {
      final layout = StudioLayout.fromSize(
        _phoneLandscape,
        isTouchPrimary: true,
      );
      expect(
        layout.inspectorWidth + layout.railWidth,
        lessThan(_phoneLandscape.width / 2),
      );
    });

    test('columnsFor never returns zero columns', () {
      expect(StudioLayout.columnsFor(10, targetTileWidth: 200), 1);
      expect(StudioLayout.columnsFor(0, targetTileWidth: 200), 1);
      expect(StudioLayout.columnsFor(-5, targetTileWidth: 200), 1);
      expect(StudioLayout.columnsFor(900, targetTileWidth: 200), 4);
      expect(StudioLayout.columnsFor(900, targetTileWidth: 200, max: 2), 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Screens
  // ---------------------------------------------------------------------------

  /// A container seeded before anything is pumped.
  ///
  /// [ProjectStore] starts empty and fills in from disk asynchronously, so a
  /// project created in some other container would never arrive inside a
  /// fake-clock widget test. The tree has to use the container that was seeded.
  ProviderContainer seededContainer() {
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Project seedProject(ProviderContainer container, [String name = 'Listing']) =>
      container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: name,
            targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
            initialCornerRadiusPct: 0.12,
          );

  /// Pumps [child] at [size] through the same scope the real app installs.
  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    ProviderContainer container,
    Widget child,
  ) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          builder: StudioLayoutScope.wrap,
          home: child,
        ),
      ),
    );
    await settle(tester);
  }

  group('editor', () {
    /// Pumps the editor over a freshly seeded project at [size].
    Future<void> pumpEditor(WidgetTester tester, Size size) async {
      final container = seededContainer();
      final project = seedProject(container);
      await pumpAt(
        tester,
        size,
        container,
        EditorScreen(
          projectId: project.id,
          screenId: container
              .read(projectStoreProvider)
              .firstWhere((p) => p.id == project.id)
              .subProjects
              .single
              .screens
              .first
              .id,
        ),
      );
    }

    testWidgets('portrait docks the tool strip to the bottom', (tester) async {
      await pumpEditor(tester, _phonePortrait);

      expect(find.byType(StudioTabStrip), findsOneWidget);
      expect(find.byType(StudioToolRail), findsNothing);

      // And it really is at the bottom, not merely present.
      final strip = tester.getRect(find.byType(StudioTabStrip));
      expect(strip.bottom, closeTo(_phonePortrait.height, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape moves the chrome to the sides', (tester) async {
      await pumpEditor(tester, _phoneLandscape);

      expect(find.byType(StudioToolRail), findsOneWidget);
      expect(find.byType(StudioTabStrip), findsNothing);

      final rail = tester.getRect(find.byType(StudioToolRail));
      expect(rail.left, closeTo(0, 1), reason: 'rail hugs the leading edge');
      expect(
        rail.height,
        greaterThan(_phoneLandscape.height * 0.7),
        reason: 'rail runs the height of the workspace',
      );
      expect(tester.takeException(), isNull);
    });

    /// Taps a library in the rail by name.
    ///
    /// By tooltip, not by caption: below desktop the rail is glyphs only, so
    /// the name is only ever spoken by the tooltip.
    Future<void> tapLibrary(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(StudioToolRail),
          matching: find.byTooltip(label),
        ),
      );
      await settle(tester, frames: 8);
    }

    final activeScene = find.byKey(const ValueKey('active-scene'));

    testWidgets('landscape leaves the canvas most of the width', (
      tester,
    ) async {
      await pumpEditor(tester, _phoneLandscape);
      await tapLibrary(tester, 'Devices');

      final rail = tester.getRect(find.byType(StudioToolRail));
      final panel = tester.getRect(
        find.ancestor(
          of: find.text('DEVICES'),
          matching: find.byType(StudioPaneHeader),
        ),
      );

      // The point of the landscape layout: chrome takes width, of which there
      // is plenty, and gives back height, of which there is not.
      expect(rail.width + panel.width, lessThan(_phoneLandscape.width / 2));
    });

    testWidgets('desktop opens on the Templates library', (tester) async {
      await pumpEditor(tester, _desktop);

      final rail = tester.getRect(find.byType(StudioToolRail));
      expect(
        tester.getRect(find.text('TEMPLATES')).right,
        greaterThan(rail.right),
        reason: 'laid out beside the rail, not parked behind it',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet opens on the canvas, libraries closed', (tester) async {
      await pumpEditor(tester, _tabletPortrait);

      // Both panes are mounted — a closed pane keeps its child so the slide
      // never reflows it — and both are parked out of the window.
      final rail = tester.getRect(find.byType(StudioToolRail));
      expect(
        tester.getRect(find.text('TEMPLATES')).right,
        lessThanOrEqualTo(rail.right),
      );
      expect(
        tester.getRect(find.text('PROPERTIES')).left,
        greaterThanOrEqualTo(_tabletPortrait.width),
      );
      expect(activeScene, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-picking the open library slides it away', (tester) async {
      await pumpEditor(tester, _desktop);

      // A collapsed pane stays mounted — that is what stops the panel
      // reflowing on every frame of the slide — so "gone" is a question about
      // where it was laid out, not about whether it exists.
      double libraryRight() => tester.getRect(find.text('TEMPLATES')).right;
      final rail = tester.getRect(find.byType(StudioToolRail));

      expect(libraryRight(), greaterThan(rail.right));

      await tapLibrary(tester, 'Templates');
      expect(
        libraryRight(),
        lessThanOrEqualTo(rail.right),
        reason: 'slid off behind the rail rather than wiped in place',
      );

      await tapLibrary(tester, 'Templates');
      expect(libraryRight(), greaterThan(rail.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking another library swaps the panel contents', (
      tester,
    ) async {
      await pumpEditor(tester, _desktop);

      await tapLibrary(tester, 'Background');

      expect(find.text('BACKGROUND'), findsOneWidget);
      expect(find.text('TEMPLATES'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a desktop shows the library and the properties together', (
      tester,
    ) async {
      await pumpEditor(tester, _desktop);

      await tester.tap(activeScene);
      await settle(tester, frames: 8);

      expect(find.text('TEMPLATES'), findsOneWidget);
      expect(find.text('DEVICE'), findsOneWidget);
      expect(
        tester.getRect(find.text('DEVICE')).left,
        greaterThan(_desktop.width / 2),
        reason: 'properties dock on the trailing side',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tablet shows one side panel at a time', (tester) async {
      await pumpEditor(tester, _tabletPortrait);

      await tapLibrary(tester, 'Devices');
      expect(find.text('DEVICES'), findsOneWidget);

      await tester.tap(activeScene);
      await settle(tester, frames: 8);

      // The device's properties take over; the library steps aside rather
      // than squeezing the canvas from both sides.
      expect(
        tester.getRect(find.text('DEVICE')).left,
        lessThan(_tabletPortrait.width),
      );
      final rail = tester.getRect(find.byType(StudioToolRail));
      expect(
        tester.getRect(find.text('DEVICES')).right,
        lessThanOrEqualTo(rail.right),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no tab is lit while the phone sheet is tucked away', (
      tester,
    ) async {
      await pumpEditor(tester, _phonePortrait);

      StudioTabStrip strip() =>
          tester.widget<StudioTabStrip>(find.byType(StudioTabStrip));
      // The sheet opens collapsed: a filled Templates tab over nothing was a
      // promise the screen did not keep.
      expect(strip().currentIndex, -1);

      await tester.tap(
        find.descendant(
          of: find.byType(StudioTabStrip),
          matching: find.text('Templates'),
        ),
      );
      await settle(tester, frames: 8);
      expect(strip().currentIndex, isNot(-1), reason: 'open, and lit');
      expect(tester.takeException(), isNull);
    });

    testWidgets('every size lays out without overflowing', (tester) async {
      for (final size in [
        _phonePortrait,
        _phoneLandscape,
        _tabletPortrait,
        _desktop,
      ]) {
        await pumpEditor(tester, size);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('library', () {
    testWidgets('cards tile side by side on a wide window', (tester) async {
      final container = seededContainer();
      seedProject(container, 'Alpha');
      seedProject(container, 'Beta');

      await pumpAt(tester, _desktop, container, const HomeScreen());

      final alpha = tester.getRect(find.text('Alpha'));
      final beta = tester.getRect(find.text('Beta'));
      expect(alpha.top, closeTo(beta.top, 1), reason: 'same row');
      expect(alpha.left, isNot(closeTo(beta.left, 1)), reason: 'side by side');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone docks the verbs in two tiers', (tester) async {
      final container = seededContainer();
      seedProject(container, 'Alpha');

      await pumpAt(tester, _phonePortrait, container, const HomeScreen());

      Rect rectOf(String label) =>
          tester.getRect(find.widgetWithText(StudioButton, label));
      final lead = rectOf('New project');
      final generate = rectOf('Generate with AI');
      final import = rectOf('Import');
      // The call to action across the full width, the other two sharing the
      // row under it — three in one row cut "Import" to "Im…" at 390pt.
      expect(lead.bottom, lessThanOrEqualTo(generate.top));
      expect(generate.top, closeTo(import.top, 1));
      expect(lead.width, greaterThan(generate.width + import.width));
      final label = tester.renderObject<RenderParagraph>(find.text('Import'));
      expect(label.didExceedMaxLines, isFalse, reason: '"Import" is whole');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window carries the verbs in its toolbar', (
      tester,
    ) async {
      final container = seededContainer();
      seedProject(container, 'Alpha');

      await pumpAt(tester, _desktop, container, const HomeScreen());

      // No dock floating in the middle of a 1440 window.
      expect(find.byType(StudioDock), findsNothing);
      final title = tester.getCenter(find.text('MockMyApp'));
      final newProject = tester.getCenter(
        find.widgetWithText(StudioButton, 'New project'),
      );
      expect(newProject.dy, closeTo(title.dy, 4), reason: 'in the toolbar');
      expect(find.widgetWithText(StudioButton, 'Import'), findsOneWidget);
      expect(
        find.widgetWithText(StudioButton, 'Generate with AI'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the first run lays out on a phone and a desktop', (
      tester,
    ) async {
      for (final size in [_phonePortrait, _phoneLandscape, _desktop]) {
        await pumpAt(tester, size, seededContainer(), const HomeScreen());
        // The headline is the only Inter Bold in the app, and the bundled face
        // loads on the real event loop, which a fake-async pump never turns.
        // Without this the next size re-lays the headline out in the fallback
        // face's metrics and the framework's paint-only rebuild trips over
        // the difference — a test clock artefact; the app's loop is real.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('start-ai')),
          findsOneWidget,
          reason: '$size',
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('and stack on a phone', (tester) async {
      final container = seededContainer();
      seedProject(container, 'Alpha');
      seedProject(container, 'Beta');

      await pumpAt(tester, _phonePortrait, container, const HomeScreen());

      final alpha = tester.getRect(find.text('Alpha'));
      final beta = tester.getRect(find.text('Beta'));
      expect(alpha.left, closeTo(beta.left, 1), reason: 'same column');
      // Order-agnostic: the library lists newest first, so which of the two is
      // on top is not what this is about.
      expect(
        (alpha.top - beta.top).abs(),
        greaterThan(100),
        reason: 'stacked, a card apart',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('studio', () {
    testWidgets('offers every export shape from the Download menu', (
      tester,
    ) async {
      final container = seededContainer();
      final project = seedProject(container);

      await pumpAt(
        tester,
        _phonePortrait,
        container,
        EditorScreen(projectId: project.id),
      );

      await tester.tap(find.byTooltip('Download'));
      await settle(tester);

      // One screen, loose PNGs for the gallery, and one zip for handing the
      // set to anyone else — a store console or a reviewer wants one file.
      expect(find.text('This screen · PNG'), findsOneWidget);
      expect(find.textContaining('screens · PNG'), findsOneWidget);
      expect(find.textContaining('screens · ZIP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a project opens on its first screen with none named', (
      tester,
    ) async {
      final container = seededContainer();
      final project = seedProject(container);
      final first = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .first
          .screens
          .first;

      await pumpAt(
        tester,
        _desktop,
        container,
        EditorScreen(projectId: project.id),
      );

      final active = tester.widget<SceneView>(
        find.byKey(const ValueKey('active-scene')),
      );
      expect(active.doc.id, first.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every screen of the set is on the canvas at once', (
      tester,
    ) async {
      final container = seededContainer();
      final project = seedProject(container);
      final count = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == project.id)
          .subProjects
          .first
          .screens
          .length;

      await pumpAt(
        tester,
        _desktop,
        container,
        EditorScreen(projectId: project.id),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('canvas-stage')),
          matching: find.byType(SceneView),
        ),
        findsNWidgets(count),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Pumps far enough for post-frame work, pane animations *and* the project
/// store's save debounce to land.
///
/// The debounce matters: `ProjectStore` schedules a 400ms timer on every write,
/// and seeding a project is a write. A test that finishes before it fires trips
/// the binding's "a Timer is still pending" assertion, which reads like a leak
/// in the code under test and is not one.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
