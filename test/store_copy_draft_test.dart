// The built-in first draft: every field of every offered store written from
// the brief, inside its limit, with none of the words each store's review
// rejects — and never another platform's name in Apple copy, whatever the
// brief says.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/domain/listing/listing_analysis.dart';
import 'package:mockmyapp/domain/listing/listing_heuristics.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/store_copy/copy_draft.dart';
import 'package:mockmyapp/domain/store_copy/copy_lint.dart';
import 'package:mockmyapp/domain/store_copy/copy_text.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';

/// A brief that says everything a store would reject: other platforms,
/// prices, "free", "best", "#1", "new", a link and another company's name.
const _risky =
    'Wayfare is the best trip planner, #1 for travellers. Plan trips, keep '
    'every booking and ticket together, and find your way with offline maps. '
    'Free to download on iPhone, Android and Google Play, Pro is \$4.99. New: '
    'share plans with friends like on Instagram. See https://wayfare.example.';

ListingBrief _briefOf(String description, {String appName = ''}) {
  final analysis = heuristicAnalysis(description, appName: appName);
  return ListingBrief.fromAnalysis(analysis, description: description);
}

final _briefs = <String, ListingBrief>{
  'risky': _briefOf(_risky, appName: 'Wayfare'),
  'wizard': _briefOf(
    'Arrow rush game. escape all the arrow out of the screen. entertaining '
    'game',
  ),
  'hand-written': const ListingBrief(
    appName: 'Habitly',
    description:
        'Habitly helps you build habits that stick. Tick off each habit in a '
        'tap, see your streaks grow, and get a gentle reminder when it '
        'matters.',
    audience: 'People building better routines, one day at a time.',
    category: TemplateCategory.health,
    keywords: ['habit tracker', 'routine', 'streaks', 'daily goals'],
    features: [
      ListingFeature(
        title: 'Tick Off Habits',
        detail: 'One tap marks a habit done.',
        importance: 9,
      ),
      ListingFeature(
        title: 'Streaks',
        detail: 'Watch your run of good days grow.',
      ),
      ListingFeature(
        title: 'Gentle Reminders',
        detail: 'A nudge at the time you choose.',
      ),
    ],
    usps: ['Private: your habits stay on your phone'],
  ),
  'japanese': const ListingBrief(
    appName: '旅のしおり',
    description: '旅行の計画をもっと簡単に。予約、地図、チケットをひとつの場所にまとめます。オフラインでも使えます。',
    keywords: ['旅行', '計画', '地図', '予約', 'チケット', 'オフライン', '観光', 'ホテル', 'フライト'],
  ),
  'empty': ListingBrief.empty,
};

const _captions = ['Plan trips in minutes', 'Every booking in one list'];

void _expectWithinLimits(CopyStore store, Map<String, String> draft) {
  for (final MapEntry(key: id, value: text) in draft.entries) {
    final spec = store.field(id)!;
    final count = countField(spec, text);
    expect(count.over, isFalse, reason: '${store.name}.$id: ${count.label}');
  }
}

