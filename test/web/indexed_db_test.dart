@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/repositories/project_store.dart';

import 'package:mockmyapp/data/services/browser_store.dart';
import 'package:mockmyapp/data/services/browser_store_web.dart';

// The real IndexedDB store, in a real browser:
//
//   flutter test --platform chrome test/web/indexed_db_test.dart
//
// A second store instance opens the database afresh, which is what a page
// reload does.

void main() {
  test('the browser gets an IndexedDB store', () {
    expect(browserStore, isA<IndexedDbStore>());
  });

  test('text and bytes come back after a reopen, and delete sticks', () async {
    final writer = IndexedDbStore();
    await writer.writeText('projects.json', '[{"id":"p"}]');
    await writer.writeBytes('img:a.png', Uint8List.fromList([1, 2, 3]));
    await writer.writeBytes('img:b.png', Uint8List.fromList([4, 5]));
    await writer.writeBytes('font:c.ttf', Uint8List.fromList([9]));

    final reader = IndexedDbStore();
    expect(await reader.readText('projects.json'), '[{"id":"p"}]');
    expect(await reader.readBytes('img:a.png'), [1, 2, 3]);

    final images = await reader.readAllBytes('img:');
    expect(images.keys, unorderedEquals(['a.png', 'b.png']));
    expect(images['b.png'], [4, 5]);

    await reader.delete('img:a.png');
    expect(await IndexedDbStore().readBytes('img:a.png'), isNull);
    expect(await reader.readText('missing'), isNull);
  });

  test('a project made in the app is there after a reload', () async {
    final before = ProviderContainer();
    final project = before
        .read(projectStoreProvider.notifier)
        .createProject(
          name: 'Saved in the browser',
          targets: const [
            (targetId: 'android-phone', presetId: 'android-phone-9-16'),
          ],
        );
    await before.read(projectStoreProvider.notifier).debugFlush();
    before.dispose();

    // A fresh store and a fresh container: nothing carried over in memory.
    browserStore = IndexedDbStore();
    final after = ProviderContainer();
    addTearDown(after.dispose);
    after.read(projectStoreProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      after.read(projectStoreProvider).map((p) => p.id),
      contains(project.id),
    );
  });
}
