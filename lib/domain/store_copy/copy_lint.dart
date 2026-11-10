/// Live counters and review checks for store copy — pure functions over the
/// text, run on every keystroke, whoever wrote the words.
///
/// Two kinds of finding:
///
/// * **errors** — the console refuses the field: over its limit, under its
///   minimum, too many items in a list;
/// * **warnings** — soft: what App Review or Google Play's policy team tends
///   to reject (Apple guidelines 2.3.7 and 2.3.10, Play's metadata policy),
///   and what wastes Apple's 100 keyword bytes. Never blocking; each one says
///   in plain words what to change, and offers the change where it can be
///   made for the person.
///
/// They behave the same whether a model, the built-in rules or the person
/// wrote the field.
library;

import 'package:flutter/foundation.dart';

import 'copy_text.dart';
import 'store_limits.dart';

/// How serious a finding is.
enum CopyIssueLevel {
  /// The console refuses it.
  error,

  /// Soft: likely to be rejected in review, or wasted space.
  warning,
}

/// Which check found it — for tests, and for one fix per field in the UI.
enum CopyRule {
  overLimit,
  underMin,
  tooManyItems,
  tooFewItems,
  keywordSpaces,
  keywordDuplicate,
  keywordInNameOrSubtitle,
  keywordPlural,
  trademark,
  applePrice,
  appleFree,
  otherPlatform,
  playBannedWord,
  playEmoji,
  playSymbols,
  playAllCaps,
  link,
  html,
}

/// One finding about one field.
@immutable
class CopyIssue {
  const CopyIssue({
    required this.field,
    required this.level,
    required this.rule,
    required this.message,
    required this.fix,
    this.fixed,
    this.fixLabel,
  });

  /// The field's id.
  final String field;
  final CopyIssueLevel level;
  final CopyRule rule;

  /// What is wrong, in a sentence.
  final String message;

  /// What to do about it, in a sentence.
  final String fix;

  /// The field's text with the fix made, when it can be made for the person.
  final String? fixed;

  /// What the button that makes [fixed] says — "Tidy keywords".
  final String? fixLabel;

  bool get isError => level == CopyIssueLevel.error;

  @override
  String toString() => '[${level.name}/${rule.name}] $field: $message $fix';
}

/// The counter under a field: how much is used, against what.
@immutable
class CopyCount {
  const CopyCount({
    required this.used,
    required this.limit,
    required this.unit,
    this.items,
    this.maxItems,
    this.itemNoun = 'items',
  });

  /// For a plain field, its length; for a list, its longest item.
  final int used;
  final int limit;
  final CopyUnit unit;

  /// How many items a list holds, and may hold. Null for a plain field.
  final int? items;
  final int? maxItems;

  /// What a list's items are called in the counter: "items", "screenshots".
  final String itemNoun;

  int get left => limit - used;

  bool get over =>
      used > limit || (maxItems != null && (items ?? 0) > maxItems!);

  /// "27/30 · 3 left", "112/100 bytes · 12 over", "3/20 items · longest
  /// 120/200".
  String get label {
    final unitWord = unit == CopyUnit.bytes ? ' bytes' : '';
    if (maxItems case final max?) {
      return '${items ?? 0}/$max $itemNoun · longest $used/$limit$unitWord';
    }
    final tail = used > limit ? '${used - limit} over' : '$left left';
    return '$used/$limit$unitWord · $tail';
  }
}

/// How [text] measures against [spec].
CopyCount countField(CopyFieldSpec spec, String text) {
  if (spec.isList) {
    final items = listItems(text);
    var longest = 0;
    for (final item in items) {
      final n = measureCopy(item, spec.unit);
      if (n > longest) longest = n;
    }
    return CopyCount(
      used: longest,
      limit: spec.limit,
      unit: spec.unit,
      items: items.where((i) => i.isNotEmpty).length,
      maxItems: spec.maxItems,
      itemNoun: spec.perScreenshot ? 'screenshots' : 'items',
    );
  }
  return CopyCount(
    used: measureCopy(text, spec.unit),
    limit: spec.limit,
    unit: spec.unit,
  );
}

/// What a store's console is called, for "App Store Connect takes 30".
String consoleOf(CopyStore store) => switch (store) {
  CopyStore.appStore || CopyStore.macAppStore => 'App Store Connect',
  CopyStore.playStore => 'The Play Console',
  CopyStore.microsoftStore => 'Partner Center',
  CopyStore.galaxyStore => 'The Galaxy Store',
  CopyStore.huaweiAppGallery => 'AppGallery Connect',
  CopyStore.amazonAppstore => 'The Amazon Appstore',
};

