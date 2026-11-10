import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

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

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apply_style_test');
    PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
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

  /// The screens of the project's only target — `applyStyleToAll` is scoped to
  /// one sub-project, so this is exactly the set it acts on.
  List<ScreenDoc> screensOf(String id) => container
      .read(projectStoreProvider)
      .firstWhere((p) => p.id == id)
      .subProjects
      .single
      .screens;

  String seed() => store()
      .createProject(
        name: 'Listing',
        targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
        initialDeviceId: 'apple-iphone-16',
        initialVariantId: '16---ultramarine',
        initialCornerRadiusPct: 0.12,
      )
      .id;

  /// Rewrites screen [index] through [edit].
  void edit(String projectId, int index, ScreenDoc Function(ScreenDoc) fn) {
    final screens = screensOf(projectId);
    store().updateScreen(projectId, fn(screens[index]));
  }

  group('applyStyleToAll carries the design and nothing else', () {
    test('every screen keeps its own backdrop photo', () {
      final id = seed();

      // Source and target both have a photo backdrop, treated differently.
      edit(
        id,
        0,
        (s) => s.copyWith(
          background: const ImageBackground(
            '/photos/source.jpg',
            blur: 0.4,
            overlayOpacity: 0.6,
          ),
        ),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(background: const ImageBackground('/photos/two.jpg')),
      );

      final sourceId = screensOf(id).first.id;
      store().applyStyleToAll(id, sourceId);

      final target = screensOf(id)[1].background as ImageBackground;
      expect(
        target.path,
        '/photos/two.jpg',
        reason: 'the picture is content, like the screenshot in the frame',
      );
      expect(target.blur, 0.4, reason: 'but the treatment comes across');
      expect(target.overlayOpacity, 0.6);
    });

    test('a screen with no photo is not handed someone else’s file', () {
      final id = seed();
      edit(
        id,
        0,
        (s) =>
            s.copyWith(background: const ImageBackground('/photos/source.jpg')),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(background: const SolidBackground(Color(0xFF102030))),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final target = screensOf(id)[1].background;
      expect(target, isA<SolidBackground>());
      expect((target as SolidBackground).color, const Color(0xFF102030));
    });

    test('fills that carry no content still copy across whole', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(background: const SolidBackground(Color(0xFFAABBCC))),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(background: const SolidBackground(Color(0xFF000000))),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      expect(
        (screensOf(id)[1].background as SolidBackground).color,
        const Color(0xFFAABBCC),
      );
    });

    test('every screen keeps its own screenshot', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.updateFrame(
          0,
          (f) => f.copyWith(
            screenshot: f.screenshot.copyWith(imagePath: '/shots/one.png'),
          ),
        ),
      );
      edit(
        id,
        1,
        (s) => s.updateFrame(
          0,
          (f) => f.copyWith(
            screenshot: f.screenshot.copyWith(imagePath: '/shots/two.png'),
          ),
        ),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      expect(
        screensOf(id)[1].frames.first.screenshot.imagePath,
        '/shots/two.png',
      );
    });

    test('every screen keeps its own caption words', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(
          caption: const CaptionSpec(text: 'Source headline', size: 90),
        ),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(caption: const CaptionSpec(text: 'Target headline')),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final caption = screensOf(id)[1].caption!;
      expect(caption.text, 'Target headline');
      expect(caption.size, 90, reason: 'the size is design, the words are not');
    });

    test('and its own words when the caption is rich text', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(
          caption: const CaptionSpec(
            text: 'Source one\nSource two',
            runs: [
              CaptionRun('Source one\n', bold: true, sizeScale: 1.4),
              CaptionRun('Source two', bold: false, sizeScale: 0.8),
            ],
          ),
        ),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(
          caption: const CaptionSpec(
            text: 'Target one\nTarget two\nTarget three',
            runs: [CaptionRun('Target one\nTarget two\nTarget three')],
          ),
        ),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final caption = screensOf(id)[1].caption!;
      expect(
        caption.plainText,
        'Target one\nTarget two\nTarget three',
        reason: 'a rich caption keeps its words inside the run list',
      );

      // Line 1 takes the source's first line, lines 2 and 3 its second — the
      // last source line styles everything beyond it.
      final byLine = {
        for (final line in caption.plainText.split('\n'))
          line: caption.runs.firstWhere((r) => r.text.contains(line)),
      };
      expect(
        byLine['Target one']!.bold,
        isTrue,
        reason: 'run styling applies positionally, line by line',
      );
      expect(byLine['Target one']!.sizeScale, 1.4);
      expect(byLine['Target two']!.bold, isFalse);
      expect(byLine['Target two']!.sizeScale, 0.8);
      expect(
        byLine['Target three']!.sizeScale,
        0.8,
        reason: 'the last source line styles anything beyond it',
      );
    });

    test('a phrase keeps its own styling inside a line', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(
          caption: const CaptionSpec(
            text: 'Ship it fast',
            runs: [
              CaptionRun('Ship', color: Color(0xFFFF0000)),
              CaptionRun(' it fast'),
            ],
          ),
        ),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(
          caption: const CaptionSpec(
            text: 'Grow it here',
            runs: [CaptionRun('Grow it here')],
          ),
        ),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final runs = screensOf(id)[1].caption!.runs;
      expect(runs.map((r) => r.text).join(), 'Grow it here');
      expect(
        runs.first.text,
        'Grow',
        reason:
            'the source styles the first four characters, so the split '
            'lands where the source put it',
      );
      expect(runs.first.color, const Color(0xFFFF0000));
      expect(runs.last.color, isNull);
    });

    test('a plain target is not made rich by a rich source', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(
          caption: const CaptionSpec(
            text: 'A\nB',
            runs: [CaptionRun('A\n'), CaptionRun('B')],
          ),
        ),
      );
      edit(
        id,
        1,
        (s) => s.copyWith(caption: const CaptionSpec(text: 'Just one line')),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final caption = screensOf(id)[1].caption!;
      expect(caption.runs, isEmpty);
      expect(caption.plainText, 'Just one line');
    });

    test('the design itself does come across', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.copyWith(
          isCaptionAbove: false,
          caption: const CaptionSpec(text: 'Source', size: 120, bold: true),
        ),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      final target = screensOf(id)[1];
      expect(target.isCaptionAbove, isFalse);
      expect(target.caption!.size, 120);
      expect(target.caption!.bold, isTrue);
    });

    test('a built frame travels across the set', () {
      final id = seed();
      edit(
        id,
        0,
        (s) => s.updateFrame(
          0,
          (f) => f.copyWith(
            design: const FrameDesign(
              thickness: 0.02,
              topThickness: 0.05,
              bottomThickness: 0.08,
              color: Color(0xFF445566),
            ),
          ),
        ),
      );

      store().applyStyleToAll(id, screensOf(id).first.id);

      // The design *is* the look. Skipping it moved the device and its
      // transform but left every other screen wearing the catalog artwork.
      final design = screensOf(id)[1].frames.first.design;
      expect(design, isNotNull);
      expect(design!.thickness, 0.02);
      expect(design.topThickness, 0.05);
      expect(design.bottomThickness, 0.08);
      expect(design.color, const Color(0xFF445566));
    });

    test('and a source with no built frame clears one from the others', () {
      final id = seed();
      edit(
        id,
        1,
        (s) => s.updateFrame(
          0,
          (f) => f.copyWith(design: const FrameDesign(thickness: 0.04)),
        ),
      );

      // Screen 0 uses catalog artwork, so applying from it means "catalog
      // artwork everywhere" — not "keep whatever you had".
      store().applyStyleToAll(id, screensOf(id).first.id);

      expect(screensOf(id)[1].frames.first.design, isNull);
    });

    test('the source screen is left exactly as it was', () {
      final id = seed();
      final before = screensOf(id).first;
      store().applyStyleToAll(id, before.id);
      expect(screensOf(id).first, same(before));
    });
  });
}
