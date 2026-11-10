import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/serialization.dart';
import 'package:mockmyapp/domain/engine/localize.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

// Languages: one design, the words (and captures) per language.

const _canvas = Size(1290, 2796);

ScreenDoc _screen({
  CaptionSpec? caption,
  List<ShapeSpec> shapes = const [],
  List<FramePlacement> frames = const [],
}) => ScreenDoc(
  id: 's',
  canvas: _canvas,
  caption: caption,
  shapes: shapes,
  frames: frames,
);

void main() {
  const english = CaptionSpec(text: 'Edit audio anywhere');

  group('localizeScreen', () {
    test('the default language is the screen itself', () {
      final screen = _screen(caption: english);
      expect(localizeScreen(screen, null), same(screen));
    });

    test('a language with no translation reads the default words', () {
      final screen = _screen(caption: english);
      expect(localizeScreen(screen, 'de-DE').caption!.text, english.text);
    });

    test('a translation replaces the words, and its face where it has one', () {
      final screen = _screen(
        caption: english.copyWith(
          translations: const {
            'ja-JP': CaptionTranslation(
              text: 'どこでも音声編集',
              fontFamily: 'Noto Sans JP',
            ),
          },
        ),
      );
      final ja = localizeScreen(screen, 'ja-JP').caption!;
      expect(ja.text, 'どこでも音声編集');
      expect(ja.fontFamily, 'Noto Sans JP');
      expect(ja.size, english.size, reason: 'no size of its own');
    });

    test('is remembered, so the canvas gets the same object each frame', () {
      final screen = _screen(
        caption: english.copyWith(
          translations: const {'de-DE': CaptionTranslation(text: 'Überall')},
        ),
      );
      expect(
        localizeScreen(screen, 'de-DE'),
        same(localizeScreen(screen, 'de-DE')),
      );
    });

    test('shows a language its own capture', () {
      final screen = _screen(
        frames: [
          FramePlacement(
            deviceId: 'd',
            variantId: 'v',
            screenshot: ScreenshotSpec.of(
              'en.png',
            ).copyWith(localeImages: {'de-DE': 'de.png'}),
          ),
        ],
      );
      expect(
        localizeScreen(screen, 'de-DE').frames.single.screenshot.imagePath,
        'de.png',
      );
      expect(screen.frames.single.screenshot.imagePath, 'en.png');
    });
  });

  group('delocalizeEdit', () {
    test('new words in German are German\'s, and English keeps its own', () {
      final base = _screen(caption: english);
      final seen = localizeScreen(base, 'de-DE');
      final edited = seen.copyWith(
        caption: seen.caption!.copyWith(text: 'Audio überall bearbeiten'),
      );

      final written = delocalizeEdit(
        base: base,
        edited: edited,
        language: 'de-DE',
      );
      expect(written.caption!.text, english.text);
      expect(
        written.caption!.translations['de-DE']!.text,
        'Audio überall bearbeiten',
      );
    });

    test('a colour changed in German changes it in every language', () {
      final base = _screen(caption: english);
      final seen = localizeScreen(base, 'de-DE');
      final edited = seen.copyWith(
        caption: seen.caption!.copyWith(color: const Color(0xFFFF0000)),
      );

      final written = delocalizeEdit(
        base: base,
        edited: edited,
        language: 'de-DE',
      );
      expect(written.caption!.color.toARGB32(), 0xFFFF0000);
      expect(
        written.caption!.translations,
        isEmpty,
        reason: 'no words changed, so no translation was made',
      );
    });

    test('a face chosen in one language is that language\'s', () {
      final base = _screen(caption: english);
      final seen = localizeScreen(base, 'ja-JP');
      final written = delocalizeEdit(
        base: base,
        edited: seen.copyWith(
          caption: seen.caption!.copyWith(fontFamily: 'Noto Sans JP'),
        ),
        language: 'ja-JP',
      );
      expect(written.caption!.fontFamily, english.fontFamily);
      expect(
        written.caption!.translations['ja-JP']!.fontFamily,
        'Noto Sans JP',
      );
      expect(written.caption!.translations['ja-JP']!.size, isNull);
    });

    test('a label is translated the same way', () {
      final base = _screen(shapes: [ShapeSpec.text('Try it free')]);
      final seen = localizeScreen(base, 'fr-FR');
      final shape = seen.shapes.single;
      final written = delocalizeEdit(
        base: base,
        edited: seen.copyWith(
          shapes: [
            shape.copyWith(label: shape.label!.copyWith(text: 'Essai gratuit')),
          ],
        ),
        language: 'fr-FR',
      );
      final label = written.shapes.single.label!;
      expect(label.text, 'Try it free');
      expect(label.translations['fr-FR']!.text, 'Essai gratuit');
      expect(
        localizeScreen(written, 'fr-FR').shapes.single.label!.text,
        'Essai gratuit',
      );
    });

    test('a capture picked in German is German\'s alone', () {
      final base = _screen(
        frames: [
          FramePlacement(
            deviceId: 'd',
            variantId: 'v',
            screenshot: ScreenshotSpec.of('en.png'),
          ),
        ],
      );
      final seen = localizeScreen(base, 'de-DE');
      final frame = seen.frames.single;
      final written = delocalizeEdit(
        base: base,
        edited: seen.copyWith(
          frames: [
            frame.copyWith(
              screenshot: frame.screenshot.copyWith(imagePath: 'de.png'),
            ),
          ],
        ),
        language: 'de-DE',
      );
      final shot = written.frames.single.screenshot;
      expect(shot.imagePath, 'en.png');
      expect(shot.localeImages, {'de-DE': 'de.png'});
    });

    test('a layer added in German is added to the design', () {
      final base = _screen(caption: english);
      final seen = localizeScreen(base, 'de-DE');
      final written = delocalizeEdit(
        base: base,
        edited: seen.copyWith(shapes: [ShapeSpec.text('Neu')]),
        language: 'de-DE',
      );
      expect(written.shapes, hasLength(1));
    });
  });

  group('persistence', () {
    test('translations and captures round-trip', () {
      final screen = _screen(
        caption: english.copyWith(
          translations: const {
            'de-DE': CaptionTranslation(text: 'Überall', size: 44),
          },
        ),
        shapes: [
          ShapeSpec.text('Free').copyWith(
            label: const ShapeLabel(
              'Free',
              translations: {'es-ES': LabelTranslation(text: 'Gratis')},
            ),
          ),
        ],
        frames: [
          FramePlacement(
            deviceId: 'd',
            variantId: 'v',
            screenshot: ScreenshotSpec.of(
              'en.png',
            ).copyWith(localeImages: {'de-DE': 'de.png'}),
          ),
        ],
      );
      final back = screenDocFromJson(
        jsonDecode(jsonEncode(screenDocToJson(screen))) as Map<String, dynamic>,
      );
      expect(back.caption!.translations['de-DE']!.text, 'Überall');
      expect(back.caption!.translations['de-DE']!.size, 44);
      expect(back.shapes.single.label!.translations['es-ES']!.text, 'Gratis');
      expect(back.frames.single.screenshot.localeImages, {'de-DE': 'de.png'});
    });

    test('a project remembers its languages, and old ones are English', () {
      final project = Project(
        id: 'p',
        name: 'App',
        subProjects: const [],
        createdAt: DateTime(2026),
        languages: const ['en-US', 'de-DE', 'ja-JP'],
      );
      final json =
          jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>;
      expect(Project.fromJson(json).languages, ['en-US', 'de-DE', 'ja-JP']);

      json.remove('languages');
      expect(Project.fromJson(json).languages, [kDefaultLanguage]);
    });

    test('backups carry every language\'s captures', () {
      final screen = _screen(
        frames: [
          FramePlacement(
            deviceId: 'd',
            variantId: 'v',
            screenshot: ScreenshotSpec.of(
              '/lib/en.png',
            ).copyWith(localeImages: {'de-DE': '/lib/de.png'}),
          ),
        ],
      );
      expect(ProjectArchive.referencedImagesIn([screen]), {
        '/lib/en.png': LibraryImageKind.screenshot,
        '/lib/de.png': LibraryImageKind.screenshot,
      });
    });

    test('a retouch of a language\'s capture survives other edits', () {
      final spec = ScreenshotSpec.of('en.png').copyWith(
        localeImages: {'de-DE': 'de.png'},
        edits: {
          'de.png': {'crop': true},
        },
      );
      expect(spec.copyWith(scale: 1.2).edits.keys, contains('de.png'));
    });
  });
}
