// The AI background surfaces as they lay out — the art direction panel — at
// a 390pt phone and on a desktop, in light and in dark; how the editor
// reaches them (the AI library on the rail, the AI section of the Background
// tool); and an image panorama exporting the same bytes whatever the app's
// theme.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';
import 'package:mockmyapp/features/ai_backgrounds/ai_background_panel.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

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

/// A sunset ramp standing in for a photo.
Uint8List _gradient(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var x = 0; x < width; x++) {
    final t = x / (width - 1);
    for (var y = 0; y < height; y++) {
      final v = y / (height - 1);
      image.setPixelRgb(
        x,
        y,
        (40 + 200 * t).round(),
        (60 + 80 * v).round(),
        (180 - 120 * t).round(),
      );
    }
  }
  return img.encodePng(image);
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ai_background_ui_test');
    ImageLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await ImageLibrary.initialize();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left to the OS.
    }
  });

  group('the panel lays out', () {
    for (final dark in [false, true]) {
      for (final (name, size, pane) in [
        ('a 390pt phone', const Size(390, 844), 390.0),
        ('a desktop pane', const Size(1440, 900), 360.0),
      ]) {
        testWidgets('on $name, ${dark ? 'dark' : 'light'}', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: dark ? StudioAppTheme.dark() : StudioAppTheme.light(),
                builder: StudioLayoutScope.wrap,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: pane,
                      child: AiBackgroundPanel(
                        padding: const EdgeInsets.all(16),
                        host: AiBackgroundHost(
                          projectId: 'p1',
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
                  ),
                ),
              ),
            ),
          );
          await _settle(tester);
          // Suggestions as well, the widest part.
          final suggest = find.byKey(const ValueKey('art-device'));
          await tester.ensureVisible(suggest);
          await tester.tap(suggest);
          await _settle(tester);
          expect(find.text('Built-in suggestions'), findsOneWidget);
          expect(find.byKey(const ValueKey('suggestion-0')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('in the editor', () {
    Future<ProviderContainer> pumpEditor(
      WidgetTester tester,
      Size size, {
      int screens = 1,
    }) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => _catalog)],
      );
      addTearDown(container.dispose);
      final store = container.read(projectStoreProvider.notifier);
      final Project project = store.createProject(
        name: 'Wayfare',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );
      SubProject sub() =>
          container.read(projectStoreProvider).first.subProjects.single;
      while (sub().screens.length < screens) {
        store.addScreen(project.id, sub().id);
      }
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
      await _settle(tester);
      return container;
    }

    testWidgets('the phone\'s tab bar has an AI library', (tester) async {
      await pumpEditor(tester, const Size(390, 844));
      final tab = find.descendant(
        of: find.byType(StudioTabStrip),
        matching: find.byTooltip('AI'),
      );
      await tester.ensureVisible(tab);
      await tester.pump();
      await tester.tap(tab);
      await _settle(tester);
      expect(find.byKey(const ValueKey('ai-brief')), findsOneWidget);
      expect(find.text('ART DIRECTION'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the desktop rail has it, and the Background tool an AI '
        'section', (tester) async {
      await pumpEditor(tester, const Size(1440, 900), screens: 3);
      await tester.tap(find.byTooltip('AI'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('ai-brief')), findsOneWidget);
      // A set of three can take one pattern across all of it.
      expect(find.byKey(const ValueKey('art-spread')), findsOneWidget);
      expect(find.text('Across all 3 screens'), findsOneWidget);

      await tester.tap(find.byTooltip('Background'));
      await _settle(tester);
      await tester.tap(find.text('AI').last);
      await _settle(tester);
      expect(find.byKey(const ValueKey('ai-brief')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an image panorama exports the same bytes in light and dark', (
    tester,
  ) async {
    final path = '${tempDir.path}/sunset.png';
    File(path).writeAsBytesSync(_gradient(600, 400));
    await tester.runAsync(() async {
      final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener((_, _) {
        stream.removeListener(listener);
        done.complete();
      }, onError: (_, _) => done.complete());
      stream.addListener(listener);
      await done.future;
    });
    final set = [
      for (final id in ['a', 'b', 'c'])
        ScreenDoc(
          id: id,
          canvas: const Size(400, 800),
          background: ImageBackground(path, slices: 3, blur: 0.01),
        ),
    ];

    Future<Uint8List> render(ThemeData theme) async {
      final key = GlobalKey();
      final composed = composeScreen(set, 1, continuous: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: SceneRenderer.captureStage(
                boundaryKey: key,
                doc: composed.doc,
                catalog: _catalog,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    final light = await render(StudioAppTheme.light());
    final dark = await render(StudioAppTheme.dark());
    expect(light, dark);
  });
}
