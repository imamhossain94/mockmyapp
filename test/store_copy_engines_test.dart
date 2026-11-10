// The engines behind "Draft with AI" and "Translate": the device's model
// laid over the rules, and the device's translator line by line.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/listing/listing_analysis.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/store_copy/copy_draft.dart';
import 'package:mockmyapp/domain/store_copy/copy_lint.dart';
import 'package:mockmyapp/domain/store_copy/copy_translate.dart';
import 'package:mockmyapp/domain/store_copy/device_copy.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';

const _brief = ListingBrief(
  appName: 'Wayfare',
  description:
      'Wayfare plans trips: every booking, map and ticket in one place, '
      'with maps that work offline.',
  audience: 'Travellers who are tired of juggling apps.',
  keywords: ['trip planner', 'itinerary', 'travel'],
  features: [
    ListingFeature(
      title: 'Every Booking Together',
      detail: 'Flights, hotels and trains in one list.',
      importance: 9,
    ),
    ListingFeature(title: 'Offline Maps', detail: 'Find your way anywhere.'),
  ],
  usps: ['Works without a signal'],
);

/// A model that answers with [reply], or fails.
class _FakeModel implements TextCompleter {
  _FakeModel(this.reply, {this.state = ModelState.ready, this.fails = false});

  final String reply;
  final ModelState state;
  final bool fails;
  final prompts = <String>[];

  @override
  Future<EngineStatus> completerStatus() async =>
      EngineStatus(AiEngine.appleIntelligence, state);

  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async {
    prompts.add('$instructions\n---\n$prompt');
    if (fails) throw const OnDeviceAiException('The model is asleep.');
    return reply;
  }
}

/// A translator that marks each piece, so the test sees what went in.
class _MarkingTranslator implements TextTranslator {
  final calls = <List<String>>[];

  @override
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  }) async => const EngineStatus(AiEngine.appleTranslation, ModelState.ready);

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async {
    calls.add(texts);
    return [for (final t in texts) t.trim().isEmpty ? t : 'de:$t'];
  }
}

