// The Store copy page, driven like a person would: on a 390-point phone and a
// desktop, light and dark; drafting on the device; the checks and their fixes
// as a field is typed; Copy and Copy all; Regenerate; translation on the
// device, language by language. Plus the ways in: the editor's project menu
// and the AI wizard's finish.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/listing/listing_analysis.dart';
import 'package:mockmyapp/domain/listing/listing_heuristics.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/providers/on_device_ai_provider.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';
import 'package:mockmyapp/features/ai_generate/listing_generator.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/store_copy/store_copy_screen.dart';

final FrameCatalog _catalog = frameCatalogFromManifest(
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

const _brief = ListingBrief(
  appName: 'Wayfare',
  description:
      'Wayfare plans trips: every booking, map and ticket in one place, with '
      'maps that work offline. Available on iPhone and Android.',
  audience: 'Travellers who are tired of juggling apps.',
  keywords: ['trip planner', 'itinerary', 'travel'],
  features: [
    ListingFeature(
      title: 'Every Booking Together',
      detail: 'Flights, hotels and trains in one list.',
      importance: 9,
    ),
    ListingFeature(
      title: 'Offline Maps',
      detail: 'Find your way without a signal.',
      importance: 8,
    ),
  ],
  usps: ['Works without a signal'],
);

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A translator that marks what it translated, for the device's run.
class _GermanTranslator implements TextTranslator {
  @override
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  }) async => to == 'de-DE'
      ? const EngineStatus(AiEngine.appleTranslation, ModelState.ready)
      : const EngineStatus(
          AiEngine.none,
          ModelState.unavailable,
          reason: 'Not available on this device',
        );

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async => [for (final t in texts) t.trim().isEmpty ? t : 'DE $t'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String? clipboard;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('store_copy_screen_test');
    ImageLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await ImageLibrary.initialize();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  /// The page for a project with an iPhone and an Android set, [brief], and
  /// [languages]; returns the container and the project's id.
  Future<(ProviderContainer, String)> pumpPage(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = false,
    ListingBrief brief = _brief,
    List<String> languages = const ['en-US'],
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        frameCatalogProvider.overrideWith((ref) => _catalog),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    final store = container.read(projectStoreProvider.notifier);
    final project = store.createProject(
      name: 'Wayfare',
      targets: [
        (
          targetId: StoreTargets.iphone.id,
          presetId: StoreTargets.iphone.defaultPreset.id,
        ),
        (
          targetId: StoreTargets.androidPhone.id,
          presetId: StoreTargets.androidPhone.defaultPreset.id,
        ),
      ],
    );
    store.setListingBrief(project.id, brief);
    store.setLanguages(project.id, languages);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? StudioAppTheme.dark() : StudioAppTheme.light(),
          builder: StudioLayoutScope.wrap,
          home: StoreCopyScreen(projectId: project.id),
        ),
      ),
    );
    await _settle(tester);
    return (container, project.id);
  }

  Project projectIn(ProviderContainer c, String id) =>
      c.read(projectStoreProvider).firstWhere((p) => p.id == id);

  String fieldText(WidgetTester tester, String id) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey('copy-field-$id')),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  /// Scrolls the page's list until [finder] is built, then brings it into
  /// view. Jumps rather than drags: a drag that lands on a multi-line field
  /// scrolls the field, not the page.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.descendant(
      of: find.byKey(const ValueKey('store-copy-list')),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(list.first).position;
      position.jumpTo(
        (position.pixels + 400).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('fits', () {
    for (final (size, label) in const [
      (Size(390, 844), 'a 390-point phone'),
      (Size(1440, 900), 'a desktop window'),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('$label, ${dark ? 'dark' : 'light'}', (tester) async {
          await pumpPage(
            tester,
            size: size,
            dark: dark,
            languages: const ['en-US', 'de-DE'],
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Store copy'), findsOneWidget);
          expect(find.byKey(const ValueKey('store-tabs')), findsOneWidget);
          expect(find.text('Draft with AI · On this device'), findsOneWidget);
          expect(find.byKey(const ValueKey('copy-field-name')), findsOneWidget);
          // Google Play is a store this project's Android set goes to.
          expect(find.text('Google Play'), findsWidgets);
          await reveal(tester, find.byKey(const ValueKey('translate')));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('drafts every field on this device, and Undo puts it back', (
    tester,
  ) async {
    final (container, id) = await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);

    final copy = projectIn(container, id).storeCopy;
    final apple = copy.fieldsOf(CopyStore.appStore, 'en-US');
    expect(apple.keys, containsAll(['name', 'subtitle', 'keywords']));
    expect(fieldText(tester, 'name'), apple['name']);
    expect(find.textContaining('left'), findsWidgets);
    // Never another platform in Apple copy, though the brief says Android.
    for (final text in apple.values) {
      expect(text.toLowerCase(), isNot(contains('android')));
    }
    expect(
      find.text('Drafted ${apple.length} fields with the built-in suggestions'),
      findsOneWidget,
    );
    expect(find.text('Written by Built-in suggestions'), findsNothing);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(projectIn(container, id).storeCopy.isEmpty, isTrue);
    expect(fieldText(tester, 'name'), isEmpty);
  });

  testWidgets('asks before a draft replaces copy somebody wrote', (
    tester,
  ) async {
    final (container, id) = await pumpPage(tester);
    container
        .read(projectStoreProvider.notifier)
        .updateStoreCopy(
          id,
          (c) => c.withText(CopyStore.appStore, 'en-US', 'name', 'My own name'),
        );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);
    expect(find.text('Replace the copy?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(
      projectIn(
        container,
        id,
      ).storeCopy.text(CopyStore.appStore, 'en-US', 'name'),
      'My own name',
    );

    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);
    await tester.tap(find.text('Replace'));
    await _settle(tester);
    expect(
      projectIn(
        container,
        id,
      ).storeCopy.text(CopyStore.appStore, 'en-US', 'name'),
      isNot('My own name'),
    );
  });

  testWidgets('checks a field as it is typed, and makes the fix', (
    tester,
  ) async {
    final (container, id) = await pumpPage(tester);
    await tester.tap(find.text('Google Play').first);
    await _settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('copy-field-title')),
        matching: find.byType(EditableText),
      ),
      'Best Trip Planner',
    );
    await _settle(tester);
    expect(find.textContaining('“Best” is a ranking'), findsOneWidget);
    expect(find.text('17/30 · 13 left'), findsOneWidget);

    await tester.tap(find.text('Remove it'));
    await _settle(tester);
    expect(fieldText(tester, 'title'), 'Trip Planner');
    expect(
      projectIn(
        container,
        id,
      ).storeCopy.text(CopyStore.playStore, 'en-US', 'title'),
      'Trip Planner',
    );
    expect(find.textContaining('“Best” is a ranking'), findsNothing);
  });

  testWidgets('counts Apple keywords in bytes and tidies them', (tester) async {
    await pumpPage(tester);
    final keywords = find.descendant(
      of: find.byKey(const ValueKey('copy-field-keywords')),
      matching: find.byType(EditableText),
    );
    await reveal(tester, keywords);
    await tester.enterText(keywords, '旅行, 計画');
    await _settle(tester);
    // Two Japanese words and a comma and a space: 14 bytes.
    expect(find.text('14/100 bytes · 86 left'), findsOneWidget);
    expect(find.textContaining('spaces around the commas'), findsOneWidget);
    await tester.tap(find.text('Tidy keywords'));
    await _settle(tester);
    expect(fieldText(tester, 'keywords'), '旅行,計画');
  });

  testWidgets('copies a field, and all of a store', (tester) async {
    final (_, _) = await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);
    final name = fieldText(tester, 'name');

    await tester.tap(find.byKey(const ValueKey('copy-name')));
    await _settle(tester);
    expect(clipboard, name);
    expect(find.text('Copied the name'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('copy-all')));
    await _settle(tester);
    expect(clipboard, startsWith('App Store · English (US)\n\nName\n$name'));
    expect(
      find.text('Copied all App Store text in English (US)'),
      findsOneWidget,
    );
  });

  testWidgets('Regenerate rewrites one field and leaves the rest', (
    tester,
  ) async {
    final (container, id) = await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);
    final before = projectIn(
      container,
      id,
    ).storeCopy.fieldsOf(CopyStore.appStore, 'en-US');

    await tester.tap(find.byKey(const ValueKey('regenerate-subtitle')));
    await _settle(tester);
    final after = projectIn(
      container,
      id,
    ).storeCopy.fieldsOf(CopyStore.appStore, 'en-US');
    expect(after['subtitle'], isNot(before['subtitle']));
    expect(after['name'], before['name']);
    expect(after['description'], before['description']);
  });

  group('translation', () {
    testWidgets('on this device, language by language', (tester) async {
      final (container, id) = await pumpPage(
        tester,
        languages: const ['en-US', 'de-DE', 'ja-JP'],
        overrides: [translatorProvider.overrideWithValue(_GermanTranslator())],
      );
      await tester.tap(find.byKey(const ValueKey('draft-all')));
      await _settle(tester);
      await reveal(tester, find.byKey(const ValueKey('translate')));
      expect(find.text('Translate · On this device'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('translate')));
      await _settle(tester);

      final copy = projectIn(container, id).storeCopy;
      final english = copy.fieldsOf(CopyStore.appStore, 'en-US');
      final german = copy.fieldsOf(CopyStore.appStore, 'de-DE');
      expect(german['name'], 'DE ${english['name']}');
      expect(find.text('German · Done'), findsOneWidget);
      expect(find.text('Japanese · Not available on this device'), findsOne);
      expect(copy.has(CopyStore.appStore, 'ja-JP'), isFalse);
    });

    testWidgets('asks before replacing a translation, and Undo puts it back', (
      tester,
    ) async {
      final (container, id) = await pumpPage(
        tester,
        languages: const ['en-US', 'de-DE'],
        overrides: [translatorProvider.overrideWithValue(_GermanTranslator())],
      );
      container
          .read(projectStoreProvider.notifier)
          .updateStoreCopy(
            id,
            (c) => c
                .withText(CopyStore.appStore, 'en-US', 'name', 'Wayfare')
                .withText(CopyStore.appStore, 'de-DE', 'name', 'Mein Name'),
          );
      await _settle(tester);
      await reveal(tester, find.byKey(const ValueKey('translate')));
      await tester.tap(find.byKey(const ValueKey('translate')));
      await _settle(tester);
      expect(find.text('Replace the translations?'), findsOneWidget);
      expect(
        find.textContaining('German already has App Store copy'),
        findsOneWidget,
      );
      await tester.tap(find.text('Translate'));
      await _settle(tester);
      String german() => projectIn(
        container,
        id,
      ).storeCopy.text(CopyStore.appStore, 'de-DE', 'name');
      expect(german(), 'DE Wayfare');
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(german(), 'Mein Name');
    });
  });

  group('the ways in', () {
    testWidgets('the editor\'s project menu opens it', (tester) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
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
      final router = GoRouter(
        initialLocation: '/project/${project.id}',
        routes: [
          GoRoute(
            path: '/project/:id',
            builder: (_, state) =>
                EditorScreen(projectId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/project/:id/store-copy',
            builder: (_, state) =>
                StoreCopyScreen(projectId: state.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            routerConfig: router,
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byTooltip('Project'));
      await _settle(tester);
      await tester.tap(find.text('Store copy'));
      await _settle(tester);
      expect(find.byType(StoreCopyScreen), findsOneWidget);
      expect(find.text('Draft with AI · On this device'), findsOneWidget);
    });

    test(
      'the AI wizard\'s finish drafts the store copy for its store',
      () async {
        final container = ProviderContainer(
          overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
        );
        addTearDown(container.dispose);
        const description =
            'Arrow rush game. escape all the arrow out of the screen. '
            'entertaining game';
        final analysis = heuristicAnalysis(description);
        final store = container.read(projectStoreProvider.notifier);
        final project = await generateListingProject(
          store: store,
          library: container.read(imageLibraryProvider.notifier),
          catalog: _catalog,
          target: StoreTargets.androidPhone,
          analysis: analysis,
          brief: ListingBrief.fromAnalysis(analysis, description: description),
          draftCopyFor: CopyStore.playStore,
        );
        final copy = store.byId(project.id)!.storeCopy;
        expect(copy.stores, [CopyStore.playStore]);
        final play = copy.fieldsOf(CopyStore.playStore, 'en-US');
        expect(play['title'], startsWith(analysis.appName));
        // Alt text from the plan's headlines, one per screen.
        expect(
          play['altText']!.split('\n'),
          hasLength(analysis.plan.length.clamp(0, 8)),
        );
        await store.debugFlush();
      },
    );
  });
}
