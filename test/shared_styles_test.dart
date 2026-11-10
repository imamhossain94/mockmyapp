// Named looks a project reuses — see `StyleLibrary`.
//
// Styles push rather than pull: editing one rewrites every caption tagged with
// it, and the documents go on holding concrete values. So the things that have
// to be true are that the push reaches every screen in the project, that it
// touches only what the style names, and that a document still draws correctly
// with no library anywhere near it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/style_library.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

const _headline = CaptionSpec(
  text: 'Track every workout',
  fontFamily: 'Inter',
  size: 64,
  lineHeight: 74,
  color: Color(0xFF101010),
  bold: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a style names a look, not a caption', () {
    test('it is taken from the caption it is saved off', () {
      final style = TextStyleDef.from(_headline, id: 's1', name: 'Headline');
      expect(style.fontFamily, 'Inter');
      expect(style.size, 64);
      expect(style.color, const Color(0xFF101010));
      expect(style.bold, isTrue);
    });

    test('applying it changes the look and nothing else', () {
      // The words, where it sits, its background plate and its effects are not
      // what "the headline style" means.
      const other = CaptionSpec(
        text: 'Something else entirely',
        offsetPct: Offset(0.1, -0.2),
        backgroundColor: Color(0xFF00FF00),
        shadowBlur: 12,
        fontFamily: 'Roboto',
        size: 20,
      );
      final style = TextStyleDef.from(_headline, id: 's1', name: 'Headline');
      final applied = style.applyTo(other);

      expect(applied.fontFamily, 'Inter');
      expect(applied.size, 64);
      expect(applied.text, 'Something else entirely');
      expect(applied.offsetPct, const Offset(0.1, -0.2));
      expect(applied.backgroundColor, const Color(0xFF00FF00));
      expect(applied.shadowBlur, 12);
    });

    test('applying it tags the caption', () {
      final style = TextStyleDef.from(_headline, id: 's1', name: 'Headline');
      expect(style.applyTo(_headline).styleId, 's1');
    });

    test('a caption edited away from its style stops matching', () {
      final style = TextStyleDef.from(_headline, id: 's1', name: 'Headline');
      final applied = style.applyTo(_headline);
      expect(style.matches(applied), isTrue);
      expect(style.matches(applied.copyWith(size: 20)), isFalse);
      // Changing something the style does not name is not a mismatch.
      expect(style.matches(applied.copyWith(text: 'New words')), isTrue);
    });
  });

  group('the library', () {
    test('saving twice under one id replaces rather than duplicates', () {
      const a = TextStyleDef(id: 's1', name: 'Headline', size: 40);
      const b = TextStyleDef(id: 's1', name: 'Headline', size: 64);
      final library = StyleLibrary.empty.withText(a).withText(b);
      expect(library.texts, hasLength(1));
      expect(library.texts.single.size, 64);
    });

    test('a missing id resolves to nothing rather than throwing', () {
      expect(StyleLibrary.empty.textById('nope'), isNull);
      expect(StyleLibrary.empty.textById(null), isNull);
      expect(StyleLibrary.empty.colorById('nope'), isNull);
    });
  });

  group('a document draws without its library', () {
    test('the tag survives a round-trip but carries no values', () {
      // The whole reason styles push: a screen moved to another project,
      // packed into an archive, or handed to the offscreen exporter has to
      // draw identically with no library in sight.
      final tagged = _headline.copyWith(styleId: 's1');
      final back = captionFromJson(captionToJson(tagged));
      expect(back.styleId, 's1');
      expect(back.fontFamily, 'Inter');
      expect(back.size, 64);
      expect(back.color, const Color(0xFF101010));
    });

    test('a caption written before styles existed loads untagged', () {
      final json = captionToJson(_headline)..remove('styleId');
      expect(captionFromJson(json).styleId, isNull);
    });

    test('the library round-trips on the project', () {
      final project = Project(
        id: 'p1',
        name: 'Listing',
        subProjects: const [],
        createdAt: DateTime.utc(2026),
        styles: StyleLibrary(
          texts: [TextStyleDef.from(_headline, id: 's1', name: 'Headline')],
          colors: const [
            ColorStyle(id: 'c1', name: 'Brand', color: Color(0xFF336FE6)),
          ],
        ),
      );
      final back = Project.fromJson(project.toJson());
      expect(back.styles.texts.single.name, 'Headline');
      expect(back.styles.texts.single.size, 64);
      expect(back.styles.colors.single.color, const Color(0xFF336FE6));
    });

    test('a project written before styles existed loads with none', () {
      final json = Project(
        id: 'p1',
        name: 'Listing',
        subProjects: const [],
        createdAt: DateTime.utc(2026),
      ).toJson()..remove('styles');
      expect(Project.fromJson(json).styles.isEmpty, isTrue);
    });
  });

  group('editing a style pushes', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('styles_test');
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
    Project byId(String id) =>
        container.read(projectStoreProvider).firstWhere((p) => p.id == id);

    Project make() => store().createProject(
      name: 'Listing',
      targets: const [(targetId: 'ios-iphone', presetId: 'iphone-6-5')],
      initialDeviceId: 'apple-iphone-16',
      initialVariantId: '16---ultramarine',
    );

    /// Tags every screen's caption with [styleId].
    void tagAll(Project project, String styleId) {
      for (final sub in byId(project.id).subProjects) {
        for (final screen in sub.screens) {
          store().updateScreen(
            project.id,
            screen.copyWith(
              caption: (screen.caption ?? const CaptionSpec()).copyWith(
                styleId: styleId,
              ),
            ),
          );
        }
      }
    }

    List<double> sizesIn(Project p) => [
      for (final sub in byId(p.id).subProjects)
        for (final screen in sub.screens)
          if (screen.caption != null) screen.caption!.size,
    ];

    test('every tagged caption in the project is rewritten', () {
      final project = make();
      const style = TextStyleDef(id: 's1', name: 'Headline', size: 40);
      store().saveTextStyle(project.id, style);
      tagAll(project, 's1');

      store().saveTextStyle(
        project.id,
        const TextStyleDef(id: 's1', name: 'Headline', size: 88),
      );

      expect(sizesIn(project), everyElement(88));
      expect(sizesIn(project), isNotEmpty);
    });

    test('untagged captions are left alone', () {
      final project = make();
      const style = TextStyleDef(id: 's1', name: 'Headline', size: 40);
      store().saveTextStyle(project.id, style);
      // Deliberately tag nothing.

      store().saveTextStyle(
        project.id,
        const TextStyleDef(id: 's1', name: 'Headline', size: 88),
      );

      expect(sizesIn(project), isNot(contains(88)));
    });

    test('saving a new style pushes to nobody', () {
      // Nothing is tagged with an id that did not exist a moment ago, and a
      // push on first save would be a rewrite of captions the user never
      // associated with it.
      final project = make();
      final before = sizesIn(project);
      store().saveTextStyle(
        project.id,
        const TextStyleDef(id: 'brand-new', name: 'Headline', size: 88),
      );
      expect(sizesIn(project), before);
    });

    test('renaming touches no caption', () {
      final project = make();
      store().saveTextStyle(
        project.id,
        const TextStyleDef(id: 's1', name: 'Headline', size: 40),
      );
      tagAll(project, 's1');
      final before = sizesIn(project);

      store().renameTextStyle(project.id, 's1', 'Big headline');

      expect(byId(project.id).styles.texts.single.name, 'Big headline');
      expect(sizesIn(project), before);
    });

    test('deleting a style unties captions but keeps the look', () {
      // Deleting a style is not a way to un-format a screen.
      final project = make();
      store().saveTextStyle(
        project.id,
        const TextStyleDef(id: 's1', name: 'Headline', size: 40),
      );
      tagAll(project, 's1');
      final before = sizesIn(project);

      store().deleteTextStyle(project.id, 's1');

      expect(byId(project.id).styles.texts, isEmpty);
      expect(sizesIn(project), before);
      for (final sub in byId(project.id).subProjects) {
        for (final screen in sub.screens) {
          expect(screen.caption?.styleId, isNull);
        }
      }
    });
  });
}