void main() {
  for (final MapEntry(key: label, value: brief) in _briefs.entries) {
    group('the "$label" brief', () {
      final source = DraftSource.from(
        brief,
        projectName: 'Wayfare',
        captions: _captions,
      );

      for (final store in CopyStore.values.where((s) => s.offered)) {
        test('drafts ${store.label} inside every limit, with no warning', () {
          final draft = draftStoreCopy(store, source);
          expect(draft, isNotEmpty);
          _expectWithinLimits(store, draft);
          final issues = lintCopy(store, draft, appName: source.name);
          expect(issues, isEmpty, reason: issues.join('\n'));
        });
      }

      test('never names another platform in Apple copy', () {
        for (final store in [CopyStore.appStore, CopyStore.macAppStore]) {
          final draft = draftStoreCopy(store, source);
          for (final MapEntry(key: id, value: text) in draft.entries) {
            expect(
              findOtherPlatform(text, store),
              isNull,
              reason: '${store.name}.$id: $text',
            );
            expect(text.toLowerCase(), isNot(contains('android')));
            expect(text.toLowerCase(), isNot(contains('google play')));
          }
        }
      });

      test('keeps prices, "free" and ranking words out of names', () {
        for (final store in [CopyStore.appStore, CopyStore.playStore]) {
          final draft = draftStoreCopy(store, source);
          final name = draft['name'] ?? draft['title'] ?? '';
          expect(playPromoPattern.hasMatch(name), isFalse, reason: name);
          expect(pricePattern.hasMatch(name), isFalse, reason: name);
          expect(freeClaimPattern.hasMatch(name), isFalse, reason: name);
        }
        final apple = draftStoreCopy(CopyStore.appStore, source);
        for (final text in apple.values) {
          expect(freeClaimPattern.hasMatch(text), isFalse, reason: text);
          expect(pricePattern.hasMatch(text), isFalse, reason: text);
          expect(linkPattern.hasMatch(text), isFalse, reason: text);
        }
      });
    });
  }

  group('the App Store draft', () {
    final source = DraftSource.from(_briefs['hand-written']!);
    final draft = draftStoreCopy(CopyStore.appStore, source);

    test('writes every Apple field', () {
      expect(draft.keys, [
        'name',
        'subtitle',
        'keywords',
        'promotionalText',
        'description',
        'whatsNew',
      ]);
    });

    test('names the app and what it is', () {
      expect(draft['name'], 'Habitly: Habit Tracker');
    });

    test('packs keywords Apple\'s way', () {
      final keywords = draft['keywords']!;
      expect(keywords, isNot(contains(' ')));
      expect(measureCopy(keywords, CopyUnit.bytes), lessThanOrEqualTo(100));
      final terms = keywords.split(',');
      expect(terms.toSet().length, terms.length);
      // Nothing the name or subtitle already says.
      final covered = {
        ...wordsOf(draft['name']!),
        ...wordsOf(draft['subtitle']!),
      };
      expect(terms.where(covered.contains), isEmpty);
      expect(terms, contains('routine'));
    });

    test('lays the description out as plain text with bullets', () {
      final description = draft['description']!;
      expect(description, startsWith('Habitly helps you build habits'));
      expect(description, contains('• Tick Off Habits: One tap marks'));
      expect(description, isNot(contains('<')));
    });
  });

  group('the Google Play draft', () {
    final source = DraftSource.from(
      _briefs['hand-written']!,
      captions: const ['Track every habit', 'Your headline', 'See streaks'],
    );
    final draft = draftStoreCopy(CopyStore.playStore, source);

    test('writes every Play field, alt text from the captions', () {
      expect(draft.keys, [
        'title',
        'shortDescription',
        'fullDescription',
        'releaseNotes',
        'altText',
      ]);
      // A starter screen's placeholder is no caption to describe.
      expect(
        draft['altText'],
        'Habitly screen: Track every habit\nHabitly screen: See streaks',
      );
    });

    test('fits the short description into 80 characters', () {
      expect(
        measureCopy(draft['shortDescription']!, CopyUnit.chars),
        lessThanOrEqualTo(80),
      );
    });
  });

  test('byte limits hold for a Japanese brief', () {
    final source = DraftSource.from(_briefs['japanese']!);
    final apple = draftStoreCopy(CopyStore.appStore, source);
    expect(
      measureCopy(apple['keywords']!, CopyUnit.bytes),
      lessThanOrEqualTo(100),
    );
    final galaxy = draftStoreCopy(CopyStore.galaxyStore, source);
    expect(
      measureCopy(galaxy['shortDescription'] ?? '', CopyUnit.bytes),
      lessThanOrEqualTo(40),
    );
  });

  test('a description longer than the field is cut, not refused', () {
    final long = List.filled(
      400,
      'Plan every trip with bookings and maps together.',
    ).join(' ');
    final source = DraftSource.from(
      ListingBrief(appName: 'Wayfare', description: long),
    );
    final draft = draftStoreCopy(CopyStore.appStore, source);
    expect(
      measureCopy(draft['description']!, CopyUnit.chars),
      lessThanOrEqualTo(4000),
    );
  });

  test('one field at a time, for Regenerate', () {
    final source = DraftSource.from(_briefs['hand-written']!);
    final only = draftStoreCopy(CopyStore.appStore, source, only: {'subtitle'});
    expect(only.keys, ['subtitle']);
  });

  test('Regenerate moves to the next alternative where there is one', () {
    final source = DraftSource.from(_briefs['hand-written']!);
    final first = draftStoreCopy(CopyStore.appStore, source);
    final second = draftStoreCopy(CopyStore.appStore, source, variant: 1);
    expect(second['subtitle'], isNot(first['subtitle']));
    // The same brief and variant always draft the same listing.
    expect(draftStoreCopy(CopyStore.appStore, source), first);
  });

  test('every field has a role, so every store can be drafted', () {
    for (final store in CopyStore.values) {
      for (final field in store.allFields) {
        expect(() => roleOf(field), returnsNormally);
      }
    }
    expect(roleOf(CopyStore.appStore.field('keywords')!), CopyRole.keywords);
    expect(roleOf(CopyStore.playStore.field('altText')!), CopyRole.screenshots);
  });
}
