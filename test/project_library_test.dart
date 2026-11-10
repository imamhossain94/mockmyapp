// Managing the library itself: renaming, deleting and ordering projects.
//
// The order is not a sort key — the list *is* the order, and the home screen
// shows projects in exactly that sequence — so a reorder has to be a move on
// the stored list and nothing else.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';

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
    tempDir = Directory.systemTemp.createTempSync('project_library_test');
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
  List<Project> all() => container.read(projectStoreProvider);
  List<String> names() => all().map((p) => p.name).toList();

  Project make(String name) => store().createProject(
    name: name,
    targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
    initialDeviceId: 'apple-iphone-16',
    initialVariantId: '16---ultramarine',
    initialCornerRadiusPct: 0.12,
  );

  /// Three projects reading One, Two, Three.
  ///
  /// Made backwards on purpose: `createProject` puts each new project at the
  /// FRONT of the library, because the one you just made is the one you are
  /// about to work on. Seeding in reading order would have quietly tested the
  /// reverse of what each expectation says.
  void seed() {
    make('Three');
    make('Two');
    make('One');
  }

  test('a new project joins at the front of the library', () {
    // The behaviour the fixtures above depend on, stated once so a change to it
    // fails here rather than confusing every ordering test at the same time.
    make('First made');
    make('Second made');
    expect(names(), ['Second made', 'First made']);
  });

  group('renaming', () {
    test('changes the name and leaves everything else alone', () {
      final p = make('Draft');
      final before = all().single.screenCount;

      store().renameProject(p.id, 'Store listing');
      expect(all().single.name, 'Store listing');
      expect(all().single.id, p.id);
      expect(all().single.screenCount, before);
    });

    test('a name is trimmed, so a stray space is not part of it', () {
      final p = make('Draft');
      store().renameProject(p.id, '  Spaced  ');
      expect(all().single.name, 'Spaced');
    });

    test('an unknown id changes nothing', () {
      make('Draft');
      store().renameProject('no-such-project', 'Nope');
      expect(names(), ['Draft']);
    });
  });

  group('deleting', () {
    test('removes that project and only that one', () {
      seed();
      final two = all()[1];
      store().deleteProject(two.id);
      expect(names(), ['One', 'Three']);
    });

    test('an unknown id removes nothing', () {
      seed();
      store().deleteProject('no-such-project');
      expect(names(), hasLength(3));
    });
  });

  group('ordering', () {
    test('a project moves to where it was dropped', () {
      seed();
      // `to` is where it ends up, not what it was dropped over.
      store().reorderProjects(0, 2);
      expect(names(), ['Two', 'Three', 'One']);
    });

    test('moving backwards works the same way', () {
      seed();
      store().reorderProjects(2, 0);
      expect(names(), ['Three', 'One', 'Two']);
    });

    test('a move that changes nothing is refused', () {
      seed();
      final before = names();
      store().reorderProjects(1, 1);
      expect(names(), before);
    });

    test('an out-of-range index does nothing rather than throwing', () {
      seed();
      final before = names();
      store().reorderProjects(9, 0);
      store().reorderProjects(-1, 0);
      expect(names(), before);
    });

    test('a drop past the end lands at the end', () {
      seed();
      store().reorderProjects(0, 99);
      expect(names(), ['Two', 'Three', 'One']);
    });

    test('move up and move down step one place', () {
      seed();
      final three = all()[2];
      store().moveProject(three.id, -1);
      expect(names(), ['One', 'Three', 'Two']);
      store().moveProject(three.id, 1);
      expect(names(), ['One', 'Two', 'Three']);
    });

    test('moving past either end stops there', () {
      seed();
      final one = all().first;
      store().moveProject(one.id, -1);
      expect(names(), ['One', 'Two', 'Three'], reason: 'already first');

      final three = all().last;
      store().moveProject(three.id, 1);
      expect(names(), ['One', 'Two', 'Three'], reason: 'already last');
    });

    test('the order survives a save and a reload', () async {
      seed();
      store().reorderProjects(0, 2);
      expect(names(), ['Two', 'Three', 'One']);

      // A fresh container reads the store back off disk, which is the only
      // thing that proves the order was persisted rather than held in memory.
      await store().debugFlush();
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      // `build` starts the read and returns empty, so the first look is always
      // the empty list. Bounded rather than a fixed sleep: fast when the file
      // lands quickly, and it still fails rather than hanging if it never does.
      for (var i = 0; i < 200; i++) {
        if (reopened.read(projectStoreProvider).isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(reopened.read(projectStoreProvider).map((p) => p.name).toList(), [
        'Two',
        'Three',
        'One',
      ]);
    });
  });
}
