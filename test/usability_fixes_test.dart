import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/shared/save_actions.dart';

// Fixes from a hands-on pass over the app on an Android phone and in a
// browser: what a new project's sets wear, what a template does to a set for
// the other store, and toasts that never went away.

final FrameCatalog testCatalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('usability_fixes_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  const both = [
    (targetId: 'ios-iphone', presetId: 'iphone-6-5'),
    (targetId: 'android-phone', presetId: 'android-phone-9-16'),
  ];

  group('a new project', () {
    test('puts each set on its own store\'s handset', () {
      final project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Both stores',
            targets: both,
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
            devicesByTarget: const {
              'android-phone': (
                deviceId: 'samsung-galaxy-note-10-plus',
                variantId: 'aura-black',
                cornerRadiusPct: 0.05,
              ),
            },
          );

      final iphone = project.subProjects.first.screens.first.frames.single;
      final android = project.subProjects.last.screens.first.frames.single;
      expect(iphone.deviceId, 'apple-iphone-16');
      expect(android.deviceId, 'samsung-galaxy-note-10-plus');
      expect(android.variantId, 'aura-black');
    });

    test('falls back to the initial handset for a target not named', () {
      final project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Both stores',
            targets: both,
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
          );
      for (final sub in project.subProjects) {
        expect(sub.screens.first.frames.single.deviceId, 'apple-iphone-16');
      }
    });
  });

  group('a template for one store', () {
    final android = screenTemplates.firstWhere((t) => t.id == 'sonary');

    test('names the platforms it was made for', () {
      expect(android.platforms, {TemplatePlatform.android});
      expect(android.framesFor(TemplatePlatform.android), isTrue);
      expect(android.framesFor(TemplatePlatform.ios), isFalse);
      expect(android.framesFor(null), isTrue);
    });

    test('keeps the real iPhone on an App Store set', () {
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Sonary',
        targets: both,
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      for (final sub in project.subProjects) {
        store.applyTemplate(project.id, sub.id, android, withCopy: true);
      }
      final saved = container.read(projectStoreProvider).single;

      final iphone = saved.subProjects.first.screens.first.frames.first;
      expect(
        iphone.design,
        isNull,
        reason: 'the Android bezel the listing was measured in stays off it',
      );
      expect(iphone.deviceId, 'apple-iphone-16');
      // Everything else about the look still arrives.
      expect(
        saved.subProjects.first.screens.first.caption?.plainText,
        isNotEmpty,
      );

      final phone = saved.subProjects.last.screens.first.frames.first;
      expect(
        phone.design,
        isNotNull,
        reason: 'the Play set wears the listing\'s own mockup',
      );
    });
  });

  testWidgets('a toast with an Undo on it goes away by itself', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioAppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    showStudioSnack(
      context,
      'Deleted screen 2',
      actionLabel: 'Undo',
      onAction: () {},
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deleted screen 2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Deleted screen 2'), findsNothing);
  });

  group('the editor', () {
    final navigator = GlobalKey<NavigatorState>();
    final activeScene = find.byKey(const ValueKey('active-scene'));
    SceneView scene(WidgetTester tester) =>
        tester.widget<SceneView>(activeScene);

    /// The editor, pushed over a home route so back has somewhere to go.
    Future<void> pushEditor(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final editorContainer = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
      );
      addTearDown(editorContainer.dispose);
      final project = editorContainer
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Listing',
            targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: editorContainer,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: const Text('home'),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => EditorScreen(projectId: project.id),
        ),
      );
      await settle(tester, frames: 20);
    }

    testWidgets('back puts down the selection before it leaves', (
      tester,
    ) async {
      await pushEditor(tester, const Size(1440, 900));
      scene(tester).onSelect!(SceneSelection.frameAt(0));
      await settle(tester, frames: 3);
      expect(scene(tester).selected, isNotNull);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(scene(tester).selected, isNull);

      await tester.binding.handlePopRoute();
      await settle(tester, frames: 20);
      expect(find.byType(EditorScreen), findsNothing);
    });

    testWidgets('on a phone, a selection brings its tools up', (tester) async {
      await pushEditor(tester, const Size(390, 844));
      expect(find.byTooltip('Hide tools'), findsNothing);

      scene(tester).onSelect!(SceneSelection.frameAt(0));
      await settle(tester);
      expect(
        find.byTooltip('Hide tools'),
        findsOneWidget,
        reason: 'the sheet opened on the device\'s panel',
      );

      await tester.tap(find.byTooltip('Hide tools'));
      await settle(tester);
      expect(find.byTooltip('Show tools'), findsOneWidget);
    });
  });

  group('an empty device', () {
    const doc = ScreenDoc(
      id: 'empty',
      canvas: Size(1290, 2796),
      frames: [
        FramePlacement(
          deviceId: 'apple-iphone-16',
          variantId: '16---ultramarine',
        ),
      ],
    );
    final glyph = find.byIcon(Icons.add_photo_alternate_outlined);

    Future<void> pumpScene(WidgetTester tester, {required bool forExport}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 650,
                child: SceneView(
                  doc: doc,
                  catalog: testCatalog,
                  forExport: forExport,
                ),
              ),
            ),
          ),
        );

    testWidgets('asks for a picture in the editor', (tester) async {
      await pumpScene(tester, forExport: false);
      expect(glyph, findsOneWidget);
    });

    testWidgets('exports as a plain plate, without the prompt', (tester) async {
      await pumpScene(tester, forExport: true);
      expect(glyph, findsNothing);
    });
  });

  group('a translated headline', () {
    const ink = Color(0xFF141A33);
    const accent = Color(0xFF5B4BFF);
    const twoTone = CaptionSpec(
      text: 'One swipe.\nTotal control.',
      runs: [
        CaptionRun('One swipe.\n', color: ink),
        CaptionRun('Total control.', color: accent),
      ],
      translations: {
        'de-DE': CaptionTranslation(text: 'Ein Wisch.\nVolle Kontrolle.'),
      },
    );

    test('keeps the original\'s colours, line by line', () {
      final german = twoTone.inLanguage('de-DE');
      expect(german.plainText, 'Ein Wisch.\nVolle Kontrolle.');
      expect(german.runs.map((r) => r.color), [ink, accent]);
    });

    test('a longer translation carries the last line\'s style on', () {
      final spec = twoTone.copyWith(
        translations: {
          'de-DE': const CaptionTranslation(text: 'Ein\nWisch\nfür alles'),
        },
      );
      expect(spec.inLanguage('de-DE').runs.map((r) => r.color), [
        ink,
        accent,
        accent,
      ]);
    });

    test('a translation styled on its own keeps its own styling', () {
      final spec = twoTone.copyWith(
        translations: {
          'de-DE': const CaptionTranslation(
            text: 'Ein Wisch.',
            runs: [CaptionRun('Ein Wisch.', color: Color(0xFFFF0000))],
          ),
        },
      );
      expect(
        spec.inLanguage('de-DE').runs.single.color,
        const Color(0xFFFF0000),
      );
    });

    test('a plain caption stays plain', () {
      const plain = CaptionSpec(
        text: 'Hello',
        translations: {'de-DE': CaptionTranslation(text: 'Hallo')},
      );
      expect(plain.inLanguage('de-DE').runs, isEmpty);
    });
  });

  group('the desktop editor', () {
    final activeScene = find.byKey(const ValueKey('active-scene'));
    SceneView scene(WidgetTester tester) =>
        tester.widget<SceneView>(activeScene);

    final elements = ElementCatalog.fromJson(
      elements:
          jsonDecode(File('assets/elements/elements.json').readAsStringSync())
              as Map<String, dynamic>,
      icons:
          jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
              as Map<String, dynamic>,
    );

    Future<ProviderContainer> pumpDesktop(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final editorContainer = ProviderContainer(
        overrides: [
          frameCatalogProvider.overrideWith((ref) => testCatalog),
          elementCatalogProvider.overrideWith((ref) => elements),
        ],
      );
      addTearDown(editorContainer.dispose);
      final store = editorContainer.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      final screen = store.byId(project.id)!.subProjects.single.screens.first;
      store.updateScreen(
        project.id,
        screen.copyWith(
          shapes: const [
            ShapeSpec(
              kind: ShapeKind.star,
              center: Offset(0.2, 0.1),
              width: 0.2,
              height: 0.2,
              z: kStackOverEverything,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: editorContainer,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: EditorScreen(projectId: project.id),
          ),
        ),
      );
      await settle(tester, frames: 20);
      return editorContainer;
    }

    testWidgets('keys typed into a panel field are left to the field', (
      tester,
    ) async {
      await pumpDesktop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await settle(tester);
      expect(find.text('ELEMENTS'), findsOneWidget);

      // "1" opens the Templates library — unless a field has the keyboard.
      await tester.tap(find.text('Search elements'));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await settle(tester);
      expect(
        find.text('ELEMENTS'),
        findsOneWidget,
        reason: 'the digit was for the search, not a shortcut',
      );

      // A press on the canvas hands the keyboard back.
      await tester.tapAt(
        tester.getRect(activeScene).bottomCenter - const Offset(0, 8),
      );
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await settle(tester);
      expect(find.text('TEMPLATES'), findsOneWidget);
    });

    testWidgets('a corner handle resizes the selected shape', (tester) async {
      final editorContainer = await pumpDesktop(tester);
      double width() => editorContainer
          .read(projectStoreProvider)
          .single
          .subProjects
          .single
          .screens
          .first
          .shapes
          .single
          .width;

      scene(tester).onSelect!(const SceneSelection.shape(0));
      await settle(tester);
      final handles = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_CornerHandle',
      );
      expect(handles, findsNWidgets(4));

      final before = width();
      // The bottom-right corner, pulled away from the middle.
      await tester.dragFrom(
        tester.getCenter(handles.at(3)),
        const Offset(40, 40),
      );
      await settle(tester);
      expect(width(), greaterThan(before * 1.1));
    });
  });
}
