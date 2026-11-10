// The AI screenshot generator, walked end to end with the built-in analysis:
// a description in, a project out whose screens carry the plan's headlines in
// the recommended template. See `lib/features/ai_generate/`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/icons/icon_concepts.dart';
import 'package:mockmyapp/domain/icons/lucide_glyphs.dart';
import 'package:mockmyapp/domain/listing/listing_heuristics.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/ai_generate/ai_generate_screen.dart';
import 'package:mockmyapp/features/ai_generate/listing_generator.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Read straight off disk, like the other screen tests: an asset load
/// resolves on the real event loop while a widget test drives a fake clock.
final FrameCatalog _catalog = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

const _arrowRush =
    'Arrow rush game. escape all the arrow out of the screen. entertaining game';

Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ai_generate_test');
    ImageLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await ImageLibrary.initialize();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The store flushes on a debounce; leave the directory to the OS.
    }
  });

  testWidgets('walks the wizard and builds the planned project', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
    );
    addTearDown(container.dispose);

    Project? generated;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          home: AiGenerateScreen(onGenerated: (p) => generated = p),
        ),
      ),
    );
    await _settle(tester);

    // Step 1: nothing to analyse yet, so nothing to go on to.
    expect(find.text('Step 1 of 5 · Product info'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ai-description')),
        matching: find.byType(EditableText),
      ),
      _arrowRush,
    );
    await _settle(tester);
    expect(find.text('${_arrowRush.length} / 10000'), findsOneWidget);

    // Step 2: the built-in analysis, labelled as such.
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Step 2 of 5 · AI analysis'), findsOneWidget);
    expect(find.textContaining('Built-in suggestions'), findsOneWidget);
    expect(find.text('Arrow Rush'), findsWidgets);
    expect(find.byKey(const ValueKey('aso-score')), findsOneWidget);

    // Step 3: the game listing is recommended and chosen.
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Step 3 of 5 · Template'), findsOneWidget);
    expect(find.byKey(const ValueKey('template-arrowrush')), findsOneWidget);

    // Step 4: screenshots are optional.
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('No screenshots yet'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await _settle(tester);

    // Step 5: generate.
    expect(find.text('Step 5 of 5 · Generate'), findsOneWidget);
    await tester.tap(find.text('Generate Project'));
    await _settle(tester);
    // Past the store's save debounce, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));

    expect(generated, isNotNull);
    final projects = container.read(projectStoreProvider);
    expect(projects, hasLength(1));
    final project = projects.single;
    expect(project.id, generated!.id);
    expect(project.name, 'Arrow Rush');

    final sub = project.subProjects.single;
    final plan = heuristicAnalysis(_arrowRush).plan;
    expect(sub.screens, hasLength(plan.length));

    final template = screenTemplates.firstWhere((t) => t.id == 'arrowrush');
    for (final (i, screen) in sub.screens.indexed) {
      final caption = screen.caption!;
      expect(
        caption.text.replaceAll('\n', ' '),
        plan[i].headline,
        reason: 'screen ${i + 1} carries its planned headline',
      );
      // Runs, where the listing has them, spell the same words.
      if (caption.runs.isNotEmpty) {
        expect(caption.runs.map((r) => r.text).join(), caption.text);
      }
      expect(
        caption.fontFamily,
        template.screenAt(i).caption.fontFamily,
        reason: 'screen ${i + 1} wears the chosen template',
      );
      if (plan[i].subtitle case final subtitle?) {
        expect(screen.subCaption?.text, subtitle);
      }
    }
  });

  testWidgets('the finish can start the app icon from a concept', (
    tester,
  ) async {
    LucideGlyphs.debugUse([
      for (final i
          in (jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
                  as Map<String, dynamic>)['icons']
              as List)
        IconDef.fromJson(i as Map<String, dynamic>),
    ]);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
    );
    addTearDown(container.dispose);
    Project? generated;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          home: AiGenerateScreen(onGenerated: (p) => generated = p),
        ),
      ),
    );
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ai-description')),
        matching: find.byType(EditableText),
      ),
      _arrowRush,
    );
    await _settle(tester);
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.text('Next'));
      await _settle(tester);
    }
    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(find.text('Step 5 of 5 · Generate'), findsOneWidget);
    // Off unless asked for: the finish has always opened the editor.
    final toggle = find.byKey(const ValueKey('design-app-icon'));
    await tester.ensureVisible(toggle);
    await _settle(tester, frames: 2);
    expect(find.text('Design the app icon next'), findsOneWidget);
    await tester.tap(toggle);
    await _settle(tester, frames: 2);
    await tester.tap(find.text('Generate Project'));
    await _settle(tester);
    // Past the store's save debounce, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));

    expect(generated, isNotNull);
    final project = container
        .read(projectStoreProvider)
        .firstWhere((p) => p.id == generated!.id);
    expect(project.icon, isNotNull);
    expect(project.icon!.glyph, isNotNull);
    expect(project.icon, await firstConceptFor(project));
  });

  test('the generator puts screenshots on the screens in order', () async {
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
    );
    addTearDown(container.dispose);

    final analysis = heuristicAnalysis(_arrowRush);
    final project = await generateListingProject(
      store: container.read(projectStoreProvider.notifier),
      library: container.read(imageLibraryProvider.notifier),
      catalog: _catalog,
      target: StoreTargets.iphone,
      analysis: analysis,
      shots: [
        PickedShot(utf8.encode('one'), 'one.png'),
        PickedShot(utf8.encode('two'), 'two.jpg'),
      ],
    );

    final screens = project.subProjects.single.screens;
    expect(project.subProjects.single.targetId, StoreTargets.iphone.id);
    expect(screens, hasLength(analysis.plan.length));
    final shots = [
      for (final s in screens) s.frames.first.screenshot.imagePath,
    ];
    expect(shots[0], endsWith('.png'));
    expect(shots[1], endsWith('.jpg'));
    expect(shots.skip(2), everyElement(isNull));
    expect(File(shots[0]!).readAsStringSync(), 'one');
    expect(
      screens.first.caption!.text.replaceAll('\n', ' '),
      analysis.plan.first.headline,
    );
    await container.read(projectStoreProvider.notifier).debugFlush();
  });

  test('a screen given a screenshot keeps its phone where the listing put '
      'it', () async {
    // On the tall iPhone page a phone showing the listing's own app sits
    // lower than designed, to keep the artwork's filled-in foot off the page.
    // A screenshot covers the artwork, so its phone has no reason to.
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
    );
    addTearDown(container.dispose);

    final template = screenTemplates.firstWhere((t) => t.id == 'arrowrush');
    final project = await generateListingProject(
      store: container.read(projectStoreProvider.notifier),
      library: container.read(imageLibraryProvider.notifier),
      catalog: _catalog,
      target: StoreTargets.iphone,
      analysis: heuristicAnalysis(_arrowRush),
      template: template,
      shots: [PickedShot(utf8.encode('one'), 'one.png')],
    );

    final screens = project.subProjects.single.screens;
    double top(Transform2D t) =>
        (1 - t.pagePercentage * t.scale) / 2 * (1 + t.align.y) + t.offsetPct.dy;
    double designed(int i) => top(
      template
          .screenAt(i)
          .transformFor(
            screens[i].canvas,
            worn: WornFrame.on(screens[i].frames.first, _catalog),
          ),
    );
    expect(screens[0].frames.first.screenshot.imagePath, isNotNull);
    expect(top(screens[0].frames.first.transform), closeTo(designed(0), 1e-9));
    expect(screens[1].frames.first.screenshot.imagePath, isNull);
    expect(
      top(screens[1].frames.first.transform),
      greaterThan(designed(1) + 0.1),
    );
    await container.read(projectStoreProvider.notifier).debugFlush();
  });

  test('a listing longer than the plan is trimmed to the plan', () async {
    final container = ProviderContainer(
      overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
    );
    addTearDown(container.dispose);

    final analysis = heuristicAnalysis(_arrowRush, planLength: 3);
    final template = screenTemplates.firstWhere((t) => t.id == 'arrowrush');
    expect(
      template.lengthFor(StoreTargets.androidPhone.defaultPreset.size),
      greaterThan(3),
      reason: 'the case only exists for a listing longer than the plan',
    );
    final project = await generateListingProject(
      store: container.read(projectStoreProvider.notifier),
      library: container.read(imageLibraryProvider.notifier),
      catalog: _catalog,
      target: StoreTargets.androidPhone,
      analysis: analysis,
      template: template,
    );
    expect(project.subProjects.single.screens, hasLength(3));
    expect(template.platforms, contains(TemplatePlatform.android));
    await container.read(projectStoreProvider.notifier).debugFlush();
  });
}
