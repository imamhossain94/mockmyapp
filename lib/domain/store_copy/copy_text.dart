/// Small, exact operations on store-copy text: cutting to a limit, packing
/// Apple's keyword field, and taking other platforms' names out of Apple
/// copy.
///
/// Every draft goes through them on its way to the page, so a field the
/// rules fit and a field a model fits come out the same.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

import 'store_limits.dart';

/// The separators Apple accepts between keywords: the English comma, and the
/// Chinese, Japanese and Arabic ones.
final _keywordSeparators = RegExp('[,，、،]');

/// A run of letters or digits in any script — a word, for comparing.
final wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// [text]'s words, lower case.
Set<String> wordsOf(String text) => {
  for (final m in wordPattern.allMatches(text.toLowerCase())) m.group(0)!,
};

/// [text] cut to fit [limit] in [unit], at a word boundary where there is one.
///
/// A cut in the middle of a word backs up to the last space when that keeps
/// most of the text; scripts without spaces (Chinese, Japanese, Thai) keep the
/// hard cut. Trailing punctuation that would dangle is dropped.
String truncateCopy(String text, int limit, CopyUnit unit) {
  if (measureCopy(text, unit) <= limit) return text;
  final graphemes = text.characters.toList();
  final out = StringBuffer();
  var used = 0;
  var kept = 0;
  for (final g in graphemes) {
    final cost = unit == CopyUnit.bytes ? utf8.encode(g).length : 1;
    if (used + cost > limit) break;
    out.write(g);
    used += cost;
    kept++;
  }
  var cut = out.toString();
  final next = kept < graphemes.length ? graphemes[kept] : ' ';
  final midWord =
      !RegExp(r'\s').hasMatch(next) && !RegExp(r'\s$').hasMatch(cut);
  final space = cut.lastIndexOf(' ');
  if (midWord && space > cut.length * 0.6) cut = cut.substring(0, space);
  return cut.replaceFirst(RegExp(r'[\s,;:–—-]+$'), '');
}

/// The keyword terms in [text], trimmed, in order, empty ones dropped.
List<String> keywordTerms(String text) => [
  for (final raw in text.split(_keywordSeparators))
    if (raw.trim().replaceAll(RegExp(r'\s+'), ' ') case final t
        when t.isNotEmpty)
      t,
];

/// Apple's keyword field packed as tightly as Apple allows: deduplicated, no
/// spaces around commas, no term that is a word of [exclude] (the name and
/// subtitle, which Apple searches already), and whole terms dropped from the
/// end until it fits [limit] bytes.
String packKeywords(String text, int limit, [List<String> exclude = const []]) {
  final banned = {
    for (final s in exclude)
      for (final w in s.toLowerCase().split(RegExp(r'[\s,]+')))
        if (w.isNotEmpty) w,
  };
  final seen = <String>{};
  final words = <String>[];
  for (final word in keywordTerms(text)) {
    final key = word.toLowerCase();
    if (seen.contains(key) || banned.contains(key)) continue;
    seen.add(key);
    words.add(word);
  }
  while (words.isNotEmpty &&
      measureCopy(words.join(','), CopyUnit.bytes) > limit) {
    words.removeLast();
  }
  return words.join(',');
}