String _units(int n, CopyUnit unit) => unit == CopyUnit.bytes
    ? '$n byte${n == 1 ? '' : 's'}'
    : '$n character${n == 1 ? '' : 's'}';

/// Every finding for [store]'s [fields] (field id → text), errors first.
///
/// [appName] is the brief's name, which Apple's keyword field should not
/// repeat any more than it repeats the name field.
List<CopyIssue> lintCopy(
  CopyStore store,
  Map<String, String> fields, {
  String appName = '',
}) {
  final out = <CopyIssue>[
    for (final spec in store.allFields)
      ...lintField(store, spec, fields, appName: appName),
  ];
  out.sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}

/// The findings for one field, read with the rest of [fields] for context
/// (the keyword checks need the name and subtitle).
List<CopyIssue> lintField(
  CopyStore store,
  CopyFieldSpec spec,
  Map<String, String> fields, {
  String appName = '',
}) {
  final text = fields[spec.id] ?? '';
  if (text.trim().isEmpty) return const [];
  return [
    ..._limits(store, spec, text),
    if (store.isApple) ..._apple(store, spec, text, fields, appName),
    if (store == CopyStore.playStore) ..._play(spec, text, appName),
    ..._everywhere(store, spec, text),
  ];
}

// -----------------------------------------------------------------------------
// Limits
// -----------------------------------------------------------------------------

List<CopyIssue> _limits(CopyStore store, CopyFieldSpec spec, String text) {
  final out = <CopyIssue>[];
  final console = consoleOf(store);
  if (spec.isList) {
    final items = listItems(text);
    final filled = items.where((i) => i.isNotEmpty).length;
    final max = spec.maxItems!;
    final what = spec.perScreenshot ? 'screenshots' : 'items';
    if (items.length > max) {
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.error,
          rule: CopyRule.tooManyItems,
          message:
              '$console takes ${spec.label.toLowerCase()} for up to $max '
              '$what; this has ${items.length} lines.',
          fix: 'Remove ${items.length - max} of them.',
          fixed: items.take(max).join('\n'),
          fixLabel: 'Keep the first $max',
        ),
      );
    }
    if (spec.minItems case final min? when filled > 0 && filled < min) {
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.warning,
          rule: CopyRule.tooFewItems,
          message:
              '$console asks for at least $min ${spec.label.toLowerCase()}; '
              'this has $filled.',
          fix: 'Add ${min - filled} more, one per line.',
        ),
      );
    }
    for (final (i, item) in items.indexed) {
      final n = measureCopy(item, spec.unit);
      if (n <= spec.limit) continue;
      final which = spec.perScreenshot
          ? 'Screenshot ${i + 1}'
          : 'Item ${i + 1}';
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.error,
          rule: CopyRule.overLimit,
          message:
              '$which is ${_units(n, spec.unit)}; $console takes '
              '${spec.limit} each.',
          fix: 'Cut ${_units(n - spec.limit, spec.unit)} from it.',
          fixed: [
            for (final (j, other) in items.indexed)
              j == i ? truncateCopy(other, spec.limit, spec.unit) : other,
          ].join('\n'),
          fixLabel: 'Cut at a word',
        ),
      );
    }
    return out;
  }

  final n = measureCopy(text, spec.unit);
  if (n > spec.limit) {
    final over = n - spec.limit;
    if (spec.keywords) {
      final packed = packKeywords(text, spec.limit);
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.error,
          rule: CopyRule.overLimit,
          message:
              '${spec.label} use ${_units(n, spec.unit)}; $console takes '
              '${spec.limit}.',
          fix:
              'Drop the keywords that matter least until it fits — '
              '${_units(over, spec.unit)} to go.',
          fixed: packed,
          fixLabel: 'Drop the last keywords',
        ),
      );
    } else {
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.error,
          rule: CopyRule.overLimit,
          message:
              '${spec.label} is ${_units(n, spec.unit)}; $console takes '
              '${spec.limit}.',
          fix: 'Cut ${_units(over, spec.unit)}.',
          fixed: truncateCopy(text, spec.limit, spec.unit),
          fixLabel: 'Cut at a word',
        ),
      );
    }
  }
  if (spec.min case final min? when n < min) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.error,
        rule: CopyRule.underMin,
        message:
            '$console needs a ${spec.label.toLowerCase()} of at least '
            '${_units(min, spec.unit)}.',
        fix: 'Write a longer ${spec.label.toLowerCase()}.',
      ),
    );
  }
  return out;
}

