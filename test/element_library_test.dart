import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/svg_path.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

// The Elements library: the generated element set and the Lucide icons.

final FrameCatalog testCatalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

ElementCatalog readCatalog() => ElementCatalog.fromJson(
  elements:
      jsonDecode(File('assets/elements/elements.json').readAsStringSync())
          as Map<String, dynamic>,
  icons:
      jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = readCatalog();

  group('the element set', () {
    test('is a real library, filed under categories that exist', () {
      expect(catalog.elements.length, greaterThanOrEqualTo(120));
      final ids = catalog.categories.map((c) => c.id).toSet();
      for (final e in catalog.elements) {
        expect(ids, contains(e.category), reason: e.id);
      }
      for (final c in catalog.categories) {
        expect(catalog.elementsIn(c.id), isNotEmpty, reason: c.id);
      }
    });

    test('has no two elements with one id', () {
      final ids = catalog.elements.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every drawing parses, and every kind is one the app draws', () {
      for (final e in catalog.elements) {
        if (e.kind == null) {
          expect(
            parseUnitPath(e.pathData!, evenOdd: e.evenOdd),
            isNotNull,
            reason: '${e.id} has a path the canvas cannot read',
          );
        }
        expect(e.kind != null || e.pathData != null, isTrue, reason: e.id);
      }
    });

    test('line art is stroked in its own box, not filled', () {
      final arc = catalog.elements.firstWhere((e) => e.id == 'arc');
      final shape = arc.toShape();
      expect(shape.strokeInBox, isTrue);
      expect(shape.fill.a, 0);
      expect(shape.strokeWidth, greaterThan(0));
    });

    test('an award keeps its words, in the ink of its laurels', () {
      final award = catalog.elements.firstWhere((e) => e.category == 'awards');
      final shape = award.toShape(ink: const Color(0xFFFFD166));
      expect(shape.hasLabel, isTrue);
      expect(shape.label!.color.toARGB32(), 0xFFFFD166);
    });

    test('words on a filled element take a colour that reads on it', () {
      final pill = catalog.elements.firstWhere((e) => e.id == 'feature-pill');
      final onWhite = pill.toShape();
      expect(onWhite.label!.color.computeLuminance(), lessThan(0.2));
    });

    test('an element lands at its drawn proportions', () {
      for (final e in catalog.elements.take(40)) {
        final s = e.toShape();
        expect(s.width / s.height, closeTo(e.aspect, 0.01), reason: e.id);
      }
    });
  });

  group('the icons', () {
    test('are all there, and every one parses', () {
      expect(catalog.icons.length, greaterThan(1500));
      for (final icon in catalog.icons) {
        expect(
          parseUnitPath(icon.pathData),
          isNotNull,
          reason: '${icon.name} has a path the canvas cannot read',
        );
      }
    });

    test('stay on their own grid', () {
      // Each icon is several SVG elements joined into one path. A joined
      // element whose first `m` was left relative lands somewhere off the
      // icon — the tick of shield-check drawn below the shield — and the one
      // symptom every such case shares is ink outside the 24-unit box.
      for (final icon in catalog.icons) {
        final bounds = parseUnitPath(icon.pathData)!.getBounds();
        expect(
          bounds.left >= -0.01 &&
              bounds.top >= -0.01 &&
              bounds.right <= 1.01 &&
              bounds.bottom <= 1.01,
          isTrue,
          reason: '${icon.name} draws outside its box: $bounds',
        );
      }
    });

    test('are found by name and by tag', () {
      expect(
        catalog.iconsIn(null, query: 'house').map((i) => i.name),
        contains('house'),
      );
      // "tick" is a tag of circle-check, not a word in its name.
      expect(
        catalog.iconsIn(null, query: 'tick').map((i) => i.name),
        contains('circle-check'),
      );
    });

    test('lead with the ones listings use', () {
      expect(catalog.featured.first.name, 'star');
      expect(catalog.featured.length, greaterThan(30));
    });

    test('draw at Lucide\'s weight, scaled with the icon', () {
      final icon = catalog.icons.first.toShape();
      expect(icon.strokeInBox, isTrue);
      expect(icon.strokeWidth, closeTo(2 / 24, 1e-9));
    });
  });

  group('box-relative strokes', () {
    test('scale with the shape, not the canvas', () {
      const shape = ShapeSpec(
        kind: ShapeKind.path,
        strokeWidth: 0.1,
        strokeInBox: true,
      );
      expect(shape.strokePixels(1000, const Size(200, 100)), 10);
      expect(shape.strokePixels(4000, const Size(400, 200)), 20);
    });

    test('round-trip, and an ordinary outline writes no flag', () {
      const boxed = ShapeSpec(kind: ShapeKind.path, strokeInBox: true);
      expect(
        shapeFromJson(
          jsonDecode(jsonEncode(shapeToJson(boxed))) as Map<String, dynamic>,
          canvas: const Size(1290, 2796),
        ).strokeInBox,
        isTrue,
      );
      expect(
        shapeToJson(const ShapeSpec(kind: ShapeKind.star)),
        isNot(contains('strokeInBox')),
      );
    });
  });

  group('in the studio', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('element_library_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    testWidgets('a tap on an element adds it to the active screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          frameCatalogProvider.overrideWith((ref) => testCatalog),
          elementCatalogProvider.overrideWith((ref) => catalog),
        ],
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

      await tester.tap(
        find.descendant(
          of: find.byType(StudioToolRail),
          matching: find.byTooltip('Elements'),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Four-point sparkle'));
      await settle(tester);

      final shapes = container
          .read(projectStoreProvider)
          .first
          .subProjects
          .single
          .screens
          .first
          .shapes;
      expect(shapes, hasLength(1));
      expect(shapes.single.kind, ShapeKind.path);
      expect(tester.takeException(), isNull);
    });
  });
}
