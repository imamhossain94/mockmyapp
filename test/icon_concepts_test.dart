// Glyph concepts: the rules pick 6–12 Lucide glyphs and palettes from the
// brief, deterministically, with every glyph readable on its fill; the
// device's model picks from the rules' shortlist instead where there is one,
// and a reply that does not hold together is refused — the rules answer and
// the page is told.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/icons/icon_concepts.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';

Map<String, IconDef> readLucide() {
  final json =
      jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final i in json['icons'] as List)
      (i as Map<String, dynamic>)['n'] as String: IconDef.fromJson(i),
  };
}

class _FakeModel implements TextCompleter {
  _FakeModel(this.reply, {this.state = ModelState.ready, this.fails = false});

  final String reply;
  final ModelState state;
  final bool fails;
  final prompts = <String>[];

  @override
  Future<EngineStatus> completerStatus() async =>
      EngineStatus(AiEngine.geminiNano, state);

  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async {
    prompts.add(prompt);
    if (fails) throw const OnDeviceAiException('The model fell over.');
    return reply;
  }
}

const _travel = IconBrief(
  appName: 'Wayfare',
  description: 'Plan trips: bookings, maps and tickets in one place.',
  category: TemplateCategory.travel,
  keywords: ['trip planner', 'itinerary'],
);

