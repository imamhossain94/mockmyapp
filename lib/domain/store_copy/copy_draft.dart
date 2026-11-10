/// The built-in first draft of a store listing: no model, no network, on
/// every platform — Windows and Linux included.
///
/// Not a language model and not pretending to be one; the page labels it
/// "built-in". It reads the brief the way a copywriter would skim it — the
/// name, the sentence that says what the app does, the features, what sets
/// it apart, the words people search with — and lays them into each store's
/// fields: inside every limit, and without the words each store's review
/// rejects. Every field it writes is the person's to edit.
///
/// Deterministic, so the same brief drafts the same listing; [variant]
/// rotates through the alternatives a field has (another keyword in the
/// name, another feature in the subtitle) for "Regenerate".
library;

import 'package:flutter/foundation.dart';

import '../listing/listing_analysis.dart';
import '../listing/listing_heuristics.dart';
import '../models/listing_brief.dart';
import 'copy_lint.dart' show kTrademarkNames, tidyAppleKeywords;
import 'copy_text.dart';
import 'store_limits.dart';

/// What a field is for, whichever store it belongs to — so one set of rules
/// drafts every store's fields.
enum CopyRole {
  name,
  subtitle,
  keywords,
  promo,
  short,
  long,
  release,
  features,
  screenshots,
}

/// The role [field] plays.
CopyRole roleOf(CopyFieldSpec field) {
  if (field.perScreenshot) return CopyRole.screenshots;
  if (field.keywords) return CopyRole.keywords;
  return switch (field.id) {
    'name' || 'title' || 'shortTitle' => CopyRole.name,
    'subtitle' => CopyRole.subtitle,
    'promotionalText' => CopyRole.promo,
    'shortDescription' || 'briefIntro' => CopyRole.short,
    'whatsNew' || 'releaseNotes' => CopyRole.release,
    'features' => CopyRole.features,
    _ => CopyRole.long,
  };
}

/// What the rules draft from: the brief, with what it leaves out read from
/// its own description — or from the screenshots' captions, for a project
/// whose brief is still empty.
@immutable
class DraftSource {
  const DraftSource({
    required this.name,
    required this.description,
    required this.audience,
    required this.features,
    required this.usps,
    required this.keywords,
    required this.captions,
  });

  /// [brief] filled out, so there is always something to write from.
  ///
  /// [projectName] stands in for a brief with no name, and [captions] — the
  /// project's headlines, in order — for one with no description; they also
  /// give Play its alt text.
  factory DraftSource.from(
    ListingBrief brief, {
    String projectName = '',
    List<String> captions = const [],
  }) {
    final name = [
      brief.appName.trim(),
      projectName.trim(),
    ].firstWhere((n) => n.isNotEmpty, orElse: () => 'My app');
    final cleanCaptions = [
      for (final c in captions)
        if (c.replaceAll(RegExp(r'\s+'), ' ').trim() case final t
            when t.isNotEmpty && !isPlaceholderCaption(t))
          t,
    ];
    // Links come out before anything reads the description: a store takes
    // none, and the analysis would otherwise make a feature of a web address.
    final description = stripMatches(
      brief.description.trim().isNotEmpty
          ? brief.description.trim()
          : cleanCaptions.map(_sentence).join(' '),
      linkPattern,
    );
    // The built-in analysis fills whatever the brief does not say. It reads
    // the same description the wizard did, so a wizard project gets back
    // what it already had.
    final analysis = heuristicAnalysis(description, appName: name);
    bool linkFree(String text) =>
        !linkPattern.hasMatch(text) &&
        !wordsOf(text).any((w) => w == 'https' || w == 'http' || w == 'www');
    final features = [
      for (final f
          in brief.features.isNotEmpty ? brief.features : analysis.features)
        if (linkFree(f.title) && linkFree(f.detail)) f,
    ];
    return DraftSource(
      name: name,
      description: description,
      audience: brief.audience.trim().isNotEmpty
          ? brief.audience.trim()
          : analysis.audience,
      features: [...features]
        ..sort((a, b) => b.importance.compareTo(a.importance)),
      usps: [
        for (final u in brief.usps.isNotEmpty ? brief.usps : analysis.usps)
          if (linkFree(u) && _clause(u).isNotEmpty) _clause(u),
      ],
      keywords: {...brief.keywords, ...analysis.keywords}.toList(),
      captions: cleanCaptions,
    );
  }

  final String name;
  final String description;
  final String audience;
  final List<ListingFeature> features;
  final List<String> usps;
  final List<String> keywords;
  final List<String> captions;
}

