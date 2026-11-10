// The Icon page, driven like a person would: on a 390-point phone and a
// desktop, light and dark; glyph concepts on open, picked in one tap; the
// mark, its size, colour and background edited, and Undo walking back; the
// guides; the home-screen, small-size and store previews; and the same files
// and the same preview pixels whichever theme the app is in.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:go_router/go_router.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/icons/icon_export.dart';
import 'package:mockmyapp/domain/icons/lucide_glyphs.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/icon_studio/icon_export_actions.dart';
import 'package:mockmyapp/features/icon_studio/icon_previews.dart';
import 'package:mockmyapp/features/icon_studio/icon_studio_screen.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

ElementCatalog readCatalog() => ElementCatalog.fromJson(
  elements:
      jsonDecode(File('assets/elements/elements.json').readAsStringSync())
          as Map<String, dynamic>,
  icons:
      jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
          as Map<String, dynamic>,
);

final FrameCatalog _frames = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

const _brief = ListingBrief(
  appName: 'Wayfare',
  description: 'Plan trips: bookings, maps and tickets in one place.',
  category: TemplateCategory.travel,
  keywords: ['trip planner', 'itinerary'],
);

const _icon = IconDoc(
  background: GradientBackground(
    colorOne: Color(0xFF0B3D4C),
    colorTwo: Color(0xFF1E9AB0),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  foreground: IconGlyph('compass'),
  glyphColor: Color(0xFFFFD166),
  stroke: 1.4,
);

/// Lets real async work — image decoding, file writes — finish between
/// frames, and waits out the store's debounced save.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A page under test: its container and its project's id.
typedef Page = (ProviderContainer, String);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalog = readCatalog();
  late Directory tempDir;

  setUpAll(() => LucideGlyphs.debugUse(catalog.icons));

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('icon_studio_test');
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

  /// The page for a new project with [icon], or — given [reuse] — the same
  /// project again, in another theme. One container a test: a second store
  /// would read the first one's saved file over its own new project.
  Future<Page> pumpPage(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = false,
    IconDoc? icon,
    Page? reuse,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ProviderContainer container;
    final String id;
    if (reuse != null) {
      (container, id) = reuse;
    } else {
      container = ProviderContainer(
        overrides: [elementCatalogProvider.overrideWith((ref) => catalog)],
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
        ],
      );
      store.setListingBrief(project.id, _brief);
      if (icon != null) store.setIcon(project.id, icon);
      id = project.id;
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? StudioAppTheme.dark() : StudioAppTheme.light(),
          builder: StudioLayoutScope.wrap,
          home: IconStudioScreen(projectId: id),
        ),
      ),
    );
    await settle(tester);
    return (container, id);
  }

  Project projectIn(ProviderContainer c, String id) =>
      c.read(projectStoreProvider).firstWhere((p) => p.id == id);

  /// Brings [finder] into view — scrolling the phone's list until it is
  /// built, when it is further down — and taps it.
  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('icon-page')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tapOn(tester, find.byKey(ValueKey(key)));

  group('fits', () {
    for (final (size, label) in const [
      (Size(390, 844), 'a 390-point phone'),
      (Size(1440, 900), 'a desktop window'),
    ]) {
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';

        testWidgets('$label, $theme, before an icon', (tester) async {
          await pumpPage(tester, size: size, dark: dark);
          expect(tester.takeException(), isNull);
          expect(find.text('App icon'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('icon-empty-stage')),
            findsOneWidget,
          );
          // The rules' first round is there on open, free.
          expect(find.byKey(const ValueKey('concept-0')), findsOneWidget);
          expect(find.text('Built-in suggestions'), findsOneWidget);
        });

        testWidgets('$label, $theme, with an icon', (tester) async {
          await pumpPage(tester, size: size, dark: dark, icon: _icon);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('icon-stage')), findsOneWidget);
          if (size.width < 900) {
            expect(find.byKey(const ValueKey('icon-sections')), findsOneWidget);
            for (final section in ['Design', 'Previews', 'Export']) {
              await tester.tap(find.text(section));
              await settle(tester, frames: 4);
              expect(tester.takeException(), isNull, reason: section);
            }
          } else {
            expect(
              find.byKey(const ValueKey('icon-inspector')),
              findsOneWidget,
            );
            expect(find.byKey(const ValueKey('home-light')), findsOneWidget);
            expect(
              find.byKey(const ValueKey('icon-mark-panel')),
              findsOneWidget,
            );
          }
        });
      }
    }
  });

  testWidgets('a concept becomes the icon in one tap, and Undo takes it '
      'back', (tester) async {
    final (container, id) = await pumpPage(tester);
    expect(projectIn(container, id).icon, isNull);

    await tapKey(tester, 'concept-0');
    final icon = projectIn(container, id).icon;
    expect(icon, isNotNull);
    expect(icon!.glyph, isNotNull);
    expect(find.byKey(const ValueKey('icon-stage')), findsOneWidget);
    // Saved with the project, as every edit is.
    expect(projectIn(container, id).toJson()['icon'], isNotNull);

    await tapKey(tester, 'icon-undo');
    expect(projectIn(container, id).icon, isNull);
    expect(projectIn(container, id).toJson().containsKey('icon'), isFalse);
  });

  testWidgets('asks for more concepts, new ones each time', (tester) async {
    await pumpPage(tester);
    String first() => tester
        .widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('concept-0')),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .label!;
    final before = first();
    await tapKey(tester, 'suggest-concepts');
    expect(first(), isNot(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mark, its colour, the background and the preview shape '
      'are edited, each saved', (tester) async {
    final (container, id) = await pumpPage(tester, icon: _icon);
    IconDoc icon() => projectIn(container, id).icon!;
    await tester.tap(find.text('Design'));
    await settle(tester);

    // A glyph from the picker, which opens on the brief's suggestions.
    await tapKey(tester, 'glyph-plane');
    expect(icon().glyph, 'plane');

    // A colour for it.
    await tapOn(
      tester,
      find
          .descendant(
            of: find.byType(Wrap),
            matching: find.byTooltip('#FF6B5A'),
          )
          .first,
    );
    expect(icon().glyphColor, const Color(0xFFFF6B5A));

    // A solid background, from the gradient it was.
    await tapOn(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('bg-kind')),
        matching: find.text('Solid'),
      ),
    );
    await tapKey(tester, 'bg-solid-#EF4444');
    expect(
      icon().background,
      isA<SolidBackground>().having(
        (b) => b.color,
        'color',
        const Color(0xFFEF4444),
      ),
    );

    // A pattern, from the calm styles.
    await tapOn(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('bg-kind')),
        matching: find.text('Pattern'),
      ),
    );
    expect(icon().background, isA<PatternBackground>());
    await tapKey(tester, 'bg-pattern-aurora');
    expect((icon().background as PatternBackground).style, PatternStyle.aurora);

    // The inner shadow, on.
    await tapKey(tester, 'inner-shadow');
    expect(icon().innerShadow, isNotNull);

    // The preview shape, which no export carries.
    await tapOn(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('preview-corner')),
        matching: find.text('Circle'),
      ),
    );
    expect(icon().corner, IconCorner.circle);

    // A monogram instead of the glyph, back at the top of the list.
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('icon-page')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await settle(tester, frames: 2);
    await tapOn(tester, find.text('Monogram'));
    await tester.enterText(find.byKey(const ValueKey('monogram-text')), 'w');
    await settle(tester);
    expect(icon().foreground, const IconText('w'));
    await tapKey(tester, 'font-Poppins');
    expect(icon().foreground, const IconText('w', fontFamily: 'Poppins'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the guides go over the large preview', (tester) async {
    await pumpPage(tester, icon: _icon);
    IconGuides shown() => tester
        .widget<IconStage>(find.byKey(const ValueKey('icon-stage')))
        .guides;
    expect(shown(), IconGuides.off);
    await tester.tap(find.text('Android safe zone'));
    await settle(tester, frames: 2);
    expect(shown(), IconGuides.android);
    await tester.tap(find.text('iOS grid'));
    await settle(tester, frames: 2);
    expect(shown(), IconGuides.ios);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is IconGuidesPainter,
      ),
      findsOneWidget,
    );
  });

  testWidgets('previews the icon on home screens, at small sizes and in a '
      'store', (tester) async {
    await pumpPage(tester, icon: _icon);
    await tester.tap(find.text('Previews'));
    await settle(tester, frames: 4);
    for (final key in [
      'home-light',
      'home-dark',
      'home-tinted',
      'icon-sizes',
      'store-tile-light',
      'store-tile-dark',
      'store-tile-play',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)).first);
      await tester.pump();
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text('29 pt'), findsOneWidget);
    expect(find.text('60 pt'), findsOneWidget);
  });

  testWidgets('the tinted home screen tints the icon, not its wallpaper', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 232,
              height: 172,
              child: IconHomeScreen(
                icon: _icon,
                appName: 'Wayfare',
                look: HomeLook.tinted,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester, frames: 4);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (data!.buffer.asUint8List(), image.width);
    });
    final (rgba, width) = pixels!;
    int red(int x, int y) => rgba[(y * width + x) * 4];
    // Between the tiles the dark wallpaper shows, not the amber tint.
    expect(red(116, 4), lessThan(60));
    expect(red(4, 86), lessThan(60));
  });

  testWidgets('Remove icon takes the icon off the project, and Undo puts it '
      'back', (tester) async {
    final (container, id) = await pumpPage(tester, icon: _icon);
    await tester.tap(find.byTooltip('More'));
    await settle(tester, frames: 6);
    await tester.tap(find.text('Remove icon'));
    await settle(tester, frames: 6);
    expect(find.text('Remove the icon?'), findsOneWidget);
    await tester.tap(find.widgetWithText(StudioButton, 'Remove icon'));
    await settle(tester);
    expect(projectIn(container, id).icon, isNull);
    await tapKey(tester, 'icon-undo');
    expect(projectIn(container, id).icon, _icon);
  });

  group('the same in light and dark', () {
    testWidgets('every exported file is byte for byte the same', (
      tester,
    ) async {
      Future<Map<String, Uint8List>> exported(Page page) async {
        final (container, id) = page;
        final files = await tester.runAsync(
          () => buildIconFiles(projectIn(container, id)),
        );
        return {for (final f in files!) f.path: f.bytes};
      }

      // One project; only the app's theme changes between the two.
      final page = await pumpPage(tester, icon: _icon);
      final light = await exported(page);
      await pumpPage(tester, dark: true, reuse: page);
      final dark = await exported(page);

      expect(light.keys.toSet(), dark.keys.toSet());
      expect(
        light.keys.where((k) => k.endsWith('.png')),
        hasLength(IconExport.files.length),
      );
      for (final path in light.keys) {
        // listEquals: the default matcher walks megabytes one by one.
        expect(listEquals(light[path], dark[path]), isTrue, reason: path);
      }
    });

    testWidgets('the large preview paints the same pixels', (tester) async {
      Future<Uint8List> stagePixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .descendant(
                of: find.byKey(const ValueKey('icon-stage')),
                matching: find.byType(RepaintBoundary),
              )
              .first,
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        });
        return bytes!;
      }

      final page = await pumpPage(tester, icon: _icon);
      final light = await stagePixels();
      await pumpPage(tester, dark: true, reuse: page);
      final dark = await stagePixels();
      expect(light.length, dark.length);
      expect(light.length, greaterThan(10000));
      expect(listEquals(light, dark), isTrue);
    });
  });

  group('the ways in', () {
    testWidgets('the editor\'s project menu opens the page', (tester) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          frameCatalogProvider.overrideWith((ref) => _frames),
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
      final router = GoRouter(
        initialLocation: '/project/${project.id}',
        routes: [
          GoRoute(
            path: '/project/:id',
            builder: (_, state) =>
                EditorScreen(projectId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/project/:id/icon',
            builder: (_, state) =>
                IconStudioScreen(projectId: state.pathParameters['id']!),
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
      await settle(tester);
      await tester.tap(find.byTooltip('Project'));
      await settle(tester);
      await tester.tap(find.text('App icon'));
      await settle(tester);
      expect(find.byType(IconStudioScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('concept-0')), findsOneWidget);
    });
  });
}
