import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

const _iphone = (targetId: 'ios-iphone', presetId: 'iphone-6-5');
const _ipad = (targetId: 'ios-ipad', presetId: 'ipad-13');

Uint8List pngish(String tag) => Uint8List.fromList(tag.codeUnits);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('project_transfer_test');
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
  ImageLibrary library() => container.read(imageLibraryProvider.notifier);
  List<Project> projects() => container.read(projectStoreProvider);
  Project projectById(String id) => projects().firstWhere((p) => p.id == id);

  Project make(String name, List<TargetChoice> targets) =>
      store().createProject(
        name: name,
        targets: targets,
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
      );

  /// Puts a fresh library picture into the first screen of [sub].
  Future<String> attachArtwork(Project project, SubProject sub) async {
    final entry = await library().importBytes(
      pngish('shot-${sub.id}'),
      projectId: project.id,
      kind: LibraryImageKind.screenshot,
    );
    final screen = projectById(
      project.id,
    ).subProjectById(sub.id)!.screens.first;
    store().updateScreen(
      project.id,
      screen.updateFrame(
        0,
        (f) => f.copyWith(
          screenshot: f.screenshot.copyWith(imagePath: entry.path),
        ),
      ),
    );
    return entry.path;
  }

  String? shotPathOf(String projectId, String subId) => projectById(
    projectId,
  ).subProjectById(subId)!.screens.first.frames.first.screenshot.imagePath;

  group('copying a target into another project', () {
    test(
      'leaves the source alone and gives the destination its own set',
      () async {
        final from = make('Alpha', const [_iphone]);
        final to = make('Beta', const [_ipad]);
        final sub = from.subProjects.single;

        final copy = await store().copyTargetTo(
          fromProjectId: from.id,
          subId: sub.id,
          toProjectId: to.id,
        );

        expect(copy, isNotNull);
        expect(
          projectById(from.id).subProjects.map((s) => s.id),
          [sub.id],
          reason: 'a copy takes nothing away from the project it came from',
        );

        final landed = projectById(to.id).subProjects.last;
        expect(landed.targetId, sub.targetId);
        expect(landed.canvas, sub.canvas);
        expect(landed.screens, hasLength(sub.screens.length));
        expect(
          landed.id,
          isNot(sub.id),
          reason: 'the copy is a different set, not the same one twice',
        );
        expect(
          landed.screens.map((s) => s.id),
          everyElement(isNot(isIn(sub.screens.map((s) => s.id)))),
          reason: 'fresh screen ids, so editing one never reaches the other',
        );
      },
    );

    test('gives the destination its own copy of the artwork', () async {
      final from = make('Alpha', const [_iphone]);
      final to = make('Beta', const [_ipad]);
      final sub = from.subProjects.single;
      final original = await attachArtwork(from, sub);

      final copy = await store().copyTargetTo(
        fromProjectId: from.id,
        subId: sub.id,
        toProjectId: to.id,
      );

      final copied = shotPathOf(to.id, copy!.id);
      expect(copied, isNotNull);
      expect(
        copied,
        isNot(original),
        reason: 'two projects sharing one file can blank each other',
      );
      expect(shotPathOf(from.id, sub.id), original);

      // Both pickers offer their own file, and only their own.
      expect(
        library()
            .forProject(to.id, LibraryImageKind.screenshot)
            .map((e) => e.path),
        [copied],
      );
      expect(
        library()
            .forProject(from.id, LibraryImageKind.screenshot)
            .map((e) => e.path),
        [original],
      );
    });

    test('is refused when the destination already has that target', () async {
      final from = make('Alpha', const [_iphone]);
      final to = make('Beta', const [_iphone]);

      expect(store().canReceiveTarget('ios-iphone', to.id), isFalse);
      expect(
        await store().copyTargetTo(
          fromProjectId: from.id,
          subId: from.subProjects.single.id,
          toProjectId: to.id,
        ),
        isNull,
      );
      expect(projectById(to.id).subProjects, hasLength(1));
    });

    test('is refused when the destination is the source', () async {
      final from = make('Alpha', const [_iphone]);
      expect(
        await store().copyTargetTo(
          fromProjectId: from.id,
          subId: from.subProjects.single.id,
          toProjectId: from.id,
        ),
        isNull,
      );
    });
  });

  group('moving a target into another project', () {
    test('takes the set out of one project and puts it in the other', () async {
      final from = make('Alpha', const [_iphone, _ipad]);
      // Seeded with the target the move is *not* sending, so there is room for
      // the one that arrives.
      final to = make('Beta', const [_ipad]);
      final sub = from.subProjects.first;

      final moved = await store().moveTargetTo(
        fromProjectId: from.id,
        subId: sub.id,
        toProjectId: to.id,
      );

      expect(moved, isTrue);
      expect(projectById(from.id).subProjects.map((s) => s.targetId), [
        'ios-ipad',
      ]);

      final landed = projectById(to.id).subProjects.last;
      expect(
        landed.id,
        sub.id,
        reason: 'the same set, in a different project — its id is its identity',
      );
      expect(
        landed.screens.map((s) => s.id),
        sub.screens.map((s) => s.id),
        reason: 'the editor route to a document still opens it',
      );
    });

    test('hands over the artwork only that set was using', () async {
      final from = make('Alpha', const [_iphone, _ipad]);
      final to = make('Beta', const [_ipad]);
      final sub = from.subProjects.first;
      final original = await attachArtwork(from, sub);

      expect(
        await store().moveTargetTo(
          fromProjectId: from.id,
          subId: sub.id,
          toProjectId: to.id,
        ),
        isTrue,
      );

      expect(
        shotPathOf(to.id, sub.id),
        original,
        reason: 'the bytes never moved, only who the picker offers them to',
      );
      expect(
        library()
            .forProject(to.id, LibraryImageKind.screenshot)
            .map((e) => e.path),
        [original],
      );
      expect(
        library().forProject(from.id, LibraryImageKind.screenshot),
        isEmpty,
      );
    });

    test('copies artwork the old project is still using elsewhere', () async {
      final from = make('Alpha', const [_iphone, _ipad]);
      final to = make('Beta', const [_ipad]);

      final moving = from.subProjects.first;
      final staying = from.subProjects.last;

      // One picture, used by both of Alpha's sets.
      final shared = await attachArtwork(from, moving);
      final stayingScreen = projectById(
        from.id,
      ).subProjectById(staying.id)!.screens.first;
      store().updateScreen(
        from.id,
        stayingScreen.updateFrame(
          0,
          (f) =>
              f.copyWith(screenshot: f.screenshot.copyWith(imagePath: shared)),
        ),
      );

      expect(
        await store().moveTargetTo(
          fromProjectId: from.id,
          subId: moving.id,
          toProjectId: to.id,
        ),
        isTrue,
      );

      expect(
        shotPathOf(to.id, moving.id),
        isNot(shared),
        reason: 'a picture both projects still need is copied, not handed over',
      );
      expect(
        shotPathOf(from.id, staying.id),
        shared,
        reason: 'the set left behind keeps pointing at the original',
      );
      expect(
        library()
            .forProject(from.id, LibraryImageKind.screenshot)
            .map((e) => e.path),
        [shared],
      );
    });

    test('is refused when it would empty the source project', () async {
      final from = make('Alpha', const [_iphone]);
      final to = make('Beta', const [_ipad]);

      expect(
        await store().moveTargetTo(
          fromProjectId: from.id,
          subId: from.subProjects.single.id,
          toProjectId: to.id,
        ),
        isFalse,
      );
      expect(projectById(from.id).subProjects, hasLength(1));
      expect(projectById(to.id).subProjects, hasLength(1));
    });

    test('is refused when the destination already has that target', () async {
      final from = make('Alpha', const [_iphone, _ipad]);
      final to = make('Beta', const [_iphone]);

      expect(
        await store().moveTargetTo(
          fromProjectId: from.id,
          subId: from.subProjects.first.id,
          toProjectId: to.id,
        ),
        isFalse,
      );
      expect(projectById(from.id).subProjects, hasLength(2));
      expect(projectById(to.id).subProjects, hasLength(1));
    });
  });

  group('duplicating a project', () {
    test('copies every target and screen under a fresh id', () async {
      final source = make('Listing', const [_iphone, _ipad]);

      final copy = await store().duplicateProject(source.id);

      expect(copy, isNotNull);
      expect(copy!.id, isNot(source.id));
      expect(copy.name, 'Listing copy');
      expect(
        copy.subProjects.map((s) => s.targetId),
        source.subProjects.map((s) => s.targetId),
      );
      expect(copy.screenCount, source.screenCount);

      final sourceIds = {
        for (final sub in source.subProjects) sub.id,
        for (final screen in source.allScreens) screen.id,
      };
      final copyIds = {
        for (final sub in copy.subProjects) sub.id,
        for (final screen in copy.allScreens) screen.id,
      };
      expect(
        sourceIds.intersection(copyIds),
        isEmpty,
        reason: 'nothing is shared, so editing one never reaches the other',
      );
    });

    test('lands directly under the project it was made from', () async {
      final first = make('First', const [_iphone]);
      make('Second', const [_iphone]);

      final copy = await store().duplicateProject(first.id);

      expect(projects().map((p) => p.name), ['Second', 'First', 'First copy']);
      expect(projects()[2].id, copy!.id);
    });

    test('numbers the copy when the plain name is taken', () async {
      final source = make('Listing', const [_iphone]);

      await store().duplicateProject(source.id);
      final second = await store().duplicateProject(source.id);

      expect(second!.name, 'Listing copy 2');
    });

    test('gives the copy its own artwork', () async {
      final source = make('Listing', const [_iphone]);
      final original = await attachArtwork(source, source.subProjects.single);

      final copy = await store().duplicateProject(source.id);

      final copied = shotPathOf(copy!.id, copy.subProjects.single.id);
      expect(copied, isNotNull);
      expect(copied, isNot(original));
      expect(shotPathOf(source.id, source.subProjects.single.id), original);
      expect(
        library()
            .forProject(copy.id, LibraryImageKind.screenshot)
            .map((e) => e.path),
        [copied],
      );
    });

    test('an unknown project duplicates to nothing', () async {
      expect(await store().duplicateProject('not-a-project'), isNull);
    });
  });
}
