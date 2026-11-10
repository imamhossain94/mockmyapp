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
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';

/// Touch targets on the shapes and layers tools.
///
/// Split from `layers_test.dart` because these are all measurements at phone
/// sizes, and every one of them was wrong when the tools were built and checked
/// on a 1440dp desktop window: the reorder grip was 31 x 19dp, a small shape
/// could only be picked by landing a finger inside its own outline, and the
/// action row wrapped onto a second line on the narrowest phone — taking the
/// height off a list that had one row of it to spare.
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

/// Apple's and Material's shared floor for something you tap.
const double kTouchTarget = 44;

/// A middling phone, and the narrowest the app supports.
const _phone = Size(390, 844);
const _narrowPhone = Size(320, 568);

Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shapes_touch_test');
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
    Size window = _phone,
    List<ShapeSpec> shapes = const [],
  }) async {
    tester.view.physicalSize = window * 3;
    tester.view.devicePixelRatio = 3;
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
    final store = container.read(projectStoreProvider.notifier);
    final seeded = container
        .read(projectStoreProvider)
        .first
        .subProjects
        .single
        .screens
        .first;
    if (shapes.isNotEmpty) {
      store.updateScreen(
        container.read(projectStoreProvider).first.id,
        seeded.copyWith(shapes: shapes),
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          builder: StudioLayoutScope.wrap,
          home: EditorScreen(projectId: project.id, screenId: seeded.id),
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

  Future<void> openLayers(WidgetTester tester) async {
    // A phone has no rail: Layers is a tab on the bottom bar, or the button
    // beside a tool's title while a tool has the bar.
    await tester.tap(find.byTooltip('Layers').first);
    await settle(tester);
  }

  /// The "..." on the row whose title is [title]: the menu button sharing
  /// that row's line.
  Finder menuOnRow(WidgetTester tester, String title) {
    final y = tester.getCenter(find.text(title).first).dy;
    final menus = find.byTooltip('Layer actions');
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < menus.evaluate().length; i++) {
      final d = (tester.getCenter(menus.at(i)).dy - y).abs();
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    expect(bestDistance, lessThan(kTouchTarget / 2), reason: 'on the row');
    return menus.at(best);
  }

  group('the layers list', () {
    testWidgets('every reorder grip clears a 44dp touch target', (
      tester,
    ) async {
      // It was 31 x 19: the one control on the row you have to *hold*, and the
      // hardest thing on it to land a finger on. Every row that can be dragged
      // has one now — the shape, the captions and the device — so the rule is
      // checked across all of them rather than on the only one there used to
      // be.
      await pumpEditor(tester, shapes: [ShapeSpec.of(ShapeKind.star)]);
      await openLayers(tester);

      final grips = find.byType(ReorderableDragStartListener);
      expect(grips, findsAtLeast(3));
      for (final grip in grips.evaluate()) {
        final rect = tester.getRect(find.byWidget(grip.widget));
        expect(rect.width, greaterThanOrEqualTo(kTouchTarget));
        expect(rect.height, greaterThanOrEqualTo(kTouchTarget));
      }
    });

    testWidgets('a row keeps its menu and its name on the narrowest phone', (
      tester,
    ) async {
      // Every row now carries its own "..." beside the eye and the grip —
      // three 48dp targets out of the 280 a 320dp phone gives the list. The
      // name has to survive that, and the row must not wrap.
      await pumpEditor(
        tester,
        window: _narrowPhone,
        shapes: [ShapeSpec.of(ShapeKind.star)],
      );
      await openLayers(tester);

      final name = tester.getRect(find.text('Star').first);
      final menu = tester.getRect(menuOnRow(tester, 'Star'));
      final eye = tester.getRect(find.byTooltip('Hide layer').first);
      expect(menu.center.dy, closeTo(eye.center.dy, 1));
      // The tooltip hugs the 32dp chip; the padded target is laid out around
      // it. So the check is the slot: the "..." and the eye beside it sit a
      // whole touch target apart, and neither eats into the other.
      expect(
        (menu.center.dx - eye.center.dx).abs(),
        greaterThanOrEqualTo(kTouchTarget),
      );
      expect(name.width, greaterThan(24), reason: 'the name is still there');

      // The bar under the list is down to what adds layers, on one line.
      final add = tester.getRect(find.byTooltip('Add a shape'));
      final components = tester.getRect(find.byTooltip('Components'));
      expect(add.center.dy, closeTo(components.center.dy, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('destructive actions sit behind the overflow, not beside it', (
      tester,
    ) async {
      // Delete used to be one mis-tap from the reorder buttons you press over
      // and over.
      final container = await pumpEditor(
        tester,
        shapes: [ShapeSpec.of(ShapeKind.star)],
      );
      await openLayers(tester);

      expect(find.byTooltip('Delete layer'), findsNothing);
      await tester.tap(menuOnRow(tester, 'Star'));
      await settle(tester);
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(docOf(container).shapes, isEmpty);
    });

    testWidgets('the narrowest phone still shows a list worth reading', (
      tester,
    ) async {
      // The tool sheet is capped so a panel can never take the whole screen,
      // and at 60% of a 568dp-tall phone the cap left this list 51dp: one row,
      // of a control whose entire job is showing you the order of things.
      await pumpEditor(
        tester,
        window: _narrowPhone,
        shapes: [ShapeSpec.of(ShapeKind.blob)],
      );
      await openLayers(tester);

      final list = tester.getRect(find.byType(ReorderableListView));
      expect(
        list.height,
        greaterThanOrEqualTo(StudioSizes.listRow * 3),
        reason: 'three rows, so a drag has somewhere to go',
      );

      // And not at the cost of the canvas disappearing: the point of moving a
      // layer is watching what it does.
      final scene = tester.getRect(find.byKey(const ValueKey('active-scene')));
      expect(scene.height, greaterThan(80));

      expect(find.byTooltip('Add a shape'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the arrange controls', () {
    testWidgets('the align grid fits and stays tappable on a narrow phone', (
      tester,
    ) async {
      // Nine cells at 44dp plus their gaps is 140 wide, against the 280 a
      // 320dp phone gives the panel — but the panel is inside a scroller, so a
      // regression here would be silent rather than an overflow stripe.
      await pumpEditor(
        tester,
        window: _narrowPhone,
        shapes: [ShapeSpec.of(ShapeKind.star)],
      );
      // The shape's own tool, from its row in the list.
      await openLayers(tester);
      await tester.tap(find.text('Star').first);
      await settle(tester);
      await tester.tap(find.text('Arrange'));
      await settle(tester);

      await tester.ensureVisible(find.byTooltip('Center'));
      await settle(tester);
      final cell = tester.getRect(find.byTooltip('Center'));
      expect(cell.width, greaterThanOrEqualTo(kTouchTarget));
      expect(cell.height, greaterThanOrEqualTo(kTouchTarget));
      expect(tester.takeException(), isNull);
    });
  });

  group('picking a shape off the canvas', () {
    /// The editing canvas, as opposed to the thumbnails in the screens pane.
    final canvasScene = find.byKey(const ValueKey('active-scene'));

    testWidgets('a shape too small to aim at is caught by a finger near it', (
      tester,
    ) async {
      // 60px on a 1179-wide canvas is under 18dp once the scene is fitted to a
      // phone. Path-precise picking asks for a finger inside that circle, which
      // is asking someone to fail.
      const side = 60 / 1179;
      final container = await pumpEditor(
        tester,
        shapes: [
          ShapeSpec.of(ShapeKind.ellipse).copyWith(width: side, height: side),
        ],
      );

      final before = docOf(container).shapes.single.center;
      final scene = tester.getRect(canvasScene);

      // Start the drag 16dp off centre — outside the 18dp circle, inside a
      // fingertip — and move it.
      final gesture = await tester.startGesture(
        scene.center + const Offset(16, 0),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      final after = docOf(container).shapes.single.center;
      expect(
        after.dy,
        greaterThan(before.dy),
        reason: 'the drag reached the shape and moved it',
      );
    });

    testWidgets('a big shape is still picked by its outline, not its box', (
      tester,
    ) async {
      // The other half of the rule: precision where precision is usable, so a
      // tap in the corner of a circle's box falls through to what is behind it.
      final container = await pumpEditor(
        tester,
        shapes: [
          ShapeSpec.of(ShapeKind.ellipse).copyWith(width: 0.8, height: 0.8),
        ],
      );

      final before = docOf(container).shapes.single.center;
      final scene = tester.getRect(canvasScene);
      // The canvas is 350dp wide here, so 0.8 is 280dp across — its box corner
      // is far outside both the circle and any fingertip allowance.
      final corner = scene.center - const Offset(130, 130);

      final gesture = await tester.startGesture(corner);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      expect(
        docOf(container).shapes.single.center,
        before,
        reason: 'the corner of the box is not the shape',
      );
    });

    testWidgets('a label does not widen what a shape is grabbed by', (
      tester,
    ) async {
      // A label is a `Text`, and a `Text` is a live `RenderParagraph`. Dropped
      // into a layer whose gesture detector defers to its child, it would
      // quietly restore box-picking for every labelled shape — the exact rule
      // the test above forbids. It is `IgnorePointer`-wrapped for this.
      final container = await pumpEditor(
        tester,
        shapes: [
          ShapeSpec.of(ShapeKind.ellipse).copyWith(
            width: 0.8,
            height: 0.8,
            label: const ShapeLabel('a wide label across the whole box'),
          ),
        ],
      );

      final before = docOf(container).shapes.single.center;
      final scene = tester.getRect(canvasScene);
      final corner = scene.center - const Offset(130, 130);

      final gesture = await tester.startGesture(corner);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      expect(
        docOf(container).shapes.single.center,
        before,
        reason: 'the words are artwork, not a bigger handle',
      );
    });

    testWidgets('the grab box never reaches an export', (tester) async {
      // The allowance is a function of how big the scene is *shown*, so it must
      // not exist at all in a scene nobody can touch — otherwise a shape's
      // layout would differ between the editor and the exporter.
      const side = 60 / 1179;
      const doc = ScreenDoc(
        id: 'a',
        shapes: [ShapeSpec(kind: ShapeKind.ellipse, width: side, height: side)],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          home: SizedBox(
            width: 300,
            height: 600,
            child: SceneView(doc: doc, catalog: testCatalog),
          ),
        ),
      );
      await tester.pump();

      // No gesture detectors in a non-interactive scene, so nothing was grown
      // to be tapped.
      expect(
        find.descendant(
          of: find.byType(SceneView),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
