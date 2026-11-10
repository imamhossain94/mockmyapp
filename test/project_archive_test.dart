import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/repositories/font_library.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/host_face.dart';
import 'support/project_fixture.dart';
import 'package:path/path.dart' as p;

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

  setUp(() => tempDir = Directory.systemTemp.createTempSync('archive_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Writes a stand-in asset and returns its absolute path — the shape of the
  /// path a document actually stores.
  String writeAsset(String name, List<int> bytes) {
    final file = File(p.join(tempDir.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  Project projectWith({String? backgroundPath, String? screenshotPath}) =>
      projectOf(
        [
          ScreenDoc(
            id: 'screen-1',
            canvas: const Size(1179, 2556),
            background: backgroundPath == null
                ? const SolidBackground(Color(0xFF101010))
                : ImageBackground(backgroundPath),
            caption: const CaptionSpec(text: 'Hello', size: 64, lineHeight: 74),
            frames: [
              FramePlacement(
                deviceId: 'iphone-15',
                variantId: 'black',
                screenshot: ScreenshotSpec.of(screenshotPath),
              ),
            ],
          ),
        ],
        id: 'project-1',
        name: 'Acme',
        createdAt: DateTime.utc(2026, 7, 1),
      );

  group('bundle → read round trip', () {
    test('carries the document and every image it references', () async {
      final backgroundBytes = List<int>.generate(64, (i) => i);
      final screenshotBytes = List<int>.generate(32, (i) => 255 - i);
      final project = projectWith(
        backgroundPath: writeAsset('bg.png', backgroundBytes),
        screenshotPath: writeAsset('shot.jpg', screenshotBytes),
      );

      final bundle = ProjectArchive.read(await ProjectArchive.bundle(project));

      expect(bundle.project.name, 'Acme');
      expect(bundle.project.createdAt, DateTime.utc(2026, 7, 1));
      expect(bundle.project.allScreens.single.caption?.text, 'Hello');
      // The listing slot rides along with the pixels: a restored backup that
      // forgot which store target its screens were for would still open, and
      // would export to the wrong console.
      expect(bundle.project.subProjects.single.targetId, 'ios-iphone');
      expect(bundle.project.subProjects.single.canvas, const Size(1179, 2556));

      expect(bundle.images, hasLength(2));
      final byName = {for (final i in bundle.images) i.fileName: i};
      expect(byName['bg.png']!.bytes, backgroundBytes);
      expect(byName['bg.png']!.kind, LibraryImageKind.background);
      expect(byName['shot.jpg']!.bytes, screenshotBytes);
      expect(byName['shot.jpg']!.kind, LibraryImageKind.screenshot);
    });

    test('re-pointing the restored document reaches the new files', () async {
      final project = projectWith(
        backgroundPath: writeAsset('bg.png', [1, 2, 3]),
        screenshotPath: writeAsset('shot.png', [4, 5, 6]),
      );

      final bundle = ProjectArchive.read(await ProjectArchive.bundle(project));
      // Stand in for what ImageLibrary.importBytes hands back on the target
      // device: the same pixels under a brand-new name.
      final restored = ProjectArchive.remapImages(bundle.project, {
        'bg.png': '/new/device/library/uuid-a.png',
        'shot.png': '/new/device/library/uuid-b.png',
      });

      final screen = restored.allScreens.single;
      expect(
        (screen.background as ImageBackground).path,
        '/new/device/library/uuid-a.png',
      );
      expect(
        screen.frames.single.screenshot.imagePath,
        '/new/device/library/uuid-b.png',
      );
    });

    test('an image deleted from the library is skipped, not fatal', () async {
      final project = projectWith(
        backgroundPath: p.join(tempDir.path, 'never-written.png'),
        screenshotPath: writeAsset('shot.png', [9]),
      );

      final bundle = ProjectArchive.read(await ProjectArchive.bundle(project));

      expect(bundle.images.map((i) => i.fileName), ['shot.png']);
      // The dead reference survives untouched, so it keeps rendering as the
      // placeholder rather than silently becoming a different image.
      expect(
        (bundle.project.allScreens.single.background as ImageBackground).path,
        endsWith('never-written.png'),
      );
    });

    test('a project with no artwork still bundles', () async {
      final bundle = ProjectArchive.read(
        await ProjectArchive.bundle(projectWith()),
      );
      expect(bundle.images, isEmpty);
      expect(bundle.project.name, 'Acme');
    });
  });

  group('remapImages', () {
    test('leaves references it has no replacement for alone', () {
      final project = projectWith(
        backgroundPath: '/old/library/bg.png',
        screenshotPath: '/old/library/shot.png',
      );

      final remapped = ProjectArchive.remapImages(project, {
        'bg.png': '/new/library/uuid.png',
      });

      final screen = remapped.allScreens.single;
      expect(
        (screen.background as ImageBackground).path,
        '/new/library/uuid.png',
      );
      expect(
        screen.frames.single.screenshot.imagePath,
        '/old/library/shot.png',
      );
    });

    test('a screen with no image references is untouched', () {
      final project = projectWith();
      final remapped = ProjectArchive.remapImages(project, {'x.png': '/y.png'});
      expect(remapped.allScreens.single.background, isA<SolidBackground>());
      expect(
        remapped.allScreens.single.frames.single.screenshot.imagePath,
        isNull,
      );
    });

    test('a repointed backdrop keeps every adjustment made to it', () {
      final project = projectOf([
        const ScreenDoc(
          id: 'adjusted',
          background: ImageBackground(
            '/old/library/bg.png',
            fit: ImageBackgroundFit.contain,
            scale: 1.4,
            offsetX: 0.2,
            blur: 6,
            overlayColor: Color(0xFF00FF00),
            overlayOpacity: 0.3,
          ),
        ),
      ]);

      final moved =
          ProjectArchive.remapImages(project, {
                'bg.png': '/new/uuid.png',
              }).allScreens.single.background
              as ImageBackground;

      expect(moved.path, '/new/uuid.png');
      expect(moved.fit, ImageBackgroundFit.contain);
      expect(moved.scale, 1.4);
      expect(moved.offsetX, 0.2);
      expect(moved.blur, 6);
      expect(moved.overlayColor, const Color(0xFF00FF00));
      expect(moved.overlayOpacity, 0.3);
    });

    test('a photo display fill is bundled and repointed like a backdrop', () {
      final project = projectOf([
        const ScreenDoc(
          id: 'filled',
          frames: [
            FramePlacement(
              deviceId: 'iphone-15',
              variantId: 'black',
              screenshot: ScreenshotSpec(
                fill: ImageBackground('/old/library/fill.png', blur: 4),
              ),
            ),
          ],
        ),
      ]);

      expect(
        ProjectArchive.referencedImages(project).keys,
        contains('/old/library/fill.png'),
      );

      final moved =
          ProjectArchive.remapImages(project, {
                'fill.png': '/new/uuid.png',
              }).allScreens.single.frames.single.screenshot.fill
              as ImageBackground;

      expect(moved.path, '/new/uuid.png');
      expect(moved.blur, 4);
    });
  });

  group('read', () {
    test('accepts a bare JSON backup from before bundles existed', () {
      final json = utf8.encode(jsonEncode(projectWith().toJson()));
      final bundle = ProjectArchive.read(Uint8List.fromList(json));

      expect(bundle.project.name, 'Acme');
      expect(bundle.images, isEmpty);
    });

    test('rejects a zip that is not one of ours', () {
      final foreign = Archive()
        ..add(ArchiveFile.typedData('notes.txt', utf8.encode('hello')));
      final bytes = ZipEncoder().encodeBytes(foreign);

      expect(
        () => ProjectArchive.read(bytes),
        throwsA(
          isA<ProjectArchiveException>().having(
            (e) => e.message,
            'message',
            contains('not a MockMyApp backup'),
          ),
        ),
      );
    });

    test('rejects a backup written by a newer version', () {
      final future = Archive()
        ..add(
          ArchiveFile.typedData(
            'manifest.json',
            utf8.encode(
              jsonEncode({
                'format': 'mockup-studio-project',
                'version': 99,
                'images': const [],
              }),
            ),
          ),
        )
        ..add(
          ArchiveFile.typedData(
            'project.json',
            utf8.encode(jsonEncode(projectWith().toJson())),
          ),
        );

      expect(
        () => ProjectArchive.read(ZipEncoder().encodeBytes(future)),
        throwsA(
          isA<ProjectArchiveException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('rejects a file that is neither zip nor JSON', () {
      expect(
        () => ProjectArchive.read(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])),
        throwsA(isA<ProjectArchiveException>()),
      );
    });
  });

  group('referencedImages', () {
    test('dedupes a shared file and files it under screenshot', () {
      final shared = '/library/shared.png';
      final project = projectOf(
        [
          ScreenDoc(
            id: 's1',
            background: ImageBackground(shared),
            frames: [
              FramePlacement(
                deviceId: 'd',
                variantId: 'v',
                screenshot: ScreenshotSpec.of(shared),
              ),
            ],
          ),
          ScreenDoc(id: 's2', background: ImageBackground(shared)),
        ],
        id: 'p',
        name: 'n',
        createdAt: DateTime.utc(2026),
      );

      expect(ProjectArchive.referencedImages(project), {
        shared: LibraryImageKind.screenshot,
      });
    });
  });

  group('referencedFonts', () {
    /// A screen whose caption and one of its runs are set in [families].
    Project projectSetIn(String captionFamily, String runFamily) => projectOf(
      [
        ScreenDoc(
          id: 's1',
          canvas: const Size(1179, 2556),
          caption: CaptionSpec(
            text: 'Ship it fast',
            fontFamily: captionFamily,
            runs: [
              const CaptionRun('Ship '),
              CaptionRun('it', fontFamily: runFamily),
              const CaptionRun(' fast'),
            ],
          ),
        ),
      ],
      id: 'p',
      name: 'n',
      createdAt: DateTime.utc(2026),
    );

    test('finds an uploaded family on a caption and inside a run', () {
      // Both, because a run can override the family on its own — a headline in
      // the brand face with one word set in something else is exactly the
      // design this feature exists for, and packing only the caption's own
      // family would lose the word on the restoring device.
      expect(
        ProjectArchive.referencedFonts(projectSetIn('user:aaa', 'user:bbb')),
        {'user:aaa', 'user:bbb'},
      );
    });

    test('ignores Google families, which have nothing to pack', () {
      // They are fetched by name wherever the backup lands.
      expect(
        ProjectArchive.referencedFonts(projectSetIn('Poppins', 'Lobster')),
        isEmpty,
      );
    });
  });

  group(
    'a bundle carrying an uploaded typeface',
    () {
      final hostFace = readHostFace();

      late Directory fontsDir;
      late ProviderContainer container;

      setUp(() async {
        fontsDir = Directory.systemTemp.createTempSync('archive_fonts_test');
        FontLibrary.debugResetStorage();
        PathProviderPlatform.instance = _ScratchPathProvider(fontsDir.path);
        await FontLibrary.initialize();
        container = ProviderContainer();
      });

      tearDown(() {
        container.dispose();
        FontLibrary.debugResetStorage();
        try {
          fontsDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Leave it for the OS.
        }
      });

      Project projectInFamily(String family) => projectOf(
        [
          ScreenDoc(
            id: 'screen-1',
            canvas: const Size(1179, 2556),
            background: const SolidBackground(Color(0xFF101010)),
            caption: CaptionSpec(text: 'Hello', fontFamily: family),
          ),
        ],
        id: 'project-1',
        name: 'Acme',
        createdAt: DateTime.utc(2026, 7, 1),
      );

      test('ships the file, its id and its label', () async {
        final entry = await container
            .read(fontLibraryProvider.notifier)
            .importBytes(hostFace!, label: 'Brand Sans');

        final bytes = await ProjectArchive.bundle(
          projectInFamily(entry!.family),
        );
        final bundle = ProjectArchive.read(bytes);

        expect(bundle.fonts, hasLength(1));
        final font = bundle.fonts.single;
        expect(
          font.id,
          entry.id,
          reason: 'the id is what the document names, so it has to survive',
        );
        expect(font.label, 'Brand Sans');
        expect(font.fileName, entry.fileName);
        expect(font.bytes, hostFace);

        // And the document still names the same family: there is no remapFonts,
        // because a font is app-global and a second reference to one id is right.
        expect(
          bundle.project.allScreens.single.caption?.fontFamily,
          entry.family,
        );
      });

      test('does not bump the archive version to do it', () async {
        // A build shipped before fonts existed skips an unknown `fonts/`
        // directory and restores the project intact. Bumping the version would
        // instead make every one of those builds refuse the backup outright.
        final entry = await container
            .read(fontLibraryProvider.notifier)
            .importBytes(hostFace!, label: 'Brand Sans');

        final archive = ZipDecoder().decodeBytes(
          await ProjectArchive.bundle(projectInFamily(entry!.family)),
        );
        final manifest =
            jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content))
                as Map<String, dynamic>;

        expect(manifest['version'], 2);
        expect(manifest['fonts'], hasLength(1));
        expect((manifest['fonts'] as List).single['id'], entry.id);
        expect(archive.findFile('fonts/${entry.fileName}'), isNotNull);
      });

      test('packs nothing for a family this device never had', () async {
        // A project restored here from someone else's backup and then backed up
        // again. The reference stays in the document, so the day the file does
        // arrive under that id every caption using it resolves once more.
        final bytes = await ProjectArchive.bundle(
          projectInFamily('user:never-seen'),
        );
        final bundle = ProjectArchive.read(bytes);

        expect(bundle.fonts, isEmpty);
        expect(
          bundle.project.allScreens.single.caption?.fontFamily,
          'user:never-seen',
        );
      });
    },
    skip: readHostFace() == null
        ? 'no readable system font on this machine'
        : null,
  );

  group('a bundle from before fonts existed', () {
    test('restores with an empty font list rather than failing', () {
      // The reverse of the version argument: a manifest with no `fonts` key at
      // all is every backup taken up to now, and every one of them still has to
      // open.
      final archive = Archive()
        ..add(
          ArchiveFile.typedData(
            'manifest.json',
            utf8.encode(
              jsonEncode({
                'format': 'mockup-studio-project',
                'version': 2,
                'images': const [],
              }),
            ),
          ),
        )
        ..add(
          ArchiveFile.typedData(
            'project.json',
            utf8.encode(jsonEncode(projectWith().toJson())),
          ),
        );

      final bundle = ProjectArchive.read(ZipEncoder().encodeBytes(archive));

      expect(bundle.fonts, isEmpty);
      expect(bundle.project.name, 'Acme');
    });
  });
}
