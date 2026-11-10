import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/repositories/font_library.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/repositories/stored_image.dart';
import 'package:mockmyapp/data/services/browser_store.dart';

import 'support/host_face.dart';

// The web's persistence, run on the VM through the same code path with an
// in-memory store standing in for IndexedDB. A "refresh" is every in-memory
// cache dropped while the store is kept.

Future<void> settleSaves() =>
    Future<void>.delayed(const Duration(milliseconds: 500));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hostFace = readHostFace();
  late MemoryKeyValueStore store;

  setUp(() {
    store = MemoryKeyValueStore();
    browserStore = store;
    ImageLibrary.debugResetStorage();
    FontLibrary.debugResetStorage();
  });

  tearDown(() {
    browserStore = null;
    ImageLibrary.debugResetStorage();
    FontLibrary.debugResetStorage();
  });

  /// What reloading the page does to the app: every cache gone, the browser's
  /// storage untouched, startup run again.
  Future<ProviderContainer> refresh() async {
    ImageLibrary.debugResetStorage();
    FontLibrary.debugResetStorage();
    await ImageLibrary.initialize();
    await FontLibrary.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
      ..read(projectStoreProvider)
      ..read(imageLibraryProvider)
      ..read(fontLibraryProvider);
    await settleSaves();
    return container;
  }

  test('projects survive a refresh', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    final project = first
        .read(projectStoreProvider.notifier)
        .createProject(
          name: 'Web listing',
          targets: const [
            (targetId: 'android-phone', presetId: 'android-phone-9-16'),
          ],
        );
    await first.read(projectStoreProvider.notifier).debugFlush();
    expect(store.entries.keys, contains('projects.json'));

    final after = await refresh();
    final projects = after.read(projectStoreProvider);
    expect(projects.single.id, project.id);
    expect(projects.single.name, 'Web listing');
  });

  test('an imported picture survives a refresh, and still draws', () async {
    await ImageLibrary.initialize();
    final first = ProviderContainer();
    addTearDown(first.dispose);
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final image = await first
        .read(imageLibraryProvider.notifier)
        .importBytes(bytes, projectId: 'p', kind: LibraryImageKind.element);
    await settleSaves();

    final after = await refresh();
    final library = after.read(imageLibraryProvider);
    expect(library.map((e) => e.id), [image.id]);
    expect(library.single.kind, LibraryImageKind.element);
    // Resolvable without waiting: the canvas asks synchronously.
    expect(await StoredImage.bytes(image.path), bytes);
    expect(StoredImage.provider(image.path), isNotNull);
  });

  test('a removed picture stays removed', () async {
    await ImageLibrary.initialize();
    final first = ProviderContainer();
    addTearDown(first.dispose);
    final notifier = first.read(imageLibraryProvider.notifier);
    final image = await notifier.importBytes(
      Uint8List.fromList([1, 2, 3]),
      projectId: 'p',
    );
    await notifier.remove(image.id);
    await settleSaves();

    final after = await refresh();
    expect(after.read(imageLibraryProvider), isEmpty);
    expect(store.entries.keys.where((k) => k.startsWith('img:')), isEmpty);
  });

  test(
    'an uploaded font survives a refresh, registered with the engine',
    () async {
      await FontLibrary.initialize();
      final first = ProviderContainer();
      addTearDown(first.dispose);
      final font = await first
          .read(fontLibraryProvider.notifier)
          .importBytes(hostFace!, label: 'Brand Sans');
      expect(font, isNotNull);
      await settleSaves();

      final after = await refresh();
      expect(after.read(fontLibraryProvider).map((e) => e.id), [font!.id]);
      expect(FontLibrary.isRegistered(font.family), isTrue);
      expect(FontLibrary.labelFor(font.family), 'Brand Sans');
    },
    skip: hostFace == null ? 'no system font to test with' : false,
  );
}
