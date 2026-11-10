import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

Uint8List pngish(String tag) => Uint8List.fromList(tag.codeUnits);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('library_scope_test');
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
      // Leave it for the OS.
    }
  });

  ImageLibrary library() => container.read(imageLibraryProvider.notifier);

  group('an imported image belongs to one project', () {
    test('and does not appear in another', () async {
      final mine = await library().importBytes(
        pngish('a'),
        projectId: 'project-a',
        kind: LibraryImageKind.background,
      );
      await library().importBytes(
        pngish('b'),
        projectId: 'project-b',
        kind: LibraryImageKind.background,
      );

      final forA = library().forProject(
        'project-a',
        LibraryImageKind.background,
      );
      expect(forA.map((e) => e.id), [mine.id]);

      final forB = library().forProject(
        'project-b',
        LibraryImageKind.background,
      );
      expect(forB, hasLength(1));
      expect(forB.single.id, isNot(mine.id));
    });

    test('and the kind filter still applies within a project', () async {
      await library().importBytes(
        pngish('bg'),
        projectId: 'p',
        kind: LibraryImageKind.background,
      );
      final shot = await library().importBytes(
        pngish('shot'),
        projectId: 'p',
        kind: LibraryImageKind.screenshot,
      );

      final shots = library().forProject('p', LibraryImageKind.screenshot);
      expect(shots.map((e) => e.id), [shot.id]);
    });

    test('entries from before the split are still reachable everywhere', () {
      // Written by a version that had one library for the whole app. Hiding
      // them would strand artwork the user already has, so they show up in
      // every project until they are replaced.
      final legacy = LibraryImage.fromJson({
        'id': 'old',
        'fileName': 'old.png',
        'kind': 'background',
        'addedAt': DateTime.now().toIso8601String(),
      });
      expect(legacy.projectId, isNull);

      container.read(imageLibraryProvider.notifier).state = [legacy];
      expect(
        library().forProject('anything', LibraryImageKind.background),
        hasLength(1),
      );
      expect(
        library().forProject('something-else', LibraryImageKind.background),
        hasLength(1),
      );
    });

    test('ownership survives the round trip through storage', () {
      final entry = LibraryImage(
        id: 'x',
        fileName: 'x.png',
        kind: LibraryImageKind.screenshot,
        addedAt: DateTime.now(),
        projectId: 'project-a',
      );
      final restored = LibraryImage.fromJson(entry.toJson());
      expect(restored.projectId, 'project-a');
    });
  });
}
