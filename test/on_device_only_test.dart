// MockMyApp is free and runs on the device: there is no account, no Cloud AI,
// no purchase and no watermark. Every surface that once had a cloud or a paid
// part is pumped here, and none of them may speak of one — no credits, no
// sign-in, no Pro, no Lifetime, no "isn't set up".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/icons/lucide_glyphs.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/ai_backgrounds/ai_background_panel.dart';
import 'package:mockmyapp/features/ai_generate/ai_generate_screen.dart';
import 'package:mockmyapp/features/icon_studio/icon_studio_screen.dart';
import 'package:mockmyapp/features/settings/settings_screen.dart';
import 'package:mockmyapp/features/shared/save_actions.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';
import 'package:mockmyapp/features/store_copy/store_copy_screen.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

final FrameCatalog _frames = frameCatalogFromManifest(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

final ElementCatalog _elements = ElementCatalog.fromJson(
  elements:
      jsonDecode(File('assets/elements/elements.json').readAsStringSync())
          as Map<String, dynamic>,
  icons:
      jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
          as Map<String, dynamic>,
);

const _brief = ListingBrief(
  appName: 'Wayfare',
  description:
      'Wayfare plans trips: every booking, map and ticket in one place, with '
      'maps that work offline. Available on iPhone and Android.',
  category: TemplateCategory.travel,
  keywords: ['trip planner', 'itinerary', 'travel'],
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

/// What no surface may say.
final _forbidden = <Pattern>[
  'Cloud AI',
  RegExp('credit', caseSensitive: false),
  RegExp('sign in', caseSensitive: false),
  // "No account" is what Settings promises; anything that manages one is not.
  RegExp('your account|delete account|sign out', caseSensitive: false),
  "isn't set up",
  RegExp(r'\bPro\b'),
  RegExp('lifetime', caseSensitive: false),
  RegExp('watermark', caseSensitive: false),
  RegExp('purchase', caseSensitive: false),
  RegExp('subscri', caseSensitive: false),
];

/// Whether [text] says any of [_forbidden].
bool _saysForbidden(String text) => _forbidden.any((p) => text.contains(p));

/// Fails if any text or tooltip on screen says one of [_forbidden].
void _expectNothingForbidden(WidgetTester tester) {
  for (final pattern in _forbidden) {
    expect(find.textContaining(pattern), findsNothing, reason: '$pattern');
  }
  final tooltips = tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((t) => t.message ?? '')
      .where(_saysForbidden)
      .toList();
  expect(tooltips, isEmpty);
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A tall phone, so lazily built lists build every row at once.
void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 3000) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() => LucideGlyphs.debugUse(_elements.icons));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('on_device_only_test');
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

  /// A container with a project carrying [_brief] and [_icon].
  (ProviderContainer, String) project() {
    final container = ProviderContainer(
      overrides: [
        frameCatalogProvider.overrideWith((ref) => _frames),
        elementCatalogProvider.overrideWith((ref) => _elements),
      ],
    );
    addTearDown(container.dispose);
    final store = container.read(projectStoreProvider.notifier);
    final p = store.createProject(
      name: 'Wayfare',
      targets: [
        (
          targetId: StoreTargets.iphone.id,
          presetId: StoreTargets.iphone.defaultPreset.id,
        ),
      ],
    );
    store.setListingBrief(p.id, _brief);
    store.setIcon(p.id, _icon);
    return (container, p.id);
  }

  Future<void> pump(
    WidgetTester tester,
    ProviderContainer container,
    Widget home,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: StudioAppTheme.light(),
          builder: StudioLayoutScope.wrap,
          home: home,
        ),
      ),
    );
    await _settle(tester);
  }

  testWidgets('the AI wizard analyses on this device', (tester) async {
    _tallPhone(tester);
    final (container, _) = project();
    await pump(tester, container, AiGenerateScreen(onGenerated: (_) {}));

    expect(find.byKey(const ValueKey('device-analysis')), findsOneWidget);
    _expectNothingForbidden(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('ai-description')),
        matching: find.byType(EditableText),
      ),
      _brief.description,
    );
    await _settle(tester);
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('aso-score')), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-source')), findsOneWidget);
    _expectNothingForbidden(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the store copy page writes and translates on this device', (
    tester,
  ) async {
    _tallPhone(tester);
    final (container, id) = project();
    await pump(tester, container, StoreCopyScreen(projectId: id));

    expect(find.text('Draft with AI · On this device'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-engine-line')), findsOneWidget);
    _expectNothingForbidden(tester);

    await tester.tap(find.byKey(const ValueKey('draft-all')));
    await _settle(tester);
    expect(
      find.textContaining('with the built-in suggestions'),
      findsOneWidget,
    );
    _expectNothingForbidden(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the backgrounds panel is art direction, on this device', (
    tester,
  ) async {
    _tallPhone(tester);
    final (container, id) = project();
    await pump(
      tester,
      container,
      Scaffold(
        body: AiBackgroundPanel(
          padding: const EdgeInsets.all(16),
          host: AiBackgroundHost(
            projectId: id,
            projectName: 'Wayfare',
            screenId: 'screen-1',
            screenCount: 5,
            canvas: const Size(1290, 2796),
            continuous: true,
            current: kDefaultBackground,
            palette: const [Color(0xFF0B3D4C), Color(0xFFFF6B5A)],
            onApply: (_) {},
            onSpread: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('art-device')), findsOneWidget);
    expect(
      find.textContaining(RegExp('generate', caseSensitive: false)),
      findsNothing,
    );
    _expectNothingForbidden(tester);

    await tester.tap(find.byKey(const ValueKey('art-device')));
    await _settle(tester);
    expect(find.text('Built-in suggestions'), findsOneWidget);
    _expectNothingForbidden(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the icon studio makes glyph concepts on this device', (
    tester,
  ) async {
    // The desktop inspector lists every panel at once.
    tester.view.physicalSize = const Size(1440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (container, id) = project();
    await pump(tester, container, IconStudioScreen(projectId: id));

    expect(find.byKey(const ValueKey('suggest-concepts')), findsOneWidget);
    expect(find.byKey(const ValueKey('icon-mark-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-background')), findsNothing);
    _expectNothingForbidden(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings has no account, plan or AI group', (tester) async {
    _tallPhone(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pump(tester, container, const SettingsScreen());

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
    expect(
      find.textContaining('MIT License', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining(RegExp('ai & privacy', caseSensitive: false)),
      findsNothing,
    );
    expect(find.textContaining('Restore'), findsNothing);
    _expectNothingForbidden(tester);

    // The source code is a link to copy, not one to open: the app starts no
    // request of its own.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    expect(find.text('github.com/imamhossain94/mockmyapp'), findsOneWidget);
    await tester.tap(find.text('Source code'));
    await _settle(tester);
    expect(copied, kSourceCodeUrl);
    expect(find.text('Link copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the save sheet offers destinations and nothing to buy', (
    tester,
  ) async {
    _tallPhone(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pump(
      tester,
      container,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: StudioButton(
              label: 'Save',
              onPressed: () => askSaveDestination(
                context,
                title: 'Export 5 screenshots',
                fileName: 'Wayfare 01.png',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('Wayfare 01.png'), findsOneWidget);
    expect(find.text('Share…'), findsOneWidget);
    _expectNothingForbidden(tester);
    expect(tester.takeException(), isNull);
  });
}
