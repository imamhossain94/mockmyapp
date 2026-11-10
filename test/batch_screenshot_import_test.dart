// Fanning a batch of captures across a set — see
// `ProjectStore.importScreenshots`.
//
// This is the shape a store listing arrives in: six captures, in the order they
// are meant to be seen, for six screens that share one treatment. The thing
// that must not happen is a batch that lands out of order, overwrites a screen's
// caption or backdrop, or quietly drops the captures that had no screen waiting
// for them.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('batch_import_test');
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
  List<Project> projects() => container.read(projectStoreProvider);
  Project projectById(String id) => projects().firstWhere((p) => p.id == id);

  Project make() => store().createProject(
    name: 'Listing',
    targets: const [_iphone],
    initialDeviceId: 'apple-iphone-16',
    initialVariantId: '16---ultramarine',
  );

  SubProject subOf(Project p) => projectById(p.id).subProjects.first;
  List<ScreenDoc> screensOf(Project p) => subOf(p).screens;

  List<String?> shotsIn(Project p) => [
    for (final screen in screensOf(p))
      screen.frames.isEmpty ? null : screen.frames.first.screenshot.imagePath,
  ];

  test('a batch lands one per screen, in order', () {
    // A new project is seeded with screens already, so the batch is sized to
    // whatever it starts with rather than to a number this test invents.
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length;
    final paths = [for (var i = 0; i < count; i++) '/shot$i.png'];

    final touched = store().importScreenshots(project.id, sub.id, paths);

    expect(shotsIn(project), paths);
    expect(touched, hasLength(count));
    expect(
      touched.first.id,
      screensOf(project).first.id,
      reason: 'the caller opens the first screen it filled',
    );
  });

  test('more captures than screens grows the set', () {
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length + 2;
    final paths = [for (var i = 0; i < count; i++) '/shot$i.png'];

    store().importScreenshots(project.id, sub.id, paths);

    expect(screensOf(project), hasLength(count));
    expect(shotsIn(project), paths);
  });

  test('fewer captures than screens leaves the rest alone', () {
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length;
    expect(count, greaterThan(1), reason: 'the case only exists above one');

    store().importScreenshots(project.id, sub.id, ['/a.png']);

    expect(screensOf(project), hasLength(count));
    expect(shotsIn(project), ['/a.png', ...List.filled(count - 1, null)]);
  });

  test('a screen keeps everything except its picture', () {
    // The caption, the backdrop and the device are the point of having set the
    // screen up. Only what is inside the frame is replaced.
    final project = make();
    final sub = subOf(project);
    final before = screensOf(project).first;
    store().updateScreen(
      project.id,
      before.copyWith(caption: const CaptionSpec(text: 'Track every workout')),
    );

    store().importScreenshots(project.id, sub.id, ['/a.png']);

    final after = screensOf(project).first;
    expect(after.caption?.text, 'Track every workout');
    expect(after.id, before.id, reason: 'the screen is edited, not replaced');
    expect(after.frames.first.deviceId, before.frames.first.deviceId);
    expect(after.frames.first.screenshot.imagePath, '/a.png');
  });

  test('the framing a screen already had survives the batch', () {
    final project = make();
    final sub = subOf(project);
    final screen = screensOf(project).first;
    store().updateScreen(
      project.id,
      screen.updateFrame(
        0,
        (f) => f.copyWith(
          screenshot: f.screenshot.copyWith(cornerRadiusPct: 0.11, scale: 1.3),
        ),
      ),
    );

    store().importScreenshots(project.id, sub.id, ['/a.png']);

    final shot = screensOf(project).first.frames.first.screenshot;
    expect(shot.imagePath, '/a.png');
    expect(shot.cornerRadiusPct, 0.11);
    expect(shot.scale, 1.3);
  });

  test('an empty batch changes nothing', () {
    final project = make();
    final sub = subOf(project);
    final before = screensOf(project).length;
    expect(store().importScreenshots(project.id, sub.id, const []), isEmpty);
    expect(screensOf(project), hasLength(before));
  });

  test('a new screen no longer inherits the last one\'s capture', () {
    // `addScreen` asked for `imagePath: null`, which reads as "leave this
    // alone" — so every screen added after the first arrived already wearing
    // the previous screen's screenshot.
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length;
    final paths = [for (var i = 0; i < count; i++) '/shot$i.png'];
    store().importScreenshots(project.id, sub.id, paths);

    store().addScreen(project.id, sub.id);

    expect(shotsIn(project), [...paths, null]);
  });

  test('a batch fills the screens still waiting for a picture', () {
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length;
    store().importScreenshots(project.id, sub.id, ['/done.png']);

    store().importScreenshots(project.id, sub.id, ['/a.png', '/b.png']);

    final shots = shotsIn(project);
    expect(shots.first, '/done.png', reason: 'a finished screen is kept');
    expect(shots.sublist(1, 3), ['/a.png', '/b.png']);
    expect(shots, hasLength(count));
  });

  test('a batch for a finished set adds screens rather than replacing', () {
    final project = make();
    final sub = subOf(project);
    final count = screensOf(project).length;
    final first = [for (var i = 0; i < count; i++) '/shot$i.png'];
    store().importScreenshots(project.id, sub.id, first);

    store().importScreenshots(project.id, sub.id, ['/new.png']);

    expect(shotsIn(project), [...first, '/new.png']);
  });
}