void main() {
  final source = DraftSource.from(_brief);

  group('the device\'s model', () {
    test(
      'writes the short fields and the opening; the rules do the rest',
      () async {
        final model = _FakeModel(
          '1. NAME: Wayfare: Trip Planner\n'
          '**SUBTITLE:** Bookings, maps and tickets\n'
          'KEYWORDS: itinerary, vacation, android, journey\n'
          'PROMO: Your whole trip, finally in one place.\n'
          'INTRO: Wayfare keeps every part of a trip together. Even offline, '
          'on iPhone and Android.\n',
        );
        final result = await DeviceCopyWriter(model).draft(
          CopyStore.appStore,
          source,
          language: 'en-US',
          inBriefLanguage: true,
        );
        expect(result.engine, AiEngine.appleIntelligence);
        final f = result.fields;
        expect(f['name'], 'Wayfare: Trip Planner');
        expect(f['subtitle'], 'Bookings, maps and tickets');
        // Tidied the Apple way: no spaces, nothing the name has, no Android.
        expect(f['keywords'], 'itinerary,vacation,journey');
        // The model's opening, with the rules' features under it — and the
        // other platform taken out of Apple copy.
        expect(
          f['description'],
          startsWith(
            'Wayfare keeps every part of a trip together. Even offline, '
            'on iPhone.',
          ),
        );
        expect(f['description'], contains('What you get'));
        expect(f['whatsNew'], isNotEmpty);
        expect(lintCopy(CopyStore.appStore, f, appName: 'Wayfare'), isEmpty);
        // The model is told the limits and the language.
        expect(model.prompts.single, contains('at most 100 bytes'));
        expect(model.prompts.single, contains('Language: English (US).'));
      },
    );

    test('in another language, only what the model wrote', () async {
      final model = _FakeModel(
        'NAME: Wayfare: Reiseplaner\nINTRO: Alle Reisen an einem Ort.',
      );
      final result = await DeviceCopyWriter(model).draft(
        CopyStore.appStore,
        source,
        language: 'de-DE',
        inBriefLanguage: false,
      );
      expect(result.fields, {
        'name': 'Wayfare: Reiseplaner',
        'description': 'Alle Reisen an einem Ort.',
      });
      expect(model.prompts.single, contains('Language: German.'));
    });

    test('a model that fails hands over to the rules, and says so', () async {
      final result = await DeviceCopyWriter(_FakeModel('', fails: true)).draft(
        CopyStore.playStore,
        source,
        language: 'en-US',
        inBriefLanguage: true,
      );
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, contains('The model is asleep.'));
      expect(result.fields['title'], isNotEmpty);
    });

    test('no model at all: the built-in rules, labelled as such', () async {
      const writer = DeviceCopyWriter(null);
      expect(await writer.engine(), AiEngine.phrasebook);
      final result = await writer.draft(
        CopyStore.playStore,
        source,
        language: 'en-US',
        inBriefLanguage: true,
      );
      expect(result.engine, AiEngine.phrasebook);
      expect(result.note, isNull);
      // The rules write only in the brief's language.
      expect(
        () => writer.draft(
          CopyStore.playStore,
          source,
          language: 'ja-JP',
          inBriefLanguage: false,
        ),
        throwsA(isA<OnDeviceAiException>()),
      );
    });

    test('a model still downloading is not asked', () async {
      final model = _FakeModel('NAME: x', state: ModelState.unavailable);
      final result = await DeviceCopyWriter(model).draft(
        CopyStore.appStore,
        source,
        language: 'en-US',
        inBriefLanguage: true,
      );
      expect(model.prompts, isEmpty);
      expect(result.engine, AiEngine.phrasebook);
    });
  });

  group('the device\'s translator', () {
    test('keeps lines and bullets, translates keywords one by one', () async {
      final translator = _MarkingTranslator();
      final out = await DeviceCopyTranslator(translator).translate(
        CopyStore.appStore,
        {
          'name': 'Wayfare',
          'keywords': 'itinerary,travel,vacation',
          'description': 'Plan trips.\n\n• Offline maps\n• Every booking',
        },
        from: 'en-US',
        to: 'de-DE',
      );
      expect(translator.calls.single, [
        'Wayfare',
        'itinerary',
        'travel',
        'vacation',
        'Plan trips.',
        '',
        'Offline maps',
        'Every booking',
      ]);
      expect(out['name'], 'de:Wayfare');
      expect(out['keywords'], 'de:itinerary,de:travel,de:vacation');
      expect(
        out['description'],
        'de:Plan trips.\n\n• de:Offline maps\n• de:Every booking',
      );
    });

    test('an indented bullet keeps its indent and its mark', () async {
      final translator = _MarkingTranslator();
      final out = await DeviceCopyTranslator(translator).translate(
        CopyStore.playStore,
        {'fullDescription': 'Lists:\n  • Offline maps'},
        from: 'en-US',
        to: 'de-DE',
      );
      expect(translator.calls.single, ['Lists:', 'Offline maps']);
      expect(out['fullDescription'], 'de:Lists:\n  • de:Offline maps');
    });

    test(
      'never cuts a translation that runs long; the counter says so',
      () async {
        final translator = _LengtheningTranslator();
        final out = await DeviceCopyTranslator(translator).translate(
          CopyStore.appStore,
          {'subtitle': 'Every booking together'},
          from: 'en-US',
          to: 'de-DE',
        );
        final subtitle = out['subtitle']!;
        expect(subtitle, 'Jede einzelne Buchung an einem gemeinsamen Ort');
        final issue = lintCopy(CopyStore.appStore, out).single;
        expect(issue.rule, CopyRule.overLimit);
        expect(issue.fix, startsWith('Cut '));
      },
    );

    test('packs translated keywords back into 100 bytes', () async {
      final out = await DeviceCopyTranslator(_JapaneseTranslator()).translate(
        CopyStore.appStore,
        {'keywords': List.generate(20, (i) => 'word$i').join(',')},
        from: 'en-US',
        to: 'ja-JP',
      );
      expect(utf8.encode(out['keywords']!).length, lessThanOrEqualTo(100));
    });
  });
}

class _LengtheningTranslator extends _MarkingTranslator {
  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async => ['Jede einzelne Buchung an einem gemeinsamen Ort'];
}

class _JapaneseTranslator extends _MarkingTranslator {
  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async => [for (var i = 0; i < texts.length; i++) '旅行計画$i'];
}
