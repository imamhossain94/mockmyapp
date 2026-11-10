import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/graphics_archive.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/export_settings.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';

// Export: format, resolution, the store sizes, and the Download menu.

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

/// A 4×2 picture: the left half opaque red, the right half fully transparent.
Future<ui.Image> halfTransparent() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = const Color(0xFFFF0000),
  );
  return recorder.endRecording().toImage(4, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encoding', () {
    testWidgets('JPG is a real JPEG, flattened onto white', (tester) async {
      await tester.runAsync(() async {
        final image = await halfTransparent();
        final bytes = await encodeExport(
          image,
          const ExportSettings(format: ExportFormat.jpg, jpegQuality: 100),
        );
        image.dispose();
        expect(bytes!.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG magic');

        final decoded = img.decodeJpg(bytes)!;
        final clear = decoded.getPixel(3, 1);
        expect(clear.r, greaterThan(240), reason: 'transparent became white');
        expect(clear.g, greaterThan(240));
        final red = decoded.getPixel(0, 0);
        expect(red.r, greaterThan(200));
        expect(red.g, lessThan(60));
      });
    });

    testWidgets('PNG stays PNG', (tester) async {
      await tester.runAsync(() async {
        final image = await halfTransparent();
        final bytes = await encodeExport(image, const ExportSettings());
        image.dispose();
        expect(bytes!.sublist(1, 4), utf8.encode('PNG'));
      });
    });

    testWidgets('PNG is 24-bit, flattened onto white', (tester) async {
      // Google Play asks for "JPEG or 24-bit PNG (no alpha)", and the engine
      // only writes 32-bit.
      await tester.runAsync(() async {
        final image = await halfTransparent();
        final bytes = await encodeExport(image, const ExportSettings());
        image.dispose();
        expect(bytes![25], 2, reason: 'IHDR colour type 2: RGB, no alpha');

        final decoded = img.decodePng(bytes)!;
        expect(decoded.numChannels, 3);
        final clear = decoded.getPixel(3, 1);
        expect(clear.r, 255, reason: 'transparent became white');
        expect(clear.g, 255);
        final red = decoded.getPixel(0, 0);
        expect([red.r, red.g, red.b], [255, 0, 0]);
      });
    });
  });

  group('archives', () {
    test('name each file by its format', () {
      final zip = GraphicsArchive.bundleSets(
        projectName: 'App',
        sets: [
          (
            folder: 'iPhone',
            scenes: [
              RenderedScene(
                index: 0,
                doc: const ScreenDoc(id: 's'),
                bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
                format: ExportFormat.jpg,
              ),
            ],
          ),
        ],
      );
      final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name);
      expect(names.single, endsWith('01.jpg'));
    });
  });

  group('settings', () {
    test('are remembered between launches', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(exportSettingsProvider.notifier)
          .set(const ExportSettings(format: ExportFormat.jpg, scale: 2));

      final again = ProviderContainer();
      addTearDown(again.dispose);
      again.read(exportSettingsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(again.read(exportSettingsProvider).format, ExportFormat.jpg);
      expect(again.read(exportSettingsProvider).scale, 2);
    });

    test('name themselves for the menu', () {
      expect(const ExportSettings().summary, 'PNG · 1×');
      expect(
        const ExportSettings(format: ExportFormat.jpg, scale: 0.5).summary,
        'JPG · 0.5×',
      );
    });
  });

  group('store sizes', () {
    test('every target and preset has an id of its own', () {
      final targets = StoreTargets.all.map((t) => t.id).toList();
      expect(targets.toSet().length, targets.length);
      final presets = [
        for (final t in StoreTargets.all)
          for (final p in t.presets) p.id,
      ];
      expect(presets.toSet().length, presets.length);
    });

    test('include the sizes the stores ask for', () {
      Size size(String target, String preset) =>
          StoreTargets.presetIn(target, preset)!.size;
      expect(size('ios-iphone', 'iphone-6-1'), const Size(1179, 2556));
      expect(size('ios-iphone', 'iphone-5-5'), const Size(1242, 2208));
      expect(size('apple-watch', 'watch-ultra'), const Size(410, 502));
      expect(size('apple-tv', 'tv-4k'), const Size(3840, 2160));
      expect(size('vision-pro', 'vision-4k'), const Size(3840, 2160));
      expect(
        size('huawei-phone', 'huawei-phone-portrait'),
        const Size(1080, 1920),
      );
      expect(
        size('android-tablet', 'android-tablet-7-wide'),
        const Size(1200, 1920),
      );
      expect(size('chromebook', 'chromebook-1080'), const Size(1920, 1080));
      expect(size('web', 'web-640'), const Size(640, 400));
    });

    test('a watch set starts without a phone around it', () {
      expect(StoreTargets.appleWatch.wearsDeviceFrame, isFalse);
      expect(StoreTargets.appleWatch.shortLabel, 'Apple Watch');
    });
  });

  group('the Download menu', () {
    late Directory tempDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('export_options_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    testWidgets('switches exports to JPG from its format entry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
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

      await tester.tap(find.byTooltip('Download'));
      await settle(tester);
      expect(find.text('Copy this screen'), findsOneWidget);
      await tester.tap(find.text('Format: PNG · 1×…'));
      await settle(tester);

      await tester.tap(find.text('JPG'));
      await settle(tester);
      await tester.tap(find.text('Use JPG · 1×'));
      await settle(tester);

      expect(container.read(exportSettingsProvider).format, ExportFormat.jpg);
      await tester.tap(find.byTooltip('Download'));
      await settle(tester);
      expect(find.text('This screen · JPG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
