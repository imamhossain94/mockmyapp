// The AI screenshot generator's analysis with no model — the path every
// Windows and Linux user and most Android phones take — and the ranking and
// matching built on it. See `lib/domain/listing/`.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/listing/listing_analysis.dart';
import 'package:mockmyapp/domain/listing/listing_assistant.dart';
import 'package:mockmyapp/domain/listing/listing_heuristics.dart';
import 'package:mockmyapp/domain/listing/listing_prompt.dart';
import 'package:mockmyapp/domain/listing/template_match.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';

const _arrowRush =
    'Arrow rush game. escape all the arrow out of the screen. entertaining game';

const _music =
    'Sonary is a music player for Android. Listen to your favourite songs '
    'offline, build playlists for every mood and discover new artists every '
    'week. A ten-band equalizer with bass boost makes every track sound its '
    'best. Sleep timer, lyrics and a home-screen widget. No ads, no account '
    'needed — your music stays on your phone.';

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  group('heuristic analysis', () {
    test('reads a two-line game description as a game', () {
      final a = heuristicAnalysis(_arrowRush);

      expect(a.appName, 'Arrow Rush');
      expect(a.category, TemplateCategory.games);
      expect(a.engine, AiEngine.phrasebook);
      expect(a.keywords, contains('arrow rush'));
      expect(a.keywords, contains('escape game'));
      expect(a.plan, hasLength(kDefaultPlanLength));
      for (final item in a.plan) {
        expect(
          _words(item.headline),
          inInclusiveRange(2, 6),
          reason: '"${item.headline}" is not a headline',
        );
      }
      expect(a.features.length, inInclusiveRange(kMinFeatures, kMaxFeatures));
      expect(a.features.first.title, 'Escape All the Arrows');
      for (final f in a.features) {
        expect(f.importance, inInclusiveRange(1, 10));
      }
      expect(a.audience, isNotEmpty);
      expect(a.usps, isNotEmpty);
      expect(a.tips.length, inInclusiveRange(2, 4));
      expect(a.asoScore, inInclusiveRange(0, 100));
    });

    test('keeps the name it was given', () {
      final a = heuristicAnalysis(_arrowRush, appName: 'Quiver Dash');
      expect(a.appName, 'Quiver Dash');
      expect(a.keywords.first, 'quiver dash');
    });

    test('still makes a whole plan from almost nothing', () {
      for (final description in ['', 'ok', 'A tool.']) {
        final a = heuristicAnalysis(description);
        expect(a.plan, hasLength(kDefaultPlanLength), reason: description);
        expect(
          a.features.length,
          greaterThanOrEqualTo(kMinFeatures),
          reason: description,
        );
        expect(a.asoScore, lessThan(50), reason: description);
        expect(a.asoVerdict, 'Needs work');
      }
    });

    test('reads a music app as music, with its own name', () {
      final a = heuristicAnalysis(_music, planLength: 6);

      expect(a.appName, 'Sonary');
      expect(a.category, TemplateCategory.music);
      expect(a.plan, hasLength(6));
      expect(a.features.length, greaterThanOrEqualTo(4));
      expect(a.keywords, contains('sonary'));
      expect(a.keywords.length, greaterThanOrEqualTo(5));
      expect(
        a.usps.any((u) => u.toLowerCase().contains('no ads')),
        isTrue,
        reason: 'a stated differentiator is a USP: ${a.usps}',
      );
    });

    test('is deterministic', () {
      final one = heuristicAnalysis(_music);
      final two = heuristicAnalysis(_music);
      expect(two.plan, one.plan);
      expect(two.keywords, one.keywords);
      expect(two.features, one.features);
    });

    test('guesses categories from vocabulary', () {
      expect(
        guessCategory('Track every expense and stick to a monthly budget'),
        TemplateCategory.finance,
      );
      expect(
        guessCategory('Hundreds of recipes with a step-by-step cooking mode'),
        TemplateCategory.food,
      );
      expect(
        guessCategory('nothing telling here'),
        TemplateCategory.productivity,
      );
    });
  });

  group('ASO score', () {
    test('a more complete listing scores higher', () {
      final thin = heuristicAnalysis(_arrowRush);
      final full = heuristicAnalysis(_music);
      expect(full.asoScore, greaterThan(thin.asoScore));
      expect(full.asoScore, inInclusiveRange(0, 100));
      expect(thin.asoScore, inInclusiveRange(0, 100));
    });

    test('rises when the user adds keywords and features', () {
      final a = heuristicAnalysis(_music);
      final fewer = a
          .copyWith(keywords: a.keywords.take(2).toList())
          .rescored(_music);
      expect(fewer.asoScore, lessThan(a.asoScore));
      expect(
        fewer.tips.any((t) => t.kind == AsoTipKind.keyword),
        isTrue,
        reason: 'two keywords is worth a keyword tip',
      );
    });

    test('labels its verdicts', () {
      expect(asoLabel(10), 'Needs work');
      expect(asoLabel(60), 'Good');
      expect(asoLabel(90), 'Great');
    });
  });

  group('template matching', () {
    test('a game ranks the game listing first', () {
      final a = heuristicAnalysis(_arrowRush);
      final ranked = rankTemplates(
        a.category,
        screenTemplates,
        platform: TemplatePlatform.android,
        keywords: a.keywords,
      );
      expect(ranked, hasLength(screenTemplates.length));
      expect(ranked.first.template.category, TemplateCategory.games);
      expect(ranked.first.score, greaterThanOrEqualTo(95));
      for (final m in ranked) {
        expect(m.score, inInclusiveRange(0, 100));
        expect(m.reason, isNotEmpty);
      }
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i].score, lessThanOrEqualTo(ranked[i - 1].score));
      }
    });

    test('a related category beats an unrelated one', () {
      final ranked = rankTemplates(TemplateCategory.entertainment, [
        _template('a', TemplateCategory.finance),
        _template('b', TemplateCategory.music),
      ]);
      expect(ranked.first.template.id, 'b');
      expect(ranked.first.score, inInclusiveRange(65, 85));
      expect(ranked.last.score, lessThan(ranked.first.score));
    });

    test('screenshots follow the headline they share words with', () {
      final order = orderScreenshotsByPlan(
        ['Build playlists', 'Equalizer with bass boost', 'Sleep timer'],
        ['Sleep timer 30 min', 'Bass boost equalizer', 'My playlists'],
      );
      expect(order, [2, 1, 0]);
    });

    test('screenshots with nothing to read keep their order', () {
      expect(orderScreenshotsByPlan(['One', 'Two'], ['', '', '']), [0, 1, 2]);
    });
  });

  group('model replies', () {
    test('labelled lines are read, and gaps filled from the rules', () async {
      final assistant = ListingAssistant(
        _FakeModel(
          '1. **NAME:** Quiver Dash\n'
          'CATEGORY: Games\n'
          'AUDIENCE: Players who love quick reflex games.\n'
          '- FEATURE: Dodge the Arrows | Slip past every arrow on screen | 9\n'
          'FEATURE: Daily Challenges | A new puzzle every day | 7\n'
          'KEYWORDS: arrow game, reflex game, dodge\n'
          'HEADLINE: Dodge Every Arrow | Fast rounds, big thrills\n'
          'HEADLINE: A New Challenge Daily\n',
        ),
      );
      final a = await assistant.analyze(_arrowRush);

      expect(a.engine, AiEngine.geminiNano);
      expect(a.appName, 'Quiver Dash');
      expect(a.category, TemplateCategory.games);
      expect(a.features.first.title, 'Dodge the Arrows');
      expect(a.features.first.importance, 9);
      expect(a.features.length, greaterThanOrEqualTo(kMinFeatures));
      expect(a.keywords, containsAll(['arrow game', 'reflex game']));
      expect(a.plan, hasLength(kDefaultPlanLength));
      expect(
        a.plan.first,
        const PlanItem(
          'Dodge Every Arrow',
          subtitle: 'Fast rounds, big thrills',
        ),
      );
    });

    test('a reply with nothing usable falls back to the rules', () async {
      final a = await ListingAssistant(
        _FakeModel('Sorry, I cannot help with that.'),
      ).analyze(_arrowRush);
      expect(a.engine, AiEngine.phrasebook);
      expect(a.appName, 'Arrow Rush');
    });

    test('the prompt names the count and carries the description', () {
      final prompt = listingPrompt(_arrowRush, planLength: 4);
      expect(prompt, contains('4 HEADLINE'));
      expect(prompt, contains('escape all the arrow'));
      expect(kListingInstructions, contains('games'));
    });
  });
}

ScreenTemplate _template(String id, TemplateCategory category) =>
    ScreenTemplate(
      id: id,
      name: id,
      blurb: '',
      category: category,
      screens: [
        TemplateScreen.measured(
          background: const SolidBackground(Color(0xFF000000)),
          display: const SolidBackground(Color(0xFFFFFFFF)),
          text: 'Headline',
          textColor: const Color(0xFFFFFFFF),
          sizePct: 0.08,
          textTopPct: 0.06,
        ),
      ],
    );

class _FakeModel implements TextCompleter {
  _FakeModel(this.reply);

  final String reply;

  @override
  Future<EngineStatus> completerStatus() async =>
      const EngineStatus(AiEngine.geminiNano, ModelState.ready);

  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async => reply;
}
