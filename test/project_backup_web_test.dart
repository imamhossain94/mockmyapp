import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

import 'support/project_fixture.dart';

/// A platform with no documents directory — what the web actually is.
class _NoStoragePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw MissingPluginException('no documents directory');

  @override
  Future<String?> getTemporaryPath() async =>
      throw MissingPluginException('no temporary directory');
}

Project projectWith({String? backdrop, String? screenshot}) => projectOf(
  [
    ScreenDoc(
      id: 's1',
      canvas: const Size(1284, 2778),
      background: backdrop == null
          ? const SolidBackground(Color(0xFF000000))
          : ImageBackground(backdrop),
      frames: [
        FramePlacement(
          deviceId: 'd',
          variantId: 'v',
          screenshot: ScreenshotSpec.of(screenshot),
        ),
      ],
    ),
  ],
  id: 'p1',
  name: 'Listing',
  createdAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    ImageLibrary.debugResetStorage();
    PathProviderPlatform.instance = _NoStoragePathProvider();

    // Resolve once here with the failure absorbed. `initialize` reports a
    // missing documents directory exactly once per run, and an unhandled
    // report would fail whichever test happened to trigger it first.
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await ImageLibrary.initialize();
    FlutterError.onError = previous;

    container = ProviderContainer();
  });

  // A closure, not a tear-off: `container.dispose` would be resolved when the
  // callback is registered, before `setUp` has assigned it.
  tearDown(() => container.dispose());

  test('a backup bundles the artwork with no filesystem to read it', () async {
    final library = container.read(imageLibraryProvider.notifier);

    // Imported the way the web imports: bytes only, nowhere to write them.
    final shot = await library.importBytes(
      Uint8List.fromList([9, 8, 7]),
      projectId: 'p1',
      kind: LibraryImageKind.screenshot,
    );
    final backdrop = await library.importBytes(
      Uint8List.fromList([1, 2]),
      projectId: 'p1',
      kind: LibraryImageKind.background,
    );
    expect(ImageLibrary.isAvailable, isFalse);

    // The reported failure: this threw before producing anything, because it
    // read every referenced image through `File`.
    final bytes = await ProjectArchive.bundle(
      projectWith(backdrop: backdrop.path, screenshot: shot.path),
    );
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(
      archive.files.map((f) => f.name),
      containsAll(<String>[
        'images/${shot.fileName}',
        'images/${backdrop.fileName}',
        'project.json',
        'manifest.json',
      ]),
    );
    expect(
      archive.findFile('images/${shot.fileName}')!.content as List<int>,
      [9, 8, 7],
      reason: 'the session bytes made it into the zip',
    );

    // And it reads back as a restorable bundle.
    final restored = ProjectArchive.read(Uint8List.fromList(bytes));
    expect(restored.project.name, 'Listing');
    expect(restored.images, hasLength(2));
  });

  test('an image that has gone is skipped, not fatal', () async {
    final bytes = await ProjectArchive.bundle(
      projectWith(backdrop: 'never-imported.png'),
    );
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.findFile('project.json'), isNotNull);
    expect(
      archive.files.where((f) => f.name.startsWith('images/')),
      isEmpty,
      reason: 'a missing picture drops out; the backup is still worth having',
    );
  });
}
