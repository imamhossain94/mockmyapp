// The language a project was being edited in survives a reload.
//
// It lived in the editor's state alone, so reopening a project — or reloading
// the web app, which is how a browser tab comes back — put a German listing
// back on the English words every time.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/locales.dart';
import 'package:mockmyapp/domain/providers/editor_language_provider.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the remembered language', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<Map<String, String>> reloaded() async {
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      fresh.read(editorLanguagesProvider);
      await pumpEventQueue();
      return fresh.read(editorLanguagesProvider);
    }

    test('is kept on the device and read back after a reload', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(editorLanguagesProvider);
      await pumpEventQueue();

      container.read(editorLanguagesProvider.notifier).set('p1', 'de-DE');
      await pumpEventQueue();

      expect(await reloaded(), {'p1': 'de-DE'});
    });

    test('going back to the default forgets it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final languages = container.read(editorLanguagesProvider.notifier);
      languages.set('p1', 'de-DE');
      languages.set('p1', null);
      await pumpEventQueue();

      expect(await reloaded(), isEmpty);
    });

    test('a choice made while it loads is not lost to the load', () async {
      SharedPreferences.setMockInitialValues({
        'editor_languages_v1': jsonEncode({'p1': 'fr-FR'}),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Chosen in the same turn the store starts reading.
      container.read(editorLanguagesProvider.notifier).set('p2', 'ja-JP');
      await pumpEventQueue();

      expect(container.read(editorLanguagesProvider), {
        'p1': 'fr-FR',
        'p2': 'ja-JP',
      });
    });
  });

  testWidgets('the editor opens on the language it was left in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('language_memory_test');
    PathProviderPlatform.instance = _ScratchPathProvider(dir.path);
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
    // What the last visit left behind.
    container.read(editorLanguagesProvider.notifier).set(project.id, 'de-DE');

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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text(localeFor('de-DE').short), findsOneWidget);
    expect(find.text(localeFor('en-US').short), findsNothing);
  });
}
