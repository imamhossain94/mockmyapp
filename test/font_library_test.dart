import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/font_library.dart';

import 'support/host_face.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Bytes that open with [tag] and are long enough to pass the length check.
///
/// The padding is what makes these a fair test: [FontLibrary.looksLikeFont]
/// refuses anything under a kilobyte first, so a four-byte buffer would be
/// rejected for the wrong reason and prove nothing about the signature.
Uint8List headed(int tag, {int length = 2048}) {
  final bytes = Uint8List(length);
  bytes[0] = (tag >> 24) & 0xFF;
  bytes[1] = (tag >> 16) & 0xFF;
  bytes[2] = (tag >> 8) & 0xFF;
  bytes[3] = tag & 0xFF;
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hostFace = readHostFace();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('font_library_test');
    FontLibrary.debugResetStorage();
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    await FontLibrary.initialize();
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

  FontLibrary library() => container.read(fontLibraryProvider.notifier);

  /// Lets the 300 ms index debounce fire, so the next read sees it on disk.
  Future<void> settleIndex() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  group('the user: scheme', () {
    test('round-trips an id through a family name', () {
      const id = '0f3a7c1e-dead-4beef-9999-0123456789ab';
      expect(FontLibrary.familyFor(id), 'user:$id');
      expect(FontLibrary.idOf(FontLibrary.familyFor(id)), id);
    });

    test('does not claim a Google family', () {
      // The whole design rests on this: a stored fontFamily was always a bare
      // string, and it keeps meaning exactly what it always meant because no
      // Google family name contains a colon.
      expect(FontLibrary.idOf('Poppins'), isNull);
      expect(FontLibrary.idOf('Plus Jakarta Sans'), isNull);
      expect(FontLibrary.idOf('Roboto'), isNull);
      expect(FontLibrary.idOf(''), isNull);
    });
  });

  group('looksLikeFont', () {
    test('accepts the sfnt signatures the engine can render', () {
      expect(
        FontLibrary.looksLikeFont(headed(0x00010000)),
        isTrue,
        reason: 'TrueType outlines',
      );
      expect(
        FontLibrary.looksLikeFont(headed(0x4F54544F)),
        isTrue,
        reason: 'OTTO — CFF outlines in an OpenType wrapper',
      );
      expect(
        FontLibrary.looksLikeFont(headed(0x74727565)),
        isTrue,
        reason: 'true — legacy Mac TrueType',
      );
    });

    test('refuses a web font, which is the whole reason it exists', () {
      // A .woff2 renamed to .ttf loads through FontLoader without complaint and
      // then renders nothing at all — every caption using it becomes blank
      // space, on the canvas and in the export. Only the magic number catches
      // that; the extension says .ttf and the load says success.
      expect(FontLibrary.looksLikeFont(headed(0x774F4632)), isFalse);
      expect(FontLibrary.looksLikeFont(headed(0x774F4646)), isFalse);
    });

    test('refuses a font collection', () {
      // ttcf holds several faces and FontLoader has no way to say which one.
      expect(FontLibrary.looksLikeFont(headed(0x74746366)), isFalse);
    });

    test('refuses anything too short to hold a table directory', () {
      expect(FontLibrary.looksLikeFont(headed(0x00010000, length: 200)), false);
    });

    test('refuses an error page saved under a font name', () {
      final html = Uint8List.fromList(
        utf8.encode('<!doctype html><title>404</title>${'x' * 2000}'),
      );
      expect(FontLibrary.looksLikeFont(html), isFalse);
    });
  });

  group('importBytes refuses bytes that are not a font', () {
    test('and leaves nothing behind when it does', () async {
      final entry = await library().importBytes(
        headed(0x774F4632),
        label: 'Web font',
      );

      expect(entry, isNull);
      expect(container.read(fontLibraryProvider), isEmpty);
      // A file written for an entry that was then refused would be an orphan
      // nothing ever cleans up.
      expect(
        Directory(FontLibrary.directoryPath).listSync().whereType<File>(),
        isEmpty,
      );
    });
  });

  group(
    'a real face',
    () {
      test('is written, indexed and registered', () async {
        final entry = await library().importBytes(
          hostFace!,
          label: 'Brand Sans',
          extension: '.ttf',
        );

        expect(entry, isNotNull);
        expect(entry!.label, 'Brand Sans');
        expect(entry.fileName, '${entry.id}.ttf');
        expect(File(entry.path).existsSync(), isTrue);
        expect(container.read(fontLibraryProvider).map((e) => e.id), [
          entry.id,
        ]);

        expect(
          FontLibrary.isRegistered(entry.family),
          isTrue,
          reason:
              'the face has to reach the engine or every caption using it '
              'paints blank',
        );
        expect(FontLibrary.labelFor(entry.family), 'Brand Sans');
        expect(FontLibrary.entryOf(entry.family)?.id, entry.id);
      });

      test('survives a reload of the index', () async {
        final entry = await library().importBytes(
          hostFace!,
          label: 'Brand Sans',
        );
        await settleIndex();

        // A second container is what a relaunch looks like from the notifier's
        // side: the folder and its index are already there and are read back.
        final second = ProviderContainer();
        addTearDown(second.dispose);
        second.read(fontLibraryProvider);
        await settleIndex();

        expect(second.read(fontLibraryProvider).map((e) => e.id), [entry!.id]);
        expect(second.read(fontLibraryProvider).single.label, 'Brand Sans');
      });

      test('keeps a font imported while the index is still loading', () async {
        // The restore path's exact shape: read the provider and import into it
        // in the same breath. Reading the index back is asynchronous, so the
        // two overlap — and whichever finishes last must not erase the other.
        final face = hostFace!;
        final seeded = await library().importBytes(face, label: 'Brand Sans');
        await settleIndex();

        final second = ProviderContainer();
        addTearDown(second.dispose);
        final added = await second
            .read(fontLibraryProvider.notifier)
            .importBytes(face, label: 'Brand Serif', id: 'arrived-late');
        await settleIndex();

        expect(
          second.read(fontLibraryProvider).map((e) => e.id),
          containsAll([seeded!.id, added!.id]),
        );
      });

      test('restoring the same id twice adds one entry, not two', () async {
        // The backup path. A font is global, so a second reference to the same id
        // is correct — re-minting would drop a duplicate in the picker every time
        // the same backup was restored.
        final face = hostFace!;
        final first = await library().importBytes(
          face,
          label: 'Brand Sans',
          id: 'fixed-id',
        );
        final second = await library().importBytes(
          face,
          label: 'Brand Sans Again',
          id: 'fixed-id',
        );

        expect(first?.id, 'fixed-id');
        expect(second?.id, 'fixed-id');
        expect(container.read(fontLibraryProvider), hasLength(1));
        expect(
          container.read(fontLibraryProvider).single.label,
          'Brand Sans',
          reason: 'the entry already held wins; a restore is not a rename',
        );
      });

      test('remove deletes the file and the entry', () async {
        final entry = await library().importBytes(
          hostFace!,
          label: 'Brand Sans',
        );
        final path = entry!.path;

        await library().remove(entry.id);

        expect(container.read(fontLibraryProvider), isEmpty);
        expect(File(path).existsSync(), isFalse);
        expect(
          FontLibrary.labelFor(entry.family),
          isNull,
          reason: 'the editor has to start calling it missing straight away',
        );
      });

      test('a face whose file has gone stays named but stops resolving', () async {
        // What a backup restored onto a device without the font looks like, and
        // what a deleted file looks like. The label survives so the picker can
        // say which font is missing rather than showing a raw id.
        final entry = await library().importBytes(
          hostFace!,
          label: 'Brand Sans',
        );
        await settleIndex();
        File(entry!.path).deleteSync();

        FontLibrary.debugResetStorage();
        await FontLibrary.initialize();

        expect(FontLibrary.labelFor(entry.family), 'Brand Sans');
        expect(FontLibrary.isRegistered(entry.family), isFalse);
      });
    },
    skip: hostFace == null ? 'no readable system font on this machine' : null,
  );

  group('UserFont', () {
    test('round-trips through the index format', () {
      final entry = UserFont(
        id: 'abc',
        fileName: 'abc.otf',
        label: 'Brand Serif',
        addedAt: DateTime.utc(2026, 7, 1),
      );
      final restored = UserFont.fromJson(entry.toJson());

      expect(restored.id, 'abc');
      expect(restored.fileName, 'abc.otf');
      expect(restored.label, 'Brand Serif');
      expect(restored.addedAt, DateTime.utc(2026, 7, 1));
      expect(restored.family, 'user:abc');
    });

    test('tolerates an entry a truncated write left half-formed', () {
      final restored = UserFont.fromJson({'id': 'abc'});
      expect(restored.fileName, 'abc.ttf');
      expect(restored.label, isNotEmpty);
    });
  });
}