/// Whether [caption] is a starter screen's placeholder ("Your headline")
/// rather than words somebody wrote — the same test the store preview uses
/// before it borrows a headline.
bool isPlaceholderCaption(String caption) => RegExp(
  r'^(your headline|highlight feature)',
  caseSensitive: false,
).hasMatch(caption.trim());

/// Every field of [store] drafted from [source], each inside its limit.
///
/// [only] limits the draft to those field ids — a per-field Regenerate.
Map<String, String> draftStoreCopy(
  CopyStore store,
  DraftSource source, {
  Set<String>? only,
  int variant = 0,
}) {
  final writer = _Writer(store, source, variant);
  final out = <String, String>{};
  for (final field in store.allFields) {
    if (only != null && !only.contains(field.id)) continue;
    final text = writer.write(field, out);
    if (text.isNotEmpty) out[field.id] = text;
  }
  return out;
}

/// [text] made fit to go into [field] of [store] — the guarantees every
/// draft gets on its way to the page, whoever wrote it: the rules or the
/// model on this device.
///
/// * Apple copy never names another platform (guideline 2.3.10): the names
///   come out and the sentence is mended.
/// * A name or a one-line description carries no ranking or promotional
///   word, which Google Play rejects there and the house tone avoids
///   everywhere.
/// * Apple's keywords are tidied — no spaces, duplicates, words the name or
///   subtitle carry, plurals, other companies — and packed into 100 bytes.
/// * Everything fits its limit, cut at a word; a list keeps its first items.
///
/// [name] and [subtitle] are the listing's own, for the keyword tidy.
String fitDraftField(
  CopyStore store,
  CopyFieldSpec field,
  String text, {
  String name = '',
  String subtitle = '',
  String appName = '',
}) {
  final role = roleOf(field);
  var out = text.trim();
  if (store.isApple) {
    out = scrubOtherPlatforms(out, mac: store == CopyStore.macAppStore);
  }
  if (role == CopyRole.name || role == CopyRole.short) {
    out = stripMatches(out, playPromoPattern);
  }
  if (field.isList) {
    final items = [
      for (final item in listItems(out))
        truncateCopy(item, field.limit, field.unit),
    ];
    return items.take(field.maxItems!).join('\n');
  }
  if (field.keywords) {
    if (store.isApple) {
      out = tidyAppleKeywords(
        out,
        name: name,
        subtitle: subtitle,
        appName: appName,
        mac: store == CopyStore.macAppStore,
      );
    }
    return packKeywords(out, field.limit);
  }
  return truncateCopy(out, field.limit, field.unit);
}

/// Words that never make a keyword: function words, filler, and the words
/// that every app could claim.
const _keywordStopwords = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'but',
  'for',
  'with',
  'without',
  'your',
  'you',
  'our',
  'we',
  'us',
  'in',
  'on',
  'of',
  'to',
  'by',
  'at',
  'from',
  'into',
  'out',
  'up',
  'it',
  'its',
  'is',
  'are',
  'be',
  'can',
  'will',
  'that',
  'this',
  'these',
  'those',
  'my',
  'me',
  'all',
  'every',
  'more',
  'most',
  'very',
  'just',
  'get',
  'gets',
  'make',
  'makes',
  'made',
  'use',
  'uses',
  'using',
  'works',
  'work',
  'one',
  'app',
  'apps',
  'application',
  'free',
  'best',
  'top',
  'new',
  'great',
  'easy',
  'simple',
  'need',
  'nothing',
  'do',
  'not',
  'so',
  'as',
  'than',
  'then',
  'also',
  'any',
  'way',
  'plans',
  // Wasted in Apple's field: every App Store search is already on an Apple
  // device, and nobody searches for "download".
  'download', 'iphone', 'ipad', 'ios', 'macos', 'apple',
  // Filler that reads as a word but nobody types into a store's search.
  'everything', 'everyone', 'place', 'thing', 'things', 'going', 'straight',
  'away', 'start', 'open', 'ready', 'see', 'keep', 'like', 'pro',
  // Half of another store's name (guideline 2.3.10, and the
  // metadata-optimization skill's own correction): "play", "google".
  'play', 'google', 'android', 'https', 'http', 'www',
};