/// The items of a list field — one per line — trimmed, empty lines kept
/// where they hold a screenshot's place.
List<String> listItems(String text) {
  final lines = text.split('\n').map((l) => l.trim()).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

// -----------------------------------------------------------------------------
// Other platforms in Apple copy (guideline 2.3.10)
// -----------------------------------------------------------------------------

/// Names of other mobile platforms and app stores, which Apple's guideline
/// 2.3.10 keeps out of App Store metadata. Longest first, so "Google Play
/// Store" goes as one name rather than leaving "Store" behind.
const kOtherPlatformNames = [
  'google play store',
  'amazon appstore',
  'microsoft store',
  'galaxy store',
  'google play',
  'play store',
  'appgallery',
  'wear os',
  'android',
];

/// Also kept out of Mac App Store copy, where Windows is the other platform.
const kOtherDesktopNames = ['windows'];

/// The other-platform names that matter for [store].
List<String> otherPlatformNames(CopyStore store) => [
  ...kOtherPlatformNames,
  if (store == CopyStore.macAppStore) ...kOtherDesktopNames,
];

String _alternation(List<String> names) =>
    names.map((n) => n.split(' ').map(RegExp.escape).join(r'\s+')).join('|');

/// Whether [text] names another platform, for [store].
RegExpMatch? findOtherPlatform(String text, CopyStore store) => RegExp(
  '(?<![\\p{L}\\p{N}])(?:${_alternation(otherPlatformNames(store))})'
  '(?![\\p{L}\\p{N}])',
  caseSensitive: false,
  unicode: true,
).firstMatch(text);

/// [text] with every other platform's name taken out, and the sentence
/// mended around the gap: "on iPhone and Android" → "on iPhone", "Android,
/// iPhone and the web" → "iPhone and the web", "for Android" → "".
///
/// What it cannot mend it leaves readable rather than perfect — a draft the
/// person edits, never a sentence that names another store.
String scrubOtherPlatforms(String text, {bool mac = false}) {
  final names = _alternation([
    ...kOtherPlatformNames,
    if (mac) ...kOtherDesktopNames,
  ]);
  final name = '(?:$names)';
  const edgeL = r'(?<![\p{L}\p{N}])';
  const edgeR = r'(?![\p{L}\p{N}])';
  // Spaces and tabs only, never a line break: a line is mended on its own,
  // and a paragraph never runs into the one before it.
  const sp = r'[ \t]';
  RegExp re(String source) =>
      RegExp(source, caseSensitive: false, unicode: true);
  final present = re('$edgeL$name$edgeR');

  return _mendLines(text, (line) {
    if (!present.hasMatch(line)) return line;
    var out = line;
    // "iPhone, Android and the web" — a list item with a comma after it.
    out = out.replaceAll(re('$edgeL$name$edgeR$sp*,$sp*'), '');
    // "iPhone and Android", "iPhone or Android", "iPhone & Android".
    out = out.replaceAll(
      re('$sp*(?:,$sp*)?$edgeL(?:and|or|&|/)$sp+$edgeL$name$edgeR'),
      '',
    );
    // ", Android" at the end of a list.
    out = out.replaceAll(re('$sp*,$sp*$edgeL$name$edgeR'), '');
    // "Android and iPhone" at the head of a list.
    out = out.replaceAll(re('$edgeL$name$edgeR$sp+(?:and|or|&|/)$sp+'), '');
    // "on Android", "for Android", "from Google Play", "via the Play Store".
    out = out.replaceAll(
      re(
        '$sp*$edgeL(?:on|for|in|from|via|with|at)$sp+(?:the$sp+)?'
        '$edgeL$name$edgeR',
      ),
      '',
    );
    // Whatever is left alone: "Android phones" → "phones".
    out = out.replaceAll(re('(?:the$sp+)?$edgeL$name$edgeR$sp*'), '');
    return out;
  });
}

/// [text] with [change] made to each line, and only the lines it changed
/// mended — so a list's "In this version:" keeps its colon when the line
/// under it lost a word.
String _mendLines(String text, String Function(String line) change) {
  final bulletOnly = RegExp(r'^\s*[•*·-]\s*$');
  final out = <String>[];
  for (final line in text.split('\n')) {
    final changed = change(line);
    if (changed == line) {
      out.add(line);
      continue;
    }
    final mended = _mendLine(changed);
    if (line.trim().isNotEmpty &&
        (mended.isEmpty || bulletOnly.hasMatch(mended))) {
      continue;
    }
    out.add(mended);
  }
  return out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _mendLine(String line) => line
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'[ \t]+([,.;:!?])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'[,;:]\s*([.!?])'), (m) => m[1]!)
    .replaceAll(RegExp(r',\s*,'), ',')
    .replaceAll(RegExp(r'\(\s*\)'), '')
    .replaceFirst(RegExp(r'^(\s*)[,;:]\s*'), '')
    .replaceFirst(RegExp(r'[\s,;:–—-]+$'), '')
    .trimLeft();

// -----------------------------------------------------------------------------
// Words the stores' policies keep out
// -----------------------------------------------------------------------------

/// A price or a discount: "\$4.99", "3 dollars", "50% off", "half-price",
/// "discounted", "on sale". Apple keeps these out of metadata (2.3.7).
final pricePattern = RegExp(
  r'(?:[$€£¥₹₩₽¢]\s?\d)|(?:\d+(?:[.,]\d+)?\s?(?:usd|eur|gbp|dollars?|euros?)\b)'
  r'|(?:\b\d+\s?%\s?off\b)|(?:\bhalf[- ]price\b)|(?:\bdiscount(?:ed|s)?\b)'
  r'|(?:\bon sale\b)',
  caseSensitive: false,
);

/// "free" as a price — not "ad-free", "hands-free", "free of ads" or
/// "free-form", which say something else entirely.
final freeClaimPattern = RegExp(
  r'(?<![\p{L}\p{N}-])free(?![\p{L}\p{N}-])(?!\s+(?:of|from)\b)',
  caseSensitive: false,
  unicode: true,
);

/// Ranking, price and promotional words Google Play keeps out of an app's
/// name and short description: its metadata policy and listing guidance.
final playPromoPattern = RegExp(
  r'(?<![\p{L}\p{N}#-])(?:best|top|#1|no\.\s?1|number one|free|new|sale|'
  r'discount(?:s|ed)?|cheap(?:est)?|deals?|bonus|million downloads|'
  r'download now|install now|\d+\s?%\s?off)(?![\p{L}\p{N}-])'
  r'(?!\s+(?:of|from)\b)',
  caseSensitive: false,
  unicode: true,
);

/// A web address.
final linkPattern = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);

/// [text] with every match of [pattern] taken out and the spacing mended.
String stripMatches(String text, RegExp pattern) =>
    _mendLines(text, (line) => line.replaceAll(pattern, ''));

/// [text] with [word] taken out wherever it stands alone, and the spacing
/// mended — for a lint fix such as "remove “Best”".
String removeWord(String text, String word) {
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(word)}(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  return _mendLines(text, (line) => line.replaceAll(pattern, ''));
}
