// What the store does with a screen that holds more than one device.
//
// Both of these were silent losses rather than crashes. A set built as two
// phones side by side is a composition somebody arranged once; a store
// operation that quietly kept only the first device — or only the screenshot
// that happened to be showing — undoes that work without saying anything.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

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

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('multi_device_store_test');
    ImageLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await ImageLibrary.initialize();
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

  ProjectStore store() => container.read(projectStoreProvider.notifier);
  Project byId(String id) =>
      container.read(projectStoreProvider).firstWhere((p) => p.id == id);

  Project make() => store().createProject(
    name: 'Listing',
    targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
    initialDeviceId: 'apple-iphone-16',
    initialVariantId: '16---ultramarine',
  );

  List<ScreenDoc> screensOf(Project p) => byId(p.id).subProjects.first.screens;

  /// Puts a second device on every screen of [p].
  void addSecondDevice(Project p) {
    for (final screen in screensOf(p)) {
      store().updateScreen(
        p.id,
        screen.addFrame(
          const FramePlacement(
            deviceId: 'google-pixel-9-pro',
            variantId: 'obsidian',
          ),
        ),
      );
    }
  }

  group('a new screen joins the composition', () {
    test('it inherits every device, not just the first', () {
      final project = make();
      addSecondDevice(project);

      final added = store().addScreen(
        project.id,
        byId(project.id).subProjects.first.id,
      );

      expect(added.frames, hasLength(2));
      expect(added.frames.map((f) => f.deviceId), [
        'apple-iphone-16',
        'google-pixel-9-pro',
      ]);
    });

    test('it inherits the framing but none of the pictures', () {
      final project = make();
      // The LAST screen: a new one inherits the set's most recent look, which
      // is the one the user was just working on.
      final source = screensOf(project).last;
      store().updateScreen(
        project.id,
        source.updateFrame(
          0,
          (f) => f.copyWith(
            screenshot: f.screenshot.copyWith(
              imagePath: '/a.png',
              cornerRadiusPct: 0.11,
            ),
          ),
        ),
      );

      final added = store().addScreen(
        project.id,
        byId(project.id).subProjects.first.id,
      );

      expect(added.frames.first.screenshot.images, isEmpty);
      expect(added.frames.first.screenshot.cornerRadiusPct, 0.11);
    });
  });

  group('applying a look across the set', () {
    /// The op the editor calls "use this screen's look everywhere".
    void applyLook(Project p) =>
        store().applyStyleToAll(p.id, screensOf(p).first.id);

    test('every device survives on every screen', () {
      // It used to replace the whole `frames` list with one frame, which threw
      // away the second device on every screen the look reached.
      final project = make();
      addSecondDevice(project);

      applyLook(project);

      for (final screen in screensOf(project)) {
        expect(screen.frames, hasLength(2), reason: screen.id);
      }
    });

    test('each screen keeps its own pictures, all of them', () {
      final project = make();
      final screens = screensOf(project);
      expect(screens.length, greaterThan(1), reason: 'needs a second screen');

      // The second screen carries a set of three; only one of them is showing.
      store().updateScreen(
        project.id,
        screens[1].updateFrame(
          0,
          (f) => f.copyWith(
            screenshot: const ScreenshotSpec(
              images: ['/a.png', '/b.png', '/c.png'],
              index: 1,
            ),
          ),
        ),
      );

      applyLook(project);

      final shot = screensOf(project)[1].frames.first.screenshot;
      expect(
        shot.images,
        ['/a.png', '/b.png', '/c.png'],
        reason: 'copying only the active capture drops the alternates',
      );
      expect(shot.activeIndex, 1, reason: 'and which one was showing');
    });

    test('a screen with fewer devices gains the missing one, empty', () {
      final project = make();
      final screens = screensOf(project);
      // Only the source screen gets a second device.
      store().updateScreen(
        project.id,
        screens.first.addFrame(
          const FramePlacement(
            deviceId: 'google-pixel-9-pro',
            variantId: 'obsidian',
          ),
        ),
      );

      applyLook(project);

      final other = screensOf(project)[1];
      expect(other.frames, hasLength(2));
      expect(
        other.frames[1].screenshot.images,
        isEmpty,
        reason: 'there was no picture on this screen for it to keep',
      );
    });
  });
}