// -----------------------------------------------------------------------------
// Apple: keywords, 2.3.7 and 2.3.10
// -----------------------------------------------------------------------------

/// Other companies' app and brand names that keyword stuffing reaches for.
/// Only distinctive names: an ordinary word that happens to be a brand
/// ("zoom", "notion", "signal") would warn about honest copy.
const kTrademarkNames = {
  'instagram',
  'facebook',
  'whatsapp',
  'tiktok',
  'snapchat',
  'youtube',
  'netflix',
  'spotify',
  'twitter',
  'pinterest',
  'linkedin',
  'reddit',
  'wechat',
  'uber',
  'lyft',
  'airbnb',
  'tinder',
  'duolingo',
  'canva',
  'figma',
  'photoshop',
  'lightroom',
  'picsart',
  'capcut',
  'chatgpt',
  'openai',
  'evernote',
  'trello',
  'dropbox',
  'gmail',
  'paypal',
  'venmo',
  'cashapp',
  'shopify',
  'ebay',
  'etsy',
  'temu',
  'shein',
  'aliexpress',
  'minecraft',
  'roblox',
  'fortnite',
  'pokemon',
  'google',
  'microsoft',
  'samsung',
  'disney',
  'adobe',
  'amazon',
};

List<CopyIssue> _apple(
  CopyStore store,
  CopyFieldSpec spec,
  String text,
  Map<String, String> fields,
  String appName,
) {
  final out = <CopyIssue>[];
  final indexed = {'name', 'subtitle', 'keywords'}.contains(spec.id);

  if (spec.keywords) {
    out.addAll(_keywords(store, spec, text, fields, appName));
  }

  final platform = findOtherPlatform(text, store);
  if (platform != null) {
    final name = platform.group(0)!;
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.otherPlatform,
        message:
            '“$name” names another platform. Apple rejects metadata that '
            'mentions other mobile platforms or app stores (guideline 2.3.10).',
        fix: spec.keywords
            ? 'Remove “$name” from the keywords.'
            : 'Remove “$name”, or say what the app does instead.',
        fixed: spec.keywords
            ? _tidyKeywords(store, text, fields, appName)
            : scrubOtherPlatforms(text, mac: store == CopyStore.macAppStore),
        fixLabel: spec.keywords ? 'Tidy keywords' : 'Remove it',
      ),
    );
  }

  if (pricePattern.firstMatch(text) case final price?) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.applePrice,
        message:
            '“${price.group(0)!.trim()}” is price information. Apple keeps '
            'prices and discounts out of App Store metadata (guideline 2.3.7) '
            'and shows the price on the listing itself.',
        fix: indexed
            ? 'Remove it from the ${spec.label.toLowerCase()}.'
            : 'Remove the price; the App Store shows it next to Get.',
      ),
    );
  }

  if (freeClaimPattern.firstMatch(text) case final free?) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.appleFree,
        message:
            '“${free.group(0)}” is a price claim. Apple asks for no pricing '
            'words in metadata (guideline 2.3.7), and the listing already says '
            'what the app costs.',
        fix: 'Say what people get instead of “free”.',
        fixed: spec.keywords
            ? _tidyKeywords(store, text, fields, appName)
            : null,
        fixLabel: spec.keywords ? 'Tidy keywords' : null,
      ),
    );
  }

  if (indexed && !spec.keywords) {
    for (final word in wordsOf(text)) {
      if (!kTrademarkNames.contains(word)) continue;
      if (wordsOf(appName).contains(word)) continue;
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.warning,
          rule: CopyRule.trademark,
          message:
              '“$word” is another company’s name. Apple rejects names and '
              'subtitles that borrow other apps’ or brands’ names (guideline '
              '2.3.7).',
          fix: 'Remove “$word”.',
        ),
      );
      break;
    }
  }
  return out;
}

