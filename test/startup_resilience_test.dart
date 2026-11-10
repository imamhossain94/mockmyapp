import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';

/// A platform with no documents directory — what the web actually is.
///
/// `path_provider` ships no web implementation, so the call does not return
/// empty, it throws `MissingPluginException` off the method channel.
class _NoStoragePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    throw MissingPluginException(
      'No implementation found for method getApplicationDocumentsDirectory '
      'on channel plugins.flutter.io/path_provider',
    );
  }

  @override
  Future<String?> getTemporaryPath() async =>
      throw MissingPluginException('no temporary directory either');
}

/// A platform whose documents directory is a real folder.
class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Runs [body], collecting anything it reports through [FlutterError].
///
/// `initialize` reports rather than rethrows, and an unhandled report fails the
/// surrounding test — so the assertion that it *was* reported has to intercept
/// it.
Future<List<Object>> collectingErrors(Future<void> Function() body) async {
  final reported = <Object>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => reported.add(details.exception);
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('startup survives a platform with no storage', () {
    test('initialize completes instead of throwing', () async {
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _NoStoragePathProvider();

      // The bug this pins: `main` awaits this call before `runApp`, so anything
      // thrown here means no frame is ever painted. On the web that leaves the
      // splash on screen forever, because Flutter's first frame is the only
      // thing that removes it — an app that hangs with nothing to explain it.
      final reported = await collectingErrors(ImageLibrary.initialize);

      expect(
        reported.single,
        isA<MissingPluginException>(),
        reason: 'reported, not swallowed — losing the folder is a real fault',
      );
      expect(ImageLibrary.isAvailable, isFalse);
    });

    test('and resolve stays usable with no library folder', () async {
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _NoStoragePathProvider();
      await collectingErrors(ImageLibrary.initialize);

      // Must not reach `dart:io` at all: on the web every File operation is a
      // stub that throws, so the emptiness check has to come first.
      expect(ImageLibrary.resolve('/gone/shot.png'), '/gone/shot.png');
      expect(ImageLibrary.resolve(''), '');
    });

    testWidgets('an import still works and still renders', (tester) async {
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _NoStoragePathProvider();
      await collectingErrors(ImageLibrary.initialize);
      expect(ImageLibrary.isAvailable, isFalse);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The reported failure: importing on the web threw
      // `Unsupported operation: _Namespace` — `dart:io`'s stub throwing from
      // the `File` constructor, before a single byte was written.
      final entry = await container
          .read(imageLibraryProvider.notifier)
          .importBytes(
            Uint8List.fromList([1, 2, 3, 4]),
            projectId: 'web-project',
            kind: LibraryImageKind.screenshot,
          );

      expect(entry.projectId, 'web-project');
      expect(
        ImageLibrary.sessionBytes(entry.path),
        [1, 2, 3, 4],
        reason: 'with nowhere to write, the bytes are kept for the session',
      );
      expect(
        container
            .read(imageLibraryProvider.notifier)
            .forProject('web-project', LibraryImageKind.screenshot),
        hasLength(1),
      );

      // An import schedules the index write on a 300ms debounce. It is a no-op
      // with no folder to write to, but the timer still has to elapse or the
      // binding reports it as leaked.
      await tester.pump(const Duration(milliseconds: 400));
    });

    test('and a real documents directory still works', () async {
      final temp = Directory.systemTemp.createTempSync('startup_test');
      addTearDown(() {
        try {
          temp.deleteSync(recursive: true);
        } on FileSystemException {
          // Leave it for the OS.
        }
      });
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _ScratchPathProvider(temp.path);

      final reported = await collectingErrors(ImageLibrary.initialize);

      expect(reported, isEmpty);
      expect(ImageLibrary.isAvailable, isTrue);
      expect(Directory(ImageLibrary.directoryPath).existsSync(), isTrue);

      // And the path repair it exists for still happens. Joined rather than
      // interpolated, so the separator is the platform's own.
      final moved = File(p.join(ImageLibrary.directoryPath, 'shot.png'))
        ..writeAsStringSync('x');
      expect(
        ImageLibrary.resolve(p.join('an', 'old', 'container', 'shot.png')),
        moved.path,
        reason: 'a stale absolute path is repaired by leaf name',
      );
    });
  });
}
