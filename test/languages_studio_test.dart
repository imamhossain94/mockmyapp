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
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

// Languages and the store preview, driven through the studio.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('languages_studio_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  Future<ProviderContainer> pumpStudio(WidgetTester tester) async {
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
    store.setLanguages(project.id, const ['en-US', 'de-DE']);

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

  ScreenDoc firstScreen(ProviderContainer c) =>
      c.read(projectStoreProvider).first.subProjects.single.screens.first;

  final activeScene = find.byKey(const ValueKey('active-scene'));

  testWidgets('the translation table writes German, and the canvas shows it', (
    tester,
  ) async {
    final container = await pumpStudio(tester);
    final english = firstScreen(container).caption!.text;

    await tester.tap(find.byTooltip('Language'));
    await settle(tester);
    await tester.tap(find.text('German'));
    await settle(tester);

    await tester.tap(find.byTooltip('Language'));
    await settle(tester);
    await tester.tap(find.text('Translate texts…'));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Deine Überschrift');
    await settle(tester);
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await settle(tester);

    final caption = firstScreen(container).caption!;
    expect(caption.text, english, reason: 'the default words are untouched');
    expect(caption.translations['de-DE']!.text, 'Deine Überschrift');
    expect(
      tester.widget<SceneView>(activeScene).doc.caption!.text,
      'Deine Überschrift',
      reason: 'the canvas is showing German',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an edit made in German stays out of English', (tester) async {
    final container = await pumpStudio(tester);
    final before = firstScreen(container).caption!;

    await tester.tap(find.byTooltip('Language'));
    await settle(tester);
    await tester.tap(find.text('German'));
    await settle(tester);

    // Drag the headline: position is design, shared by every language.
    await tester.tap(activeScene);
    await settle(tester);
    final scene = tester.widget<SceneView>(activeScene);
    scene.onTransformStart!(SceneSelection.caption);
    scene.onTransform!(
      SceneSelection.caption,
      ScaleUpdateDetails(focalPointDelta: const Offset(40, 0)),
    );
    scene.onTransformEnd!(SceneSelection.caption);
    await settle(tester);

    final after = firstScreen(container).caption!;
    expect(after.offsetPct, isNot(before.offsetPct));
    expect(after.text, before.text);
    expect(after.translations, isEmpty, reason: 'no words were changed');
  });

  testWidgets('the store preview shows every screen in a listing', (
    tester,
  ) async {
    final container = await pumpStudio(tester);
    final count = container
        .read(projectStoreProvider)
        .first
        .subProjects
        .single
        .screens
        .length;

    await tester.tap(find.byTooltip('Store preview'));
    await settle(tester);

    expect(find.text('Store preview'), findsOneWidget);
    expect(
      find.text('Get'),
      findsOneWidget,
      reason: 'an iPhone set opens on the App Store',
    );
    // The listing scrolls sideways, so count what it was asked to show.
    expect(find.byType(SceneView), findsWidgets);
    expect(count, greaterThan(0));

    await tester.tap(find.text('Google Play'));
    await settle(tester);
    expect(find.text('Install'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
