// AI art direction: what a model's reply is allowed to become. A device
// model's JSON is checked field by field and refused when it does not hold
// together; the built-in rules answer deterministically everywhere. Plus the
// design's palette, which both keep to.

import 'dart:ui';

import 'package:flutter/painting.dart' show Alignment;
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/ai_backgrounds/art_direction.dart';
import 'package:mockmyapp/domain/ai_backgrounds/design_palette.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

/// A device model that answers [reply], or throws [error].
class _FakeCompleter implements TextCompleter {
  _FakeCompleter({this.reply = '', this.error, this.usable = true});

  final String reply;
  final Object? error;
  final bool usable;
  final prompts = <String>[];

  @override
  Future<EngineStatus> completerStatus() async => EngineStatus(
    AiEngine.geminiNano,
    usable ? ModelState.ready : ModelState.unavailable,
  );

  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async {
    prompts.add(prompt);
    if (error case final e?) throw e;
    return reply;
  }
}

const _brief = ArtBrief(appName: 'Wayfare', mood: 'calm travel, sunrise');

const _good = '''
[
  {"name": "Northern calm", "style": "aurora", "colors": ["#0B3D4C", "#FF6B5A", "#FFD3A5"], "scale": 1.2, "angle": 30, "intensity": 0.7, "seed": 99},
  {"name": "Dune line", "style": "dunes", "colors": ["#F4E1C1", "#C27A4A"], "scale": 0.9, "angle": 0, "intensity": 0.8}
]''';