/// Apple's keyword checks: spacing, duplicates, words the name or subtitle
/// already carry, plurals of words already there, other companies' names.
List<CopyIssue> _keywords(
  CopyStore store,
  CopyFieldSpec spec,
  String text,
  Map<String, String> fields,
  String appName,
) {
  final out = <CopyIssue>[];
  final tidy = _tidyKeywords(store, text, fields, appName);
  CopyIssue issue(CopyRule rule, String message, String fix) => CopyIssue(
    field: spec.id,
    level: CopyIssueLevel.warning,
    rule: rule,
    message: message,
    fix: fix,
    fixed: tidy == text ? null : tidy,
    fixLabel: tidy == text ? null : 'Tidy keywords',
  );

  if (RegExp(r'\s[,，、،]|[,，、،]\s|^\s|\s$').hasMatch(text)) {
    out.add(
      issue(
        CopyRule.keywordSpaces,
        'There are spaces around the commas. Apple counts every one against '
            'the 100 bytes.',
        'Remove the spaces after commas.',
      ),
    );
  }

  final terms = keywordTerms(text);
  final seen = <String>{};
  for (final term in terms) {
    final key = term.toLowerCase();
    if (!seen.add(key)) {
      out.add(
        issue(
          CopyRule.keywordDuplicate,
          '“$term” is in the keywords twice.',
          'Keep one “$term”.',
        ),
      );
      break;
    }
  }

  final covered = {
    ...wordsOf(fields['name'] ?? ''),
    ...wordsOf(fields['subtitle'] ?? ''),
    ...wordsOf(appName),
  };
  for (final term in terms) {
    final words = wordsOf(term);
    if (words.isEmpty || !words.every(covered.contains)) continue;
    out.add(
      issue(
        CopyRule.keywordInNameOrSubtitle,
        '“$term” is already in the name or subtitle, and Apple searches those '
            'too.',
        'Remove “$term” and use the bytes for a word you don’t have yet.',
      ),
    );
    break;
  }

  final singulars = {for (final t in terms) t.toLowerCase(), ...covered};
  for (final term in terms) {
    final singular = _singularOf(term.toLowerCase(), singulars);
    if (singular == null) continue;
    out.add(
      issue(
        CopyRule.keywordPlural,
        '“$term” is the plural of “$singular”. Apple matches both forms, so '
            'the plural wastes bytes.',
        'Remove “$term”.',
      ),
    );
    break;
  }

  for (final term in terms) {
    final brand = wordsOf(term).where(kTrademarkNames.contains).firstOrNull;
    if (brand == null || wordsOf(appName).contains(brand)) continue;
    out.add(
      issue(
        CopyRule.trademark,
        '“$term” names another company. Apple rejects keywords that name other '
            'apps or brands (guideline 2.3.7).',
        'Remove “$term”.',
      ),
    );
    break;
  }
  return out;
}

/// The singular form of [word] already present in [known], when [word] is
/// its plural: "trips" → "trip", "boxes" → "box", "stories" → "story".
String? _singularOf(String word, Set<String> known) {
  if (word.length < 4 || !word.endsWith('s') || word.endsWith('ss')) {
    return null;
  }
  final candidates = [
    if (word.endsWith('ies')) '${word.substring(0, word.length - 3)}y',
    if (word.endsWith('es')) word.substring(0, word.length - 2),
    word.substring(0, word.length - 1),
  ];
  for (final c in candidates) {
    if (c != word && known.contains(c)) return c;
  }
  return null;
}

/// The keyword field with every soft problem taken out: spacing, duplicates,
/// words the name and subtitle already carry, plurals of words already there,
/// other companies' and platforms' names, and "free".
String _tidyKeywords(
  CopyStore store,
  String text,
  Map<String, String> fields,
  String appName,
) => tidyAppleKeywords(
  text,
  name: fields['name'] ?? '',
  subtitle: fields['subtitle'] ?? '',
  appName: appName,
  mac: store == CopyStore.macAppStore,
);

/// See [_tidyKeywords]. Public for the drafts, which pass their keywords
/// through it before anyone sees them.
String tidyAppleKeywords(
  String text, {
  String name = '',
  String subtitle = '',
  String appName = '',
  bool mac = false,
}) {
  final covered = {...wordsOf(name), ...wordsOf(subtitle), ...wordsOf(appName)};
  final appWords = wordsOf(appName);
  final store = mac ? CopyStore.macAppStore : CopyStore.appStore;
  final seen = <String>{};
  final kept = <String>[];
  final terms = keywordTerms(text);
  final singulars = {for (final t in terms) t.toLowerCase(), ...covered};
  for (final term in terms) {
    final key = term.toLowerCase();
    final words = wordsOf(term);
    if (seen.contains(key)) continue;
    if (words.isNotEmpty && words.every(covered.contains)) continue;
    if (_singularOf(key, singulars) != null) continue;
    if (words.any(
      (w) => kTrademarkNames.contains(w) && !appWords.contains(w),
    )) {
      continue;
    }
    if (findOtherPlatform(term, store) != null) continue;
    if (freeClaimPattern.hasMatch(term)) continue;
    seen.add(key);
    kept.add(term);
  }
  return kept.join(',');
}

