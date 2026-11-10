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
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/editor/panels/text_layer_panel.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

// Text and image layers: the two layer types a screen can hold any number of,
// both built on the shape model.

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

  group('text layers', () {
    test('a text preset is a text layer and not a shape', () {
      final text = ShapeSpec.text('Hello');
      expect(text.isText, isTrue);
      expect(text.hasImage, isFalse);
      expect(text.displayName, 'Hello');
    });

    test('giving a text layer a fill makes it a badge', () {
      final badge = ShapeSpec.text(
        'NEW',
      ).copyWith(fill: const Color(0xFF3355FF));
      expect(badge.isText, isFalse);
    });

    // A widget test, not a plain one: measuring resolves a Google font, and
    // its offline failure is only tolerated inside the widget binding.
    testWidgets('the fitted box grows with the words', (tester) async {
      const canvas = Size(1290, 2796);
      final one = ShapeSpec.text('Short');
      final many = ShapeSpec.text(
        'A much longer line of words that will certainly wrap across '
        'several lines inside the box at this size',
      );
      expect(
        fittedTextHeight(many, canvas),
        greaterThan(fittedTextHeight(one, canvas)),
      );
    });
  });

  group('image layers', () {
    test('an image layer keeps the picture\'s proportions', () {
      final wide = ShapeSpec.image('logo.png', aspect: 2);
      expect(wide.hasImage, isTrue);
      expect(wide.isText, isFalse);
      expect(wide.width / wide.height, closeTo(2, 0.001));

      final tall = ShapeSpec.image('badge.png', aspect: 0.5);
      expect(tall.width / tall.height, closeTo(0.5, 0.001));
    });

    test('the picture survives a save and reload', () {
      final shape = ShapeSpec.image('/lib/logo.png', aspect: 1.5);
      final back = shapeFromJson(
        jsonDecode(jsonEncode(shapeToJson(shape))) as Map<String, dynamic>,
        canvas: const Size(1290, 2796),
      );
      expect(back.imagePath, '/lib/logo.png');
    });

    test('a shape saved before image layers has no picture', () {
      final json = shapeToJson(const ShapeSpec(kind: ShapeKind.star));
      expect(json.containsKey('image'), isFalse);
      final back = shapeFromJson(json, canvas: const Size(1290, 2796));
      expect(back.imagePath, isNull);
    });

    test('backups carry image layers as their own kind', () {
      final screen = ScreenDoc(
        id: 's',
        canvas: const Size(1290, 2796),
        shapes: [ShapeSpec.image('/lib/logo.png')],
      );
      expect(ProjectArchive.referencedImagesIn([screen]), {
        '/lib/logo.png': LibraryImageKind.element,
      });
    });

    test('an unknown image kind reads as a background', () {
      expect(LibraryImageKind.parse('element'), LibraryImageKind.element);
      expect(LibraryImageKind.parse('screenshot'), LibraryImageKind.screenshot);
      expect(
        LibraryImageKind.parse('from the future'),
        LibraryImageKind.background,
      );
      expect(LibraryImageKind.parse(null), LibraryImageKind.background);
    });
  });

  group('in the studio', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('layer_types_test');
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

    Future<void> openText(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(StudioToolRail),
          matching: find.byTooltip('Text'),
        ),
      );
      await settle(tester);
    }

    testWidgets('adds as many text layers as you like', (tester) async {
      final container = await pumpEditor(tester);
      await openText(tester);

      await tester.tap(find.text('Heading'));
      await settle(tester);
      await tester.tap(find.text('Body'));
      await settle(tester);

      final shapes = shapesOf(container);
      expect(shapes, hasLength(2));
      expect(shapes.every((s) => s.isText), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new text layer opens the Text properties', (tester) async {
      await pumpEditor(tester);
      await openText(tester);

      await tester.tap(find.text('Heading'));
      await settle(tester);

      expect(find.byType(TextLayerPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Delete removes the selected layer', (tester) async {
      final container = await pumpEditor(tester);
      await openText(tester);
      await tester.tap(find.text('Heading'));
      await settle(tester);
      expect(shapesOf(container), hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);

      expect(shapesOf(container), isEmpty);
    });

    testWidgets('an image layer paints its picture inside its outline', (
      tester,
    ) async {
      final screen = ScreenDoc(
        id: 's',
        canvas: const Size(1290, 2796),
        shapes: [ShapeSpec.image('assets/does-not-exist.png')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 650,
            child: SceneView(doc: screen, catalog: testCatalog),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ClipPath),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });
  });
}