void main() {
  group('a device model\'s reply', () {
    test('a clean array becomes suggestions, seeded by the app', () {
      final out = parseDeviceArtReply(_good, brief: _brief, seedBase: 1000);
      expect(out, hasLength(2));
      final first = out.first.background;
      expect(out.first.name, 'Northern calm');
      expect(first.style, PatternStyle.aurora);
      expect(first.colors, const [
        Color(0xFF0B3D4C),
        Color(0xFFFF6B5A),
        Color(0xFFFFD3A5),
      ]);
      expect(first.scale, 1.2);
      expect(first.angle, 30);
      expect(first.intensity, 0.7);
      // The model's own "seed" is ignored: the same suggestion must always
      // paint the same picture, which only the app can promise.
      expect(first.seed, 1000);
      expect(out[1].background.seed, isNot(first.seed));
      expect(first.slices, 1);
    });

    test('the wrapping small models add is looked past', () {
      final fenced = 'Sure! Here you go:\n```json\n$_good\n```\nEnjoy.';
      expect(
        parseDeviceArtReply(fenced, brief: _brief, seedBase: 1),
        hasLength(2),
      );
      final wrapped = '{"suggestions": $_good}';
      expect(
        parseDeviceArtReply(wrapped, brief: _brief, seedBase: 1),
        hasLength(2),
      );
    });

    test('prose with no JSON in it is refused', () {
      expect(
        () => parseDeviceArtReply(
          'Try a calm blue gradient with soft waves.',
          brief: _brief,
          seedBase: 1,
        ),
        throwsA(isA<ArtDirectionRejected>()),
      );
    });

    test('JSON cut short — the 320-token cap — is refused', () {
      final cut = _good.substring(0, _good.length ~/ 2);
      expect(
        () => parseDeviceArtReply(cut, brief: _brief, seedBase: 1),
        throwsA(isA<ArtDirectionRejected>()),
      );
    });

    test('JSON of the wrong shape is refused', () {
      for (final reply in ['"aurora"', '42', '{"style": "aurora"}', '[]']) {
        expect(
          () => parseDeviceArtReply(reply, brief: _brief, seedBase: 1),
          throwsA(isA<ArtDirectionRejected>()),
          reason: reply,
        );
      }
    });

    test('an item that does not hold together is dropped, the rest kept', () {
      const reply = '''[
        {"style": "volcano", "colors": ["#000000", "#FFFFFF"]},
        {"style": "mesh", "colors": ["#000000"]},
        {"style": "mesh", "colors": ["black", "white"]},
        {"style": "mesh", "colors": ["#000000", "#FFFFFF"], "scale": "big"},
        {"style": "symbols", "colors": ["#000000", "#FFFFFF"]},
        {"style": "Crest_Top", "colors": ["112233", "#445566"]}
      ]''';
      final out = parseDeviceArtReply(reply, brief: _brief, seedBase: 1);
      expect(out, hasLength(1));
      expect(out.single.background.style, PatternStyle.crestTop);
      expect(out.single.name, 'Crest top');
    });

    test('nothing usable at all is refused', () {
      const reply =
          '[{"style": "volcano", "colors": ["#000000", "#FFFFFF"]}, '
          '{"style": "mesh", "colors": [1, 2]}]';
      expect(
        () => parseDeviceArtReply(reply, brief: _brief, seedBase: 1),
        throwsA(isA<ArtDirectionRejected>()),
      );
    });

    test('numbers out of range are brought into it', () {
      const reply =
          '[{"style": "waves", "colors": ["#000000", "#FFFFFF", "#FF0000", '
          '"#00FF00", "#0000FF"], "scale": 9, "angle": -30, "intensity": 3}]';
      final b = parseDeviceArtReply(
        reply,
        brief: _brief,
        seedBase: 1,
      ).single.background;
      expect(b.scale, ArtRanges.scaleMax);
      expect(b.angle, 0);
      expect(b.intensity, 1);
      expect(b.colors, hasLength(4), reason: 'four stops at most');
    });

    test('a set of screens gets panoramas', () {
      final out = parseDeviceArtReply(
        _good,
        brief: const ArtBrief(appName: 'Wayfare', screens: 5),
        seedBase: 1,
      );
      expect(out.every((s) => s.background.slices == 5), isTrue);
    });
  });

  group('the built-in rules', () {
    test('are deterministic, and asking again gives new ones', () {
      final a = ruleArtDirection(_brief);
      final b = ruleArtDirection(_brief);
      expect(
        [for (final s in a) s.background.seed],
        [for (final s in b) s.background.seed],
      );
      expect(
        [for (final s in a) s.background.style],
        [for (final s in b) s.background.style],
      );
      final next = ruleArtDirection(_brief, roll: 1);
      expect(next.first.background.seed, isNot(a.first.background.seed));
    });

    test('read the mood in the brief', () {
      final calm = ruleArtDirection(_brief);
      expect(calm.first.background.style, PatternStyle.aurora);
      final game = ruleArtDirection(
        const ArtBrief(appName: 'Arrow Rush', mood: 'a fun puzzle game'),
      );
      expect(game.first.background.style, PatternStyle.confetti);
    });

    test('use the design\'s own colours first', () {
      const brand = [Color(0xFF0B3D4C), Color(0xFFFF6B5A)];
      final out = ruleArtDirection(
        const ArtBrief(appName: 'Wayfare', palette: brand),
      );
      expect(out.first.background.colors, brand);
      expect(out.first.name, endsWith('in your colours'));
      expect(out[1].background.colors, isNot(brand));
    });

    test('keep every motif readable against its base', () {
      for (final s in ruleArtDirection(_brief, count: 6)) {
        final colors = s.background.colors;
        final la = colors[0].computeLuminance();
        final lb = colors[1].computeLuminance();
        final ratio =
            (la > lb ? la + 0.05 : lb + 0.05) /
            (la > lb ? lb + 0.05 : la + 0.05);
        expect(ratio, greaterThan(1.5), reason: s.name);
      }
    });

    test('choose flowing styles for a set, as panoramas', () {
      final out = ruleArtDirection(
        const ArtBrief(appName: 'Arrow Rush', mood: 'puzzle game', screens: 4),
      );
      expect(out.every((s) => s.background.slices == 4), isTrue);
      expect(
        out.any((s) => s.background.style == PatternStyle.confetti),
        isFalse,
        reason: 'a scatter of confetti does not read as one picture',
      );
    });
  });

  group('the director on the device', () {
    test('uses the model when it answers well', () async {
      final model = _FakeCompleter(reply: _good);
      final result = await ArtDirector(model).suggest(_brief);
      expect(result.engine, AiEngine.geminiNano);
      expect(result.note, isNull);
      expect(result.suggestions.first.name, 'Northern calm');
      expect(model.prompts.single, contains('Mood: calm travel, sunrise'));
    });

    test(
      'hands over to the rules, and says so, when the JSON is bad',
      () async {
        final result = await ArtDirector(
          _FakeCompleter(reply: 'I like blue.'),
        ).suggest(_brief);
        expect(result.engine, AiEngine.phrasebook);
        expect(result.note, contains("didn't give a usable answer"));
        expect(result.suggestions, isNotEmpty);
      },
    );

    test('hands over when the model fails outright', () async {
      final result = await ArtDirector(
        _FakeCompleter(error: const OnDeviceAiException('busy')),
      ).suggest(_brief);
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, isNotNull);
    });

    test('with no model, the rules answer without a note', () async {
      final result = await const ArtDirector(null).suggest(_brief);
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, isNull);
      expect(await const ArtDirector(null).engine(), AiEngine.phrasebook);
    });

    test('an unavailable model is not asked', () async {
      final model = _FakeCompleter(reply: _good, usable: false);
      final result = await ArtDirector(model).suggest(_brief);
      expect(result.engine, AiEngine.phrasebook);
      expect(model.prompts, isEmpty);
    });
  });

  group('the design\'s palette', () {
    test('is the background and the shapes behind the device', () {
      const doc = ScreenDoc(
        id: 'a',
        canvas: Size(1290, 2796),
        background: GradientBackground(
          colorOne: Color(0xFF101830),
          colorTwo: Color(0xFFE0B080),
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      );
      expect(paletteOf(doc), const [Color(0xFF101830), Color(0xFFE0B080)]);
    });

    test('a photo backdrop has none', () {
      const doc = ScreenDoc(
        id: 'a',
        canvas: Size(1290, 2796),
        background: ImageBackground('/library/a.jpg'),
      );
      expect(paletteOf(doc), isEmpty);
    });

    test('is at most five colours, with no repeats', () {
      const doc = ScreenDoc(
        id: 'a',
        canvas: Size(1290, 2796),
        background: PatternBackground(
          style: PatternStyle.mesh,
          colors: [
            Color(0xFF000001),
            Color(0xFF000002),
            Color(0xFF000001),
            Color(0xFF000003),
          ],
        ),
      );
      expect(paletteOf(doc), hasLength(3));
      expect(paletteOf(doc, max: 2), hasLength(2));
    });
  });
}