// -----------------------------------------------------------------------------
// Google Play
// -----------------------------------------------------------------------------

final _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
  unicode: true,
);

final _repeatedSymbols = RegExp(r'[!?*#~^$€£]{2,}');

List<CopyIssue> _play(CopyFieldSpec spec, String text, String appName) {
  final out = <CopyIssue>[];
  final headline = spec.id == 'title' || spec.id == 'shortDescription';
  if (!headline) {
    if (spec.id == 'fullDescription' && _mostlyCapitals(text)) {
      out.add(
        CopyIssue(
          field: spec.id,
          level: CopyIssueLevel.warning,
          rule: CopyRule.playAllCaps,
          message:
              'Most of the description is in capitals. Google Play treats '
              'that as spam.',
          fix: 'Write it in sentence case.',
        ),
      );
    }
    return out;
  }
  final where = spec.id == 'title' ? 'the app name' : 'the short description';

  if (playPromoPattern.firstMatch(text) case final m?) {
    final word = m.group(0)!;
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.playBannedWord,
        message:
            '“$word” is a ranking, price or promotional word. Google Play '
            'rejects them in $where.',
        fix: 'Remove “$word”.',
        fixed: removeWord(text, word),
        fixLabel: 'Remove it',
      ),
    );
  }

  if (_emoji.hasMatch(text)) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.playEmoji,
        message: 'Google Play rejects emoji in $where.',
        fix: 'Remove the emoji.',
        fixed: text
            .replaceAll(_emoji, '')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim(),
        fixLabel: 'Remove emoji',
      ),
    );
  }

  if (_repeatedSymbols.firstMatch(text) case final m?) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.playSymbols,
        message:
            '“${m.group(0)}” is repeated punctuation, which Google Play '
            'rejects in $where.',
        fix: 'Use one mark, or none.',
      ),
    );
  }

  final brand = wordsOf(appName);
  for (final m in RegExp(r'\b[A-Z][A-Z0-9]{3,}\b').allMatches(text)) {
    final word = m.group(0)!;
    if (brand.contains(word.toLowerCase())) continue;
    final calm = '${word[0]}${word.substring(1).toLowerCase()}';
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.playAllCaps,
        message:
            '“$word” is in capitals. Google Play rejects $where in all caps '
            'unless it is how your brand is written.',
        fix: 'Write it as “$calm”.',
        fixed: text.replaceAll(word, calm),
        fixLabel: 'Write it as $calm',
      ),
    );
    break;
  }
  return out;
}

bool _mostlyCapitals(String text) {
  var letters = 0;
  var capitals = 0;
  for (final rune in text.runes) {
    final c = String.fromCharCode(rune);
    if (c.toLowerCase() == c.toUpperCase()) continue;
    letters++;
    if (c == c.toUpperCase()) capitals++;
  }
  return letters >= 50 && capitals / letters > 0.5;
}

// -----------------------------------------------------------------------------
// Every store
// -----------------------------------------------------------------------------

final _html = RegExp(r'<\s*/?\s*[a-z][a-z0-9]*[^>]*>', caseSensitive: false);

List<CopyIssue> _everywhere(CopyStore store, CopyFieldSpec spec, String text) {
  final out = <CopyIssue>[];
  if (linkPattern.firstMatch(text) case final m?) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.link,
        message:
            '${store.label} doesn’t take links in listing text '
            '(${m.group(0)}).',
        fix:
            'Remove the link; the console has its own fields for your '
            'website and support page.',
      ),
    );
  }
  if (_html.hasMatch(text)) {
    out.add(
      CopyIssue(
        field: spec.id,
        level: CopyIssueLevel.warning,
        rule: CopyRule.html,
        message:
            '${store.label} shows listing text as plain text, so HTML '
            'tags appear as typed.',
        fix: 'Remove the tags; use line breaks and “• ” for lists.',
        fixed: text.replaceAll(_html, ''),
        fixLabel: 'Remove tags',
      ),
    );
  }
  return out;
}