/// The nouns a product is: a phrase ending in one ("trip planner", "photo
/// editor") makes a better second half of a name than one that does not
/// ("trips bookings").
const _productNouns = {
  'planner',
  'tracker',
  'editor',
  'maker',
  'manager',
  'builder',
  'creator',
  'generator',
  'scanner',
  'reader',
  'player',
  'recorder',
  'timer',
  'journal',
  'diary',
  'notes',
  'calendar',
  'budget',
  'wallet',
  'camera',
  'game',
  'puzzle',
  'quiz',
  'trainer',
  'coach',
  'workout',
  'guide',
  'translator',
  'keyboard',
  'launcher',
  'widgets',
  'browser',
  'studio',
  'designer',
  'mockup',
  'mockups',
  'screenshots',
  'organizer',
  'organiser',
  'reminders',
  'checklist',
  'habits',
  'meditation',
  'recipes',
  'dictionary',
  'flashcards',
  'radio',
  'podcasts',
  'weather',
  'fitness',
  'diet',
  'calories',
  'converter',
  'calculator',
};

/// Whether every word of [a] is in [b] — the same thing said twice.
bool _within(String a, String b) {
  final words = wordsOf(a);
  return words.isNotEmpty && words.every(wordsOf(b).contains);
}

class _Writer {
  _Writer(this.store, this.source, this.variant);

  final CopyStore store;
  final DraftSource source;
  final int variant;

  /// Whether [text] is fit to go into [role] of this store as it stands:
  /// nothing the store's review rejects, and nothing the house tone avoids
  /// (prices, rankings, links, other companies' names).
  bool _fits(String text, CopyRole role) {
    if (text.trim().isEmpty) return false;
    if (linkPattern.hasMatch(text)) return false;
    if (pricePattern.hasMatch(text)) return false;
    if (playPromoPattern.hasMatch(text)) return false;
    if (store.isApple && findOtherPlatform(text, store) != null) return false;
    if (store.isApple && freeClaimPattern.hasMatch(text)) return false;
    final own = wordsOf(source.name);
    if (wordsOf(
      text,
    ).any((w) => kTrademarkNames.contains(w) && !own.contains(w))) {
      return false;
    }
    return true;
  }

  /// The candidates that fit [role], in order, rotated by [variant].
  List<String> _pick(Iterable<String> candidates, CopyRole role) {
    final fit = [
      for (final c in candidates)
        if (_fits(c, role)) c.trim(),
    ];
    if (fit.isEmpty || variant == 0) return fit;
    final shift = variant % fit.length;
    return [...fit.skip(shift), ...fit.take(shift)];
  }

