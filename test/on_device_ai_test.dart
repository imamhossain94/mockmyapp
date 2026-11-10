import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';

/// A writer that answers whatever it is told to, for the fallback tests.
class _ScriptedWriter implements CaptionWriter {
  _ScriptedWriter(this.state, {this.ideas = const [], this.fails = false});

  final ModelState state;
  final List<CaptionIdea> ideas;
  final bool fails;
  int writes = 0;

  @override
  Future<EngineStatus> writerStatus() async =>
      EngineStatus(AiEngine.appleIntelligence, state);

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async {
    writes++;
    if (fails) throw const OnDeviceAiException('asleep');
    return ideas;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading a model\'s answer', () {
    test('strips numbering, bullets, bold, quotes and labels', () {
      final ideas = parseCaptionIdeas('''
Here are five captions:
1. **Track every penny** | Budgets that update themselves
2) "Spend smarter" — See where it all goes
- Headline: Money, sorted | Subtitle: One tap to categorise
• Your wallet's new best friend
''');
      expect(ideas, const [
        CaptionIdea(
          'Track every penny',
          subtitle: 'Budgets that update themselves',
        ),
        CaptionIdea('Spend smarter', subtitle: 'See where it all goes'),
        CaptionIdea('Money, sorted', subtitle: 'One tap to categorise'),
        CaptionIdea("Your wallet's new best friend"),
      ]);
    });

    test('drops repeats and lines too long to be a headline', () {
      final ideas = parseCaptionIdeas(
        'Plan trips fast\nplan trips fast\n'
        '${'A sentence that goes on far longer than any store headline ever '
            'should, because it is a paragraph'}\nShare your plans',
      );
      expect(ideas.map((i) => i.headline), [
        'Plan trips fast',
        'Share your plans',
      ]);
    });

    test('stops at the limit', () {
      final reply = List.generate(12, (i) => 'Caption $i').join('\n');
      expect(parseCaptionIdeas(reply, limit: 5), hasLength(5));
    });
  });

  group('asking', () {
    test('the prompt carries the brief, and cuts a long screen short', () {
      final prompt = captionPrompt(
        CaptionBrief(
          appName: 'Pocket',
          about: 'Track spending by category',
          screenText: 'x' * 900,
          current: 'Your headline goes here.',
          tone: CaptionTone.premium,
          language: 'de-DE',
          count: 4,
        ),
      );
      expect(prompt, contains('App: Pocket'));
      expect(prompt, contains('This screen: Track spending by category'));
      expect(prompt, contains('Language: German.'));
      expect(prompt, contains(CaptionTone.premium.description));
      expect(prompt, contains('Write 4 different captions.'));
      // 600 characters of screen and an ellipsis, not 900.
      expect(prompt, isNot(contains('x' * 601)));
      expect(prompt, contains('…'));
    });

    test('the house rules name the format the parser reads', () {
      expect(kCaptionInstructions, contains('Headline | Subtitle'));
      expect(kCaptionInstructions, contains('Never mention prices'));
    });
  });

  group('the phrasebook', () {
    test(
      'writes from the user\'s own words, in every tone, the same way twice',
      () {
        for (final tone in CaptionTone.values) {
          final brief = CaptionBrief(
            appName: 'Pocket',
            about: 'Track spending by category',
            tone: tone,
          );
          final first = phrasebookIdeas(brief);
          expect(first, hasLength(5), reason: tone.name);
          expect(phrasebookIdeas(brief), first, reason: 'deterministic');
          for (final idea in first) {
            expect(idea.headline.length, lessThanOrEqualTo(48));
            expect(idea.headline, isNot(contains('  ')));
          }
        }
      },
    );

    test('an action subject keeps its verb', () {
      final ideas = phrasebookIdeas(
        const CaptionBrief(appName: 'Trip', about: 'Plan trips with friends'),
      );
      expect(ideas.first.headline, 'Plan trips with friends');
    });

    test('reads the screen when told nothing, skipping chrome and numbers', () {
      final ideas = phrasebookIdeas(
        const CaptionBrief(
          appName: 'Pocket',
          screenText: '9:41\nLTE\nHome\n\$1,240.00\nMonthly budget\nGroceries',
        ),
      );
      expect(ideas.first.headline.toLowerCase(), contains('monthly budget'));
    });

    test('still writes with nothing to go on', () {
      final ideas = phrasebookIdeas(const CaptionBrief(appName: ''));
      expect(ideas, isNotEmpty);
    });
  });

  group('re-breaking a translation', () {
    test('keeps a two-line headline on two lines', () {
      final out = rebreakLines(
        'Your headline\ngoes here.',
        'Ihre Überschrift steht hier.',
      );
      expect(out.split('\n'), hasLength(2));
      expect(out.replaceAll('\n', ' '), 'Ihre Überschrift steht hier.');
    });

    test(
      'leaves one line as one line, flattening what the translator broke',
      () {
        expect(
          rebreakLines('Plan trips', 'Planifiez\nvos voyages'),
          'Planifiez vos voyages',
        );
      },
    );

    test('never breaks a script written without spaces', () {
      expect(
        rebreakLines('Your headline\ngoes here.', '見出しはここに入ります'),
        '見出しはここに入ります',
      );
    });
  });

  group('choosing an engine', () {
    test('a ready model writes', () async {
      final model = _ScriptedWriter(
        ModelState.ready,
        ideas: const [CaptionIdea('From the model')],
      );
      final assistant = CaptionAssistant(model);
      expect(
        (await assistant.writerStatus()).engine,
        AiEngine.appleIntelligence,
      );
      final ideas = await assistant.write(const CaptionBrief(appName: 'X'));
      expect(ideas.single.headline, 'From the model');
    });

    test('no model, or an unavailable one, is the phrasebook', () async {
      for (final assistant in [
        CaptionAssistant(null),
        CaptionAssistant(_ScriptedWriter(ModelState.unavailable)),
      ]) {
        expect((await assistant.writerStatus()).engine, AiEngine.phrasebook);
        expect(
          await assistant.write(const CaptionBrief(appName: 'X')),
          isNotEmpty,
        );
      }
    });

    test('a model that fails hands over rather than leaving nothing', () async {
      final model = _ScriptedWriter(ModelState.ready, fails: true);
      final ideas = await CaptionAssistant(
        model,
      ).write(const CaptionBrief(appName: 'X', about: 'Share photos'));
      expect(model.writes, 1);
      expect(ideas, isNotEmpty);
    });

    test('with no translator the reason is said, not guessed at', () async {
      const translator = UnavailableTranslator('Not here.');
      final status = await translator.translationStatus(
        from: 'en-US',
        to: 'de-DE',
      );
      expect(status.usable, isFalse);
      expect(status.reason, 'Not here.');
      expect(
        () => translator.translate(['Hi'], from: 'en-US', to: 'de-DE'),
        throwsA(isA<OnDeviceAiException>()),
      );
    });
  });

  group('the platform channel', () {
    const channel = MethodChannel('mockmyapp/ai-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() => calls = []);
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void answer(Object? Function(MethodCall call) reply) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final out = reply(call);
          if (out is PlatformException) throw out;
          return out;
        });

    test('status is read back into the engine and state', () async {
      answer(
        (_) => {
          'engine': 'geminiNano',
          'state': 'needsDownload',
          'reason': null,
        },
      );
      final status = await NativeOnDeviceAi(channel: channel).writerStatus();
      expect(status.engine, AiEngine.geminiNano);
      expect(status.state, ModelState.needsDownload);
      expect(status.usable, isTrue);
    });

    test(
      'captions go out as instructions and a prompt, and come back parsed',
      () async {
        answer(
          (_) => '1. Split bills in seconds | No maths needed\n2. Even Steven',
        );
        final ideas = await NativeOnDeviceAi(
          channel: channel,
        ).write(const CaptionBrief(appName: 'Split', about: 'Split bills'));
        expect(calls.single.method, 'writeCaptions');
        final args = calls.single.arguments as Map;
        expect(args['instructions'], kCaptionInstructions);
        expect(args['prompt'], contains('App: Split'));
        expect(
          ideas.first,
          const CaptionIdea(
            'Split bills in seconds',
            subtitle: 'No maths needed',
          ),
        );
      },
    );

    test('a platform failure is an OnDeviceAiException', () async {
      answer((_) => PlatformException(code: 'ai_failed', message: 'Busy'));
      expect(
        () => NativeOnDeviceAi(
          channel: channel,
        ).translate(['Hello'], from: 'en-US', to: 'fr-FR'),
        throwsA(isA<OnDeviceAiException>()),
      );
    });

    test('blank texts are not sent at all', () async {
      answer((_) => fail('should not be called'));
      final out = await NativeOnDeviceAi(
        channel: channel,
      ).translate(['', '  '], from: 'en-US', to: 'fr-FR');
      expect(out, ['', '  ']);
      expect(calls, isEmpty);
    });

    test(
      'a missing platform side reads as unavailable, not as a crash',
      () async {
        // No handler at all: MissingPluginException under the hood.
        final ai = NativeOnDeviceAi(channel: channel);
        expect((await ai.writerStatus()).usable, isFalse);
        expect(await ai.canRead, isFalse);
        expect(await ai.read(Uint8List(4)), '');
      },
    );
  });
}
