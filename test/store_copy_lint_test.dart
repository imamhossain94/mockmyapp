// The live counters and the review checks under every store-copy field: what
// each store counts (characters as graphemes, bytes as UTF-8), and each rule —
// limits, Apple's keyword field, guidelines 2.3.7 and 2.3.10, Play's banned
// words, emoji and capitals — with the plain-English fix it offers.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/store_copy/copy_lint.dart';
import 'package:mockmyapp/domain/store_copy/copy_text.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';

CopyFieldSpec _spec(CopyStore store, String id) => store.field(id)!;

List<CopyRule> _rules(
  CopyStore store,
  Map<String, String> fields, {
  String appName = '',
}) => [for (final i in lintCopy(store, fields, appName: appName)) i.rule];

CopyIssue _issue(
  CopyStore store,
  Map<String, String> fields,
  CopyRule rule, {
  String appName = '',
}) =>
    lintCopy(store, fields, appName: appName).firstWhere((i) => i.rule == rule);

void main() {
  group('counters', () {
    test('count characters as people see them', () {
      expect(measureCopy('café', CopyUnit.chars), 4);
      expect(measureCopy('👩‍💻 dev', CopyUnit.chars), 5);
      expect(measureCopy('🇯🇵', CopyUnit.chars), 1);
    });

    test('count bytes as Apple and Samsung do', () {
      expect(measureCopy('café', CopyUnit.bytes), 5);
      expect(measureCopy('বাংলা', CopyUnit.bytes), 15);
      expect(measureCopy('旅行', CopyUnit.bytes), 6);
      expect(measureCopy('Привет', CopyUnit.bytes), 12);
    });

    test('say how much is left, or how far over', () {
      final name = _spec(CopyStore.appStore, 'name');
      final count = countField(name, 'Wayfare');
      expect(count.used, 7);
      expect(count.left, 23);
      expect(count.over, isFalse);
      expect(count.label, '7/30 · 23 left');
      final over = countField(name, 'x' * 34);
      expect(over.over, isTrue);
      expect(over.label, '34/30 · 4 over');
    });

    test('count Apple keywords in bytes', () {
      final keywords = _spec(CopyStore.appStore, 'keywords');
      // Ten Japanese characters are 30 bytes — a third of the field.
      final count = countField(keywords, '旅行,計画,地図,予約,切符');
      expect(count.unit, CopyUnit.bytes);
      expect(count.used, 34);
      expect(count.label, '34/100 bytes · 66 left');
    });

    test('count a Galaxy Store short description in bytes', () {
      final short = _spec(CopyStore.galaxyStore, 'shortDescription');
      expect(
        countField(short, 'Plan trips in minutes').label,
        '21/40 bytes · 19 left',
      );
      expect(countField(short, '여행을 몇 분 만에 계획하세요 지금').over, isTrue);
    });

    test('count a list by its items and its longest one', () {
      final features = _spec(CopyStore.microsoftStore, 'features');
      final count = countField(features, 'Offline maps\n\nEvery booking');
      expect(count.items, 2);
      expect(count.used, 'Every booking'.length);
      expect(count.label, '2/20 items · longest 13/200');
      final alt = _spec(CopyStore.playStore, 'altText');
      expect(
        countField(alt, 'Trips\nMaps').label,
        '2/8 screenshots · longest 5/140',
      );
    });
  });

  group('limits', () {
    test('a field over its limit is an error, with a cut that fits', () {
      final issue = _issue(CopyStore.appStore, {
        'subtitle': 'Every booking, map and ticket together',
      }, CopyRule.overLimit);
      expect(issue.isError, isTrue);
      expect(issue.message, contains('App Store Connect takes 30'));
      expect(issue.fix, 'Cut 8 characters.');
      expect(measureCopy(issue.fixed!, CopyUnit.chars), lessThanOrEqualTo(30));
      expect(issue.fixed, 'Every booking, map and ticket');
    });

    test('keywords over 100 bytes drop whole keywords to fit', () {
      final long = List.generate(20, (i) => 'keyword$i').join(',');
      final issue = _issue(CopyStore.appStore, {
        'keywords': long,
      }, CopyRule.overLimit);
      expect(issue.message, contains('bytes'));
      expect(measureCopy(issue.fixed!, CopyUnit.bytes), lessThanOrEqualTo(100));
      expect(issue.fixed!.split(',').every(long.split(',').contains), isTrue);
    });

    test('a one-letter Apple name is under the minimum', () {
      expect(_rules(CopyStore.appStore, {'name': 'W'}), [CopyRule.underMin]);
    });

    test('a list with too many items, or an item too long', () {
      final features = List.generate(21, (i) => 'Feature $i').join('\n');
      expect(
        _rules(CopyStore.microsoftStore, {'features': features}),
        contains(CopyRule.tooManyItems),
      );
      final issue = _issue(CopyStore.microsoftStore, {
        'features': 'Short one\n${'x' * 230}',
      }, CopyRule.overLimit);
      expect(issue.message, startsWith('Item 2 is 230 characters'));
      final alt = _issue(CopyStore.playStore, {
        'altText': 'Fine\n${'y' * 150}',
      }, CopyRule.overLimit);
      expect(alt.message, startsWith('Screenshot 2 is 150 characters'));
    });

    test('Amazon asks for three bullets at least', () {
      final issue = _issue(CopyStore.amazonAppstore, {
        'features': 'One\nTwo',
      }, CopyRule.tooFewItems);
      expect(issue.isError, isFalse);
      expect(issue.fix, 'Add 1 more, one per line.');
    });

    test('an empty field has nothing to say', () {
      expect(lintCopy(CopyStore.appStore, const {}), isEmpty);
    });
  });

  group('Apple keywords', () {
    const name = 'Wayfare: Trip Planner';
    const subtitle = 'Bookings and maps together';

    test('spaces after commas waste bytes, and tidying removes them', () {
      final issue = _issue(CopyStore.appStore, {
        'keywords': 'itinerary, travel, vacation',
      }, CopyRule.keywordSpaces);
      expect(issue.isError, isFalse);
      expect(issue.fix, 'Remove the spaces after commas.');
      expect(issue.fixed, 'itinerary,travel,vacation');
      expect(issue.fixLabel, 'Tidy keywords');
    });

    test('a keyword twice', () {
      final issue = _issue(CopyStore.appStore, {
        'keywords': 'travel,itinerary,Travel',
      }, CopyRule.keywordDuplicate);
      expect(issue.message, contains('twice'));
      expect(issue.fixed, 'travel,itinerary');
    });

    test('a word the name or subtitle already has', () {
      final issue = _issue(CopyStore.appStore, {
        'name': name,
        'subtitle': subtitle,
        'keywords': 'itinerary,planner,maps,vacation',
      }, CopyRule.keywordInNameOrSubtitle);
      expect(issue.message, contains('“planner” is already in the name'));
      expect(issue.fixed, 'itinerary,vacation');
    });

    test('a plural of a word already there', () {
      final issue = _issue(CopyStore.appStore, {
        'name': 'Wayfare',
        'keywords': 'journey,journeys,story,stories',
      }, CopyRule.keywordPlural);
      expect(issue.message, contains('“journeys” is the plural of “journey”'));
      expect(issue.fixed, 'journey,story');
      // A word that only looks plural is left alone.
      expect(
        _rules(CopyStore.appStore, {'keywords': 'chess,glass,news'}),
        isNot(contains(CopyRule.keywordPlural)),
      );
    });

    test('another company\'s name', () {
      final issue = _issue(CopyStore.appStore, {
        'keywords': 'photo editor,instagram,filters',
      }, CopyRule.trademark);
      expect(issue.message, contains('guideline 2.3.7'));
      expect(issue.fixed, 'photo editor,filters');
      // Unless it is the app's own name.
      expect(
        _rules(CopyStore.appStore, {'keywords': 'uber,rides'}, appName: 'Uber'),
        isNot(contains(CopyRule.trademark)),
      );
    });

    test('tidying takes out every soft problem at once', () {
      expect(
        tidyAppleKeywords(
          'trip , planner,Android,free,itinerary,itinerary,maps,tiktok',
          name: 'Wayfare: Trip Planner',
          subtitle: 'Bookings and maps',
        ),
        'itinerary',
      );
    });
  });

  group('Apple 2.3.7 and 2.3.10', () {
    test('another platform\'s name, mended out of the sentence', () {
      final issue = _issue(CopyStore.appStore, {
        'description': 'Plan trips on iPhone and Android. Bookings sync.',
      }, CopyRule.otherPlatform);
      expect(issue.message, contains('guideline 2.3.10'));
      expect(issue.fixed, 'Plan trips on iPhone. Bookings sync.');
      expect(
        _rules(CopyStore.appStore, {'subtitle': 'Get it on Google Play'}),
        contains(CopyRule.otherPlatform),
      );
    });

    test('Windows is the other platform on the Mac App Store only', () {
      const fields = {'description': 'Syncs with your Windows PC.'};
      expect(
        _rules(CopyStore.macAppStore, fields),
        contains(CopyRule.otherPlatform),
      );
      expect(
        _rules(CopyStore.appStore, fields),
        isNot(contains(CopyRule.otherPlatform)),
      );
    });

    test('prices and discounts', () {
      for (final text in [
        'Only \$4.99',
        'Now 50% off',
        'Half-price Pro',
        'Discounted plans',
        'Just 3 dollars',
      ]) {
        expect(
          _rules(CopyStore.appStore, {'subtitle': text}),
          contains(CopyRule.applePrice),
          reason: text,
        );
      }
      final issue = _issue(CopyStore.appStore, {
        'promotionalText': 'Pro is €2.99 this week.',
      }, CopyRule.applePrice);
      expect(issue.message, contains('guideline 2.3.7'));
      expect(issue.fix, contains('Remove the price'));
    });

    test('"free" as a price claim, but not ad-free or hands-free', () {
      expect(
        _rules(CopyStore.appStore, {'subtitle': 'Free trip planner'}),
        contains(CopyRule.appleFree),
      );
      for (final text in [
        'Ad-free trip planning',
        'Hands-free navigation',
        'Free of ads and trackers',
        'Freedom to roam',
      ]) {
        expect(
          _rules(CopyStore.appStore, {'description': text}),
          isNot(contains(CopyRule.appleFree)),
          reason: text,
        );
      }
    });

    test('another app\'s name in the name or subtitle', () {
      final issue = _issue(CopyStore.appStore, {
        'subtitle': 'Like Instagram for trips',
      }, CopyRule.trademark);
      expect(issue.fix, 'Remove “instagram”.');
    });

    test('Google Play copy may say Android', () {
      expect(
        _rules(CopyStore.playStore, {
          'fullDescription': 'Made for Android phones and tablets.',
        }),
        isEmpty,
      );
    });
  });

  group('Google Play', () {
    test('ranking, price and promotional words in the app name', () {
      for (final word in ['Best', '#1', 'Top', 'Free', 'New', 'Sale']) {
        final issue = _issue(CopyStore.playStore, {
          'title': '$word Trip Planner',
        }, CopyRule.playBannedWord);
        expect(issue.fix, 'Remove “$word”.', reason: word);
        expect(issue.fixed, 'Trip Planner', reason: word);
      }
    });

    test('the short description is checked too, the full one is not', () {
      expect(
        _rules(CopyStore.playStore, {
          'shortDescription': 'The best way to plan a trip',
        }),
        contains(CopyRule.playBannedWord),
      );
      expect(
        _rules(CopyStore.playStore, {
          'fullDescription': 'Our best work yet: every booking together.',
        }),
        isEmpty,
      );
    });

    test('ad-free is no promotion', () {
      expect(
        _rules(CopyStore.playStore, {'title': 'Ad-free Trip Planner'}),
        isEmpty,
      );
    });

    test('emoji and repeated punctuation in the app name', () {
      final emoji = _issue(CopyStore.playStore, {
        'title': 'Wayfare ✈️ Trips',
      }, CopyRule.playEmoji);
      expect(emoji.fixed, 'Wayfare Trips');
      expect(
        _rules(CopyStore.playStore, {'title': 'Wayfare!!!'}),
        contains(CopyRule.playSymbols),
      );
    });

    test('capitals, unless they are the brand', () {
      final issue = _issue(CopyStore.playStore, {
        'title': 'Wayfare AMAZING Trips',
      }, CopyRule.playAllCaps);
      expect(issue.fix, 'Write it as “Amazing”.');
      expect(issue.fixed, 'Wayfare Amazing Trips');
      expect(
        _rules(CopyStore.playStore, {
          'title': 'NASA Trips',
        }, appName: 'NASA Trips'),
        isEmpty,
      );
      expect(
        _rules(CopyStore.playStore, {
          'fullDescription':
              'PLAN EVERY TRIP IN MINUTES WITH ALL YOUR BOOKINGS IN ONE '
              'PLACE AND MAPS THAT WORK OFFLINE.',
        }),
        contains(CopyRule.playAllCaps),
      );
    });
  });

  group('every store', () {
    test('links and HTML', () {
      expect(
        _rules(CopyStore.galaxyStore, {
          'description': 'See https://wayfare.example for more.',
        }),
        contains(CopyRule.link),
      );
      final html = _issue(CopyStore.microsoftStore, {
        'description': '<b>Plan</b> trips',
      }, CopyRule.html);
      expect(html.fixed, 'Plan trips');
    });

    test('errors come before warnings', () {
      final issues = lintCopy(CopyStore.appStore, {
        'subtitle': 'Free trip planner for every single traveller',
      });
      expect(issues.first.level, CopyIssueLevel.error);
      expect(issues.last.level, CopyIssueLevel.warning);
    });
  });

  group('text operations match the server', () {
    test('cut at a word, or hard where the script has no spaces', () {
      expect(
        truncateCopy('Plan every trip in minutes', 18, CopyUnit.chars),
        'Plan every trip in',
      );
      expect(truncateCopy('旅行の計画をもっと簡単に楽しく', 6, CopyUnit.chars), '旅行の計画を');
      expect(truncateCopy('short', 30, CopyUnit.chars), 'short');
      expect(
        measureCopy(
          truncateCopy('বাংলা ভাষা সুন্দর', 20, CopyUnit.bytes),
          CopyUnit.bytes,
        ),
        lessThanOrEqualTo(20),
      );
    });

    test('pack keywords without spaces, duplicates or the name', () {
      expect(
        packKeywords('trip, Travel, travel planner, Wayfare, trip, maps', 100, [
          'Wayfare',
          'Trip planner',
        ]),
        'Travel,travel planner,maps',
      );
      final tight = packKeywords('alpha,bravo,charlie,delta', 17);
      expect(tight, 'alpha,bravo');
    });

    test('other platforms come out of Apple copy readably', () {
      const cases = {
        'Plan trips on iPhone and Android.': 'Plan trips on iPhone.',
        'Works on Android, iPhone and the web.': 'Works on iPhone and the web.',
        'Get it for Android today.': 'Get it today.',
        'Android and iPhone, in sync.': 'iPhone, in sync.',
        'Also on Google Play.': 'Also.',
        '• Offline maps\n• Android widgets\n• Android':
            '• Offline maps\n• widgets',
        'Your trips. Nothing else.': 'Your trips. Nothing else.',
      };
      for (final MapEntry(key: text, value: expected) in cases.entries) {
        final scrubbed = scrubOtherPlatforms(text);
        expect(scrubbed, expected, reason: text);
        expect(
          findOtherPlatform(scrubbed, CopyStore.appStore),
          isNull,
          reason: text,
        );
      }
      expect(
        scrubOtherPlatforms('Syncs with your Windows PC and Mac.', mac: true),
        isNot(contains('Windows')),
      );
    });
  });
}