  String write(CopyFieldSpec field, Map<String, String> sofar) {
    final role = roleOf(field);
    final raw = switch (role) {
      CopyRole.name => _name(field),
      CopyRole.subtitle => _subtitle(field, sofar),
      CopyRole.keywords => _keywords(field, sofar),
      CopyRole.promo => _promo(field),
      CopyRole.short => _short(field),
      CopyRole.long => _long(),
      CopyRole.release => _release(),
      CopyRole.features => _featureLines(field),
      CopyRole.screenshots => _screenshots(field),
    };
    // The guarantees every draft gets on its way out; the keywords were
    // already tidied against the name and subtitle as they were written.
    return fitDraftField(store, field, raw);
  }

  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// "Wayfare: Trip Planner" — the name and the strongest search phrase it
  /// does not already say, when both fit; the name alone otherwise.
  String _name(CopyFieldSpec field) {
    final name = source.name;
    final own = wordsOf(name);
    int score(String phrase) {
      final words = phrase.toLowerCase().split(RegExp(r'\s+'));
      return (words.length == 2 ? 2 : 0) +
          (_productNouns.contains(words.last) ? 3 : 0);
    }

    final usable = [
      for (final k in source.keywords)
        if (wordsOf(k) case final words
            when words.isNotEmpty &&
                words.length <= 3 &&
                !words.any(own.contains) &&
                !words.any(_keywordStopwords.contains))
          k,
    ];
    // Best first, the analysis's own order kept among equals.
    final ranked = [...usable.indexed]
      ..sort((a, b) {
        final byScore = score(b.$2).compareTo(score(a.$2));
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
    // Only a phrase that names what the product is earns a place after the
    // name: "Wayfare: Trip Planner" helps search, "Wayfare: Bookings Maps"
    // only reads oddly. With none, the name stands alone.
    final phrases = _pick([
      for (final (_, k) in ranked)
        if (_productNouns.contains(k.toLowerCase().split(RegExp(r'\s+')).last))
          k,
    ], CopyRole.name);
    for (final phrase in phrases) {
      final candidate = '$name: ${_titleCase(phrase)}';
      if (measureCopy(candidate, field.unit) <= field.limit) return candidate;
    }
    return name;
  }

  /// A feature or what sets the app apart, in a line that does not repeat
  /// the name.
  String _subtitle(CopyFieldSpec field, Map<String, String> sofar) {
    final named = wordsOf(sofar['name'] ?? source.name);
    // Two words at least: a one-word feature title ("Find") is a fragment,
    // not a subtitle.
    final candidates = _pick([
      for (final f in source.features)
        if (wordsOf(f.title).length >= 2) f.title,
      for (final u in source.usps)
        if (wordsOf(u).length >= 2) u,
    ], CopyRole.subtitle);
    String? fallback;
    for (final c in candidates) {
      final text = _sentenceCase(c);
      if (measureCopy(text, field.unit) > field.limit) continue;
      if (wordsOf(text).where(named.contains).isEmpty) return text;
      fallback ??= text;
    }
    return fallback ??
        (candidates.isEmpty
            ? ''
            : truncateCopy(
                _sentenceCase(candidates.first),
                field.limit,
                field.unit,
              ));
  }

  /// Single words people search with, none the name or subtitle already
  /// carries, packed into Apple's 100 bytes.
  String _keywords(CopyFieldSpec field, Map<String, String> sofar) {
    final words = <String>[];
    void add(String phrase) {
      for (final w in wordsOf(phrase)) {
        if (w.length < 3 || _keywordStopwords.contains(w)) continue;
        if (RegExp(r'^\d+$').hasMatch(w)) continue;
        if (!words.contains(w)) words.add(w);
      }
    }

    // The person's search words first, then what the features say, then the
    // rest of the description: Apple gives 100 bytes, and an empty byte is a
    // search the app does not show up in.
    source.keywords.forEach(add);
    for (final f in source.features) {
      add(f.title);
    }
    for (final f in source.features) {
      add(f.detail);
    }
    source.usps.forEach(add);
    add(source.description);
    final tidy = tidyAppleKeywords(
      words.join(','),
      name: sofar['name'] ?? source.name,
      subtitle: sofar['subtitle'] ?? '',
      appName: source.name,
      mac: store == CopyStore.macAppStore,
    );
    return packKeywords(tidy, field.limit);
  }

  /// What sets the app apart, then what it does — the line above the
  /// description.
  String _promo(CopyFieldSpec field) {
    final usps = _pick(source.usps, CopyRole.promo);
    final details = _pick([
      for (final f in source.features)
        if (f.detail.trim().isNotEmpty) f.detail,
    ], CopyRole.promo);
    final usp = usps.firstOrNull;
    final detail = details.firstOrNull;
    final parts = [
      // Said once: a selling point the feature's sentence already holds, or
      // the other way round, would read twice.
      if (usp != null && (detail == null || !_within(usp, detail)))
        _sentence(usp),
      if (detail != null && (usp == null || !_within(detail, usp)))
        _sentence(detail),
    ];
    return _fitSentences(parts, field);
  }

  /// One line under the name: what the app does, in the person's words where
  /// they fit.
  String _short(CopyFieldSpec field) {
    final candidates = _pick([
      ..._sentences(source.description).where((s) => s.length <= 120),
      for (final f in source.features)
        if (f.detail.trim().isNotEmpty) f.detail,
      ...source.usps,
    ], CopyRole.short);
    // A line of four words or more says what the app does; "Arrow rush
    // game." only names it, so it waits until nothing fuller fits.
    final fuller = [
      for (final c in candidates)
        if (wordsOf(c).length >= 4) c,
    ];
    for (final c in [...fuller, ...candidates]) {
      final text = _sentence(c);
      if (measureCopy(text, field.unit) <= field.limit) return text;
    }
    if (candidates.isEmpty) return '';
    return truncateCopy(_sentence(candidates.first), field.limit, field.unit);
  }

  /// The description: what it is, who it is for, what it does, what sets it
  /// apart — plain text, short paragraphs, "• " bullets.
  String _long() {
    final hook = _pick(_sentences(source.description), CopyRole.long);
    final features = _distinct([
      for (final f in source.features)
        if (_featureLine(f, CopyRole.long) case final line?) '• $line',
    ]);
    final usps = _distinct([
      for (final u in _pick(source.usps, CopyRole.long))
        if (!features.any((f) => _within(u, f))) u,
    ]);
    final audience = _fits(source.audience, CopyRole.long)
        ? source.audience
        : '';
    final paragraphs = [
      if (hook.isNotEmpty) hook.take(2).map(_sentence).join(' '),
      if (audience.isNotEmpty) 'Made for ${_lowerFirst(_sentence(audience))}',
      if (features.isNotEmpty) ['What you get', ...features].join('\n'),
      if (usps.isNotEmpty)
        [
          'Why ${source.name}',
          for (final u in usps) '• ${_sentenceCase(u)}',
        ].join('\n'),
    ];
    if (paragraphs.isEmpty) return source.name;
    return paragraphs.join('\n\n');
  }

  /// Release notes a person edits before each release: what this version
  /// brings, from the features.
  String _release() {
    final lines = [
      for (final f in source.features)
        if (_featureLine(f, CopyRole.release) case final line?) '• $line',
    ].take(3).toList();
    if (lines.isEmpty) return '';
    return ['In this version:', ...lines].join('\n');
  }

  String _featureLines(CopyFieldSpec field) {
    final lines = _distinct([
      for (final f in source.features) ?_featureLine(f, CopyRole.features),
      for (final u in source.usps)
        if (_fits(u, CopyRole.features)) _sentenceCase(u),
    ]);
    return lines.take(field.maxItems ?? lines.length).join('\n');
  }

  /// One feature as a line: "Offline maps: Find your way without a signal."
  /// — or just the sentence, when it already says everything the title does.
  String? _featureLine(ListingFeature f, CopyRole role) {
    if (!_fits(f.title, role)) return null;
    final detail = f.detail.trim();
    if (detail.isEmpty || !_fits(detail, role)) return f.title.trim();
    if (_within(f.title, detail)) return _sentence(detail);
    return '${f.title.trim()}: ${_sentence(detail)}';
  }

  /// [lines] without one that only repeats the words of a line before it.
  static List<String> _distinct(List<String> lines) {
    final out = <String>[];
    for (final line in lines) {
      if (out.any((kept) => _within(line, kept))) continue;
      out.add(line);
    }
    return out;
  }

  /// One line per screenshot, from its caption: what the screen shows, for
  /// someone who cannot see it.
  String _screenshots(CopyFieldSpec field) {
    final lines = [
      for (final c in source.captions.take(field.maxItems ?? 8))
        _fits(c, CopyRole.screenshots)
            ? '${source.name} screen: ${_sentenceCase(c.replaceAll(RegExp(r'[.!?]+$'), ''))}'
            : '${source.name} screen',
    ];
    return lines.join('\n');
  }

  /// [sentences], as many as fit [field] whole.
  String _fitSentences(List<String> sentences, CopyFieldSpec field) {
    var out = '';
    for (final s in sentences) {
      final next = out.isEmpty ? s : '$out $s';
      if (measureCopy(next, field.unit) > field.limit) break;
      out = next;
    }
    if (out.isEmpty && sentences.isNotEmpty) {
      return truncateCopy(sentences.first, field.limit, field.unit);
    }
    return out;
  }
}

// -----------------------------------------------------------------------------
// Words
// -----------------------------------------------------------------------------

/// [text]'s sentences, trimmed.
List<String> _sentences(String text) => [
  for (final s
      in text.replaceAll(RegExp(r'\s+'), ' ').split(RegExp(r'(?<=[.!?])\s+')))
    // Two words at least: "See." is what is left of a sentence whose link
    // came out.
    if (wordsOf(s).length >= 2) s.trim(),
];

/// [s] without an "and" left over at the start from the sentence it was cut
/// out of.
String _clause(String s) => s.trim().replaceFirst(
  RegExp(r'^(?:and|but|or|so|then|also)\s+', caseSensitive: false),
  '',
);

/// [s] as a sentence: a capital first, a full stop last.
String _sentence(String s) {
  final t = _sentenceCase(_clause(s));
  if (t.isEmpty) return t;
  return RegExp(r'[.!?…]$').hasMatch(t) ? t : '$t.';
}

String _sentenceCase(String s) {
  final t = s.trim();
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

String _lowerFirst(String s) {
  if (s.length < 2) return s.toLowerCase();
  // An acronym or a name stays as written: "NASA fans", "iPhone owners".
  if (s[1] == s[1].toUpperCase() && s[1] != s[1].toLowerCase()) return s;
  return '${s[0].toLowerCase()}${s.substring(1)}';
}

/// Small words that stay lower case inside a title.
const _minor = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'of',
  'in',
  'on',
  'to',
  'for',
  'at',
  'by',
  'with',
};

String _titleCase(String s) {
  final words = s.trim().split(RegExp(r'\s+'));
  return [
    for (final (i, w) in words.indexed)
      if (w.isEmpty)
        w
      else if (i > 0 && _minor.contains(w.toLowerCase()))
        w.toLowerCase()
      else if (w.length > 1 && w.substring(1) != w.substring(1).toLowerCase())
        w
      else
        '${w[0].toUpperCase()}${w.substring(1)}',
  ].join(' ');
}