void main() {
  final icons = readLucide();

  test('every curated glyph is in the bundled set', () {
    for (final MapEntry(:key, :value) in kCategoryGlyphs.entries) {
      for (final name in value) {
        expect(icons.containsKey(name), isTrue, reason: '$key: $name');
      }
    }
    for (final name in kEverydayGlyphs) {
      expect(icons.containsKey(name), isTrue, reason: name);
    }
    for (final category in TemplateCategory.values) {
      expect(kCategoryGlyphs[category], isNotEmpty, reason: '$category');
    }
  });

  group('the rules', () {
    test('give a round of readable glyph concepts for the brief', () {
      final concepts = ruleIconConcepts(_travel, icons);
      expect(concepts, hasLength(kDefaultConcepts));
      for (final concept in concepts) {
        final glyph = concept.doc.glyph!;
        expect(icons.containsKey(glyph), isTrue);
        expect(kAvoidedGlyphs.contains(glyph), isFalse);
        expect(
          glyphContrast(concept.doc.glyphColor, concept.doc.background),
          greaterThanOrEqualTo(kMinGlyphContrast),
          reason: '${concept.name} must read on its fill',
        );
      }
      // The category's own marks lead, with the brief's words — a trip
      // planner — lifting the plane to the front.
      expect(concepts.first.doc.glyph, 'plane');
      expect(
        concepts.map((c) => c.doc.glyph),
        containsAll(['compass', 'map', 'luggage']),
      );
      // One variant of each idea.
      final families = [
        for (final c in concepts)
          if (!kCategoryGlyphs[TemplateCategory.travel]!.contains(c.doc.glyph))
            c.doc.glyph!.split('-').first,
      ];
      expect(families.toSet(), hasLength(families.length));
      // A mix of grounds: gradients, solids and a pattern.
      expect(
        concepts.map((c) => c.doc.background.runtimeType).toSet(),
        containsAll([GradientBackground, SolidBackground, PatternBackground]),
      );
    });

    test('are the same for the same brief, and new on the next roll', () {
      String names(List<IconConcept> list) => [
        for (final c in list)
          '${c.doc.glyph}:${jsonEncode(c.doc.toJson()['background'])}',
      ].join('|');
      final a = ruleIconConcepts(_travel, icons);
      final b = ruleIconConcepts(_travel, icons);
      final next = ruleIconConcepts(_travel, icons, roll: 1);
      expect(names(a), names(b));
      expect(names(next), isNot(names(a)));
    });

    test('hold a round to six to twelve', () {
      expect(ruleIconConcepts(_travel, icons, count: 2), hasLength(6));
      expect(ruleIconConcepts(_travel, icons, count: 40), hasLength(12));
    });

    test('find glyphs by the brief\'s words when it names no category', () {
      const brief = IconBrief(
        appName: 'Penny',
        keywords: ['savings', 'budget'],
      );
      final shortlist = candidateGlyphs(brief, icons);
      expect(shortlist, contains('piggy-bank'));
      final concepts = ruleIconConcepts(brief, icons);
      expect(concepts, hasLength(kDefaultConcepts));
      expect(concepts.first.rationale, 'Picked for your brief.');
    });

    test('dress the first in the listing\'s own colours', () {
      const brief = IconBrief(
        appName: 'Wayfare',
        category: TemplateCategory.travel,
        palette: [Color(0xFF0B3D4C), Color(0xFFFF6B5A)],
      );
      final first = ruleIconConcepts(brief, icons).first;
      // No ink reads on the whole teal-to-coral ramp, so the teal carries the
      // glyph on its own — the person's colour as it is, never darkened.
      expect(first.doc.background, isA<SolidBackground>());
      expect(
        (first.doc.background as SolidBackground).color,
        const Color(0xFF0B3D4C),
      );
      expect(first.rationale, contains('your listing'));

      // Two colours an ink reads across stay a gradient.
      const readable = IconBrief(
        appName: 'Wayfare',
        palette: [Color(0xFF0B3D4C), Color(0xFF3A1C71)],
      );
      final ramp = ruleIconConcepts(readable, icons).first.doc.background;
      expect(ramp, isA<GradientBackground>());
      expect((ramp as GradientBackground).colors, const [
        Color(0xFF0B3D4C),
        Color(0xFF3A1C71),
      ]);
    });

    test('never suggest another company\'s mark', () {
      const brief = IconBrief(
        appName: 'Orchard',
        keywords: ['apple', 'github', 'fruit'],
        category: TemplateCategory.food,
      );
      final shortlist = candidateGlyphs(brief, icons, max: 60);
      expect(shortlist.where(kAvoidedGlyphs.contains), isEmpty);
    });

    test('still have something to say about an empty brief', () {
      final concepts = ruleIconConcepts(const IconBrief(appName: ''), icons);
      expect(concepts, hasLength(kDefaultConcepts));
      expect(concepts.first.rationale, 'A versatile mark to start from.');
    });
  });

  group('a device model\'s reply', () {
    final candidates = candidateGlyphs(_travel, icons);

    test('is read into concepts', () {
      final concepts = parseDeviceIconReply('''Here you go:
```json
[{"name": "North star", "glyph": "compass", "colors": ["#0B3D4C", "#1E7A8C"], "glyphColor": "#FFFFFF"},
 {"name": "Take off", "glyph": "plane", "colors": ["#FF6B5A"]}]
```''', candidates: candidates);
      expect(concepts, hasLength(2));
      expect(concepts.first.name, 'North star');
      expect(concepts.first.doc.background, isA<GradientBackground>());
      expect(concepts.last.doc.background, isA<SolidBackground>());
      // Left out, so chosen: whichever ink reads on coral.
      expect(
        glyphContrast(
          concepts.last.doc.glyphColor,
          concepts.last.doc.background,
        ),
        greaterThanOrEqualTo(kMinGlyphContrast),
      );
    });

    test('drops items that do not hold together, never repairs them', () {
      final concepts = parseDeviceIconReply(
        jsonEncode({
          'icons': [
            // Not on the list.
            {
              'glyph': 'github',
              'colors': ['#000000'],
              'glyphColor': '#FFFFFF',
            },
            // Unreadable: white on pale yellow.
            {
              'glyph': 'plane',
              'colors': ['#FFF8C0'],
              'glyphColor': '#FFFFFF',
            },
            // A colour that does not parse.
            {
              'glyph': 'map',
              'colors': ['teal'],
              'glyphColor': '#FFFFFF',
            },
            // A glyph colour given badly.
            {
              'glyph': 'globe',
              'colors': ['#123456'],
              'glyphColor': 'white',
            },
            // Fine.
            {
              'glyph': 'compass',
              'colors': ['#0B3D4C'],
              'glyphColor': '#FFD166',
            },
            // The same glyph again.
            {
              'glyph': 'compass',
              'colors': ['#222222'],
              'glyphColor': '#FFFFFF',
            },
          ],
        }),
        candidates: candidates,
      );
      expect(concepts.map((c) => c.doc.glyph), ['compass']);
      expect(concepts.single.doc.glyphColor, const Color(0xFFFFD166));
    });

    test('with nothing usable in it is refused', () {
      for (final reply in [
        'I would suggest a compass on teal.',
        '[{"glyph": "rocket-ship", "colors": ["#000000"]}]',
        '{"answer": 42}',
        '[{"glyph": "compass", "colors": ["#FFFFFF"], "glyphColor": "#FAFAFA"}]',
        '[{"glyph": "compass"',
      ]) {
        expect(
          () => parseDeviceIconReply(reply, candidates: candidates),
          throwsA(isA<IconConceptsRejected>()),
          reason: reply,
        );
      }
    });
  });

  group('the director', () {
    String goodReply(int count) => jsonEncode([
      for (final (i, glyph) in candidateGlyphs(
        _travel,
        icons,
      ).take(count).indexed)
        {
          'name': 'Idea $i',
          'glyph': glyph,
          'colors': ['#0B3D4C', '#1E7A8C'],
          'glyphColor': '#FFFFFF',
        },
    ]);

    test('uses the device\'s model when it answers well', () async {
      final model = _FakeModel(goodReply(8));
      final result = await IconConceptDirector(model).suggest(_travel, icons);
      expect(result.engine, AiEngine.geminiNano);
      expect(result.note, isNull);
      expect(result.concepts, hasLength(8));
      expect(result.concepts.first.name, 'Idea 0');
      // It chose from a shortlist the rules drew up, and was told the brief.
      expect(model.prompts.single, startsWith('Glyphs: plane, '));
      expect(model.prompts.single, contains('compass'));
      expect(model.prompts.single, contains('Category: Travel'));
    });

    test('tops up a short answer from the rules, and says so', () async {
      final result = await IconConceptDirector(
        _FakeModel(goodReply(3)),
      ).suggest(_travel, icons);
      expect(result.concepts, hasLength(kMinConcepts));
      expect(result.note, contains('suggested 3'));
      expect(
        result.concepts.map((c) => c.doc.glyph).toSet(),
        hasLength(kMinConcepts),
      );
    });

    test('refuses a bad reply and lets the rules answer', () async {
      final result = await IconConceptDirector(
        _FakeModel('Sorry, I cannot help with that.'),
      ).suggest(_travel, icons);
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, contains("didn't give a usable answer"));
      expect(result.concepts, hasLength(kDefaultConcepts));
    });

    test('lets the rules answer when the model fails', () async {
      final result = await IconConceptDirector(
        _FakeModel('', fails: true),
      ).suggest(_travel, icons);
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, contains("couldn't answer"));
    });

    test('uses the rules quietly where there is no model', () async {
      for (final director in [
        const IconConceptDirector(null),
        IconConceptDirector(_FakeModel('[]', state: ModelState.unavailable)),
      ]) {
        final result = await director.suggest(_travel, icons);
        expect(result.engine, AiEngine.phrasebook);
        expect(result.note, isNull);
        expect(await director.engine(), AiEngine.phrasebook);
      }
    });
  });

  test('a concept is an ordinary icon, editable and saved like any other', () {
    final concept = ruleIconConcepts(_travel, icons).first;
    final json = jsonDecode(jsonEncode(concept.doc.toJson()));
    expect(IconDoc.fromJson(json), concept.doc);
  });
}
