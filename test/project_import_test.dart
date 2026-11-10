import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/repositories/font_library.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

import 'support/host_face.dart';
import 'support/project_fixture.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points the app's documents directory at a scratch folder so the library and
/// the project file can be written for real.
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

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('import_test');
    // The resolved folder is static and outlives a single case, so a new
    // scratch directory has to be announced or the library keeps writing into
    // the one the previous case already deleted.
    ImageLibrary.debugResetStorage();
    FontLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await ImageLibrary.initialize();
    await FontLibrary.initialize();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// A backup taken on some *other* device: the paths inside point at a
  /// container this device has never seen.
  Future<List<int>> foreignBackup({
    required String screenshotFileName,
    required List<int> screenshotBytes,
  }) async {
    // Written where the source device's library would have been.
    final sourceLibrary = Directory(p.join(tempDir.path, 'other-device'))
      ..createSync();
    final sourcePath = p.join(sourceLibrary.path, screenshotFileName);
    File(sourcePath).writeAsBytesSync(screenshotBytes);

    final bytes = await ProjectArchive.bundle(
      projectOf(
        [
          ScreenDoc(
            id: 'screen-1',
            background: const SolidBackground(Color(0xFF101010)),
            frames: [
              FramePlacement(
                deviceId: 'iphone-16',
                variantId: 'black',
                screenshot: ScreenshotSpec.of(sourcePath),
              ),
            ],
          ),
        ],
        id: 'source-id',
        name: 'Acme',
        createdAt: DateTime.utc(2026, 7, 1),
      ),
    );

    // The source device is now gone, exactly as it would be for a real user.
    sourceLibrary.deleteSync(recursive: true);
    return bytes;
  }

  test('a backup restored beside its original is told apart by name', () async {
    final backup = await foreignBackup(
      screenshotFileName: 'source-uuid.png',
      screenshotBytes: List<int>.generate(16, (i) => i),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(projectStoreProvider.notifier);

    final first = await store.importProject(Uint8List.fromList(backup));
    final second = await store.importProject(Uint8List.fromList(backup));
    final third = await store.importProject(Uint8List.fromList(backup));

    expect([first.name, second.name, third.name], ['Acme', 'Acme 2', 'Acme 3']);
  });

  test('importing a bundle lands the artwork on this device', () async {
    final pixels = List<int>.generate(48, (i) => i * 5 % 256);
    final backup = await foreignBackup(
      screenshotFileName: 'source-uuid.png',
      screenshotBytes: pixels,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final project = await container
        .read(projectStoreProvider.notifier)
        .importProject(Uint8List.fromList(backup));

    expect(project.name, 'Acme');
    expect(project.id, isNot('source-id'), reason: 'imports get a fresh id');

    final restoredPath =
        project.allScreens.single.frames.single.screenshot.imagePath;
    expect(restoredPath, isNotNull);

    // The document must point at a file that exists *here*, holding the
    // original pixels — the whole reason backups became bundles.
    expect(
      p.dirname(restoredPath!),
      ImageLibrary.directoryPath,
      reason: 'restored artwork must live in this device\'s library',
    );
    expect(File(restoredPath).existsSync(), isTrue);
    expect(File(restoredPath).readAsBytesSync(), pixels);

    // And it is a real library entry, so it shows up in the image picker.
    final library = container.read(imageLibraryProvider);
    expect(library.single.fileName, p.basename(restoredPath));
    expect(library.single.kind, LibraryImageKind.screenshot);
  });

  test('importing the same backup twice does not share one file', () async {
    final backup = await foreignBackup(
      screenshotFileName: 'source-uuid.png',
      screenshotBytes: const [1, 2, 3, 4],
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(projectStoreProvider.notifier);

    final first = await store.importProject(Uint8List.fromList(backup));
    final second = await store.importProject(Uint8List.fromList(backup));

    String pathOf(Project pr) =>
        pr.allScreens.single.frames.single.screenshot.imagePath!;

    expect(pathOf(first), isNot(pathOf(second)));
    expect(File(pathOf(first)).readAsBytesSync(), const [1, 2, 3, 4]);
    expect(File(pathOf(second)).readAsBytesSync(), const [1, 2, 3, 4]);
    expect(container.read(projectStoreProvider), hasLength(2));
  });

  test('a bad file is refused with a message worth showing', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(projectStoreProvider.notifier)
          .importProject(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])),
      throwsA(isA<ProjectArchiveException>()),
    );
    expect(container.read(projectStoreProvider), isEmpty);
  });

  group(
    'a backup carrying an uploaded typeface',
    () {
      final hostFace = readHostFace();

      /// A backup of a project set in a font this device then loses, and the id
      /// that font was held under.
      Future<(Uint8List, String)> backupInAnUploadedFont(
        ProviderContainer container,
      ) async {
        final fonts = container.read(fontLibraryProvider.notifier);
        final entry = await fonts.importBytes(hostFace!, label: 'Brand Sans');

        final bytes = await ProjectArchive.bundle(
          projectOf(
            [
              ScreenDoc(
                id: 'screen-1',
                caption: CaptionSpec(text: 'Hello', fontFamily: entry!.family),
              ),
            ],
            id: 'source-id',
            name: 'Acme',
            createdAt: DateTime.utc(2026, 7, 1),
          ),
        );

        // The typeface is gone from this device — which is what a backup opened
        // on a second phone, or after a reinstall, actually looks like.
        await fonts.remove(entry.id);
        expect(FontLibrary.isRegistered(entry.family), isFalse);

        return (bytes, entry.id);
      }

      test('restores the face under the id the document names', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final (backup, fontId) = await backupInAnUploadedFont(container);
        final project = await container
            .read(projectStoreProvider.notifier)
            .importProject(backup);

        // Not re-pointed and not re-minted: unlike an image, a typeface is
        // app-global, so the id inside project.json is already the id this
        // device will resolve.
        expect(
          project.allScreens.single.caption?.fontFamily,
          FontLibrary.familyFor(fontId),
        );
        expect(container.read(fontLibraryProvider).single.id, fontId);
        expect(container.read(fontLibraryProvider).single.label, 'Brand Sans');
        expect(
          FontLibrary.isRegistered(FontLibrary.familyFor(fontId)),
          isTrue,
          reason: 'the restored caption has to paint in its own face',
        );
      });

      test('restoring it twice leaves one font and two projects', () async {
        // The mirror of what images do on purpose. A picture is copied per
        // project so clearing one cannot blank another; a typeface is shared, so
        // duplicating it would just put the same name in the picker twice.
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final (backup, fontId) = await backupInAnUploadedFont(container);
        final store = container.read(projectStoreProvider.notifier);
        await store.importProject(backup);
        await store.importProject(backup);

        expect(container.read(projectStoreProvider), hasLength(2));
        expect(container.read(fontLibraryProvider).map((e) => e.id), [fontId]);
      });
    },
    skip: readHostFace() == null
        ? 'no readable system font on this machine'
        : null,
  );
}
